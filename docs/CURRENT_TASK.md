# Milestone 4 — Honest numbers and calibration recording

Follows the two research reports (Claude, ChatGPT) on the Milestone 3 model.

## Changes

- **Power-match gate.** Halves whose average power differs by more than 5% are
  not compared: the metric shows `POWER_CHANGED` with the change instead of a
  percentage. With HR ≈ HR0 + k·P, Pw:HR changes by about (HR0/HR)·ΔP/P, so a 10%
  lower second half alone looks like ~5% drift. Even inside the 5% gate a power
  change can still add up to ~2.5% of apparent drift; the gate may be tightened to
  3% after calibration.
- **Fallback instead of a refusal screen.** If the selected metric has given up
  on the ride (POWER CHANGED or NOT STEADY) and the other has a value, the other
  is shown large; its tab is filled and the selected tab gets an orange outline.
  The refused metric shrinks to its one-line summary (e.g. `RIDE  PWR -10%`).
  While a metric is still collecting, its progress is shown as before.
- **HR recovery after a non-steady minute: 3 minutes** (was 2), about three HR
  time constants of 35–70 s.
- **Label hysteresis:** STABLE / WATCH / HIGH DRIFT change only once the drift is
  0.5 percentage points past a boundary.
- **Negative drift below −3%** gets a neutral `NEGATIVE` label (muted color)
  instead of STABLE: usually an unfinished warm-up or a change of effort.
- **FIT recording (FitContributor)** for calibration against Intervals.icu:
  - record, updated each minute: `dg_ef` (minute Pw:HR, 0 = no data),
    `dg_steady` (0/1), `dg_ride_drift` (%), `dg_ride_state`, `dg_cadence`
    (pedalling-only minute average, rpm);
  - session: `dg_ride_drift_final`, `dg_ride_state_final`, `dg_steady_percent`,
    `dg_power_change`, `dg_compat_drift`;
  - state codes: 0 warm-up, 1 collecting, 2 not steady, 3 power changed, 4 valid;
  - `dg_compat_drift` is computed like Intervals.icu (whole activity from the
    start, average power including zeros / average HR, halves by time) to check
    the arithmetic against the Intervals.icu activity value.

Deferred to a later milestone (need real FIT data first): HR = α + β·P + γ·t
regression, %/hour, heat flag, settings for Edge 540, uncertainty display.

---

# Milestone 3 — Long-ride live drift

## Goal

Make DriftGuard useful on a real 2–4 h steady ride: the drift keeps updating for
the whole ride instead of freezing after the first 30-minute period, and the
rider can switch between the whole-ride and the last-hour view with a tap.

## Calculation contract

All data is kept in one-minute records. A minute is 60 seconds of running timer;
seconds with a stopped timer (pause, auto-pause) are ignored entirely.

- Warm-up: the first 15 running minutes never count (configurable in code).
- A second is valid when power and HR are both positive.
- A minute is **steady** when all of the following hold:
  - at least 48 of its 60 seconds are valid (≤ 20% coasting / dropout);
  - its average power (over valid seconds) is within ±20% of the median
    minute power of the ride so far (post-warm-up minutes with enough data);
  - it is not one of the 2 minutes after a non-steady minute (HR still
    recovering from a climb or a stop would inflate drift).
- Efficiency (EF) is average power / average HR over valid seconds of steady
  minutes, the same definition Intervals.icu uses for Pw:HR decoupling.
- Drift is `(EF first half - EF second half) / EF first half * 100`. Halves are
  split by steady seconds, not by clock time, so excluded minutes do not
  unbalance them. A minute straddling the split is divided proportionally.

### RIDE DRIFT

- All steady minutes after the warm-up.
- `VALID` from 40 steady minutes, if at least 70% of post-warm-up minutes are
  steady; otherwise `NOT_STEADY` (from 40 post-warm-up minutes).
- Recomputed every minute for the whole ride. Minute records are merged
  pairwise when the fixed buffer fills, so memory is constant for any duration
  and the sums (and therefore the result) are exact.

### LAST 60 MIN

- The last 60 running minutes, available once 60 post-warm-up minutes exist.
- `VALID` if at least 48 of those minutes are steady; otherwise `NOT_STEADY`.

### States (per metric)

- `WARMUP` → `COLLECTING` (NOT READY, with progress) → `VALID` / `NOT_STEADY`.
- Valid drift is labelled STABLE (< 5%), WATCH (5–10%) or HIGH DRIFT (≥ 10%).
  The 5% guide follows common practice (TrainingPeaks); the 10% boundary is a
  product heuristic, not a physiological fact.

All thresholds are heuristics to be calibrated on real ride files.

## UX

- Tap anywhere on the field toggles the main metric between RIDE and LAST 60
  (`InputDelegate.onTap`, Edge touch devices). The choice is remembered.
- The other metric and STEADY TIME stay visible in smaller type, so no
  information depends on touch (Edge 540 has no touch screen).
- The Pw:HR chart draws non-steady minutes muted; the dashed baseline is the
  first-half EF of the selected metric.

## Scope

- Edge 1050 only. No settings UI, no FIT developer fields, no network.

## Acceptance criteria

- Ride drift keeps updating after 45 minutes and follows a later decline.
- A climb in the middle of a steady ride, plus its HR recovery, does not change
  the ride drift.
- Pauses do not count; hilly riding is reported as NOT STEADY.
- A 6 h ride works with constant memory and gives the same result as unmerged data.
- Tap toggles the metric; reset between activities clears everything.
- Edge 1050 build and simulator tests pass.
