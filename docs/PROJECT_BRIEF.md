# DriftGuard — Project Brief

## Goal

Build a small, high-quality Garmin Connect IQ product for modern Garmin Edge computers, publish it in the official Connect IQ Store, get real installs and test whether a solo developer can earn the first real $1–10.

The first product is **DriftGuard**.

The project should validate the market before growing into a larger cycling SaaS.

## Developer profile

Primary experience:

- TypeScript / JavaScript
- React
- Node.js / NestJS
- REST / GraphQL / WebSocket
- APIs
- CI/CD

Monkey C is new.

Primary development OS: Windows 10/11.

Suggested tooling:

- VS Code + official Garmin Monkey C extension for `garmin-app`;
- WebStorm remains useful later for TypeScript backend / web.

## Target devices

Initial modern Edge family:

- Edge 540
- Edge 840
- Edge 1040
- Edge 1050

Milestone 1 may target Edge 1050 only to reduce setup friction.

## Product

DriftGuard is a Connect IQ **Data Field** for endurance cycling.

Primary user:

- road / gravel / endurance cyclist;
- uses a power meter;
- uses a heart-rate sensor;
- cares about Zone 2 durability, power/HR efficiency and aerobic decoupling.

Core problem:

Aerobic decoupling / Pw:HR is commonly inspected after the ride in analysis tools. DriftGuard aims to make a careful, quality-aware version visible on the Edge during the ride.

## Product principle

The differentiator is not simply displaying a drift percentage.

The differentiator is **validity / quality gating**.

DriftGuard should refuse to present a precise-looking aerobic-decoupling number when the data is too short, too incomplete or clearly inappropriate.

Possible states:

- NOT READY
- VALID
- STABLE
- WATCH
- HIGH DRIFT

These are sports-performance indicators, not medical diagnoses.

## Initial UX direction

Full-size concept:

```text
            2.8%

       AEROBIC DRIFT

           STABLE

Pw:HR                    1.57
Steady                   1:21

Power                   HR
218 W                  151
```

Before sufficient valid data:

```text
       AEROBIC DRIFT

         NOT READY

Steady data
18 / 40 min

Power                   HR
218 W                  151
```

Compact field:

```text
2.8%
DRIFT
```

or:

```text
2.8%
STABLE
```

The UI must be readable while riding, not merely attractive on a desktop screenshot.

## First algorithm direction

Do not overcomplicate v1.

Inputs:

- current power;
- current heart rate;
- elapsed / moving activity time.

Expected behavior:

1. Exclude an initial warm-up period.
2. Ignore unusable samples:
   - missing HR;
   - missing power;
   - stops / invalid samples;
   - other obvious conditions discovered during testing.
3. Accumulate sufficient valid data.
4. Compute Power-to-HR efficiency.
5. Compare early vs later valid steady-state data.
6. Compute an approximate aerobic decoupling percentage.
7. Independently determine whether the result is valid enough to show.

The calculation must be deterministic, documented and testable with synthetic fixtures.

Do not present a physiologically questionable number merely because the formula can produce one.

## MVP constraints

The first MVP is fully local.

Do **not** add:

- backend;
- database;
- LLM;
- Garmin Connect Developer API;
- weather API;
- payment integration;
- analytics infrastructure;
- remote network dependency.

These can be introduced only after a real product need appears.

## Store / business goal

First validation ladder:

- 10 installs;
- 20–30 installs + actual rides;
- 50–100 installs;
- first unsolicited useful feedback;
- first real paid unlock later.

Possible future price test: approximately $2.99 lifetime, likely via an external unlock mechanism suitable for Edge if/when monetization is introduced.

Monetization must not block MVP development.

## Possible product family later

1. **DriftGuard** — live Pw:HR / aerobic decoupling.
2. **FuelGuard / FuelLock** — persistent fueling guidance / intake tracking.
3. **ClimbBudget** — pacing / power budget to summit.
4. **RaceSheet** — offline-first race execution: pace + fuel + ETA.

Long-term architecture may become:

```text
Edge deterministic engine
        ↓
TypeScript planning backend
        ↓
route / weather / history
        ↓
optional AI before/after ride
```

LLM output should never be required for real-time 1 Hz decisions on the Edge.
