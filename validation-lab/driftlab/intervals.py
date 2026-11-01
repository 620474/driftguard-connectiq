"""Independent offline segment accumulator. Input events are explicit boundaries.

No effort/recovery classification and no inference of live callbacks from FIT laps.
"""
class Intervals:
    def __init__(self):
        self.reset()

    def reset(self):
        self.source = "NONE"
        self.sequence = self.seconds = self.valid_power = 0
        self.power_sum = 0
        self.last = None
        self.interrupted = False

    def workout_start(self):
        self.reset()
        self.source, self.sequence = "WORKOUT", 1

    def boundary(self, workout=False):
        if workout and self.source != "WORKOUT":
            self.workout_start()
            return
        if not workout:
            if self.source == "WORKOUT":
                return
            if self.source == "NONE":
                self.source, self.sequence = "MANUAL", 1
                return
        if not self.seconds:
            return
        self.last = (self.seconds, self.valid_power, self.power_sum, self.mean, self.interrupted or self.valid_power != self.seconds)
        self.sequence += 1
        self.seconds = self.valid_power = self.power_sum = 0
        self.interrupted = False

    def sample(self, power, running=True):
        if not running:
            self.interrupted |= self.seconds > 0
            return
        if not self.sequence:
            return
        self.seconds += 1
        if power is not None and 0 <= power <= 10000:
            self.valid_power += 1
            self.power_sum += power

    @property
    def mean(self):
        return self.power_sum / self.valid_power if self.valid_power else None
