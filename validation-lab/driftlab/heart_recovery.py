"""Source-faithful strict and active HRR60; engineering gates, no clinical labels."""
from collections import deque


class HeartRecovery:
    def __init__(self):
        self.reset()

    def reset(self):
        self.hr = deque(maxlen=8)
        self.power = deque(maxlen=8)
        self.end_hr = None
        self.cancel('NEED EFFORT')

    def cancel(self, reason):
        self.collecting = self.active_collecting = False
        self.delta = self.active_delta = None
        self.elapsed = self.parent_id = 0
        self.recovery_power_sum = 0
        self.reason = reason

    @property
    def mean_recovery_power(self):
        return self.recovery_power_sum / 60 if self.elapsed == 60 else None

    def mean(self, delay=0):
        values = list(self.hr)
        if len(values) < delay + 3:
            return None
        window = values[len(values)-delay-3:len(values)-delay]
        return sum(window)/3 if all(x is not None for x in window) else None

    def begin(self, delay, effort_power, duration):
        self.cancel('NEED EFFORT')
        self.end_hr = self.mean(delay)
        if duration < 10:
            self.reason = 'TOO SHORT'
            return
        if self.end_hr is None:
            self.reason = 'HR MISSING'
            return
        if effort_power is None:
            self.reason = 'POWER MISSING'
            return
        if effort_power <= 0:
            return
        self.limit, self.active_limit = effort_power*.5, effort_power*.9
        self.collecting = self.active_collecting = True
        previous = list(zip(self.hr, self.power))[-delay:] if delay else []
        for h, p in previous:
            if h is None:
                self.cancel('HR MISSING')
                return
            if p is None:
                self.cancel('POWER MISSING')
                return
            if p > self.limit:
                self.collecting = False
                self.reason = 'POWER HIGH'
            if p > self.active_limit:
                self.active_collecting = False
                self.reason = 'ACTIVE POWER HIGH'
        if not self.collecting and not self.active_collecting:
            return
        self.recovery_power_sum = sum(p for h, p in previous)
        self.elapsed, self.reason = delay, 'COLLECTING'

    def sample(self, hr, power, running=True):
        if not running:
            self.cancel('PAUSED')
            self.hr.clear()
            self.power.clear()
            return
        hr = hr if hr is not None and 0 < hr <= 300 else None
        power = power if power is not None and 0 <= power <= 10000 else None
        self.hr.append(hr)
        self.power.append(power)
        if not self.collecting and not self.active_collecting:
            return
        if hr is None:
            self.cancel('HR MISSING')
            return
        if power is None:
            self.cancel('POWER MISSING')
            return
        if self.collecting and power > self.limit:
            self.collecting, self.reason = False, 'POWER HIGH'
        if self.active_collecting and power > self.active_limit:
            self.active_collecting = False
            if not self.collecting:
                self.reason = 'ACTIVE POWER HIGH'
        if not self.collecting and not self.active_collecting:
            return
        self.recovery_power_sum += power
        self.elapsed += 1
        if self.elapsed == 60:
            if self.collecting:
                self.delta = self.end_hr-self.mean()
                self.reason = 'READY'
            if self.active_collecting:
                self.active_delta = self.end_hr-self.mean()
                if not self.collecting:
                    self.reason = 'ACTIVE READY'
            self.collecting = self.active_collecting = False
