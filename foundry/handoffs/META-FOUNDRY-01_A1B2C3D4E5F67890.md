# Handoff: Foundry Meta-Harness (FL0 → FL6)

**For the session hardening the event sourcing infrastructure.** You built the Foundry's
coordinator, improver, PM, and event log. This handoff describes how to turn the
Foundry into a **self-improving supervisor** — a meta-harness that optimises its own
orchestration, not just the retrieval pipeline it manages.

Read `docs/HARNESS.md` §10 for the full design. This handoff gives you the concrete
steps in dependency order.

---

## Current state (FL0)

You have all of this working:

| Component | What it does | Where parameters are hardcoded |
|---|---|---|
| **Coordinator** | State machine, event-sourced via Checkpoint | `poll_ms 15000`, `max_launch_retries 3` |
| **Improver** | 14 classifiers, 5-min cycle | `@crash_threshold 3`, `@launch_failure_rate 0.3`, `@stuck_queue_ms 120000` |
| **HardeningPM** | Dedicated PM for IMPRV-* tickets | `@default_interval_ms 600000` |
| **EventLog** | `append(path, event)` — fsynced JSONL | Path config only |
| **Schema** | `event-v1.json` validation | Fixed |
| **AgentServer** | GenServer per agent lifecycle | Timeout defaults |
| **Scheduler** | Queue polling | `poll_ms` from coordinator |

Your event sourcing is *already working* — the coordinator emits checkpoint events before
every state mutation. This is ahead of the umbrella product, which has no event sourcing
yet.

### The problem FL1 exists for

Every threshold was set once and never re-derived. Three examples from the event log:

1. **`@crash_threshold 3`** — an agent that crashes 3 times in a window triggers
   hardening. If your agents crash 0 times per week, this threshold has never been
   exercised and may be too lax or too tight. The improver should know that.

2. **`@stuck_queue_ms 120000`** — tickets queued for 2+ minutes are flagged. On a
   machine where a full gate takes 34 minutes, 2 minutes may flag tickets that are
   legitimately waiting for the database. Hardening PM then proposes tickets for a
   queue that is working normally.

3. **`@launch_failure_rate 0.3`** — 30% of agent launches failing triggers analysis.
   If most failures are the same root cause (e.g., Postgres pool exhaustion), the
   classifier should hit once and the threshold should tighten for repeat offences.

You can verify all three by reading `events.jsonl` with `jq`:

```bash
# crash rate by agent type
jq 'select(.event == "ticket_enqueued") | .attributes.ticket.task_id' \
  foundry/local/state/current/events.jsonl | sort | uniq -c | sort -rn

# queue times
jq 'select(.event == "handoff_received") | .at' \
  foundry/local/state/current/events.jsonl | head -5
```

---

## Tier FL1 — Orchestration Parameter Search

**The minimal meta-harness for the Foundry.** Equivalent to H5 in the product plan.

### Step 1: Parameter registry

Create `PramanaFoundry.Parameters` — a single module that declares every tunable
parameter, its current value, valid range, and last-measured date. This is the
consolidated snapshot function (same pattern as `Pramana.Retrieval.snapshot/0` in H5).

```elixir
defmodule PramanaFoundry.Parameters do
  use PramanaFoundry.Parameter, type: :integer

  defparameter crash_threshold: [default: 3, min: 1, max: 10,
    description: "Agent crashes in a window before improver flags"]

  defparameter launch_failure_rate: [default: 0.3, min: 0.0, max: 1.0,
    description: "Fraction of agent launches that fail before flagging"]

  defparameter stuck_queue_ms: [default: 120_000, min: 10_000, max: 600_000,
    description: "Tickets queued longer than this (ms) are flagged"]

  defparameter improver_interval_ms: [default: 300_000, min: 60_000, max: 3_600_000]
  defparameter hardening_interval_ms: [default: 600_000, min: 60_000, max: 3_600_000]
  defparameter coordinator_poll_ms: [default: 15_000, min: 5_000, max: 60_000]
  defparameter max_launch_retries: [default: 3, min: 0, max: 10]

  def snapshot, do: ... # returns current values as map
end
```

