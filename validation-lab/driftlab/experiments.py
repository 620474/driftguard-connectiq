"""Managed one-factor experiments; no factorial search."""
from dataclasses import replace, asdict
from .oracle import Config, Engine, halves


def configs():
    base=Config()
    yield 'current',base
    for field,values in dict(warmup=[0,10,15,20,30],recovery=[0,1,2,3],median=['current','prior','rolling60','fixed'],
                             band=[10,15,20,25],valid=[42,48,54],mismatch=[2,3,5,7.5,10]).items():
        for value in values:
            c=replace(base,**{field:value})
            if c!=base:
                yield f'{field}_{value}',c


def compare(samples, suite=False):
    out={}
    for name,c in configs() if suite else [('current',Config())]:
        e=Engine(c)
        for s in samples:
            e.add(s['power'],s['hr'],s['running'])
        total=sum(m['valid_seconds'] for m in e.minutes if m['steady'])
        done=0
        for m in e.minutes:
            n=m['valid_seconds'] if m['steady'] else 0
            share=max(0,min(1,(total/2-done)/n)) if n else 0
            m['first_half_share']=share if n else None
            m['second_half_share']=1-share if n else None
            # Additive sufficient statistics, not an invented per-minute drift.
            m['first_power_contribution']=m['power_sum']*share if n else 0
            m['second_power_contribution']=m['power_sum']*(1-share) if n else 0
            done+=n
        out[name]=dict(config=asdict(c),summary=e.result,minutes=e.minutes,partial_seconds=len(e.pending),bucket_width=e.ride.width)
    active=[s for s in samples if s['running']]
    def classic(positive=False,clock=False):
        rows=[]
        for s in active:
            p,h=s['power'],s['hr']
            valid=p is not None and p>=0 and h is not None and h>0 and (not positive or p>0)
            rows.append((p if valid else 0,h if valid else 0,1 if valid else 0))
        if clock:
            cut=len(rows)//2
            halves_rows=[tuple(sum(r[i] for r in part) for i in range(3)) for part in (rows[:cut],rows[cut:])]
            a,b=halves_rows
            return (1-(b[0]/b[1])/(a[0]/a[1]))*100 if a[0] and a[1] and b[1] else None
        r=halves(rows)
        return r[0] if r else None
    # Exploratory slope of HR/P versus running time; no physiological adjustment.
    points=[(i,s['hr']/s['power']) for i,s in enumerate(active) if s['power'] is not None and s['power']>0 and s['hr'] is not None and s['hr']>0]
    slope=None
    if len(points)>1:
        x=sum(p[0] for p in points)/len(points); y=sum(p[1] for p in points)/len(points)
        den=sum((a-x)**2 for a,b in points)
        slope=sum((a-x)*(b-y) for a,b in points)/den*3600 if den else None
    return dict(models=out,alternatives=dict(classic_valid_time=classic(),classic_clock=classic(clock=True),positive_only=classic(True),hr_per_watt_slope_per_hour=slope))


def minute_diff(a,b):
    return [dict(minute=x['minute'],a=x['reason'],b=y['reason']) for x,y in zip(a['minutes'],b['minutes']) if x['steady']!=y['steady']]
