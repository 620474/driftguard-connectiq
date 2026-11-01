import unittest
from datetime import datetime, timedelta
from driftlab.calibration import compare as compare_decoded, FIELDS
from driftlab.calibration_schema import SCHEMA, CALIBRATION_APP_ID
from driftlab.calibration_config import ALGO_VERSION, CONFIG_CRC


def compare(samples, messages, quality=None):
    # Explicit trusted metadata for unit-level clock/math fixtures.
    # Binary decoder/provenance tests below call compare_decoded directly.
    for message in messages:
        if 'developer_fields' not in message:
            kind = message['type']
            message['developer_fields'] = []
            for name, value in message['fields'].items():
                if name in SCHEMA:
                    _, number, base, size = SCHEMA[name]
                    message['developer_fields'].append(dict(name=name, value=value,
                        application_id=CALIBRATION_APP_ID, developer_data_index=0,
                        field_definition_number=number, base_type=base, size=size))
        else:
            for field in message['developer_fields']:
                field['value'] = message['fields'].get(field['name'])
    return compare_decoded(samples, messages, quality)


def fixture(n=120, pause=False):
    samples=[]
    start=datetime(2026,10,30)
    for i in range(n):
        samples.append(dict(timestamp=(start+timedelta(seconds=i)).isoformat(), power=200, hr=100,
                            running=not (pause and 30 <= i < 40)))
    messages=[dict(type='session',fields=dict(dg_algo_version=ALGO_VERSION,dg_config_crc=CONFIG_CRC,
        dg_ride_drift_final=None,dg_ride_state_final=0,dg_steady_percent=0,
        dg_power_change=None,dg_compat_drift=0.,dg_bucket_width=1,dg_compat_width=1))]
    active=[s for s in samples if s['running']]
    for i in range(len(active)//60):
        values=(60*(i+1),60,0,12000,6000,60,12000,6000,0,0)
        row=dict(zip(FIELDS,values),dg_ef=2.,dg_ride_drift=None,dg_cadence=90,dg_minute_seq=i+1,timestamp=active[(i+1)*60-1]['timestamp'])
        messages.append(dict(type='record',fields=row))
    for kind in ('record', 'session'):
        definitions=[]
        for name,(message_type,number,base,size) in SCHEMA.items():
            if message_type==kind:
                definitions.append(dict(name=name,application_id=CALIBRATION_APP_ID,
                    developer_data_index=0,field_definition_number=number,base_type=base,size=size))
        messages.append(dict(type='developer_schema',message_type=kind,fields={},developer_fields=definitions))
    return samples,messages


class CalibrationTests(unittest.TestCase):
    def test_exact_boundaries(self):
        for n in (59,60,61,119,120,121):
            s,m=fixture(n)
            r=compare(s,m)
            self.assertEqual(r['partial_samples'],n%60)
            self.assertEqual(r['status'],'matched_candidate' if n>=60 else 'incomplete')
    def test_pause_inside_minute(self):
        s,m=fixture(130,True)
        self.assertEqual(compare(s,m)['status'],'matched_candidate')
    def test_identical_adjacent_minutes_and_repeated_records(self):
        s,m=fixture();m.insert(2,m[1])
        self.assertEqual(compare(s,m)['compared_minutes'],2)
        self.assertEqual(compare(s,m)['status'],'matched_candidate')
    def test_post_warmup_pause_is_seen_by_comparator(self):
        samples,messages=fixture(21*60+10)
        for i,sample in enumerate(samples):
            sample['running']=not 930 <= i < 940
        active=[s for s in samples if s['running']]
        messages=[m for m in messages if m['type']!='record']
        session=messages[0]['fields']
        session.update(dg_ride_state_final=1,dg_steady_percent=33)
        for minute in range(1,22):
            reason=0 if minute<=15 else 2 if minute==16 else 3 if minute<=19 else 4
            values=(minute*60,60,reason,12000,6000,60,12000,6000,int(reason==4),0 if minute<15 else 1)
            messages.append(dict(type='record',fields=dict(zip(FIELDS,values),
                dg_ef=2.,dg_ride_drift=None,dg_cadence=90,dg_minute_seq=minute,
                timestamp=active[minute*60-1]['timestamp'])))
        self.assertEqual(compare(samples,messages)['status'],'matched_candidate')

    def test_wrong_boundary(self):
        s,m=fixture();m[1]['fields']['timestamp']=s[60]['timestamp']
        self.assertEqual(compare(s,m)['status'],'mismatch')
    def test_missing_conflicting_and_unknown_config(self):
        s,m=fixture();self.assertEqual(compare(s,m[:1]+m[2:])['status'],'incomplete')
        s,m=fixture();m.append(dict(type='record',fields={**m[2]['fields'],'dg_valid_seconds':48}))
        self.assertEqual(compare(s,m)['status'],'incomplete')
        m[0]['fields']['dg_config_crc']=0
        self.assertEqual(compare(s,m)['status'],'unsupported')
    def test_exact_integer_mismatch(self):
        s,m=fixture();m[1]['fields']['dg_min_power_sum']+=1
        self.assertEqual(compare(s,m)['status'],'mismatch')
    def test_missing_sensors_and_zero_power(self):
        s,m=fixture(60)
        for row in s[:12]:row['power']=0
        m[1]['fields'].update(dg_valid_seconds=48,dg_min_power_sum=9600,dg_min_hr_sum=4800,dg_compat_power_sum=9600)
        self.assertEqual(compare(s,m)['status'],'matched_candidate')

class DiagnosticFitTests(unittest.TestCase):
    def test_fit_developer_fields_decode_and_compare(self):
        from fit_fixtures import decode_fixture
        samples,quality,messages=decode_fixture()
        self.assertEqual(compare_decoded(samples,messages,quality)['status'],'matched_candidate')


class ContractTests(unittest.TestCase):
    def test_crc_and_source_thresholds(self):
        import zlib
        from pathlib import Path
        from driftlab.calibration_config import CONFIG
        self.assertEqual(zlib.crc32(CONFIG.encode()), CONFIG_CRC)
        source=(Path(__file__).resolve().parents[2]/'garmin-app/source/DriftEngine.mc').read_text()
        for declaration in ('DEFAULT_WARMUP_MINUTES = 15', 'MIN_STEADY_VALID_SECONDS = 48',
            'STEADY_BAND_PERCENT = 20', 'RECOVERY_MINUTES = 3', 'MAX_POWER_CHANGE_PERCENT = 5.0f',
            'RIDE_MIN_STEADY_MINUTES = 40', 'RIDE_MIN_STEADY_PERCENT = 70',
            'LAST_WINDOW_MINUTES = 60', 'LAST_MIN_STEADY_MINUTES = 48', 'RIDE_BUCKETS = 240',
            'HISTOGRAM_BIN_WATTS = 10', 'HISTOGRAM_BINS = 150'):
            self.assertIn(declaration,source)
    def test_power_and_compression_boundaries(self):
        from driftlab.oracle import Engine,Config
        # Python double yields 5.000000000000004 at the exact 5% boundary.
        # Monkey C Float can fall on the other side; preserve and document this.
        for power,state in ((209,'VALID'),(210,'POWER_CHANGED'),(211,'POWER_CHANGED')):
            e=Engine(Config(warmup=0))
            for p in [200]*1200+[power]*1200:e.add(p,100)
            self.assertEqual(e.result['ride']['state'],state)
        e=Engine(Config(warmup=0))
        for minute in range(1,962):
            for _ in range(60):e.add(200,100)
            if minute in (240,241,481,961):
                self.assertEqual(e.ride.width,{240:1,241:2,481:4,961:8}[minute])
