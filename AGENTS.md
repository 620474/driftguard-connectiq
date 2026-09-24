# DriftGuard — Codex / implementation agent instructions

DriftGuard is a Garmin Connect IQ Data Field for endurance cyclists.

## Read first

Before changing code, read:

1. `docs/CURRENT_TASK.md` — the only scope you should implement now.
2. `docs/PROJECT_BRIEF.md` — product intent and constraints.
3. `docs/ARCHITECTURE.md` — current architecture and boundaries.
4. `docs/DECISIONS.md` — decisions that must not be silently reversed.
5. `docs/STATUS.md` — current state of the project.

## Your role

You are the implementation agent.

When you have repository and terminal access, do the work directly:

- inspect existing files first;
- make the smallest useful change;
- run the Garmin build / simulator-related checks that are available;
- fix compilation errors you introduced;
- inspect the final diff;
- keep changes inside the current milestone.

Do not stop at explaining what could be done when you can implement it.

## Project rules

- Do not invent Connect IQ APIs.
- If Garmin API behavior is uncertain, verify it against current Garmin documentation before coding.
- Do not add backend, database, LLM, weather API, Garmin Connect Developer API, payments, analytics, or cloud infrastructure unless `CURRENT_TASK.md` explicitly requires it.
- Do not implement future roadmap items early.
- Prefer deterministic local logic on the Edge.
- Avoid premature abstractions and framework-like architecture.
- Treat Garmin memory, lifecycle, rendering and device differences as real constraints.
- Handle missing sensor values defensively.
- Never display NaN, Infinity, obviously corrupt percentages, or stale values as if they were valid.
- Code should be easy to understand for a TypeScript developer learning Monkey C.
- Comment surprising Monkey C / Connect IQ behavior, not obvious syntax.

## Completion checklist

Before declaring a task complete:

1. Build the project.
2. Run relevant tests / simulator checks if available.
3. Inspect `git diff`.
4. Confirm the current milestone acceptance criteria.
5. Report:
   - what changed;
   - commands executed;
   - what passed;
   - what failed or remains uncertain;
   - recommended next step.

Do not move to the next milestone unless explicitly asked.
