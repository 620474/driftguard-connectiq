"""Source-faithful algorithm port. Python double arithmetic, not bitwise MC Float."""
from dataclasses import dataclass


def halves(records):
    total = sum(r[2] for r in records)
    if total <= 0:
        return None
    p1 = h1 = p2 = h2 = done = 0.0
    for p, h, s in records:
        if s <= 0:
            continue
        share = max(0., min(1., (total / 2 - done) / s))
        p1 += p * share
        h1 += h * share
        p2 += p * (1-share)
        h2 += h * (1-share)
        done += s
    if min(p1, h1, h2) <= 0:
        return None
    ef = p1 / h1
    return [(ef - p2/h2) / ef * 100, ef, (p2/p1-1)*100]


class Buckets:
    def __init__(self, capacity=240):
        self.capacity = capacity - capacity % 2
        if self.capacity < 2:
            raise ValueError('capacity must be >=2')
        self.records = []
        self.width = 1
        self.open = 0

    def add(self, record):
        if not self.records or self.open == self.width:
            if len(self.records) == self.capacity:
                self.records = [tuple(a+b for a,b in zip(self.records[i], self.records[i+1]))
                                for i in range(0, self.capacity, 2)]
                self.width *= 2
            self.records.append((0,0,0))
            self.open = 0
        self.records[-1] = tuple(a+b for a,b in zip(self.records[-1],record))
        self.open += 1


@dataclass(frozen=True)
class Config:
    warmup: int = 15
    recovery: int = 3
    band: int = 20
    valid: int = 48
    mismatch: float = 5.
    median: str = 'current'
    power_cv: float | None = None
    resume_gate: bool = True


def band_for(d):
    return 3 if d >= 10 else 2 if d >= 5 else 0 if d < -3 else 1


def label(d, previous):
    if previous is None:
        return band_for(d)
    hi, lo = band_for(d-.5), band_for(d+.5)
    return hi if hi > previous else lo if lo < previous else previous


class Engine:
    def __init__(self, config=Config()):
        self.c = config
        self.ride, self.compat = Buckets(), Buckets()
        self.history, self.minutes, self.powers = [], [], []
        self.hist = [0]*150
        self.recovery = self.post = self.steady = self.steady_seconds = 0
        self.pending = []
        self.pause_seen = False
        self.interrupted = False
        self.bands = [None,None]
        self.result = self.evaluate()

    def add(self, power, hr, running=True):
        if not running:
            if self.minutes or self.pending:
                self.pause_seen = True
            return
        if self.pause_seen and self.c.resume_gate:
            self.recovery = self.c.recovery
            self.interrupted = True
        self.pause_seen = False
        self.pending.append((power,hr))
        if len(self.pending) == 60:
            self.commit()

    def median(self, powers):
        hist = [0]*150
        for p in powers:
            hist[min(149,p//10)] += 1
        target, seen = (len(powers)+1)//2, 0
        for i,n in enumerate(hist):
            seen += n
            if seen >= target:
                return i*10+5
        return 0

    def commit(self):
        good = [(p,h) for p,h in self.pending if p is not None and 0<p<=10000 and h is not None and 0<h<=300]
        with_hr = [(p,h) for p,h in self.pending if h is not None and 0<h<=300]
        ps, hs, n = sum(p for p,h in good), sum(h for p,h in good), len(good)
        ref = None
        reason = 'warm-up'
        steady = False
        before = self.recovery
        if len(self.minutes) >= self.c.warmup:
            self.post += 1
            inband = False
            reason = 'insufficient valid seconds'
            if n >= self.c.valid:
                p = ps//n  # Monkey C Number division truncates
                prior = self.powers[:]
                self.powers.append(p)
                pool = self.powers
                if self.c.median == 'prior':
                    pool = prior or [p]
                elif self.c.median == 'rolling60':
                    # Includes only eligible powers from last 60 running minutes.
                    pool = [m['power_int'] for m in self.minutes[-59:] if m['power_int'] is not None] + [p]
                elif self.c.median == 'fixed':
                    pool = self.powers[:1]
                ref = self.median(pool)
                inband = p*100 >= ref*(100-self.c.band) and p*100 <= ref*(100+self.c.band)
                stable = self.c.power_cv is None or sum(p*p for p,h in good)/n <= (ps/n)**2 * (1+self.c.power_cv**2)
                inband = inband and stable and not self.interrupted
                reason = 'power out of band'
                if not stable: reason = 'variable power'
                if self.interrupted: reason = 'timer resume'
            if not inband:
                self.recovery = self.c.recovery
            elif self.recovery:
                self.recovery -= 1
                reason = 'recovery after unstable minute'
            else:
                steady, reason = True, 'steady'
                self.steady += 1
                self.steady_seconds += n
            self.ride.add((ps,hs,n) if steady else (0,0,0))
        self.history.append((ps,hs,n if steady else 0))
        self.history = self.history[-60:]
        self.compat.add((sum(p if p is not None and 0<p<=10000 else 0 for p,h in with_hr),sum(h for p,h in with_hr),len(with_hr)))
        self.minutes.append(dict(minute=len(self.minutes)+1,power=ps/n if n else None,hr=hs/n if n else None,
            valid_seconds=n,reference_median=ref,steady=steady,reason=reason,recovery_before=before,
            recovery_after=self.recovery,power_sum=ps,hr_sum=hs,power_int=ps//n if n>=self.c.valid and self.post else None))
        self.pending = []
        self.interrupted = False
        self.result = self.evaluate()
        self.minutes[-1]['ride_drift'] = self.result['ride']['drift']
        self.minutes[-1]['ride_state'] = self.result['ride']['state']

    def evaluate(self):
        def metric(state, records, index):
            r = halves(records) if state is None else None
            if state is None:
                state = 'NOT_STEADY' if r is None else 'POWER_CHANGED' if abs(r[2])>self.c.mismatch else 'VALID'
            d = r[0] if state=='VALID' else None
            self.bands[index] = label(d,self.bands[index]) if d is not None else None
            return dict(state=state,drift=d,baseline=r[1] if r else None,power_change=r[2] if r else None,band=self.bands[index])
        warm = len(self.minutes)<self.c.warmup
        ride = 'WARMUP' if warm else 'NOT_STEADY' if self.post>=40 and self.steady*100<self.post*70 else 'COLLECTING' if self.steady<40 else None
        last = 'WARMUP' if warm else 'COLLECTING' if self.post<60 else 'NOT_STEADY' if sum(r[2]>0 for r in self.history)<48 else None
        compat = halves(self.compat.records)
        return dict(ride=metric(ride,self.ride.records,0),last60=metric(last,self.history,1),compat=compat[0] if compat else None,
                    coverage=self.steady*100/self.post if self.post else 0,steady_seconds=self.steady_seconds)
