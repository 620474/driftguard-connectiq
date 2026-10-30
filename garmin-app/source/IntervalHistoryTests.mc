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
    var info=new Activity.Info();info.timerState=Activity.TIMER_STATE_ON;info.currentPower=100;info.currentHeartRate=140;
    for (var i=0;i<60;i+=1) { field.compute(info); }
    info.currentPower=300;
    for (var j=0;j<20;j+=1) { field.compute(info); }
    field.onUpdate(bmp.getDc());
    info.currentPower=null;field.compute(info);field.onUpdate(bmp.getDc());
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
