import Toybox.Lang;

enum DriftState {
    DRIFT_WARMUP,
    DRIFT_COLLECTING,
    DRIFT_NOT_STEADY,
    // Enough steady data, but the halves were ridden at different power, so the
    // Pw:HR ratio would show drift that is only a change of effort.
    DRIFT_POWER_CHANGED,
    DRIFT_VALID
}

// Ordered from lowest to highest drift; hysteresis relies on this order.
enum DriftBand {
    BAND_NEGATIVE,
    BAND_STABLE,
    BAND_WATCH,
    BAND_HIGH
}

enum DriftMetric {
    METRIC_RIDE,
    METRIC_LAST_60
}

// Below this, efficiency rose markedly: more often an unfinished warm-up or a
// change of effort than great fitness, so it gets a neutral label.
const NEGATIVE_DRIFT_PERCENT = -3.0f;
const WATCH_DRIFT_PERCENT = 5.0f;
const HIGH_DRIFT_PERCENT = 10.0f;
// A label changes only once the drift is this far past a boundary.
const BAND_HYSTERESIS_PERCENT = 0.5f;

// Live aerobic decoupling from one-minute records; see docs/CURRENT_TASK.md.
// All thresholds are heuristics to be calibrated on real rides.
class DriftEngine {
    private const DEFAULT_WARMUP_MINUTES = 15;
    private const MINUTE_SECONDS = 60;
    // A steady minute has at most 20% coasting / dropout ...
    private const MIN_STEADY_VALID_SECONDS = 48;
    // ... power within 20% of the ride's median minute ...
    private const STEADY_BAND_PERCENT = 20;
    // ... and is not in the HR recovery after a non-steady minute
    // (about three HR time constants of 35-70 s).
    private const RECOVERY_MINUTES = 3;
    // Halves whose average power differs more than this are not compared:
    // with HR = HR0 + k * P, a 10% power change alone moves Pw:HR by about 5%.
    private const MAX_POWER_CHANGE_PERCENT = 5.0f;

    private const RIDE_MIN_STEADY_MINUTES = 40;
    private const RIDE_MIN_STEADY_PERCENT = 70;
    private const LAST_WINDOW_MINUTES = 60;
    private const LAST_MIN_STEADY_MINUTES = 48;

    private const RIDE_BUCKETS = 240;
    private const HISTOGRAM_BIN_WATTS = 10;
    private const HISTOGRAM_BINS = 150;

    var mWarmupMinutes as Number;
    var mHistory as EfficiencyHistory;
    var mRide as RideBuckets;
    // Intervals.icu-style reference for calibration: every running second with
    // HR (zero power included), from the start, halves by time.
    var mCompat as RideBuckets;
    // Minute powers for the running median, in 10 W bins.
    var mPowerHistogram as Array<Number>;
    var mHistogramCount as Number = 0;

    // The minute being collected.
    var mSecond as Number = 0;
    var mValidSeconds as Number = 0;
    var mPowerSum as Number = 0;
    var mHeartRateSum as Number = 0;
    var mCompatSeconds as Number = 0;
    var mCompatPowerSum as Number = 0;
    var mCompatHeartRateSum as Number = 0;

    var mMinutes as Number = 0;
    var mPostWarmupMinutes as Number = 0;
    var mSteadyMinutes as Number = 0;
    var mSteadySeconds as Number = 0;
    var mRecoveryLeft as Number = 0;

    var mRideState as DriftState = DRIFT_WARMUP;
    var mRideResult as Array<Float>? = null;
    var mRideBand as DriftBand? = null;
    var mLastState as DriftState = DRIFT_WARMUP;
    var mLastResult as Array<Float>? = null;
    var mLastBand as DriftBand? = null;

    function initialize(warmupMinutes as Number?) {
        mWarmupMinutes = DEFAULT_WARMUP_MINUTES;
        if (warmupMinutes != null && warmupMinutes >= 0) {
            mWarmupMinutes = warmupMinutes;
        }
        mHistory = new EfficiencyHistory();
        mRide = new RideBuckets(RIDE_BUCKETS);
        mCompat = new RideBuckets(RIDE_BUCKETS);
        mPowerHistogram = new Array<Number>[HISTOGRAM_BINS];
        reset();
    }

    // Starts over for a new activity; the warm-up setting is kept.
    function reset() as Void {
        mHistory.reset();
        mRide.reset();
        mCompat.reset();
        for (var i = 0; i < HISTOGRAM_BINS; i += 1) {
            mPowerHistogram[i] = 0;
        }
        mHistogramCount = 0;
        resetMinute();
        mMinutes = 0;
        mPostWarmupMinutes = 0;
        mSteadyMinutes = 0;
        mSteadySeconds = 0;
        mRecoveryLeft = 0;
        mRideBand = null;
        mLastBand = null;
        evaluate();
    }

