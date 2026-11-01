## 2026-11-01 � hosted simulator release gate restored

Complete Edge 1050 runtime assets and WW fonts are provisioned through private
GitHub Environment secrets. Production and calibration execution is mandatory
again; no simulator skip remains. Hosted validation run [41339749884](https://github.com/620474/driftguard-connectiq/actions/runs/41339749884)
passed 110 Python tests, 54 production Monkey C tests and 57 calibration tests,
then built the signed production PRG. Logs are retained as an Actions artifact.
Application calculations and FIT schema are unchanged. Physical Edge validation
is still separate. See [CI provisioning and gates](RELEASE_CI.md).

## 2026-11-01 — offline model comparison

Owner authorized the comparative lab study, then commit and push to main.
Scope: frozen DRIFT/AUTO/HRR candidates, synthetic schedules, private 123-FIT
comparison, independent-label import and blind-review packet. No production model
replacement. Protocol: [MODEL_STUDY_PROTOCOL_RU.md](MODEL_STUDY_PROTOCOL_RU.md).
Source settings and individual ride outputs remain local; only anonymised results
are committed. Earlier no-push instructions below are historical.

## 2026-11-01 — release gate and boundary follow-up

Owner authorized CI gating, exact-60s HRR preservation and CV opt-in.
Current contract: [RELEASE_GATE_V3.md](RELEASE_GATE_V3.md).
No push or release.

## 2026-11-01 — audit reliability candidate

Implemented schema/algorithm v2; see [contract](RELIABILITY_V2_RU.md).
This is a local candidate, not a published release. Strict CV/resume gates
produce zero final VALID metrics on the 123-FIT audit cohort; this limitation
must remain visible when evaluating the candidate. Device validation outstanding.

# INTERVALS HR and raw HRR60 — 2026-10-31

Current HR and gated signed HRR60 added by owner request. AUTO end is backdated
five samples, explicit segments require complete power data. Three-second HR
windows, complete low-power recovery, no pause/new effort. No normative bands.
DriftEngine, detector thresholds and FIT contracts unchanged. Physical test pending.
See HEART_RECOVERY_RU.md.

---

# Live AUTO на Edge 1050 — 2026-10-31

По новому запросу владельца автоматический режим включён в приложение по умолчанию.
Без workout/manual источника он работает при каждом compute, независимо от экрана.
Переключение на INTERVALS — обычным тапом. Первые 60 известных running samples
собирают baseline; затем возможна автоматическая детекция. HR для неё не требуется.
Параметры balanced v1 перенесены из Python как инженерный стартовый контракт,
без заявления, что это оптимальный или физиологически валидированный вариант.

Одиночный всплеск не становится усилием: 3 samples подтверждают начало,
до 10 s экран показывает CONFIRMING. Пять низких samples закрывают усилие;
короткий провал внутри включается в среднее. После окончания видны LAST W / s.
Pause/missing power закрывают достаточно длинное усилие с LAST INCOMPLETE,
baseline собирается заново. Текущая активность без HR поддерживается.

Manual LAP переводит в ручные сегменты до workout/reset; неполное AUTO при
переключении источника сбрасывается. Workout start/step имеют приоритет.
Определение окончания workout по-прежнему не реализовано: WORKOUT остаётся до
reset/new activity. Сохранённый экран не влияет на выбор источника анализа.
DRIFT и FIT-схемы не меняются. Разделы ниже описывают также историю этапов.

---

# Offline power-effort prototype — 2026-10-31

Timer import ambiguity fixed and real archive rechecked. Three causal power-change
candidates added to validation-lab, with synthetic tests and private archive reports.
This is an exploratory offline experiment, not a deployed automatic Edge mode.
Production DriftEngine, live IntervalEngine and FIT recording are unchanged.
See AUTO_EFFORTS_RU.md and auto-efforts-verification.json for results and limitations.

---

# INTERVALS stage 1 — 2026-10-31

Implemented: DRIFT/INTERVALS screen switch, separate explicit-boundary segment
accumulator, manual/workout sources, independent Python model and regression tests.
DriftEngine, mathematical drift oracle and FIT schemas remain unchanged.
See INTERVALS_RU.md. Physical Edge and six-month FIT validation remain pending.

---

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