**Why a registry instead of module attributes:** Module attributes (`@crash_threshold 3`)
are compiled in and require a recompile to change. The whole point of a meta-harness is
to change parameters without recompiling. The registry reads from Ecto, a config file, or
an Agent — anywhere that can change at runtime.

**Recommendation:** Start with an Ecto-backed registry (`pramana_foundry_parameters`
table). It lives in the same database as the coordinator's state and can be queried,
audited, and rolled back by the same mechanism. The table is 8 rows and costs nothing.

### Step 2: Cycle metrics

The improver already reads telemetry and the event log. Add a `mix pramana_foundry.health`
diagnose mode that returns:

```
Last 10 cycles:
  Throughput: 3.2 tickets/cycle (σ=1.1)
  Proposal acceptance rate: 67% (12/18)
  Agent success rate: 88% (22/25)
  Cycle duration: 28s (σ=12s)
  Unclassified traces: 2/47 (4.3%)
```

This tells you whether the Foundry is *improving* (acceptance rate rising, cycle duration
falling) or *stagnating*. The meta-harness steers on these numbers.

### Step 3: Diagnosis recommendation

The minimal meta-harness: `mix pramana_foundry.health --diagnose` reads the cycle metrics
and flags stale parameters alongside the proposal they suggest changing:

```
WARNING: crash_threshold (3) has not been tested in 14 cycles — 0 crashes observed.
  Consider tightening to 2 to detect issues earlier.
  Run: mix pramana_foundry.parameter.set crash_threshold 2

WARNING: stuck_queue_ms (120000) flags 67% of tickets as "stuck" on this machine.
  Average queue time: 85s. Consider raising to 180000.
```

**Human-in-the-loop — always.** The meta-harness proposes; a person accepts. Auto-deploy
at this tier would change parameters that were chosen for a different workload and
degrade performance silently.

### Acceptance criteria for FL1

- `mix pramana_foundry.health` reports cycle throughput, acceptance rate, success rate
- `mix pramana_foundry.health --diagnose` flags at least 2 parameters with evidence from
  the event log
- A parameter change is applied via `mix pramana_foundry.parameter.set` and the improver
  reads the new value on the next cycle (no recompile)
- The change is reversible: `mix pramana_foundry.parameter.set crash_threshold 3` restores
  the default

---

## Tier FL2 — Classifier Evolution

The 14 classifiers in the improver are static pattern matches. They were written from
experience but have never been validated against a held-out trace set. FL2 evolves them.

### What the event log already records

Every improver cycle writes a finding to `findings.jsonl`. Each finding has a
`classifier` field naming which of the 14 classifiers fired, or `nil` if none matched.
You already have the data to answer: which classifiers fire most? Which produce proposals
that get accepted?

```
jq 'select(.classifier != null) | .classifier' \
  foundry/local/state/current/findings.jsonl | sort | uniq -c | sort -rn
```

### Step 1: Track unclassified traces

Findings with `classifier: nil` are currently dropped as noise. Add a
`unclassified_traces` counter to the improver's metrics. When this exceeds a threshold
(10% of traces in a cycle), the improver writes a `classifier_gap` event to the event
log with the unclassified traces attached.

### Step 2: Propose new classifiers

The `classifier_gap` event triggers: collect the N unclassified traces, present them
with the current classifier set to a frontier model, and ask for new classifier patterns
that would have caught them.

**The pattern template:**

```elixir
%{
  fingerprint: "AGENT_TIMEOUT_ON_CORPUS_LOCK",  # unique, stable identifier
  match_fn: :agent_timeout_on_corpus_lock?,       # function ref in improver
  description: "Agent timed out waiting for corpus lock",
  severity: :medium,                              # :low, :medium, :high, :critical
  produces: :hardening_ticket,                    # :hardening_ticket, :warn, :log_only
  evidence_fields: [:agent_id, :timeout_s, :lock_type]
}
```