    // DataField.compute() is called once per second. Seconds with a stopped
    // timer (pause, auto-pause) are neither valid nor invalid: they are skipped.
    function addSample(power as Number?, heartRate as Number?, isTimerRunning as Boolean) as Void {
        if (!isTimerRunning) {
            return;
        }
        mSecond += 1;
        var hasPower = power != null && power > 0;
        if (heartRate != null && heartRate > 0) {
            mCompatSeconds += 1;
            mCompatHeartRateSum += heartRate;
            if (hasPower) {
                mCompatPowerSum += power as Number;
                mValidSeconds += 1;
                mPowerSum += power as Number;
                mHeartRateSum += heartRate;
            }
        }
        if (mSecond == MINUTE_SECONDS) {
            commitMinute();
        }
    }

    // Completed running minutes; changes once per minute.
    function getMinutes() as Number {
        return mMinutes;
    }

    function getState(metric as DriftMetric) as DriftState {
        return metric == METRIC_RIDE ? mRideState : mLastState;
    }

    // The drift, only when it can be shown (VALID).
    function getDriftPercent(metric as DriftMetric) as Float? {
        if (getState(metric) != DRIFT_VALID) {
            return null;
        }
        return (result(metric) as Array<Float>)[0];
    }

    // First-half Pw:HR; the reference the drift is measured from.
    function getBaselineEfficiency(metric as DriftMetric) as Float? {
        var values = result(metric);
        return values == null ? null : values[1];
    }

    // Second-half power relative to the first, in percent, once computed.
    function getPowerChangePercent(metric as DriftMetric) as Float? {
        var values = result(metric);
        return values == null ? null : values[2];
    }

    function getBand(metric as DriftMetric) as DriftBand? {
        return metric == METRIC_RIDE ? mRideBand : mLastBand;
    }

    // Sports-performance labels only, not physiological or medical findings.
    static function bandFor(driftPercent as Float) as DriftBand {
        if (driftPercent >= HIGH_DRIFT_PERCENT) {
            return BAND_HIGH;
        } else if (driftPercent >= WATCH_DRIFT_PERCENT) {
            return BAND_WATCH;
        }
        return driftPercent < NEGATIVE_DRIFT_PERCENT ? BAND_NEGATIVE : BAND_STABLE;
    }

    // Keeps the previous label unless the drift is clearly past a boundary, so a
    // value hovering around 5% does not flip between STABLE and WATCH.
    static function bandWithHysteresis(driftPercent as Float, previous as DriftBand?) as DriftBand {
        if (previous == null) {
            return bandFor(driftPercent);
        }
        var clearlyHigher = bandFor(driftPercent - BAND_HYSTERESIS_PERCENT);
        if ((clearlyHigher as Number) > (previous as Number)) {
            return clearlyHigher;
        }
        var clearlyLower = bandFor(driftPercent + BAND_HYSTERESIS_PERCENT);
        if ((clearlyLower as Number) < (previous as Number)) {
            return clearlyLower;
        }
        return previous;
    }

    // Intervals.icu-style drift of the whole activity (average power incl. zeros
    // / average HR, halves by time), recorded for calibration, not shown.
    function getCompatDriftPercent() as Float? {
        var values = mCompat.drift();
        return values == null ? null : values[0];
    }

    // Minutes done / needed before the metric can have a result.
    function getProgressMinutes(metric as DriftMetric) as Number {
        return metric == METRIC_RIDE ? mSteadyMinutes : mPostWarmupMinutes;
    }

    function getRequiredMinutes(metric as DriftMetric) as Number {
        return metric == METRIC_RIDE ? RIDE_MIN_STEADY_MINUTES : LAST_WINDOW_MINUTES;
    }

    function getWarmupElapsedSeconds() as Number {
        var elapsed = mMinutes * MINUTE_SECONDS + mSecond;
        var warmup = getWarmupSeconds();
        return elapsed < warmup ? elapsed : warmup;
    }

    function getWarmupSeconds() as Number {
        return mWarmupMinutes * MINUTE_SECONDS;
    }

    // Valid seconds in steady minutes: the data both drift values are based on.
    function getSteadySeconds() as Number {
        return mSteadySeconds;
    }

    // Share of post-warm-up minutes that were steady, 0-100.
    function getSteadyPercent() as Number {
        return mPostWarmupMinutes == 0 ? 0 : mSteadyMinutes * 100 / mPostWarmupMinutes;
    }

    function getRequiredSteadyPercent() as Number {
        return RIDE_MIN_STEADY_PERCENT;
    }

    function getMaxPowerChangePercent() as Float {
        return MAX_POWER_CHANGE_PERCENT;
    }

    function getLastSteadyMinutes() as Number {
        return mHistory.getSteadyMinutes();
    }

