# Milestone 2 — Quality-aware aerobic decoupling

## Goal

Add the first local aerobic-decoupling engine to the Edge 1050 Data Field.

## Calculation contract

- Initial warm-up is configurable in code and defaults to 15 minutes of timer
  time (`Activity.Info.timerTime`, which excludes pauses).
- Samples with a stopped timer (pause, auto-pause) are ignored entirely: they are
  neither valid nor invalid.
- While the timer runs, a sample is valid only when power and HR are positive.
  Missing or zero power/HR (sensor dropout, coasting) is invalid. Speed is not
  used, so indoor rides without a speed sensor work.
- The engine compares the first and second halves of a period of 30 minutes of
  valid 1 Hz samples. It stores accumulators, not a ride history.
- Efficiency is average power divided by average HR for each half.
- Drift is `(firstHalfEfficiency - secondHalfEfficiency) / firstHalfEfficiency * 100`.
- At least 80% of the samples in a period must be valid (at most 450 invalid
  samples per 1800 valid). Once exceeded, the period is rejected and a new one
  starts.
- Power variability is the coefficient of variation of 30-second power averages
  across the period and must be at or below 15%. This rejects interval-like power
  changes without rejecting normal second-to-second pedalling noise. A rejected
  period restarts collection. The threshold needs validation on real outdoor rides.
- The first accepted period is the ride's result and is not recalculated.
- The engine resets on `DataField.onTimerReset()` (activity saved or discarded).

## Validity states

- `WARMUP`: warm-up has not elapsed.
- `COLLECTING`: collecting the first period (shown as NOT READY).
- `NOT_STEADY`: the last period failed a quality gate; a new one is collecting.
- `VALID`: a period passed both gates and a finite drift value is available.

Valid drift is labelled STABLE (< 5%), WATCH (5–10%) or HIGH DRIFT (≥ 10%).
These are sports-performance labels, not medical claims.

## Scope

- Edge 1050 only.
- Local deterministic calculation and basic rendering of state/value.
- Synthetic deterministic tests with known drift values.

## Explicitly out of scope

- backend, AI, networking, FIT developer fields, monetization;
- additional Edge models;
- settings UI or final Store UI;
- rolling or moving-window drift calculations.

## Acceptance criteria

- Calculation logic is separate from rendering.
- Missing values and stopped/coasting samples cannot create NaN or Infinity.
- Tests cover warm-up, known positive drift, missing sensor data, stopped/coasting
  data, sparse data, highly variable power, a result that stays valid for the rest
  of the ride, and reset between activities.
- Edge 1050 build and simulator tests pass.
