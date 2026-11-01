"""Frozen offline hypotheses, not replacements for the on-device metrics.

One sample per wall-clock second; running time excludes pauses. Invalid/gapped
power resets the EWMA. Resume excludes 180 running seconds; no interpolation.
Regression intervals describe model uncertainty, not physiology or sensor error.
"""
from collections import deque
from math import exp, sqrt
from statistics import mean, median


def valid_power(p):
    return isinstance(p, (int, float)) and 0 <= p <= 10000


def valid_hr(h):
    return isinstance(h, (int, float)) and 0 < h <= 300


def minute_features(samples, tau=40):
    rows = []
    pending = []
    filtered = None
    elapsed = 0
    paused = False
    recovery = 0
    alpha = 1 - exp(-1 / tau) if tau else 1
    for slot, s in enumerate(samples):
        if not s['running']:
            if elapsed:
                paused = True
            filtered = None
            continue
        if paused:
            recovery = 180
            paused = False
        p, h = s.get('power'), s.get('hr')
        filtered = (p if filtered is None else filtered + alpha *
                    (p - filtered)) if valid_power(p) else None
        elapsed += 1
        pending.append((p, h, filtered, elapsed / 3600, recovery > 0))
        recovery = max(0, recovery - 1)
        if len(pending) == 60:
            good = [
                v for v in pending if valid_power(
                    v[0]) and v[0] > 0 and valid_hr(
                    v[1]) and v[2] is not None]
            rows.append(dict(minute=elapsed // 60, slot=slot, n=len(good),
                             power=mean(v[0] for v in good) if good else None,
                             lag_power=mean(v[2]
                                            for v in good) if good else None,
                             hr=mean(v[1] for v in good) if good else None,
                             time_h=mean(v[3] for v in pending), resume=any(v[4] for v in pending)))
            pending = []
    return rows


def invert(a):
    n = len(a)
    m = [list(row) + [int(i == j) for j in range(n)]
         for i, row in enumerate(a)]
    for j in range(n):
        pivot = max(range(j, n), key=lambda i: abs(m[i][j]))
        if abs(m[pivot][j]) < 1e-10:
            raise ValueError('singular design')
        m[j], m[pivot] = m[pivot], m[j]
        scale = m[j][j]
        m[j] = [v / scale for v in m[j]]
        for i in range(n):
            if i != j:
                scale = m[i][j]
                m[i] = [x - scale * y for x, y in zip(m[i], m[j])]
    return [row[n:] for row in m]


def regression(rows, support=None, hac_lags=3):
    good = [r for r in rows if r['minute'] > 15 and r['n'] >= 48 and not r['resume']
            and (support is None or r['minute'] in support)]
    base = dict(
        n=len(good),
        status='INSUFFICIENT',
        bpm_per_hour=None,
        ci95=None)
    if len(good) < 40 or good[-1]['time_h'] - good[0]['time_h'] < .5:
        return base
    pbar = mean(r['lag_power'] for r in good)
    tbar = mean(r['time_h'] for r in good)
    pvar = mean((r['lag_power'] - pbar)**2 for r in good)
    reduced = pvar < 1.0
    x = [[1, (r['time_h'] - tbar)] if reduced else [1,
                                                    (r['lag_power'] - pbar) / 100, r['time_h'] - tbar] for r in good]
    y = [r['hr'] for r in good]
    n = len(x)
    k = len(x[0])
    if not reduced:
        cov = sum(v[1] * v[2] for v in x)
        corr = cov / sqrt(sum(v[1]**2 for v in x) * sum(v[2]**2 for v in x))
        if abs(corr) > .98:
            return dict(base, status='UNIDENTIFIABLE',
                        power_time_correlation=corr)
    gram = [[sum(v[i] * v[j] for v in x) for j in range(k)] for i in range(k)]
    try:
        inverse = invert(gram)
    except ValueError:
        return dict(base, status='UNIDENTIFIABLE')
    xy = [sum(v[i] * h for v, h in zip(x, y)) for i in range(k)]
    beta = [sum(v * z for v, z in zip(row, xy)) for row in inverse]
    residual = [h - sum(b * z for b, z in zip(beta, v)) for h, v in zip(y, x)]
    score = [[v * e for v in row] for row, e in zip(x, residual)]
    meat = [[sum(v[i] * v[j] for v in score) for j in range(k)]
            for i in range(k)]
    for lag in range(1, hac_lags + 1):
        weight = 1 - lag / (hac_lags + 1)
        for a in range(lag, n):
            if good[a]['minute'] - good[a - lag]['minute'] != lag:
                continue
            for i in range(k):
                for j in range(k):
                    meat[i][j] += weight * (score[a][i] * score[a - lag]
                                            [j] + score[a - lag][i] * score[a][j])
    variance = sum(inverse[-1][i] * meat[i][j] * inverse[j][-1]
                   for i in range(k) for j in range(k)) * n / (n - k)
    se = sqrt(max(0, variance))
    slope = beta[-1]
    return dict(base, status='MODEL_ESTIMATE', bpm_per_hour=slope, ci95=[slope - 1.96 * se, slope + 1.96 * se],
                power_adjusted=not reduced, reference_power_w=pbar,
                rmse=sqrt(mean(e * e for e in residual)), span_h=good[-1]['time_h'] - good[0]['time_h'])


