# Harness Engineering — Planning — chapter 4

> Design/research note. Proposed commands and guarantees are not shipped capabilities unless current source and acceptance evidence establish them.
> [Contents](../HARNESS.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## 10. Parallel Track: the Self-Improving Supervisor (Foundry's Own Meta-Harness)

The six tiers above are for the **product** — the retrieval pipeline that users and models
query. There is a second, parallel meta-harness for the **build process**: the Foundry
supervisor that writes code, runs experiments, and maintains Pramana itself.

The Foundry already has foundations the product meta-harness is still waiting for:

| What | Foundry | Umbrella (product) |
|---|---|---|
| Event sourcing | ✅ Coordinator emits checkpoint events before state mutations | ❌ Not yet — planned rearchitecture |
| Event schema | ✅ `event-v1.json` — validated JSONL | ❌ Not yet |
| Event log | ✅ `foundry/local/state/current/events.jsonl` | ❌ Not yet |
| Self-healing loop | ✅ Improver — 14 classifiers, 5-min cycle | ❌ Not yet — H1 planned |
| Hardening PM | ✅ Dedicated GenServer for IMPRV-* tickets | ❌ Not yet |
| Agent lifecycle | ✅ DynamicSupervisor + GenServer per agent | ❌ Not yet — Foundry-only |

**The Foundry IS a domain-specific harness for software engineering over Pramana.** Its
meta-harness progression is about improving the Foundry's own orchestration — not the
retrieval pipeline it manages, but the system that manages the pipeline.

### FL0 — Current state

Everything hand-authored:

- **14 improver classifiers** — static pattern matches with hardcoded thresholds
  (`@crash_threshold 3`, `@launch_failure_rate 0.3`, `@stuck_queue_ms 120000`)
- **Coordinator state machine** — fixed GenServer pattern with hand-coded transitions
- **Agent dispatch** — fixed DynamicSupervisor + GenServer per agent, serial launches
- **Roles** — developer, reviewer, pm — each a static markdown file
- **PM cycle** — fixed 10-minute timer for hardening review
- **Scheduler** — fixed polling interval (15s), fixed ticket queue management

### FL1 — Orchestration parameter search

Search over the Foundry's own tunable parameters:

| parameter | current value | module |
|---|---|---|
| `@crash_threshold` | 3 | Improver |
| `@launch_failure_rate` | 0.3 | Improver |
| `@stuck_queue_ms` | 120000 | Improver |
| `@default_interval_ms` | 300000 (5 min) | Improver |
| `@hardening_interval_ms` | 600000 (10 min) | HardeningPM |
| `poll_ms` (coordinator tick) | 15000 | Coordinator |
| `max_launch_retries` | 3 | Coordinator |
| agent timeout | defaults | AgentServer |
| Herdr timeout | 30000 | Coordinator |

**What changes:** Parameter values only. The orchestration shape is fixed.

**Trigger:** When the Foundry's own efficacy metrics cross a threshold — e.g., ticket
throughput per cycle, agent success rate, proposal acceptance rate.

**Produces:** `mix pramana_foundry.health --diagnose` that recommends parameter changes
based on observed cycle efficiency.

**Risk:** Overfitting to current workload patterns. If the corpus is stable and tickets
are few, the improver may converge to parameters that work well for 3 tickets/week and
break under load. Mitigation: parameters revert to defaults when ticket volume changes
by more than 2×.

### FL2 — Classifier evolution

The 14 classifiers are the improver's core intelligence. When a failure trace does not
match any classifier, the improver currently drops it as noise. FL2 evolves the
classifier set.

**What changes:** The pattern-matching logic in the improver's `classify/1` function. New
classifiers added, existing ones refined, dead ones removed.

**Trigger:** When `UnclassifiedTracesRate` — the share of failure traces matching no
classifier — exceeds a threshold (e.g., 10% of traces in a cycle). Or when a classifier
has consistently produced proposals that were rejected (over-classifying).

**Mutation strategy:** GEPA-style: collect the N unclassified traces, present them with
the current classifier set to a frontier model, and ask for new classifier patterns that
would have caught them. Scored against a held-out trace set: precision (does the new
classifier fire on things it shouldn't?) and recall (does it fire on the traces it was
created for?).

**Who owns output:** The new classifier pattern is reviewed before addition. A classifier
that fires on nothing after N cycles is auto-removed.

**Event:** `ClassifierProposed(fingerprint, pattern, traces_caught, false_positive_rate)`
→ `ClassifierAccepted` or `ClassifierRejected`

**Risk:** Classifier proliferation — adding classifiers for one-off failures degrades the
system's signal/noise ratio. Mitigation: a classifier must catch at least N distinct
traces (not repeats of the same failure) before it is promoted out of probation.

### FL3 — Agent dispatch strategy search

Currently every agent launch creates a GenServer under the DynamicSupervisor with fixed
timeout, retry, and routing. FL3 searches over how agents are dispatched.

**What changes:** The agent launch strategy in `AgentServer.start_link/1` and
`Herdr.Adapter`. Not the agent's behaviour — how agents are launched and managed.

**Search space:**

| strategy | when to try | risk |
|---|---|---|
| Eager launch (spawn all tickets now) | Low load, fast agents | Resource contention |
| Lazy launch (spawn when coordinator tick) | Normal operation | Latency |
| Pooled agents (pre-spawn N agents, assign tickets) | Predictable ticket types | Wasted agents |
| Serial launches (one agent at a time) | Corpus bake — exclusive resource | Throughput floor |
| Priority queuing (high-priority tickets skip queue) | Urgent fixes | Starvation of low priority |

**Trigger:** When ticket throughput drops (more tickets queued than completed per cycle)
or when agent failure rate rises.

**Produces:** `Coordinator.dispatch_strategy()` — the active strategy, which can be
switched at runtime without restarting agents.

### FL4 — Workflow architecture search

The Foundry's own coordination code — the coordinator state machine, the handoff flow,
the integration pipeline. A coding agent rewrites the Foundry's orchestration.

**What changes:** Source code in `foundry/lib/pramana_foundry/coordinator.ex`,
`improver.ex`, `hardening_pm.ex`, `agent_server.ex`. Not the agent behaviour — how the
Foundry manages itself.

**Trigger:** When FL1–FL3 improvements plateau (ticket throughput flat for N cycles
despite active parameter/classifier/dispatch search).

**Search strategy:** A coding agent is given: the current Foundry architecture, the last N
cycle metrics (throughput, proposal acceptance rate, agent success rate, cycle duration),
and the event log. It proposes a concrete architectural change — e.g., "merge the improver
and hardening PM into one cycle to reduce latency between finding and acting", or "replace
the GenServer-based coordinator with a pure Ecto-based projection that doesn't need VM
state".

**Who owns output:** PR review, same as any code change. The changed code must pass the
same tests the current Foundry does. The key safety property: the event log is the source
of truth — a new coordinator that reads from the same log produces the same state, even
if it gets there by a different path.

**Risk:** The coding agent produces a coordinator that works differently and passes tests
but has worse performance under the real workload. Mitigation: the event log supports
replay — the new coordinator is tested against a replay of the last N cycles of live
events before it is deployed. If it processes the replay slower than the current
coordinator, it is rejected.

### FL5 — Online self-healing

The Foundry learns from its own cycles in real-time, adjusting dispatch, classifiers, and
priorities per-cycle without waiting for batch FL2/FL3 experiments.

**What changes:** Runtime adaptation of improver thresholds, dispatch strategy, agent
timeouts, classifier firing order. All within the bounds set by FL1's parameters — FL5
adjusts within the envelope; FL1 adjusts the envelope.

**Trigger:** Every cycle. If the last cycle's agent failure rate was high, the next cycle's
agent timeout is extended. If the last cycle's proposal acceptance rate was low, the next
cycle's classifier confidence threshold is raised.

**Safety:** Bounded adaptation only. Max parameter delta per cycle (e.g., timeout can
increase by at most 20% per cycle). Automatic rollback if the adjustment makes things
worse (measured as proposal acceptance rate dropping after an adjustment).

**Event:** `FoundryOnlineAdaptation(cycle_id, parameter, old, new, delta)` — emitted for
every adjustment, enabling offline analysis of whether the online loop is converging.

**Pramana-specific opportunity:** The improver runs every 5 minutes but the cycle can
complete in under 30 seconds for a small ticket queue. The remaining 4.5 minutes are idle.
An online loop could use that idle time to run low-priority meta-experiments — e.g., test
a new classifier against archived traces without affecting the live cycle.

### FL6 — Meta-Foundry

The improver's improvement logic improves itself. If the improver's proposals have been
declining in acceptance rate (the PM or reviewer rejects more of them), the meta loop
adjusts how the improver formulates proposals — more evidence per finding? shorter
summaries? different severity labels? different role assignment for the proposal review?

**What changes:** The code of the improver's `do_analyze/1` — the loop that reads records,
classifies traces, derives observations, computes forecasts, and creates proposals. The
meta loop rewrites the analysis function itself, not just its parameters.

**Search space:** Analysis strategy, classifier ordering, observation derivation method,
forecast algorithm, proposal formulation template.

**Trigger:** When the improver's own proposal acceptance rate drops below a threshold for
N consecutive cycles. Or when the Foundry's ticket queue has been empty for N cycles
(everything is running smoothly and the improver has nothing to propose — at which point
it should be looking for latent improvements rather than waiting for failures).

**Who owns output:** Human veto power over meta-Foundry changes, because a broken
improver that stops noticing failures is the system's blind spot. The meta loop proposes
a new improver; a human accepts or rejects it. The old improver is retained in the
archive and can be reinstated with one command.

### Relationship to the Product Meta-Harness

The two meta-harness progressions operate on different timescales and feed each other:

| | Product meta-harness (L1–L6) | Foundry meta-harness (FL0–FL6) |
|---|---|---|
| **What it optimises** | Retrieval pipeline — parameters, prompts, architecture | Orchestration — dispatch, classifiers, coordination |
| **Timescale** | Hours per trial (evals run ~30 min) | Minutes per cycle (improver runs every 5 min) |
| **Eval signal** | Gold-set evals, recall@k, chain survival | Cycle metrics: throughput, proposal acceptance, agent success |
| **Event stream** | Umbrella event store (planned) | Foundry `events.jsonl` (exists) |
| **Auto-deploy risk** | Low — guard is architecture-independent | High — a broken coordinator stops all work |
| **First step** | `mix pramana.retrieval.tune` (H5) | `mix pramana_foundry.health --diagnose` (FL1) |

The two converge at L4/FL4 (architectural search): a coding agent that proposes changes
to both the retrieval pipeline AND the orchestration, because a change to one may require
a change to the other (e.g., per-canon retrieval requires the coordinator to dispatch
canon-specific agent types).
