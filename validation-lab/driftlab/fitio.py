"""Strict FIT decoding and conservative one-second timeline reconstruction."""
from datetime import timedelta
from collections import defaultdict
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


def extract_repetitions(messages):
    """Collect FIT RECORD developer events by monotonic repetition ID.

    A held event value may appear in many successive RECORD messages.
    Collapse repeats, attach an HRR update to its parent effort, and report
    missing starts or gaps explicitly instead of inventing repetitions.
    """
    reps = []
    by_id = {}
    errors = []
    last_event = None
    provenance = 'unverified'
    from .calibration_schema import PRODUCTION_APP_ID, canonical_app_id
    metadata_present = any(m.get('developer_fields') for m in messages)
    verified = []
    if metadata_present:
        if any(m.get('type') == 'developer_identity_conflict' for m in messages):
            return dict(repetitions=[], issues=['ambiguous developer identity'], provenance='unverified')
        for message in messages:
            fields = {k:v for k,v in message.get('fields', {}).items() if not k.startswith('dg_')}
            seen = set()
            ambiguous = False
            for field in message.get('developer_fields', []):
                if canonical_app_id(field.get('application_id')) == PRODUCTION_APP_ID:
                    if field['name'] in seen:
                        ambiguous = True
                    seen.add(field['name'])
                    fields[field['name']] = field.get('value')
            if ambiguous:
                errors.append('ambiguous duplicate production developer fields')
                continue
            verified.append(dict(type=message.get('type'), fields=fields))
        if any('dg_rep_id' in m['fields'] for m in verified):
            provenance = 'production_application_id'
        elif any('dg_rep_id' in m.get('fields', {}) for m in messages):
            errors.append('repetition fields have unverified application identity; not attributed to DriftGuard')
        messages = verified
    sessions = [m.get('fields', {}) for m in messages if m.get('type') == 'session']
    versions = {m['dg_schema_version'] for m in sessions if 'dg_schema_version' in m}
    schema = next(iter(versions)) if len(versions) == 1 else None
    if versions and (len(versions) != 1 or schema not in (2,3)):
        return dict(repetitions=[], issues=errors+['unsupported repetition schema'], provenance=provenance)
    for message in messages:
        if message.get('type') != 'record':
            continue
        values = message.get('fields', {})
        rep_id = values.get('dg_rep_id')
        event = 1 if schema == 3 else values.get('dg_rep_evt')
        if not isinstance(rep_id, int) or not isinstance(event, int) or rep_id <= 0:
            continue
        marker = (rep_id, event)
        if marker == last_event:
            continue
        last_event = marker
        if event == 1:
            duration = values.get('dg_rep_s')
            power = values.get('dg_rep_w')
            quality = values.get('dg_rep_quality')
            valid = values.get('dg_rep_valid_s')
            if schema in (2,3) and not (isinstance(quality,int) and 0 <= quality <= 15 and
                    isinstance(valid,int) and isinstance(duration,int) and 0 <= valid <= duration and
                    isinstance(values.get('dg_rep_end_s'),int) and
                    (valid == duration or quality & 2)):
                errors.append(f'invalid effort quality: {rep_id}')
                continue
            source = values.get('dg_rep_src')
            if not (isinstance(duration, int) and duration > 0 and
                    (isinstance(power, (int, float)) and 0 <= power <= 10000 or
                     schema in (2,3) and power is None and valid == 0) and source in (1, 2, 3)):
                errors.append(f'invalid effort fields: {rep_id}')
                continue
            if rep_id in by_id:
                errors.append(f'duplicate/wrapped repetition id: {rep_id}')
                continue
            item = dict(id=rep_id, time=values.get('timestamp'), duration_s=duration,
                        power_w=power, schema_version=schema, quality_flags=values.get("dg_rep_quality"),
                        valid_power_s=values.get("dg_rep_valid_s"), end_running_s=values.get("dg_rep_end_s"),
                        recovery_power_w=None, source={1:'AUTO',2:'MANUAL',3:'WORKOUT'}[source],
                        hrr60_bpm=None, active_hrr60_bpm=None)
            reps.append(item)
            by_id[rep_id] = item
        elif event in (2, 3):
            item = by_id.get(rep_id)
            hrr = values.get('dg_rep_hrr' if event == 2 else 'dg_rep_hrr_active')
            if item is None:
                errors.append(f'HRR without effort: {rep_id}')
            elif isinstance(hrr, (int, float)) and -300 <= hrr <= 300:
                item['hrr60_bpm' if event == 2 else 'active_hrr60_bpm'] = hrr
                item['recovery_power_w'] = values.get('dg_rep_recovery_w')
                if event == 3:
                    strict = values.get('dg_rep_hrr')
                    if isinstance(strict, (int, float)) and -300 <= strict <= 300:
                        item['hrr60_bpm'] = strict
            else:
                errors.append(f'invalid HRR: {rep_id}')
        else:
            errors.append(f'unknown repetition event: {event}')
    if schema == 3:
        seen_recovery=set()
        for message in messages:
            if message.get('type')!='record':continue
            values=message.get('fields',{})
            parent=values.get('dg_hrr_parent')
            if not isinstance(parent,int) or parent<=0:continue
            marker=(parent,values.get('dg_rep_hrr'),values.get('dg_rep_hrr_active'))
            if marker in seen_recovery:continue
            seen_recovery.add(marker)
            item=by_id.get(parent)
            if item is None:
                errors.append(f'HRR without effort: {parent}');continue
            for field,key in [('dg_rep_hrr','hrr60_bpm'),('dg_rep_hrr_active','active_hrr60_bpm')]:
                value=values.get(field)
                if isinstance(value,(int,float)) and -300<=value<=300:item[key]=value
            item['recovery_power_w']=values.get('dg_rep_recovery_w')
    ids = [rep['id'] for rep in reps]
    if ids and ids[0] != 1:
        errors.append(f'possible missed initial effort(s): first id {ids[0]}')
    for previous, current in zip(ids, ids[1:]):
        if current != previous + 1 and not (previous == 65534 and current == 1):
            errors.append(f'possible missed effort(s): {previous} -> {current}')
    totals = [m['dg_rep_count'] for m in sessions if isinstance(m.get('dg_rep_count'), int)]
    if totals and max(totals) != len(reps):
        errors.append(f'session reports {max(totals)} efforts; recovered {len(reps)}')
    return dict(repetitions=reps, issues=errors, provenance=provenance,
                availability='present' if reps else 'unavailable')


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
    # Retain raw events in read_fit's messages; this timeline is an explicit proxy.
    # Missing event_group is the legacy implicit group only when no group is given.
    groups = {e.get('event_group') for e in events}
    multiple_groups = len(groups) > 1
    chosen_group = min(groups, key=lambda x: (x is None, str(x))) if groups else None
    if multiple_groups:
        issues.append('multiple timer groups; deterministic single-group proxy only')
    selected = [e for e in events if e.get('event_group') == chosen_group]
    batches = defaultdict(set)
    stops = ('stop','stop_all','stop_disable','stop_disable_all')
    for event in selected:
        kind = event.get('event_type')
        if kind == 'start':
            batches[event['timestamp']].add(True)
        elif kind in stops:
            batches[event['timestamp']].add(False)
        else:
            issues.append('unrecognized timer event')
    conflicts = any(len(values) > 1 for values in batches.values())
    if conflicts:
        issues.append('conflicting simultaneous timer events; stop wins in proxy')
    if not events:
        issues.append('timer events absent; timer assumed running')
    initial_unknown = not any(time <= start for time in batches)
    if initial_unknown:
        issues.append('initial timer state unknown; running assumed until first known event')
    timeline = sorted(batches.items())
    running, ei, samples, missing = True,0,[],0
    t = start
    while t <= end:
        while ei < len(timeline) and timeline[ei][0] <= t:
            # min gives stop precedence; independent of input list ordering.
            running = min(timeline[ei][1])
            ei += 1
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
                        missing_sensor_seconds=missing_sensor,active_seconds=active,wall_seconds=len(samples),
                        timer_ambiguous=initial_unknown or multiple_groups or conflicts,
                        timer_group=chosen_group, timer_policy='single-group; stop wins; unknown prefix assumes running')
