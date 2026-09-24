import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.UserProfile;
import Toybox.WatchUi;

class DriftGuardView extends WatchUi.DataField {
    private const POWER_AVERAGE_SECONDS = 3;
    private const METRIC_STORAGE_KEY = "metric";
    // Garmin's usual zone colors: gray, blue, green, orange, red, then yellow/purple
    // for 7-zone power models (inserted so the order stays cool to hot).
    private const ZONE_COLORS_5 = [0x8C8C8C, 0x2F7FE0, 0x2EA84A, 0xF08A00, 0xE0282E] as Array<Number>;
    private const ZONE_COLORS_7 = [0x8C8C8C, 0x2F7FE0, 0x2EA84A, 0xE6C200, 0xF08A00, 0xE0282E,
        0x9B3FD1] as Array<Number>;

    // onUpdate may run before the first compute callback.
    var powerText as String = "--";
    var heartRateText as String = "--";
    var ratioText as String = "--";
    var driftEngine as DriftEngine;
    // The metric shown large; tapping the field switches it.
    var metric as DriftMetric = METRIC_RIDE;

    // 3 s average power, as on Garmin's own power field; 1 s power is too jumpy for zones.
    var power3s as Number? = null;
    var heartRate as Number? = null;
    private var mPowerWindow as Array<Number> = [0, 0, 0] as Array<Number>;
    private var mPowerWindowCount as Number = 0;
    private var mPowerWindowNext as Number = 0;

    // The rider's own zones from the Garmin user profile; null when unavailable.
    var powerZones as Array<Number>? = null;
    var heartRateZones as Array<Number>? = null;

    // Colors for the current background, refreshed at the start of each onUpdate.
    private var mForeground as Number = Graphics.COLOR_BLACK;
    private var mBackground as Number = Graphics.COLOR_WHITE;
    private var mMuted as Number = Graphics.COLOR_DK_GRAY;
    private var mTrack as Number = Graphics.COLOR_LT_GRAY;
    private var mGreen as Number = Graphics.COLOR_DK_GREEN;

    function initialize() {
        DataField.initialize();
        driftEngine = new DriftEngine(null);
        loadZones();
        loadMetric();
    }

    function compute(info as Activity.Info) as Void {
        var power = info.currentPower;
        var currentHeartRate = info.currentHeartRate;

        // Replace every value on every sample so missing sensors cannot leave stale text.
        powerText = "--";
        heartRateText = "--";
        power3s = null;
        heartRate = null;
        if (power != null && power >= 0) {
            mPowerWindow[mPowerWindowNext] = power;
            mPowerWindowNext = (mPowerWindowNext + 1) % POWER_AVERAGE_SECONDS;
            if (mPowerWindowCount < POWER_AVERAGE_SECONDS) {
                mPowerWindowCount += 1;
            }
            var total = 0;
            for (var i = 0; i < mPowerWindowCount; i += 1) {
                total += mPowerWindow[(mPowerWindowNext - 1 - i + POWER_AVERAGE_SECONDS)
                    % POWER_AVERAGE_SECONDS];
            }
            power3s = (total + mPowerWindowCount / 2) / mPowerWindowCount;
            powerText = (power3s as Number).format("%d");
        } else {
            // A dropout restarts the average rather than mixing in stale readings.
            mPowerWindowCount = 0;
        }
        if (currentHeartRate != null && currentHeartRate > 0) {
            heartRate = currentHeartRate;
            heartRateText = currentHeartRate.format("%d");
        }

        var isTimerRunning = info.timerState == Activity.TIMER_STATE_ON;
        driftEngine.addSample(power, currentHeartRate, isTimerRunning);
        // Instant power / HR is noise (HR lags power); show the last full minute instead.
        var ratio = driftEngine.getHistory().getLatest();
        ratioText = ratio == null ? "--" : ratio.format("%.2f");
    }

    // Called when the activity is saved or discarded: the next ride starts clean.
    function onTimerReset() as Void {
        driftEngine.reset();
        mPowerWindowCount = 0;
        ratioText = "--";
        // Zones may have been edited in Garmin Connect since the field started.
        loadZones();
    }

