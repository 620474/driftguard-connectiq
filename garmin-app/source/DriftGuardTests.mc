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
    Test.assertEqual(field.powerText, "247");
    Test.assertEqual(field.heartRateText, "151");
    // Pw:HR is shown per full minute, never per second.
    Test.assertEqual(field.ratioText, "--");

    // Zero power (coasting) is a real reading and enters the 3 s average.
    info.currentPower = 0;
    field.compute(info);
    Test.assertEqual(field.powerText, "124");

    info.currentHeartRate = 0;
    field.compute(info);
    Test.assertEqual(field.heartRateText, "--");
    Test.assert(field.heartRate == null);
    return true;
}

(:test)
function powerIsAveragedOverThreeSeconds(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var info = new Activity.Info();
    info.currentHeartRate = 140;
    var readings = [200, 210, 220, 230] as Array<Number>;
    for (var i = 0; i < readings.size(); i += 1) {
        info.currentPower = readings[i];
        field.compute(info);
    }
    Test.assertEqual(field.powerText, "220");
    Test.assertEqual(field.power3s as Number, 220);

    // A dropout clears the value and restarts the average without stale readings.
    info.currentPower = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assert(field.power3s == null);
    info.currentPower = 100;
    field.compute(info);
    Test.assertEqual(field.powerText, "100");
    return true;
}

(:test)
function ratioShowsLastFullMinute(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var info = new Activity.Info();
    info.timerState = Activity.TIMER_STATE_ON;
    info.timerTime = 0;
    info.currentPower = 200;
    info.currentHeartRate = 100;
    for (var i = 0; i < 59; i += 1) {
        field.compute(info);
    }
    Test.assertEqual(field.ratioText, "--");
    field.compute(info);
    Test.assertEqual(field.ratioText, "2.00");

    field.onTimerReset();
    Test.assertEqual(field.ratioText, "--");
    return true;
}

(:test)
function zonesMapValuesOntoEqualWidthGauge(logger as Test.Logger) as Boolean {
    // Garmin HR format: min zone 1, then the max of each of 5 zones.
    var heartRateZones = [100, 120, 140, 155, 170, 190] as Array<Number>;
    Test.assertEqual(Zones.zoneIndex(90, heartRateZones), 0);
    Test.assertEqual(Zones.zoneIndex(120, heartRateZones), 0);
    Test.assertEqual(Zones.zoneIndex(121, heartRateZones), 1);
    Test.assertEqual(Zones.zoneIndex(200, heartRateZones), 4);
    Test.assertEqual(Zones.position(90, heartRateZones).format("%.2f"), "0.00");
    Test.assertEqual(Zones.position(130, heartRateZones).format("%.2f"), "0.30");
    Test.assertEqual(Zones.position(250, heartRateZones).format("%.2f"), "1.00");

    Test.assert(Zones.validated(null) == null);
    Test.assert(Zones.validated([100, 120] as Array<Number>) == null);
    Test.assert(Zones.validated([100, 140, 120] as Array<Number>) == null);
    Test.assert(Zones.validated(heartRateZones) != null);

    var powerZones = Zones.fromFtp(250);
    Test.assertEqual(powerZones.size(), 8);
    Test.assertEqual(powerZones[1], 137);
    Test.assertEqual(powerZones[2], 187);
    Test.assertEqual(Zones.zoneIndex(180, powerZones), 1);
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
    Test.assertEqual(field.powerText, "247");
    Test.assertEqual(field.heartRateText, "--");

    info.currentPower = null;
    info.currentHeartRate = 151;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "151");

    info.currentHeartRate = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");

    info.currentPower = -1;
    info.currentHeartRate = -1;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");
    Test.assert(field.power3s == null);
    Test.assert(field.heartRate == null);
    return true;
}

