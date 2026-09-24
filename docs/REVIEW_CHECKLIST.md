# Review Checklist

Use this checklist for Claude review or manual review after Codex implementation.

## Garmin API

- Are all Toybox APIs real and supported for the configured API level?
- Are any APIs used that are unavailable to the target device?
- Are lifecycle assumptions documented?
- Does the code rely on touch interaction for core functionality?
- Is device compatibility honest?

## Sensor data

- Missing HR handled?
- HR = 0 handled?
- Missing power handled?
- Power = 0 policy explicit?
- Sensor dropout handled?
- Reconnect handled?
- Stale values avoided?

## Numeric safety

- Division by zero impossible?
- NaN impossible?
- Infinity impossible?
- Percentage bounds / obviously corrupt values handled?
- Formatting stable?

## Cycling logic

- Warm-up policy explicit?
- Pauses / stops considered?
- Coasting policy explicit?
- Valid duration distinct from wall-clock duration?
- Short / non-steady efforts prevented from looking authoritative?
- No medical interpretation?

## Runtime / performance

- Excessive allocation inside frequent update loops?
- Storing unnecessary 1 Hz history?
- Rendering work reasonable?
- Avoidable repeated calculations?

## UX

- Main metric readable quickly?
- Compact layout useful?
- Labels understandable while riding?
- Missing / not-ready state clear?
- No dangerous interaction demands during a ride?

## Scope

- Does the change satisfy `CURRENT_TASK.md`?
- Did it introduce backend / AI / payments / future milestone work without permission?
- Is the implementation smaller than an overengineered alternative?

## Review output

Return:

### BLOCKING

### SHOULD FIX

### OPTIONAL

If there are no blocking issues, say so explicitly.
