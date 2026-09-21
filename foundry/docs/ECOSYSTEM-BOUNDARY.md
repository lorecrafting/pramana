# Foundry ecosystem boundary and positioning

**Date:** 2026-09-20. **Type:** research synthesis and architecture guidance, not an
implementation inventory, repair-ticket disposition, dependency selection or authorization
to activate execution.

[Foundry strategy](STRATEGY.md) · [Workflow contract](WORKFLOW-CONTRACT.md) ·
[Planning strategies](PLANNING-STRATEGIES.md) ·
[Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md) ·
[AX/Substrate backend](AX-SUBSTRATE.md) ·
[Broader research record](../../docs/strategy/RESEARCH.md)

## Executive conclusion

Recent comparison against Google AX/Agent Substrate, AgentLedger, Restate, Temporal,
Microsoft Agent Governance Toolkit/Agent Control Specification (AGT/ACS), Cedar/OPA,
Tandem and Permission Protocol mostly **confirms the existing Foundry direction rather
than overturning it**.

The ecosystem is converging on a common split:

- probabilistic models, planners and workflow strategies propose work;
- a deterministic runtime or policy boundary decides what is admitted;
- consequential external effects need explicit lifecycle and retry semantics;
- durable evidence must be distinguishable from model claims and UI projections;
- execution, isolation, policy evaluation and presentation can be supplied by replaceable
  infrastructure.

Foundry should therefore remain a **workflow-agnostic authority/evidence/acceptance kernel
for model-directed work**, not expand into a comprehensive agent framework, generic
workflow platform, policy language, container runtime, trace backend or model router.

The durable product boundary is the contract, not ownership of every mechanism underneath
it.

> **External systems may execute, evaluate, isolate, observe or present
> Foundry-governed work; none may independently create authoritative Foundry facts.**

That rule should govern future integration choices.

## The irreducible Foundry responsibility

The protected kernel should own only facts whose correctness cannot safely depend on an
agent, planner, harness, external workflow runtime or UI believing its own story.

### 1. Admitted intent and durable identity

Foundry owns the exact admitted objective/work definition, revisions and immutable
identities needed to distinguish one assignment, execution, artifact and decision from
another. A process ID, pane, model session, ticket label or workflow-engine invocation ID
may be useful evidence, but is not authoritative identity by itself.

### 2. Authority lineage and capability grants

Foundry owns principals, assignment lineage, capability grants, revocation generations and
the rule that delegation cannot expand authority. A child/sub-workflow may receive the
same or less delegable authority than its parent, never authority merely because a prompt
or project file requested it.

The useful invariant is:

```text
child capability <= parent delegable capability <= operator/project policy
```

Role names remain project/workflow concepts; the protected ontology should not hard-code
PM/developer/reviewer as universal roles.

### 3. Budgets, reservations and consequential effects

Foundry owns durable resource allocation and the lifecycle of side effects that can matter
outside an agent's transient process. Unknown outcomes are first-class states.

A crash or lost acknowledgement after an external operation must never collapse into
"probably failed; retry." Foundry must preserve enough claim, request identity and receipt
state to reconcile the outcome before another effect is permitted when duplication could
be unsafe.

### 4. Exact artifact and evidence binding

Foundry owns the mapping from a claim such as "tests passed" or "review approved" to the
exact candidate/artifact and exact evidence that supports it. Logs, traces, model output,
session transcripts and provider status are evidence inputs with explicit strength; they
do not become acceptance merely by being recorded.

### 5. Independent acceptance and promotion

Foundry owns the predicates that decide whether evidence is sufficient for acceptance,
whether required review is independent of the maker, and whether an exact artifact may be
integrated, published, deployed or activated.

A model saying "done", an external runtime saying "completed", or a CI job exiting zero
does not by itself establish the higher-level acceptance fact.

### 6. Canonical acknowledged state and replay semantics

Foundry should keep one authoritative durable store/reducer boundary for its domain facts.
External runtimes can maintain their own execution journals, but those journals must be
treated as execution evidence/substrate state rather than a competing authority for
Foundry budgets, grants, evidence binding or acceptance.

### 7. Conformance of replaceable components

Foundry should own versioned behavioral contracts for components on which protected
decisions rely. Substitution should be earned through common hostile/conformance fixtures,
not through feature-list similarity or adapter presence.

The desirable direction is a small family of contracts such as:

```text
HarnessAdapter
ExecutionBackend
PolicyProvider
EffectAdapter
ReceiptExporter
```

These are architecture seams, not authorization to create five new services or a new
repair backlog. Existing repair ownership remains unchanged.

## What Foundry should deliberately not become

Foundry's differentiation does **not** require it to own:

- a universal planning algorithm, agent graph or workflow DSL;
- a coding-agent harness when Pi/Jido.Harness or future systems satisfy the required
  execution/observation contract;
