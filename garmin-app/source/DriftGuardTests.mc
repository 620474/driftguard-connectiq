import Toybox.Activity;
import Toybox.Lang;
import Toybox.Test;

// ---- Live readings -------------------------------------------------------

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

// ---- Drift engine --------------------------------------------------------

(:test)
function driftWaitsForWarmupThenReportsRideDrift(logger as Test.Logger) as Boolean {
    var defaultEngine = new DriftEngine(null);
    addMinutes(defaultEngine, 14, 200, 100);
    Test.assertEqual(defaultEngine.getState(METRIC_RIDE), DRIFT_WARMUP);
    Test.assertEqual(defaultEngine.getState(METRIC_LAST_60), DRIFT_WARMUP);
    Test.assertEqual(defaultEngine.getWarmupElapsedSeconds(), 14 * 60);
    addMinutes(defaultEngine, 1, 200, 100);
    Test.assertEqual(defaultEngine.getState(METRIC_RIDE), DRIFT_COLLECTING);
    Test.assertEqual(defaultEngine.getSteadySeconds(), 0);

    // First half efficiency = 2.00; second half efficiency = 1.80; drift = 10.0%.
    var engine = new DriftEngine(0);
    addMinutes(engine, 20, 200, 100);
    addMinutes(engine, 19, 180, 100);
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_COLLECTING);
    Test.assertEqual(engine.getProgressMinutes(METRIC_RIDE), 39);
    addMinutes(engine, 1, 180, 100);
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent(METRIC_RIDE) as Float).format("%.1f"), "10.0");
    Test.assertEqual((engine.getBaselineEfficiency(METRIC_RIDE) as Float).format("%.2f"), "2.00");
    Test.assertEqual(engine.getBand(METRIC_RIDE) as DriftBand, BAND_HIGH);
    Test.assertEqual(engine.getState(METRIC_LAST_60), DRIFT_COLLECTING);
    Test.assertEqual(engine.getProgressMinutes(METRIC_LAST_60), 40);
    return true;
}

(:test)
function driftKeepsUpdatingOnLongRide(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    addMinutes(engine, 20, 200, 100);
    addMinutes(engine, 20, 180, 100);
    addMinutes(engine, 40, 170, 100);
    // Ride halves: 20x2.00 + 20x1.80 = 1.90 vs 40x1.70 = 1.70 -> 10.5%.
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent(METRIC_RIDE) as Float).format("%.1f"), "10.5");
    // Last 60: 20x1.80 + 10x1.70 = 1.767 vs 30x1.70 = 1.70 -> 3.8%.
    Test.assertEqual(engine.getState(METRIC_LAST_60), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent(METRIC_LAST_60) as Float).format("%.1f"), "3.8");
    Test.assertEqual(engine.getBand(METRIC_LAST_60) as DriftBand, BAND_STABLE);
    return true;
}

(:test)
function driftExcludesClimbAndHeartRateRecovery(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    addMinutes(engine, 20, 200, 100);
    // A 5-minute climb, then 2 minutes at normal power with HR still elevated.
    addMinutes(engine, 5, 320, 150);
    addMinutes(engine, 2, 200, 130);
    addMinutes(engine, 20, 200, 100);
    Test.assertEqual(engine.getSteadySeconds(), 40 * 60);
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent(METRIC_RIDE) as Float).format("%.1f"), "0.0");

    var history = engine.getHistory();
    Test.assert(history.isSteady(19));
    Test.assert(!history.isSteady(20));
    Test.assert(!history.isSteady(26));
    Test.assert(history.isSteady(27));
    return true;
}

(:test)
function driftIgnoresPausedTimer(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    addMinutes(engine, 20, 200, 100);
    // A long cafe stop with the timer paused is neither valid nor invalid data.
    addSeconds(engine, 30 * 60, 0, 90, false);
    addMinutes(engine, 20, 180, 100);
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_VALID);
    Test.assertEqual((engine.getDriftPercent(METRIC_RIDE) as Float).format("%.1f"), "10.0");
    Test.assertEqual(engine.getSteadySeconds(), 40 * 60);
    return true;
}

(:test)
function driftTreatsCoastingMinuteAsNotSteady(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    addMinutes(engine, 1, 200, 100);
    // 20 s of coasting in a minute exceeds the 20% allowance.
    addSeconds(engine, 40, 200, 100, true);
    addSeconds(engine, 20, 0, 100, true);
    // Missing HR counts the same as coasting.
    addSeconds(engine, 40, 200, 100, true);
    addSeconds(engine, 20, 200, null, true);
    var history = engine.getHistory();
    Test.assert(history.isSteady(0));
    Test.assert(!history.isSteady(1));
    Test.assert(!history.isSteady(2));
    // The chart still shows the coasting minute from its valid seconds.
    Test.assertEqual((history.getPoint(1) as Float).format("%.2f"), "2.00");
    return true;
}

