import Toybox.Lang;
import Toybox.Test;
import Toybox.Graphics;
import Toybox.Activity;
(:test)
function intervalHistoryWrapGapsAndReset(logger as Test.Logger) as Boolean {
    var h=new IntervalHistory();
    for (var i=0;i<200;i+=1) { h.add(i,140,true); }
    Test.assertEqual(h.size,180); Test.assertEqual(h.point(0,false) as Number,20);
    h.add(0,null,true);Test.assertEqual(h.point(179,false) as Number,0);Test.assert(h.point(179,true)==null);
    h.add(300,160,false);Test.assert(h.point(179,false)==null);Test.assert(h.point(179,true)==null);
    h.reset();Test.assertEqual(h.size,0);Test.assert(h.point(0,false)==null);
    return true;
}
(:test)
function intervalsFullRenderingSmoke(logger as Test.Logger) as Boolean {
    var ref=Graphics.createBufferedBitmap({:width=>480,:height=>800,:palette=>[Graphics.COLOR_WHITE,Graphics.COLOR_BLACK,Graphics.COLOR_LT_GRAY,0x2F7FE0]});
    var bmp=ref.get() as Graphics.BufferedBitmap;
    var field=new DriftGuardView(false);field.onTimerReset();field.intervalScreen=true;
    field.onUpdate(bmp.getDc());
    field.intervalScreen=false;field.onUpdate(bmp.getDc());field.intervalScreen=true;
    var info=new Activity.Info();info.timerState=Activity.TIMER_STATE_ON;info.currentPower=100;info.currentHeartRate=140;
    for (var i=0;i<60;i+=1) { field.compute(info); }
    info.currentPower=300;
    for (var j=0;j<20;j+=1) { field.compute(info); }
    field.onUpdate(bmp.getDc());
    field.intervalScreen=false;field.onUpdate(bmp.getDc());field.intervalScreen=true;
    info.currentPower=null;field.compute(info);field.onUpdate(bmp.getDc());
    field.intervalScreen=false;field.onUpdate(bmp.getDc());
    field.onTimerReset();Test.assertEqual(field.intervalHistory.size,0);
    return true;
}

(:test)
function intervalDurationsRetainSeconds(logger as Test.Logger) as Boolean {
    var view=new DriftGuardView(false);
    Test.assertEqual(view.intervalDurationText(30),"0:30");
    Test.assertEqual(view.intervalDurationText(90),"1:30");
    Test.assertEqual(view.intervalDurationText(5400),"1:30:00");
    Test.assertEqual(view.durationText(5400),"1:30");
    return true;
}

(:test)
function recorderCompletionIdentityIgnoresNextAutoStart(logger as Test.Logger) as Boolean {
    var session=new IntervalSession(); var recorder=new ProductionRecorder(null);
    for (var i=0;i<60;i+=1) { session.addSample(100,true); }
    for (var j=0;j<20;j+=1) { session.addSample(300,true); }
    for (var k=0;k<5;k+=1) { session.addSample(100,true); }
    var completed=recorder.effortMarker(session);
    for (var n=0;n<3;n+=1) { session.addSample(300,true); }
    Test.assert(session.automatic.active);
    Test.assertEqual(recorder.effortMarker(session),completed);
    for (var a=0;a<17;a+=1) { session.addSample(300,true); }
    for (var b=0;b<5;b+=1) { session.addSample(100,true); }
    Test.assert(!recorder.effortMarker(session).equals(completed));
    session.reset();session.boundary(false);
    session.addSample(200,true);session.boundary(false);
    var manual=recorder.effortMarker(session);
    session.addSample(200,true);session.boundary(false);
    Test.assert(!recorder.effortMarker(session).equals(manual));
    return true;
}

(:test)
function adaptiveSplitsTempoSurgeAndRejectsEasyReturn(logger as Test.Logger) as Boolean {
    var e=new AutoEffortEngine();e.experimental=true;
    for(var i=0;i<60;i+=1){e.addSample(100,true);}
    for(var j=0;j<180;j+=1){e.addSample(200,true);}
    for(var k=0;k<3;k+=1){e.addSample(280,true);}
    Test.assertEqual(e.lastSeconds,180);Test.assertEqual(e.lastMean as Float,200.0f);
    Test.assertEqual(e.seconds,3);Test.assert(e.active);
    for(var n=0;n<57;n+=1){e.addSample(280,true);}
    for(var a=0;a<5;a+=1){e.addSample(200,true);}
    Test.assertEqual(e.lastSeconds,60);Test.assertEqual(e.lastMean as Float,280.0f);
    Test.assert(!e.active);
    e.reset();
    for(var b=0;b<60;b+=1){e.addSample(0,true);}
    for(var c=0;c<90;c+=1){e.addSample(120,true);}
    Test.assert(!e.active);Test.assertEqual(e.sequence,0);
    e.addSample(null,true);Test.assertEqual(e.historyCount,0);
    return true;
}
