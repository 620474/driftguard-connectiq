"""Compare completed device minutes against the source-faithful oracle; never fit offsets."""
import argparse
import json
from .calibration_config import ALGO_VERSION, CONFIG_CRC
from .fitio import read_fit
from .oracle import Engine
from .calibration_schema import validate_messages

REASONS = {'warm-up': 0, 'insufficient valid seconds': 1, 'power out of band': 2,
           'recovery after unstable minute': 3, 'steady': 4}
STATES = {'WARMUP': 0, 'COLLECTING': 1, 'NOT_STEADY': 2, 'POWER_CHANGED': 3, 'VALID': 4}
FIELDS = ('dg_sample_seq', 'dg_valid_seconds', 'dg_reject_reason', 'dg_min_power_sum',
          'dg_min_hr_sum', 'dg_compat_seconds', 'dg_compat_power_sum', 'dg_compat_hr_sum',
          'dg_steady', 'dg_ride_state')


def compare(samples, messages, quality=None):
    messages, status, issues = validate_messages(messages)
    if status:
        return dict(status=status, issues=issues)

    sessions = [m['fields'] for m in messages if m['type'] == 'session']
    if len(sessions) != 1 or sessions[0].get('dg_algo_version') != ALGO_VERSION or sessions[0].get('dg_config_crc') != CONFIG_CRC:
        return dict(status='unsupported', issues=['missing/unsupported version or config, or multiple sessions'])
    expected, engine, pending = {}, Engine(), []
    for s in samples:
        if not s['running']:
            continue
        pending.append(s)
        engine.add(s['power'], s['hr'])
        if len(pending) == 60:
            m = engine.minutes[-1]
            compat = [s for s in pending if s['hr'] is not None and s['hr'] > 0]
            expected[m['minute']] = dict(zip(FIELDS, (
                m['minute'] * 60, m['valid_seconds'], REASONS[m['reason']], m['power_sum'], m['hr_sum'],
                len(compat), sum(max(0, s['power'] or 0) for s in compat), sum(s['hr'] for s in compat),
                int(m['steady']), STATES[m['ride_state']]
            )), timestamp=s['timestamp'], drift=m['ride_drift'])
            pending = []
    observed, issues, differences = {}, [], []
    last = 0
    for msg in messages:
        if msg['type'] != 'record':
            continue
        row = msg['fields']
        seq = row.get('dg_minute_seq')
        if seq is None or seq == 0:
            continue
        if not isinstance(seq, int) or seq < 1 or seq >= 65535:
            issues.append('invalid minute sequence')
            continue
        snapshot = {k: row.get(k) for k in FIELDS}
        if seq in observed:
            if snapshot != observed[seq]:
                issues.append(f'conflicting snapshot for minute {seq}')
            if seq != last:
                issues.append(f'nonmonotonic sequence {seq}')
            continue
        if seq != last + 1:
            issues.append(f'missing sequence before {seq}')
        last = seq
        observed[seq] = snapshot
        target = expected.get(seq)
        if target is None:
            issues.append(f'no oracle minute {seq}')
            continue
        for key in FIELDS:
            if snapshot[key] != target[key]:
                differences.append(dict(minute=seq, field=key, device=snapshot[key], oracle=target[key]))
        timestamp = row.get('timestamp')
        if hasattr(timestamp, 'isoformat'):
            timestamp = timestamp.isoformat()
        if timestamp != target['timestamp']:
            differences.append(dict(minute=seq, field='boundary_timestamp', device=timestamp, oracle=target['timestamp']))
        # Retained drift is meaningful only in VALID; integer/state checks stay exact.
        if target['drift'] is not None and snapshot['dg_ride_state'] == 4:
            value = row.get('dg_ride_drift')
            if value is None:
                issues.append(f'missing VALID record drift: {seq}')
                continue
            if not isinstance(value, (int, float)) or not abs(value - target['drift']) <= .001:
                differences.append(dict(minute=seq, field='dg_ride_drift', device=value, oracle=target['drift']))
    session = sessions[0]
    final = engine.result
    integer_session = {'dg_ride_state_final': STATES[final['ride']['state']],
                       'dg_steady_percent': int(final['coverage']),
                       'dg_bucket_width': engine.ride.width, 'dg_compat_width': engine.compat.width}
    float_session = {'dg_compat_drift': final['compat'],
                     'dg_power_change': final['ride']['power_change'],
                     'dg_ride_drift_final': final['ride']['drift']}
    for key, value in integer_session.items():
        if key in session and session[key] != value:
            differences.append(dict(field=key, device=session[key], oracle=value))
    for key, value in float_session.items():
        if value is not None:
            device = session.get(key)
            if device is None:
                issues.append(f'missing meaningful session value: {key}')
                continue
            if not isinstance(device, (int, float)) or not abs(device-value) <= .001:
                differences.append(dict(field=key, device=device, oracle=value))
    missing = sorted(set(expected) - set(observed))
    if missing:
        issues.append(f'missing completed minutes: {missing}')
    if not observed:
        issues.append('no diagnostic snapshots')
    return dict(status='incomplete' if issues else 'mismatch' if differences else 'matched_candidate',
                compared_minutes=len(observed), oracle_minutes=len(expected), partial_samples=len(pending),
                issues=issues, differences=differences, quality=quality,
                limitation='FIT samples cannot prove identity to live compute callbacks; no offsets fitted')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('fit')
    args = parser.parse_args()
    samples, quality, messages = read_fit(args.fit)
    report = compare(samples, messages, quality)
    print(json.dumps(report, indent=2, default=str, allow_nan=False))
    return 0 if report['status'] == 'matched_candidate' else 1


if __name__ == '__main__':
    raise SystemExit(main())
