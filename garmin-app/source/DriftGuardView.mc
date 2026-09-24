import Toybox.Activity;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class DriftGuardView extends WatchUi.DataField {
    // onUpdate may run before the first compute callback.
    var powerText as String = "--";
    var heartRateText as String = "--";
    var ratioText as String = "--";
    var driftText as String = "--";
    var driftState as String = "NOT_READY";
    var driftEngine as DriftEngine;

    function initialize() {
        DataField.initialize();
        driftEngine = new DriftEngine(null);
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

        var isTimerRunning = info.timerState == Activity.TIMER_STATE_ON;
        driftEngine.addSample(info.elapsedTime, power, heartRate, info.currentSpeed, isTimerRunning);
        driftState = driftEngine.getValidityState();
        var drift = driftEngine.getDriftPercent();
        driftText = drift == null ? "--" : drift.format("%.1f") + "%";
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
            dc.drawText(center, height * 0.06, Graphics.FONT_SMALL, "DRIFTGUARD", align);
            dc.drawText(center, height * 0.16, Graphics.FONT_XTINY, driftState, align);
            dc.drawText(center, height * 0.25, Graphics.FONT_LARGE, driftText, align);
            dc.drawText(center, height * 0.38, Graphics.FONT_XTINY, "POWER", align);
            dc.drawText(center, height * 0.47, Graphics.FONT_MEDIUM, powerText, align);
            dc.drawText(center, height * 0.59, Graphics.FONT_XTINY, "HR", align);
            dc.drawText(center, height * 0.68, Graphics.FONT_MEDIUM, heartRateText, align);
            dc.drawText(center, height * 0.80, Graphics.FONT_XTINY, "PW:HR", align);
            dc.drawText(center, height * 0.90, Graphics.FONT_MEDIUM, ratioText, align);
        } else {
            dc.drawText(center, height / 8, Graphics.FONT_XTINY, driftState, align);
            dc.drawText(center, height * 3 / 8, Graphics.FONT_XTINY, "DRIFT " + driftText, align);
            dc.drawText(center, height * 5 / 8, Graphics.FONT_XTINY, "P " + powerText, align);
            dc.drawText(center, height * 7 / 8, Graphics.FONT_XTINY, "HR " + heartRateText, align);
        }
    }
}
