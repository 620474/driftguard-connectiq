import Toybox.Lang;

module DriftMath {
    // Splits a run of minute records (possibly a ring buffer) into two halves by
    // steady seconds and compares their efficiency (power / HR).
    // Records with zero seconds are skipped; a record straddling the split is
    // divided proportionally. Returns [driftPercent, firstHalfEfficiency,
    // powerChangePercent] or null. Both halves have the same seconds, so the power
    // change is simply second-half power over first-half power.
    function halves(powerSums as Array<Number>, heartRateSums as Array<Number>,
                    seconds as Array<Number>, start as Number, count as Number,
                    capacity as Number) as Array<Float>? {
        var total = 0;
        for (var k = 0; k < count; k += 1) {
            total += seconds[(start + k) % capacity];
        }
        if (total <= 0) {
            return null;
        }

        var half = total / 2.0f;
        var done = 0.0f;
        var firstPower = 0.0f;
        var firstHeartRate = 0.0f;
        var secondPower = 0.0f;
        var secondHeartRate = 0.0f;
        for (var k = 0; k < count; k += 1) {
            var i = (start + k) % capacity;
            var recordSeconds = seconds[i];
            if (recordSeconds <= 0) {
                continue;
            }
            var firstShare = (half - done) / recordSeconds;
            if (firstShare > 1.0f) {
                firstShare = 1.0f;
            } else if (firstShare < 0.0f) {
                firstShare = 0.0f;
            }
            firstPower += powerSums[i] * firstShare;
            firstHeartRate += heartRateSums[i] * firstShare;
            secondPower += powerSums[i] * (1.0f - firstShare);
            secondHeartRate += heartRateSums[i] * (1.0f - firstShare);
            done += recordSeconds;
        }
        if (firstPower <= 0.0f || firstHeartRate <= 0.0f || secondHeartRate <= 0.0f) {
            return null;
        }
        var firstEfficiency = firstPower / firstHeartRate;
        var secondEfficiency = secondPower / secondHeartRate;
        return [(firstEfficiency - secondEfficiency) / firstEfficiency * 100.0f,
            firstEfficiency, (secondPower / firstPower - 1.0f) * 100.0f] as Array<Float>;
    }
}