    function toggleMetric() as Void {
        metric = metric == METRIC_RIDE ? METRIC_LAST_60 : METRIC_RIDE;
        try {
            Application.Storage.setValue(METRIC_STORAGE_KEY, metric as Number);
        } catch (e) {
            // Remembering the choice is a convenience; the toggle still works.
        }
    }

    function driftTextFor(forMetric as DriftMetric) as String {
        var drift = driftEngine.getDriftPercent(forMetric);
        return drift == null ? "--" : drift.format("%.1f");
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        updatePalette();
        dc.setColor(mForeground, mBackground);
        dc.clear();

        var height = dc.getHeight();
        if (height >= 500) {
            drawFull(dc);
        } else if (height >= 150) {
            drawMedium(dc);
        } else {
            drawSmall(dc);
        }
    }

    // Full page: metric tabs, hero drift, the other metric and steady time,
    // Pw:HR trend chart, power and HR zone gauges.
    private function drawFull(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = width / 2;
        var margin = width / 12;

        drawTabs(dc, center, height * 0.05);
        drawHero(dc, center, height * 0.195, height * 0.325, Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_LARGE, width - 2 * margin);

        var left = width / 4;
        var right = width * 3 / 4;
        var other = otherMetric();
        drawLabel(dc, left, height * 0.39, metricName(other), Graphics.TEXT_JUSTIFY_CENTER);
        drawLabel(dc, right, height * 0.39, "STEADY TIME", Graphics.TEXT_JUSTIFY_CENTER);
        var summaryAlign = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(stateColor(other), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, height * 0.425, Graphics.FONT_MEDIUM, summaryText(other), summaryAlign);
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(right, height * 0.425, Graphics.FONT_MEDIUM,
            durationText(driftEngine.getSteadySeconds()), summaryAlign);

        drawLabel(dc, margin, height * 0.49, "PW:HR · 1 MIN", Graphics.TEXT_JUSTIFY_LEFT);
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width - margin, height * 0.49, Graphics.FONT_SMALL, ratioText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        var chartTop = (height * 0.52).toNumber();
        drawTrend(dc, margin, chartTop, width - 2 * margin, (height * 0.645).toNumber() - chartTop);
        drawRule(dc, margin, width - margin, height * 0.67);

        var gaugeWidth = width - 2 * margin;
        drawZoneGauge(dc, margin, (height * 0.705).toNumber(), gaugeWidth, "POWER 3S", powerText,
            "W", power3s, powerZones);
        drawZoneGauge(dc, margin, (height * 0.845).toNumber(), gaugeWidth, "HEART RATE",
            heartRateText, "BPM", heartRate, heartRateZones);
    }

