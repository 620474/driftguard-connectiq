"""AUTO EXP v2 replay of AutoEffortEngine.addAdaptive, not the balanced candidate.

Feed consecutive one-second slots. No implicit finish: just as live compute(),
completion requires power drop, missing power or timer stop. An active tail is
reported separately and must never masquerade as a recorded FIT repetition.
Integer comparisons match Monkey C; accumulated power uses Python float64.
"""
from collections import deque

ALGORITHM = 'auto-exp-v2'


class ExperimentalDetector:
    def __init__(self):
        self.floor = 180
        self.entry_floor = 0
        self.hist = deque(maxlen=60)
        self.pending = [0] * 3
        self.pc = 0
        self.gap = []
        self.active = False
        self.seq = 0
        self.seconds = 0
        self.total = 0
        self.tick = -1
        self.events = []
        self.discards = []
        self.pending_base = 0
        self.start = 0
        self.end = 0
        self.base = 0

    def close(self, partial, reason):
        if self.active:
            row = dict(
                start=self.start,
                end=self.end,
                detected=self.tick,
                duration=self.seconds,
                power=self.total / self.seconds,
                partial=partial,
                reason=reason,
                sustained=self.seconds >= 240,
                valid_power_s=self.seconds,
                sequence=self.seq,
                baseline=self.base / 2)
            (self.events if self.seconds >= 20 else self.discards).append(row)
        self.active = False
        self.seconds = 0
        self.total = 0
        self.pc = 0

    def sample(self, p, running):
        self.tick += 1
        if not running or p is None or p < 0 or p > 10000:
            self.close(True, 'pause' if not running else 'missing_power')
            self.gap = []
            self.hist.clear()
            return
        ordered = sorted(self.hist)
        base = ordered[29] + ordered[30] if len(ordered) == 60 else 0
        high = len(self.hist) == 60 and p >= self.floor and p * \
            200 >= base * 115 and p * 2 >= base + 60
        if high and (not self.active or (
                self.seconds >= 120 and not self.gap)):
            if self.pc == 0:
                self.pending_base = base
            self.pending[self.pc] = p
            self.pc += 1
            if self.pc == 3:
                if self.active:
                    self.total -= self.pending[0] + self.pending[1]
                    self.seconds -= 2
                    self.end = self.tick - 3
                    self.close(False, 'local_split')
                self.active = True
                self.seq += 1
                self.seconds = 3
                self.total = sum(self.pending)
                self.pc = 0
                self.start = self.tick - 2
                self.end = self.tick
                self.base = self.pending_base
                self.entry_floor = sum(self.pending) * 7 // 30
                self.gap = []
                self.hist.append(p)
                return
        else:
            self.pc = 0
        if self.active:
            if p < self.entry_floor or p * 200 < self.base * 115 or p * 2 < self.base + 40:
                self.gap.append(p)
                if len(self.gap) == 5:
                    self.close(False, 'power_drop')
                    self.gap = []
            else:
                self.total += sum(self.gap) + p
                self.seconds += len(self.gap) + 1
                self.gap = []
                self.end = self.tick
        self.hist.append(p)
