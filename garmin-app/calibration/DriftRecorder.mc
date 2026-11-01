import Toybox.FitContributor;
import Toybox.Lang;
import Toybox.WatchUi;
(:calibration)
class DriftRecorder extends ProductionRecorder {
    var diagnostics as Array<FitContributor.Field> = [];
    var bucketWidth as FitContributor.Field? = null;
    var compatWidth as FitContributor.Field? = null;
    var enabled as Boolean = false;
    function initialize(field as WatchUi.DataField?) {
        ProductionRecorder.initialize(field);
        if (field == null || !ProductionRecorder.isRecording()) { return; }
        try {
            diagnostics.add(field.createField("dg_minute_seq", 10, FitContributor.DATA_TYPE_UINT16, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_sample_seq", 11, FitContributor.DATA_TYPE_UINT32, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_valid_seconds", 12, FitContributor.DATA_TYPE_UINT8, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_reject_reason", 13, FitContributor.DATA_TYPE_UINT8, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_min_power_sum", 14, FitContributor.DATA_TYPE_UINT32, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_min_hr_sum", 15, FitContributor.DATA_TYPE_UINT16, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_compat_seconds", 16, FitContributor.DATA_TYPE_UINT8, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_compat_power_sum", 17, FitContributor.DATA_TYPE_UINT32, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            diagnostics.add(field.createField("dg_compat_hr_sum", 18, FitContributor.DATA_TYPE_UINT16, {:mesgType => FitContributor.MESG_TYPE_RECORD}));
            field.createField("dg_algo_version", 19, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION}).setData(2);
            field.createField("dg_config_crc", 20, FitContributor.DATA_TYPE_UINT32,
                {:mesgType => FitContributor.MESG_TYPE_SESSION}).setData(3866173107l);
            bucketWidth = field.createField("dg_bucket_width", 21, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
            compatWidth = field.createField("dg_compat_width", 22, FitContributor.DATA_TYPE_UINT16,
                {:mesgType => FitContributor.MESG_TYPE_SESSION});
            enabled = true;
            clearDiagnostics();
        } catch (e) { enabled = false; }
    }
    function isRecording() as Boolean { return ProductionRecorder.isRecording() && enabled; }
    function clearDiagnostics() as Void {
        for (var i = 0; i < diagnostics.size(); i += 1) { diagnostics[i].setData(0); }
    }
    function reset() as Void {
        ProductionRecorder.reset();
        if (bucketWidth != null) { bucketWidth.setData(1); }
        if (compatWidth != null) { compatWidth.setData(1); }
        clearDiagnostics();
    }
    function writeMinute(engine as DriftEngine) as Void {
        ProductionRecorder.writeMinute(engine);
        if (!enabled) { return; }
        var m = engine.calibrationMinute;
        var n = engine.getMinutes();
        // FIT uint16 reserves 65535; refuse overflow instead of wrapping IDs.
        if (n >= 65535) { enabled = false; clearDiagnostics(); return; }
        diagnostics[1].setData(n * 60);
        diagnostics[2].setData(m[0]);
        diagnostics[3].setData(m[6]);
        diagnostics[4].setData(m[1]);
        diagnostics[5].setData(m[2]);
        diagnostics[6].setData(m[3]);
        diagnostics[7].setData(m[4]);
        diagnostics[8].setData(m[5]);
        diagnostics[0].setData(n);
        (bucketWidth as FitContributor.Field).setData(engine.mRide.getMinutesPerBucket());
        (compatWidth as FitContributor.Field).setData(engine.mCompat.getMinutesPerBucket());
    }
}
