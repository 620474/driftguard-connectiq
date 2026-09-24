import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class DriftGuardView extends WatchUi.DataField {
    // onUpdate may run before the first compute callback.
    var powerText as String = "--";
    var heartRateText as String = "--";
    var ratioText as String = "--";

    function initialize() {
        DataField.initialize();
    }

    function compute(info as Activity.Info) as Void {
        var power = info.currentPower;
        var heartRate = info.currentHeartRate;

        // Replace every value on every sample so missing sensors cannot leave stale text.
        powerText = "--";
        heartRateText = "--";
        ratioText = "--";
        if (power != null && power >= 0) {
            powerText = power.format("%d") + " W";
        }
        if (heartRate != null && heartRate > 0) {
            heartRateText = heartRate.format("%d") + " bpm";
            if (power != null && power >= 0) {
                // Activity.Info supplies nullable integers; convert before dividing.
                ratioText = (power.toFloat() / heartRate).format("%.2f");
            }
        }
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var background = getBackgroundColor();
        var foreground = background == Graphics.COLOR_BLACK
            ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        dc.setColor(foreground, background);
        dc.clear();
        var center = dc.getWidth() / 2;
        var height = dc.getHeight();
        var align = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        if (height >= 300) {
            dc.drawText(center, height * 0.08, Graphics.FONT_SMALL, "DRIFTGUARD", align);
            dc.drawText(center, height * 0.23, Graphics.FONT_XTINY, "POWER", align);
            dc.drawText(center, height * 0.34, Graphics.FONT_LARGE, powerText, align);
            dc.drawText(center, height * 0.49, Graphics.FONT_XTINY, "HR", align);
            dc.drawText(center, height * 0.60, Graphics.FONT_LARGE, heartRateText, align);
            dc.drawText(center, height * 0.75, Graphics.FONT_XTINY, "PW:HR", align);
            dc.drawText(center, height * 0.86, Graphics.FONT_LARGE, ratioText, align);
        } else {
            dc.drawText(center, height / 6, Graphics.FONT_XTINY, "P " + powerText, align);
            dc.drawText(center, height / 2, Graphics.FONT_XTINY, "HR " + heartRateText, align);
            dc.drawText(center, height * 5 / 6, Graphics.FONT_XTINY, "PW:HR " + ratioText, align);
        }
    }
}