- a generic durable-workflow engine if a mature engine satisfies the same failure
  semantics at lower total maintenance cost;
- a policy language or enterprise IAM product;
- a container/micro-VM implementation;
- an observability backend;
- a general model gateway/router;
- a terminal/session presentation system;
- a generic RAG/memory system.

Those components may be important. They are replaceable infrastructure around the trusted
boundary.

## Comparative findings

### Google AX + Agent Substrate: preferred distributed execution candidate, not authority

The 2026-09-21 [focused review](AX-SUBSTRATE.md) checked AX at
`d8ed0fe38bceb7842d3c47817d53d16ccdfcb601` and Agent Substrate at
`bb0effed188e06a44e03862cb6ea993e58f86893`. AX's September 20 rewrite is materially
different from its earlier harness-centric shape: it now exposes a small declarative
`Task`/`Workspace`/`Gateway`/`Model` control plane, stores high-churn task state in
Redis, distributes reconciliation through Redis Streams and delegates sandbox execution to
Agent Substrate. Substrate in turn owns the actor/worker split, suspend/resume, snapshots,
sandbox classes and actor-aware routing on top of Kubernetes.

That division is unusually compatible with the intended `ExecutionBackend` seam:

```text
Foundry authority/evidence/acceptance
                |
                v
         AX ExecutionBackend
                |
                v
        Agent Substrate
                |
                v
          Kubernetes
```

The current implementation is not yet acceptable as a trusted Foundry boundary by default.
The inspected AX reconciler falls back to `*:443` when no Gateway is supplied and
continues after an egress-policy application failure; the default runner does not feed
child-command exit into authoritative Task completion; workspace Git materialization is
branch/ref-oriented rather than an explicit immutable Foundry source identity; and
model-assisted workspace bootstrap can fail while the runner continues. Schema presence
also cannot be treated as enforcement without conformance proof.

**Position:** prefer AX over direct Substrate as the first distributed execution experiment,
because bypassing AX would make Foundry rebuild workload resources and reconciliation that
AX now exists to provide. Keep a direct Substrate adapter as an escape hatch only when a
demonstrated requirement cannot be satisfied through AX. In either path, Foundry remains
the sole authority for grants, budgets, exact source/evidence binding, completion meaning,
acceptance and promotion.

### AgentLedger: closest design peer; mine the semantics, do not depend on it yet

