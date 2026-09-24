# Architecture

## Current phase

MVP / Connect IQ learning phase.

The architecture is intentionally small.

```text
garmin-app/
  manifest.xml
  monkey.jungle
  source/
  resources/
```

No backend exists in the current phase.

## Runtime model

DriftGuard is a Connect IQ Data Field running inside the normal Garmin cycling activity experience.

High-level flow:

```text
Garmin Activity.Info
      ↓
sample validation
      ↓
metric accumulation
      ↓
Pw:HR / drift / validity
      ↓
Data Field rendering
```

The live loop must not depend on the network.

## Intended code structure after Milestone 1

Do not create this structure until it is justified by actual code.

A reasonable direction is:

```text
source/
  DriftGuardApp.mc
  DriftGuardView.mc

  metrics/
    SampleAccumulator.mc
    EfficiencyCalculator.mc
    DriftCalculator.mc
    ValidityEvaluator.mc

  ui/
    FullLayout.mc
    CompactLayout.mc
```

This is a direction, not a requirement to create empty abstractions.

For Milestone 1, a much smaller project is preferred.

## Data handling rules

- Missing HR or power must be handled explicitly.
- Do not divide by zero.
- Do not show stale sensor values as current without a clear policy.
- Do not emit NaN or Infinity.
- Avoid unnecessary allocation in code that runs frequently.
- Prefer accumulators / rolling summaries over retaining every 1 Hz sample when possible.
- Distinguish elapsed time from valid steady-state sample duration.

## UI rules

- Main metric must be legible at a glance.
- Full-screen and compact layouts may show different information density.
- UI should degrade gracefully on smaller field sizes.
- Touch interaction must not be required for the fundamental value of DriftGuard because Edge 540 is non-touch.
- Device-specific assumptions must be documented.

## Future backend boundary

If a backend is later introduced, it belongs outside the live 1 Hz calculation loop.

Potential later structure:

```text
/garmin-app   Monkey C
/api          NestJS / TypeScript
/web          React / TypeScript
/shared       schemas / protocol docs
```

The Edge must cache enough information to remain useful without connectivity.

## AI boundary

AI is not part of the current architecture.

Potential later use:

- pre-ride plan explanation;
- post-ride analysis and narrative;
- tool-calling / MCP around normalized cycling data.

AI should explain or orchestrate domain calculations, not replace deterministic ride-time math.