def fixed_reference(rows):
    reference = [r for r in rows if 16 <= r['minute'] <= 35]
    current = rows[-10:]

    def supported(part):
        return part and all(r['n'] >= 48 and not r['resume'] for r in part)
    result = dict(status='INSUFFICIENT', drift_percent=None)
    if len(reference) != 20 or len(
            current) != 10 or current[0]['minute'] <= 35:
        return result
    if not supported(reference) or not supported(current):
        return dict(result, status='DATA_GAPS_OR_RESUME')

    def stable(part):
        p = mean(r['power'] for r in part)
        return sqrt(mean((r['power'] - p)**2 for r in part)) / p <= .10
    if not stable(reference) or not stable(current):
        return dict(result, status='VARIABLE_WORKLOAD')

    def weighted(part, key): return sum(
        r[key] * r['n'] for r in part) / sum(r['n'] for r in part)
    p0 = weighted(reference, 'power')
    p1 = weighted(current, 'power')
    if abs(p1 / p0 - 1) > .05:
        return dict(result, status='POWER_CHANGED')
    ef0 = p0 / weighted(reference, 'hr')
    ef1 = p1 / weighted(current, 'hr')
    return dict(result, status='COMPARABLE_WINDOWS', drift_percent=(1 - ef1 / ef0) * 100,
                reference_w=p0, current_w=p1, reference_minutes=[16, 35], current_minutes=[current[0]['minute'], current[-1]['minute']])


class RelativeDetector:
    """Frozen engineering candidate: baseline only outside active efforts, no split/cap."""

    def __init__(self, ftp):
        if not isinstance(ftp, (int, float)) or not 50 <= ftp <= 600:
            raise ValueError('FTP must be 50..600 W')
        self.ftp = ftp
        self.history = deque(maxlen=60)
        self.pending = []
        self.gap = []
        self.active = None
        self.events = []
        self.tick = -1

    def close(self, reason):
        if self.active and self.active['duration'] >= 20:
            self.events.append(dict(self.active, power=self.active['total'] / self.active['duration'],
                                    partial=reason != 'power_drop', reason=reason))
        self.active = None
        self.pending = []
        self.gap = []

    def append(self, t, p):
        self.active['end'] = t
        self.active['duration'] += 1
        self.active['total'] += p

    def sample(self, p, running=True):
        self.tick += 1
        if not running or not valid_power(p):
            self.close('pause' if not running else 'missing_power')
            self.history.clear()
            return
        if self.active:
            if p < self.active['exit']:
                self.gap.append((self.tick, p))
                if len(self.gap) == 5:
                    low = self.gap[:]
                    self.close('power_drop')
                    self.history.extend(p for t, p in low)
            else:
                for t, v in self.gap:
                    self.append(t, v)
                self.gap = []
                self.append(self.tick, p)
            return
        if len(self.history) < 60:
            self.history.append(p)
            return
        base = median(self.history)
        threshold = max(.60 * self.ftp, 1.20 * base, base + .10 * self.ftp)
        if p >= threshold:
            self.pending.append((self.tick, p))
            if len(self.pending) == 3:
                entry = mean(p for t, p in self.pending)
                self.active = dict(start=self.pending[0][0], end=self.tick, duration=0, total=0,
                                   exit=max(1.08 * base, base + .05 * self.ftp, .70 * entry))
                for t, v in self.pending:
                    self.append(t, v)
                self.pending = []
        else:
            self.history.extend(v for t, v in self.pending)
            self.pending = []
            self.history.append(p)