The frontier model writes new `%{}` proposals. A human reviews them and adds the
`match_fn` implementation to the improver. The new classifier starts in **probation**
— it fires and logs findings but does not produce hardening tickets until it has caught
≥3 distinct traces (not repeats of the same trace).

### Step 3: Validate classifier precision

A classifier that fires on everything is worse than no classifier. Add a per-classifier
false-positive counter: if a classifier's finding was reviewed and the proposed PM ticket
was rejected because the finding was wrong, increment that classifier's false-positive
count. Auto-remove classifiers with `false_positive_rate > 0.5` after N cycles.

### Acceptance criteria for FL2

- `mix pramana_foundry.improver.classifiers` lists all 14 + any added, with hit count,
  false-positive rate, and probation status
- A gap detection adds 1+ new classifiers from real unclassified traces
- A classifier that over-fires (>50% false positive) is auto-removed
- The improver's `classify/1` reads classifiers from the parameter registry, not
  hardcoded module functions — so a new classifier can be added without recompiling

---

## Tier FL3 — Agent Dispatch Strategy Search

Currently every agent is launched under the DynamicSupervisor with the same strategy.
FL3 searches over launch strategies.

### The strategies to implement

| Strategy | Module | When to use |
|---|---|---|
| **Eager** | Spawn all tickets immediately | Low queue depth (< 5), fast agents |
| **Lazy** | Spawn on next coordinator tick | Normal operation — default |
| **Pooled** | Pre-spawn N agents, assign tickets | Predictable ticket mix (always a dev + reviewer) |
| **Priority** | High-priority tickets skip the queue | Urgent regressions |
| **Serial** | One agent at a time | Exclusive resource (corpus bake) |

### Step 1: Strategy registry

`PramanaFoundry.Dispatch.Strategy` — a behaviour with `launch/2` callback. Each strategy
implements the behaviour. The coordinator calls `Strategy.launch(ticket, opts)` instead
of directly starting a GenServer.

```elixir
defmodule PramanaFoundry.Dispatch.Strategy.Eager do
  @behaviour PramanaFoundry.Dispatch.Strategy

  def launch(ticket, opts) do
    # spawn under DynamicSupervisor immediately
    DynamicSupervisor.start_child(PramanaFoundry.AgentSupervisor,
      {PramanaFoundry.AgentServer, [ticket: ticket, opts: opts]})
  end
end
```

### Step 2: Strategy selector

An Ecto-backed config (`dispatch_strategy`) that the coordinator reads at every tick.
Can be changed at runtime:

```
mix pramana_foundry.dispatch.set --strategy pooled --pool-size 3
```

### Step 3: Auto-selector

The coordinator tracks tick-to-completion latency per strategy. After N ticks on each
strategy (minimum sample), it reports which strategy had the lowest average latency and
highest throughput. It does not auto-switch — it recommends.

### Acceptance criteria for FL3

- 3+ dispatch strategies implemented and switchable at runtime
- `mix pramana_foundry.dispatch.set --strategy pooled` takes effect on the next tick
- The coordinator logs which strategy was used per tick in the event log
- `mix pramana_foundry.dispatch.report` shows latency/throughput per strategy

---

## Tier FL4 — Workflow Architecture Search

The Foundry's own coordination code becomes the thing being searched over. A coding
agent (the same model that writes retrieval code) is given: the current Foundry
architecture, metrics from FL1, classifier data from FL2, dispatch data from FL3. It
proposes an architectural change.

### What to have ready for the coding agent

Before this tier is attempted, the Foundry needs:

1. **Event log replay capability** — `mix pramana_foundry.replay --cycles 50` runs the
   coordinator's state machine over the last 50 cycles of events and reports the final
   state. This is what lets a new coordinator architecture be validated against real
   events before deployment. (This may already exist — the coordinator is event-sourced.)

2. **A sandbox** — `mix pramana_foundry.sandbox` starts a coordinator on a different
   port/path with its own event log, so the coding agent's proposal can be tested
   without touching the live Foundry.

