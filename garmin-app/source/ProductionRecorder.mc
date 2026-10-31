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

    // Session-only summaries avoid adding to the 32-byte RECORD developer field budget.
    // These are the LAST completed effort / LAST valid recovery, not ride averages.
    private var mLastEffortPowerField as FitContributor.Field? = null;
    private var mLastEffortSecondsField as FitContributor.Field? = null;
    private var mLastEffortSourceField as FitContributor.Field? = null;
    private var mLastHrr60Field as FitContributor.Field? = null;
    private var mLastEffortMarker as String = "";
    private var mLastHrrMarker as String = "";

    // Per-effort RECORD stream. 2+2+2+1+2+1 = 10 additional bytes;
    // existing RECORD fields consume 14 B, staying below the 32 B cap.
    private var mRepIdField as FitContributor.Field? = null;
    private var mRepPowerField as FitContributor.Field? = null;
    private var mRepSecondsField as FitContributor.Field? = null;
    private var mRepSourceField as FitContributor.Field? = null;
    private var mRepHrrField as FitContributor.Field? = null;
    private var mRepEventField as FitContributor.Field? = null;
    private var mRepCounter as Number = 0;
    private var mPendingHrrRep as Number = 0;

    private var mLastMinute as Number = 0;
    private var mCadenceSum as Number = 0;
    private var mCadenceSeconds as Number = 0;
    var lastCadence as Number = 0;

    // createField must be called while the data field is being initialized. If the
    // fields cannot be created (e.g. unit tests, or the device's FIT field budget
    // is used up by other apps), recording is off and everything else still works.
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
            mLastEffortPowerField = field.createField("dg_last_effort_w", 10,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "W"});
            mLastEffortSecondsField = field.createField("dg_last_effort_s", 11,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "s"});
            mLastEffortSourceField = field.createField("dg_last_effort_src", 12,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "mode"});
            mLastHrr60Field = field.createField("dg_hrr60_last", 13,
                FitContributor.DATA_TYPE_FLOAT,
                {:mesgType => FitContributor.MESG_TYPE_SESSION, :units => "bpm"});
            mRepIdField = field.createField("dg_rep_id", 14,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "rep"});
            mRepPowerField = field.createField("dg_rep_w", 15,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "W"});
            mRepSecondsField = field.createField("dg_rep_s", 16,
                FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "s"});
            mRepSourceField = field.createField("dg_rep_src", 17,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "mode"});
            mRepHrrField = field.createField("dg_rep_hrr", 18,
                FitContributor.DATA_TYPE_SINT16,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "bpm"});
            mRepEventField = field.createField("dg_rep_evt", 19,
                FitContributor.DATA_TYPE_UINT8,
                {:mesgType => FitContributor.MESG_TYPE_RECORD, :units => "event"});
        } catch (e) {
            mEfficiencyField = null;
        }
    }

    // True when every FIT field was created and values are being recorded.
    function isRecording() as Boolean {
        return mSessionCompatField != null && mEfficiencyField != null;
    }

    function reset() as Void {
        mLastMinute = 0;
        resetCadence();
        lastCadence = 0;
        mLastEffortMarker = "";
        mLastHrrMarker = "";
        mRepCounter = 0;
        mPendingHrrRep = 0;
    }

    // AUTO sequence advances at START; detectedEnd changes only on completion.
    // Keying held lastMean by sequence records the previous effort again at next start.
    function effortMarker(intervals as IntervalSession) as String {
        var identity=intervals.source.equals("AUTO") ? intervals.automatic.detectedEnd : intervals.sequence;
        return intervals.source + ":" + identity.format("%d") + ":" + intervals.lastSeconds.format("%d");
    }

    // Last completed effort and last valid HRR60 are independent session snapshots.
    // Source: 1 automatic, 2 manual lap, 3 structured workout.
    function onIntervals(intervals as IntervalSession, recovery as HeartRecovery) as Void {
        if (mLastEffortPowerField == null) { return; }
        var mode = intervals.source.equals("AUTO") ? 1 :
            (intervals.source.equals("MANUAL") ? 2 : 3);
        var effort = intervals.lastMean;
        var duration = intervals.lastSeconds;
        if (effort != null && duration > 0) {
            var marker = effortMarker(intervals);
            if (!marker.equals(mLastEffortMarker)) {
                mLastEffortMarker = marker;
                (mLastEffortPowerField as FitContributor.Field).setData(effort);
                (mLastEffortSecondsField as FitContributor.Field).setData(
                    duration > 65535 ? 65535 : duration);
                (mLastEffortSourceField as FitContributor.Field).setData(mode);
                // A monotonically increasing ID permits reconstruction of every
                // completed effort from held RECORD values when physically sampled.
                // Wrap is explicit; very long activities should be flagged by decoder.
                mRepCounter = mRepCounter >= 65534 ? 1 : mRepCounter + 1;
                mPendingHrrRep = mRepCounter;
                if (mRepEventField != null) {
                    (mRepIdField as FitContributor.Field).setData(mRepCounter);
                    (mRepPowerField as FitContributor.Field).setData(
                        (effort as Float) > 65534 ? 65534 : (effort as Float).toNumber());
                    (mRepSecondsField as FitContributor.Field).setData(
                        duration > 65534 ? 65534 : duration);
                    (mRepSourceField as FitContributor.Field).setData(mode);
                    (mRepEventField as FitContributor.Field).setData(1);
                    // Negative 32768 means HRR is pending or unavailable.
                    (mRepHrrField as FitContributor.Field).setData(-32768);
                }
            }
        }
        if (recovery.delta != null && recovery.reason.equals("READY")) {
            var completedHrr = recovery.delta as Float;
            var hrrMarker = mLastEffortMarker + ":" + completedHrr.format("%.2f");
            if (!hrrMarker.equals(mLastHrrMarker)) {
                mLastHrrMarker = hrrMarker;
                if (mLastHrr60Field != null) {
                    (mLastHrr60Field as FitContributor.Field).setData(completedHrr);
                }
                if (mPendingHrrRep != 0 && mRepEventField != null) {
                    (mRepIdField as FitContributor.Field).setData(mPendingHrrRep);
                    (mRepHrrField as FitContributor.Field).setData(
                        completedHrr.toNumber());
                    (mRepEventField as FitContributor.Field).setData(2);
                    mPendingHrrRep = 0;
                }
            }
        }
    }

    // Called every second after the engine has taken the sample.
    function onSecond(engine as DriftEngine, cadence as Number?, isTimerRunning as Boolean) as Void {
        if (isTimerRunning && cadence != null && cadence > 0) {
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

        var history = engine.getHistory();
        var size = history.getSize();
        var efficiency = history.getLatest();
        (mEfficiencyField as FitContributor.Field).setData(efficiency == null ? 0.0f : efficiency);
        (mSteadyField as FitContributor.Field).setData(
            size > 0 && history.isSteady(size - 1) ? 1 : 0);
        (mCadenceField as FitContributor.Field).setData(lastCadence > 255 ? 255 : lastCadence);

        var state = engine.getState(METRIC_RIDE) as Number;
        (mRideStateField as FitContributor.Field).setData(state);
        (mSessionStateField as FitContributor.Field).setData(state);
        var drift = engine.getDriftPercent(METRIC_RIDE);
        if (drift != null) {
            (mRideDriftField as FitContributor.Field).setData(drift);
            (mSessionDriftField as FitContributor.Field).setData(drift);
        }
        var powerChange = engine.getPowerChangePercent(METRIC_RIDE);
        if (powerChange != null) {
            (mSessionPowerChangeField as FitContributor.Field).setData(powerChange);
        }
        (mSessionSteadyField as FitContributor.Field).setData(engine.getSteadyPercent());
        var compat = engine.getCompatDriftPercent();
        if (compat != null) {
            (mSessionCompatField as FitContributor.Field).setData(compat);
        }
    }

    private function resetCadence() as Void {
        mCadenceSum = 0;
        mCadenceSeconds = 0;
    }
}
