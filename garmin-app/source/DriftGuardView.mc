import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.UserProfile;
import Toybox.WatchUi;

class DriftGuardView extends WatchUi.DataField {
    private const POWER_AVERAGE_SECONDS = 3;
    private const SCREEN_STORAGE_KEY = "screen";
    // Shared full-page anchors keep both screens still when toggled.
    private const FULL_HEADER_Y = 0.05;
    private const FULL_HERO_Y = 0.12;
    private const FULL_STATUS_Y = 0.205;
    private const FULL_SUMMARY_LABEL_Y = 0.255;
    private const FULL_SUMMARY_VALUE_Y = 0.30;
    private const FULL_CHART_LABEL_Y = 0.395;
    private const FULL_CHART_TOP = 0.435;
    private const FULL_CHART_BOTTOM = 0.685;
    private const FULL_RULE_Y = 0.705;
    private const FULL_POWER_Y = 0.735;
    private const FULL_HR_Y = 0.845;
    var intervals as IntervalSession;
    var recovery as HeartRecovery;
    var intervalHistory as IntervalHistory;
    var intervalScreen as Boolean = false;
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
    var recorder as DriftRecorder;
    // RIDE is preferred on DRIFT; fallback can show LAST 60 large.
    var metric as DriftMetric = METRIC_RIDE;
    // The metric actually drawn large this update (see displayMetric).
    private var mShown as DriftMetric = METRIC_RIDE;

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

    // recordFit is false only in unit tests, where the view is not part of an
    // activity and FIT fields cannot be created.
    function initialize(recordFit as Boolean) {
        DataField.initialize();
        driftEngine = new DriftEngine(null);
        recorder = new DriftRecorder(recordFit ? self : null);
        loadZones();
        intervals = new IntervalSession();
        recovery = new HeartRecovery();
        intervalHistory = new IntervalHistory();
        loadScreen();
    }

    function compute(info as Activity.Info) as Void {
        var power = info.currentPower;
        if(power!=null && (power<0 || power>10000)){power=null;}
        var currentHeartRate = info.currentHeartRate;
        if(currentHeartRate!=null && (currentHeartRate<=0 || currentHeartRate>300)){currentHeartRate=null;}

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
        intervalHistory.add(power,currentHeartRate,isTimerRunning);
        recovery.sample(currentHeartRate,power,isTimerRunning);
        var priorEnd=intervals.automatic.detectedEnd;
        var priorSequence=intervals.automatic.sequence;
        intervals.addSample(power, isTimerRunning);
        if (intervals.source.equals("AUTO")) {
            if (priorSequence!=intervals.automatic.sequence && intervals.automatic.active) { recovery.cancel("NEW EFFORT"); }
            if (priorEnd!=intervals.automatic.detectedEnd && !intervals.lastInterrupted && !intervals.automatic.active) {
                recovery.begin(5,intervals.lastMean,intervals.lastSeconds);
                recovery.parentId=intervals.completionId;
            }
        }
        recorder.onSecond(driftEngine, info.currentCadence, isTimerRunning);
        recorder.onIntervals(intervals, recovery);
        // Instant power / HR is noise (HR lags power); show the last full minute instead.
        var ratio = driftEngine.getHistory().getLatest();
        ratioText = ratio == null ? "--" : ratio.format("%.2f");
    }

    // Called when the activity is saved or discarded: the next ride starts clean.
    function onTimerReset() as Void {
        driftEngine.reset();
        intervals.reset();
        recovery.reset();
        intervalHistory.reset();
        recorder.reset();
        mPowerWindowCount = 0;
        ratioText = "--";
        // Zones may have been edited in Garmin Connect since the field started.
        loadZones();
    }

    function toggleScreen() as Void {
        intervalScreen = !intervalScreen;
        try {
            Application.Storage.setValue(SCREEN_STORAGE_KEY, intervalScreen ? 1 : 0);
        } catch (e) {}
    }

