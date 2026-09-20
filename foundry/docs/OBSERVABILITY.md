# Foundry Observability

This document is both the implementation inventory and the target measurement contract
for Foundry diagnostics. Observability is **not authority**: telemetry may explain,
compare and improve work, but it cannot authorize a model request, retry, acceptance,
integration or activation. Unknown observations remain unknown rather than becoming
zero, success or reusable budget.

**Current-state warning, 2026-09-20:** the repository has useful telemetry schemas,
storage, exports, duration observations and VM/process metrics, but the live agent
lifecycle is not yet a coherent end-to-end telemetry pipeline. FR-18B owns alignment of
real producers, validators and consumers. Do not infer complete token/cost accounting
from the presence of the `llm_phase` schema. Foundry is **not currently unified under
OpenTelemetry**: `foundry/mix.exs` declares no OpenTelemetry packages and Foundry's own
runtime producers do not currently emit an application-wide `:telemetry` event contract.
The Erlang `telemetry` package is present only transitively through current dependencies.

## Data model: four local JSONL surfaces

The current system uses four append-oriented JSONL surfaces under
`foundry/local/state/current/`:

| Log | File | Current source | Boundary |
|---|---|---|---|
| **Coordinator log** | `coordinator.jsonl` | `LogStore.append/2` | Free-form diagnostic lifecycle events |
| **Telemetry log** | `telemetry.jsonl` | Mixed current producers | Intended home for validated telemetry; producer/schema alignment is incomplete |
| **Event log** | `events.jsonl` | checkpoint/durable lifecycle paths | Workflow transition evidence; not interchangeable with telemetry |
| **Findings log** | `findings.jsonl` | Improver | Metrics snapshots and derived findings |

### ConsolidatedLog

`PramanaFoundry.ConsolidatedLog.tail/1` merges coordinator, telemetry and event
logs into a time-sorted diagnostic view with a source tag. This is useful for inspection
and Improver classifiers; it does not turn those records into authoritative workflow
facts.

## Canonical telemetry schemas that exist today

`PramanaFoundry.Telemetry.Telemetry` implements two validated record types:

- `command` records: task/run/phase, exact start/end/duration, exit code,
  resource class and sanitized argv;
- `llm_phase` records: task/run/role/phase/provider/profile/model/reasoning,
  exact start/end/duration/outcome plus source-qualified provider metrics.

The current LLM metric vocabulary is:

- `prompt_input_tokens`
- `cached_input_tokens`
- `output_tokens`
- `reasoning_tokens`
- `context_window_utilization`

Every metric is stored as `{value, source, quality}`. Missing provider values are
explicitly unavailable. Prompt/response bodies, transcripts, environment values,
credentials and unknown provider payload fields are deliberately excluded from durable
telemetry.

The store provides validated JSONL reads/appends, deterministic JSONL/CSV exports,
deduplication and bounded compaction. `TelemetryStatus` can group records by
task/role/provider/profile/model/phase/outcome and report metric availability/source/
quality. `Telemetry.Observation` derives phase durations from lifecycle events.

## Known implementation gaps

These are current source findings, not hypothetical future requirements.

1. **AgentServer lifecycle telemetry does not match the canonical command schema.**
   `AgentServer.emit_telemetry/3` constructs a `record_type: "command"` record with
   fields such as outcome/reason/agent/pane/step timings while omitting the required
   command argv. `Telemetry.command/1` rejects unknown fields and requires `command`,
   so these records fail validation before `Telemetry.Store.append/2`.

2. **Coordinator uses a different telemetry shape.** Its local `emit_telemetry/3`
   writes EventLog-style maps directly with `EventLog.append/2` rather than the
   canonical Telemetry validator/store. A shared path therefore does not imply one schema
   or one trustworthy consumer contract.

3. **Live model usage is not bridged.** `llm_phase` and its exports are tested, but
   ordinary AgentServer/harness execution does not currently populate them. Token metrics
   are therefore schema capability, not current end-to-end accounting.

4. **Compaction does not preserve numeric token totals.** `Telemetry.Store.aggregate/1`
   currently retains duration totals plus metric source/quality counts and record IDs, but
   not the numeric metric values themselves. Longitudinal token/cost analysis cannot rely
   on compacted history until aggregate/merge validation preserves those totals.

5. **Identity is too coarse for efficiency accounting.** Canonical telemetry has task/run
   identity but not the full objective → ticket → attempt → execution → model request/tool
   → candidate/review/acceptance lineage required to separate productive work, retries,
   corrections and independent review.

