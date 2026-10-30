import Toybox.Activity;
import Toybox.Lang;
import Toybox.Test;
import Toybox.WatchUi;

(:test)
function intervalBoundariesAndMissingPower(logger as Test.Logger) as Boolean {
    var e = new IntervalEngine();
    e.addSample(300, true);
    Test.assertEqual(e.sequence, 0);
    e.boundary(false);
    e.addSample(300, true); e.addSample(0, true); e.addSample(null, true);
    e.addSample(900, false); e.addSample(-1, true);
    Test.assertEqual(e.seconds, 4); Test.assertEqual(e.validPower, 2);
    Test.assertEqual(e.powerSum, 300.0f); Test.assertEqual(e.meanPower() as Float, 150.0f);
    e.boundary(false);
    Test.assertEqual(e.sequence, 2); Test.assertEqual(e.lastSeconds, 4);
    Test.assertEqual(e.lastMean as Float, 150.0f); Test.assert(e.lastInterrupted);
    Test.assert(e.meanPower() == null);
    e.boundary(false); Test.assertEqual(e.sequence, 2);
    e.startWorkout(); e.addSample(200, true); e.boundary(false);
    Test.assertEqual(e.sequence, 1); Test.assertEqual(e.seconds, 1);
    e.boundary(true); Test.assertEqual(e.sequence, 2);
    e.reset(); Test.assertEqual(e.sequence, 0); Test.assert(e.lastMean == null);
    return true;
}

(:test)
function intervalCallbacksAndIndependentScreens(logger as Test.Logger) as Boolean {
    var f = new DriftGuardView(false);
    f.onTimerReset();
    f.onTimerLap2({:lapTrigger => WatchUi.DataField.LAP_TRIGGER_DISTANCE});
    Test.assertEqual(f.intervals.sequence, 0);
    f.onTimerLap2({:lapTrigger => WatchUi.DataField.LAP_TRIGGER_MANUAL});
    var info = new Activity.Info();
    info.currentPower = 240; info.currentHeartRate = 120;
    info.timerState = Activity.TIMER_STATE_ON;
    f.compute(info); f.toggleScreen(); f.compute(info);
    Test.assertEqual(f.intervals.seconds, 2);
    Test.assertEqual(f.intervals.powerSum, 480.0f);
    f.onWorkoutStarted(); f.onWorkoutStepComplete();
    Test.assertEqual(f.intervals.sequence, 1);
    f.compute(info); f.onWorkoutStepComplete();
    Test.assertEqual(f.intervals.sequence, 2);
    f.onTimerReset(); Test.assertEqual(f.intervals.sequence, 0);
    Test.assertEqual(f.intervals.seconds, 0);
    return true;
}

(:test)
function intervalLateLoadAndReset(logger as Test.Logger) as Boolean {
    var e = new IntervalEngine();
    e.boundary(true); Test.assertEqual(e.source, "WORKOUT");
    Test.assertEqual(e.sequence, 1); Test.assert(e.meanPower() == null);
    e.addSample(null, true); e.boundary(true);
    Test.assert(e.lastMean == null); Test.assertEqual(e.lastSeconds, 1);
    e.addSample(100, true); e.reset();
    Test.assertEqual(e.seconds, 0); Test.assert(e.lastMean == null);
    return true;
}