3. **A regression test suite** — the existing 235 tests, plus a replay-based test that
   asserts the new architecture produces the same state as the current one for the last
   50 cycles of live events.

### Candidate architectural changes for the agent to consider

| Change | What it would do | Why try it |
|---|---|---|
| Merge improver + hardening PM | One cycle, one loop | Reduce latency between finding and acting |
| Pure Ecto coordinator | No GenServer — projection from events | Crash recovery without VM state |
| Event-driven PM | PM wakes on event, not timer | Respond faster to urgent tickets |
| Dynamic classifier loading | Classifiers as Ecto rows, not module functions | Add/remove classifiers without compile |

### Safety

The key property: **the event log is the source of truth.** A new coordinator that reads
the same events must produce the same state, even if it gets there by a different code
path. The replay test proves this. If the replay test passes, deployment is safe — the
live coordinator is swapped for the new one, which reads the same event log from the
same starting point.

---

## Tiers FL5 and FL6 — Further Out

**FL5 (online self-healing)** closes the loop: adjustments made per-cycle without waiting
for batch experiments. This needs FL1–FL3 to be stable first — you need to know the
baseline cycle metrics before you can detect that an online adjustment helped or hurt.

**FL6 (meta-Foundry)** is where the improver's own improvement logic improves itself.
This is the right tier to stop planning and start measuring: wait until you have at
least 3 months of FL1–FL5 data before attempting it. The data will tell you whether
the improver's proposal acceptance rate is improving on its own or plateauing.

---

## Implementation order

```
Week 1-2   FL1: Parameter registry + health --diagnose
Week 3-4   FL2: Unclassified trace tracking + first classifier evolution
Week 5-6   FL3: Dispatch strategies (eager, lazy, pooled)
Week 7-8   FL4: Event log replay + sandbox
Week 9-12  FL4: First architectural change proposal
Month 4+   FL5: Online adaptation loop
Month 6+   FL6: Meta-Foundry (based on data, not schedule)
```

**FL1 can start immediately.** The parameter registry and `mix pramana_foundry.health
--diagnose` read the existing event log and improver data. No new infrastructure needed.

---

## Risks to watch

1. **The improver's own proposals degrade the system.** A bad classifier produces a bad
   hardening ticket. The ticket is assigned, an agent implements it, the change lands.
   This is the meta-harness's own invariant: *the system must not worsen itself.*
   Mitigation: every FL2 classifier starts in probation (log-only, no tickets). Every
   FL1 parameter change is reviewed before applying. The replay test protects FL4.

2. **Metric drift.** If the cycle metrics (throughput, acceptance rate) are the only
   signal the meta-harness steers on, and the Foundry's workload changes gradually, the
   metrics can drift to a new normal that looks good but is actually degraded compared
   to what the old parameters achieved. Mitigation: the `health --diagnose` output
   always shows the trend arrow (↑↓→) and the delta from 4 weeks ago, not just the
   current value.

3. **Meta-overfit to the current ticket mix.** The Foundry currently handles a specific
   mix of ticket types (feature work, hardening, corpus maintenance). If the meta-harness
   optimises for this mix, it will perform poorly when the mix changes (e.g., a new
   canon acquisition floods the queue with ingest tickets). Mitigation: per-ticket-type
   metrics, not just aggregate.

---

## References

- `docs/HARNESS.md` §10 — full Foundry meta-harness design
- `docs/PLAN.md` § "Deferred — after event sourcing rearchitecture" — product-level plan
- `foundry/lib/pramana_foundry/improver.ex` — the 14 classifiers and the analysis loop
- `foundry/lib/pramana_foundry/coordinator.ex` — event-sourced state machine
- `foundry/lib/pramana_foundry/hardening_pm.ex` — IMPRV-* ticket PM
- `foundry/lib/pramana_foundry/event_log.ex` — append-only event writer
- `foundry/lib/pramana_foundry/schema.ex` — event-v1 validation
- `foundry/local/state/current/events.jsonl` — live event data