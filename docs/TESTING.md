# Testing: choose the right boundary

A green result only establishes what that check exercised. Run commands from the
selected project root (`pramana/` or `foundry/`); repository checks run at the Git root. Never start paid inference, active
Foundry dispatch or a public deployment merely to validate a documentation change.

| Change / question | Check | Prerequisites and limits |
|---|---|---|
| Documentation routing, links, rule coverage, task/tool indexes and layout | From the Git root: `elixir bin/check_docs.exs` | Elixir and Git only; no Mix dependencies, database, models or daemon |
| Umbrella formatting | `mix format --check-formatted` | Pinned umbrella toolchain and formatting dependencies |
| Umbrella code | `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test --cover` | Umbrella dependencies, Rust NIF, PostgreSQL with required extensions; not a live corpus gate |
| Foundry code or contract work | From `foundry/`: `elixir ci/run.exs --output /tmp/foundry-ci-artifacts` | Isolated model-free runner; see [Foundry CI](../foundry/docs/CI.md). Does not prove real-provider execution or activation. |
| Corpus and retrieval acceptance | `mix pramana.gate` | Acquired/loaded corpus, matching database, required models and toolchain; see [detailed checks](../pramana/docs/CHECKS.md) |
| Re-running one declared source task | `mix help pramana.<task>` | Replace the placeholder with an actual task from [the CLI index](../pramana/docs/CLI.md) and inspect its options |

## Fresh test databases

From `pramana/`, `mix test` creates and migrates the configured test database before
recursive application startup. The umbrella owns this alias: a child-only alias
runs too late when an earlier child starts the domain app and Oban. It never drops
or resets a database. Test connection settings remain in `pramana/config/test.exs`.
Use an isolated test database, not an operator's corpus or production database.

## The umbrella gate is staged

[The gate implementation](../pramana/apps/pramana/lib/mix/tasks/pramana.gate.ex) defines the
steps and ordering. It runs format, compile, Credo, dependency audit, covered tests,
Dialyzer, lockfile census, coherence, generated figures, source verification,
integrity and evaluation. Independent steps within a stage may run concurrently;
a failing stage prevents subsequent stages, rather than cancelling the first sibling
that is still running.

`--quick` omits verify, integrity and evals. It still includes lockfile, coherence and
figure checks and is **not** a database-free lint command. `--from` resumes a gate
at a named step; omitted earlier steps have not been rechecked by that resumed run.

`mix pramana.evals --gate` compares with the existing baseline. Advancing an existing
baseline is a separate reviewed action using `--gate --accept`; a successful ordinary
gate does not automatically adopt improvements. Do not lower a baseline to hide a regression.

## Generated figures and live evidence

`mix pramana.docs.figures` checks marked blocks in `pramana/docs/*.md` and the
shared root `docs/*.md`, using explicitly configured documentation roots rather than
the shell working directory.
`--write` regenerates those blocks. Unmarked prose is not synchronized by that task.
On an empty corpus the task reports **not checked / not written** and returns normally;
its zero exit status is not a corpus verification result.

Keep the live blocks in [STATUS.md](../pramana/docs/STATUS.md) and [PLAN.md](PLAN.md) discoverable to
that scanner. Do not move them into chapters without changing and testing discovery.
A committed count is a recorded database snapshot, not proof of the current local database.

## CI is not deployment acceptance

[Umbrella CI](../.github/workflows/ci.yml) checks source/build/test concerns with a
Postgres service; it does not acquire and certify the research corpus.
[Foundry CI](../.github/workflows/foundry-ci.yml) is independently model-free.
[Documentation CI](../.github/workflows/docs.yml) checks only documentation structure.
A read-only API, successful compilation or green test run does not by itself prove
licensing clearance, production hardening, account isolation or safe activation.

Record the exact commit, command, environment and outcome. Say explicitly which
checks were unavailable or skipped. Do not convert a source inspection into a claim
that code was executed.

## Sibling-layout validation

At the Git root, `mix format --check-formatted` covers only shared scripts/tests;
there is no root Mix application. Run product formatting inside the product.
`elixir bin/check_docs.exs` checks both documentation trees, project-root declarations,
figure discovery, independent lockfiles, and root compatibility wrappers using fake
commands in isolated directories. It cannot certify the operator's external data.

The Pramāṇa workflow uses `working-directory: pramana` for shell steps. Cache paths
remain Git-root-relative. Rust audits name both actual lockfiles. Native quotation
tests and production assets/release builds have explicit steps; no release is
started. The container workflow uses `pramana/` as its context. Foundry's existing
isolated runner executes independently, without Pramāṇa dependencies.

[Cutover and rollback](LAYOUT_MIGRATION.md) describes checks for an existing corpus
and task worktrees. Do not substitute model-free structure tests for those checks.