(:test)
function driftReportsHillyRideAsNotSteady(logger as Test.Logger) as Boolean {
    var engine = new DriftEngine(0);
    // 3 minutes steady, 2 minutes climbing, repeated: few minutes stay steady.
    for (var cycle = 0; cycle < 13; cycle += 1) {
        addMinutes(engine, 3, 200, 120);
        addMinutes(engine, 2, 320, 150);
    }
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_NOT_STEADY);
    Test.assert(engine.getDriftPercent(METRIC_RIDE) == null);
    Test.assert(engine.getSteadyPercent() < 70);
    Test.assertEqual(engine.getState(METRIC_LAST_60), DRIFT_NOT_STEADY);
    Test.assert(engine.getDriftPercent(METRIC_LAST_60) == null);
    return true;
}

(:test)
function rideBucketsMergeWithoutChangingResult(logger as Test.Logger) as Boolean {
    // Capacity 4 stands in for the engine's 240 so a "6 h ride" stays small.
    var buckets = new RideBuckets(4);
    for (var i = 0; i < 16; i += 1) {
        buckets.addMinute(i < 8 ? 12000 : 10800, 6000, 60);
    }
    Test.assertEqual(buckets.getCount(), 4);
    Test.assertEqual(buckets.getMinutesPerBucket(), 4);
    var result = buckets.drift() as Array<Float>;
    Test.assertEqual(result[0].format("%.1f"), "10.0");
    Test.assertEqual(result[1].format("%.2f"), "2.00");

    buckets.reset();
    Test.assert(buckets.drift() == null);
    Test.assertEqual(buckets.getMinutesPerBucket(), 1);
    return true;
}

(:test)
function historyKeepsLastHourAndComputesItsDrift(logger as Test.Logger) as Boolean {
    var history = new EfficiencyHistory();
    // 15 minutes that scroll out of the window, then 30 at 2.00 and 30 at 1.80.
    for (var i = 0; i < 15; i += 1) {
        history.addMinute(6000, 6000, 60, true);
    }
    for (var i = 0; i < 60; i += 1) {
        history.addMinute(i < 30 ? 12000 : 10800, 6000, 60, true);
    }
    Test.assertEqual(history.getSize(), 60);
    Test.assertEqual((history.getPoint(0) as Float).format("%.2f"), "2.00");
    Test.assertEqual((history.getLatest() as Float).format("%.2f"), "1.80");
    Test.assertEqual(history.getSteadyMinutes(), 60);
    var result = history.drift() as Array<Float>;
    Test.assertEqual(result[0].format("%.1f"), "10.0");

    // Under 30 valid seconds is a chart gap; a non-steady minute is not in the drift.
    history.addMinute(2000, 1000, 20, false);
    Test.assert(history.getLatest() == null);
    Test.assert(!history.isSteady(59));
    Test.assertEqual(history.getSteadyMinutes(), 59);

    history.reset();
    Test.assertEqual(history.getSize(), 0);
    return true;
}

// ---- View state ----------------------------------------------------------

(:test)
function driftResetsForNextActivity(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var engine = field.driftEngine;
    addMinutes(engine, 60, 200, 100);
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_VALID);

    field.onTimerReset();
    Test.assertEqual(engine.getState(METRIC_RIDE), DRIFT_WARMUP);
    Test.assertEqual(engine.getState(METRIC_LAST_60), DRIFT_WARMUP);
    Test.assert(engine.getDriftPercent(METRIC_RIDE) == null);
    Test.assertEqual(engine.getSteadySeconds(), 0);
    Test.assertEqual(engine.getHistory().getSize(), 0);
    Test.assertEqual(field.driftTextFor(METRIC_RIDE), "--");
    return true;
}

(:test)
function tapTogglesMainMetric(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var start = field.metric;
    field.toggleMetric();
    Test.assert(field.metric != start);
    field.toggleMetric();
    Test.assertEqual(field.metric, start);
    return true;
}

(:test)
function labelsAndFormatting(logger as Test.Logger) as Boolean {
    Test.assertEqual(DriftEngine.bandFor(-3.0f), BAND_STABLE);
    Test.assertEqual(DriftEngine.bandFor(4.9f), BAND_STABLE);
    Test.assertEqual(DriftEngine.bandFor(5.0f), BAND_WATCH);
    Test.assertEqual(DriftEngine.bandFor(9.9f), BAND_WATCH);
    Test.assertEqual(DriftEngine.bandFor(10.0f), BAND_HIGH);

    var field = new DriftGuardView();
    Test.assertEqual(field.stateTitle(METRIC_RIDE), "WARMING UP");
    Test.assertEqual(field.summaryText(METRIC_LAST_60), "WARM-UP");
    Test.assertEqual(field.durationText(2 * 3600 + 27 * 60 + 59), "2:27");
    Test.assertEqual(field.durationText(0), "0:00");
    Test.assertEqual(field.metricName(METRIC_LAST_60), "LAST 60");
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

// ---- Helpers -------------------------------------------------------------

function addMinutes(engine as DriftEngine, minutes as Number, power as Number,
                    heartRate as Number) as Void {
    addSeconds(engine, minutes * 60, power, heartRate, true);
}

function addSeconds(engine as DriftEngine, count as Number, power as Number?,
                    heartRate as Number?, isTimerRunning as Boolean) as Void {
    for (var i = 0; i < count; i += 1) {
        engine.addSample(power, heartRate, isTimerRunning);
    }
}
