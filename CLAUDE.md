# CLAUDE.md — Pramāṇa

This project uses **`AGENTS.md`** as its canonical reference. Read it first.

`AGENTS.md` contains: project overview, non-negotiable invariants, document routing
table, project layout (including the foundry/ subproject), rules trigger table,
documentation maintenance conventions, framework guidelines, and foundry observability.

## Session start

```
AGENTS.md → docs/STATUS.md → docs/PLAN.md → (document for what you're doing)
```

## Claude-specific notes

- This file is loaded first by Claude Code. `AGENTS.md` has the full project context.
- Claude Code works in this repo using the Oh My Pi coding harness. Follow tool
  conventions: `read` for files, `edit` for changes, `grep` for search, `task` for
  delegation.
- The `docs/RULES.md` rules trigger table is in `AGENTS.md` — check it before starting
  any activity.

## Key docs

| Doc | What |
|---|---|
| `AGENTS.md` | Canonical project reference |
| `docs/STATUS.md` | What is true now |
| `docs/PLAN.md` | What to do next |
| `docs/RULES.md` | 84 rules from real defects |
| `docs/CHECKS.md` | Phase gates |
| `foundry/docs/OBSERVABILITY.md` | Foundry telemetry and health