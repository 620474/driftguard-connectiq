"""Experimental causal power-change detector. Offline only, not physiology.

Feed one timestamped grid slot per second; do not call with sparse FIT RECORDs.
Explicit workout/manual segmentation remains separate from this fallback model.
"""
from collections import deque
from dataclasses import dataclass, asdict
from statistics import median
from fractions import Fraction

@dataclass(frozen=True)
class Config:
    baseline_seconds: int = 60
    start_ratio: float = 1.35
    start_delta: int = 50
    minimum_watts: int = 120
    start_confirm: int = 3
    end_ratio: float = 1.15
    end_delta: int = 20
    end_confirm: int = 5
    minimum_seconds: int = 10

    def __post_init__(self):
        if min(self.baseline_seconds,self.start_confirm,self.end_confirm,self.minimum_seconds) < 1:
            raise ValueError('durations must be positive')
        if self.start_ratio <= self.end_ratio or self.start_delta <= self.end_delta:
            raise ValueError('start threshold must exceed end threshold')

class Detector:
    def __init__(self, config=Config()):
        self.config = config
        self.start_ratio = Fraction(str(config.start_ratio))
        self.end_ratio = Fraction(str(config.end_ratio))
        self.history = deque(maxlen=config.baseline_seconds)
        self.pending = []
        self.gap = []
        self.active = None
        self.last_time = None

    def _append(self, row):
        t, p = row
        self.active['end'] = t
        self.active['seconds'] += 1
        self.active['power_sum'] += p

    def _close(self, reason, detected_at):
        result = None
        if self.active is not None and self.active['seconds'] >= self.config.minimum_seconds:
            result = dict(self.active, mean_power=self.active['power_sum']/self.active['seconds'],
                          reason=reason, partial=reason != 'power_drop', detected_end=detected_at)
        self.active = None
        self.pending.clear()
        self.gap.clear()
        return result

    def sample(self, timestamp, power, running=True):
        c = self.config
        # timestamp is integer grid index; sparse records must be normalized first.
        if self.last_time is not None and timestamp != self.last_time + 1:
            raise ValueError('expected consecutive one-second grid slots')
        self.last_time = timestamp
        if not running or power is None or not 0 <= power <= 10000:
            result = self._close('pause' if not running else 'missing_power', timestamp)
            self.history.clear()
            return result
        row = (timestamp, power)
        if self.active is not None:
            base_twice = int(self.active['baseline'] * 2)
            if (power*2*self.end_ratio.denominator < base_twice*self.end_ratio.numerator
                    or power*2 < base_twice+2*c.end_delta):
                self.gap.append(row)
                if len(self.gap) >= c.end_confirm:
                    low = list(self.gap)
                    result = self._close('power_drop', timestamp)
                    self.history.extend(p for _,p in low)
                    return result
            else:
                for held in self.gap:
                    self._append(held)
                self.gap.clear()
                self._append(row)
            return None
        if len(self.history) < c.baseline_seconds:
            self.history.append(power)
            return None
        baseline = median(self.history)
        base_twice = int(baseline*2)
        threshold = max(c.minimum_watts, float(Fraction(base_twice,2)*self.start_ratio), baseline+c.start_delta)
        if (power >= c.minimum_watts
                and power*2*self.start_ratio.denominator >= base_twice*self.start_ratio.numerator
                and power*2 >= base_twice+2*c.start_delta):
            self.pending.append(row)
            if len(self.pending) >= c.start_confirm:
                self.active = dict(start=self.pending[0][0], end=timestamp, seconds=0, power_sum=0,
                                   baseline=baseline, start_threshold=threshold,
                                   end_threshold=max(float(Fraction(base_twice,2)*self.end_ratio),baseline+c.end_delta),
                                   detected_start=timestamp)
                for held in self.pending:
                    self._append(held)
                self.pending.clear()
        else:
            self.history.extend(p for _,p in self.pending)
            self.pending.clear()
            self.history.append(power)
        return None

    def finish(self):
        return self._close('activity_end', self.last_time)

CANDIDATES = {
    'responsive': Config(start_ratio=1.25,start_delta=40,start_confirm=2,end_confirm=3,minimum_seconds=5),
    'balanced': Config(),
    'conservative': Config(start_ratio=1.5,start_delta=70,start_confirm=5,end_confirm=8,minimum_seconds=15),
}

def detect(samples, config=Config()):
    detector = Detector(config)
    for i,row in enumerate(samples):
        result = detector.sample(i,row.get('power'),row['running'])
        if result is not None:
            yield result
    result = detector.finish()
    if result is not None:
        yield result


def main():
    import argparse, csv, json, hashlib
    from pathlib import Path
    from .fitio import read_fit
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive',type=Path)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.output.exists():
        parser.error('output must be a new directory (private ride data)')
    args.output.mkdir(parents=True)
    activity_rows=[];effort_rows=[]
    for file in sorted(args.archive.glob('*.fit')):
        digest=hashlib.sha256(file.read_bytes()).hexdigest()
        try:
            samples,quality,_=read_fit(file)
        except Exception as error:
            activity_rows.append(dict(activity=digest,status='decode_error',issues=type(error).__name__))
            continue
        activity_rows.append(dict(activity=digest,status=quality['status'],issues='; '.join(quality['issues'])))
        for candidate,config in CANDIDATES.items():
            for effort in detect(samples,config):
                effort_rows.append(dict(activity=digest,candidate=candidate,quality=quality['status'],
                    timer_ambiguous=quality['timer_ambiguous'],**effort))
    def save(name, rows):
        if not rows: return
        with (args.output/name).open('w',encoding='utf8',newline='') as f:
            writer=csv.DictWriter(f,fieldnames=sorted(set().union(*(r.keys() for r in rows))))
            writer.writeheader();writer.writerows(rows)
    save('activities.csv',activity_rows);save('efforts.csv',effort_rows)
    from collections import Counter
    summary=dict(files=len(activity_rows),configs={k:asdict(v) for k,v in CANDIDATES.items()},
                 counts=dict(Counter(r['candidate'] for r in effort_rows)),
                 partial=dict(Counter(r['candidate'] for r in effort_rows if r['partial'])),
                 limitation='All FITs exploratory; no independently labelled race/effort ground truth. '
                 'Null grid gaps are not interpolated. Counts are sensitivity, not accuracy; '
                 'this run does not select a winner or validate on-device callbacks.')
    (args.output/'summary.json').write_text(json.dumps(summary,indent=2),encoding='utf8')
    print(json.dumps(summary))

if __name__ == '__main__':
    main()
