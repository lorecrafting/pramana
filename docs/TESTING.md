# Testing: choose the right boundary

A green result only establishes what that check exercised. Run product commands from
`pramana/`; repository checks run at the Git root. Never start paid inference
or a public deployment merely to validate a documentation change.

| Change / question | Check | Prerequisites and limits |
|---|---|---|
| Documentation routing, links, rule coverage, task/tool indexes and layout | From the Git root: `elixir bin/check_docs.exs` | Elixir and Git only; no Mix dependencies, database, models or daemon |
| Pramāṇa pilot preflight bookkeeping | `elixir bin/check_pilot_preflight.exs --validate`; readiness claims use `--ready --subject <exact-candidate-git-sha>` | Network/model/database-free. Validates the recorded gate/evidence shape and explicit candidate-revision/ancestry binding; cannot establish substantive rights, evaluator or provider approval. |
| Chinese pilot acceptance contract | `elixir bin/check_pilot_acceptance.exs --validate` | Network/model/database-free. Pins the frozen v1 bounds/rubric/critical/rehearsal identifiers and their preflight alignment; it does not prove runtime enforcement, rehearsal success or retrieval quality. |
| Chinese pilot participant protocol | `elixir bin/check_pilot_participants.exs --validate` | Network/model/database-free. Pins consent, retention/deletion, withdrawal, evaluator separation, current-alternative intake and denominator rules plus preflight alignment; it does not establish that anyone has consented or been recruited. |
| Saved Chinese pilot scope artifact | `elixir bin/check_pilot_scope.exs --validate PATH` | Network/model/database-free. Checks the frozen scope schema, canonical hash, seed/relation/depth contract and internal denominators. It does **not** prove the file matches the current live corpus/release; generation uses the DB-backed Mix task and still requires review. |
| Umbrella formatting | `mix format --check-formatted` | Pinned umbrella toolchain and formatting dependencies |
| Umbrella code | `mix compile --warnings-as-errors`, `mix credo --strict`, `mix test --cover` | Umbrella dependencies, Rust NIF, PostgreSQL with required extensions; not a live corpus gate |
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
[Documentation CI](../.github/workflows/docs.yml) checks only documentation structure.
A read-only API, successful compilation or green test run does not by itself prove
licensing clearance, production hardening, account isolation or safe activation.

Record the exact commit, command, environment and outcome. Say explicitly which
checks were unavailable or skipped. Do not convert a source inspection into a claim
that code was executed.

## CI routing and reusable build caches

Heavy workflows are scoped to inputs they can actually exercise. Documentation-only
changes do not run the Pramāṇa database/Rust/Dialyzer/release lane.
The runtime-container workflow is narrower still: it runs for application, release,
configuration, Docker or runtime-smoke inputs, not every file below `pramana/`.
Repository layout tests pin these routing assumptions so a later edit cannot silently
restore an all-PR expensive lane or omit a named shared executable input.

Build caches are accelerators, never acceptance evidence. Pramāṇa CI builds its
PostgreSQL fixture from [a repository-owned Dockerfile](../pramana/ci/postgres.Dockerfile)
that pins the tested pgvector/PostgreSQL base by digest and pins pg_bigm to an immutable
upstream commit. Cached builds still request registry metadata (`pull: true`), but the digest
prevents identical source from silently moving to a newer PostgreSQL/pgvector image. BuildKit may restore layers
from GitHub's cache, but a cache miss must still build successfully. Cache export is allowed to fail without changing the build
result; losing an optimization is not a correctness failure.

Pull-request build steps restore reusable cache layers but omit cache export entirely.
Only the trusted `push` variant writes the shared BuildKit cache, so large PR-local caches
cannot crowd out the default-branch cache. A merged `main` run is therefore the producer
future PRs can reuse.

