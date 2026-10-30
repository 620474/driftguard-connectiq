import Toybox.Lang;

// Explicit sources take priority. Manual mode lasts until workout start/activity reset.
class IntervalSession extends IntervalEngine {
    var automatic as AutoEffortEngine;
    function initialize() {
        automatic=new AutoEffortEngine();
        IntervalEngine.initialize(); reset();
    }
    function reset() as Void {
        IntervalEngine.reset(); automatic.reset(); source="AUTO";
    }
    function boundary(workout as Boolean) as Void {
        if (!workout && source.equals("AUTO")) {
            IntervalEngine.reset(); automatic.reset();
        }
        IntervalEngine.boundary(workout);
    }
    function addSample(power as Number?, running as Boolean) as Void {
        if (!source.equals("AUTO")) { IntervalEngine.addSample(power,running); return; }
        automatic.addSample(power,running);
        paused=!running; sequence=automatic.sequence;
        seconds=automatic.seconds; validPower=seconds; powerSum=automatic.powerSum;
        lastSeconds=automatic.lastSeconds; lastMean=automatic.lastMean;
        lastInterrupted=automatic.lastPartial; interrupted=false;
    }
}