    function onWorkoutStarted() as Void { intervals.startWorkout(); recovery.reset(); }
    function onWorkoutStepComplete() as Void { intervalBoundary(true); }
    private function intervalBoundary(workout as Boolean) as Void {
        var explicitSource=intervals.source.equals("WORKOUT") || intervals.source.equals("MANUAL");
        var oldSequence=intervals.sequence;
        var oldSeconds=intervals.seconds;
        var oldValid=intervals.validPower;
        intervals.boundary(workout);
        if (explicitSource && oldSeconds>0 && intervals.sequence!=oldSequence) {
            if (oldValid==oldSeconds && !intervals.lastInterrupted) { recovery.begin(0,intervals.lastMean,intervals.lastSeconds); recovery.parentId=intervals.completionId; }
            else { recovery.cancel("POWER MISSING"); }
        } else if (!explicitSource) { recovery.cancel("NEW SEGMENT"); }
        recorder.onIntervals(intervals, recovery);
    }
    function onTimerLap2(trigger as WatchUi.DataField.LapInfoType) as Boolean {
        if (trigger[:lapTrigger] == WatchUi.DataField.LAP_TRIGGER_MANUAL) {
            intervalBoundary(false);
        }
        // Consume all lap notifications so the legacy callback cannot duplicate one.
        return true;
    }

    function driftTextFor(forMetric as DriftMetric) as String {
        var drift = driftEngine.getDriftPercent(forMetric);
        return drift == null ? "--" : drift.format("%.1f");
    }

