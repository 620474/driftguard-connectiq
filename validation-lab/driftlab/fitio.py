"""Strict FIT decoding and conservative one-second timeline reconstruction."""
from datetime import timedelta
from pathlib import Path
import fitdecode


def read_fit(path):
    messages, records, events = [], [], []
    applications = {}

    def metadata(definition):
        return dict(name=definition.name, developer_data_index=definition.dev_data_index,
                    application_id=applications.get(definition.dev_data_index),
                    field_definition_number=definition.def_num,
                    base_type=definition.base_type.identifier, size=definition.size)

    with fitdecode.FitReader(str(path), check_crc=fitdecode.CrcCheck.RAISE) as reader:
        for frame in reader:
            if isinstance(frame, fitdecode.FitDefinitionMessage):
                if frame.dev_field_defs:
                    messages.append(dict(type='developer_schema', fields={}, message_type=frame.name,
                                         developer_fields=[metadata(d) for d in frame.dev_field_defs]))
                continue
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            # Keep native fields separate: same-name developers must not overwrite them.
            data = {f.name: f.value for f in frame.fields
                    if f.field_def is None or not f.field_def.is_dev}
            if frame.name == 'developer_data_id':
                index = frame.get_raw_value('developer_data_index', fallback=None)
                raw = frame.get_raw_value('application_id', fallback=None)
                try:
                    app = bytes(raw).hex() if raw is not None and len(raw) == 16 else None
                except (TypeError, ValueError):
                    app = None
                if index in applications and applications[index] != app:
                    messages.append(dict(type='developer_identity_conflict', fields={'index': index}))
                applications[index] = app
            developers = [dict(metadata(f.field_def), value=f.value) for f in frame.fields
                          if f.field_def is not None and f.field_def.is_dev]
            # Legacy consumers may use unambiguous names, while calibration uses metadata only.
            names = [f['name'] for f in developers]
            for field in developers:
                if names.count(field['name']) == 1 and field['name'] not in data:
                    data[field['name']] = field['value']
            messages.append(dict(type=frame.name, fields=data, developer_fields=developers))
            if frame.name == 'record':
                records.append(data)
            elif frame.name == 'event' and data.get('event') == 'timer':
                events.append(data)
    samples, quality = normalize(records, events)
    sessions = [m['fields'] for m in messages if m['type']=='session']
    sports = {s.get('sport') for s in sessions}
    if sports and sports != {'cycling'}:
        quality['status'] = 'unsupported'
        quality['issues'].append('non-cycling or multisport sessions')
    return samples, quality, messages


def normalize(records, events):
    issues = []
    stamped = [r for r in records if r.get('timestamp') is not None]
    if len(stamped) != len(records):
        issues.append('records without timestamp')
    times = [r['timestamp'] for r in stamped]
    if times != sorted(times):
        issues.append('nonmonotonic timestamps')
    if len(times) != len(set(times)):
        issues.append('duplicate timestamps; first retained')
    bytime = {}
    for r in stamped:
        bytime.setdefault(r['timestamp'],r)
    events = sorted([e for e in events if e.get('timestamp')],key=lambda e:e['timestamp'])
    if not bytime:
        return [],dict(status='insufficient',issues=issues+['no record timestamps'])
    start, end = min(bytime),max(bytime)
    if (end-start).total_seconds()>7*86400:
        raise ValueError('timeline exceeds seven days; refusing expansion')
    if not events:
        issues.append('timer events absent; timer assumed running')
    running, ei, samples, missing = True,0,[],0
    t = start
    while t <= end:
        while ei<len(events) and events[ei]['timestamp']<=t:
            kind=events[ei].get('event_type')
            if kind=='start':
                running=True
            elif kind in ('stop','stop_all','stop_disable','stop_disable_all'):
                running=False
            else:
                issues.append('unrecognized timer event')
            ei+=1
        r=bytime.get(t,{})
        if not r and running:
            missing+=1
        samples.append(dict(timestamp=t.isoformat(),power=r.get('power'),hr=r.get('heart_rate'),
                            cadence=r.get('cadence'),speed=r.get('enhanced_speed',r.get('speed')),running=running))
        t+=timedelta(seconds=1)
    if missing:
        issues.append('missing seconds inserted with null sensors; no interpolation')
    missing_sensor=sum(s['running'] and (s['power'] is None or s['hr'] is None) for s in samples)
    active=sum(s['running'] for s in samples)
    status='approximate' if issues else 'comparison_candidate'
    if active<60 or missing_sensor/max(1,active)>.2:
        status='insufficient'
    # Even 1 Hz FIT cannot prove equality to compute() calls; candidate != exact.
    return samples,dict(status=status,issues=sorted(set(issues)),missing_seconds=missing,
                        missing_sensor_seconds=missing_sensor,active_seconds=active,wall_seconds=len(samples))
