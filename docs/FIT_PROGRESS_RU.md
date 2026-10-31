# FIT summary and offline progress — experimental

This change adds **session-only** developer fields to the existing FIT recorder. No extra RECORD fields were introduced; the existing per-minute DRIFT contract is unchanged.

| Developer field | Type | Meaning |
| --- | --- | --- |
| `dg_last_effort_w` | float | Mean power, last completed effort (W) |
| `dg_last_effort_s` | uint16 | Duration, last completed effort (s; capped at 65535) |
| `dg_last_effort_src` | uint8 | Source: 1 AUTO, 2 MANUAL, 3 WORKOUT |
| `dg_hrr60_last` | float | Last valid raw HRR60 (bpm, signed) |

These are **snapshots**, not all repetitions and not session averages. Missing/invalid values are not reported as zero. Existing FIT fields use their existing IDs 0–9; new fields use IDs 10–13. No baseline, algorithm threshold, or sensor definition was modified.

## Local progress

From `validation-lab/`:

```bash
python -m driftlab.cli run --offline --import-dir /path/to/fit/files --months 6
```

Open the generated `.data/report/index.html` locally. The new trend chart uses `models.current.summary.ride.drift` from *decoded and replayed* activities, not the session developer field, and can therefore also show older recordings. Strict mode includes only `comparison_candidate`, known timer state, at least 90 min running, VALID RIDE drift and at most 3% power change between halves. It does **not** normalize power, HR, temperature, course, or duration. No medical/fitness improvement claims can be made from the plot alone.

## Verification still required

- Compile production and calibration Monkey C, run existing simulator and Python test suites.
- On a physical Edge 1050: record a completed AUTO effort, a complete 60 s recovery, and a manual/workout segment. Decode FIT developer fields and verify exact values, names, units, and developer identity.
- Check device FIT-field allocation and session fields alongside third-party data fields; `createField` can fail with limited budgets.
- Check on-device activity reset; discard/save/restart must not leak stale data.

The current reporting UI is retrospective **drift**, not interval-by-interval trends. Persisting each repetition would need a separately validated EVENT/LAP or buffered FIT schema; it is **not** implemented by these four session fields.
