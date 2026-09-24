import Toybox.Lang;

// Per-minute Pw:HR for the trend chart: a fixed ring buffer, no ride history growth.
class EfficiencyHistory {
    private const POINT_SECONDS = 60;
    // A minute with less valid data is a gap in the chart, not an estimate.
    private const MIN_VALID_SECONDS = 30;
    private const CAPACITY = 60;

    var mPoints as Array<Float?>;
    var mCommitted as Number = 0;
    var mSeconds as Number = 0;
    var mValidSeconds as Number = 0;
    var mPowerTotal as Float = 0.0f;
    var mHeartRateTotal as Float = 0.0f;

    function initialize() {
        mPoints = new Array<Float?>[CAPACITY];
        reset();
    }

    function reset() as Void {
        for (var i = 0; i < CAPACITY; i += 1) {
            mPoints[i] = null;
        }
        mCommitted = 0;
        resetMinute();
    }

    // Called once per second; only seconds with a running timer make up a minute.
    function addSample(power as Number?, heartRate as Number?, isTimerRunning as Boolean) as Void {
        if (!isTimerRunning) {
            return;
        }
        mSeconds += 1;
        if (power != null && heartRate != null && power > 0 && heartRate > 0) {
            mValidSeconds += 1;
            mPowerTotal += power.toFloat();
            mHeartRateTotal += heartRate.toFloat();
        }
        if (mSeconds < POINT_SECONDS) {
            return;
        }
        mPoints[mCommitted % CAPACITY] = mValidSeconds >= MIN_VALID_SECONDS
            ? mPowerTotal / mHeartRateTotal : null;
        mCommitted += 1;
        resetMinute();
    }

    function getSize() as Number {
        return mCommitted < CAPACITY ? mCommitted : CAPACITY;
    }

    // Index 0 is the oldest visible minute.
    function getPoint(index as Number) as Float? {
        return mPoints[(mCommitted - getSize() + index) % CAPACITY];
    }

    // The most recent full minute, or null before the first minute or after a gap.
    function getLatest() as Float? {
        var size = getSize();
        return size == 0 ? null : getPoint(size - 1);
    }

    private function resetMinute() as Void {
        mSeconds = 0;
        mValidSeconds = 0;
        mPowerTotal = 0.0f;
        mHeartRateTotal = 0.0f;
    }
}
