"""Reproducible archive audit. Run after lab analyze --suite; does not mutate production."""
import argparse,csv,json,math,statistics,html,os,base64,time
from pathlib import Path
from collections import Counter,defaultdict
from datetime import datetime
from urllib.request import Request,urlopen,build_opener,HTTPRedirectHandler
from urllib.error import HTTPError,URLError
from urllib.parse import urlencode
from driftlab.oracle import halves
from driftlab.fitio import normalize

ROOT=Path(__file__).resolve().parent

def env_values():
    values={}
    if (ROOT/'.env').exists():
        for line in (ROOT/'.env').read_text('utf-8-sig').splitlines():
            k,sep,v=line.partition('=')
            if sep:values[k.strip()]=v.strip().strip('\"\'')
    return {**values,**os.environ}


def stats(values):
    a=[x for x in values if x is not None and math.isfinite(x)]
    return dict(n=len(a),median=statistics.median(a) if a else None,min=min(a) if a else None,max=max(a) if a else None)


def cv(a):
    return statistics.pstdev(a)/statistics.mean(a) if len(a)>1 and statistics.mean(a)>0 else None


def drift(rows):
    r=halves(rows)
    return r[0] if r else None


def intervals(root,since,until):
    e=env_values();key=e.get('INTERVALS_API_KEY');athlete=e.get('INTERVALS_ATHLETE_ID','0') or '0'
    if not key:return dict(status='not_configured',activities=[])
    if not athlete.isalnum():return dict(status='invalid_athlete_id',activities=[])
    # GET only. Never forward Basic credentials on a redirect.
    class NoRedirect(HTTPRedirectHandler):
        def redirect_request(self,*args,**kwargs):raise RuntimeError('Intervals redirect refused')
    url='https://intervals.icu/api/v1/athlete/'+athlete+'/activities?'+urlencode(dict(oldest=since[:10],newest=until[:10]))
    req=Request(url,headers={'Authorization':'Basic '+base64.b64encode(('API_KEY:'+key).encode()).decode(),'User-Agent':'DriftGuard-Validation-Lab/0.1','Accept':'application/json'})
    for attempt in range(3):
        try:
            with build_opener(NoRedirect()).open(req,timeout=60) as response:
                raw=response.read(30*1024*1024+1)
                if len(raw)>30*1024*1024:raise RuntimeError('Intervals response too large')
                activities=json.loads(raw)
                if not isinstance(activities,list):raise RuntimeError('Intervals schema unexpected')
                (root/'intervals-activities.json').write_text(json.dumps(activities),encoding='utf-8')
                return dict(status='downloaded',activities=activities)
        except HTTPError as exc:
            if exc.code in (429,500,502,503,504) and attempt<2:time.sleep(2**attempt);continue
            return dict(status='http_'+str(exc.code),activities=[])
        except (URLError,TimeoutError,ValueError,RuntimeError):
            if attempt<2:time.sleep(2**attempt);continue
            return dict(status='network_or_schema_error',activities=[])


