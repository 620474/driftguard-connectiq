import Toybox.Lang;

enum DriftState {
    DRIFT_WARMUP,
    DRIFT_COLLECTING,
    DRIFT_NOT_STEADY,
    DRIFT_VALID
}

enum DriftBand {
    BAND_STABLE,
    BAND_WATCH,
    BAND_HIGH
}

enum DriftMetric {
    METRIC_RIDE,
    METRIC_LAST_60
}

const WATCH_DRIFT_PERCENT = 5.0f;
const HIGH_DRIFT_PERCENT = 10.0f;

// Live aerobic decoupling from one-minute records; see docs/CURRENT_TASK.md.
// All thresholds are heuristics to be calibrated on real rides.
class DriftEngine {
    private const DEFAULT_WARMUP_MINUTES = 15;
    private const MINUTE_SECONDS = 60;
    // A steady minute has at most 20% coasting / dropout ...
    private const MIN_STEADY_VALID_SECONDS = 48;
    // ... power within 20% of the ride's median minute ...
    private const STEADY_BAND_PERCENT = 20;
    // ... and is not in the HR recovery after a non-steady minute.
    private const RECOVERY_MINUTES = 2;

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
    // Minute powers for the running median, in 10 W bins.
    var mPowerHistogram as Array<Number>;
    var mHistogramCount as Number = 0;

    // The minute being collected.
    var mSecond as Number = 0;
    var mValidSeconds as Number = 0;
    var mPowerSum as Number = 0;
    var mHeartRateSum as Number = 0;

    var mMinutes as Number = 0;
    var mPostWarmupMinutes as Number = 0;
    var mSteadyMinutes as Number = 0;
    var mSteadySeconds as Number = 0;
    var mRecoveryLeft as Number = 0;

    var mRideState as DriftState = DRIFT_WARMUP;
    var mRideResult as Array<Float>? = null;
    var mLastState as DriftState = DRIFT_WARMUP;
    var mLastResult as Array<Float>? = null;

    function initialize(warmupMinutes as Number?) {
        mWarmupMinutes = DEFAULT_WARMUP_MINUTES;
        if (warmupMinutes != null && warmupMinutes >= 0) {
            mWarmupMinutes = warmupMinutes;
        }
        mHistory = new EfficiencyHistory();
        mRide = new RideBuckets(RIDE_BUCKETS);
        mPowerHistogram = new Array<Number>[HISTOGRAM_BINS];
        reset();
    }

    // Starts over for a new activity; the warm-up setting is kept.
    function reset() as Void {
        mHistory.reset();
        mRide.reset();
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
        evaluate();
    }

    // DataField.compute() is called once per second. Seconds with a stopped
    // timer (pause, auto-pause) are neither valid nor invalid: they are skipped.
    function addSample(power as Number?, heartRate as Number?, isTimerRunning as Boolean) as Void {
        if (!isTimerRunning) {
            return;
        }
        mSecond += 1;
        if (power != null && heartRate != null && power > 0 && heartRate > 0) {
            mValidSeconds += 1;
            mPowerSum += power;
            mHeartRateSum += heartRate;
        }
        if (mSecond == MINUTE_SECONDS) {
            commitMinute();
        }
    }

    function getState(metric as DriftMetric) as DriftState {
        return metric == METRIC_RIDE ? mRideState : mLastState;
    }

    function getDriftPercent(metric as DriftMetric) as Float? {
        var result = metric == METRIC_RIDE ? mRideResult : mLastResult;
        return result == null ? null : result[0];
    }

    // First-half Pw:HR; the reference the drift is measured from.
    function getBaselineEfficiency(metric as DriftMetric) as Float? {
        var result = metric == METRIC_RIDE ? mRideResult : mLastResult;
        return result == null ? null : result[1];
    }

    function getBand(metric as DriftMetric) as DriftBand? {
        var drift = getDriftPercent(metric);
        return drift == null ? null : bandFor(drift);
    }

    // Sports-performance labels only; negative drift (improving efficiency) is stable.
    static function bandFor(driftPercent as Float) as DriftBand {
        if (driftPercent >= HIGH_DRIFT_PERCENT) {
            return BAND_HIGH;
        }
        return driftPercent >= WATCH_DRIFT_PERCENT ? BAND_WATCH : BAND_STABLE;
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

    // Share of post-warm-up minutes that were steady, 0–100.
    function getSteadyPercent() as Number {
        return mPostWarmupMinutes == 0 ? 0 : mSteadyMinutes * 100 / mPostWarmupMinutes;
    }

    function getRequiredSteadyPercent() as Number {
        return RIDE_MIN_STEADY_PERCENT;
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
            return;
        }

        if (mPostWarmupMinutes >= RIDE_MIN_STEADY_MINUTES &&
            mSteadyMinutes * 100 < mPostWarmupMinutes * RIDE_MIN_STEADY_PERCENT) {
            mRideState = DRIFT_NOT_STEADY;
        } else if (mSteadyMinutes < RIDE_MIN_STEADY_MINUTES) {
            mRideState = DRIFT_COLLECTING;
        } else {
            mRideResult = mRide.drift();
            mRideState = mRideResult == null ? DRIFT_NOT_STEADY : DRIFT_VALID;
        }

        if (mPostWarmupMinutes < LAST_WINDOW_MINUTES) {
            mLastState = DRIFT_COLLECTING;
        } else if (mHistory.getSteadyMinutes() < LAST_MIN_STEADY_MINUTES) {
            mLastState = DRIFT_NOT_STEADY;
        } else {
            mLastResult = mHistory.drift();
            mLastState = mLastResult == null ? DRIFT_NOT_STEADY : DRIFT_VALID;
        }
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
    }
}
