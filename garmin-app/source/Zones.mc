import Toybox.Lang;

// Zone thresholds as Garmin returns them: [min zone 1, max zone 1, ..., max zone N].
module Zones {
    // Coggan-style upper bounds in % of FTP, used only when the profile has no power zones.
    const FTP_ZONE_PERCENTS = [55, 75, 90, 105, 120, 150] as Array<Number>;

    // Returns the thresholds only if they describe at least two ascending zones.
    function validated(thresholds as Array<Number>?) as Array<Number>? {
        if (thresholds == null || thresholds.size() < 3) {
            return null;
        }
        for (var i = 1; i < thresholds.size(); i += 1) {
            if (thresholds[i] == null || thresholds[i - 1] == null ||
                thresholds[i] <= thresholds[i - 1]) {
                return null;
            }
        }
        return thresholds;
    }

    // Seven power zones from FTP; the top zone is open-ended in practice.
    function fromFtp(ftp as Number) as Array<Number> {
        var thresholds = [0] as Array<Number>;
        for (var i = 0; i < FTP_ZONE_PERCENTS.size(); i += 1) {
            thresholds.add(ftp * FTP_ZONE_PERCENTS[i] / 100);
        }
        thresholds.add(ftp * 2);
        return thresholds;
    }

    // 0-based zone index; values below zone 1 are zone 1, above the top are the top zone.
    function zoneIndex(value as Number, thresholds as Array<Number>) as Number {
        var zoneCount = thresholds.size() - 1;
        for (var i = 0; i < zoneCount; i += 1) {
            if (value <= thresholds[i + 1]) {
                return i;
            }
        }
        return zoneCount - 1;
    }

    // Marker position 0..1 on a gauge where every zone has the same width.
    function position(value as Number, thresholds as Array<Number>) as Float {
        var zoneCount = thresholds.size() - 1;
        var zone = zoneIndex(value, thresholds);
        var low = thresholds[zone];
        var high = thresholds[zone + 1];
        var fraction = (value - low).toFloat() / (high - low);
        if (fraction < 0.0f) {
            fraction = 0.0f;
        } else if (fraction > 1.0f) {
            fraction = 1.0f;
        }
        return (zone + fraction) / zoneCount;
    }
}
