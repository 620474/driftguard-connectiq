import Toybox.Lang;

// Version 1: balanced offline candidate, causal and bounded (60+60+3+5 values).
class AutoEffortEngine {
    var experimental as Boolean = false;
    private var pendingBase as Number = 0;
    private var steadyPlateauSeconds as Number = 0;
    private var history as Array<Number>;
    private var sorted as Array<Number>;
    private var pending as Array<Number> = [0,0,0] as Array<Number>;
    private var gap as Array<Number> = [0,0,0,0,0] as Array<Number>;
    var historyCount as Number = 0;
    private var next as Number = 0;
    private var pendingCount as Number = 0;
    private var gapCount as Number = 0;
    private var offBaselineTwice as Number = 0;
    var active as Boolean = false;
    var noPower as Boolean = true;
    var sequence as Number = 0;
    var seconds as Number = 0;
    var powerSum as Float = 0.0f;
    var lastSeconds as Number = 0;
    var lastMean as Float? = null;
    var lastPartial as Boolean = false;
    var tick as Number = -1;
    var startTick as Number = 0;
    var endTick as Number = 0;
    var detectedStart as Number = 0;
    var lastStart as Number = 0;
    var lastEnd as Number = 0;
    var detectedEnd as Number = 0;

    function initialize() {
        history = new [60] as Array<Number>;
        sorted = new [60] as Array<Number>;
        reset();
    }
    function reset() as Void {
        historyCount=0; next=0; pendingCount=0; gapCount=0; active=false;
        steadyPlateauSeconds=0;
        sequence=0; seconds=0; powerSum=0.0f; lastSeconds=0; lastMean=null;
        lastPartial=false; noPower=true; tick=-1; startTick=0; endTick=0; detectedStart=0;
        lastStart=0; lastEnd=0; detectedEnd=0;
    }
    private function idle(power as Number) as Void {
        history[next]=power; next=(next+1)%60;
        if (historyCount<60) { historyCount+=1; }
    }
    private function baseline() as Number {
        // Reuse scratch storage: no allocations inside the 1 Hz loop.
        for (var i=0; i<60; i+=1) {
            var value=history[i]; var j=i-1;
            while (j>=0 && sorted[j]>value) { sorted[j+1]=sorted[j]; j-=1; }
            sorted[j+1]=value;
        }
        return sorted[29]+sorted[30];
    }
    private function close(partial as Boolean) as Void {
        if (active && seconds>=(experimental ? 20 : 10)) {
            lastSeconds=seconds; lastMean=powerSum/seconds; lastPartial=partial;
            lastStart=startTick; lastEnd=endTick; detectedEnd=tick;
        }
        active=false; seconds=0; powerSum=0.0f; pendingCount=0;
        steadyPlateauSeconds=0;
    }
    function addSample(power as Number?, running as Boolean) as Void {
        if (experimental) { addAdaptive(power,running); return; }
        tick+=1;
        noPower=power==null || power<0 || power>10000;
        if (!running || power==null || power<0 || power>10000) {
            close(true); gapCount=0; historyCount=0; next=0; return;
        }
        var value=power as Number;
        if (active) {
            if (value*200<offBaselineTwice*115 || value*2<offBaselineTwice+40) {
                gap[gapCount]=value; gapCount+=1;
                if (gapCount==5) {
                    close(false);
                    for (var g=0; g<5; g+=1) { idle(gap[g]); }
                    gapCount=0;
                }
            } else {
                for (var k=0; k<gapCount; k+=1) { powerSum+=gap[k]; seconds+=1; }
                gapCount=0; powerSum+=value; seconds+=1; endTick=tick;
            }
            return;
        }
        if (historyCount<60) { idle(value); return; }
        var base=baseline();
        // Twice the median keeps threshold comparisons exact, including half watts.
        // Products are bounded by 2.7 million for the 0..10000 W input contract.
        if (value>=120 && value*200>=base*135 && value*2>=base+100) {
            pending[pendingCount]=value; pendingCount+=1;
            if (pendingCount==3) {
                active=true; sequence+=1; seconds=3;
                powerSum=pending[0].toFloat()+pending[1]+pending[2]; pendingCount=0;
                startTick=tick-2; endTick=tick; detectedStart=tick;
                offBaselineTwice=base;
            }
        } else {
            for (var n=0; n<pendingCount; n+=1) { idle(pending[n]); }
            pendingCount=0; idle(value);
        }
    }
    // Experimental local-step detector. History advances during efforts as well.
    // Frozen exit baseline preserves sustained efforts; a new local step can split one.
    private function addAdaptive(power as Number?, running as Boolean) as Void {
        tick+=1;
        noPower=power==null || power<0 || power>10000;
        if (!running || noPower) {
            close(true); gapCount=0; historyCount=0; next=0; return;
        }
        var value=power as Number;
        var base=historyCount==60 ? baseline() : 0;
        var high=historyCount==60 && value>=180 && value*200>=base*115 && value*2>=base+60;
        if (high && (!active || (seconds>=120 && gapCount==0))) {
            if (pendingCount==0) { pendingBase=base; }
            pending[pendingCount]=value;pendingCount+=1;
            if (pendingCount==3) {
                if (active) {
                    // First two confirming samples already belong to the parent.
                    powerSum-=pending[0]+pending[1];seconds-=2;endTick=tick-3;
                    close(false);
                }
                active=true;sequence+=1;seconds=3;steadyPlateauSeconds=0;
                powerSum=pending[0].toFloat()+pending[1]+pending[2];pendingCount=0;
                startTick=tick-2;endTick=tick;detectedStart=tick;
                offBaselineTwice=pendingBase;gapCount=0;
                idle(value);return;
            }
        } else { pendingCount=0; }
        if (active) {
            if (value*200<offBaselineTwice*115 || value*2<offBaselineTwice+40) {
                gap[gapCount]=value;gapCount+=1;
                if (gapCount==5) { close(false);gapCount=0; }
            } else {
                for (var k=0;k<gapCount;k+=1) { powerSum+=gap[k];seconds+=1; }
                gapCount=0;powerSum+=value;seconds+=1;endTick=tick;
            }
        }
        idle(value);
        // AUTO is deliberately limited to short surges. A sustained transition
        // to a new riding level must never become a bogus 30-minute repetition.
        // At 240 s suppress the candidate without calling close(), so no
        // completed-effort FIT event or HRR is produced.
        // Longer prescribed intervals must use WORKOUT or manual LAP.
        if (active && seconds>=240) {
            active=false;seconds=0;powerSum=0.0f;pendingCount=0;
            gapCount=0;steadyPlateauSeconds=0;
        }
    }
    function meanPower() as Float? { return active ? powerSum/seconds : null; }
}
