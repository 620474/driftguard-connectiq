import Toybox.Lang;

class DriftEngine {
    private const DEFAULT_WARMUP_MS = 15 * 60 * 1000;
    private const HALF_SAMPLE_COUNT = 15 * 60;
    private const REQUIRED_VALID_SAMPLES = HALF_SAMPLE_COUNT * 2;
    private const MIN_VALID_PERCENT = 80;
    private const MAX_POWER_CV_SQUARED = 0.0225f; // 15%^2

    var mWarmupMs as Number;
    var mObservedSamples as Number = 0;
    var mValidSamples as Number = 0;
    var mFirstPowerTotal as Float = 0.0f;
    var mFirstHeartRateTotal as Float = 0.0f;
    var mSecondPowerTotal as Float = 0.0f;
    var mSecondHeartRateTotal as Float = 0.0f;
    var mPowerTotal as Float = 0.0f;
    var mPowerSquareTotal as Float = 0.0f;
    var mValidityState as String = "NOT_READY";
    var mDriftPercent as Float? = null;

    function initialize(warmupMs as Number?) {
        mWarmupMs = DEFAULT_WARMUP_MS;
        if (warmupMs != null && warmupMs >= 0) {
            mWarmupMs = warmupMs;
        }
    }

    // DataField.compute() is called once per second, so each accepted sample is 1 s.
    function addSample(elapsedTime as Number?, power as Number?, heartRate as Number?,
                       speed as Float?, isTimerRunning as Boolean) as Void {
        if (elapsedTime == null || elapsedTime < mWarmupMs) {
            return;
        }

        mObservedSamples += 1;
        if (!isTimerRunning || power == null || heartRate == null ||
            power <= 0 || heartRate <= 0 || (speed != null && speed <= 0.0f)) {
            updateValidity();
            return;
        }

        if (mValidSamples < REQUIRED_VALID_SAMPLES) {
            mValidSamples += 1;
            var powerFloat = power.toFloat();
            mPowerTotal += powerFloat;
            mPowerSquareTotal += powerFloat * powerFloat;
            if (mValidSamples <= HALF_SAMPLE_COUNT) {
                mFirstPowerTotal += powerFloat;
                mFirstHeartRateTotal += heartRate.toFloat();
            } else {
                mSecondPowerTotal += power.toFloat();
                mSecondHeartRateTotal += heartRate.toFloat();
            }
        }
        updateValidity();
    }

    function getValidityState() as String {
        return mValidityState;
    }

    function getDriftPercent() as Float? {
        return mDriftPercent;
    }

    function getValidSamples() as Number {
        return mValidSamples;
    }

    function updateValidity() as Void {
        mDriftPercent = null;
        if (mValidSamples < REQUIRED_VALID_SAMPLES) {
            mValidityState = mObservedSamples >= REQUIRED_VALID_SAMPLES
                ? "NOT_STEADY" : "NOT_READY";
            return;
        }

        if (mValidSamples * 100 < mObservedSamples * MIN_VALID_PERCENT) {
            mValidityState = "NOT_STEADY";
            return;
        }

        var meanPower = mPowerTotal / mValidSamples;
        var powerVariance = mPowerSquareTotal / mValidSamples - meanPower * meanPower;
        if (powerVariance > meanPower * meanPower * MAX_POWER_CV_SQUARED) {
            mValidityState = "NOT_STEADY";
            return;
        }

        var firstEfficiency = mFirstPowerTotal / mFirstHeartRateTotal;
        var secondEfficiency = mSecondPowerTotal / mSecondHeartRateTotal;
        if (firstEfficiency <= 0.0f || secondEfficiency <= 0.0f) {
            mValidityState = "NOT_STEADY";
            return;
        }
        mDriftPercent = ((firstEfficiency - secondEfficiency) / firstEfficiency) * 100.0f;
        mValidityState = "VALID";
    }
}
