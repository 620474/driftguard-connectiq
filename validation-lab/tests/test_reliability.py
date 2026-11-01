import json
import os
import re
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from driftlab.auto_exp import ExperimentalDetector
from driftlab.oracle import Engine, Config
from driftlab.heart_recovery import HeartRecovery
from driftlab.fitio import extract_repetitions
from driftlab.calibration_schema import PRODUCTION_APP_ID

ROOT = Path(__file__).resolve().parents[2]


class ReliabilityTests(unittest.TestCase):
    def test_variable_minute_rejected(self):
        e = Engine(Config(warmup=0))
        for i in range(3600):
            e.add(100 if i%2 else 300,140)
        self.assertEqual(e.steady_seconds,0)
        self.assertEqual(e.result['last60']['state'],'NOT_STEADY')
        self.assertEqual(e.minutes[0]['reason'],'variable power')

    def test_resume_and_sensor_limits(self):
        e = Engine(Config(warmup=0))
        for _ in range(30): e.add(200,140)
        e.add(200,140,False)
        for _ in range(210): e.add(200,140)
        self.assertEqual(e.steady_seconds,0)
        for _ in range(60): e.add(200,140)
        self.assertEqual(e.steady_seconds,60)
        bad=Engine(Config(warmup=0))
        for _ in range(60): bad.add(200,400)
        self.assertEqual(bad.minutes[0]['valid_seconds'],0)
        self.assertIsNone(bad.result['compat'])

    def detector(self, duration):
        e = ExperimentalDetector()
        for p in [100]*60+[300]*duration+[100]*5: e.sample(p,True)
        return e

    def test_duration_boundaries_and_sustained(self):
        for n in (20,239,240,241,600):
            e=self.detector(n)
            self.assertEqual(len(e.events),1)
            self.assertEqual((e.events[0]['duration'],e.events[0]['power']),(n,300))
            self.assertEqual(e.events[0]['sustained'],n>=240)
        self.assertEqual(self.detector(19).events,[])

    def test_low_baseline_tail(self):
        e=ExperimentalDetector()
        for p in [40]*60+[210]*4+[90]*40: e.sample(p,True)
        self.assertEqual(e.events,[])
        self.assertFalse(e.active)

    def test_local_split_and_partial(self):
        e=ExperimentalDetector()
        for p in [100]*60+[200]*180+[280]*60+[200]*5: e.sample(p,True)
        self.assertEqual([(x['duration'],x['power']) for x in e.events],[(180,200),(60,280)])
        e=self.detector(20)
        for p in [100]*60+[300]*30: e.sample(p,True)
        e.sample(None,True)
        self.assertTrue(e.events[-1]['partial'])
        self.assertEqual(e.events[-1]['valid_power_s'],30)

    def test_active_hrr_context(self):
        r=HeartRecovery()
        for _ in range(3): r.sample(160,300)
        r.begin(0,300,60);r.parent_id=7
        for _ in range(60): r.sample(140,200)
        self.assertIsNone(r.delta)
        self.assertEqual(r.active_delta,20)
        self.assertEqual(r.mean_recovery_power,200)
        r.cancel('NEW EFFORT')
        self.assertEqual(r.parent_id,0)

    def messages(self, app=PRODUCTION_APP_ID):
        def msg(kind, fields):
            return dict(type=kind,fields=fields,developer_fields=[dict(name=k,value=v,application_id=app)
                       for k,v in fields.items()])
        return [msg('session',dict(dg_schema_version=2,dg_rep_count=2)),
                msg('record',dict(dg_rep_id=2,dg_rep_evt=1,dg_rep_s=60,dg_rep_w=300,
                    dg_rep_src=3,dg_rep_quality=3,dg_rep_valid_s=30,dg_rep_end_s=120))]

    def test_quality_and_missing_events(self):
        r=extract_repetitions(self.messages())
        self.assertEqual(r['repetitions'][0]['valid_power_s'],30)
        self.assertEqual(r['repetitions'][0]['quality_flags'],3)
        self.assertIn('possible missed initial effort(s): first id 2',r['issues'])
        self.assertIn('session reports 2 efforts; recovered 1',r['issues'])

    def test_unverified_producer_is_not_attributed(self):
        r=extract_repetitions(self.messages('00'*16))
        self.assertEqual(r['repetitions'],[])
        self.assertEqual(r['provenance'],'unverified')
        self.assertTrue(r['issues'])

    def test_fit_field_budgets_and_unique_ids(self):
        prod=(ROOT/'garmin-app/source/ProductionRecorder.mc').read_text()
        cal=(ROOT/'garmin-app/calibration/DriftRecorder.mc').read_text()
        base,extras=prod.split('    (:production)',1)
        extras=extras.split('    (:calibration)',1)[0]
        pattern=r'createField\("[^"\n]+",\s*(\d+),\s*FitContributor.DATA_TYPE_(\w+),\s*\{:mesgType => FitContributor.MESG_TYPE_(\w+)'
        sizes={'FLOAT':4,'UINT8':1,'UINT16':2,'SINT16':2,'UINT32':4}
        for source,expected in [(base+extras,{'RECORD':32,'SESSION':23}),
                                (base+cal,{'RECORD':32,'SESSION':24})]:
            fields=re.findall(pattern,source)
            self.assertEqual(len({i for i,t,m in fields}),len(fields))
            self.assertEqual({m:sum(sizes[t] for i,t,k in fields if k==m) for m in expected},expected)

    def test_report_uses_input_and_handles_empty_cohort(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'research';out.mkdir()
            data=dict(summary=dict(period=['2030-01-01','2030-01-02'],models=[]),cohort=[],
                      cases=[],device_comparisons=[],intervals_matches=[])
            (out/'research.json').write_text(json.dumps(data),encoding='utf8')
            subprocess.run([sys.executable,str(ROOT/'validation-lab/render_research.py'),'--data',temp],
                           check=True,capture_output=True,env={**os.environ,'PYTHONUTF8':'1'})
            text=(out/'index.html').read_text(encoding='utf8')
            self.assertIn('2030-01-01',text)
            self.assertIn('0 FIT',text)
            self.assertNotIn('122 Garmin FIT',text)
            self.assertNotIn('3135',text)

    def test_entirely_missing_power_still_has_duration(self):
        messages=self.messages()
        for field in messages[1]['developer_fields']:
            if field['name']=='dg_rep_w':field['value']=None
            if field['name']=='dg_rep_valid_s':field['value']=0
        actual=extract_repetitions(messages)['repetitions'][0]
        self.assertEqual(actual['duration_s'],60)
        self.assertEqual(actual['valid_power_s'],0)
        self.assertIsNone(actual['power_w'])

    def test_duplicate_producer_fields_are_ambiguous(self):
        messages=self.messages()
        messages[1]['developer_fields'].append(dict(messages[1]['developer_fields'][0]))
        actual=extract_repetitions(messages)
        self.assertEqual(actual['repetitions'],[])
        self.assertIn('ambiguous duplicate production developer fields',actual['issues'])
