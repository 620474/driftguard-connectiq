# Milestone 1 — Live Power / HR / Pw:HR on Edge 1050 Simulator

## Goal

Create the smallest working Connect IQ Data Field and run it in Garmin Device Simulator using the Edge 1050 device profile.

The screen should display:

```text
DRIFTGUARD

POWER
247 W

HR
151 bpm

PW:HR
1.64
```

Values may differ based on simulator data.

## Requirements

Use standard Connect IQ activity data.

Display:

- current power;
- current heart rate;
- current Power / HR ratio.

Handle missing values gracefully.

Examples:

- missing HR → show `--`;
- missing power → show `--`;
- no ratio when HR is missing / zero;
- no NaN;
- no Infinity;
- no runtime crash.

## Scope

For this milestone only:

- Edge 1050;
- basic Data Field project;
- simple readable rendering;
- live Power / HR / Pw:HR.

## Explicitly out of scope

Do **not** implement yet:

- aerobic decoupling;
- rolling averages;
- warm-up exclusion;
- validity detector;
- settings UI;
- FIT developer fields;
- backend;
- network calls;
- AI;
- payments;
- analytics;
- support for all Edge devices;
- polished final Store graphics.

## Acceptance criteria

- Project builds successfully with the current supported Garmin Connect IQ toolchain.
- Data Field launches in Garmin Device Simulator using Edge 1050.
- Power and HR can be displayed from simulated activity data.
- Missing / zero values do not crash the field or produce invalid numeric output.
- Code remains small and understandable.
- No future-milestone functionality is introduced.

## Codex completion report

At the end, report:

1. Files created or changed.
2. Commands executed.
3. Build result.
4. Simulator result or exact blocker if simulator cannot be launched autonomously.
5. Any API assumptions that still require physical-device verification.

Stop after this milestone.
