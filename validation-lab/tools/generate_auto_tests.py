from pathlib import Path
import json
from driftlab.auto_efforts import Detector
p=Path(__file__).resolve().parents[2]
streams=[('repeats',[(100,True)]*60+([(300,True)]*30+[(100,True)]*30)*3),('coast_gap',[(100,True)]*60+[(300,True)]*10+[(0,True)]*2+[(300,True)]*10+[(100,True)]*5),('dropouts',[(100,True)]*60+[(300,True)]*20+[(None,True)]+[(100,True)]*60+[(300,True)]*20+[(100,False)]),('spikes',[(100,True)]*60+([(400,True)]+[(100,True)]*10)*6),('over_under',[(100,True)]*60+([(300,True)]*20+[(200,True)]*20)*3+[(100,True)]*5)]
code=['import Toybox.Lang;','import Toybox.Test;','import Toybox.Activity;']
for ix,(name,rows) in enumerate(streams):
 code+=['(:test)',f'function liveAutoParity{ix}(logger as Test.Logger) as Boolean {{','var e=new AutoEffortEngine();']
 d=Detector();last=None;seq=0
 for tick,(power,running) in enumerate(rows):
  was=d.active is not None;result=d.sample(tick,power,running)
  if not was and d.active is not None:seq+=1
  if result is not None:last=result
  code.append('e.addSample('+('null' if power is None else str(power))+','+str(running).lower()+');')
  if tick%20==0 or result is not None or tick==len(rows)-1:
   active=d.active
   code+=['Test.assertEqual(e.active,'+str(active is not None).lower()+');',f'Test.assertEqual(e.sequence,{seq});',f'Test.assertEqual(e.seconds,{active["seconds"] if active else 0});']
   if active:code.append(f'Test.assert(e.powerSum >= {float(active["power_sum"])-0.5}f && e.powerSum <= {float(active["power_sum"])+0.5}f);')
   if last:
    code +=[f'Test.assertEqual(e.lastSeconds,{last["seconds"]});',f'Test.assertEqual(e.lastStart,{last["start"]});',f'Test.assertEqual(e.lastEnd,{last["end"]});',f'Test.assertEqual(e.detectedEnd,{last["detected_end"]});','Test.assertEqual(e.lastPartial,'+str(last['partial']).lower()+');',f'Test.assert((e.lastMean as Float)>={last["mean_power"]-0.01}f && (e.lastMean as Float)<={last["mean_power"]+0.01}f);']
 code+=['return true;','}']
code+=['''(:test)
function liveAutoSourcePriority(logger as Test.Logger) as Boolean {
    var s=new IntervalSession();
    Test.assert(s.source.equals("AUTO"));
    for (var i=0;i<60;i+=1) { s.addSample(100,true); }
    for (var j=0;j<20;j+=1) { s.addSample(300,true); }
    Test.assertEqual(s.seconds,20);
    s.boundary(false);
    Test.assert(s.source.equals("MANUAL")); Test.assertEqual(s.seconds,0);
    s.addSample(250,true); Test.assertEqual(s.seconds,1);
    s.startWorkout(); Test.assert(s.source.equals("WORKOUT"));
    s.boundary(false); Test.assertEqual(s.seconds,0);
    s.addSample(220,true); s.boundary(true); Test.assertEqual(s.lastSeconds,1);
    s.reset(); Test.assert(s.source.equals("AUTO")); Test.assertEqual(s.automatic.historyCount,0);
    var f=new DriftGuardView(false); f.onTimerReset();
    var info=new Activity.Info(); info.timerState=Activity.TIMER_STATE_ON;
    info.currentHeartRate=100; info.currentPower=100;
    for (var k=0;k<60;k+=1) { f.compute(info); }
    f.toggleScreen(); info.currentPower=300;
    for (var n=0;n<20;n+=1) { f.compute(info); }
    Test.assertEqual(f.intervals.seconds,20);
    return true;
}''']
(p/'garmin-app/source/AutoEffortTests.mc').write_text('\n'.join(code)+'\n',encoding='utf8')
print('Generated parity streams',len(streams),'samples',sum(len(r) for _,r in streams))
