"""Calibration v1 wire schema and conservative source/completeness checks."""
from uuid import UUID
from math import isfinite

CALIBRATION_APP_ID = 'db66c379db704260b7199dfc467e407a'
PRODUCTION_APP_ID = '9d014b18b5954a729a66bc80df4ccad5'
# name: (message, field ID, FIT base type, scalar byte size)
SCHEMA = {
    'dg_ef': ('record', 0, 0x88, 4),
    'dg_steady': ('record', 1, 2, 1),
    'dg_ride_drift': ('record', 2, 0x88, 4),
    'dg_ride_state': ('record', 3, 2, 1),
    'dg_cadence': ('record', 4, 2, 1),
    'dg_ride_drift_final': ('session', 5, 0x88, 4),
    'dg_ride_state_final': ('session', 6, 2, 1),
    'dg_steady_percent': ('session', 7, 2, 1),
    'dg_power_change': ('session', 8, 0x88, 4),
    'dg_compat_drift': ('session', 9, 0x88, 4),
    'dg_minute_seq': ('record', 10, 0x84, 2),
    'dg_sample_seq': ('record', 11, 0x86, 4),
    'dg_valid_seconds': ('record', 12, 2, 1),
    'dg_reject_reason': ('record', 13, 2, 1),
    'dg_min_power_sum': ('record', 14, 0x86, 4),
    'dg_min_hr_sum': ('record', 15, 0x84, 2),
    'dg_compat_seconds': ('record', 16, 2, 1),
    'dg_compat_power_sum': ('record', 17, 0x86, 4),
    'dg_compat_hr_sum': ('record', 18, 0x84, 2),
    'dg_algo_version': ('session', 19, 0x84, 2),
    'dg_config_crc': ('session', 20, 0x86, 4),
    'dg_bucket_width': ('session', 21, 0x84, 2),
    'dg_compat_width': ('session', 22, 0x84, 2),
}


def canonical_app_id(raw):
    """Accept exact GUID bytes or .NET GUID little-endian layout, never name heuristics."""
    try:
        value = bytes.fromhex(raw)
        if len(value) != 16:
            return None
        direct, little = UUID(bytes=value).hex, UUID(bytes_le=value).hex
    except (ValueError, TypeError, AttributeError):
        return None
    for expected in (CALIBRATION_APP_ID, PRODUCTION_APP_ID):
        if expected in (direct, little):
            return expected
    return direct


def validate_messages(messages):
    """Return metadata-selected messages, or (status, issues) before numeric comparison."""
    seen, producers, clean, incomplete = set(), set(), [], []
    for message in messages:
        if message['type'] == 'developer_identity_conflict':
            return None, 'unsupported', ['developer_data_index identity redefined']
        kind = message.get('message_type', message['type'])
        fields = {k: v for k, v in message['fields'].items() if not k.startswith('dg_')}
        local_names = set()
        for field in message.get('developer_fields', []):
            name = field['name']
            if not name.startswith('dg_'):
                continue
            app = canonical_app_id(field.get('application_id'))
            if app != CALIBRATION_APP_ID:
                return None, 'unsupported', [f'untrusted/unknown dg_* producer: {app}']
            index = field.get('developer_data_index')
            if type(index) is not int or not 0 <= index <= 254:
                return None, 'unsupported', ['invalid developer_data_index']
            producers.add((app, index))
            if len(producers) > 1 or name in local_names:
                return None, 'unsupported', ['ambiguous dg_* producer or duplicate field']
            local_names.add(name)
            actual = (kind, field.get('field_definition_number'), field.get('base_type'), field.get('size'))
            if name not in SCHEMA or actual != SCHEMA[name]:
                return None, 'unsupported', [f'wrong v1 definition: {name} {actual}']
            seen.add(name)
            if message['type'] != 'developer_schema':
                fields[name] = field.get('value')
        if kind in ('record', 'session') and message['type'] != 'developer_schema':
            required = {name for name, spec in SCHEMA.items() if spec[0] == kind}
            missing = required - fields.keys()
            if missing:
                incomplete.append(f'{kind} missing fields: {sorted(missing)}')
            # Nullable floats may legitimately remain unset outside their valid state.
            if kind == 'session' or fields.get('dg_minute_seq', 0):
                for name in required & fields.keys():
                    value = fields[name]
                    if SCHEMA[name][2] != 0x88:
                        if type(value) is not int:
                            incomplete.append(f'{kind} missing scalar value: {name}')
                    elif value is not None and (type(value) not in (int, float) or not isfinite(value)):
                        incomplete.append(f'{kind} invalid float value: {name}')
                if kind == 'record':
                    if fields.get('dg_ef') is None:
                        incomplete.append('record missing scalar value: dg_ef')
                    if fields.get('dg_ride_state') == 4 and fields.get('dg_ride_drift') is None:
                        incomplete.append('record missing VALID drift')
            clean.append(dict(type=kind, fields=fields))
    if not producers:
        return None, 'unsupported', ['calibration producer metadata absent']
    if set(SCHEMA) - seen:
        incomplete.append(f'missing v1 definitions: {sorted(set(SCHEMA) - seen)}')
    if incomplete:
        return None, 'incomplete', sorted(set(incomplete))
    return clean, None, []