def recoveries(samples, events, ftp, minimum_duration=180):
    """Paired definitions on identical boundaries; 3-minute/40% FTP are hypotheses."""
    results = []

    def hr3(t):
        if t < 2 or t >= len(samples):
            return None
        chunk = samples[t - 2:t + 1]
        return mean(s['hr'] for s in chunk) if all(
            s['running'] and valid_hr(s.get('hr')) for s in chunk) else None
    for i, event in enumerate(events):
        end = event['end']
        next_start = events[i + 1]['start'] if i + \
            1 < len(events) else len(samples)
        row = dict(start=event['start'], end=end, duration=event['duration'], end_hrr60=None, peak_hrr60=None,
                   peak_offset_s=None, status='INCOMPLETE', recovery_w=None)

        def window_ok(anchor, limit, start=None):
            if anchor + 60 >= len(samples) or anchor + 60 >= next_start:
                return False
            return all(s['running'] and valid_power(s.get('power')) and s['power'] <= limit and valid_hr(s.get('hr'))
                       for s in samples[anchor + 1 if start is None else start:anchor + 61])
        h0 = hr3(end)
        if not event.get('partial') and event['duration'] >= 10 and h0 is not None and window_ok(
                end, .5 * event['power']):
            row['end_hrr60'] = h0 - hr3(end + 60)
        if event.get('partial'):
            row['status'] = 'PARTIAL_EFFORT'
        elif event['duration'] < minimum_duration:
            row['status'] = 'SHORT_EFFORT'
        elif end + 15 >= next_start:
            row['status'] = 'PEAK_WINDOW_CENSORED'
        else:
            peak_window = [(hr3(t), t) for t in range(end, end + 16)]
            if any(h is None for h, t in peak_window):
                row['status'] = 'HR_GAP_OR_EOF'
            else:
                hpeak, anchor = max(peak_window, key=lambda v: (v[0], -v[1]))
                row['peak_offset_s'] = anchor - end
                if window_ok(anchor, .4 * ftp, end + 1):
                    row.update(status='CANDIDATE_ESTIMATE', peak_hrr60=hpeak - hr3(anchor + 60),
                               recovery_w=mean(s['power'] for s in samples[anchor + 1:anchor + 61]))
                else:
                    row['status'] = 'RECOVERY_POWER_GAP_PAUSE_OR_CENSORED'
        results.append(row)
    return results


def detection_scores(predicted, truth, iou_threshold=.5):
    """Maximum-cardinality one-to-one matching. Truth must be independently supplied."""
    def iou(a, b):
        overlap = max(0, min(a['end'], b['end']) -
                      max(a['start'], b['start']) + 1)
        return overlap / ((a['end'] - a['start'] + 1) +
                          (b['end'] - b['start'] + 1) - overlap)
    edges = [sorted([j for j, t in enumerate(truth) if iou(
        p, t) >= iou_threshold], key=lambda j: -iou(p, truth[j])) for p in predicted]
    matched = {}

    def assign(i, seen):
        for j in edges[i]:
            if j in seen:
                continue
            seen.add(j)
            if j not in matched or assign(matched[j], seen):
                matched[j] = i
                return True
        return False
    for i in range(len(predicted)):
        assign(i, set())
    pairs = [(predicted[i], truth[j]) for j, i in matched.items()]
    tp = len(pairs)
    return dict(tp=tp, fp=len(predicted) - tp, fn=len(truth) - tp,
                precision=tp / len(predicted) if predicted else None, recall=tp / len(truth) if truth else None,
                median_start_error_s=median(
        p['start'] - t['start'] for p,
        t in pairs) if pairs else None,
        median_end_error_s=median(p['end'] - t['end'] for p, t in pairs) if pairs else None)
