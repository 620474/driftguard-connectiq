# Project Status

Last updated: 2026-09-24

## Current phase

Milestone 1 implemented; Edge 1050 build and simulator tests pass.
Manual visual/live-playback acceptance remains pending because desktop capture failed.

## Current milestone

**Milestone 1 — Live Power / HR / Pw:HR on Edge 1050 Simulator**

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

## Next

1. Manually inspect the full-size field and simulated activity playback on Edge 1050.
2. Review Milestone 1 before authorizing any Milestone 2 work.

## Known uncertainties

- Automated visual inspection failed: Windows capture `SetIsBorderRequired`
  returned `0x80004002`; UI input reported unavailable geometry.
- Simulator tests reported 2 passed / 0 errors, but the runner returned exit code 1.
- Physical Edge behavior has not been tested.
- Sensor-disconnection timing and actual activity lifecycle need physical-device verification.
- Final drift formula / validity rules are intentionally not frozen yet.

## Not started

- drift algorithm;
- validity detector;
- multi-device layouts;
- FIT fields;
- Store submission;
- monetization;
- backend;
- AI features.
