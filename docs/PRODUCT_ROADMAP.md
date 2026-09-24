# Product Roadmap

This roadmap is directional. It is **not** permission for the implementation agent to start future milestones early.

## Phase 0 — Toolchain

Goal: prove we can build and run a Connect IQ Data Field on Windows.

- SDK / device definitions
- VS Code + Monkey C
- Device Simulator
- Edge 1050 profile

## Phase 1 — DriftGuard basic telemetry

- Power
- HR
- Pw:HR
- missing-value handling

## Phase 2 — Drift calculation foundations

- valid-sample accumulation
- warm-up exclusion
- steady-duration accounting
- early vs later efficiency
- deterministic drift percentage

## Phase 3 — Validity detector

Possible states:

- NOT READY
- VALID
- STABLE
- WATCH
- HIGH DRIFT

The app must avoid showing false precision when the ride is too short or unsuitable.

## Phase 4 — UI polish and device support

- full-size layout
- compact layout
- Edge 540
- Edge 840
- Edge 1040
- Edge 1050
- readability tests in simulator and on-road

## Phase 5 — Physical testing

Test:

- power meter;
- HR strap;
- coasting;
- pause / resume;
- auto-pause;
- sensor dropout;
- long endurance ride;
- structured workout;
- page switching / navigation coexistence.

## Phase 6 — Store release

- icon;
- screenshots;
- description;
- support page;
- privacy statement as applicable;
- compatible devices;
- version / changelog;
- export `.iq`;
- submit to Connect IQ Store.

## Phase 7 — Product validation

Targets:

- first 10 installs;
- 20–30 installs with real rides;
- first unsolicited feedback;
- 50–100 installs;
- evidence of repeat usage.

## Phase 8 — Monetization experiment

Only if users care.

Possible model:

- free basic live metric;
- approximately $2.99 lifetime Pro unlock for advanced drift / validity / FIT / layout features.

External payment / entitlement approach must be re-checked against current Edge and Garmin rules before implementation.

## Future product family

### FuelGuard / FuelLock
Fuel reminders, acknowledgment, carb intake / debt.

### ClimbBudget
Power budget / pacing to summit rather than another ClimbPro clone.

### RaceSheet
Offline-first event execution plan:

- pacing;
- fuel;
- ETA;
- later route / weather planning backend.

## Long-term TypeScript expansion

Only after product validation:

```text
React web
   ↓
NestJS
   ↓
cycling domain services
   ↓
optional LLM / tools / MCP
   ↓
compact plan synced to Edge
```
