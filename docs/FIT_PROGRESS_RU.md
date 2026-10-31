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

## Per-repetition RECORD protocol (experimental)

A completed effort produces a held RECORD event that can be recovered after the ride. Six developer fields (IDs 14–19) are allocated in RECORD: `dg_rep_id` (uint16), `dg_rep_w` (uint16), `dg_rep_s` (uint16), `dg_rep_src` (uint8), `dg_rep_hrr` (sint16), `dg_rep_evt` (uint8). Including the existing RECORD fields, the combined allocation is below Garmin's 32-byte Data Field RECORD limit. The original session snapshots are retained.

- `evt=1`: a completed effort, a fresh sequential ID, W, s, source (AUTO=1, MANUAL=2, WORKOUT=3); HRR sentinel -32768 (unavailable).
- `evt=2`: same ID updated with a valid raw HRR60 delta (bpm) if recovery completes; not every effort qualifies.
- Developer values remain held until the next event. Repeated RECORD rows are **not** repeated intervals: `extract_repetitions()` deduplicates by (ID, event). Missing IDs and orphan HRR updates become warnings; no intervals are manufactured.
- Historical FIT without these fields have an empty repetition history; historical AUTO replay is a separate experiment, not device output.

**Crucial limitation:** Garmin `Field.setData()` updates the *next* FIT value, not an append-only event log. With Smart Recording or pause/discard, a fast event change before the next physical FIT write may be lost. Consequently this scheme records all detected efforts **provided each completion event is physically sampled in a RECORD message**; the decoder reports detectable gaps, but cannot establish completeness of every ride. Independent physical FIT testing is required before claiming 100% retention. For guaranteed append-only per-repetition storage a Data Field-only design may need a different Garmin-supported persistence mechanism or a different app architecture.

The HTML report now displays the reconstructed repetition table, source, duration, power and HRR60 for each ride; longitudinal chart still reports only DRIFT, not inferred interval fitness trends.

## Completion identity fix (2026-10-31)

AUTO sequence advances at effort start, while lastMean/lastSeconds still refer to
its predecessor. This formerly duplicated that predecessor in RECORD and could
misassociate a later HRR update. AUTO recording now keys completions by detectedEnd;
manual/workout recording retains boundary sequence. Identical-duration successive
completions remain distinct. Regression exercises real IntervalSession transitions.
Existing FIT files are unchanged; their duplicate IDs cannot be treated as true reps.

## AUTO candidate duration policy (experimental)

Experimental AUTO stops a candidate at 240 running samples without emitting a completed repetition, specifically to reject persistent baseline shifts such as the ~31-minute false candidate found in a real ride. This is a conservative **short-surge-only** mode; valid long sustained efforts also do not become AUTO repetitions. For those use a structured workout or manual LAP. The original FIT was replayed with a separate Python translation of the state machine: 3 short effort candidates (~62s, ~58s, ~57s) remain, with the long one suppressed. This is not a Garmin SDK, simulator, or on-device result.
