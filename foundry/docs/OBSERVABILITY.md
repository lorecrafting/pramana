# Foundry Observability

This document is both the implementation inventory and the target measurement contract
for Foundry diagnostics. Observability is **not authority**: telemetry may explain,
compare and improve work, but it cannot authorize a model request, retry, acceptance,
integration or activation. Unknown observations remain unknown rather than becoming
zero, success or reusable budget.

**Current-state warning, 2026-09-19:** the repository has useful telemetry schemas,
storage, exports, duration observations and VM/process metrics, but the live agent
lifecycle is not yet a coherent end-to-end telemetry pipeline. FR-18 owns alignment of
real producers, validators and consumers. Do not infer complete token/cost accounting
from the presence of the `llm_phase` schema.

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
   cache writes, total tokens, tool-result bytes admitted to context, context-source
   attribution, or operator steering/review/recovery effort.

Until FR-18 closes these gaps, lifecycle tables and dashboards should describe intended
or partial observations, not claim complete measurement.

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
duration, result size, truncation/error status and how much of the result was subsequently
admitted to model context. Tool output itself need not be duplicated into telemetry.

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
| context-source tax | Finds large context categories that do not improve accepted outcomes |
| tool-result context tax | Detects oversized or repeatedly irrelevant tool output |
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
| Agent step timings | Intended lifecycle observation; current AgentServer emitter is schema-misaligned | Profile launch bottlenecks after FR-18 producer repair |
| Agent lifecycle timeline | Coordinator/events plus intended telemetry | Reconstruct lifespan only after correlating authoritative execution identity and aligned producers |
| Token usage | Telemetry `llm_phase.metrics.*` schema only today | Requires selected-harness bridge and numeric-retention repair before end-to-end accounting |
| Duration forecasts | `Telemetry.Forecast.estimate/3` | Predict completion times from historical observations |
| Consolidated event timeline | `ConsolidatedLog.tail/1` | Cross-source time-ordered replay |
| Metrics snapshot history | `findings.jsonl` events with `source: "improver"` | Trend analysis over N cycles |
