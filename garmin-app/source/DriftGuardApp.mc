import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class DriftGuardApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var view = new DriftGuardView();
        return [view, new DriftGuardDelegate(view)];
    }
}
