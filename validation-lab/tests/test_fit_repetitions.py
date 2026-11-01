import unittest
from driftlab.fitio import extract_repetitions


def record(rep_id, event, power=260, seconds=180, source=1, hrr=-32768):
    return {'type': 'record', 'fields': {
        'timestamp': f'2026-10-31T12:00:{rep_id % 60:02d}',
        'dg_rep_id': rep_id, 'dg_rep_evt': event,
        'dg_rep_w': power, 'dg_rep_s': seconds,
        'dg_rep_src': source, 'dg_rep_hrr': hrr if event != 3 else 22,
        'dg_rep_hrr_active': hrr if event == 3 else -32768
    }}


class TestFitRepetitions(unittest.TestCase):
    def test_multiple_efforts_and_hrr_update(self):
        messages = [
            record(1, 1), record(1, 1), record(1, 2, hrr=22),
            record(1, 2, hrr=22), record(1, 3, hrr=19), record(2, 1, power=280, source=3),
            record(3, 1, power=310, seconds=45, source=2)
        ]
        actual = extract_repetitions(messages)
        self.assertEqual(len(actual['repetitions']), 3)
        self.assertEqual([r['source'] for r in actual['repetitions']], ['AUTO','WORKOUT','MANUAL'])
        self.assertEqual(actual['repetitions'][0]['hrr60_bpm'], 22)
        self.assertEqual(actual['repetitions'][0]['active_hrr60_bpm'], 19)
        self.assertIsNone(actual['repetitions'][1]['hrr60_bpm'])
        self.assertEqual(actual['issues'], [])

    def test_missing_effort_is_flagged(self):
        result = extract_repetitions([record(1, 1), record(3, 1)])
        self.assertIn('possible missed effort(s): 1 -> 3', result['issues'])

    def test_orphan_recovery_is_not_invented(self):
        result = extract_repetitions([record(4, 2, hrr=30)])
        self.assertEqual(result['repetitions'], [])
        self.assertIn('HRR without effort: 4', result['issues'])

    def test_unrelated_records_are_ignored(self):
        result = extract_repetitions([{'type':'record','fields':{'power':270}},
                                      {'type':'session','fields':{'dg_rep_id':1,'dg_rep_evt':1}}])
        self.assertEqual(result['repetitions'], [])
        self.assertEqual(result['issues'], [])


if __name__ == '__main__':
    unittest.main()
