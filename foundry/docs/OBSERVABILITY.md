# Foundry Observability

This document describes every observability surface in the Pramāṇa workflow system:
structured logs, telemetry records, health probes, CLI diagnostic commands, the
self-healing Improver, and the raw primitives available for future analysis.

## Data model: three structured logs

The system writes to three append-only JSONL files under `foundry/local/state/current/`:

| Log | File | Schema | Source |
|---|---|---|---|
| **Coordinator log** | `coordinator.jsonl` | Free-form map with `event`, `source`, `at` | `LogStore.append/2` |
| **Telemetry log** | `telemetry.jsonl` | Validated `command`-type records via `Telemetry.Telemetry.validate/1` | `emit_telemetry/3` in Coordinator, AgentServer |
| **Event log** | `events.jsonl` | Checkpoint events from `Effects.Checkpoint` | Agent lifecycle transitions |
| **Findings log** | `findings.jsonl` | `metrics_snapshot` and `finding` events from the Improver | `LogStore.append/2` in Improver |

### ConsolidatedLog

`PramanaFoundry.ConsolidatedLog.tail/1` merges the coordinator, telemetry, and event
logs into a single time-sorted view with a `source` tag (`"coord"`, `"telemetry"`,
`"events"`). This is what the Improver reads and what `pramana_foundry logs tail N`
displays.

## Telemetry records

Every telemetry record uses the `command` type schema defined in
`PramanaFoundry.Telemetry.Telemetry`:

```json
{
  "record_id": "<hex>",
  "record_type": "command",
  "phase": "<phase_name>",
  "task_id": "<id>",
  "run_id": "<hex>",
  "started_at": "<iso8601>",
  "ended_at": "<iso8601>",
  "duration_ms": <integer>,
  "outcome": "<dispatched|failed|timeout|accepted|rejected|crashed>",
  "reason": "<optional structured error>",
  "exit_code": 0,
  "resource_class": "workflow",
  "command": ["<phase_name>"]
}
```

### Phase types

| Phase | Emitted by | Occurs when |
|---|---|---|
| `agent_launch` | Coordinator | An AgentServer launch completes (success or failure). `outcome: "dispatched"` on success, `"failed"` on failure. On success, includes `step_timings` with `pane_split_ms`, `agent_start_ms`, `prompt_ms`. |
| `agent_timeout` | AgentServer | A running agent reaches its `work_timeout_ms` and is shut down. |
| `agent_handoff` | AgentServer | A handoff is submitted to a running agent, forwarded to the coordinator. |
| `agent_crash` | AgentServer (terminate/2) | An agent exits abnormally (crash, killed). |
| `agent_completed` | Coordinator | An agent completes for any reason (handoff accepted/rejected, timeout, etc.). |
| `agent_crash` | Coordinator | Coordinator receives and records an agent crash notification. |

### Token metrics (future)

The `Telemetry.Telemetry` module defines `llm_phase` record type with token metric
fields — the schema and export path exist for when Herdr agent responses include
token usage info:

```json
{
  "metrics": {
    "prompt_input_tokens": <integer>,
    "cached_input_tokens": <integer>,
    "output_tokens": <integer>,
    "reasoning_tokens": <integer>,
    "context_window_utilization": <float>
  }
}
```

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
| Agent step timings | Telemetry `agent_launch.step_timings` | Profile launch bottlenecks (pane split vs agent start vs prompt) |
| Agent lifecycle timeline | Telemetry `agent_launch` → `agent_completed` / `agent_crash` / `agent_timeout` | Full agent lifespan tracking |
| Token usage (schema only) | Telemetry `llm_phase.metrics.*` | Ready for Herdr token bridge |
| Duration forecasts | `Telemetry.Forecast.estimate/3` | Predict completion times from historical observations |
| Consolidated event timeline | `ConsolidatedLog.tail/1` | Cross-source time-ordered replay |
| Metrics snapshot history | `findings.jsonl` events with `source: "improver"` | Trend analysis over N cycles |