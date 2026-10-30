import unittest
from datetime import datetime, timedelta
from driftlab.calibration import compare, FIELDS
from driftlab.calibration_config import ALGO_VERSION, CONFIG_CRC


def fixture(n=120, pause=False):
    samples=[]
    start=datetime(2026,10,30)
    for i in range(n):
        samples.append(dict(timestamp=(start+timedelta(seconds=i)).isoformat(), power=200, hr=100,
                            running=not (pause and 30 <= i < 40)))
    messages=[dict(type='session',fields=dict(dg_algo_version=ALGO_VERSION,dg_config_crc=CONFIG_CRC))]
    active=[s for s in samples if s['running']]
    for i in range(len(active)//60):
        values=(60*(i+1),60,0,12000,6000,60,12000,6000,0,0)
        row=dict(zip(FIELDS,values),dg_minute_seq=i+1,timestamp=active[(i+1)*60-1]['timestamp'])
        messages.append(dict(type='record',fields=row))
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
        import struct, tempfile
        from pathlib import Path
        from test_lab import crc
        from driftlab.fitio import read_fit
        # Real FIT field_description messages plus developer fields in records/session.
        definitions=[('dg_minute_seq',4,2),('dg_sample_seq',6,4),('dg_valid_seconds',2,1),
          ('dg_reject_reason',2,1),('dg_min_power_sum',6,4),('dg_min_hr_sum',4,2),
          ('dg_compat_seconds',2,1),('dg_compat_power_sum',6,4),('dg_compat_hr_sum',4,2),
          ('dg_steady',2,1),('dg_ride_state',2,1),('dg_algo_version',4,2),('dg_config_crc',6,4)]
        body=bytes([0x40,0,0,207,0,1,3,1,2,0,0])
        for i,(name,base,size) in enumerate(definitions):
            name=name.encode()+b'\0'
            body+=bytes([0x40,0,0,206,0,4,0,1,2,1,1,2,2,1,2,3,len(name),7])
            body+=bytes([0,0,i,base | 0x80 if base in (4,6) else base])+name
        # Record local definition 1 with eleven developer fields.
        body+=bytes([0x61,0,0,20,0,3,253,4,0x86,7,2,0x84,3,1,2,11])
        for i,(_,_,size) in enumerate(definitions[:11]):body+=bytes([i,size,0])
        for second in range(120):
            complete=(second+1)//60
            values=[complete,complete*60,60 if complete else 0,0,12000 if complete else 0,6000 if complete else 0,
                    60 if complete else 0,12000 if complete else 0,6000 if complete else 0,0,0]
            body+=bytes([1])+struct.pack('<IHB',1162224000+second,200,100)
            for value,(_,_,size) in zip(values,definitions):body+=value.to_bytes(size,'little')
        body+=bytes([0x62,0,0,18,0,0,2,11,2,0,12,4,0])
        body+=bytes([2])+struct.pack('<HI',ALGO_VERSION,CONFIG_CRC)
        data=struct.pack('<BBHI4s',12,0x20,2100,len(body),b'.FIT')+body
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'calibration.fit';p.write_bytes(data+struct.pack('<H',crc(data)))
            samples,quality,messages=read_fit(p)
            self.assertEqual(messages[-1]['fields']['dg_config_crc'],CONFIG_CRC)
            self.assertEqual(compare(samples,messages,quality)['status'],'matched_candidate')



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
