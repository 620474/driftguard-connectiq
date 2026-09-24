# Project Status

Last updated: 2026-09-24

## Current phase

Milestone 2 implemented; Edge 1050 build and simulator tests pass.
Manual visual/live-playback acceptance remains pending because desktop capture failed.

## Current milestone

**Milestone 2 — Quality-aware aerobic decoupling**

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

## Next

1. Check medium/small layouts and a FIT playback in the simulator.
2. Validate the 15% variability threshold on real outdoor ride files.
3. Review Milestone 2 before authorizing any later work.

## Known uncertainties

- The simulator test runner returns exit code 1 despite a passing summary.
- The 15% CV threshold on 30 s averages is not yet validated on real rides.
- Physical Edge behavior has not been tested.
- Sensor-disconnection timing and actual activity lifecycle need physical-device verification.
- Physical-device testing must validate the timer and speed semantics used by the
  sample filter, especially indoor speed-null and auto-pause behavior.

## Not started

- multi-device layouts;
- FIT fields;
- Store submission;
- monetization;
- backend;
- AI features.
