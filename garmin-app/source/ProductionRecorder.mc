import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.WatchUi;

// Writes DriftGuard's numbers into the activity FIT file so they can be compared
// with Intervals.icu on the same ride. Values change once per minute.
// Policy: 0 in a per-minute field means "no data that minute"; drift fields are
// meaningful only while the matching state field is VALID (codes at writeMinute).
class ProductionRecorder {
    // Record (per second, value updated each minute).
    private var mEfficiencyField as FitContributor.Field? = null;
    private var mSteadyField as FitContributor.Field? = null;
    private var mRideDriftField as FitContributor.Field? = null;
    private var mRideStateField as FitContributor.Field? = null;
    private var mCadenceField as FitContributor.Field? = null;
    // Session (last value written is kept).
    private var mSessionDriftField as FitContributor.Field? = null;
    private var mSessionStateField as FitContributor.Field? = null;
    private var mSessionSteadyField as FitContributor.Field? = null;
    private var mSessionPowerChangeField as FitContributor.Field? = null;
    private var mSessionCompatField as FitContributor.Field? = null;

    // Schema 2: base RECORD 11 B + repetitions 21 B = 32 B.
    // Base SESSION 14 B + metadata 9 B = 23 B. Calibration excludes extras.
    private var extra as Array<FitContributor.Field> = [];
    private var ready as Boolean = false;
    private var lastCompletion as Number = 0;
    private var mRepCounter as Number = 0;
    private const UNAVAILABLE = -9999.0f;

    private var mLastMinute as Number = 0;
    private var mCadenceSum as Number = 0;
    private var mCadenceSeconds as Number = 0;
    var lastCadence as Number = 0;

