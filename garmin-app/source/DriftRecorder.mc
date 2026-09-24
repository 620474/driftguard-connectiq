import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.WatchUi;

// Writes DriftGuard's numbers into the activity FIT file so they can be compared
// with Intervals.icu on the same ride. Values change once per minute.
// Policy: 0 in a per-minute field means "no data that minute"; drift fields are
// meaningful only while the matching state field is VALID (codes at writeMinute).
class DriftRecorder {
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
    private function writeMinute(engine as DriftEngine) as Void {
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
