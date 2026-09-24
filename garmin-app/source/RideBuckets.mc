import Toybox.Lang;

// Steady-minute sums for the whole ride in constant memory. When the buffer is
// full, neighbouring buckets are merged pairwise and each bucket then covers
// twice as many minutes. Sums add exactly; only the resolution of the half-way
// split becomes one bucket (e.g. 2 minutes after 4 hours with 240 buckets).
class RideBuckets {
    var mCapacity as Number;
    var mPowerSums as Array<Number>;
    var mHeartRateSums as Array<Number>;
    var mSeconds as Array<Number>;
    var mCount as Number = 0;
    var mMinutesPerBucket as Number = 1;
    // Minutes already added to the last (open) bucket.
    var mOpenMinutes as Number = 0;

    function initialize(capacity as Number) {
        // An even capacity keeps pairwise merging simple.
        mCapacity = capacity - capacity % 2;
        mPowerSums = new Array<Number>[mCapacity];
        mHeartRateSums = new Array<Number>[mCapacity];
        mSeconds = new Array<Number>[mCapacity];
        reset();
    }

    function reset() as Void {
        for (var i = 0; i < mCapacity; i += 1) {
            mPowerSums[i] = 0;
            mHeartRateSums[i] = 0;
            mSeconds[i] = 0;
        }
        mCount = 0;
        mMinutesPerBucket = 1;
        mOpenMinutes = 0;
    }

    // Adds one post-warm-up minute; a non-steady minute is added with zero seconds
    // so bucket boundaries stay aligned with ride time.
    function addMinute(powerSum as Number, heartRateSum as Number, seconds as Number) as Void {
        if (mCount == 0 || mOpenMinutes == mMinutesPerBucket) {
            if (mCount == mCapacity) {
                merge();
            }
            mCount += 1;
            mOpenMinutes = 0;
        }
        var i = mCount - 1;
        mPowerSums[i] += powerSum;
        mHeartRateSums[i] += heartRateSum;
        mSeconds[i] += seconds;
        mOpenMinutes += 1;
    }

    // [driftPercent, firstHalfEfficiency] over all steady data, or null.
    function drift() as Array<Float>? {
        return DriftMath.halves(mPowerSums, mHeartRateSums, mSeconds, 0, mCount, mCapacity);
    }

    function getMinutesPerBucket() as Number {
        return mMinutesPerBucket;
    }

    function getCount() as Number {
        return mCount;
    }

    private function merge() as Void {
        var half = mCapacity / 2;
        for (var i = 0; i < half; i += 1) {
            mPowerSums[i] = mPowerSums[2 * i] + mPowerSums[2 * i + 1];
            mHeartRateSums[i] = mHeartRateSums[2 * i] + mHeartRateSums[2 * i + 1];
            mSeconds[i] = mSeconds[2 * i] + mSeconds[2 * i + 1];
        }
        for (var i = half; i < mCapacity; i += 1) {
            mPowerSums[i] = 0;
            mHeartRateSums[i] = 0;
            mSeconds[i] = 0;
        }
        mCount = half;
        mMinutesPerBucket *= 2;
    }
}
