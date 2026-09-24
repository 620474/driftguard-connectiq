# DriftGuard Connect IQ

Private development repository for **DriftGuard**, a Garmin Connect IQ Data Field for endurance cyclists.

The first product goal is a quality-aware live Power/HR and aerobic-decoupling field for modern Garmin Edge devices.

## Start here

- [Project brief](docs/PROJECT_BRIEF.md)
- [Current task](docs/CURRENT_TASK.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Decision log](docs/DECISIONS.md)
- [Project status](docs/STATUS.md)
- [Roadmap](docs/PRODUCT_ROADMAP.md)

## AI workflow

- **Codex** is the implementation agent. Its persistent instructions are in [AGENTS.md](AGENTS.md).
- **Claude** is the reviewer / lightweight tech lead. Its instructions are in [CLAUDE.md](CLAUDE.md).
- Review rubric: [docs/REVIEW_CHECKLIST.md](docs/REVIEW_CHECKLIST.md).

## Current milestone

**Milestone 1 — Live Power / HR / Pw:HR on Edge 1050 Simulator**

The first implementation should remain intentionally small:

- Connect IQ Data Field;
- Edge 1050;
- current power;
- current HR;
- Power/HR ratio;
- defensive missing-value handling.

No drift calculation, backend, AI or monetization yet.

## Planned target devices

- Edge 540
- Edge 840
- Edge 1040
- Edge 1050

## Repository layout

```text
.
├─ AGENTS.md
├─ CLAUDE.md
├─ docs/
│  ├─ PROJECT_BRIEF.md
│  ├─ ARCHITECTURE.md
│  ├─ CURRENT_TASK.md
│  ├─ DECISIONS.md
│  ├─ STATUS.md
│  ├─ PRODUCT_ROADMAP.md
│  └─ REVIEW_CHECKLIST.md
└─ garmin-app/
   └─ README.md
```

The actual Garmin project files will be generated after the local Windows Garmin SDK/toolchain is verified.

## Releases

Pushes to `main` run semantic-release in GitHub Actions. It creates version tags
and GitHub Releases from [Conventional Commits](https://www.conventionalcommits.org/):
`fix:` creates a patch release, `feat:` a minor release, and a `BREAKING CHANGE:`
footer a major release. `docs:`, `chore:`, and other non-release commit types do
not publish a release.
