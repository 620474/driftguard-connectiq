import Toybox.Lang;
import Toybox.WatchUi;

// Edge touch devices deliver onTap to data fields; a tap anywhere on the field
// switches DRIFT / INTERVALS. Both drift metrics stay on the DRIFT screen.
class DriftGuardDelegate extends WatchUi.InputDelegate {
    private var mView as DriftGuardView;

    function initialize(view as DriftGuardView) {
        InputDelegate.initialize();
        mView = view;
    }

    function onTap(clickEvent as WatchUi.ClickEvent) as Boolean {
        mView.toggleScreen();
        return true;
    }
}