    // Half-page style field: selected metric large, the other metric and steady time below.
    private function drawMedium(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = width / 2;
        var heroFont = height >= 300 ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_MEDIUM;
        var titleFont = height >= 300 ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM;

        drawLabel(dc, center, height * 0.10, metricName(metric) + " DRIFT",
            Graphics.TEXT_JUSTIFY_CENTER);
        drawHero(dc, center, height * 0.40, height * 0.68, heroFont, titleFont, width * 3 / 4);
        var other = otherMetric();
        drawLabel(dc, center, height * 0.89, metricName(other) + " " + summaryText(other) +
            "   STEADY " + durationText(driftEngine.getSteadySeconds()),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Small field: value (or progress) and the metric with a colored state word.
    private function drawSmall(dc as Graphics.Dc) as Void {
        var center = dc.getWidth() / 2;
        var height = dc.getHeight();
        var align = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(center, height * 0.38, Graphics.FONT_MEDIUM, summaryText(metric), align);
        dc.setColor(stateColor(metric), Graphics.COLOR_TRANSPARENT);
        dc.drawText(center, height * 0.78, Graphics.FONT_XTINY,
            metricName(metric) + " · " + stateTitle(metric), align);
    }

    // Two pills; the selected metric is filled.
    private function drawTabs(dc as Graphics.Dc, x as Number, y as Float) as Void {
        var font = Graphics.FONT_XTINY;
        var textHeight = dc.getFontHeight(font);
        var tabHeight = textHeight + 8;
        var tabWidth = dc.getTextWidthInPixels("LAST 60", font) + textHeight * 2;
        var gap = 12;
        var metrics = [METRIC_RIDE, METRIC_LAST_60] as Array<DriftMetric>;
        for (var i = 0; i < metrics.size(); i += 1) {
            var tabX = i == 0 ? x - gap / 2 - tabWidth : x + gap / 2;
            var selected = metrics[i] == metric;
            dc.setColor(selected ? mForeground : mTrack, Graphics.COLOR_TRANSPARENT);
            if (selected) {
                dc.fillRoundedRectangle(tabX, y - tabHeight / 2, tabWidth, tabHeight, tabHeight / 2);
                dc.setColor(mBackground, Graphics.COLOR_TRANSPARENT);
            } else {
                dc.setPenWidth(2);
                dc.drawRoundedRectangle(tabX, y - tabHeight / 2, tabWidth, tabHeight, tabHeight / 2);
                dc.setPenWidth(1);
                dc.setColor(mMuted, Graphics.COLOR_TRANSPARENT);
            }
            dc.drawText(tabX + tabWidth / 2, y, font, metricName(metrics[i]),
                Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        }
    }

    // The main block: the drift value with a status pill once valid, otherwise the
    // state title with a progress bar and what is still missing.
    private function drawHero(dc as Graphics.Dc, x as Number, heroY as Float, statusY as Float,
                              heroFont as Graphics.FontType, titleFont as Graphics.FontType,
                              barWidth as Number) as Void {
        var state = driftEngine.getState(metric);
        if (state == DRIFT_VALID) {
            drawDriftValue(dc, x, heroY, heroFont, titleFont);
            drawPill(dc, x, statusY, stateTitle(metric), stateColor(metric));
            return;
        }

        dc.setColor(stateColor(metric), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, heroY, titleFont, stateTitle(metric),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var done = driftEngine.getProgressMinutes(metric);
        var total = driftEngine.getRequiredMinutes(metric);
        var caption = (metric == METRIC_RIDE ? "STEADY " : "RIDING ") + minutesText(done, total);
        if (state == DRIFT_WARMUP) {
            done = driftEngine.getWarmupElapsedSeconds() / 60;
            total = driftEngine.getWarmupSeconds() / 60;
            caption = "WARM-UP " + minutesText(done, total);
        } else if (state == DRIFT_NOT_STEADY && metric == METRIC_RIDE) {
            done = driftEngine.getSteadyPercent();
            total = driftEngine.getRequiredSteadyPercent();
            caption = "STEADY " + done.format("%d") + "% · NEED " + total.format("%d") + "%";
        } else if (state == DRIFT_NOT_STEADY) {
            done = driftEngine.getLastSteadyMinutes();
            total = driftEngine.getRequiredLastSteadyMinutes();
            caption = "STEADY " + minutesText(done, total);
        }
        var barHeight = 10;
        var barY = statusY - barHeight;
        drawProgress(dc, x - barWidth / 2, barY, barWidth, barHeight, done, total);
        drawLabel(dc, x, barY + barHeight * 3, caption, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Number font for the digits and a smaller "%" sharing their baseline.
    private function drawDriftValue(dc as Graphics.Dc, x as Number, y as Float,
                                    numberFont as Graphics.FontType,
                                    unitFont as Graphics.FontType) as Void {
        var text = driftTextFor(metric);
        var numberWidth = dc.getTextWidthInPixels(text, numberFont);
        var unitWidth = dc.getTextWidthInPixels("%", unitFont);
        var left = x - (numberWidth + unitWidth) / 2;
        var numberTop = y - dc.getFontHeight(numberFont) / 2;
        var baseline = numberTop + Graphics.getFontAscent(numberFont);
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, numberTop, numberFont, text, Graphics.TEXT_JUSTIFY_LEFT);
        dc.drawText(left + numberWidth, baseline - Graphics.getFontAscent(unitFont), unitFont,
            "%", Graphics.TEXT_JUSTIFY_LEFT);
    }

    // Per-minute Pw:HR line. Steady minutes (the ones drift uses) are drawn in the
    // metric's color, others muted; the dashed line is the selected metric's
    // first-half baseline, so drift shows as the line settling below it.
    private function drawTrend(dc as Graphics.Dc, x as Number, y as Number, width as Number,
                               height as Number) as Void {
        var history = driftEngine.getHistory();
        var size = history.getSize();
        var baseline = driftEngine.getBaselineEfficiency(metric);
        var points = 0;
        var steadyPoints = 0;
        for (var i = 0; i < size; i += 1) {
            if (history.getPoint(i) != null) {
                points += 1;
                if (history.isSteady(i)) {
                    steadyPoints += 1;
                }
            }
        }
        if (points < 2) {
            dc.setColor(mTrack, Graphics.COLOR_TRANSPARENT);
            dc.drawRoundedRectangle(x, y, width, height, 8);
            drawLabel(dc, x + width / 2, y + height / 2, "TREND AFTER 2 MIN OF RIDING",
                Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        // Scale to steady minutes when there are some, so warm-up or a climb does
        // not squash the part that matters; other points are clamped to the chart.
        var scaleSteadyOnly = steadyPoints >= 2;
        var low = baseline;
        var high = baseline;
        for (var i = 0; i < size; i += 1) {
            var point = history.getPoint(i);
            if (point != null && (!scaleSteadyOnly || history.isSteady(i))) {
                low = (low == null || point < low) ? point : low;
                high = (high == null || point > high) ? point : high;
            }
        }
        if (low == null || high == null) {
            return;
        }
        // A minimum 0.2 span keeps ordinary minute-to-minute noise from looking dramatic.
        var mid = (low + high) / 2.0f;
        var span = (high - low) * 1.3f;
        if (span < 0.2f) {
            span = 0.2f;
        }
        var bottom = mid - span / 2.0f;
        var step = width.toFloat() / (size - 1);

        if (baseline != null) {
            var baseY = chartY(baseline, bottom, span, y, height);
            dc.setColor(mMuted, Graphics.COLOR_TRANSPARENT);
            for (var dashX = x; dashX < x + width; dashX += 14) {
                dc.drawLine(dashX, baseY, dashX + 7, baseY);
            }
        }

        var lineColor = driftEngine.getState(metric) == DRIFT_VALID ? stateColor(metric) : mForeground;
        dc.setPenWidth(4);
        var hasLast = false;
        var lastX = 0;
        var lastY = 0;
        var lastSteady = false;
        for (var i = 0; i < size; i += 1) {
            var point = history.getPoint(i);
            if (point == null) {
                // Not enough valid data that minute: break the line.
                hasLast = false;
                continue;
            }
            var steady = history.isSteady(i);
            var pointX = x + (step * i).toNumber();
            var pointY = chartY(point, bottom, span, y, height);
            if (hasLast) {
                dc.setColor(steady && lastSteady ? lineColor : mTrack, Graphics.COLOR_TRANSPARENT);
                dc.drawLine(lastX, lastY, pointX, pointY);
            }
            lastX = pointX;
            lastY = pointY;
            lastSteady = steady;
            hasLast = true;
        }
        dc.setPenWidth(1);
        if (hasLast) {
            dc.setColor(lastSteady ? lineColor : mMuted, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(lastX, lastY, 7);
        }
    }

    private function chartY(value as Float, bottom as Float, span as Float, y as Number,
                            height as Number) as Number {
        var pointY = y + height - ((value - bottom) / span * height).toNumber();
        if (pointY < y) {
            return y;
        }
        return pointY > y + height ? y + height : pointY;
    }

    // Label, zone and value on one line; below it one equal-width segment per zone,
    // the current zone drawn thicker and a marker at the value's position.
    private function drawZoneGauge(dc as Graphics.Dc, x as Number, y as Number, width as Number,
                                   label as String, valueText as String, unit as String,
                                   value as Number?, zones as Array<Number>?) as Void {
        var valueFont = Graphics.FONT_NUMBER_MILD;
        var lineY = y + dc.getFontHeight(valueFont) / 2;
        drawLabel(dc, x, lineY, label, Graphics.TEXT_JUSTIFY_LEFT);

        var unitWidth = dc.getTextWidthInPixels(unit, Graphics.FONT_XTINY);
        var valueRight = x + width - unitWidth - 6;
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(valueRight, lineY, valueFont, valueText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawLabel(dc, x + width, lineY + dc.getFontHeight(valueFont) / 5, unit,
            Graphics.TEXT_JUSTIFY_RIGHT);

        var barY = y + dc.getFontHeight(valueFont) + 8;
        if (zones == null) {
            dc.setColor(mTrack, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(x, barY, width, 8, 4);
            drawLabel(dc, x + width / 2, lineY, "NO ZONES", Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }

        var zoneCount = zones.size() - 1;
        var colors = zoneCount > 5 ? ZONE_COLORS_7 : ZONE_COLORS_5;
        var current = value == null ? -1 : Zones.zoneIndex(value, zones);
        var gap = 4;
        var segmentWidth = (width - gap * (zoneCount - 1)) / zoneCount;
        for (var i = 0; i < zoneCount; i += 1) {
            var segmentX = x + i * (segmentWidth + gap);
            var thick = i == current;
            dc.setColor(colors[i % colors.size()], Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(segmentX, thick ? barY - 4 : barY, segmentWidth,
                thick ? 16 : 8, 4);
        }
        if (value == null) {
            return;
        }

        var zoneColor = colors[current % colors.size()];
        dc.setColor(zoneColor, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x + width * 2 / 5, lineY, Graphics.FONT_MEDIUM, "Z" + (current + 1).format("%d"),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Place the marker inside the current segment, accounting for the gaps.
        var zoneFraction = Zones.position(value, zones) * zoneCount - current;
        var markerX = x + current * (segmentWidth + gap) + (zoneFraction * segmentWidth).toNumber();
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(markerX, barY + 4, 11);
        dc.setColor(mBackground, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(markerX, barY + 4, 7);
        dc.setColor(zoneColor, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(markerX, barY + 4, 5);
    }

    private function drawPill(dc as Graphics.Dc, x as Number, y as Float, text as String,
                              color as Number) as Void {
        var font = Graphics.FONT_SMALL;
        var textHeight = dc.getFontHeight(font);
        var pillWidth = dc.getTextWidthInPixels(text, font) + textHeight * 2;
        var pillHeight = textHeight + textHeight / 3;
        dc.setColor(color, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x - pillWidth / 2, y - pillHeight / 2, pillWidth, pillHeight,
            pillHeight / 2);
        dc.setColor(mBackground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, font, text, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawProgress(dc as Graphics.Dc, x as Number, y as Float, width as Number,
                                  height as Number, done as Number, total as Number) as Void {
        dc.setColor(mTrack, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, width, height, height / 2);
        if (total <= 0 || done <= 0) {
            return;
        }
        var filled = done >= total ? width : width * done / total;
        if (filled < height) {
            filled = height;
        }
        dc.setColor(stateColor(metric), Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(x, y, filled, height, height / 2);
    }

    private function drawLabel(dc as Graphics.Dc, x as Number, y as Numeric, text as String,
                               justify as Number) as Void {
        dc.setColor(mMuted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, y, Graphics.FONT_XTINY, text, justify | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawRule(dc as Graphics.Dc, x1 as Number, x2 as Number, y as Float) as Void {
        dc.setColor(mTrack, Graphics.COLOR_TRANSPARENT);
        dc.drawLine(x1, y, x2, y);
    }

    private function otherMetric() as DriftMetric {
        return metric == METRIC_RIDE ? METRIC_LAST_60 : METRIC_RIDE;
    }

    function metricName(forMetric as DriftMetric) as String {
        return forMetric == METRIC_RIDE ? "RIDE" : "LAST 60";
    }

    // Compact value for a metric: the drift, or what it is waiting for.
    function summaryText(forMetric as DriftMetric) as String {
        var state = driftEngine.getState(forMetric);
        if (state == DRIFT_VALID) {
            return driftTextFor(forMetric) + "%";
        } else if (state == DRIFT_NOT_STEADY) {
            return "NOT STEADY";
        } else if (state == DRIFT_WARMUP) {
            return "WARM-UP";
        }
        return driftEngine.getProgressMinutes(forMetric).format("%d") + " / " +
            driftEngine.getRequiredMinutes(forMetric).format("%d") + "'";
    }

    // Completed / total minutes, e.g. "18 / 40 MIN".
    private function minutesText(done as Number, total as Number) as String {
        return done.format("%d") + " / " + total.format("%d") + " MIN";
    }

    // h:mm
    function durationText(seconds as Number) as String {
        var minutes = seconds / 60;
        return (minutes / 60).format("%d") + ":" + (minutes % 60).format("%02d");
    }

    function stateTitle(forMetric as DriftMetric) as String {
        var state = driftEngine.getState(forMetric);
        if (state == DRIFT_WARMUP) {
            return "WARMING UP";
        } else if (state == DRIFT_COLLECTING) {
            return "NOT READY";
        } else if (state == DRIFT_NOT_STEADY) {
            return "NOT STEADY";
        }
        var band = driftEngine.getBand(forMetric);
        if (band == BAND_HIGH) {
            return "HIGH DRIFT";
        }
        return band == BAND_WATCH ? "WATCH" : "STABLE";
    }

    private function stateColor(forMetric as DriftMetric) as Number {
        var state = driftEngine.getState(forMetric);
        if (state == DRIFT_NOT_STEADY) {
            return Graphics.COLOR_ORANGE;
        } else if (state != DRIFT_VALID) {
            return mForeground;
        }
        var band = driftEngine.getBand(forMetric);
        if (band == BAND_HIGH) {
            return Graphics.COLOR_RED;
        }
        return band == BAND_WATCH ? Graphics.COLOR_ORANGE : mGreen;
    }

    private function loadMetric() as Void {
        try {
            var stored = Application.Storage.getValue(METRIC_STORAGE_KEY);
            if (stored instanceof Number && (stored as Number) == METRIC_LAST_60) {
                metric = METRIC_LAST_60;
            }
        } catch (e) {
            // Storage can be unavailable; RIDE is the default.
        }
    }

    private function loadZones() as Void {
        var heartRateThresholds = null;
        if (UserProfile has :getHeartRateZones2) {
            heartRateThresholds = UserProfile.getHeartRateZones2(Activity.SPORT_CYCLING);
        } else {
            heartRateThresholds = UserProfile.getHeartRateZones(UserProfile.HR_ZONE_SPORT_BIKING);
        }
        heartRateZones = Zones.validated(heartRateThresholds as Array<Number>?);

        var powerThresholds = null;
        if (UserProfile has :getPowerZones) {
            powerThresholds = Zones.validated(
                UserProfile.getPowerZones(Activity.SPORT_CYCLING) as Array<Number>?);
        }
        if (powerThresholds == null && UserProfile has :getFunctionalThresholdPower) {
            var ftp = UserProfile.getFunctionalThresholdPower(Activity.SPORT_CYCLING);
            if (ftp != null && ftp > 0) {
                powerThresholds = Zones.fromFtp(ftp);
            }
        }
        powerZones = powerThresholds;
    }

    private function updatePalette() as Void {
        mBackground = getBackgroundColor();
        var dark = mBackground == Graphics.COLOR_BLACK;
        mForeground = dark ? Graphics.COLOR_WHITE : Graphics.COLOR_BLACK;
        mMuted = dark ? Graphics.COLOR_LT_GRAY : Graphics.COLOR_DK_GRAY;
        mTrack = dark ? Graphics.COLOR_DK_GRAY : Graphics.COLOR_LT_GRAY;
        mGreen = dark ? Graphics.COLOR_GREEN : Graphics.COLOR_DK_GREEN;
    }
}
