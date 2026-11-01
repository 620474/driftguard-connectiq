## 2026-11-01 — release gate and boundary follow-up

Owner authorized CI gating, exact-60s HRR preservation and CV opt-in.
Current contract: [RELEASE_GATE_V3.md](RELEASE_GATE_V3.md).
No push or release.

# Audit reliability fixes — 2026-11-01

Owner requests all audit fixes in one local commit; no push or release.
Scope: calibration allocation, steady variability/resume/sensor checks, sustained
AUTO and low-baseline tails, completion identity, FIT quality/HRR provenance,
source-faithful offline replay and data-driven research reporting.
Contract and known loss of final VALID availability: RELIABILITY_V2_RU.md.
Build both variants, run regression and private archive replay, inspect diff.

---

# Enable experimental local surge detector — 2026-10-31

Owner explicitly requested enabling it on Edge. Enable for AUTO sessions; keep
legacy direct-engine parity tests. Rolling 60-s baseline during active efforts,
3-s start, 5-s exit, 180 W entry floor, 20-s saved effort minimum. After >=120 s
allow a new local step to split the sustained parent. Cancel HRR at such splits.
Mark AUTO EXP in header. Manual/workout priority, DRIFT and FIT schema unchanged.
Run deterministic regression plus private actual FIT replay in Monkey C.

---

# FIT duplicates and tempo surges — 2026-10-31

Owner authorized fixes after activity 24921319846 review. Fix completion identity
without changing FIT schema. Regression: next AUTO start preserves prior marker;
next equal-duration completion changes it; manual boundaries remain distinct.
Research local tempo surge boundaries offline before changing live thresholds.

---

# Shared screen alignment — 2026-10-31

Owner requests stable positions when toggling DRIFT and INTERVALS. Use shared
full-page anchors and fonts for heading, hero, status, summary, chart envelope,
separator and sensor gauges. Keep two INTERVALS plots and all analysis unchanged.
Verify both screens in rendering smoke, build/test, push and release.

---

# Screen spacing — 2026-10-31

Owner requested less whitespace below screen titles and more separation around
INTERVALS chart frames. Preserve headings, larger fonts and all analysis. Move
hero/summary up, add title-to-frame gaps, keep frames separated from lower gauges.
Build, run existing simulator rendering smoke/suites, publish and open production.

---

# INTERVALS legibility — 2026-10-31

Owner marked LAST EFFORT, HRR60 and both chart areas as too small in screenshots.
Increase summary values, labels, chart axes/placeholders and plot heights on full
Edge layout, using spare hero whitespace. Keep smaller layouts compact and analysis
unchanged. Split rendering into small frames to preserve Garmin stack headroom.
Run the existing rendering smoke test and simulator suites, publish release.

---

# INTERVALS visual consistency — 2026-10-31

Owner supplied screenshots and requested a heading and graphs matching DRIFT.
Add INTERVALS/source header, matching hero/summary typography, independent power
and HR traces, shared zone gauges. Fixed 180-slot history; preserve missing gaps,
zero watts, pause gaps, reset and screen independence. Analysis and FIT unchanged.
Verify rendering in simulator, build/release and open updated production PRG.

---

# INTERVALS HR / raw HRR60 — 2026-10-31

Owner explicitly confirmed adding current HR and raw gated HRR60 for a joint test.
Implement separate bounded state, independent of screen. Preserve DriftEngine and
FIT schemas. Handle AUTO backdating, explicit segments, dropout/pause/new effort.
No normative scores, rep trend or diagnosis. Build/tests, push main and verify release.
See HEART_RECOVERY_RU.md for the measurement contract and engineering gates.

---

# Release distribution — 2026-10-31

Owner requested ready-to-install PRG downloads in GitHub releases. Build signed
production Edge 1050 before semantic-release, publish PRG and checksum assets.
Existing signing identity and minimal compiler profile use encrypted Actions
secrets, never Git or release assets. Verify a real GitHub Actions run.

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

# Дополнение владельца — 2026-10-31

Два отдельных коммита: (1) offline timer quality policy + регрессии и повторный аудит;
(2) offline-прототип автоматического выделения усилий и исследование архива.
Production DRIFT, FIT contracts и live INTERVALS остаются без изменений.
Автоматический детектор не переносится на Edge до отдельной проверки.

---

# INTERVALS — stage 1 (2026-10-31)

Owner authorized implementation and push to main in the current chat.

- Tap switches DRIFT / INTERVALS; both RIDE and LAST 60 remain on DRIFT.
- Separate constant-memory segment accumulator, independent of visible screen.
- Structured workout callbacks and manual laps only; Auto Lap ignored.
- No work/recovery inference: display SEG, source, average power, running duration,
  valid power count and interruption flag. First manual lap starts segment 1.
- Missing power is excluded, zero is included. Pauses freeze duration and mark interruption.
- New activity reset clears analysis, keeps screen choice. Old metric storage defaults to DRIFT.
- Keep DriftEngine, Python drift oracle and all FIT recorder contracts unchanged.
- Independent Python segment implementation and matching deterministic test streams.
- Build production/calibration and tests with strict level 3; run both simulator suites
  and Python suite. Document physical-device and historic FIT limitations.
- HR, HRR, rep matching, fatigue scores and automatic power segmentation are deferred.

See INTERVALS_RU.md for exact boundary and offline validation contract.

---

## Historical scope (superseded by the stage above)

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
