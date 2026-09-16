# Behavior-first test audit implementation

## Scope and source revision

This work implements findings F01–F22 from the September 15, 2026 test-value audit.
It starts from `fbe1205d8558b9362a341a0f9c78b596fb75a684`, **after PR #6**, and retains
that PR's release-drift and MCP error-provenance changes. The original audit was at
`0c3e61cc9aef761bef12603ce29929ea0a8dd389`: 197 ExUnit files inventoried, 89 fully
reviewed, one partly reviewed. An inventory entry is not deletion approval. Additional archive/figure helpers and the coordinator fixture setup were read
before their narrowly scoped isolation fixes here. This is not a claim that every test in
the repository has been audited.

The objective is a discriminating regression test, not a larger test count or a
higher coverage percentage. Existing safety containment, source bytes, provider
restrictions and corpus-scale tests remain in place.

## Finding disposition

| Finding | Implementation |
|---|---|
| F01 | The actual character-count backfill now uses grapheme clusters, matching the loader. Combining-mark, reload, 501-row/two-batch, idempotency and populated-row preservation tests call the task, not copied SQL. Source bytes are never normalized. |
| F02 | Removed fixture-only hyphen checks and the architecture test's self-defined list-length assertion. Real range and architecture restrictions remain. |
| F03 | Removed the seven duplicate suspended-integration scenarios. FR05's direct-entrypoint, no-effect containment remains authoritative. Integration is not reactivated. |
| F04 | Engine tests now submit real handoffs in both controlled mailbox orders and inspect one durable handoff record per identity. Pause/stop controls begin with a dispatchable ticket. Pure PM/quota/preparation checks have their own owners. This tests serialized coordinator ordering, not parallel OS execution. |
| F05 | Global revision-label tests are serialized and restore prior state exactly. Explicit report options now avoid eagerly evaluating a global default. The tests say label reconciliation, not code activation. |
| F06 | Synthetic stored vectors verify exact semantic date-filter results for complete, one-sided and missing bounds. The source-rights fixture now genuinely replaces stale permissive rights with restricted registry rights. |
| F07 | Distinct cosine scores and an over-limit candidate pool make ranking/limit failures observable. The candidate-budget plan used by production search is tested directly, separately from retrieval. Pure fusion/confidence contracts no longer insert a corpus. |
| F08 | Reader tests include a competing collection, a matching translation and an actually derived address. Result-local semantic selectors distinguish source hits from the translation panel and from page-wide warnings. |
| F09 | MCP tests decode structured payloads, plant language-specific reading exceptions with a wrong-language decoy, resolve a held parallel, and verify translated/untranslated neighbors with actual source hashes and offsets. |
| F10 | A unique unknown replay key must not exist as a VM atom before or after execution. |
| F11 | One fresh-BEAM subprocess checks mode/type mapping before a retriever loads. Shared-VM UI/MCP tests claim only ordinary dispatch. |
| F12 | Merged weaker mode, pagination, score-map, chunk-size and Derge duplicates into reviewed stronger owners. No blanket negative-test deletion. |
| F13 | Discovery/documentation compare nonempty runtime tool sets rather than historical counts; incidental generated callbacks are removed. Pure renderer tests avoid a DB connection. Focus is asserted through a semantic marker instead of a Tailwind class list. Intentional router budgets remain. |
| F14 | Source checks are labeled presence/declaration lints. Runtime span correspondence is checked separately. A real title-task dry-run must preserve rows and bytes, with a positive write control. |
| F15 | SQL body-transfer checks require captured queries before asserting the forbidden column is absent. |
| F16 | Identity dimensions, missing fields, task/run mismatches, deadline equality and exclusive resource classes have independent counterexamples and valid controls. Classification tests no longer claim exact-once process adoption. |
| F17 | Fake launch/prompt boundaries inspect durable intent before the effect occurs. An unreadable checkpoint must prevent all external calls. Existing recovery/no-resend and append-failure tests remain. |
| F18 | The saved benchmark is explicitly tagged and named artifact validation. Optional recomputation remains separate; a stored result is not a current performance measurement. |
| F19 | Telemetry uses a release handshake, not competing short timeouts. Public-mode, dummy credentials and global configuration are restored exactly. Reviewed temporary-file helpers clean up their outputs. |
| F20 | Small opt-in source/alignment fixture builders compute hashes and offsets and reject inconsistent alignments. Reader, neighboring-rendering, parallel, reranking and commentary-outline fixtures use real corresponding text/addresses. Deliberately absent candidates remain explicit. |
| F21 | Query capture distinguishes cheap punctuation diagnosis from actual database-backed diagnosis. Blank/whitespace quotations are existence-only and cannot increment verified-quote counts. |
| F22 | Coverage scope and execution lanes are stated below. Thresholds and coverage exclusions are not silently changed. No replacement filler is added. |

## Test ownership

Reader tests are split into search, passage, work, inventory, survey and provenance
capabilities, with a small shared fixture module. Parsing, grouping, candidate
planning, fusion and confidence cases use ordinary ExUnit where they do not query.
Database-backed integration tests retain sandbox isolation. The umbrella still
starts applications; changing a case template alone does not make it DB-free.

The native quotation executable also now has direct tests for maximal matches,
Unicode character offsets, self-reuse exclusion, minimum length and boilerplate
frequency boundaries. Its previous `cargo test` invocation ran no tests.

## Execution and coverage are different evidence

| Lane | Command / evidence | Does not establish |
|---|---|---|
| Shared repository | `elixir bin/check_docs.exs` | Application behavior or model quality. |
| Pramana mechanical CI | From `pramana/`: `mix test` plus native Cargo tests and static checks | Full-corpus completeness, HNSW planning at production scale, model quality, or enforced coverage thresholds. |
| Pramana coverage | From `pramana/`: `mix test --cover` (also used by the separate corpus gate) | Correctness merely because a line ran. |
| Foundry model-free CI | From `foundry/`: `elixir ci/run.exs --output <isolated-output>` | Authorized live-provider or activation acceptance. Read its exclusions/provenance. |
| Corpus/model/provider evidence | The separately authorized runbooks and gates | Never infer a pass from an excluded or absent lane. |

Configured coverage floors remain **87% core and 93% web**. These are configuration
values, not measurements in this document. The core's current exclusion pattern
covers `Pramana.Corpus.*`, including behavioral code such as Loader, not just
schemas. Those functions still have behavioral tests, but the headline percentage
does not measure them. Any future change to that denominator needs a separately
reviewed baseline, not a hidden adjustment to make this cleanup pass.

Core tests explicitly exclude `:corpus` when `raw/cbeta` is absent. Synthetic
semantic tests exercise SQL/result contracts, not large-index execution plans.
The saved Foundry benchmark fixture is historical evidence; only the explicitly
requested recomputation lane measures the implementation again.

## Operational boundaries

The backfill updates only null counts in bounded transactions; it does not rewrite
already populated counts or operate on a user's corpus during testing. Historical
counts produced by the old code require an explicitly scoped data-maintenance
operation, not an automatic migration hidden in a test cleanup.

The CI compile step now forces compilation before the test run. A baseline CI run
restored BEAM files from cache without the native tokenizer shared library and
failed before any tests could run. Forced compilation rebuilds the Rustler artifact
instead of treating that stale cache as a test result.

No Foundry repair status, provider profile, integration suspension, deployment or
activation authorization is changed. Runtime-startup, FR05 and checked-persistence
containment tests remain. Validation receipts belong in the implementation PR;
performance improvements are not claimed without timings.