[AgentLedger](https://github.com/yaogdu/AgentLedger) is the closest current conceptual
peer to Foundry's lower execution/evidence layer. At pinned main revision
`dd966e3b3d9eb54032c51701d30efcfbaa2379b0`, its documented scope principle explicitly
keeps planning/workflow engines outside the core while the runtime owns durable execution,
governed tool use, evidence/replay, policy hooks, leases/fencing, cancellation, budgets,
attribution and conformance.

Useful mechanisms to compare or adopt as design pressure:

- managed tool effects use idempotency keys rather than relying on prompt discipline;
- uncertain effects enter an explicit pending-verification state instead of being blindly
  retried;
- leases/fencing prevent stale workers from committing after ownership changes;
- evidence bundles separate event history, final state, approvals, artifacts and tool
  effect records;
- a stable contract/conformance layer is treated as more important than any one storage,
  sandbox or framework adapter.

This supports Foundry's own direction around claims, receipts, reservations and replay.
The specific lesson is not "copy AgentLedger's tables"; it is to make Foundry's
unknown-effect and adapter-conformance semantics at least as explicit.

**Position:** design comparator and adversarial/conformance reference. Do not put the
trusted Foundry kernel on it today without proving project maturity, operational behavior,
upgrade burden and exact semantic equivalence.

### Restate: strongest durable-execution substitution candidate

[Restate](https://github.com/restatedev/restate) provides durable workflows, stateful
actors/state machines, replay, reliable calls, timers/signals and operational
introspection. Its current main repository lists official SDKs for TypeScript,
Java/Kotlin, Python, Go and Rust, but not Elixir. The server is licensed under BUSL-1.1
with an additional-use grant and later conversion to Apache-2.0; that licensing posture
must be considered in any product dependency decision.

Restate is therefore interesting primarily as a possible implementation of the
**ExecutionBackend** responsibility:

```text
Foundry authority/evidence/acceptance
                |
        admitted execution
                v
         ExecutionBackend
          /           \
     native OTP     Restate?
```

Restate must not become a second authority store. Its invocation/journal state can answer
questions such as "this execution is suspended/resumed/completed"; Foundry must still
decide what that observation means for claims, budgets, evidence, acceptance and
promotion.

**Position:** run a bounded substitution experiment before building large new durable
execution machinery. Keep the native OTP path as the reference until Restate proves lower
total complexity and correct failure semantics.

### Temporal: mature durable-execution control comparison

[Temporal](https://github.com/temporalio/temporal) is a mature MIT-licensed durable
execution platform. Its architecture is explicitly event-sourced: deterministic workflow
code emits commands, the service persists resulting event history, and replay recreates
workflow state after failure. Temporal currently documents official SDKs for .NET, Go,
Java, PHP, Python, Ruby, Rust and TypeScript, not Elixir.

Temporal is valuable even if Foundry never adopts it because it is a strong control for
any "we need to build durable execution ourselves" claim.

**Position:** benchmark beside Restate on the same Foundry cases. Do not infer that mature
durable workflow semantics automatically supply Foundry's authority, exact evidence
binding or independent acceptance semantics.

### Microsoft AGT/ACS: strong policy/conformance ideas, not the authority ledger

At pinned main revision
`e7f5d2bafca79e508e80a8cd7e0a6f0bb05ce197`, Microsoft's
[Agent Governance Toolkit](https://github.com/microsoft/agent-governance-toolkit) contains
formal governance specifications and conformance suites. Its Agent Control Specification
(ACS) is especially relevant: it defines a stateless, deterministic, fail-closed policy
runtime. The host supplies a complete snapshot; ACS returns a normalized verdict; the
host performs enforcement.

That is an excellent shape for a future Foundry **PolicyProvider** boundary:

```text
Foundry authoritative snapshot
             |
             v
     PolicyProvider.evaluate
             |
     allow / deny / gate
             |
             v
Foundry records + enforces
```

Other useful ideas to preserve:

- RFC-2119-style normative contracts backed by conformance suites;
- explicit delegation/identity lineage;
- canonical identities for exact policy inputs;
- tamper-evident/Merkle-style exported audit evidence;
- redacted telemetry distinct from full audit/evidence storage.

Caution: dynamic trust scores or privilege-ring abstractions may be useful risk signals,
but must never mint Foundry authority. Explicit grants, lineage and policy remain the
source of permission.

**Position:** borrow contract discipline and consider ACS as an optional policy adapter
after the protected interface is stable. Do not replace Foundry's durable authority,
budget, effect or acceptance ledger with AGT.

### Cedar and OPA: bounded stateless authorization providers

[Cedar](https://docs.cedarpolicy.com/) models authorization around principal, action,
resource and context and now documents patterns for agents acting on behalf of users.
[OPA](https://www.openpolicyagent.org/docs) accepts structured input and evaluates general
policy-as-code.

Both are plausible implementations behind a narrow PolicyProvider interface. Neither
should own state that changes the meaning of a later Foundry decision unless that state is
first represented as a durable Foundry input/revision.

**Position:** preserve an adapter seam; keep the built-in evaluator until actual policy
complexity justifies another dependency.

### Tandem: product-level convergence and competitor, not a dependency

[Tandem](https://tandem.ac/) explicitly positions itself as an authority runtime in which
the model proposes work and the runtime decides what can run. Its current documentation
covers durable runs, scoped tools, approvals, artifacts, event/checkpoint/snapshot
separation, uncertain-effect recovery and audit evidence. Its engine/governance
components are open-core/source-available under BUSL-1.1 with commercial production
licensing requirements.

The conceptual convergence is useful validation:

- an event is not automatically complete current state;
- an artifact is not automatically promoted/trusted knowledge;
- a snapshot is not permission to repeat an effect;
- approval is a distinct authority event;
- runtime execution state and governance evidence should not be flattened into one
  generic "memory" abstraction.

**Position:** monitor as a competitor/design comparator. Do not integrate its governance
engine into Foundry; doing so would create overlapping product authority and licensing
coupling without solving a missing primitive that cannot be exposed through a narrower
contract.

### Permission Protocol: future receipt interoperability, not current core dependency

The
[Permission Protocol Governance Framework](https://github.com/permission-protocol/governance-framework),
at pinned revision `3ea8533a18bc72233ecdcfc38c9c35d96f64478f`, is currently
a 0.1 draft/RFC. Its core idea is an immutable authority receipt recording who authorized
an action, what was authorized, why, when and what happened. It explicitly leaves agent
orchestration out of scope.

That vocabulary aligns well with Foundry's receipts and evidence model, but the
specification is still young and its formal API/receipt schemas are planned rather than a
stable compatibility target.

**Position:** keep Foundry's internal receipt data rich enough to export to emerging
interoperability formats later. Do not let an external receipt schema constrain the
protected domain before it stabilizes.

## One-authority rule for all substitutions

The most important integration failure mode is **dual truth**.

Restate, Temporal, Tandem, AgentLedger and similar systems each maintain durable execution
state. Foundry also maintains durable authority state. That is acceptable only when the
boundary is explicit:

```text
external runtime state
        |
        | observation / receipt
        v
Foundry protected decision
        |
        v
Foundry authoritative fact
```

Never:

```text
external runtime says completed
        |
        v
accepted = true
```

without the Foundry decision that binds the exact identity, evidence and acceptance
predicate.

The same applies to policy engines and observability:

- OPA/Cedar/ACS verdicts are policy inputs/results; Foundry records and enforces their
  admitted meaning.
- OpenTelemetry traces are operational observations; they do not replace receipts.
- harness/model usage reports are evidence; they do not mint budgets or acceptance.
- sandbox/container success establishes process-level facts; it does not prove task-level
  correctness.

## Substitution contracts and conformance

A future external component should be adopted only through a versioned contract with
failure-focused tests.

### ExecutionBackend conformance

At minimum test:

- crash before start;
- crash after start but before acknowledgement;
- lost completion acknowledgement;
- duplicate dispatch;
- stale/zombie worker after ownership transfer;
- cancellation before start and during execution;
- durable wait and resume;
- code/runtime upgrade while work is suspended;
- unknown external-effect outcome;
- restart after process/host failure;
- high concurrency with bounded backpressure.

Measure correctness first, then operator effort, latency, resource cost, integration LOC,
upgrade burden and observability quality.

### PolicyProvider conformance

At minimum test:

- identical inputs produce identical decisions;
- malformed/unknown policy fails closed;
- missing authoritative context fails closed;
- policy revision and exact evaluated input are attributable;
- provider cannot mutate protected state directly;
- approval/escalation cannot silently become permission;
- adapter failure cannot fall back to a more permissive path.

### HarnessAdapter conformance

At minimum preserve:

- exact execution/session identity;
- provider/model/config identity where available;
- lifecycle and cancellation semantics;
- token/cache/cost evidence without inventing unavailable precision;
- bounded tool surface and isolation assumptions;
- restart/reconciliation semantics;
- no credential or paid-fallback route outside admitted policy.

### EffectAdapter conformance

At minimum preserve:

- stable request identity/idempotency key;
- pre-effect claim/reservation;
- exact receipt or explicit unknown outcome;
- no unsafe automatic retry of unknown effects;
- reconciliation;
- actor/assignment/capability binding;
- evidence sufficient to distinguish requested, attempted and actually effected.

## Language/runtime posture

This research does not create a reason to rewrite Foundry wholesale in Rust.

The BEAM/OTP runtime remains unusually well matched to the control-plane work Foundry does:
many supervised long-lived processes, waits, signals, failures, cancellations and
coordination around slow external systems. The authority semantics should remain pure and
deterministic regardless of the hosting mechanism.

Rust is a strong candidate for **small hardened boundaries** when the gain is concrete:

- OS sandbox/launcher and process-isolation helpers;
- credential/network brokers;
- canonical serialization, hashing and signature verification;
- possibly a small portable authority-core library after the semantic contract stabilizes.

Do not introduce a Rust/Elixir boundary merely for aesthetic type safety while the
authority model is still changing. A separate Rust process and versioned IPC protocol is
preferable to an in-VM native extension for hostile-code isolation because it creates a
real fault/security boundary.

## Resulting product position

Foundry's defensible position is not "the best agent framework" or "the best workflow
engine."

It is:

> **A small trusted execution-governance kernel that turns probabilistic model-directed
> work into bounded, attributable, replayable and independently acceptable outcomes,
> while allowing the planner, model, harness, execution runtime, sandbox, policy engine
> and presentation layer to evolve independently.**

That gives Foundry two related roles:

1. **authority kernel** — preserve the invariants that decide who may do what, what
   happened, what evidence supports it and what may become accepted;
2. **experimentation kernel** — hold those invariants stable while comparing workflow
   strategies, models, harnesses, policies, tool surfaces and execution backends by
   accepted-outcome correctness, effort, latency and cost.

The second role depends on the first. If experimental infrastructure is allowed to change
the rules of authority/evidence/acceptance, the measurements stop being comparable.

## Immediate consequence for the current repository

No repair ticket, production route or dependency should change merely because of this
research.

The present action is architectural discipline:

- preserve the existing one-store/one-reducer authority boundary;
- finish the current repair path before broad generalization;
- express new infrastructure through narrow substitutable contracts;
- compare unknown-effect semantics and conformance practice against AgentLedger/AGT;
- benchmark Restate/Temporal before growing custom durable-execution machinery;
- keep Cedar/OPA/ACS optional and stateless relative to Foundry authority;
- treat Tandem as a competitor/design comparator;
- keep receipts exportable enough for future interoperability such as Permission
  Protocol;
- retain Elixir/OTP as the control plane unless measured evidence justifies a narrower
  component rewrite.

This is convergence, not a change of thesis.
