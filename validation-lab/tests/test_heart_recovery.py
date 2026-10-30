import unittest
from driftlab.heart_recovery import HeartRecovery

class RecoveryTests(unittest.TestCase):
    def test_auto_backdated_60(self):
        r=HeartRecovery()
        for _ in range(3):r.sample(160,300)
        for _ in range(5):r.sample(150,100)
        r.begin(5,300,30)
        for _ in range(54):r.sample(130,100)
        self.assertIsNone(r.delta)
        r.sample(130,100)
        self.assertEqual((r.delta,r.elapsed),(30,60))
    def test_quality_and_pause(self):
        for hr,power,reason in [(None,100,'HR MISSING'),(140,None,'POWER MISSING'),(140,151,'POWER HIGH')]:
            r=HeartRecovery()
            for _ in range(3):r.sample(160,300)
            r.begin(0,300,30);r.sample(hr,power)
            self.assertEqual(r.reason,reason);self.assertIsNone(r.delta)
        r.sample(140,100,False);self.assertEqual(r.reason,'PAUSED')
        for _ in range(3):r.sample(140,0)
        r.begin(0,0,30);self.assertEqual(r.reason,'NEED EFFORT')
    def test_signed_reset_and_short(self):
        r=HeartRecovery()
        for _ in range(3):r.sample(140,300)
        r.begin(0,300,30)
        for _ in range(60):r.sample(145,100)
        self.assertEqual(r.delta,-5)
        r.cancel('NEW EFFORT');self.assertIsNone(r.delta)
        r.begin(0,300,5);self.assertEqual(r.reason,'TOO SHORT')
        r.reset();self.assertIsNone(r.end_hr)

    def test_three_second_windows(self):
        r=HeartRecovery()
        for hr in (150,153,156):r.sample(hr,300)
        r.begin(0,300,30)
        for _ in range(57):r.sample(110,100)
        for hr in (120,123,126):r.sample(hr,100)
        self.assertEqual(r.delta,30)
