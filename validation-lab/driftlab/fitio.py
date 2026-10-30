"""Strict FIT decoding and conservative one-second timeline reconstruction."""
from datetime import timedelta
from pathlib import Path
import fitdecode


def read_fit(path):
    messages, records, events = [], [], []
    with fitdecode.FitReader(str(path), check_crc=fitdecode.CrcCheck.RAISE) as reader:
        for frame in reader:
            if not isinstance(frame, fitdecode.FitDataMessage):
                continue
            data = {f.name: f.value for f in frame.fields}
            messages.append(dict(type=frame.name,fields=data))
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