    // The selected metric, unless it has given up on this ride (POWER CHANGED or
    // NOT STEADY) while the other one has a value: then the other is shown large
    // and the selected one is reduced to its one-line summary.
    function displayMetric() as DriftMetric {
        var state = driftEngine.getState(metric);
        var other = metric == METRIC_RIDE ? METRIC_LAST_60 : METRIC_RIDE;
        if ((state == DRIFT_POWER_CHANGED || state == DRIFT_NOT_STEADY) &&
            driftEngine.getState(other) == DRIFT_VALID) {
            return other;
        }
        return metric;
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        mShown = displayMetric();
        updatePalette();
        dc.setColor(mForeground, mBackground);
        dc.clear();

        if (intervalScreen) { drawIntervals(dc); return; }
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

        drawTabs(dc, center, height * FULL_HEADER_Y);
        drawHero(dc, center, height * (height>=700 ? FULL_HERO_Y : 0.165), height * (height>=700 ? FULL_STATUS_Y : 0.295),
            height>=700 ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_THAI_HOT,
            Graphics.FONT_LARGE, width - 2 * margin);

        var left = width / 4;
        var right = width * 3 / 4;
        var other = otherMetric();
        dc.setColor(mMuted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, height * (height>=700 ? FULL_SUMMARY_LABEL_Y : 0.39),
            height>=700 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY, metricName(other),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(right, height * (height>=700 ? FULL_SUMMARY_LABEL_Y : 0.39),
            height>=700 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY, "STEADY TIME",
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        var summaryAlign = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        dc.setColor(stateColor(other), Graphics.COLOR_TRANSPARENT);
        dc.drawText(left, height * (height>=700 ? FULL_SUMMARY_VALUE_Y : 0.425), Graphics.FONT_MEDIUM, summaryText(other), summaryAlign);
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(right, height * (height>=700 ? FULL_SUMMARY_VALUE_Y : 0.425), Graphics.FONT_MEDIUM,
            durationText(driftEngine.getSteadySeconds()), summaryAlign);

        dc.setColor(mMuted, Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin, height * (height>=700 ? FULL_CHART_LABEL_Y : 0.49),
            height>=700 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY, "PW:HR · 1 MIN",
            Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(mForeground, Graphics.COLOR_TRANSPARENT);
        dc.drawText(width - margin, height * (height>=700 ? FULL_CHART_LABEL_Y : 0.49), Graphics.FONT_SMALL, ratioText,
            Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER);
        var chartTop = (height * (height>=700 ? FULL_CHART_TOP : 0.52)).toNumber();
        drawTrend(dc, margin, chartTop, width - 2 * margin, (height * (height>=700 ? FULL_CHART_BOTTOM : 0.645)).toNumber() - chartTop);
        drawFullGauges(dc);
    }

    // Half-page style field: selected metric large, the other metric and steady time below.
    private function drawMedium(dc as Graphics.Dc) as Void {
        var width = dc.getWidth();
        var height = dc.getHeight();
        var center = width / 2;
        var heroFont = height >= 300 ? Graphics.FONT_NUMBER_HOT : Graphics.FONT_NUMBER_MEDIUM;
        var titleFont = height >= 300 ? Graphics.FONT_LARGE : Graphics.FONT_MEDIUM;

        drawLabel(dc, center, height * 0.10, metricName(mShown) + " DRIFT",
            Graphics.TEXT_JUSTIFY_CENTER);
        drawHero(dc, center, height * 0.40, height * 0.68, heroFont, titleFont, width * 3 / 4);
        var other = otherMetric();
        drawLabel(dc, center, height * 0.89, metricName(other) + " " + summaryText(other) +
            "   STEADY " + durationText(driftEngine.getSteadySeconds()),
            Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Small field: value (or progress) and the metric with a colored state word.
    private function drawSmall(dc as Graphics.Dc) as Void {
        var x = dc.getWidth() / 2;
        var h = dc.getHeight();
        drawLabel(dc, x, h * 0.30, "RIDE " + summaryText(METRIC_RIDE), Graphics.TEXT_JUSTIFY_CENTER);
        drawLabel(dc, x, h * 0.72, "LAST 60 " + summaryText(METRIC_LAST_60), Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawIntervals(dc as Graphics.Dc) as Void {
        if (dc.getHeight()>=500) { drawIntervalsFull(dc); return; }
        var x=dc.getWidth()/2;
        var h=dc.getHeight();
        var align=Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var compact=h<150;
        var autoMode=intervals.source.equals("AUTO");
        var waiting=autoMode ? !intervals.automatic.active : intervals.sequence==0;
        var title="INTERVALS / " + (intervals.source.equals("AUTO") && intervals.automatic.experimental ? "AUTO EXP" : intervals.source);
        if (autoMode && intervals.automatic.active && intervals.seconds<20) { title="CONFIRMING"; }
        if (compact) {
            var heading=title;
            if (waiting) {
                heading=intervals.paused ? "PAUSED" : "AUTO WAIT";
                if (autoMode && !intervals.paused && intervals.automatic.noPower) { heading="NO POWER"; }
                else if (autoMode && !intervals.paused && intervals.automatic.historyCount<60) {
                    heading="BASE " + intervals.automatic.historyCount.format("%d") + "/60";
                }
            }
            drawLabel(dc,x,h*0.16,heading,Graphics.TEXT_JUSTIFY_CENTER);
            var current=intervals.meanPower();
            var middle=current==null ? "-- W" : current.format("%.0f") + "W " + intervals.seconds.format("%d") + "s";
            var previous=intervals.lastMean;
            if (waiting && previous!=null) { middle="LAST " + previous.format("%.0f") + "W" + (intervals.lastInterrupted ? " *" : ""); }
            drawLabel(dc,x,h*0.48,middle,Graphics.TEXT_JUSTIFY_CENTER);
            drawLabel(dc,x,h*0.80,"HR" + heartRateText + " " + recovery.inlineText(),Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        drawLabel(dc,x,h*0.12,title,Graphics.TEXT_JUSTIFY_CENTER);
        if (waiting) {
            var status=intervals.paused ? "PAUSED" : "WAITING";
            if (!intervals.paused && autoMode && intervals.automatic.noPower) { status="NO POWER"; }
            else if (!intervals.paused && autoMode && intervals.automatic.historyCount<60) {
                status="BASELINE " + intervals.automatic.historyCount.format("%d") + "/60 s";
            }
            drawLabel(dc,x,h*0.34,status,Graphics.TEXT_JUSTIFY_CENTER);
            drawLabel(dc,x,h*0.50,"HR " + heartRateText + " bpm",Graphics.TEXT_JUSTIFY_CENTER);
            var last=intervals.lastMean;
            var caption=last==null ? "RIDE TO DETECT" : "LAST " + last.format("%.0f") + " W / " + intervals.lastSeconds.format("%d") + " s";
            drawLabel(dc,x,h*0.66,caption,Graphics.TEXT_JUSTIFY_CENTER);
            drawLabel(dc,x,h*0.88,(compact ? recovery.compactText() : recovery.text()),Graphics.TEXT_JUSTIFY_CENTER);
            return;
        }
        var mean=intervals.meanPower();
        var text=mean==null ? "--" : mean.format("%.0f");
        if (h<300) { text+=" W"; }
        dc.drawText(x,h*0.40,h<300 ? Graphics.FONT_MEDIUM : Graphics.FONT_NUMBER_MEDIUM,text,align);
        if (h>=300) { drawLabel(dc,x,h*0.52,"AVG POWER (W)",Graphics.TEXT_JUSTIFY_CENTER); }
        var elapsed=(intervals.seconds/60).format("%d") + ":" + (intervals.seconds%60).format("%02d");
        var detail=(intervals.paused ? "PAUSED " : "") + elapsed;
        if (!autoMode && !compact) { detail+=" / " + intervals.validPower.format("%d") + " PWR samples"; }
        drawLabel(dc,x,h*0.63,detail,Graphics.TEXT_JUSTIFY_CENTER);
        drawLabel(dc,x,h*0.76,"HR " + heartRateText + " bpm",Graphics.TEXT_JUSTIFY_CENTER);
        var footer=autoMode ? "AUTO / #" + intervals.sequence.format("%d") : intervals.source;
        if (intervals.interrupted) { footer+=" / INTERRUPTED"; }
        drawLabel(dc,x,h*0.90,(compact ? recovery.compactText() : recovery.text()),Graphics.TEXT_JUSTIFY_CENTER);
    }

    private function drawIntervalsFull(dc as Graphics.Dc) as Void {
        // Small render frames preserve stack space for nested zone calculations.
        drawIntervalHeader(dc);
        drawIntervalSummary(dc);
        drawIntervalCharts(dc);
        drawFullGauges(dc);
    }
    private function drawIntervalHeader(dc as Graphics.Dc) as Void {
        var w=dc.getWidth(); var h=dc.getHeight(); var x=w/2; var margin=w/12;
        var large=h>=700;
        var align=Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var autoMode=intervals.source.equals("AUTO");
        var waiting=autoMode ? !intervals.automatic.active : intervals.sequence==0;
        drawLabel(dc,x,h*FULL_HEADER_Y,"INTERVALS / " + (intervals.source.equals("AUTO") && intervals.automatic.experimental ? "AUTO EXP" : intervals.source),Graphics.TEXT_JUSTIFY_CENTER);
        var mean=intervals.meanPower();
        if (!waiting && mean!=null && !intervals.paused) {
            dc.setColor(mForeground,Graphics.COLOR_TRANSPARENT);
            dc.drawText(x,h*(large ? FULL_HERO_Y : 0.18),Graphics.FONT_NUMBER_HOT,mean.format("%.0f"),align);
            drawLabel(dc,x,h*(large ? 0.17 : 0.255),"AVG POWER / W",Graphics.TEXT_JUSTIFY_CENTER);
            var caption=intervalDurationText(intervals.seconds);
            if(autoMode && intervals.seconds>=240){caption="SUSTAINED / "+caption;}
            if (autoMode && intervals.seconds<20) { caption="CONFIRMING / " + caption; }
            drawPill(dc,x,h*(large ? FULL_STATUS_Y : 0.315),caption,mMuted);
        } else {
            var status=intervals.paused ? "PAUSED" : "WAITING";
            if (autoMode && !intervals.paused && intervals.automatic.noPower) { status="NO POWER"; }
            else if (autoMode && !intervals.paused && intervals.automatic.historyCount<60) { status="COLLECTING"; }
            dc.setColor(mForeground,Graphics.COLOR_TRANSPARENT);
            dc.drawText(x,h*(large ? FULL_HERO_Y : 0.195),Graphics.FONT_LARGE,status,align);
            var caption="RIDE TO DETECT EFFORTS";
            if (autoMode && !intervals.paused && !intervals.automatic.noPower && intervals.automatic.historyCount<60) {
                drawProgress(dc,margin,h*(large ? 0.165 : 0.30),w-2*margin,10,intervals.automatic.historyCount,60);
                caption="BASELINE " + intervals.automatic.historyCount.format("%d") + " / 60 S";
            }
            drawLabel(dc,x,h*(large ? FULL_STATUS_Y : 0.34),caption,Graphics.TEXT_JUSTIFY_CENTER);
        }
    }
    private function drawIntervalSummary(dc as Graphics.Dc) as Void {
        var w=dc.getWidth(); var h=dc.getHeight(); var margin=w/12;
        var large=h>=700;
        var align=Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
        var labelFont=large ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
        var valueFont=large ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL;
        dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
        var labelsY=h*(large ? FULL_SUMMARY_LABEL_Y : 0.39);
        var valuesY=h*(large ? FULL_SUMMARY_VALUE_Y : 0.425);
        dc.drawText(w/4,labelsY,labelFont,"LAST EFFORT",align);
        dc.drawText(w*3/4,labelsY,labelFont,recovery.delta==null && recovery.activeDelta!=null ? "ACTIVE HRR60" : "HRR60",align);
        var previous=intervals.lastMean;
        var last=previous==null ? "--" : previous.format("%.0f") + " W";
        if(intervals.lastInterrupted){last+=" *";}
        dc.setColor(mForeground,Graphics.COLOR_TRANSPARENT);
        dc.drawText(w/4,valuesY,valueFont,last,align);
        var hrValue=recovery.delta!=null ? recovery.delta : recovery.activeDelta;
        var response=hrValue==null ? recovery.reason : hrValue.format("%+.0f");
        if (recovery.collecting || recovery.activeCollecting) { response=recovery.elapsed.format("%d") + " / 60 S"; }
        var responseFont=dc.getTextWidthInPixels(response,valueFont)<=w/2-margin ? valueFont : labelFont;
        dc.drawText(w*3/4,valuesY,responseFont,response,align);
        if (large) {
            dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
            dc.drawText(w/4,h*0.35,labelFont,intervals.lastSeconds==0 ? "--:--" : (intervals.lastInterrupted ? "PARTIAL " : "") + intervalDurationText(intervals.lastSeconds),align);
            dc.drawText(w*3/4,h*0.35,labelFont,recovery.meanRecoveryPower()==null ? "BPM / 60 S" : "REC "+(recovery.meanRecoveryPower() as Float).format("%.0f")+" W",align);
        }
    }
    private function drawIntervalCharts(dc as Graphics.Dc) as Void {
        var w=dc.getWidth(); var h=dc.getHeight(); var margin=w/12;
        var large=h>=700;
        var labelFont=large ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
        dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin,h*(large ? FULL_CHART_LABEL_Y : 0.465),labelFont,"POWER (W) / 3 MIN",Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawIntervalPlot(dc,margin,(h*(large ? FULL_CHART_TOP : 0.485)).toNumber(),w-2*margin,(h*(large ? 0.09 : 0.07)).toNumber(),false);
        dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
        dc.drawText(margin,h*(large ? 0.565 : 0.575),labelFont,"HR (BPM) / 3 MIN",Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        drawIntervalPlot(dc,margin,(h*(large ? 0.605 : 0.595)).toNumber(),w-2*margin,(h*(large ? 0.08 : 0.07)).toNumber(),true);
    }
    private function drawFullGauges(dc as Graphics.Dc) as Void {
        var w=dc.getWidth(); var h=dc.getHeight(); var margin=w/12;
        var large=h>=700;
        drawRule(dc,margin,w-margin,h*(large ? FULL_RULE_Y : 0.68));
        drawZoneGauge(dc,margin,(h*(large ? FULL_POWER_Y : 0.705)).toNumber(),w-2*margin,"POWER 3S",powerText,"W",power3s,powerZones);
        drawZoneGauge(dc,margin,(h*FULL_HR_Y).toNumber(),w-2*margin,"HEART RATE",heartRateText,"BPM",heartRate,heartRateZones);
    }

    private function drawIntervalPlot(dc as Graphics.Dc,x as Number,y as Number,w as Number,h as Number,heart as Boolean) as Void {
        dc.setColor(mTrack,Graphics.COLOR_TRANSPARENT);
        dc.drawRoundedRectangle(x,y,w,h,8);
        var low=10000; var high=0; var count=0;
        for (var i=0;i<intervalHistory.size;i+=1) {
            var value=intervalHistory.point(i,heart);
            if (value!=null) { count+=1; if (value<low) { low=value; } if (value>high) { high=value; } }
        }
        if (count<2) {
            dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
            dc.drawText(x+w/2,y+h/2,w>=360 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY,"WAITING FOR DATA",Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER); return;
        }
        if (!heart) { low=0; if (high<200) { high=200; } high+=20; }
        else { low-=5; if (low<0) { low=0; } high+=5; if (high-low<10) { high=low+10; } }
        var span=(high-low).toFloat();
        var axisFont=w>=360 && h>=60 ? Graphics.FONT_SMALL : Graphics.FONT_XTINY;
        var axisWidth=dc.getTextWidthInPixels(high.format("%d"),axisFont);
        var lowWidth=dc.getTextWidthInPixels(low.format("%d"),axisFont);
        if (lowWidth>axisWidth) { axisWidth=lowWidth; }
        var plotW=w-axisWidth-20; var plotH=h-12;
        var lastX=0; var lastY=0; var connected=false;
        dc.setColor(heart ? 0x2F7FE0 : mForeground,Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(2);
        for (var j=0;j<intervalHistory.size;j+=1) {
            var point=intervalHistory.point(j,heart);
            if (point==null) { connected=false; continue; }
            var px=x+6+((intervalHistory.CAPACITY-intervalHistory.size+j)*plotW/(intervalHistory.CAPACITY-1));
            var py=chartY(point.toFloat(),low.toFloat(),span,y+6,plotH);
            if (connected) { dc.drawLine(lastX,lastY,px,py); }
            lastX=px; lastY=py; connected=true;
        }
        dc.setPenWidth(1);
        if (connected) { dc.fillCircle(lastX,lastY,3); }
        dc.setColor(mMuted,Graphics.COLOR_TRANSPARENT);
        dc.drawText(x+w-5,y+2,axisFont,high.format("%d"),Graphics.TEXT_JUSTIFY_RIGHT);
        if (h>=2*dc.getFontHeight(axisFont)+6) { dc.drawText(x+w-5,y+h-dc.getFontHeight(axisFont)-2,axisFont,low.format("%d"),Graphics.TEXT_JUSTIFY_RIGHT); }
    }

    // Screen title identifies which of the two drift results is drawn large.
    private function drawTabs(dc as Graphics.Dc, x as Number, y as Float) as Void {
        drawLabel(dc, x, y, "DRIFT / " + metricName(mShown), Graphics.TEXT_JUSTIFY_CENTER);
    }

    // The main block: the drift value with a status pill once valid, otherwise the
    // state title with a progress bar and what is still missing.
    private function drawHero(dc as Graphics.Dc, x as Number, heroY as Float, statusY as Float,
                              heroFont as Graphics.FontType, titleFont as Graphics.FontType,
                              barWidth as Number) as Void {
        var state = driftEngine.getState(mShown);
        if (state == DRIFT_VALID) {
            drawDriftValue(dc, x, heroY, heroFont, titleFont);
            drawPill(dc, x, statusY, stateTitle(mShown), stateColor(mShown));
            return;
        }

        dc.setColor(stateColor(mShown), Graphics.COLOR_TRANSPARENT);
        dc.drawText(x, heroY, titleFont, stateTitle(mShown),
            Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var done = driftEngine.getProgressMinutes(mShown);
        var total = driftEngine.getRequiredMinutes(mShown);
        var caption = (mShown == METRIC_RIDE ? "STEADY " : "RIDING ") + minutesText(done, total);
        if (state == DRIFT_WARMUP) {
            done = driftEngine.getWarmupElapsedSeconds() / 60;
            total = driftEngine.getWarmupSeconds() / 60;
            caption = "WARM-UP " + minutesText(done, total);
        } else if (state == DRIFT_NOT_STEADY && mShown == METRIC_RIDE) {
            done = driftEngine.getSteadyPercent();
            total = driftEngine.getRequiredSteadyPercent();
            caption = "STEADY " + done.format("%d") + "% · NEED " + total.format("%d") + "%";
        } else if (state == DRIFT_NOT_STEADY) {
            done = driftEngine.getLastSteadyMinutes();
            total = driftEngine.getRequiredLastSteadyMinutes();
            caption = "STEADY " + minutesText(done, total);
        } else if (state == DRIFT_POWER_CHANGED) {
            // No progress bar: the halves must be ridden at similar power.
            done = 0;
            total = 0;
            var change = driftEngine.getPowerChangePercent(mShown) as Float;
            caption = "2ND HALF " + (change > 0 ? "+" : "") + change.format("%.0f") +
                "% · MAX ±" + driftEngine.getMaxPowerChangePercent().format("%.0f") + "%";
        }
        var barHeight = 10;
        var barY = statusY - (dc.getHeight()>=700 ? 30 : barHeight);
        if (total > 0) {
            drawProgress(dc, x - barWidth / 2, barY, barWidth, barHeight, done, total);
        }
        drawLabel(dc, x, (dc.getHeight()>=700 ? statusY : barY + barHeight * 3), caption, Graphics.TEXT_JUSTIFY_CENTER);
    }

    // Number font for the digits and a smaller "%" sharing their baseline.
    private function drawDriftValue(dc as Graphics.Dc, x as Number, y as Float,
                                    numberFont as Graphics.FontType,
                                    unitFont as Graphics.FontType) as Void {
        var text = driftTextFor(mShown);
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
        var baseline = driftEngine.getBaselineEfficiency(mShown);
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

        var lineColor = driftEngine.getState(mShown) == DRIFT_VALID ? stateColor(mShown) : mForeground;
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
        dc.setColor(stateColor(mShown), Graphics.COLOR_TRANSPARENT);
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
        return mShown == METRIC_RIDE ? METRIC_LAST_60 : METRIC_RIDE;
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
        } else if (state == DRIFT_POWER_CHANGED) {
            var change = driftEngine.getPowerChangePercent(forMetric) as Float;
            return "PWR " + (change > 0 ? "+" : "") + change.format("%.0f") + "%";
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
    function intervalDurationText(seconds as Number) as String {
        if (seconds>=3600) {
            return (seconds/3600).format("%d") + ":" + ((seconds/60)%60).format("%02d") + ":" + (seconds%60).format("%02d");
        }
        return (seconds/60).format("%d") + ":" + (seconds%60).format("%02d");
    }

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
        } else if (state == DRIFT_POWER_CHANGED) {
            return "POWER CHANGED";
        }
        var band = driftEngine.getBand(forMetric);
        if (band == BAND_HIGH) {
            return "HIGH DRIFT";
        } else if (band == BAND_WATCH) {
            return "WATCH";
        }
        return band == BAND_NEGATIVE ? "NEGATIVE" : "STABLE";
    }

    private function stateColor(forMetric as DriftMetric) as Number {
        var state = driftEngine.getState(forMetric);
        if (state == DRIFT_NOT_STEADY || state == DRIFT_POWER_CHANGED) {
            return Graphics.COLOR_ORANGE;
        } else if (state != DRIFT_VALID) {
            return mForeground;
        }
        var band = driftEngine.getBand(forMetric);
        if (band == BAND_HIGH) {
            return Graphics.COLOR_RED;
        } else if (band == BAND_WATCH) {
            return Graphics.COLOR_ORANGE;
        }
        // Negative drift is neither good nor bad news on its own: neutral color.
        return band == BAND_NEGATIVE ? mMuted : mGreen;
    }

    private function loadScreen() as Void {
        // Old metric storage is deliberately ignored: migrate to DRIFT with both values.
        try {
            var stored = Application.Storage.getValue(SCREEN_STORAGE_KEY);
            intervalScreen = stored instanceof Number && stored == 1;
        } catch (e) {}
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
