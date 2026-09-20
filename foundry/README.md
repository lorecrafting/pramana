# Pramāṇa foundry

**Audit, 2026-09-12:** The [architecture and lifecycle audit](docs/AUDIT-2026-09-12.md)
found that the live execution path bypasses several safeguards described below.
Treat the following capability list as an implementation inventory, not verified
end-to-end guarantees. The audit includes reproductions and an ordered repair plan.

**Status: live.** The Elixir OTP release is the sole local dispatcher — Python supervisor
retired and state archived, self-healing Improver loop active. This standalone Mix project
supplies the local OTP release/CLI shell, strict schema validation, durable-state and
fencing, typed Herdr adapter, checkpointed OS-child/check lifecycle with process-group
ownership and crash-recovery adoption, deterministic scheduling, PM planning lifecycle
with attempt caps, quota cooldown and subscription fallback, exact-commit review, serial
candidate integration, terminal board, sanitized local BEAM inspection, journaled
workspace relocation, cutover facade, soak/restart harness, telemetry-driven
self-healing Improver, full system metrics, health probes, and structured observability.

The project remains independent of the Phoenix umbrella, Postgres, the research corpus, and
`priv/embed/`.

## Acceptance and activation containment

FR-05 disables legacy promotion and mutable-source activation. Public handoff and review
commands preserve the submitted artifact identities verbatim, require an existing Git
checkout, and cannot request the production Git-check bypass. `auto_approve` is rejected
at admission, runtime, PM and replay boundaries; reviews require a separately issued
reviewer run identity. The legacy integration command stops before intent, check, Git or
state effects. Historical `integration_completed/succeeded` records are retained only as
explicit `legacy_unverified` claims and cannot advance `accepted_revision`.

`bin/pramana-live.sh`, `bin/tickets_from_review.sh` and `bin/live_test.exs` are disabled.
FR-13 restores controller-verified artifact/check evidence, FR-14 restores protected Git
promotion, and FR-17 restores immutable accepted-build activation and rollback. Status
revision values remain presentation-only labels, not acceptance or activation evidence.

## Automatic execution containment

FR-01 is implemented as fail-closed static containment. Automatic developer, reviewer and
PM eligibility requires an explicit plain-map policy naming the OMP profile, provider,
account, subscription billing authorization, exact allowed model, reasoning and approval
mode, authorized roles, quota state and any provider cooldown. Missing, malformed, paid,
exhausted, unknown or cooled-down policy blocks before pane creation. The temporary inputs
are the `:pramana_foundry` application keys `:launch_profiles` and
`:launch_role_profiles`; Coordinator options of the same names exist for isolated tests.

Configuration alone cannot enable a real launch. The production Herdr System runner
deliberately reports subscription-route enforcement as unsupported, because installed OMP
profile selection does not itself prove account/billing isolation or exclude API-key
fallback. FR-09 and FR-15a own that protected conformance boundary and may restore real
automatic execution only with exact backend evidence. FR-16 owns durable quota observation
and bounded switching. Do not treat a model name, available credential or this temporary
policy as entitlement, and do not change the System capability as an operator workaround.

## Agent command transport

`bin/pramana` treats every user argument as inert data. It invokes Elixir with those values
only in `System.argv/0`, encodes a bounded versioned JSON envelope as canonical URL-safe
base64, and sends one fixed `PramanaFoundry.CLI.RPC.run/1` expression to the release.
The daemon rejects malformed, duplicate-key, oversized, non-UTF-8, NUL-containing and
unknown command shapes before calling the CLI. The wrapper preserves remote stdout,
stderr and exit status.

This is FR-02 containment, not a claim that the release's general `rpc` evaluator is a
safe public authority boundary. Keep access local/protected; FR-15a replaces that general
evaluation credential. The older maintenance scripts named in the repair plan remain
disabled/routed to their containment owners until rewritten.

## Read first

- [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md) — telemetry records, health probe,
  system metrics, CLI diagnostics, self-healing classifiers.
- [`docs/MIGRATION.md`](docs/MIGRATION.md) — destination architecture, runtime and storage
  boundaries, parity matrix, cutover, and rollback.
- [`docs/MIGRATION-TICKETS.md`](docs/MIGRATION-TICKETS.md) — authoritative eight-ticket
  sequence and the bounded contracts for the next two implementation tickets.
- [`docs/DURABLE-STORE.md`](docs/DURABLE-STORE.md) — FR-07 SQLite authority boundary,
  initialization/recovery, offline import and current limitations.
- [`../docs/PLAN.md`](../docs/PLAN.md) — project roadmap and Foundry audit follow-up.

## Tracked layout