(:test)
function driftIgnoresWarmupAndCalculatesKnownValue(logger as Test.Logger) as Boolean {
    var defaultEngine = new DriftEngine(null);
    defaultEngine.addSample(15 * 60 * 1000 - 1, 250, 100, true);
    Test.assertEqual(defaultEngine.getState(), DRIFT_WARMUP);
    Test.assertEqual(defaultEngine.getValidSamples(), 0);
    defaultEngine.addSample(15 * 60 * 1000, 250, 100, true);
    Test.assertEqual(defaultEngine.getState(), DRIFT_COLLECTING);
    Test.assertEqual(defaultEngine.getValidSamples(), 1);

    var engine = new DriftEngine(1000);
    engine.addSample(999, 250, 100, true);
    Test.assertEqual(engine.getValidSamples(), 0);
    Test.assertEqual(engine.getWarmupElapsedMs(), 999);

    // First half efficiency = 2.00; second half efficiency = 1.80; drift = 10.0%.
    addSamples(engine, 900, 1000, 200, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_COLLECTING);
    addSamples(engine, 900, 2000, 180, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "10.0");
    Test.assertEqual(engine.getBand() as DriftBand, BAND_HIGH);
    return true;
}

(:test)
function driftStaysValidForTheRestOfTheRide(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    addSamples(engine, 900, 0, 200, 100, true);
    addSamples(engine, 900, 900, 188, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);

    // Hours of later riding, coasting, dropouts and pauses must not change the result.
    addSamples(engine, 3600, 1800, 0, 100, true);
    addSamples(engine, 600, 5400, null, null, true);
    addSamples(engine, 600, 6000, 400, 170, false);
    addSamples(engine, 3600, 6600, 120, 150, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "6.0");
    Test.assertEqual(engine.getBand() as DriftBand, BAND_WATCH);
    return true;
}

(:test)
function driftIgnoresInvalidSamplesWithoutChangingKnownValue(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // Missing power, missing HR and coasting count against quality but not efficiency.
    addSamples(engine, 100, 0, null, 100, true);
    addSamples(engine, 100, 100, 200, null, true);
    addSamples(engine, 100, 200, 0, 100, true);

    addSamples(engine, 900, 300, 200, 100, true);
    addSamples(engine, 900, 1200, 180, 100, true);
    Test.assertEqual(engine.getValidSamples(), 1800);
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "10.0");
    return true;
}

(:test)
function driftIgnoresPausedTimer(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // A long cafe stop with the timer paused is neither valid nor invalid data.
    addSamples(engine, 450, 0, 200, 100, true);
    addSamples(engine, 1800, 450, 0, 100, false);
    addSamples(engine, 450, 450, 200, 100, true);
    addSamples(engine, 900, 900, 180, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "10.0");
    return true;
}

(:test)
function driftRejectsSparsePeriodAndStartsOver(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // More than 20% coasting while collecting fails the 80% quality gate.
    addSamples(engine, 600, 0, 200, 100, true);
    addSamples(engine, 451, 600, 0, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_NOT_STEADY);
    Test.assert(engine.getDriftPercent() == null);
    Test.assertEqual(engine.getValidSamples(), 0);

    // A clean new period produces a result from that period only.
    addSamples(engine, 900, 1051, 200, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_NOT_STEADY);
    addSamples(engine, 900, 1951, 196, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "2.0");
    Test.assertEqual(engine.getBand() as DriftBand, BAND_STABLE);
    return true;
}

(:test)
function driftRejectsHighlyVariablePower(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // The full period is present, but its sustained 3x power step is not steady.
    addSamples(engine, 450, 0, 100, 100, true);
    addSamples(engine, 450, 450, 300, 100, true);
    addSamples(engine, 900, 900, 180, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_NOT_STEADY);
    Test.assert(engine.getDriftPercent() == null);
    return true;
}

(:test)
function driftAcceptsSecondToSecondPowerNoise(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // 150/250 W alternating each second is 25% CV at 1 Hz but steady at 30 s.
    for (var i = 0; i < 1800; i += 1) {
        engine.addSample(i, i % 2 == 0 ? 150 : 250, 100, true);
    }
    Test.assertEqual(engine.getState(), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent() as Float).format("%.1f"), "0.0");
    return true;
}

