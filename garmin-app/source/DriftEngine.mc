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

const WATCH_DRIFT_PERCENT = 5.0f;
const HIGH_DRIFT_PERCENT = 10.0f;

class DriftEngine {
    private const DEFAULT_WARMUP_MS = 15 * 60 * 1000;
    private const HALF_SAMPLE_COUNT = 15 * 60;
    private const REQUIRED_VALID_SAMPLES = HALF_SAMPLE_COUNT * 2;
    // At least 80% of samples in a period must be valid: 1800 valid allow 450 invalid.
    private const MAX_INVALID_SAMPLES = REQUIRED_VALID_SAMPLES * 20 / 80;
    // Variability is measured on 30 s power averages, not raw 1 Hz power.
    private const BLOCK_SAMPLE_COUNT = 30;
    private const MAX_POWER_CV_SQUARED = 0.0225f; // 15%^2

    var mWarmupMs as Number;
    var mTimerTime as Number = 0;
    var mState as DriftState = DRIFT_WARMUP;
    var mDriftPercent as Float? = null;
    var mBaselineEfficiency as Float? = null;

    // Accumulators for the period currently being collected.
    var mValidSamples as Number = 0;
    var mInvalidSamples as Number = 0;
    var mFirstPowerTotal as Float = 0.0f;
    var mFirstHeartRateTotal as Float = 0.0f;
    var mSecondPowerTotal as Float = 0.0f;
    var mSecondHeartRateTotal as Float = 0.0f;
    var mBlockPowerTotal as Float = 0.0f;
    var mBlockMeanTotal as Float = 0.0f;
    var mBlockMeanSquareTotal as Float = 0.0f;

    function initialize(warmupMs as Number?) {
        mWarmupMs = DEFAULT_WARMUP_MS;
        if (warmupMs != null && warmupMs >= 0) {
            mWarmupMs = warmupMs;
        }
        reset();
    }

    // Starts over for a new activity; the warm-up setting is kept.
    function reset() as Void {
        mTimerTime = 0;
        mState = mWarmupMs > 0 ? DRIFT_WARMUP : DRIFT_COLLECTING;
        mDriftPercent = null;
        mBaselineEfficiency = null;
        resetPeriod();
    }

    // DataField.compute() is called once per second, so each accepted sample is 1 s.
    // timerTime excludes pauses, so waiting at the start does not count as warm-up.
    function addSample(timerTime as Number?, power as Number?, heartRate as Number?,
                       isTimerRunning as Boolean) as Void {
        if (timerTime != null) {
            mTimerTime = timerTime;
        }
        // The first valid period is the result for the ride; it is not recalculated.
        // A stopped timer (pause, auto-pause) is neither valid nor invalid data.
        if (mState == DRIFT_VALID || !isTimerRunning || timerTime == null ||
            timerTime < mWarmupMs) {
            return;
        }
        if (mState == DRIFT_WARMUP) {
            mState = DRIFT_COLLECTING;
        }

        // Missing sensors and coasting (zero power) while riding count against quality.
        if (power == null || heartRate == null || power <= 0 || heartRate <= 0) {
            mInvalidSamples += 1;
            if (mInvalidSamples > MAX_INVALID_SAMPLES) {
                rejectPeriod();
            }
            return;
        }

        var powerFloat = power.toFloat();
        mValidSamples += 1;
        if (mValidSamples <= HALF_SAMPLE_COUNT) {
            mFirstPowerTotal += powerFloat;
            mFirstHeartRateTotal += heartRate.toFloat();
        } else {
            mSecondPowerTotal += powerFloat;
            mSecondHeartRateTotal += heartRate.toFloat();
        }

        mBlockPowerTotal += powerFloat;
        if (mValidSamples % BLOCK_SAMPLE_COUNT == 0) {
            var blockMean = mBlockPowerTotal / BLOCK_SAMPLE_COUNT;
            mBlockMeanTotal += blockMean;
            mBlockMeanSquareTotal += blockMean * blockMean;
            mBlockPowerTotal = 0.0f;
        }

        if (mValidSamples == REQUIRED_VALID_SAMPLES) {
            finishPeriod();
        }
    }

    function getState() as DriftState {
        return mState;
    }

    function getDriftPercent() as Float? {
        return mDriftPercent;
    }

    // First-half Pw:HR of the accepted period; the reference the drift is measured from.
    function getBaselineEfficiency() as Float? {
        return mBaselineEfficiency;
    }

    function getBand() as DriftBand? {
        return mDriftPercent == null ? null : bandFor(mDriftPercent as Float);
    }

    // Sports-performance labels only; negative drift (improving efficiency) is stable.
    static function bandFor(driftPercent as Float) as DriftBand {
        if (driftPercent >= HIGH_DRIFT_PERCENT) {
            return BAND_HIGH;
        }
        return driftPercent >= WATCH_DRIFT_PERCENT ? BAND_WATCH : BAND_STABLE;
    }

    function getValidSamples() as Number {
        return mValidSamples;
    }

    function getRequiredSamples() as Number {
        return REQUIRED_VALID_SAMPLES;
    }

    function getWarmupMs() as Number {
        return mWarmupMs;
    }

    function getWarmupElapsedMs() as Number {
        return mTimerTime < mWarmupMs ? mTimerTime : mWarmupMs;
    }

    private function finishPeriod() as Void {
        var blockCount = REQUIRED_VALID_SAMPLES / BLOCK_SAMPLE_COUNT;
        var meanPower = mBlockMeanTotal / blockCount;
        var powerVariance = mBlockMeanSquareTotal / blockCount - meanPower * meanPower;
        if (powerVariance > meanPower * meanPower * MAX_POWER_CV_SQUARED) {
            rejectPeriod();
            return;
        }

        // Both halves contain only positive power and HR, so neither total is zero.
        var firstEfficiency = mFirstPowerTotal / mFirstHeartRateTotal;
        var secondEfficiency = mSecondPowerTotal / mSecondHeartRateTotal;
        mDriftPercent = ((firstEfficiency - secondEfficiency) / firstEfficiency) * 100.0f;
        mBaselineEfficiency = firstEfficiency;
        mState = DRIFT_VALID;
    }

    // The period failed a quality gate; report it and start collecting a new one.
    private function rejectPeriod() as Void {
        mState = DRIFT_NOT_STEADY;
        resetPeriod();
    }

    private function resetPeriod() as Void {
        mValidSamples = 0;
        mInvalidSamples = 0;
        mFirstPowerTotal = 0.0f;
        mFirstHeartRateTotal = 0.0f;
        mSecondPowerTotal = 0.0f;
        mSecondHeartRateTotal = 0.0f;
        mBlockPowerTotal = 0.0f;
        mBlockMeanTotal = 0.0f;
        mBlockMeanSquareTotal = 0.0f;
    }
}
