import csv
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from driftlab.model_candidates import (minute_features, regression, fixed_reference, RelativeDetector,
                                       recoveries, detection_scores)
from driftlab.model_protocols import protocol
from driftlab.model_study import read_labels, labelled_scores, load_samples, review_page


class ModelCandidatesTests(unittest.TestCase):
    def test_known_slope_with_power_adjustment(self):
        rows = []
        for i in range(120):
            t = (i + .5) / 60
            p = 200 + 30 * ((i % 10) - 4.5) / 4.5
            rows.append(
                dict(
                    minute=i + 1,
                    n=60,
                    power=p,
                    lag_power=p,
                    hr=60 + .4 * p + 4 * t,
                    time_h=t,
                    resume=False))
        result = regression(rows)
        self.assertEqual(result['status'], 'MODEL_ESTIMATE')
        self.assertAlmostEqual(result['bpm_per_hour'], 4, places=8)
        self.assertTrue(result['power_adjusted'])

    def test_duration_invariance_and_power_step(self):
        estimates = []
        for hours in (2, 5):
            samples, _ = protocol(seconds=hours * 3600, drift=4, noise=0)
            r = regression(minute_features(samples, 40))
            estimates.append(r['bpm_per_hour'])
            self.assertAlmostEqual(r['bpm_per_hour'], 4, delta=.08)
            self.assertFalse(r['power_adjusted'])
        self.assertLess(abs(estimates[0] - estimates[1]), .08)
        samples, _ = protocol(name='plus4', noise=0)
        self.assertAlmostEqual(
            regression(
                minute_features(
                    samples,
                    40))['bpm_per_hour'],
            0,
            delta=.1)

    def test_confounding_and_short_data_rejected(self):
        samples, _ = protocol(seconds=1800)
        self.assertEqual(
            regression(
                minute_features(samples))['status'],
            'INSUFFICIENT')
        rows = [dict(minute=i + 1, n=60, power=100 + i, lag_power=100 + i, hr=100 + i * .2,
                     time_h=i / 60, resume=False) for i in range(100)]
        self.assertEqual(regression(rows)['status'], 'UNIDENTIFIABLE')

    def test_resume_resets_filter_and_preserves_wall_slots(self):
        samples = [dict(power=200, hr=140, running=True) for _ in range(120)]
        samples[30]['running'] = False
        rows = minute_features(samples)
        self.assertEqual(rows[0]['slot'], 60)
        self.assertTrue(rows[0]['resume'])
        self.assertEqual(rows[0]['n'], 60)
        self.assertEqual(len(rows), 1)

    def test_fixed_reference_requires_comparable_windows(self):
        samples, _ = protocol(noise=0, drift=4)
        rows = minute_features(samples)
        self.assertEqual(fixed_reference(rows)['status'], 'COMPARABLE_WINDOWS')
        rows[-1]['power'] = 400
        self.assertEqual(fixed_reference(rows)['status'], 'VARIABLE_WORKLOAD')

    def test_relative_long_and_ftp_scaling(self):
        for ftp in (180, 360):
            d = RelativeDetector(ftp)
            for p in [.4 * ftp] * 60 + [1.2 * ftp] * 720 + [.4 * ftp] * 5:
                d.sample(p)
            self.assertEqual(len(d.events), 1)
            self.assertEqual(d.events[0]['duration'], 720)
            self.assertFalse(d.events[0]['partial'])
        with self.assertRaises(ValueError):
            RelativeDetector(0)

    def test_partial_censor_and_short_minimum(self):
        d = RelativeDetector(250)
        for p in [100] * 60 + [300] * 30:
            d.sample(p)
        self.assertEqual(d.events, [])  # EOF is not an observed completion.
        d.sample(None)
        self.assertTrue(d.events[0]['partial'])
        d = RelativeDetector(250)
        for p in [100] * 60 + [300] * 15 + [100] * 5:
            d.sample(p)
        self.assertEqual(d.events, [])

    def test_peak_definition_is_separate_and_requires_duration(self):
        samples = [dict(power=300, hr=160, running=True) for _ in range(180)]
        samples += [dict(power=40, hr=h, running=True)
                    for h in ([160] * 5 + [170] * 3 + [160] * 7 + [130] * 70)]
        event = dict(start=0, end=179, duration=180, power=300, partial=False)
        result = recoveries(samples, [event], 250)[0]
        self.assertEqual(result['end_hrr60'], 30)
        self.assertEqual(result['peak_hrr60'], 40)
        self.assertEqual(result['peak_offset_s'], 8)
        event['duration'] = 30
        self.assertEqual(
            recoveries(
                samples,
                [event],
                250)[0]['status'],
            'SHORT_EFFORT')

    def test_hrr_censors_next_effort_and_missing(self):
        samples = [
            dict(
                power=300 if t < 180 else 40,
                hr=160 if t < 180 else 130,
                running=True) for t in range(270)]
        event = dict(start=0, end=179, duration=180, power=300, partial=False)
        samples[200]['hr'] = None
        self.assertIsNone(recoveries(samples, [event], 250)[0]['peak_hrr60'])
        samples[200]['hr'] = 130
        next_event = dict(event, start=200, end=220, duration=21)
        self.assertIsNone(
            recoveries(
                samples, [
                    event, next_event], 250)[0]['end_hrr60'])

    def test_one_to_one_matching_and_scope(self):
        truth = [dict(start=60, end=119)]
        score = detection_scores(
            [dict(start=60, end=119), dict(start=60, end=119)], truth)
        self.assertEqual((score['tp'], score['fp'], score['fn']), (1, 1, 0))
        self.assertIsNone(detection_scores([], [])['precision'])
        with self.assertRaises(ValueError):
            labelled_scores([], [], 120)
        complete = [
            dict(
                start=0, end=119, label='reviewed'), dict(
                start=60, end=119, label='effort')]
        self.assertEqual(labelled_scores(truth, complete, 120)['recall'], 1)

    def test_labels_cannot_come_from_detector(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'labels.csv'
            path.write_text(
                'sha256,start,end,label,source\nx,0,59,effort,detector\n')
            with self.assertRaises(ValueError):
                read_labels(path)

    def test_review_packet_and_cache_provenance(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'review.html'
            review_page(path, [])
            self.assertIn('manual-labels.csv', path.read_text(encoding='utf8'))
            with patch('driftlab.model_study.fitio.read_fit', return_value=([], {'status': 'insufficient'}, [])) as read:
                load_samples(Path('unused.fit'), 'abc', Path(temp))
                load_samples(Path('unused.fit'), 'abc', Path(temp))
                self.assertEqual(read.call_count, 1)


class ModelReportTests(unittest.TestCase):
    def test_empty_render_and_public_privacy(self):
        from driftlab.model_report import render
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            summary = dict(files=0, labelled_activities=0, source_commit='fixture', source_fingerprint='fixture',
                           regression_tau40_states={}, fixed_states={}, current_auto=0)
            (root / 'summary.json').write_text(json.dumps(summary))
            (root / 'synthetic.csv').write_text('case,tau_s\n')
            (root / 'REPORT_RU.md').write_text('# Test\n')
            (root / 'input-context.json').write_text(json.dumps(dict(notes='PRIVATE_FTP_SENTINEL')))
            public = root / 'public.md'
            result = render(root, public)
            render(root, public)
            self.assertEqual(result['files'], 0)
            self.assertNotIn(
                'PRIVATE_FTP_SENTINEL',
                public.read_text(
                    encoding='utf8'))
            local = (root / 'REPORT_RU.md').read_text(encoding='utf8')
            self.assertIn('PRIVATE_FTP_SENTINEL', local)
            self.assertEqual(
                local.count('## Численные сравнения и решение'), 1)

    def test_review_payload_does_not_break_script(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / 'review.html'
            review_page(path, [dict(id='</script><script>bad</script>', date='', length=60,
                                    sha256='fixture', split='test', trace=[])])
            self.assertEqual(
                path.read_text(
                    encoding='utf8').count('</script>'), 1)


if __name__ == '__main__':
    unittest.main()