(:test)
function driftResetsForNextActivity(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var engine = field.driftEngine;
    addSamples(engine, 900, 15 * 60 * 1000, 200, 100, true);
    addSamples(engine, 900, 15 * 60 * 1000 + 900, 180, 100, true);
    Test.assertEqual(engine.getState(), DRIFT_VALID);

    field.onTimerReset();
    Test.assertEqual(engine.getState(), DRIFT_WARMUP);
    Test.assert(engine.getDriftPercent() == null);
    Test.assertEqual(engine.getValidSamples(), 0);
    Test.assertEqual(engine.getWarmupElapsedMs(), 0);
    Test.assertEqual(field.driftText, "--");
    return true;
}

(:test)
function driftBandsAndTitles(logger as Test.Logger) as Boolean {
    Test.assertEqual(DriftEngine.bandFor(-3.0f), BAND_STABLE);
    Test.assertEqual(DriftEngine.bandFor(4.9f), BAND_STABLE);
    Test.assertEqual(DriftEngine.bandFor(5.0f), BAND_WATCH);
    Test.assertEqual(DriftEngine.bandFor(9.9f), BAND_WATCH);
    Test.assertEqual(DriftEngine.bandFor(10.0f), BAND_HIGH);

    var field = new DriftGuardView();
    Test.assertEqual(field.stateTitle(), "WARMING UP");
    return true;
}

(:test)
function historyRecordsMinutePwHrWithGaps(logger as Test.Logger) as Boolean {
    var history = new EfficiencyHistory();
    addHistorySamples(history, 59, 200, 100, true);
    Test.assertEqual(history.getSize(), 0);
    // Paused seconds do not complete a minute.
    addHistorySamples(history, 300, 200, 100, false);
    Test.assertEqual(history.getSize(), 0);
    addHistorySamples(history, 1, 200, 100, true);
    Test.assertEqual(history.getSize(), 1);
    Test.assertEqual((history.getPoint(0) as Float).format("%.2f"), "2.00");

    // Under 30 valid seconds (mostly coasting) is a gap, not a point.
    addHistorySamples(history, 29, 180, 100, true);
    addHistorySamples(history, 31, 0, 100, true);
    Test.assertEqual(history.getSize(), 2);
    Test.assert(history.getPoint(1) == null);

    // Coasting inside an otherwise valid minute does not dilute the ratio.
    addHistorySamples(history, 40, 180, 100, true);
    addHistorySamples(history, 20, 0, 100, true);
    Test.assertEqual((history.getPoint(2) as Float).format("%.2f"), "1.80");
    return true;
}

(:test)
function historyKeepsLastHourAndResets(logger as Test.Logger) as Boolean {
    var history = new EfficiencyHistory();
    for (var minute = 0; minute < 75; minute += 1) {
        addHistorySamples(history, 60, 100 + minute, 100, true);
    }
    Test.assertEqual(history.getSize(), 60);
    Test.assertEqual((history.getPoint(0) as Float).format("%.2f"), "1.15");
    Test.assertEqual((history.getPoint(59) as Float).format("%.2f"), "1.74");

    history.reset();
    Test.assertEqual(history.getSize(), 0);
    return true;
}

(:test)
function driftExposesBaselineEfficiency(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    Test.assert(engine.getBaselineEfficiency() == null);
    addSamples(engine, 900, 0, 200, 100, true);
    addSamples(engine, 900, 900, 180, 100, true);
    Test.assertEqual((engine.getBaselineEfficiency() as Float).format("%.2f"), "2.00");
    engine.reset();
    Test.assert(engine.getBaselineEfficiency() == null);
    return true;
}

function addHistorySamples(history as EfficiencyHistory, count as Number, power as Number?,
                           heartRate as Number?, isTimerRunning as Boolean) as Void {
    for (var i = 0; i < count; i += 1) {
        history.addSample(power, heartRate, isTimerRunning);
    }
}

function addSamples(engine as DriftEngine, count as Number, startTimer as Number,
                    power as Number?, heartRate as Number?, isTimerRunning as Boolean) as Void {
    for (var i = 0; i < count; i += 1) {
        engine.addSample(startTimer + i, power, heartRate, isTimerRunning);
    }
}