    function getRequiredLastSteadyMinutes() as Number {
        return LAST_MIN_STEADY_MINUTES;
    }

    function getHistory() as EfficiencyHistory {
        return mHistory;
    }

    private function result(metric as DriftMetric) as Array<Float>? {
        return metric == METRIC_RIDE ? mRideResult : mLastResult;
    }

    private function commitMinute() as Void {
        var isSteady = false;
        if (mMinutes >= mWarmupMinutes) {
            mPostWarmupMinutes += 1;
            var inBand = false;
            if (mValidSeconds >= MIN_STEADY_VALID_SECONDS) {
                var minutePower = mPowerSum / mValidSeconds;
                addToHistogram(minutePower);
                var median = medianPower();
                inBand = minutePower * 100 >= median * (100 - STEADY_BAND_PERCENT) &&
                    minutePower * 100 <= median * (100 + STEADY_BAND_PERCENT);
            }
            if (!inBand) {
                mRecoveryLeft = RECOVERY_MINUTES;
            } else if (mRecoveryLeft > 0) {
                mRecoveryLeft -= 1;
            } else {
                isSteady = true;
            }

            if (isSteady) {
                mSteadyMinutes += 1;
                mSteadySeconds += mValidSeconds;
                mRide.addMinute(mPowerSum, mHeartRateSum, mValidSeconds);
            } else {
                mRide.addMinute(0, 0, 0);
            }
        }
        mHistory.addMinute(mPowerSum, mHeartRateSum, mValidSeconds, isSteady);
        mCompat.addMinute(mCompatPowerSum, mCompatHeartRateSum, mCompatSeconds);
        mMinutes += 1;
        resetMinute();
        evaluate();
    }

    private function evaluate() as Void {
        mRideResult = null;
        mLastResult = null;
        if (mMinutes < mWarmupMinutes) {
            mRideState = DRIFT_WARMUP;
            mLastState = DRIFT_WARMUP;
            mRideBand = null;
            mLastBand = null;
            return;
        }

        if (mPostWarmupMinutes >= RIDE_MIN_STEADY_MINUTES &&
            mSteadyMinutes * 100 < mPostWarmupMinutes * RIDE_MIN_STEADY_PERCENT) {
            mRideState = DRIFT_NOT_STEADY;
        } else if (mSteadyMinutes < RIDE_MIN_STEADY_MINUTES) {
            mRideState = DRIFT_COLLECTING;
        } else {
            mRideResult = mRide.drift();
            mRideState = stateFor(mRideResult);
        }
        mRideBand = labelFor(mRideState, mRideResult, mRideBand);

        if (mPostWarmupMinutes < LAST_WINDOW_MINUTES) {
            mLastState = DRIFT_COLLECTING;
        } else if (mHistory.getSteadyMinutes() < LAST_MIN_STEADY_MINUTES) {
            mLastState = DRIFT_NOT_STEADY;
        } else {
            mLastResult = mHistory.drift();
            mLastState = stateFor(mLastResult);
        }
        mLastBand = labelFor(mLastState, mLastResult, mLastBand);
    }

    private function stateFor(values as Array<Float>?) as DriftState {
        if (values == null) {
            return DRIFT_NOT_STEADY;
        }
        var change = values[2];
        if (change > MAX_POWER_CHANGE_PERCENT || change < -MAX_POWER_CHANGE_PERCENT) {
            return DRIFT_POWER_CHANGED;
        }
        return DRIFT_VALID;
    }

    // The label follows the drift with hysteresis while valid and is cleared otherwise.
    private function labelFor(state as DriftState, values as Array<Float>?,
                              previous as DriftBand?) as DriftBand? {
        if (state != DRIFT_VALID || values == null) {
            return null;
        }
        return bandWithHysteresis(values[0], previous);
    }

    private function addToHistogram(power as Number) as Void {
        var bin = power / HISTOGRAM_BIN_WATTS;
        if (bin >= HISTOGRAM_BINS) {
            bin = HISTOGRAM_BINS - 1;
        }
        mPowerHistogram[bin] += 1;
        mHistogramCount += 1;
    }

    // Centre of the bin holding the median minute power.
    private function medianPower() as Number {
        var target = (mHistogramCount + 1) / 2;
        var seen = 0;
        for (var i = 0; i < HISTOGRAM_BINS; i += 1) {
            seen += mPowerHistogram[i];
            if (seen >= target) {
                return i * HISTOGRAM_BIN_WATTS + HISTOGRAM_BIN_WATTS / 2;
            }
        }
        return 0;
    }

    private function resetMinute() as Void {
        mSecond = 0;
        mValidSeconds = 0;
        mPowerSum = 0;
        mHeartRateSum = 0;
        mCompatSeconds = 0;
        mCompatPowerSum = 0;
        mCompatHeartRateSum = 0;
    }
}
