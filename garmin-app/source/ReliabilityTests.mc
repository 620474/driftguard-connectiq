import Toybox.Lang;
import Toybox.Test;

(:test)
function rejectHiddenIntervals(logger as Test.Logger) as Boolean {
    var e=new DriftEngine(0);e.experimentalCV=true;
    for(var i=0;i<3600;i+=1){e.addSample(i%2==0 ? 100 : 300,140,true);}
    Test.assertEqual(e.getSteadySeconds(),0);
    Test.assertEqual(e.getState(METRIC_RIDE),DRIFT_NOT_STEADY);
    Test.assertEqual(e.getState(METRIC_LAST_60),DRIFT_NOT_STEADY);
    return true;
}
(:test)
function resumeRejectsJoinedMinute(logger as Test.Logger) as Boolean {
    var e=new DriftEngine(0);
    for(var i=0;i<30;i+=1){e.addSample(200,140,true);}
    e.addSample(200,140,false);
    for(var j=0;j<210;j+=1){e.addSample(200,140,true);}
    Test.assertEqual(e.getMinutes(),4);Test.assertEqual(e.getSteadySeconds(),0);
    for(var k=0;k<60;k+=1){e.addSample(200,140,true);}
    Test.assertEqual(e.getSteadySeconds(),60);
    return true;
}
(:test)
function lastValidSurvivesInvalidButNotReset(logger as Test.Logger) as Boolean {
    var e=new DriftEngine(0);
    for(var i=0;i<2400;i+=1){e.addSample(200,140,true);}
    Test.assert(e.lastValidDrift!=null);Test.assertEqual(e.lastValidMinute,40);
    for(var j=0;j<1200;j+=1){e.addSample(0,140,true);}
    Test.assert(e.getDriftPercent(METRIC_RIDE)==null);
    Test.assertEqual(e.lastValidMinute,57);
    e.reset();Test.assert(e.lastValidDrift==null);Test.assertEqual(e.lastValidMinute,0);
    return true;
}
(:test)
function rejectCorruptSensors(logger as Test.Logger) as Boolean {
    var e=new DriftEngine(0);
    for(var i=0;i<60;i+=1){e.addSample(200,400,true);}
    Test.assertEqual(e.getSteadySeconds(),0);
    Test.assert(e.getCompatDriftPercent()==null);
    return true;
}
(:test)
function durationBoundaryHasNoCliff(logger as Test.Logger) as Boolean {
    for(var n=239;n<=241;n+=1){
        var e=new IntervalSession();
        for(var i=0;i<60;i+=1){e.addSample(100,true);}
        for(var j=0;j<n;j+=1){e.addSample(300,true);}
        for(var k=0;k<5;k+=1){e.addSample(100,true);}
        Test.assertEqual(e.lastSeconds,n);Test.assertEqual(e.completionId,1);
        Test.assertEqual(e.lastEndSeconds,60+n);Test.assertEqual(e.lastValidPower,n);
    }
    return true;
}
(:test)
function lowBaselineTailAndShortSprint(logger as Test.Logger) as Boolean {
    var e=new AutoEffortEngine();e.experimental=true;
    for(var i=0;i<60;i+=1){e.addSample(40,true);}
    for(var j=0;j<4;j+=1){e.addSample(210,true);}
    for(var k=0;k<40;k+=1){e.addSample(90,true);}
    Test.assert(!e.active);Test.assert(e.lastMean==null);
    e.reset();
    for(var a=0;a<60;a+=1){e.addSample(100,true);}
    for(var b=0;b<8;b+=1){e.addSample(700,true);}
    for(var c=0;c<5;c+=1){e.addSample(100,true);}
    Test.assert(e.lastMean==null);
    return true;
}
(:test)
function workoutCompletionIdentityAndCoverage(logger as Test.Logger) as Boolean {
    var e=new IntervalSession();var recorder=new ProductionRecorder(null);
    e.startWorkout();
    for(var i=0;i<60;i+=1){e.addSample(i<30 ? 300 : null,true);}
    e.boundary(true);var first=recorder.effortMarker(e);
    Test.assertEqual(e.lastSeconds,60);Test.assertEqual(e.lastValidPower,30);
    Test.assertEqual(e.lastMean as Float,300.0f);Test.assert(e.lastInterrupted);
    e.startWorkout();
    for(var j=0;j<60;j+=1){e.addSample(300,true);}
    e.boundary(true);
    Test.assert(!first.equals(recorder.effortMarker(e)));Test.assertEqual(e.completionId,2);
    Test.assertEqual(e.lastEndSeconds,120);Test.assert(!e.lastInterrupted);
    e.boundary(true);Test.assertEqual(e.completionId,2);
    e.reset();Test.assertEqual(e.completionId,0);
    return true;
}
(:test)
function autoPauseCompletionClock(logger as Test.Logger) as Boolean {
    var e=new IntervalSession();
    for(var i=0;i<60;i+=1){e.addSample(100,true);}
    for(var j=0;j<20;j+=1){e.addSample(300,true);}
    e.addSample(100,false);
    Test.assertEqual(e.lastEndSeconds,80);Test.assert(e.lastInterrupted);
    Test.assertEqual(e.completionId,1);
    e.addSample(100,false);Test.assertEqual(e.completionId,1);
    return true;
}
(:test)
function activeRecoveryHasContext(logger as Test.Logger) as Boolean {
    var r=new HeartRecovery();
    for(var i=0;i<3;i+=1){r.sample(160,300,true);}
    r.begin(0,300.0f,60);r.parentId=7;
    for(var j=0;j<60;j+=1){r.sample(140,200,true);}
    Test.assert(r.delta==null);Test.assertEqual(r.activeDelta as Float,20.0f);
    Test.assertEqual(r.meanRecoveryPower() as Float,200.0f);Test.assertEqual(r.parentId,7);
    r.cancel("NEW EFFORT");Test.assertEqual(r.parentId,0);Test.assert(r.activeDelta==null);
    return true;
}
