import Toybox.Lang;

// Last 180 compute slots (nominal 3 min). Pauses/dropouts remain visible gaps.
class IntervalHistory {
    const CAPACITY=180;
    private var powers as Array<Number>;
    private var hearts as Array<Number>;
    private var next as Number=0;
    var size as Number=0;
    function initialize() { powers=new [CAPACITY] as Array<Number>; hearts=new [CAPACITY] as Array<Number>; }
    function reset() as Void { next=0; size=0; }
    function add(power as Number?, hr as Number?, running as Boolean) as Void {
        powers[next]=running && power!=null && power>=0 && power<=10000 ? power : -1;
        hearts[next]=running && hr!=null && hr>0 && hr<=300 ? hr : -1;
        next=(next+1)%CAPACITY; if (size<CAPACITY) { size+=1; }
    }
    function point(index as Number, heart as Boolean) as Number? {
        if (index<0 || index>=size) { return null; }
        var slot=(next-size+index+CAPACITY)%CAPACITY;
        var value=heart ? hearts[slot] : powers[slot];
        return value<0 ? null : value;
    }
}