def audit(root):
    source=json.loads((root/'results.json').read_text('utf-8'));activities=source['activities'];out=root/'research';out.mkdir(exist_ok=True)
    manifest=json.loads((root/'sync.json').read_text('utf-8'))
    # Map archive content hash to stable Garmin ID, never expose a key.
    ids={entry['sha256']:aid for aid,entries in manifest.items() for entry in entries}
    cohort=[];segments=[];comparisons=[];dg=[];all_reasons=Counter();quality=Counter();sensor=Counter();metadata=Counter()
    for index,a in enumerate(activities):
        key=a['id'];current=a.get('models',{}).get('current')
        if not current:continue
        minutes=current['minutes'];quality[a['quality']['status']]+=1
        messages=json.loads((root/'analysis'/(key+'_decoded.json')).read_text('utf-8'))
        records=[m['fields'] for m in messages if m['type']=='record']
        events=[m['fields'] for m in messages if m['type']=='event' and m['fields'].get('event')=='timer']
        # Decoded export timestamps are ISO strings. Restore before normalization.
        for row in records+events:
            if row.get('timestamp'):row['timestamp']=datetime.fromisoformat(row['timestamp'])
        samples,_=normalize(records,events)
        active=[s for s in samples if s['running']]
        causes=Counter()
        for s in active:
            p,h=s['power'],s['hr']
            category='missing_hr' if h is None or h<=0 else 'missing_power' if p is None else 'zero_power' if p==0 else 'negative_power' if p<0 else 'valid'
            causes[category]+=1
        sensor.update(causes)
        reasons=Counter(m['reason'] for m in minutes);all_reasons.update(reasons)
        insufficient=Counter();recovery_origins=Counter();trigger=None;accepted_cv=[]
        for mi,m in enumerate(minutes):
            if m['steady']:
                values=[s['power'] for s in active[mi*60:(mi+1)*60] if s['power'] is not None and s['power']>0 and s['hr'] is not None and s['hr']>0]
                value=cv(values)
                if value is not None:accepted_cv.append(value)
            if m['reason']=='insufficient valid seconds':
                chunk=active[mi*60:(mi+1)*60]
                coast=sum(s['power']==0 and s['hr'] is not None and s['hr']>0 for s in chunk)
                missing=sum(s['power'] is None or s['hr'] is None or s['hr']<=0 for s in chunk)
                insufficient['coasting_dominant' if coast>missing else 'missing_dominant_or_tied']+=1
            if m['reason'] in ('insufficient valid seconds','power out of band'):trigger=m['reason']
            elif m['reason']=='recovery after unstable minute':recovery_origins[trigger or 'unknown']+=1
        post=minutes[15:];powers=[m['power'] for m in post if m['power'] is not None]
        mean_cv=cv(powers);n=len(post);late=post[n//2:];early=post[:n//2]
        cov=lambda rows:sum(m['steady'] for m in rows)/len(rows)*100 if rows else None
        raw_uncompressed=drift([(m['power_sum'],m['hr_sum'],m['valid_seconds']) for m in post if m['steady']])
        comp=current['summary']['ride']['drift']
        tags=[]
        if len(active)>=4*3600:tags.append('long')
        if len(samples)-len(active)>600:tags.append('pauses')
        if mean_cv is not None and mean_cv<=.10:tags.append('low_minute_power_variation')
        if mean_cv is not None and mean_cv>=.25:tags.append('variable_power')
        if causes['missing_power']+causes['missing_hr']>len(active)*.05:tags.append('sensor_gaps')
        cohort.append(dict(id=key,garmin_id=ids.get(key),start=a['start'],quality=a['quality']['status'],minutes=len(minutes),
            active_seconds=len(active),paused_seconds=len(samples)-len(active),power_cv=mean_cv,early_coverage=cov(early),late_coverage=cov(late),
            ride_state=current['summary']['ride']['state'],ride_drift=comp,last60=current['summary']['last60']['drift'],
            coverage=current['summary']['coverage'],compat=current['summary']['compat'],classic_clock=a['alternatives']['classic_clock'],
            compression_error_pp=comp-raw_uncompressed if comp is not None and raw_uncompressed is not None else None,
            tags=tags,causes=dict(causes),reasons=dict(reasons),insufficient_minute_causes=dict(insufficient),recovery_origins=dict(recovery_origins),accepted_second_power_cv=stats(accepted_cv),accepted_cv_over_30=sum(v>.30 for v in accepted_cv)))
        for name,model in a['models'].items():
            if name=='current':continue
            other=model['minutes'];intersect=[i for i,(m,v) in enumerate(zip(minutes,other)) if m['steady'] and v['steady']]
            common_a=drift([(minutes[i]['power_sum'],minutes[i]['hr_sum'],minutes[i]['valid_seconds']) for i in intersect])
            common_b=drift([(other[i]['power_sum'],other[i]['hr_sum'],other[i]['valid_seconds']) for i in intersect])
            # Shared minute support must have the same arithmetic, independent of model validity gates.
            if common_a is not None and abs(common_a-common_b)>1e-9:raise AssertionError('Common-support arithmetic differs')
            b=model['summary'];base=current['summary'];d0=base['ride']['drift'];d1=b['ride']['drift']
            comparisons.append(dict(id=key,model=name,base_state=base['ride']['state'],state=b['ride']['state'],
                newly_valid=base['ride']['state']!='VALID' and b['ride']['state']=='VALID',
                lost_valid=base['ride']['state']=='VALID' and b['ride']['state']!='VALID',
                coverage_delta=b['coverage']-base['coverage'],drift_delta_pp=d1-d0 if d1 is not None and d0 is not None else None,
                included=sum(not m['steady'] and v['steady'] for m,v in zip(minutes,other)),
                excluded=sum(m['steady'] and not v['steady'] for m,v in zip(minutes,other)),common_minutes=len(intersect),common_drift=common_a))
        # Prespecified non-overlapping workload screens; no HR is used for admission.
        # Not physiological ground truth and not an independently annotated steady label.
        for begin in range(15,len(minutes)-29,30):
            block=minutes[begin:begin+30];pp=[m['power'] for m in block]
            if any(m['valid_seconds']<54 for m in block) or any(p is None for p in pp):continue
            ref=statistics.median(pp)
            if ref<=0 or cv(pp)>.10 or any(abs(p/ref-1)>.15 for p in pp):continue
            result=halves([(m['power_sum'],m['hr_sum'],m['valid_seconds']) for m in block])
            if result is None or abs(result[2])>3:continue
            chosen=[m for m in block if m['steady']]
            selected=drift([(m['power_sum'],m['hr_sum'],m['valid_seconds']) for m in chosen]) if len(chosen)>=10 else None
            segments.append(dict(id=key,start_minute=begin+1,end_minute=begin+30,quality=a['quality']['status'],power_cv=cv(pp),
                power_change=result[2],all_drift=result[0],accepted_minutes=len(chosen),selected_drift=selected,
                selection_delta_pp=selected-result[0] if selected is not None else None,
                reasons=dict(Counter(m['reason'] for m in block))))
        sessions=[m['fields'] for m in messages if m['type']=='session']
        fields={k:v for session in sessions for k,v in session.items() if k.startswith('dg_')}
        if fields:
            expected={'WARMUP':0,'COLLECTING':1,'NOT_STEADY':2,'POWER_CHANGED':3,'VALID':4}[current['summary']['ride']['state']]
            recorded_state=fields.get('dg_ride_state_final')
            dg.append(dict(id=key,start=a['start'],recorded_state=recorded_state,oracle_state=expected,state_match=recorded_state==expected,
                recorded_drift=fields.get('dg_ride_drift_final'),oracle_drift=comp,
                drift_delta_pp=comp-fields['dg_ride_drift_final'] if comp is not None and recorded_state==4 and isinstance(fields.get('dg_ride_drift_final'),(int,float)) else None,
                recorded_coverage=fields.get('dg_steady_percent'),oracle_coverage=current['summary']['coverage'],
                recorded_compat=fields.get('dg_compat_drift'),oracle_compat=current['summary']['compat'],
                compat_delta_pp=current['summary']['compat']-fields['dg_compat_drift'] if current['summary']['compat'] is not None and isinstance(fields.get('dg_compat_drift'),(int,float)) else None,
                dg_record_count=sum('dg_steady' in r for r in records),quality=a['quality']['status']))
        for m in messages:
            metadata[m['type']]+=1
        if (index+1)%20==0:print('Research audited',index+1,flush=True)
    models=[]
    for name in sorted({c['model'] for c in comparisons}):
        rows=[c for c in comparisons if c['model']==name]
        models.append(dict(model=name,valid=sum(c['state']=='VALID' for c in rows),newly_valid=sum(c['newly_valid'] for c in rows),
            lost_valid=sum(c['lost_valid'] for c in rows),coverage_delta=stats([c['coverage_delta'] for c in rows]),
            drift_delta_pp=stats([c['drift_delta_pp'] for c in rows]),changed_rides=sum(bool(c['included'] or c['excluded']) for c in rows),
            included_minutes=sum(c['included'] for c in rows),excluded_minutes=sum(c['excluded'] for c in rows)))
    # Deterministic case selection: unique rides, explicit ranking, no outcome-based physiological labels.
    picks=[];used=set()
    def pick(reason,rows,number=3):
        for row in rows:
            if row['id'] not in used:
                picks.append(dict(id=row['id'],reason=reason));used.add(row['id'])
                if sum(p['reason']==reason for p in picks)>=number:break
    pick('low power variability',sorted([c for c in cohort if c['power_cv'] is not None and c['minutes']>=55],key=lambda c:c['power_cv']))
    lookup={c['id']:c for c in cohort}
    pick('recovery changes availability',[lookup[c['id']] for c in sorted([c for c in comparisons if c['model']=='recovery_0' and c['newly_valid']],key=lambda c:-c['included'])])
    pick('long ride',sorted(cohort,key=lambda c:-c['minutes']),2)
    pick('pause burden',sorted(cohort,key=lambda c:-c['paused_seconds']),2)
    pick('recorded DriftGuard fields',[lookup[c['id']] for c in dg],2)
    pick('variable power',sorted([c for c in cohort if c['power_cv'] is not None],key=lambda c:-c['power_cv']),2)
    external=intervals(out,source['since'],source['until'])
    matched=[]
    for c in cohort:
        candidates=[v for v in external['activities'] if str(v.get('external_id',''))==str(c['garmin_id']) or str(v.get('external_id',''))=='garmin_'+str(c['garmin_id'])]
        # Exact external ID only. Timestamp proximity alone is not enough to equate inputs.
        for v in candidates:
            matched.append(dict(id=c['id'],intervals_id=v.get('id'),external_id=v.get('external_id'),
                                decoupling=v.get('decoupling'),oracle_compat=c['compat'],classic_clock=c['classic_clock'],
                                delta_compat_pp=c['compat']-v['decoupling'] if isinstance(v.get('decoupling'),(int,float)) and c['compat'] is not None else None,
                                delta_classic_pp=c['classic_clock']-v['decoupling'] if isinstance(v.get('decoupling'),(int,float)) and c['classic_clock'] is not None else None))
    summary=dict(period=[source['since'],source['until']],activities=len(cohort),quality=dict(quality),states=dict(Counter(c['ride_state'] for c in cohort)),
        reasons=dict(all_reasons),sensor_seconds=dict(sensor),models=models,workload_screen_segments=len(segments),
        segment_selection_delta_pp=stats([s['selection_delta_pp'] for s in segments]),recorded_dg_activities=len(dg),
        recorded_dg_state_matches=sum(d['state_match'] for d in dg),dg_drift_delta_pp=stats([d['drift_delta_pp'] for d in dg]),
        dg_compat_delta_pp=stats([d['compat_delta_pp'] for d in dg]),compression_error_pp=stats([c['compression_error_pp'] for c in cohort]),
        intervals_status=external['status'],intervals_matches=len(matched),intervals_compat_delta_pp=stats([m['delta_compat_pp'] for m in matched]),intervals_classic_delta_pp=stats([m['delta_classic_pp'] for m in matched]))
    result=dict(summary=summary,cohort=cohort,comparisons=comparisons,segments=segments,device_comparisons=dg,cases=picks,intervals_matches=matched)
    (out/'research.json').write_text(json.dumps(result,ensure_ascii=False,allow_nan=False,indent=2),encoding='utf-8')
    for name,rows in [('cohort',cohort),('models',models),('comparisons',comparisons),('segments',segments),('device_comparisons',dg),('cases',picks),('intervals_matches',matched)]:
        if rows:
            with (out/(name+'.csv')).open('w',encoding='utf-8-sig',newline='') as f:
                w=csv.DictWriter(f,fieldnames=list(rows[0]));w.writeheader();w.writerows(rows)
    print(json.dumps(summary,ensure_ascii=True),flush=True)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--data',type=Path,default=ROOT/'.data');args=p.parse_args();audit(args.data)