6. **Cost, tool-context and human-effort accounting are not canonical.** There is no
   general production record for provider-reported monetary cost, subscription capacity,
   cache writes, total tokens, raw versus model-visible tool-result bytes, bootstrap/
   initial-context attribution, tool-contract/skill context, orchestrator wakeups, idle
   polling, or operator steering/review/recovery effort.

Until FR-18B closes these gaps, lifecycle tables and dashboards should describe intended
or partial observations, not claim complete measurement.

## OpenTelemetry and normalization direction

The current fragmentation is worth fixing because Foundry's self-improvement goal depends
on comparing the **whole cost of an accepted outcome**, not isolated log lines. The target
is one canonical observation model with multiple projections/sinks, not one giant log and
not an OpenTelemetry backend as a new source of truth.

A useful layering is:

```text
runtime producers / harness adapters / effect broker / checks / operator actions
                              |
                              v
                  canonical observation envelope
          stable identity + timing + source/quality + outcome
                              |
                :telemetry in-process event seam
                 /             |              \
                /              |               \
               v               v                v
      durable analytics   OpenTelemetry     live consumers
      / self-improver     traces/metrics    board/status
```

The authoritative workflow/effect store remains separate. It may be referenced by exact
IDs and may emit observations about committed transitions, but no trace collector,
dashboard, metric aggregate or dropped telemetry event may decide authorization,
acceptance, budget balance, effect issuance or recovery.

### Why use standard `:telemetry` plus OpenTelemetry

Elixir's `:telemetry` is a good low-coupling in-process seam: domain/runtime code can
emit a normalized event once and independent handlers can persist, aggregate or export it.
OpenTelemetry then supplies portable traces, metrics/log export and widely used semantic
conventions without requiring Foundry's domain code to depend on a particular backend.

OpenTelemetry's current GenAI semantic conventions include model/provider and token
concepts such as input, cache-read/cache-creation, output and reasoning tokens. Those
conventions remain under active development, so Foundry should maintain a **versioned
mapping** from its stable internal observation schema rather than make an unstable
external semantic-convention version the stored domain format.

Prompt/response content should remain excluded by default. GenAI content attributes can
contain user data, project secrets and large payloads; Foundry's optimization goals
normally require counts, digests, categories, timings and result sizes rather than full
conversation bodies.

### Canonical correlation model

Every observation should be able to carry the applicable subset of the durable lineage:

`objective_id → ticket_id → attempt_id → execution_id → request/tool/effect_id → candidate_id → review_id → accepted_outcome_id`

Add harness/session/provider IDs as **observed foreign identities**, not replacements for
Foundry execution identity. Use high-cardinality IDs for trace/span correlation and
durable analysis records; do not make them metric labels that explode time-series
cardinality.

The normalized model should cover at least these event families:

| Family | Required useful measurements |
|---|---|
| workflow/runtime | queue time, phase duration, retries/restarts, cancellation/reconciliation outcome |
| model request | provider/account route, model/profile/reasoning, latency, input/cache-read/cache-write/output/reasoning/total tokens, context use, reported cost |
| tool/effect | admitted capability/tool, duration, result bytes, bytes admitted to model context, truncation/error, claim/receipt correlation where applicable |
| context | source-category counts/bytes/digests for policy, role, spec, source, retrieval, tools, history and corrections |
| check/review | exact candidate identity, check/reviewer type, duration, outcome and correction relationship |
| human effort | steering, intervention, review/recovery/maintenance time where measurable |
| infrastructure | CPU/memory/process/queue/storage/network measurements with execution correlation |

Token fields should preserve provider-native semantics and source/quality. In particular,
do not double-count cache-read/cache-write classes when a provider's total already
includes them, and do not infer zero from absent usage.

### Trace shape for diagnosing token cost

A trace should make a costly outcome visually decomposable, for example:

```text
objective / ticket / attempt
  execution: developer
    context.compile
    model.request
      tool.read
      tool.test
      model.request
    candidate.freeze
  checks
  review
    model.request
  correction execution
    ...
  accepted outcome
```

This lets Foundry answer questions such as:

- Was the cost dominated by mandatory context, repeated source reads, tool-result bloat,
  compaction, review or correction?
- Did a cheaper model reduce request cost but increase rework and total accepted-outcome
  cost?
- Are workers waking/polling while no useful event exists?
- Did cache reads actually reduce paid/input work?
- Which task classes have poor first-pass acceptance or high reviewer/correction tax?
- Which context categories consume tokens without improving accepted outcomes?

The Improver should consume the same normalized durable observation records used for these
questions rather than scrape several incompatible logs.

### Metrics versus traces versus durable analytics

Use each signal for what it is good at:

