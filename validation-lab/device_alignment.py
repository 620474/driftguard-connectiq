"""Diagnostics for device/FIT clock alignment. Fitted offsets are not validation."""
import json,statistics
from pathlib import Path
from datetime import datetime
from collections import Counter
from driftlab.fitio import normalize
from driftlab.oracle import Engine
root=Path(__file__).resolve().parent/'.data';r=json.loads((root/'research/research.json').read_text('utf8'));out=[]
for d in r['device_comparisons']:
 messages=json.loads((root/'analysis'/(d['id']+'_decoded.json')).read_text('utf8'))
 records=[m['fields'] for m in messages if m['type']=='record'];events=[m['fields'] for m in messages if m['type']=='event' and m['fields'].get('event')=='timer']
 for row in records+events:
  if row.get('timestamp'):row['timestamp']=datetime.fromisoformat(row['timestamp'])
 samples,_=normalize(records,events);active=[s for s in samples if s['running']];positions={s['timestamp']:i for i,s in enumerate(active)}
 e=Engine();snapshots=[]
 for s in active:
  before=len(e.minutes);e.add(s['power'],s['hr'])
  if len(e.minutes)>before:snapshots.append(e.result['compat'])
 transitions=[];last=None
 for rec in records:
  value=rec.get('dg_ef')
  if value is not None and value!=last:
   pos=positions.get(rec['timestamp'].isoformat())
   if pos is not None:transitions.append((pos,value))
   last=value
 first=next((i for i,v in transitions if v>0),None)
 ef_errors=[];gaps=[]
 for i,v in transitions:
  if v<=0 or i<59:continue
  pairs=[(s['power'],s['hr']) for s in active[i-59:i+1] if s['power'] is not None and s['power']>0 and s['hr'] is not None and s['hr']>0]
  if len(pairs)>=30:ef_errors.append(abs(sum(p for p,h in pairs)/sum(h for p,h in pairs)-v))
 for (i,v),(j,w) in zip(transitions,transitions[1:]):
  if v>0 and w>0:gaps.append(j-i)
 target=d['recorded_compat'];valid=[(abs(v-target),i+1,v) for i,v in enumerate(snapshots) if v is not None and isinstance(target,(int,float))]
 best=min(valid) if valid else None
 out.append(dict(id=d['id'],first_positive_ef_running_second=first+1 if first is not None else None,ef_transition_count=len(transitions),
   ef_transition_gaps=dict(Counter(gaps)),median_observed_window_ef_error=statistics.median(ef_errors) if ef_errors else None,
   best_compat_snapshot=dict(error_pp=best[0],minute=best[1],value=best[2]) if best else None,complete_minutes=len(snapshots)))
(root/'research/device_alignment.json').write_text(json.dumps(out,indent=2),encoding='utf8')
for v in out:print(json.dumps({**v,'id':v['id'][:12]}))
