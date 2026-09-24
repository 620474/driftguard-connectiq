import Toybox.Activity;
import Toybox.Lang;
import Toybox.Test;

(:test)
function liveReadings(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    Test.assertEqual(field.ratioText, "--");
    var info = new Activity.Info();
    info.currentPower = 247;
    info.currentHeartRate = 151;
    field.compute(info);
    Test.assertEqual(field.powerText, "247 W");
    Test.assertEqual(field.heartRateText, "151 bpm");
    Test.assertEqual(field.ratioText, "1.64");

    info.currentPower = 0;
    field.compute(info);
    Test.assertEqual(field.powerText, "0 W");
    Test.assertEqual(field.ratioText, "0.00");

    info.currentHeartRate = 0;
    field.compute(info);
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");
    return true;
}

(:test)
function missingReadings(logger as Test.Logger) as Boolean {
    var field = new DriftGuardView();
    var info = new Activity.Info();
    info.currentPower = 247;
    info.currentHeartRate = 151;
    field.compute(info);
    info.currentHeartRate = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "247 W");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");

    info.currentPower = null;
    info.currentHeartRate = 151;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "151 bpm");
    Test.assertEqual(field.ratioText, "--");

    info.currentHeartRate = null;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");

    info.currentPower = -1;
    info.currentHeartRate = -1;
    field.compute(info);
    Test.assertEqual(field.powerText, "--");
    Test.assertEqual(field.heartRateText, "--");
    Test.assertEqual(field.ratioText, "--");
    return true;
}
