import unittest
from driftlab.intervals import Intervals

class IntervalTests(unittest.TestCase):
    def test_shared_monkey_stream(self):
        # Same stream and expected totals as intervalBoundariesAndMissingPower.
        e = Intervals()
        e.sample(300)
        self.assertEqual(e.sequence, 0)
        e.boundary()
        for power, running in [(300, True), (0, True), (None, True), (900, False), (-1, True)]:
            e.sample(power, running)
        self.assertEqual((e.seconds, e.valid_power, e.power_sum, e.mean), (4, 2, 300, 150))
        e.boundary()
        self.assertEqual(e.last, (4, 2, 300, 150, True))
        self.assertIsNone(e.mean)
        e.boundary()
        self.assertEqual(e.sequence, 2)
        e.workout_start()
        e.sample(200)
        e.boundary()
        self.assertEqual((e.sequence, e.seconds), (1, 1))
        e.boundary(True)
        self.assertEqual(e.sequence, 2)
        e.reset()
        self.assertEqual(e.sequence, 0)
        self.assertIsNone(e.last)

    def test_late_load_missing_and_partial_reset(self):
        e = Intervals()
        e.boundary(True)
        self.assertEqual((e.source, e.sequence), ("WORKOUT", 1))
        e.sample(None)
        e.boundary(True)
        self.assertEqual(e.last[:4], (1, 0, 0, None))
        e.sample(100)
        e.reset()
        self.assertEqual(e.seconds, 0)
        self.assertIsNone(e.last)