    // createField must be called while the data field is being initialized. If the
    // fields fail with a catchable exception, recording is disabled. VM allocation
    // errors are fatal: enforce byte budgets before launch, and pass null in tests.
    function initialize(field as WatchUi.DataField?) {
        if (field == null) {
            return;
        }
        try {
            mEfficiencyField = field.createField("dg_ef", 0, FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W/bpm"});
            mSteadyField = field.createField("dg_steady", 1, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "flag"});
            mRideDriftField = field.createField("dg_ride_drift", 2, FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "%"});
            mRideStateField = field.createField("dg_ride_state", 3, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "state"});
            mCadenceField = field.createField("dg_cadence", 4, FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rpm"});
            mSessionDriftField = field.createField("dg_ride_drift_final", 5,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            mSessionStateField = field.createField("dg_ride_state_final", 6,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "state"});
            mSessionSteadyField = field.createField("dg_steady_percent", 7,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            mSessionPowerChangeField = field.createField("dg_power_change", 8,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            mSessionCompatField = field.createField("dg_compat_drift", 9,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"});
            initializeIntervals(field);
            ready = true;
            ProductionRecorder.reset();
        } catch (e) { ready = false; }
    }

    (:production)
    function initializeIntervals(field as WatchUi.DataField) as Void {
        extra.add(field.createField("dg_rep_id", 14, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rep"}));
        extra.add(field.createField("dg_rep_w", 15, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W"}));
        extra.add(field.createField("dg_rep_s", 16, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"}));
        extra.add(field.createField("dg_rep_src", 17, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mode"}));
        extra.add(field.createField("dg_rep_hrr", 18, FitContributor.DATA_TYPE_SINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "bpm"}));
        extra.add(field.createField("dg_rep_evt", 19, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "event"}));
        extra.add(field.createField("dg_rep_hrr_active", 21, FitContributor.DATA_TYPE_SINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "bpm"}));
        extra.add(field.createField("dg_schema_version", 22, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "version"}));
        extra.add(field.createField("dg_last_valid_drift", 23, FitContributor.DATA_TYPE_FLOAT,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "%"}));
        extra.add(field.createField("dg_last_valid_minute", 24, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "min"}));
        extra.add(field.createField("dg_rep_count", 25, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "rep"}));
        extra.add(field.createField("dg_rep_quality", 27, FitContributor.DATA_TYPE_UINT8,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "flags"}));
        extra.add(field.createField("dg_rep_valid_s", 28, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"}));
        extra.add(field.createField("dg_rep_recovery_w", 29, FitContributor.DATA_TYPE_UINT16,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W"}));
        extra.add(field.createField("dg_rep_end_s", 30, FitContributor.DATA_TYPE_UINT32,
            {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"}));
    }
    (:calibration)
    function initializeIntervals(field as WatchUi.DataField) as Void {}

    function isRecording() as Boolean { return ready; }

    function reset() as Void {
        mLastMinute=0;resetCadence();lastCadence=0;
        lastCompletion=0;mRepCounter=0;
        if(!ready){return;}
        try {
            (mEfficiencyField as FitContributor.Field).setData(0.0f);
            (mSteadyField as FitContributor.Field).setData(0);
            (mCadenceField as FitContributor.Field).setData(0);
            (mRideDriftField as FitContributor.Field).setData(UNAVAILABLE);
            (mRideStateField as FitContributor.Field).setData(0);
            (mSessionDriftField as FitContributor.Field).setData(UNAVAILABLE);
            (mSessionStateField as FitContributor.Field).setData(0);
            (mSessionSteadyField as FitContributor.Field).setData(0);
            (mSessionPowerChangeField as FitContributor.Field).setData(UNAVAILABLE);
            (mSessionCompatField as FitContributor.Field).setData(UNAVAILABLE);
            for(var i=0;i<extra.size();i+=1){extra[i].setData(0);}
            if(extra.size()>0){
                extra[4].setData(-32768);extra[6].setData(-32768);
                extra[7].setData(2);extra[8].setData(UNAVAILABLE);
                extra[13].setData(65535);
            }
        } catch(e){ready=false;}
    }

    function effortMarker(intervals as IntervalSession) as String {
        return intervals.completionId.format("%d");
    }

    // Completion identity survives mode changes and repeated workout starts.
    // HRR carries its own parent; a previous recovery cannot attach to a new rep.
    function onIntervals(intervals as IntervalSession, recovery as HeartRecovery) as Void {
        if(!ready || extra.size()==0){return;}
        try {
            if(intervals.completionId>lastCompletion && intervals.lastSeconds>0){
                lastCompletion=intervals.completionId;
                // Never wrap: FIT IDs and total count must remain unambiguous.
                if(mRepCounter>=65534){ready=false;return;}
                mRepCounter+=1;
                var duration=intervals.lastSeconds;
                var valid=intervals.lastValidPower;
                var quality=(intervals.lastInterrupted ? 1 : 0) |
                    (valid<duration ? 2 : 0) | (duration>=240 ? 4 : 0) |
                    (duration>65534 ? 8 : 0);
                extra[0].setData(mRepCounter);
                extra[1].setData(intervals.lastMean==null ? 65535 : (intervals.lastMean as Float).toNumber());
                extra[2].setData(duration>65534 ? 65534 : duration);
                extra[3].setData(intervals.source.equals("AUTO") ? 1 : intervals.source.equals("MANUAL") ? 2 : 3);
                extra[4].setData(-32768);extra[6].setData(-32768);
                extra[5].setData(1);extra[10].setData(mRepCounter);
                extra[11].setData(quality);extra[12].setData(valid>65534 ? 65534 : valid);
                extra[13].setData(65535);extra[14].setData(intervals.lastEndSeconds);
            }
            if(mRepCounter>0 && recovery.parentId==lastCompletion){
                if(recovery.delta!=null){extra[4].setData((recovery.delta as Float).toNumber());extra[5].setData(2);}
                if(recovery.activeDelta!=null){extra[6].setData((recovery.activeDelta as Float).toNumber());extra[5].setData(3);}
                var watts=recovery.meanRecoveryPower();
                if(watts!=null){extra[13].setData(watts.toNumber());}
            }
        } catch(e){ready=false;}
    }

    // Called every second after the engine has taken the sample.
    function onSecond(engine as DriftEngine, cadence as Number?, isTimerRunning as Boolean) as Void {
        if (isTimerRunning && cadence != null && cadence > 0 && cadence < 255) {
            // Pedalling cadence only: coasting would pull the average down.
            mCadenceSum += cadence;
            mCadenceSeconds += 1;
        }
        var minutes = engine.getMinutes();
        if (minutes == mLastMinute) {
            return;
        }
        mLastMinute = minutes;
        writeMinute(engine);
    }

    // Numeric codes for the state fields: 0 warm-up, 1 collecting, 2 not steady,
    // 3 power changed, 4 valid (the DriftState order).
    function writeMinute(engine as DriftEngine) as Void {
        lastCadence = mCadenceSeconds == 0 ? 0 : mCadenceSum / mCadenceSeconds;
        resetCadence();
        if (!isRecording()) {
            return;
        }

        try {
        var history = engine.getHistory();
        var size = history.getSize();
        var efficiency = history.getLatest();
        (mEfficiencyField as FitContributor.Field).setData(efficiency == null ? 0.0f : efficiency);
        (mSteadyField as FitContributor.Field).setData(
            size > 0 && history.isSteady(size - 1) ? 1 : 0);
        (mCadenceField as FitContributor.Field).setData(lastCadence > 254 ? 254 : lastCadence);

        var state = engine.getState(METRIC_RIDE) as Number;
        (mRideStateField as FitContributor.Field).setData(state);
        (mSessionStateField as FitContributor.Field).setData(state);
        var drift = engine.getDriftPercent(METRIC_RIDE);
        (mRideDriftField as FitContributor.Field).setData(drift==null ? UNAVAILABLE : drift);
        (mSessionDriftField as FitContributor.Field).setData(drift==null ? UNAVAILABLE : drift);
        var powerChange = engine.getPowerChangePercent(METRIC_RIDE);
        (mSessionPowerChangeField as FitContributor.Field).setData(powerChange==null ? UNAVAILABLE : powerChange);
        if(extra.size()>0){
            extra[8].setData(engine.lastValidDrift==null ? UNAVAILABLE : (engine.lastValidDrift as Float));
            extra[9].setData(engine.lastValidMinute>65534 ? 65534 : engine.lastValidMinute);
        }
        (mSessionSteadyField as FitContributor.Field).setData(engine.getSteadyPercent());
        var compat = engine.getCompatDriftPercent();
        (mSessionCompatField as FitContributor.Field).setData(compat==null ? UNAVAILABLE : compat);
        } catch(e){ready=false;}
    }

    private function resetCadence() as Void {
        mCadenceSum = 0;
        mCadenceSeconds = 0;
    }
}
