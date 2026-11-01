"""Seeded workload schedules define truth before either detector sees samples."""
from math import exp
from random import Random


def protocol(name='steady', seconds=7200, drift=0,
             tau=40, noise=.04, seed=20261101, ftp=250):
    rng = Random(seed)
    truth = []
    if name == 'repeats':
        truth = [dict(start=1200 + i * 360, end=1439 + i * 360)
                 for i in range(5)]
    if name == 'climb':
        truth = [dict(start=1200, end=1919)]
    if name == 'sprints':
        truth = [dict(start=1200 + i * 120, end=1214 + i * 120)
                 for i in range(6)]
    power_state = .8 * ftp
    err = 0
    samples = []
    for t in range(seconds):
        p = .8 * ftp
        if name in ('plus4', 'minus4', 'minus8') and t >= seconds // 2:
            p *= dict(plus4=1.04, minus4=.96, minus8=.92)[name]
        if name in ('repeats', 'sprints'):
            p = .4 * ftp
        if any(v['start'] <= t <= v['end'] for v in truth):
            p = 1.2 * ftp if name == 'repeats' else 2.4 * ftp if name == 'sprints' else ftp
        if name == 'hills':
            p = .76 * ftp + (60 if (t % 240) < 75 else 0)
        err = .8 * err + rng.gauss(0, noise * .6)
        p = max(0, round(p * (1 + err)))
        power_state = p if not tau else power_state + \
            (1 - exp(-1 / tau)) * (p - power_state)
        h = 60 + .4 * power_state + drift * t / 3600
        if name == 'nonlinear':
            h += .001 * max(0, p - 180)**2
        if name == 'temperature':
            h += 10 * min(1, max(0, (t - 3600) / 600))
        running = not (name == 'pause' and 2500 <= t < 2800)
        if name == 'gaps' and 2500 <= t < 2530:
            p = None
        samples.append(dict(power=p, hr=round(h), running=running))
    return samples, truth


def suite():
    for hours in (2, 3, 5):
        yield f'linear_{hours}h', dict(seconds=hours * 3600, drift=4, noise=0), 4
    for name in ('plus4', 'minus4', 'minus8'):
        yield name, dict(name=name, drift=0, noise=0), 0
    for name in ('steady', 'repeats', 'climb', 'sprints', 'hills',
                 'pause', 'gaps', 'nonlinear', 'temperature'):
        yield name, dict(name=name, seconds=7200, drift=4 if name in ('pause', 'gaps') else 0,
                         noise=.12 if name == 'hills' else .04), None
