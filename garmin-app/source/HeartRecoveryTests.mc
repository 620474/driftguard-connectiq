import Toybox.Activity;
import Toybox.Lang;
import Toybox.Test;
(:test)
function recoveryBoundariesAndGuards(logger as Test.Logger) as Boolean {
    var r=new HeartRecovery();
    for (var i=0;i<3;i+=1) { r.sample(160,300,true); }
    for (var j=0;j<5;j+=1) { r.sample(150,100,true); }
    r.begin(5,300.0f,30); Test.assertEqual(r.elapsed,5);
    for (var k=0;k<54;k+=1) { r.sample(130,100,true); }
    Test.assert(r.delta==null); r.sample(130,100,true);
    Test.assertEqual(r.delta as Float,30.0f); Test.assertEqual(r.elapsed,60);
    r.reset(); Test.assert(r.delta==null);
    for (var n=0;n<3;n+=1) { r.sample(150,300,true); }
    r.begin(0,300.0f,30); r.sample(140,151,true);
    Test.assert(r.reason.equals("POWER HIGH")); Test.assert(r.delta==null);
    r.begin(0,300.0f,30); r.sample(null,100,true);
    Test.assert(r.reason.equals("HR MISSING"));
    r.reset(); r.begin(0,300.0f,30); Test.assert(r.endHr==null);
    for (var z=0;z<3;z+=1) { r.sample(140,0,true); }
    r.begin(0,0.0f,30); Test.assert(r.reason.equals("NEED EFFORT"));
    return true;
}
(:test)
function recoverySignedPauseAndCancellation(logger as Test.Logger) as Boolean {
    var r=new HeartRecovery();
    for (var i=0;i<3;i+=1) { r.sample(140,300,true); }
    r.begin(0,300.0f,30);
    for (var j=0;j<60;j+=1) { r.sample(145,100,true); }
    Test.assertEqual(r.delta as Float,-5.0f);
    r.cancel("NEW EFFORT"); Test.assert(r.delta==null);
    r.begin(0,300.0f,30); r.sample(120,100,false);
    Test.assert(r.reason.equals("PAUSED")); Test.assert(!r.collecting);
    return true;
}

(:test)
function recoveryAutoIntegration(logger as Test.Logger) as Boolean {
    var f=new DriftGuardView(false); f.onTimerReset();
    var info=new Toybox.Activity.Info(); info.timerState=Toybox.Activity.TIMER_STATE_ON;
    info.currentPower=100; info.currentHeartRate=140;
    for (var i=0;i<60;i+=1) { f.compute(info); }
    info.currentPower=300; info.currentHeartRate=160;
    for (var j=0;j<30;j+=1) { f.compute(info); }
    info.currentPower=100; info.currentHeartRate=150;
    for (var k=0;k<5;k+=1) { f.compute(info); }
    Test.assertEqual(f.recovery.elapsed,5);
    info.currentHeartRate=130;
    for (var n=0;n<55;n+=1) { f.compute(info); }
    Test.assertEqual(f.recovery.delta as Float,30.0f);
    f.onTimerReset(); Test.assert(f.recovery.delta==null);
    return true;
}

(:test)
function recoveryUsesThreeSecondWindows(logger as Test.Logger) as Boolean {
    var r=new HeartRecovery();
    r.sample(150,300,true);r.sample(153,300,true);r.sample(156,300,true);
    r.begin(0,300.0f,30);
    for (var i=0;i<57;i+=1) { r.sample(110,100,true); }
    r.sample(120,100,true);r.sample(123,100,true);r.sample(126,100,true);
    Test.assertEqual(r.delta as Float,30.0f);
    Test.assertEqual(r.compactText(),"HRR60 +30");
    return true;
}

(:test)
function recoveryExactBoundaryOrders(logger as Test.Logger) as Boolean {
    for(var order=0;order<2;order+=1){
        var f=new DriftGuardView(false);
        f.onWorkoutStarted();
        var info=new Activity.Info();info.timerState=Activity.TIMER_STATE_ON;
        info.currentPower=300;info.currentHeartRate=160;
        for(var i=0;i<30;i+=1){f.compute(info);}
        f.onWorkoutStepComplete();
        info.currentPower=100;info.currentHeartRate=130;
        for(var j=0;j<59;j+=1){f.compute(info);}
        var completed=new HeartRecovery();
        if(order==0){
            f.onWorkoutStepComplete();completed=f.terminalRecovery as HeartRecovery;f.compute(info);
        } else {
            f.compute(info);completed=f.recovery.terminalCopy();f.onWorkoutStepComplete();
        }
        Test.assertEqual(completed.parentId,1);Test.assertEqual(completed.delta as Float,30.0f);
        Test.assert(f.terminalRecovery==null);
    }
    return true;
}
(:test)
function variabilityIsExperimentalByDefault(logger as Test.Logger) as Boolean {
    var e=new DriftEngine(0);
    for(var i=0;i<60;i+=1){e.addSample(i%2==0 ? 100 : 300,140,true);}
    Test.assert(!e.experimentalCV);Test.assertEqual(e.getSteadySeconds(),60);
    return true;
}
