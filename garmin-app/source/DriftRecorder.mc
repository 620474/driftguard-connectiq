import Toybox.WatchUi;
(:production)
class DriftRecorder extends ProductionRecorder {
    function initialize(field as WatchUi.DataField?) { ProductionRecorder.initialize(field); }
}
