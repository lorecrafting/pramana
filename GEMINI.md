# Pramāṇa instructions for Gemini CLI / Antigravity

This is Gemini's native repository entrypoint. Shared project truth does not live in a
provider-specific file: `docs/AGENT_GUIDE.md` is canonical, and `docs/INDEX.md` is the
task-oriented documentation map.

## Start every task

1. Read `docs/AGENT_GUIDE.md`, the shared provider-neutral project contract.
2. Read `docs/STATUS.md` for current truth and only the relevant section of the authoritative
   `docs/PLAN.md` for current intent.
3. Use `docs/INDEX.md` to load only task-routed references.
   Application work loads the complete framework contract in `docs/DEV_ENV.md`.
   Local supervisor or Elixir workflow migration work also loads `workflow/README.md`,
   `workflow/docs/MIGRATION.md`, and `workflow/docs/MIGRATION-TICKETS.md`; current Python
   operations remain in `automation/RUNBOOK.md` until cutover.
4. For interactive questions, status inspection, failure diagnosis, or steering the running
   supervisor, read `automation/roles/steerer.md`.
   For supervised execution, read the named `automation/roles/*.md` file and exact assignment or
   review JSON. Verify its checkout, base revision, task ID, run ID, scope, and checks.
5. Inspect `git status` before edits. Preserve unrelated work and never use the original dirty
   checkout for an isolated assignment.

Run exact assigned checks and finish ordinary project changes with `mix precommit`. Stage only
scoped paths. Never write the research corpus, weaken baselines, expose credentials, run paid
inference, push, deploy, publish, or contact third parties without explicit authorization.

The eight project invariants, activity-to-rule trigger table, documentation rules, architecture
summary, and working conventions remain at `docs/AGENT_GUIDE.md`. Existing code and historical
documents that cite `CLAUDE.md` or `AGENTS.md` remain valid through this compatibility route.