- **traces:** exact high-cardinality causal/correlation paths for individual attempts;
- **metrics:** low-cardinality aggregate rates/histograms such as latency, token usage,
  accepted outcomes, correction rate and queue delay by stable task/model/profile class;
- **logs/events:** diagnostic detail and unusual failures;
- **Foundry durable observations:** provenance-preserving longitudinal/self-improvement
  dataset that survives exporter sampling/retention and can be reprojected.

OTel exporters are therefore optional sinks. Foundry should still be able to optimize
locally/offline and should not lose its self-improvement history when an external
observability backend samples or expires traces.

### Staged convergence under FR-18B

All five steps belong to FR-18B, not FR-18A. FR-18A is the minimal honest observation
surface — identities, source and quality, and explicit unknown, unavailable and corrupt
outcomes — and it is deliberately silent about producers. The producer chain, numeric
retention and any export are FR-18B's scope.

Do not perform a flag-day logging rewrite. Route the work through the owning FR-18B
requirements:

1. **Freeze the canonical observation envelope and identity vocabulary.** Reconcile
   `command`, `llm_phase` and lifecycle fields; define source/quality and unknown rules.
2. **Repair producers.** Make Coordinator, AgentServer, effect/tool execution and later
   harness adapters emit that contract through one module/`:telemetry` namespace.
3. **Repair numeric retention.** Compaction/aggregation must preserve token/cost totals,
   provenance and enough lineage to compute accepted-outcome economics.
4. **Bridge the selected harness.** Map direct Pi or Jido.Harness observations into the
   canonical model; preserve provider-native usage distinctions and unknowns.
5. **Add OpenTelemetry export.** Introduce pinned OTel dependencies/export configuration
   only after internal semantics are stable; map to a pinned semantic-convention version.
6. **Move Improver/status to canonical observations.** Stop treating
   `ConsolidatedLog` over heterogeneous files as the long-term analytics contract.
7. **Validate optimization loops.** Use fixed task classes and acceptance gates to show
   that a proposed token/context optimization lowers accepted-outcome cost or operator
   burden without reducing quality/safety.

This direction centralizes semantics without centralizing authority, and it preserves a
local durable dataset suitable for Foundry's self-improvement work.

### Candidate OpenTelemetry mapping

Prefer standard attributes when their semantics match, while retaining Foundry-specific
IDs in a separate namespace/mapping. Candidate mappings include:

| Foundry concept | OpenTelemetry direction |
|---|---|
| model/provider | GenAI request/response model and provider attributes |
| input/output tokens | GenAI usage input/output attributes |
| cache read/write | GenAI cache-read/cache-creation usage where equivalent |
| reasoning tokens | GenAI reasoning output usage |
| request/tool latency | span duration plus GenAI/tool semantic attributes |
| Foundry workflow identities | trace/span attributes and durable observation fields; avoid metric-label cardinality |
| accepted outcome/correction/review | Foundry-specific attributes/events until a suitable stable convention exists |

Treat this table as an adapter plan, not a promise that current OpenTelemetry GenAI
conventions are stable or sufficient for Foundry's domain.

## Target execution-observation contract

A selected harness should expose enough information for Foundry to produce one
source-qualified observation graph while keeping authority elsewhere. The durable
correlation chain should support:

`objective → ticket → attempt → execution → request/tool/effect → candidate → review → accepted outcome`

At minimum, a **model-request observation** should bind the exact execution/request,
role, harness/version, provider/account route, profile/model/reasoning, phase, start/end,
outcome and retry/compaction relationship. Preserve provider-exposed input, cache-read,
cache-write, output, reasoning/other token classes, total tokens, context use, latency and
reported cost where available. Each value names its source and quality; a later pricing
estimate is a different field from provider-reported cost.

A **tool observation** should bind the admitted capability/tool, invocation identity,
duration, raw result size, model-visible/admitted result size, truncation/error status,
preflight/execution phase and how much of the result was subsequently admitted to model
context. Tool output itself need not be duplicated into telemetry.

An **orchestration observation** should distinguish deterministic controller waits from
model invocations and record wake reason (event/deadline/operator/poll), whether the wake
had an actionable state change, child/job count and subsequent model request identity
when one was actually issued. This makes repeated "nothing completed yet" LLM polling
visible instead of hiding it inside generic turn counts.

A **context attribution observation** should record counts/digests rather than prompt
bodies for categories such as mandatory policy, role instructions, task/spec, source
files, retrieved docs, tool results, conversation history and correction history. Provider
totals may be exact while per-category attribution is estimated; retain that distinction.

