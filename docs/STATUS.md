# Project Status

Last updated: 2026-09-25

## Current phase

Milestone 4 implemented; Edge 1050 build and 21 simulator tests pass.
Physical-device testing and calibration on real ride files are pending.

## Current milestone

**Milestone 4 — Honest numbers and calibration recording**

See: `docs/CURRENT_TASK.md`.

## Done

- Product direction chosen.
- Private GitHub repository created.
- Codex role defined.
- Claude reviewer role defined.
- MVP scope defined.
- Initial architecture and decisions documented.
- Verified installed Garmin SDK 9.2.0 and Edge 1050 device profile.
- Created the Data Field under `garmin-app/` from Garmin SDK templates.
- Implemented current power / HR / instantaneous Pw:HR and missing-value handling.
- Strict compiler build passed with no warnings.
- Loaded the field in Edge 1050 simulator (device API 6.0.0).
- Two simulator tests passed: normal readings, zero power/HR, missing and negative values.
- Milestone 1 manually accepted.
- Added local quality-aware decoupling: configurable 15-minute warm-up, valid
  30-minute sample period, 80% data-quality and 15% power-variability gates,
  and `NOT_READY` / `NOT_STEADY` / `VALID` states.
- Review fixes: the result no longer flips from VALID to NOT_STEADY later in
  the ride; paused timer is ignored; warm-up uses timer time; rejected periods
  restart collection; variability uses 30 s averages; speed filter removed;
  engine resets on `onTimerReset`.
- Redesigned field: large drift value with STABLE / WATCH / HIGH DRIFT pill,
  progress bar before a result, Pw:HR row, power / HR columns; medium and small
  layouts; light and dark backgrounds.
- Full page adds a per-minute Pw:HR trend chart (last 60 min, first-half
  baseline) and power (3 s average) / HR zone gauges from the Garmin user
  profile zones (`UserProfile` permission). Pw:HR number is per full minute.
- Seventeen simulator tests passed. Full-page layout checked by screenshot in the
  Edge 1050 simulator (warm-up and VALID states, chart and zone gauges).
- Milestone 3: minute-based steady filter (valid data, ±20% of median power,
  2-minute HR recovery), live RIDE drift over the whole ride (constant-memory
  buckets) and LAST 60 MIN drift, STEADY TIME, tap to switch the main metric,
  chart marks non-steady minutes. 16 simulator tests; tap and both metrics
  checked by screenshot with a synthetic 2.5 h ride.
- Milestone 4 (after research review): POWER CHANGED gate for halves differing
  by more than 5% in power, 3-minute HR recovery, label hysteresis, neutral
  NEGATIVE label, FIT recording of minute EF / steady / drift / cadence and an
  Intervals-style compat drift; a refused metric gives way to the other one
  on screen. 21 simulator tests.

## Next

1. Ride with the sideloaded field on the Edge 1050; check auto-pause, sensor
   dropouts, tap in gloves and readability.
2. Calibrate the steady filter and the 40 / 70% / 48-minute gates on real FIT
   files; compare RIDE drift with Intervals.icu on steady Z2 rides.
3. Check medium/small layouts in the simulator.

## Known uncertainties

- The simulator test runner returns exit code 1 despite a passing summary.
- All steady-minute and validity thresholds are heuristics, not yet calibrated.
- The half-way split resolution becomes one bucket (2 min) after 4 h of riding.
- Physical Edge behavior (onTap, auto-pause, sensor dropouts) has not been tested.

## Not started

- multi-device layouts;
- FIT fields;
- Store submission;
- monetization;
- backend;
- AI features.
