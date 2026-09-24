import Toybox.Activity;
import Toybox.Lang;
import Toybox.Test;

(:test)
function liveReadings(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    Test.assertEqual(field.ratioText, "--");
    var info = new Activity.Info();
    info.currentPower = 247;
    info.currentHeartRate = 151;
    field.compute(info);
    Test.assertEqual(field.powerText, "247 W");
    Test.assertEqual(field.heartRateText, "151 bpm");
    Test.assertEqual(field.ratioText, "1.64");

    info.currentPower = 0;
    field.compute(info);
    Test.assertEqual(field.powerText, "0 W");
    Test.assertEqual(field.ratioText, "0.00");

    info.currentHeartRate = 0;
    field.compute(info);
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");
    return true;
}

(:test)
function missingReadings(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var info = new Activity.Info();
    info.currentPower = 247;
    info.currentHeartRate = 151;
    field.compute(info);
    info.currentHeartRate = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "247 W");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");

    info.currentPower = null;
    info.currentHeartRate = 151;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "151 bpm");
    Test.assertEqual(field.ratioText, "--");

    info.currentHeartRate = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");

    info.currentPower = -1;
    info.currentHeartRate = -1;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");
    return true;
}

(:test)
function driftIgnoresWarmupAndCalculatesKnownValue(logger as Test.Logger) as Boolean {
    var defaultEngine = new DriftEngine(null);
    defaultEngine.addSample(15 * 60 * 1000 - 1, 250, 100, 5.0f, true);
    Test.assertEqual(defaultEngine.getValidSamples(), 0);
    defaultEngine.addSample(15 * 60 * 1000, 250, 100, 5.0f, true);
    Test.assertEqual(defaultEngine.getValidSamples(), 1);

    var engine = new DriftEngine(1000);
    engine.addSample(999, 250, 100, 5.0f, true);
    Test.assertEqual(engine.getValidSamples(), 0);
    Test.assertEqual(engine.getValidityState(), "NOT_READY");

    // First half efficiency = 2.00; second half efficiency = 1.80; drift = 10.0%.
    addSamples(engine, 900, 1000, 200, 100, 5.0f, true);
    addSamples(engine, 900, 2000, 180, 100, 5.0f, true);
    Test.assertEqual(engine.getValidityState(), "VALID");
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "10.0");
    return true;
}

(:test)
function driftIgnoresInvalidSamplesWithoutChangingKnownValue(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // These must not become efficiency samples.
    addSamples(engine, 36, 0, null, 100, 5.0f, true);
    addSamples(engine, 36, 100, 200, null, 5.0f, true);
    addSamples(engine, 36, 200, 0, 100, 5.0f, false);
    addSamples(engine, 36, 300, 0, 100, 0.0f, true);
    addSamples(engine, 36, 400, 0, 100, 5.0f, true);

    addSamples(engine, 900, 500, 200, 100, 5.0f, true);
    addSamples(engine, 900, 1400, 180, 100, 5.0f, true);
    Test.assertEqual(engine.getValidSamples(), 1800);
    Test.assertEqual(engine.getValidityState(), "VALID");
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "10.0");
    return true;
}

(:test)
function driftRejectsSparseSteadyPeriod(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // A stopped 30-minute segment followed by valid data reaches the sample count,
    // but only half of the observed post-warm-up data is valid.
    addSamples(engine, 1800, 0, 200, 100, 5.0f, false);
    addSamples(engine, 900, 1800, 200, 100, 5.0f, true);
    addSamples(engine, 900, 2700, 180, 100, 5.0f, true);
    Test.assertEqual(engine.getValidityState(), "NOT_STEADY");
    Test.assert(engine.getDriftPercent() == null);
    return true;
}

(:test)
function driftRejectsHighlyVariablePower(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // The full period is present, but its 50% power step exceeds the 15% CV limit.
    addSamples(engine, 450, 0, 100, 100, 5.0f, true);
    addSamples(engine, 450, 450, 300, 100, 5.0f, true);
    addSamples(engine, 900, 900, 180, 100, 5.0f, true);
    Test.assertEqual(engine.getValidityState(), "NOT_STEADY");
    Test.assert(engine.getDriftPercent() == null);
    return true;
}

function addSamples(engine as DriftEngine, count as Number, startElapsed as Number,
                    power as Number?, heartRate as Number?, speed as Float?,
                    isTimerRunning as Boolean) as Void {
    for (var i = 0; i < count; i += 1) {
        engine.addSample(startElapsed + i, power, heartRate, speed, isTimerRunning);
    }
}
