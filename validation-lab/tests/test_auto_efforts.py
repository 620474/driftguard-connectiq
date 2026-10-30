import unittest
from driftlab.auto_efforts import Config, Detector, detect, CANDIDATES

def rows(powers):
    return [dict(power=p,running=True) for p in powers]

class AutoEffortTests(unittest.TestCase):
    def test_spike_and_short_coast(self):
        self.assertEqual(list(detect(rows([100]*60+[400]+[100]*60))),[])
        e=list(detect(rows([100]*60+[300]*10+[0]*2+[300]*10+[100]*5)))
        self.assertEqual(len(e),1)
        self.assertEqual((e[0]['start'],e[0]['end'],e[0]['seconds']), (60,81,22))
        self.assertEqual(e[0]['power_sum'],6000)
        self.assertFalse(e[0]['partial'])
        self.assertEqual(e[0]['detected_start']-e[0]['start'],2)
        self.assertEqual(e[0]['detected_end']-e[0]['end'],5)
    def test_repeats(self):
        for duration,rest in [(30,30),(40,20),(60,60),(180,120),(600,120)]:
            e=list(detect(rows([100]*60+([300]*duration+[100]*rest)*3)))
            self.assertEqual(len(e),3)
            self.assertTrue(all(x['seconds']==duration and x['mean_power']==300 for x in e))
    def test_missing_and_pause_are_partial(self):
        for pause in (True,False):
            r=rows([100]*60+[300]*20+[None]+[100]*60)
            r[80]['running']=pause
            e=list(detect(r))
            self.assertEqual(len(e),1)
            self.assertTrue(e[0]['partial'])
            self.assertEqual(e[0]['seconds'],20)
    def test_finish_and_unconfirmed_end(self):
        e=list(detect(rows([100]*60+[300]*20+[100]*2)))
        self.assertEqual(e[0]['seconds'],20)
        self.assertTrue(e[0]['partial'])
    def test_grid_and_config(self):
        d=Detector();d.sample(0,100)
        with self.assertRaises(ValueError):d.sample(2,100)
        with self.assertRaises(ValueError):Config(start_confirm=0)
        self.assertEqual(list(detect(rows([100]*100))),[])

    def test_over_under_stays_one_effort(self):
        e=list(detect(rows([100]*60+([300]*20+[200]*20)*3+[100]*5)))
        self.assertEqual(len(e),1)
        self.assertEqual(e[0]['seconds'],120)
        self.assertEqual(e[0]['mean_power'],250)
    def test_buffers_remain_bounded(self):
        d=Detector()
        for i in range(10000):
            d.sample(i,100 if i<60 else 300)
            self.assertLessEqual(len(d.history),60)
            self.assertLess(len(d.pending),3)
            self.assertLess(len(d.gap),5)
        self.assertEqual(d.finish()['seconds'],9940)

    def test_all_candidates_on_frozen_protocols(self):
        for name, config in CANDIDATES.items():
            for duration,rest in [(30,30),(40,20),(60,60),(180,120),(600,120)]:
                with self.subTest(candidate=name,duration=duration):
                    e=list(detect(rows([100]*60+([300]*duration+[100]*rest)*3),config))
                    self.assertEqual(len(e),3)
                    for index, effort in enumerate(e):
                        self.assertEqual(effort['start'],60+index*(duration+rest))
                        self.assertEqual(effort['seconds'],duration)
                        self.assertEqual(effort['mean_power'],300)
                        self.assertFalse(effort['partial'])