A **human-effort observation** should make steering, review, intervention, recovery and
maintenance visible where measured. Subscription usage and local infrastructure also have
cost even when marginal provider cash spend is zero; report cash spend, subscription
capacity, infrastructure/storage and human effort separately.

Failed work must remain in the denominator. Developer, reviewer, PM/assessor, correction,
retry and compaction consumption all stay attached to their exact attempt/candidate rather
than being hidden behind the eventual successful run.

### Pi candidate mapping

The pinned Pi RPC contract referenced by [Foundry strategy](STRATEGY.md#pi-explicit-session-contracts-and-replaceable-execution)
is a promising source for this adapter because it provides strict JSONL headless control,
session statistics with input/output/cache-read/cache-write/total tokens, reported cost
and context usage, plus explicit compaction usage and before/after context estimates.
Those values are **observations**, not authority. A successful Pi prompt response means
accepted/queued/handled, not task completion.

If Pi is selected after FR-09/15a conformance, bridge its observations into Foundry's
versioned schema rather than persisting arbitrary Pi payloads as authoritative data.
Record the pinned harness/protocol version and preserve unknown values when a provider or
custom handler does not report a metric. Do not sum overlapping session/cumulative values
as if each were an independent request; the adapter must define and test settlement rules
for request-level and session-level usage.

For harness-efficiency experiments, also record the exact presentation/configuration
revision: active versus deferred tool-contract set, skill-loading mode, context/compaction
policy and ordinary structured-tool versus notebook/code-composition mode. These are
experimental factors, not authority. Keep the underlying CapabilityGrant, provider/model,
isolation and acceptance profile fixed when claiming a harness-level difference.

## Efficiency projections

The primary Foundry product measure remains trustworthy accepted delivery with low
operator burden. Useful secondary projections include:

| Projection | Purpose |
|---|---|
| accepted outcomes / operator hour | Measures the scarce human-attention resource |
| total/model tokens / accepted outcome | Compares comparable execution profiles without rewarding failed volume |
| provider cost / accepted outcome | Cash-cost view where provider-reported or explicitly estimated |
| first-pass acceptance rate | Shows how much work avoids correction |
| correction/review/failed-work tax | Makes rework and rejected attempts visible |
| cache-read/write effectiveness | Tests whether caching reduces real repeated input |
| bootstrap/harness context tax | Separates mandatory task context from repeated system/tool/skill overhead |
| context-source tax | Finds large context categories that do not improve accepted outcomes |
| tool-result context tax | Compares raw tool output with bytes/tokens actually admitted to the model |
| orchestration wakeup tax | Counts model wakeups with no actionable state change, especially idle child polling |
| preflight miss tax | Counts model/tool churn caused by deterministically knowable missing environment capabilities |
| wall-clock and queue time / accepted outcome | Separates model speed from scheduling/operational delay |

Do not optimize one projection in isolation. A lower-token run that increases missed
defects, correction cycles, operator review or unacceptable outcomes is not an efficiency
improvement. Comparisons need comparable task classes, fixed acceptance gates, a declared
baseline and enough observations to avoid inventing precision.

## System metrics

`PramanaFoundry.SystemMetrics` captures VM-level and per-process metrics. The Improver
includes a full snapshot in every cycle's `metrics_snapshot` event.

### VM-level (`SystemMetrics.system/0`)

| Field | Description |
|---|---|
| `total_memory_bytes` | Total Erlang VM memory |
| `processes_memory_bytes` | Memory used by BEAM processes |
| `ets_memory_bytes` | Memory used by ETS tables |
| `atom_memory_bytes` | Memory used by the atom table |
| `code_memory_bytes` | Memory used by loaded code |
| `binary_memory_bytes` | Memory used by binary references |
| `atom_count` | Current atom table size |
| `atom_limit` | Maximum atom table capacity |
| `process_count` | Current number of BEAM processes |
| `process_limit` | Maximum process capacity |
| `run_queue_length` | Length of the scheduler run queue |
| `uptime_seconds` | VM uptime |
| `ets_table_count` | Number of ETS tables |

### Per-process (`SystemMetrics.per_process/0`)

Tracks Coordinator, Improver, HardeningPM, and AssignmentSupervisor:

| Field | Description |
|---|---|
| `pid` | Process identifier |
| `memory_bytes` | Process heap memory |
| `mailbox_depth` | Unprocessed messages in mailbox |
| `reductions` | Process reduction count (CPU usage proxy) |
| `heap_size_words` | Current heap size |
| `total_heap_size_words` | Total heap including old generation |

### Agent child metrics (`SystemMetrics.agent_servers/0`)

Lists every child of the AssignmentSupervisor DynamicSupervisor:

```json
{
  "count": 2,
  "agents": [
    {
      "pid": "#PID<...>",
      "memory_bytes": 12345,
      "mailbox_depth": 0,
      "reductions": 67890
    }
  ]
}
```

## Health probe

`PramanaFoundry.Coordinator.health/0` returns a structured health report:

```json
{
  "status": "running|paused|stopping|unreachable",
  "queue_depth": 0,
  "active_assignments": 2,
  "running_agents": 1,
  "system": { /* SystemMetrics.system/0 */ },
  "per_process": { /* SystemMetrics.per_process/0 */ },
  "agent_servers": { /* SystemMetrics.agent_servers/0 */ }
}
```

## Self-healing Improver

The `PramanaFoundry.Improver` GenServer runs every 5 minutes. Each cycle:

1. Reads the last 500 records from `ConsolidatedLog`
2. Splits by source: telemetry vs events
3. Derives `Observations` from phase transitions
4. Computes `Forecast` estimates for expected durations
5. Runs classifiers against telemetry and events
6. Logs findings to `findings.jsonl`
7. For novel findings, creates PM proposals via `Coordinator.apply_pm_proposals`

### Classifiers

| Classifier | Triggers on | Creates |
|---|---|---|
| `classify_crashes` | ≥3 `phase: "task_crash"` | `:task_crashes` finding → P1 ticket |
| `classify_agent_crashes` | ≥3 `phase: "crash"` | `:agent_crashes` finding → P1 ticket |
| `classify_agent_timeouts` | ≥1 `phase: "timeout"` | `:agent_timeouts` finding → P1 ticket |
| `classify_launch_failures` | ≥30% failure rate on `agent_launch` | `:launch_failures` finding → P1 ticket |
| `classify_slow_ticks` | Tick events exceeding duration threshold | `:slow_ticks` finding |
| `classify_tick_crashes` | Any `tick_error` event | `:tick_crashes` finding |
| `classify_stuck_tickets` | Tickets in queue >120s without admission | `:stuck_tickets` finding |
| `classify_process_memory` | Coordinator memory >50MB | `:high_memory` finding |
| `classify_task_sup_capacity` | TaskSupervisor near full | `:task_sup_full` finding |
| `classify_no_events` | Event log completely empty | `:no_activity` finding |
| `classify_coordinator_restart` | Generation counter changed | `:coordinator_restart` finding |
| `classify_observation_anomalies` | Duration outliers vs forecast | `:duration_anomaly` finding |
| `classify_duplicate_run_ids` | Repeated run_id across tasks | `:duplicate_run_id` finding |
| `classify_assignment_consistency` | Stale/broken assignment records | `:assignment_inconsistency` finding |

### Metrics snapshot

Every cycle emits a `metrics_snapshot` event to `findings.jsonl` containing the full
`SystemMetrics.snapshot()` — system-wide stats, per-process metrics, and agent child
metrics. The board's findings panel displays the latest snapshot.

## CLI diagnostic commands

```bash
# Health report (JSON)
pramana_foundry health

# List running agents
pramana_foundry agents

# System metrics overview
pramana_foundry metrics

# Consolidated log tail
pramana_foundry logs tail N

# Log summary (record counts per source)
pramana_foundry logs summary

# Telemetry status projection
pramana_foundry telemetry-status PATH

# Telemetry export
pramana_foundry telemetry-export jsonl|csv INPUT OUTPUT
```

## Raw primitives available for future diagnostics

| Data | Access path | Purpose |
|---|---|---|
| Per-process memory/mailbox/reductions | `SystemMetrics.per_process/0` | Detect memory leaks, stuck agents |
| Agent child list with resources | `SystemMetrics.agent_servers/0` | Track agent count, detect orphaned panes |
| VM memory breakdown | `SystemMetrics.system/0` | Diagnose OOM, ETS bloat, atom table growth |
| Agent step timings | Intended lifecycle observation; current AgentServer emitter is schema-misaligned | Profile launch bottlenecks after FR-18B producer repair |
| Agent lifecycle timeline | Coordinator/events plus intended telemetry | Reconstruct lifespan only after correlating authoritative execution identity and aligned producers |
| Token usage | Telemetry `llm_phase.metrics.*` schema only today | Requires selected-harness bridge and numeric-retention repair before end-to-end accounting |
| Duration forecasts | `Telemetry.Forecast.estimate/3` | Predict completion times from historical observations |
| Consolidated event timeline | `ConsolidatedLog.tail/1` | Cross-source time-ordered replay |
| Metrics snapshot history | `findings.jsonl` events with `source: "improver"` | Trend analysis over N cycles |
