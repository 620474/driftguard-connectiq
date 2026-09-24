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
- Six simulator tests passed, including known 10.0% drift, warm-up, missing
  readings, stopped/coasting data, sparse data, and power-variability gating.

## Next

1. Manually inspect the Milestone 2 full-size field and simulated activity playback on Edge 1050.
2. Review Milestone 2 before authorizing any later work.

## Known uncertainties

- Automated visual inspection failed: Windows capture `SetIsBorderRequired`
  returned `0x80004002`; UI input reported unavailable geometry.
- Simulator tests reported 2 passed / 0 errors, but the runner returned exit code 1.
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
