import Toybox.Lang;

// Raw 3-second end HR minus 3-second HR at +60 s. No normative classification.
class HeartRecovery {
    private var hr as Array<Number>;
    private var power as Array<Number>;
    private var next as Number = 0;
    private var count as Number = 0;
    var elapsed as Number = 0;
    var endHr as Float? = null;
    var delta as Float? = null;
    var collecting as Boolean = false;
    var reason as String = "NEED EFFORT";
    private var limit as Float = 0.0f;
    function initialize() { hr=new [8] as Array<Number>; power=new [8] as Array<Number>; reset(); }
    function reset() as Void { next=0; count=0; endHr=null; cancel("NEED EFFORT"); }
    function cancel(why as String) as Void { collecting=false; delta=null; elapsed=0; reason=why; }
    private function at(values as Array<Number>, offset as Number) as Number {
        return values[(next-1-offset+16)%8];
    }
    private function mean(offset as Number) as Float? {
        if (count<offset+3) { return null; }
        var sum=0;
        for (var i=offset;i<offset+3;i+=1) { var value=at(hr,i); if (value<=0) { return null; } sum+=value; }
        return sum.toFloat()/3;
    }
    function sample(value as Number?, watts as Number?, running as Boolean) as Void {
        if (!running) { cancel("PAUSED"); count=0; next=0; return; }
        hr[next]=(value!=null && value>0 && value<=300) ? value : -1;
        power[next]=(watts!=null && watts>=0 && watts<=10000) ? watts : -1;
        next=(next+1)%8; if (count<8) { count+=1; }
        if (!collecting) { return; }
        if (at(hr,0)<0) { cancel("HR MISSING"); return; }
        if (at(power,0)<0) { cancel("POWER MISSING"); return; }
        if (at(power,0)>limit) { cancel("POWER HIGH"); return; }
        elapsed+=1;
        if (elapsed==60) {
            var terminal=mean(0);
            if (terminal==null || endHr==null) { cancel("HR MISSING"); return; }
            delta=(endHr as Float)-terminal; collecting=false; reason="READY";
        }
    }
    function begin(delay as Number, effortPower as Float?, duration as Number) as Void {
        cancel("NEED EFFORT"); endHr=mean(delay);
        if (duration<10) { reason="TOO SHORT"; return; }
        if (endHr==null) { reason="HR MISSING"; return; }
        if (effortPower==null) { reason="POWER MISSING"; return; }
        if (effortPower<=0) { reason="NEED EFFORT"; return; }
        // Conservative engineering gate, not a physiological recovery threshold.
        limit=effortPower*0.5f;
        for (var i=0;i<delay;i+=1) {
            if (at(hr,i)<0) { reason="HR MISSING"; return; }
            if (at(power,i)<0) { reason="POWER MISSING"; return; }
            if (at(power,i)>limit) { reason="POWER HIGH"; return; }
        }
        elapsed=delay; collecting=true; reason="COLLECTING";
    }
    function inlineText() as String {
        if (delta!=null) { return "R60" + delta.format("%+.0f"); }
        if (collecting) { return "R" + elapsed.format("%d") + "/60"; }
        return "R--";
    }
    function compactText() as String {
        if (delta!=null) { return "HRR60 " + delta.format("%+.0f"); }
        if (collecting) { return "HRR " + elapsed.format("%d") + "/60"; }
        if (reason.equals("HR MISSING")) { return "HRR -- / HR"; }
        if (reason.equals("POWER MISSING") || reason.equals("POWER HIGH")) { return "HRR -- / PWR"; }
        return "HRR --";
    }
    function text() as String {
        if (delta!=null) { return "HRR60 " + ((delta as Float)>=0 ? "+" : "") + delta.format("%.0f") + " bpm"; }
        if (collecting) { return "HRR60 " + elapsed.format("%d") + "/60 s"; }
        return "HRR60 -- / " + reason;
    }
}
