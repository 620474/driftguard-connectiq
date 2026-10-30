"""Raw gated HRR60 prototype. No clinical categories or rep comparisons."""
from collections import deque

class HeartRecovery:
    def __init__(self):
        self.reset()
    def reset(self):
        self.hr=deque(maxlen=8);self.power=deque(maxlen=8)
        self.end_hr=None;self.cancel('NEED EFFORT')
    def cancel(self,reason):
        self.collecting=False;self.delta=None;self.elapsed=0;self.reason=reason
    def mean(self,delay=0):
        values=list(self.hr)
        if len(values)<delay+3:return None
        window=values[len(values)-delay-3:len(values)-delay]
        return sum(window)/3 if all(x is not None for x in window) else None
    def begin(self,delay,effort_power,duration):
        self.cancel('NEED EFFORT');self.end_hr=self.mean(delay)
        if duration<10:self.reason='TOO SHORT';return
        if self.end_hr is None:self.reason='HR MISSING';return
        if effort_power is None:self.reason='POWER MISSING';return
        if effort_power<=0:self.reason='NEED EFFORT';return
        self.limit=effort_power*.5
        for h,p in zip(list(self.hr)[-delay:] if delay else [],list(self.power)[-delay:] if delay else []):
            if h is None:self.reason='HR MISSING';return
            if p is None:self.reason='POWER MISSING';return
            if p>self.limit:self.reason='POWER HIGH';return
        self.elapsed=delay;self.collecting=True;self.reason='COLLECTING'
    def sample(self,hr,power,running=True):
        if not running:
            self.cancel('PAUSED');self.hr.clear();self.power.clear();return
        hr=hr if hr is not None and 0<hr<=300 else None
        power=power if power is not None and 0<=power<=10000 else None
        self.hr.append(hr);self.power.append(power)
        if not self.collecting:return
        if hr is None:self.cancel('HR MISSING');return
        if power is None:self.cancel('POWER MISSING');return
        if power>self.limit:self.cancel('POWER HIGH');return
        self.elapsed+=1
        if self.elapsed==60:
            self.delta=self.end_hr-self.mean();self.collecting=False;self.reason='READY'
