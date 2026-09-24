# Milestone 2 — Quality-aware aerobic decoupling

## Goal

Add the first local aerobic-decoupling engine to the Edge 1050 Data Field.

## Calculation contract

- Initial warm-up is configurable in code and defaults to 15 minutes.
- A sample is valid only when the timer is running, power and HR are positive,
  and speed is either positive or unavailable (for indoor compatibility).
- Missing or zero power/HR, a stopped timer, and a known zero speed do not enter
  the calculation.
- The engine compares the first and second halves of the first 30 minutes of
  valid 1 Hz samples. It stores accumulators, not a ride history.
- Efficiency is average power divided by average HR for each half.
- Drift is `(firstHalfEfficiency - secondHalfEfficiency) / firstHalfEfficiency * 100`.
- At least 80% of post-warm-up samples observed while collecting the period must
  be valid. This prevents sparse data, stops, and coasting from looking steady.
- Power variability across the period must have coefficient of variation at or
  below 15%, which prevents interval-like power changes from looking steady.

## Validity states

- `NOT_READY`: warm-up has not elapsed, or fewer than 30 minutes of valid data.
- `NOT_STEADY`: enough valid data exists but the 80% quality threshold failed.
- `VALID`: enough valid, quality data exists and a finite drift value is available.

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
  data, sparse data, and highly variable power.
- Edge 1050 build and simulator tests pass.