The ordinary Pramāṇa lane still performs a forced warnings-as-errors compile, full
model-free umbrella tests, Dialyzer and a fresh release build from the checked source.
The container lane still constructs the candidate's final runtime image and runs the
same synthetic-database release smoke. Reused Docker layers may contain unchanged
toolchain or dependency work; they do not substitute an older final image for the
candidate. No CI cache authorizes corpus acceptance, provider use or deployment.

## Repository layout checks

At the Git root, `mix format --check-formatted` covers only shared scripts/tests;
there is no root Mix application. Run product formatting inside `pramana/`.
`elixir bin/check_docs.exs` checks both documentation trees, project-root declarations,
figure discovery, the lockfile and the root wrappers using fake commands in isolated
directories. It cannot certify the operator's local data.

The Pramāṇa workflow uses `working-directory: pramana` for shell steps. Cache paths
remain Git-root-relative. Rust audits name both actual lockfiles. Native quotation
tests and production assets/release builds have explicit steps; no release is
started. The container workflow uses `pramana/` as its context and starts the built runtime
image only against owned disposable synthetic databases. Its [smoke runner](../pramana/ci/release_smoke.py)
checks explicit HTTP activation, assets/MCP, public-data refusal and administrative
non-serving behavior. Public cases use a distinct restricted login, with in-process
[effective-privilege/denied-write probes](../pramana/ci/serving_privileges.exs). Queued
bakes and old jobs remain unchanged on public nodes under both restricted and privileged
fixture credentials; the same job/source must be ingested by the real research queue
and old history pruned. Missing audit-read permission must still refuse startup. This is not a research-corpus, inference or production deployment
check. It never pushes an image.

## Compiler dependency evidence

[The dependency review runbook](agents/DEPENDENCY_REVIEW.md) owns local commands,
application scope, interpretation and reviewer handoff. Pramāṇa CI exports native
`xref` JSON, statistics and compile-connected cycle reports after successful forced
compilation. It requires graph/configured Elixir sources to be app-local tracked
regular files in the checksum inventory, checks dependency labels and source stability,
and records genuinely source-free apps as `no_elixir_sources` rather than failures.
Ignored/generated, symlinked and external sources are unsupported. It uploads a
seven-day schema-v2 artifact stamped with
the actual checkout SHA/tree, build environment and source hashes. A report from
a PR merge checkout is not automatically a report for the head commit alone.

Graph generation/schema failures remain visible CI failures, but there are no
node-count, dependency-count or cycle-count acceptance thresholds. An uploaded
artifact can coexist with failing tests elsewhere in the run. Graphs never select
or exclude tests and do not replace the normal checks above.

The maintained [collector regressions](../test/xref_collector_test.py) run with
`python3 test/xref_collector_test.py` from the Git root. They require Bash, Git and
the pinned Elixir/Mix but no Python packages, Mix dependencies or database. CI runs
them after BEAM setup. The tests execute the actual workflow collector and runbook
caller loop in temporary native Mix fixtures, including stale ignored input,
symlinks, external inputs, zero-source scopes and missing manifests. Their fixture
applications deliberately cannot start. They do not replace the application suite.

## Report lifecycle integration

[Report execution tests](../pramana/apps/pramana_web/test/pramana_web/mcp/report_execution_test.exs)
exercise the actual Streamable HTTP plug, Anubis session scheduler and report component
against isolated fixtures. Injected server-owned callbacks block or fail specific
stages; monitors establish worker termination, and a later request proves the same
session remains usable. These are lifecycle tests, not corpus-performance measurements.
The existing runtime-image smoke check still requires real report verification/repair
under restricted database credentials. Reader lifecycle and domain evidence tests remain
separate required regressions; none is replaced by a transport test.

## Behavior-first test maintenance

The [2026-09-15 test audit](RETIRED_FILES.md#retired-2026-09-24-the-single-product-cleanup)
recorded finding dispositions, suite ownership and coverage exclusions. Each changed test should name the plausible regression its fixtures
can distinguish. A count, successful return, or empty observation alone is not
proof of filtering, ordering, no-effect safety, or fresh-VM behavior.
