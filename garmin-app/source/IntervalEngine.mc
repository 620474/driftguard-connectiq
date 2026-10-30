import Toybox.Lang;

// Boundaries identify segments, not work/recovery intent. No sensor-based guesses.
class IntervalEngine {
    var source as String = "NONE";
    var sequence as Number = 0;
    var seconds as Number = 0;
    var validPower as Number = 0;
    var powerSum as Float = 0.0f;
    var lastSeconds as Number = 0;
    var lastMean as Float? = null;
    var paused as Boolean = false;
    var interrupted as Boolean = false;
    var lastInterrupted as Boolean = false;

    function initialize() {}

    function reset() as Void {
        source = "NONE"; sequence = 0; seconds = 0; validPower = 0;
        powerSum = 0.0f; lastSeconds = 0; lastMean = null;
        paused = false; interrupted = false; lastInterrupted = false;
    }

    function startWorkout() as Void {
        // A second start cannot silently join two workouts or close a manual segment.
        reset(); source = "WORKOUT"; sequence = 1;
    }

    function boundary(workout as Boolean) as Void {
        if (workout) {
            // Loading mid-workout: first observed boundary starts a complete segment.
            if (!source.equals("WORKOUT")) { reset(); source = "WORKOUT"; sequence = 1; return; }
        } else {
            if (source.equals("WORKOUT")) { return; }
            if (source.equals("NONE")) { source = "MANUAL"; sequence = 1; return; }
        }
        // Duplicate boundaries before a running sample are idempotent.
        if (seconds == 0) { return; }
        lastSeconds = seconds; lastMean = meanPower(); lastInterrupted = interrupted;
        sequence += 1; seconds = 0; validPower = 0; powerSum = 0.0f;
        interrupted = false;
    }

    function addSample(power as Number?, running as Boolean) as Void {
        paused = !running;
        if (!running) {
            if (seconds > 0) { interrupted = true; }
            return;
        }
        if (sequence == 0) { return; }
        seconds += 1;
        if (power != null && power >= 0 && power <= 10000) {
            validPower += 1; powerSum += power;
        }
    }

    function meanPower() as Float? {
        return validPower == 0 ? null : powerSum / validPower;
    }
}
