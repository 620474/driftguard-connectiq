import tempfile
import unittest
import struct
from pathlib import Path
from datetime import datetime,timedelta
from driftlab.oracle import Engine,Config,Buckets,halves,label
from driftlab.fitio import normalize,read_fit
from driftlab.archive import sync_import
from driftlab.experiments import compare


def minutes(e,n,p,h):
    for _ in range(n*60): e.add(p,h)


def crc(data):
    value=0
    for b in data:
        value^=b
        for _ in range(8): value=(value>>1)^0xA001 if value&1 else value>>1
    return value


def fixture():
    # FIT definition: record 20, timestamp uint32, power uint16, HR uint8.
    body=bytes([0x40,0,0,20,0,3,253,4,0x86,7,2,0x84,3,1,2])
    for i in range(120): body+=bytes([0])+struct.pack('<IHB',1162224000+i,200,100)
    header=struct.pack('<BBHI4s',12,0x20,2100,len(body),b'.FIT')
    data=header+body
    return data+struct.pack('<H',crc(data))


class LabTests(unittest.TestCase):
    def test_monkey_reference_warmup(self):
        e=Engine();minutes(e,14,200,100);self.assertEqual(e.result['ride']['state'],'WARMUP')
        minutes(e,1,200,100);self.assertEqual(e.result['ride']['state'],'COLLECTING');self.assertEqual(e.steady_seconds,0)
    def test_monkey_reference_ten_percent(self):
        e=Engine(Config(warmup=0));minutes(e,20,180,90);minutes(e,20,180,100)
        self.assertEqual(e.result['ride']['state'],'VALID');self.assertAlmostEqual(e.result['ride']['drift'],10)
    def test_last_hour(self):
        e=Engine(Config(warmup=0));minutes(e,20,180,90);minutes(e,20,180,100);minutes(e,40,180,105)
        self.assertAlmostEqual(e.result['ride']['drift'],9.5238095)
        self.assertAlmostEqual(e.result['last60']['drift'],3.17460317)
    def test_recovery(self):
        e=Engine(Config(warmup=0));minutes(e,20,200,100);minutes(e,5,320,150);minutes(e,3,200,130);minutes(e,20,200,100)
        self.assertEqual(e.steady_seconds,2400);self.assertAlmostEqual(e.result['ride']['drift'],0)
    def test_pause(self):
        e=Engine(Config(warmup=0))
        for _ in range(500):e.add(200,100,False)
        self.assertEqual(e.pending,[])
    def test_valid_boundary(self):
        for n in (47,48):
            e=Engine(Config(warmup=0))
            for i in range(60):e.add(200 if i<n else None,100)
            self.assertEqual(e.minutes[0]['steady'],n==48)
    def test_power_gate(self):
        for p,expected in ((180,'POWER_CHANGED'),(192,'VALID')):
            e=Engine(Config(warmup=0));minutes(e,20,200,100);minutes(e,20,p,100)
            self.assertEqual(e.result['ride']['state'],expected)
    def test_histogram(self):
        e=Engine();self.assertEqual(e.median([200,210]),205);self.assertEqual(e.median([1700]),1495)
    def test_compression(self):
        b=Buckets(4)
        for i in range(16):b.add((12000 if i<8 else 10800,6000,60))
        self.assertEqual(b.width,4);self.assertEqual(len(b.records),4);self.assertAlmostEqual(halves(b.records)[0],10)
    def test_compression_preserves_sums_but_not_arbitrary_split(self):
        rows=[(12000,6000,60)]*3+[(12000,12000,60)]*2
        b=Buckets(4)
        for row in rows:b.add(row)
        self.assertEqual(tuple(map(sum,zip(*rows))),tuple(map(sum,zip(*b.records))))
        self.assertAlmostEqual(halves(rows)[0],44.4444444444)
        self.assertAlmostEqual(halves(b.records)[0],35.2941176471)
    def test_long_ride(self):
        e=Engine(Config(warmup=0));minutes(e,600,200,100)
        self.assertLessEqual(len(e.ride.records),240);self.assertAlmostEqual(e.result['ride']['drift'],0)
    def test_labels(self):
        self.assertEqual(label(5.2,1),1);self.assertEqual(label(5.6,1),2);self.assertEqual(label(-3.6,1),0)
    def test_timestamp_missing_pause(self):
        t=datetime(2026,10,1)
        records=[dict(timestamp=t,power=0,heart_rate=100),dict(timestamp=t+timedelta(seconds=3),power=200,heart_rate=100)]
        rows,q=normalize(records,[dict(timestamp=t,event_type='start'),dict(timestamp=t+timedelta(seconds=1),event_type='stop'),dict(timestamp=t+timedelta(seconds=3),event_type='start')])
        self.assertEqual(len(rows),4);self.assertFalse(rows[1]['running']);self.assertIsNone(rows[1]['power']);self.assertEqual(rows[0]['power'],0)
    def test_smart_recording(self):
        t=datetime(2026,10,1);r,q=normalize([dict(timestamp=t),dict(timestamp=t+timedelta(seconds=90))],[])
        self.assertEqual(q['missing_seconds'],89);self.assertEqual(q['status'],'insufficient')
    def test_fit_and_corrupt(self):
        with tempfile.TemporaryDirectory() as d:
            p=Path(d)/'test.fit';p.write_bytes(fixture());r,q,m=read_fit(p)
            self.assertEqual(len(r),120);self.assertEqual(r[0]['power'],200)
            p.write_bytes(b'bad')
            with self.assertRaises(Exception):read_fit(p)
    def test_incremental(self):
        with tempfile.TemporaryDirectory() as d:
            source=Path(d)/'in';source.mkdir();(source/'test.FIT').write_bytes(fixture());target=Path(d)/'archive'
            self.assertEqual(sync_import(source,target),1);self.assertEqual(sync_import(source,target),0)
    def test_reproducible(self):
        rows=[dict(power=200,hr=100,running=True)]*120
        self.assertEqual(compare(rows,True),compare(rows,True))


if __name__=='__main__':unittest.main()
