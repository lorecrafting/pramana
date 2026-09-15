# Pramāṇa observability

**Working directory:** `pramana/` for the commands and source-relative paths below.
Shared policy and the active plan remain at repository `docs/`. Existing corpus,
models and virtualenvs are not moved: see [layout migration](../../docs/LAYOUT_MIGRATION.md).

Current source reference. This is distinct from
[Foundry observability](../../foundry/docs/OBSERVABILITY.md). The original audit's
"no domain telemetry" findings are [historical](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md), not
the current implementation.

## Implemented observations

[Pramana.Telemetry](../apps/pramana/lib/pramana/telemetry.ex) emits domain events;
[the web telemetry module](../apps/pramana_web/lib/pramana_web/telemetry.ex) defines
metrics for them alongside Phoenix, database and VM metrics.

| Boundary | What is observed | Limit |
|---|---|---|
| Retrieval | Duration, result count, mode/outcome and retriever metadata | A configured mode is not proof every retriever ran |
| Citation guard | Check duration and verdict counters | Not a persisted transcript or proof of entailment |
| MCP replies | Tool call counts via reply construction | Not end-to-end tool duration; failures before reply construction may differ |
| Bake work | Work duration, segments and outcome metadata | Not a substitute for integrity verification |
| Acquisition | Duration/bytes and source/outcome metadata | Source permissions and network correctness are separate |
| Coverage caveats | Caveat counters | A reported gap is not automatically an acquisition task |

The telemetry helper can attach the current source identity. An identity lookup can
fail and yield no identity rather than crash the operation being observed. These
events are not a content-complete retrieval-release trace.

## Oban failures and retention

The application attaches an Oban exception handler at startup. It reports job failure
context, including worker/attempt/node information; the handler does not own retry
policy. [config/config.exs](../config/config.exs) configures the Oban pruner for seven
days of terminal-job retention. Retention of job rows is not equivalent to retaining
all corpus outputs, query logs or provider transcripts.

## Reading the system

For a loaded research database, `mix pramana.doctor` reports source and derived-state
facts. `mix pramana.release.stamp` **writes** a retrieval-state stamp and is not a
read-only diagnostic. The stamp has the [limitations documented in architecture](ARCHITECTURE.md#identity-and-replay).

The development dashboard is routed at `/dev/dashboard` only when development routes
are enabled. A metrics definition does not automatically configure a durable external
metrics backend; the console reporter remains commented out in the current source.

MCP success/error payloads carry replay information, but replay metadata is neither a
stored query log nor a promise of identical results after data or code changes.
There is no default durable audit trail of every research query established by this
module. Any such feature needs an explicit privacy, access and retention policy.

## Verification

Use [testing](../../docs/TESTING.md) for code checks and corpus acceptance. Check a real deployment's
handlers, exporters and retention before claiming it is monitored. The documentation
audit inspected the implementation; it did not observe a running service or provider.

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="observability--what-this-system-can-and-cannot-tell-you-about-itself"></a>[Observability — what this system can and cannot tell you about itself](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#observability--what-this-system-can-and-cannot-tell-you-about-itself) |
| <a id="the-one-line-summary"></a>[The one-line summary](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#the-one-line-summary) |
| <a id="what-the-audit-found"></a>[What the audit found](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#what-the-audit-found) |
| <a id="what-is-already-good-and-worth-not-breaking"></a>[What is already good, and worth not breaking](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#what-is-already-good-and-worth-not-breaking) |
| <a id="the-cost-measured-on-this-project-rather-than-argued"></a>[The cost, measured on this project rather than argued](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#the-cost-measured-on-this-project-rather-than-argued) |
| <a id="plan-cheapest-first"></a>[Plan, cheapest first](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#plan-cheapest-first) |
| <a id="1-mix-pramanadoctor--the-state-a-session-needs-in-one-command"></a>[1. `mix pramana.doctor` — the state a session needs, in one command](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#1-mix-pramanadoctor--the-state-a-session-needs-in-one-command) |
| <a id="2-domain-telemetry-at-five-boundaries---built-2026-08-29"></a>[2. Domain telemetry at five boundaries — ▸ BUILT 2026-08-29](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#2-domain-telemetry-at-five-boundaries---built-2026-08-29) |
| <a id="3-an-oban-failure-handler---built-2026-08-29"></a>[3. An Oban failure handler — ▸ BUILT 2026-08-29](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#3-an-oban-failure-handler---built-2026-08-29) |
| <a id="4-structured-errors-on-the-mcp-surface---built-2026-08-29"></a>[4. Structured errors on the MCP surface — ▸ BUILT 2026-08-29](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#4-structured-errors-on-the-mcp-surface---built-2026-08-29) |
| <a id="5-guard-refusals-and-caveat-counts---built-2026-08-29"></a>[5. Guard refusals and caveat counts — ▸ BUILT 2026-08-29](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#5-guard-refusals-and-caveat-counts---built-2026-08-29) |
| <a id="what-this-deliberately-does-not-propose"></a>[What this deliberately does not propose](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md#what-this-deliberately-does-not-propose) |
