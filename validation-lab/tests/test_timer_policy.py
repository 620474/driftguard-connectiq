import unittest
from datetime import datetime, timedelta
from driftlab.fitio import normalize

class TimerPolicyTests(unittest.TestCase):
    def setUp(self):
        self.t = datetime(2026, 10, 1)
        self.records = [dict(timestamp=self.t+timedelta(seconds=i), power=200, heart_rate=100) for i in range(120)]
    def event(self, s, kind, group=0):
        return dict(timestamp=self.t+timedelta(seconds=s),event_type=kind,event_group=group)
    def test_unknown_prefix(self):
        _, q = normalize(self.records,[self.event(119,'stop')])
        self.assertTrue(q['timer_ambiguous'])
        self.assertEqual(q['status'],'approximate')
        self.assertEqual(q['active_seconds'],119)
    def test_known_initial_stop(self):
        _, q = normalize(self.records,[self.event(0,'stop'),self.event(1,'start')])
        self.assertFalse(q['timer_ambiguous'])
        self.assertEqual(q['active_seconds'],119)
    def test_mixed_groups_order_independent(self):
        events=[self.event(0,'start'),self.event(60,'stop'),self.event(60,'start',1)]
        a, q = normalize(self.records,events)
        b, r = normalize(self.records,[events[0],events[2],events[1]])
        self.assertEqual((a,q),(b,r))
        self.assertEqual(q['active_seconds'],60)
        self.assertTrue(q['timer_ambiguous'])
        self.assertEqual(q['status'],'approximate')
    def test_same_group_conflict_order_independent(self):
        events=[self.event(0,'start'),self.event(60,'start'),self.event(60,'stop')]
        a,q=normalize(self.records,events)
        b,r=normalize(self.records,list(reversed(events)))
        self.assertEqual((a,q),(b,r))
        self.assertEqual(q['active_seconds'],60)
        self.assertTrue(q['timer_ambiguous'])
    def test_normal_and_missing_groups(self):
        for event in [self.event(0,'start'),dict(timestamp=self.t,event_type='start')]:
            _,q=normalize(self.records,[event])
            self.assertFalse(q['timer_ambiguous'])
            self.assertEqual(q['status'],'comparison_candidate')
