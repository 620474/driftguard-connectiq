# Decision Log

## 2026-09-24 — Start with a narrow Connect IQ Data Field

We will validate the market with a small Edge Data Field rather than build a broad cycling SaaS first.

Reason: faster path to a real Store release and real users.

## 2026-09-24 — DriftGuard is the first product

The first product focuses on Power-to-HR efficiency and quality-aware aerobic decoupling.

The main differentiation is validity gating, not simply another numeric metric.

## 2026-09-24 — Offline-first MVP

The first version must provide its core value entirely on the Edge.

No backend, database, weather API, LLM, Garmin Connect Developer API or network dependency in MVP.

## 2026-09-24 — Edge 1050 first, then broader compatibility

Milestone 1 targets Edge 1050 in the simulator to reduce setup complexity.

Later target family:

- Edge 540
- Edge 840
- Edge 1040
- Edge 1050

## 2026-09-24 — No medical claims

DriftGuard is a sports-performance tool.

It must not diagnose health conditions or present aerobic-decoupling thresholds as medical facts.

## 2026-09-24 — Deterministic live logic

Ride-time decisions and metrics are deterministic and local.

Potential future LLM usage is limited to pre-ride planning / explanation and post-ride analysis.

## 2026-09-24 — Monetization does not block validation

Initial release may be free.

Only after real usage should we add paid unlock / external payment experiments.

## 2026-09-25 — Live drift for the whole ride and the last hour

The fixed 15–45 minute result is replaced by two live metrics: RIDE drift over
all steady minutes and LAST 60 MIN drift. EF is average power / average HR, the
Intervals.icu definition, so results can be compared after a ride.

Only steady minutes count (valid data, power within ±20% of the ride median, not
in the 2-minute HR recovery after a non-steady minute). This favours validity
over matching Intervals.icu on hilly rides.

The main metric is switched by tapping the field; both stay visible, so the
product also works without touch.

STABLE < 5% follows common practice; the 10% HIGH DRIFT boundary and all
steady-filter thresholds are product heuristics to be calibrated on real rides.

## 2026-09-24 — Claude reviews, Codex implements

- Codex: implementation agent with repository / terminal access.
- Claude: architecture / Garmin API / algorithm / UX reviewer.
- Human owner: product decisions and acceptance of scope.
