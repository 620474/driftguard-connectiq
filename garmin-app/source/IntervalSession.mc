import Toybox.Lang;

// Explicit sources take priority. Manual mode lasts until workout start/activity reset.
class IntervalSession extends IntervalEngine {
    var automatic as AutoEffortEngine;
    var completionId as Number = 0;
    var timerSeconds as Number = 0;
    var lastEndSeconds as Number = 0;
    function initialize() {
        automatic=new AutoEffortEngine();automatic.experimental=true;
        IntervalEngine.initialize(); reset();
    }
    function reset() as Void {
        IntervalEngine.reset(); automatic.reset(); source="AUTO";
        completionId=0;timerSeconds=0;lastEndSeconds=0;
    }
    function startWorkout() as Void {
        var identity=completionId;var clock=timerSeconds;
        IntervalEngine.startWorkout();completionId=identity;timerSeconds=clock;
    }
    function boundary(workout as Boolean) as Void {
        var identity=completionId;var clock=timerSeconds;
        var previous=sequence;var hadSamples=seconds>0;
        var previousSource=source;
        if (!workout && source.equals("AUTO")) {
            IntervalEngine.reset(); automatic.reset();
        }
        IntervalEngine.boundary(workout);
        completionId=identity;timerSeconds=clock;
        if(hadSamples && previousSource.equals(source) && sequence!=previous){completionId+=1;lastEndSeconds=timerSeconds;}
    }
    function addSample(power as Number?, running as Boolean) as Void {
        if(running){timerSeconds+=1;}
        if (!source.equals("AUTO")) { IntervalEngine.addSample(power,running); return; }
        var before=automatic.detectedEnd;
        automatic.addSample(power,running);
        if(before!=automatic.detectedEnd){completionId+=1;lastEndSeconds=timerSeconds-(automatic.detectedEnd-automatic.lastEnd)+(running ? 0 : 1);lastValidPower=automatic.lastSeconds;}
        paused=!running; sequence=automatic.sequence;
        seconds=automatic.seconds; validPower=seconds; powerSum=automatic.powerSum;
        lastSeconds=automatic.lastSeconds; lastMean=automatic.lastMean;
        lastInterrupted=automatic.lastPartial; interrupted=false;
    }
}
