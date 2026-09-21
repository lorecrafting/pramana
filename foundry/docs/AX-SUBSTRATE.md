# AX + Agent Substrate as a Foundry execution backend

**Date:** 2026-09-21. **Type:** architecture research and bounded integration proposal, not
dependency adoption, repair-ticket reprioritization, production authorization or evidence that
AX/Agent Substrate satisfy Foundry conformance.

[Foundry strategy](STRATEGY.md) · [Ecosystem boundary](ECOSYSTEM-BOUNDARY.md) ·
[Workflow contract](WORKFLOW-CONTRACT.md) · [Observability](OBSERVABILITY.md) ·
[Broader research register](../../docs/strategy/RESEARCH.md)

## Source snapshot

This note was checked against:

- Google AX at pinned revision
  [`d8ed0fe38bceb7842d3c47817d53d16ccdfcb601`](https://github.com/google/ax/tree/d8ed0fe38bceb7842d3c47817d53d16ccdfcb601),
  including its 2026-09-20 architecture rewrite at
  [`dc4f36cdba647f110b34fd69adf31eb2bec37ca3`](https://github.com/google/ax/commit/dc4f36cdba647f110b34fd69adf31eb2bec37ca3);
- Agent Substrate at pinned revision
  [`bb0effed188e06a44e03862cb6ea993e58f86893`](https://github.com/agent-substrate/substrate/tree/bb0effed188e06a44e03862cb6ea993e58f86893).

Both projects are moving quickly. Recheck their contracts at any implementation decision; a
link or adapter written against these revisions is not evidence of future compatibility.

## Executive decision

The new AX architecture materially strengthens the case for treating Google's stack as a
future Foundry execution substrate, but it does **not** change Foundry's product boundary.

The preferred architecture is:

```text
Foundry
  authority / admission / budgets / workflow / evidence / acceptance
        |
        v
AX
  declarative agent-workload control plane
  Task / Workspace / Gateway / Model
        |
        v
Agent Substrate
  actor lifecycle / scheduling / snapshots / sandbox / routing
        |
        v
Kubernetes
  machine / pod / worker-pool infrastructure
```

Foundry should remain the authority/evidence/acceptance kernel. AX may become the preferred
distributed `ExecutionBackend` implementation. Agent Substrate is the lower-level actor
runtime AX uses and should normally remain behind AX rather than becoming another control
plane that Foundry reimplements around directly.

The durable rule is:

> **AX/Substrate may establish execution facts. Only Foundry may turn admitted execution
> facts and evidence into authoritative Foundry completion, budget, acceptance or promotion
> facts.**

This is a refinement of the existing ecosystem boundary, not a new kernel architecture.

## Why the September AX rewrite matters

AX's 2026-09-20 rewrite changes its architectural role.

The previous project mixed a CLI and embedded agent harness. The current design is a
general-purpose orchestration layer with:

- a stateless gRPC `ax-server`;
- Redis resource state, indexes, PubSub and task-event streams;
- horizontally scalable `ax-controller` reconcilers consuming Redis Streams;
- a replaceable `ax-task-runner` contract inside each sandbox;
- Agent Substrate as the actual actor/sandbox execution runtime.

AX deliberately keeps its task primitive small. Its current concepts document says an
agent may plan, delegate, retry or fan out above AX, while AX supplies cheap isolated tasks
that can be created, suspended, resumed and discarded. That is much closer to Foundry's
desired boundary than an agent framework that also wants to own planning, approval and
workflow truth.

The four current AX resource concepts are also a useful fit:

| AX resource | Infrastructure role | Foundry interpretation |
|---|---|---|
| `Task` | isolated execution request/lifecycle | one admitted execution attempt, never acceptance itself |
| `Workspace` | materialize repositories, MCP and skills | execution environment whose exact source identity must still be verified |
| `Gateway` | task listener/egress policy | compiled capability-derived network boundary |
| `Model` | named provider/model config for AX components | optional infrastructure config; never Foundry model authority by itself |

AX should therefore be evaluated as infrastructure below Foundry, not as a replacement for
Foundry's PM/planning, budgeting, evidence or acceptance logic.

## Why Agent Substrate is the deeper infrastructure bet

Agent Substrate addresses a different problem from Foundry and from AX: how to run very
large populations of stateful, mostly-idle workloads without binding one physical Pod to
every logical agent.

Its core abstraction separates a long-lived **Actor** from the physical **Worker** currently
executing it. Actors can be suspended, snapshotted and later resumed on an available worker.
The current project supports gVisor and microVM sandbox classes, worker pools, actor-aware
routing, snapshot transfer and lifecycle operations including create, resume, pause, suspend,
revert and delete.

That division is valuable for Foundry because it can avoid owning machinery such as:

- worker scheduling and multiplexing;
- gVisor/microVM lifecycle;
- process and filesystem snapshot movement;
- warm-worker pools;
- actor migration;
- actor-aware ingress/egress routing;
- node-level execution daemons;
- low-level checkpoint/restore performance engineering.

Foundry should specify the security, capability, resource and evidence requirements for an
execution. It should not build a competing sandbox scheduler merely because it needs those
requirements enforced.

## The responsibility split

A future integration should preserve the following ownership table.

| Concern | Foundry | AX | Agent Substrate |
|---|---:|---:|---:|
| objective/work definition | authoritative | no | no |
| principal/assignment lineage | authoritative | execution labels only | no |
| CapabilityGrant | authoritative | compiled projection only | enforcement substrate |
| budget reservation/accounting | authoritative | usage observation only | infrastructure usage only |
| workflow/planning strategy | authoritative admission of proposals | deliberately out of scope | out of scope |
| exact source/candidate identity | authoritative | materialization input/status | durable filesystem only |
| task queue/reconciliation | domain scheduling | infrastructure reconciliation | actor scheduling |
| sandbox/runtime image | policy/profile selects | Task/runner declaration | executes |
| CPU/RAM isolation | required profile | declaration/projection | enforcement |
| egress policy | capability-derived requirement | Gateway projection | enforcement |
| suspend/resume | domain intent/record | Task API | actor lifecycle |
| snapshot/checkpoint | receipt/observation | orchestration | implementation |
| process exit | required execution evidence | currently incomplete | process/runtime fact |
| model/tool telemetry | canonical observation ingestion | optional observation | infrastructure observation |
| correctness checks | authoritative evidence requirements | no | no |
| independent review | authoritative | no | no |
| acceptance/promotion | authoritative | never | never |

The same model/harness may run inside multiple backends. AX/Substrate must not become a
hidden second ontology for developer/reviewer/PM roles or work-slice planning.

## Preferred backend shape

Do not couple Foundry domain modules directly to AX protobufs or Substrate actors. Preserve
a narrow versioned boundary:

```text
Foundry.ExecutionBackend
        |
        +-- LocalLinuxBackend
        |
        +-- AxBackend             preferred distributed experiment
        |      |
        |      +-- AX control plane
        |              |
        |              +-- Agent Substrate
        |
        +-- SubstrateBackend?     optional research/escape hatch
```

The direct Substrate path should exist only if AX prevents a required Foundry semantic or
creates materially worse operational behavior. Bypassing AX by default would make Foundry
rebuild task resources, desired-state reconciliation, workspace declarations, task watches
and other control-plane machinery that AX now exists to provide.

A minimal future `ExecutionBackend` contract should cover behavior, not vendor types:

```text
prepare(admitted_execution) -> prepared_handle | refusal
launch(prepared_handle) -> execution_handle | known_non_start | unknown
observe(execution_handle) -> observations
signal(execution_handle, signal) -> receipt | unknown
suspend(execution_handle) -> receipt | unknown
resume(execution_handle) -> receipt | unknown
cancel(execution_handle) -> receipt | unknown
collect(execution_handle) -> completion/evidence observations
destroy(execution_handle) -> cleanup receipt | unknown
reconcile(execution_handle) -> current external facts
```

The existing FR-06 R1-R5 authority, ownership, reservation and replay semantics remain above
this boundary. Backend implementation may not weaken them.

## Current AX gaps that matter to Foundry

AX is promising infrastructure, but the inspected revision is not yet a trusted Foundry
backend without a strict adapter/runner and conformance work.

### 1. AX `Running` is not task completion

The default `ax-task-runner` supervises the task command, records its exit locally and
intentionally remains alive after that command exits so the sandbox stays inspectable.
The runner exposes an `OnCommandExit` hook, but the current control plane does not consume
that child exit into authoritative Task completion state.

Therefore:

```text
AX actor running       != work progressing
AX workspace ready     != command completed
AX command exit 0      != Foundry acceptance
```

A Foundry runner/adapter must return an attributable process-completion receipt tied to the
exact execution identity. Lost acknowledgement remains an explicit reconciliation case.

### 2. Current AX Gateway behavior is not fail-closed enough

In the inspected reconciler, absence of an explicit Gateway falls back to `*:443`.
More importantly, an egress-policy application error records `GatewayReady=False` but
continues toward actor execution.

That cannot be the governed Foundry path.

For a protected execution:

```text
CapabilityGrant
      |
      v
compiled Gateway / substrate policy
      |
      v
verified applied generation
      |
      +-- unknown / failed -> REFUSE OR REMAIN BLOCKED
      |
      +-- verified         -> launch may proceed
```

No permissive fallback is acceptable. Backend unavailability must not silently broaden
network access.

### 3. Workspace Git identity is mutable by default

The current AX `GitRepo` schema records repository, branch, directory and depth. The
runner fetches the requested branch/ref and checks out `FETCH_HEAD`; it does not expose a
dedicated immutable commit/tree field in the inspected schema.

That is convenient environment setup, not sufficient Foundry provenance.

Governed execution needs a verified chain such as:

```text
admitted repository identity
+ required immutable revision/tree
+ checkout/materialization observation
+ independently verified loaded identity
= source-binding receipt
```

A branch label alone cannot establish what source was executed.

### 4. Natural-language workspace bootstrap is not authoritative setup

AX can attach a plain-language `goal` to a workspace and let an Antigravity bootstrap
agent install/prepare the environment. The current implementation logs and continues when
that bootstrap is unavailable or fails.

That is useful for exploratory tasks. It should be disabled or treated as non-authoritative
for protected Foundry execution.

Governed runs should prefer pinned runner images, deterministic setup, immutable source and
explicit tool inventories. If a model-assisted bootstrap is ever admitted, its effects must
be bounded, attributable and separately verified.

### 5. Resource and policy-looking schema fields must not be assumed enforced

The AX proto contains CPU/memory request/limit types, `UsageStats` and
`PendingApproval`. In the inspected control path, task-specific ActorTemplate construction
passes image/environment/runner state into Substrate but does not yet project the Task
`ResourceReqs` into the constructed ActorTemplate. Searches also did not find an
end-to-end current implementation populating the usage/approval status fields.

Foundry must test behavior, not trust schema presence. A declared field that is not enforced
is unavailable capability, not partial success.

### 6. Credential materialization needs a stricter Foundry path

The inspected AX reconciler resolves `GEMINI_API_KEY` from a Kubernetes secret and adds
the resulting value to the environment used to construct the task's Substrate
ActorTemplate. That is workable for AX's current bootstrap path, but a governed Foundry
execution should not assume that copying a long-lived provider secret into template
environment state satisfies credential custody.

Prefer scoped/short-lived credentials or a brokered route whose grant, generation and
revocation remain attributable to the Foundry execution. A backend adapter must prove that
unrelated bootstrap, debug and extension processes cannot read a credential merely because
they share the actor.

### 7. Failed reconciliation and queue recovery need explicit proof

The inspected AX controller acknowledges each Redis task event after processing even when
`processEvent` returns an error, intentionally preventing a bad task from wedging the
queue. That means Foundry must not infer a durable retry merely from AX's queue use.

The Redis subscription uses `XREADGROUP` for new entries and leaves unacknowledged entries
pending when a consumer disappears. At the inspected revision, the subscription code does
not itself show pending-entry reclaim logic such as an explicit claim/autoclaim path.
The comments say abandoned entries remain claimable; a Foundry integration must prove the
actual controller-death/recovery behavior rather than relying on that comment.

Backend reconciliation therefore needs a Foundry-visible distinction between known
terminal infrastructure failure, retryable non-start, unknown execution state and
successfully reconciled execution. Retry policy stays above AX.

### 8. AX/Agent Substrate are high-churn dependencies

AX still identifies its API as `v1alpha1` and warns that core concepts/protocols may break
before a stable release. Agent Substrate is also evolving rapidly, including current work
on lifecycle, authorization, networking and observability.

Therefore the integration should pin exact revisions and force upstream changes through a
backend conformance suite. Upstream churn must break the adapter test, not mutate Foundry's
protected semantics.

## Foundry AX runner

The safest integration point is a small Foundry-specific runner image rather than teaching
the Foundry kernel about AX internals.

Conceptually:

```text
AX Task
  image: foundry-ax-runner@sha256:...
  workspace: admitted material
  gateway: compiled capability projection
        |
        v
Foundry AX runner
  1. validate execution envelope
  2. verify immutable source/candidate identity
  3. construct allowed harness environment
  4. launch Pi/Jido/other admitted harness
  5. emit lifecycle + model/tool observations
  6. record exact child exit and produced artifacts
  7. expose completion receipt to Foundry
  8. remain reconcilable until Foundry settles the attempt
```

The runner is still untrusted relative to Foundry acceptance. Its signed/typed output is
evidence to verify and bind, not permission to accept itself.

The runner must not receive Foundry root authority, budget-minting authority or credentials
outside the admitted execution profile.

## Credential and tool posture

Do not copy broad provider credentials into a generic workspace merely because AX can put
environment variables into a task template.

A governed backend should preserve the current Foundry direction:

- principal/assignment-specific capability;
- minimum credential scope;
- explicit model/provider route;
- bounded MCP/tool endpoints;
- no automatic paid-provider fallback;
- no credentials exposed to unrelated bootstrap or extension processes;
- revocation/generation changes reconciled before further effects.

AX Gateway and Substrate network controls are enforcement mechanisms beneath this policy,
not the policy source.

## Observability integration

Agent Substrate is particularly interesting because it already uses OpenTelemetry-oriented
actor identity and lifecycle instrumentation. Foundry should correlate that infrastructure
telemetry rather than invent a parallel low-level worker telemetry stack.

A desired trace relationship is:

```text
Foundry objective
  -> admitted assignment
     -> attempt
        -> execution_id
           -> AX task identity
              -> Substrate actor UID
                 -> resume / ready
                 -> harness + model/tool activity
                 -> checkpoint / pause / suspend
                 -> cleanup
```

Useful measurements include:

- queue/reconcile latency;
- actor resume latency;
- active versus suspended time;
- checkpoint/restore duration and bytes where available;
- worker-pool pressure;
- sandbox class;
- process runtime and exit;
- model tokens/cache/context/cost;
- tool execution;
- retry/correction tax;
- review effort;
- accepted outcome.

High-cardinality execution/actor identifiers belong in traces/logs and Foundry's canonical
observation records, not metric labels merely because Substrate exposes them.

OpenTelemetry remains correlation/export infrastructure. It does not replace Foundry's
receipts, budget ledger or evidence store.

## Conformance additions for AX/Substrate

In addition to the general `ExecutionBackend` cases in
[ECOSYSTEM-BOUNDARY.md](ECOSYSTEM-BOUNDARY.md), an AX experiment should explicitly prove:

1. missing Gateway refuses before command execution;
2. Gateway application failure refuses rather than running permissively;
3. egress to an ungranted destination is denied from the actual sandbox;
4. admitted immutable revision equals the revision actually loaded;
5. workspace/bootstrap failure cannot be reported as successful setup;
6. actual child exit is attributable and survives lost completion acknowledgement;
7. suspend/resume preserves required workspace state without replaying completed external
   effects;
8. stale actor/worker identity cannot settle a newer Foundry execution;
9. cancel during harness/tool activity terminates the whole admitted process subtree;
10. declared CPU/RAM limits are actually enforced, not merely serialized;
11. debug/SSH guest services remain disabled unless explicitly admitted;
12. no provider/model/tool credential is available outside its grant;
13. AX/Redis/controller restart does not duplicate an unsafe Foundry effect;
14. Substrate actor migration preserves correlation but does not change authority identity;
15. upstream version change fails a pinned compatibility test until reviewed;
16. provider credentials are not persisted or exposed beyond the admitted principal/tool
    boundary merely because an ActorTemplate carries environment state;
17. controller death with an unacknowledged Redis event is recovered or reconciled without
    silently losing work, while reconciliation errors cannot trigger unbounded or duplicate
    execution.

The experiment should include fault injection, not only a happy-path demo.

## Adoption sequence

This research does **not** create a new repair dependency. Finish the current repair and
FR-22 acceptance path under its existing authority.

After a suitable bounded experiment is authorized:

### A0 — Contract-only spike

- define/confirm the vendor-neutral `ExecutionBackend` behavior;
- map current local execution onto it without changing authority;
- define AX/Substrate identity fields as external observations;
- add no production AX dependency.

### A1 — Local AX/Substrate lab

- pin exact AX/Substrate revisions;
- deploy an isolated non-production cluster;
- build the Foundry AX runner;
- run deterministic fixtures with no paid provider required;
- prove network/source/completion/cancel/suspend/reconcile failure cases.

### A2 — Harness integration

- run the selected Pi/Jido harness inside the same runner/profile;
- preserve FR-09/15a provider/subscription controls;
- correlate model/tool usage with AX/Substrate lifecycle telemetry;
- compare against the existing local backend on identical task classes.

### A3 — Decision gate

Compare:

- accepted-outcome correctness;
- failed/retried/corrected work;
- operator/recovery effort;
- total token/provider/infrastructure cost;
- latency;
- isolation strength;
- integration LOC;
- upgrade/churn burden;
- observability quality;
- portability and rollback.

Only then decide whether AX becomes the preferred distributed backend.

### A4 — Optional direct-Substrate experiment

Attempt only if AX blocks a demonstrated requirement. Keep the same backend conformance
suite. Do not bypass AX merely to access a lower-level API.

## What this does not authorize

This note does not:

- add AX, Redis, Kubernetes or Agent Substrate as production dependencies;
- rewrite Foundry around Kubernetes or Go;
- replace BEAM/OTP as the authority/control-plane implementation;
- move budgets, grants, workflow state, receipts or acceptance into AX;
- declare AX/Substrate production-ready for Foundry;
- replace Pi/Jido/other harness evaluation;
- permit model-driven workspace bootstrap for protected work;
- permit permissive network defaults;
- alter FR-06, FR-09, FR-15a, FR-18, FR-22 or other current repair acceptance;
- claim Google's project provenance predicts ecosystem adoption.

The Kubernetes analogy is useful as strategic attention, not as evidence. The correct bet
is **adapter compatibility and measurement**, not surrendering Foundry's kernel boundary.

## Resulting architecture principle

The most useful formulation is:

> **Foundry governs autonomous work; AX reconciles agent workloads; Agent Substrate runs
> stateful actors; Kubernetes supplies physical cluster infrastructure.**

If AX/Substrate succeeds broadly, Foundry should benefit from that success because the
commodity execution layer becomes better while Foundry remains focused on the harder
cross-backend questions: what was allowed, what actually happened, what it cost, what
evidence supports it and whether the result may be accepted.