```text
foundry/
  .formatter.exs
  mix.exs
  mix.lock
  config/
  lib/pramana_foundry/
    agent_server.ex          — GenServer per agent (launch, timeout, handoff lifecycle)
    coordinator.ex           — central GenServer (state, queue, agent registry, health)
    coordinator/tick.ex      — tick loop (enqueue -> AgentServer start via DynamicSupervisor)
    improver.ex              — self-healing loop (classifiers, proposals, metrics)
    hardening_pm.ex          — PM for IMPRV-* hardening tickets
    system_metrics.ex        — VM and per-process metrics collection
    consolidated_log.ex      — merged view of all three structured logs
    log_store.ex             — fast append-only JSONL writer
    schema.ex                — strict versioned schema validation
    telemetry/telemetry.ex   — structured record validation
    telemetry/store.ex       — deduplicating telemetry append with compaction
    telemetry/observation.ex — duration derivations from phase events
    telemetry/forecast.ex    — confidence-rated duration forecasts
    herdr/                   — typed adapter for the Herdr agent CLI
    effects/                 — checkpointed launch, prompt, and process lifecycle
    board/                   — terminal kanban dashboard
    relocation/              — journaled workspace move
    cutover/                 — Python-supervisor cutover facade
  test/
  roles/
  docs/
    OBSERVABILITY.md
    MIGRATION.md
    MIGRATION-TICKETS.md
  README.md
```

Source, tests, role templates, schemas, migration design, sanitized milestone records, and
pinned dependencies belong in Git. Live state, transcripts, config, caches, logs, releases,
temporary files, worktrees, and provider authentication do not.

The fixed runtime root is `/Users/raymondluong/dev/pramana/foundry/local/`. It is local to
the original project checkout and ignored by Git; it must never be derived from the current
task checkout. Provider credentials stay in provider-owned locations outside that root.

## Runtime dependencies

The coordinator runs a tick/dispatch loop every N seconds. Enable it by setting the
`COORDINATOR_TICK=1` environment variable in the daemon's runtime environment:

```bash
COORDINATOR_TICK=1 _build/prod/rel/pramana_foundry/bin/pramana_foundry daemon
```

Without it, the coordinator starts idle — it serves health probes and admin commands,
but will not dequeue tickets, launch agents, or advance dispatched work. The tick
interval defaults to 15 seconds; configure via `config :pramana_foundry,
poll_seconds: N` before building the release.

Agents run as supervised `AgentServer` GenServers under `PramanaFoundry.AssignmentSupervisor`
(a `DynamicSupervisor` with `:temporary` restart — crashed agents are never automatically
restarted). Each AgentServer manages its own lifecycle: split pane → start agent → prompt
→ await handoff or timeout → cleanup pane. Task crashes are observed via
`DynamicSupervisor` child exit; orphaned Herdr panes are cleaned up in `terminate/2`.
The release does not require Herdr at build time — it resolves the CLI binary at runtime
via PATH or the configured `herdr_command`.

## Configuration

See `config/config.exs`. Key values:

| Key | Default | Notes |
|---|---|---|
| `herdr_command` | `"herdr"` | Path or name of the Herdr CLI |
| `herdr_timeout_ms` | `30_000` | Per-operation timeout for Herdr calls |
| `poll_seconds` | `15` | Tick interval (ignored unless `COORDINATOR_TICK=1`) |
| `max_assignments` | `3` | Max concurrent AgentServer children |
| `max_tasks` | `8` | Max concurrent async tasks (for Improver classifiers) |

## CLI commands

```bash
pramana_foundry validate KIND PATH    # Validate a schema
pramana_foundry shadow PATH            # Shadow an existing checkout
pramana_foundry runtime-root           # Print runtime root path
pramana_foundry health                 # Structured health report (JSON)
pramana_foundry agents                 # List running agents with metrics
pramana_foundry metrics                # System metrics overview
pramana_foundry logs tail N            # Tail consolidated logs
pramana_foundry logs summary           # Log record counts per source
pramana_foundry board                  # Terminal kanban dashboard
pramana_foundry telemetry-status PATH  # Telemetry status projection
pramana_foundry telemetry-export ...   # Export telemetry as JSONL/CSV
```

## Observability

See [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md) for the full reference.

- **Three structured JSONL logs**: coordinator lifecycle, telemetry records, durable events.
- **ConsolidatedLog** merges all three into one time-sorted view.
- **SystemMetrics** captures VM stats, per-process memory/mailbox/reductions, agent child list.
- **Health probe** at `Coordinator.health/0` returns status, queue depth, system metrics.
- **Self-healing Improver** runs every 5 minutes, classifies 14 categories of issues, creates PM proposals for hardening tickets.
- **Token metrics schema** ready for Herdr integration (`prompt_input_tokens`, `output_tokens`, etc.).
