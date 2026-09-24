import Toybox.Lang;

// The last 60 minute records: the Pw:HR chart and the LAST 60 MIN drift.
class EfficiencyHistory {
    // A minute with less valid data is a gap in the chart, not an estimate.
    private const MIN_CHART_SECONDS = 30;
    const CAPACITY = 60;

    var mPowerSums as Array<Number>;
    var mHeartRateSums as Array<Number>;
    var mValidSeconds as Array<Number>;
    // Valid seconds of steady minutes, 0 for minutes that do not count.
    var mSteadySeconds as Array<Number>;
    var mCommitted as Number = 0;

    function initialize() {
        mPowerSums = new Array<Number>[CAPACITY];
        mHeartRateSums = new Array<Number>[CAPACITY];
        mValidSeconds = new Array<Number>[CAPACITY];
        mSteadySeconds = new Array<Number>[CAPACITY];
        reset();
    }

    function reset() as Void {
        for (var i = 0; i < CAPACITY; i += 1) {
            mPowerSums[i] = 0;
            mHeartRateSums[i] = 0;
            mValidSeconds[i] = 0;
            mSteadySeconds[i] = 0;
        }
        mCommitted = 0;
    }

    function addMinute(powerSum as Number, heartRateSum as Number, validSeconds as Number,
                       isSteady as Boolean) as Void {
        var i = mCommitted % CAPACITY;
        mPowerSums[i] = powerSum;
        mHeartRateSums[i] = heartRateSum;
        mValidSeconds[i] = validSeconds;
        mSteadySeconds[i] = isSteady ? validSeconds : 0;
        mCommitted += 1;
    }

    function getSize() as Number {
        return mCommitted < CAPACITY ? mCommitted : CAPACITY;
    }

    // Pw:HR of a visible minute (index 0 is the oldest), or null for a gap.
    function getPoint(index as Number) as Float? {
        var i = ringIndex(index);
        if (mValidSeconds[i] < MIN_CHART_SECONDS) {
            return null;
        }
        return mPowerSums[i].toFloat() / mHeartRateSums[i];
    }

    function isSteady(index as Number) as Boolean {
        return mSteadySeconds[ringIndex(index)] > 0;
    }

    // The most recent full minute, or null before the first minute or after a gap.
    function getLatest() as Float? {
        var size = getSize();
        return size == 0 ? null : getPoint(size - 1);
    }

    function getSteadyMinutes() as Number {
        var steady = 0;
        for (var i = 0; i < getSize(); i += 1) {
            if (mSteadySeconds[i] > 0) {
                steady += 1;
            }
        }
        return steady;
    }

    // [driftPercent, firstHalfEfficiency] over the steady minutes shown, or null.
    function drift() as Array<Float>? {
        var size = getSize();
        return DriftMath.halves(mPowerSums, mHeartRateSums, mSteadySeconds,
            (mCommitted - size) % CAPACITY, size, CAPACITY);
    }

    private function ringIndex(index as Number) as Number {
        return (mCommitted - getSize() + index) % CAPACITY;
    }
}
