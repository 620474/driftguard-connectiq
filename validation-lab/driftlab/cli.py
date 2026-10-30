import argparse
import csv
import hashlib
import json
import sys
import unittest
from datetime import datetime
from pathlib import Path
from dateutil.relativedelta import relativedelta
from .archive import atomic,digest,sync_import
from .fitio import read_fit
from .experiments import compare,minute_diff


def save(path,value):
    atomic(path,json.dumps(value,ensure_ascii=False,default=str,allow_nan=False).encode('utf-8'))


def fingerprint():
    h=hashlib.sha256()
    for p in sorted(Path(__file__).parent.glob('*.py')):
        h.update(p.read_bytes())
    return h.hexdigest()


def analyze(root,suite=False,months=6):
    archive=root/'archive'; dest=root/'analysis'; dest.mkdir(parents=True,exist_ok=True)
    now=datetime.now().astimezone(); since=now-relativedelta(months=months)
    results=[]
    for path in sorted(archive.glob('*.fit')):
        key=digest(path)
        cache=dest/(key+'.json')
        signature=f'{fingerprint()}:{suite}'
        if cache.exists():
            result=json.loads(cache.read_text('utf-8'))
            if result.get('signature')==signature:
                stamp=result.get('start')
                if stamp is None or since.date()<=datetime.fromisoformat(stamp).date()<=now.date():
                    results.append(result)
                continue
        result=dict(id=key,signature=signature,start=None)
        try:
            samples,quality,messages=read_fit(path)
            result.update(quality=quality,start=samples[0]['timestamp'] if samples else None)
            if samples:
                date=datetime.fromisoformat(samples[0]['timestamp']).date()
                if date<since.date() or date>now.date():
                    continue
            save(dest/(key+'_decoded.json'),messages)
            if quality['status']!='unsupported':
                result.update(compare(samples,suite))
                base=result['models']['current']
                result['filter_differences']={k:minute_diff(base,v) for k,v in result['models'].items() if k!='current'}
        except Exception as exc:
            result['quality']=dict(status='corrupt_or_unsupported',issues=[type(exc).__name__+': '+str(exc)])
        save(cache,result); results.append(result)
    save(root/'results.json',dict(since=since.isoformat(),until=now.isoformat(),activities=results))
    return results


def report(root):
    data=json.loads((root/'results.json').read_text('utf-8'))
    out=root/'report'; out.mkdir(parents=True,exist_ok=True)
    save(out/'results.json',data)
    with (out/'summary.csv').open('w',newline='',encoding='utf-8-sig') as f:
        w=csv.writer(f); w.writerow(['id','quality','model','ride_state','ride_drift','last60','compat','coverage','power_change','classic_clock'])
        for a in data['activities']:
            for name,v in a.get('models',{}).items():
                s=v['summary'];w.writerow([a['id'],a['quality']['status'],name,s['ride']['state'],s['ride']['drift'],s['last60']['drift'],s['compat'],s['coverage'],s['ride']['power_change'],a['alternatives']['classic_clock']])
            for name,v in a.get('models',{}).items():
                if not v['minutes']: continue
                with (out/(a['id']+'_'+name+'_minutes.csv')).open('w',newline='',encoding='utf-8-sig') as mf:
                    mw=csv.DictWriter(mf,fieldnames=list(v['minutes'][0]));mw.writeheader();mw.writerows(v['minutes'])
    display=dict(data)
    display['activities']=[]
    for activity in data['activities']:
        item={k:v for k,v in activity.items() if k not in ('samples','messages')}
        item['models']={}
        for name,model in activity.get('models',{}).items():
            visible=dict(model)
            visible['minutes']=[{k:v for k,v in m.items() if k in ('minute','power','hr','steady','reason','ride_drift')} for m in model['minutes']]
            item['models'][name]=visible
        display['activities'].append(item)
    payload=json.dumps(display,ensure_ascii=False,default=str,separators=(',',':')).replace('<','\\u003c')
    template=(Path(__file__).parent/'report.html').read_text('utf-8')
    atomic(out/'index.html',template.replace('__DATA__',payload).encode('utf-8'))
    return out/'index.html'


def main(argv=None):
    p=argparse.ArgumentParser(description='DriftGuard local validation')
    p.add_argument('command',choices=['sync','analyze','compare','report','run','test'])
    p.add_argument('--data',type=Path,default=Path(__file__).resolve().parents[1]/'.data')
    p.add_argument('--import-dir',type=Path)
    p.add_argument('--offline',action='store_true')
    p.add_argument('--suite',action='store_true')
    p.add_argument('--months',type=int,default=6)
    a=p.parse_args(argv)
    if not 1 <= a.months <= 120: p.error('--months must be between 1 and 120')
    a.data.mkdir(parents=True,exist_ok=True)
    if a.command=='test':
        tests=unittest.defaultTestLoader.discover(str(Path(__file__).resolve().parents[1]/'tests'))
        return 0 if unittest.TextTestRunner(verbosity=2).run(tests).wasSuccessful() else 1
    if a.command in ('sync','run'):
        if a.import_dir:
            if not a.import_dir.is_dir(): p.error('--import-dir must exist')
            print('Imported',sync_import(a.import_dir,a.data/'archive'))
        elif not a.offline:
            from .garmin import sync
            try:
                print('Downloaded',sync(a.data,months=a.months))
            except RuntimeError as exc:
                print(str(exc),file=sys.stderr)
                return 2
    if a.command in ('analyze','compare','run'):
        print('Analyzed',len(analyze(a.data,a.suite or a.command=='compare',a.months)))
    if a.command in ('report','run'):
        if not (a.data/'results.json').exists(): p.error('run analyze first')
        print(report(a.data))
    return 0


if __name__=='__main__':
    raise SystemExit(main())
