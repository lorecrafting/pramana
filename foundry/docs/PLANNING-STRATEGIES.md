# Replaceable planning strategies and human work projections

**Date:** 2026-09-20. **Status:** post-repair strategy/design guidance. This document
does not alter the active repair plan, workflow contract, launch policy, provider
entitlement, repair ordering or current runtime behavior.

[Foundry strategy](STRATEGY.md) · [Workflow contract](WORKFLOW-CONTRACT.md) ·
[Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md) ·
[Observability](OBSERVABILITY.md)

## 1. Thesis: preserve invariants, experiment with methodologies

Foundry should become a trusted experimental governance kernel for model-directed work.
The protected core should preserve the facts that must remain dependable while allowing
the intelligence and workflow layers above it to change aggressively.

That separation should let Foundry compare, for representative task classes:

- planning/workflow strategies;
- model, provider, reasoning and execution profiles;
- harnesses and agent runtimes;
- context-selection and compaction policies;
- tool surfaces and execution backends;
- role/reviewer topology;
- concurrency and scheduling policies;
- correction, escalation and stopping strategies.

The comparison target is not activity. It is independently accepted useful work and the
whole cost of producing it: correctness/acceptance, operator effort, rework, latency,
tokens/context, provider-reported cost where available, failure/recovery burden and
Foundry maintenance.

This is a direction, not a current capability claim. Live agent lifecycle telemetry is
not yet a coherent end-to-end pipeline, automatic provider execution remains gated, the
active runtime is still software-role-specific, and the complete repaired lifecycle has
not yet been proved. The owning repair tickets remain authoritative.

## 2. Kernel invariants versus replaceable methodology

Foundry should preserve **invariants, not methodologies**.

| Stable kernel concern | Replaceable strategy above the kernel |
|---|---|
| admitted objective/policy identity | vertical slices, goal graphs, blackboards, dynamic DAGs |
| principal/assignment identity | PM, shaper, researcher, builder or temporary role labels |
| bounded capability grants | which roles/tools a planner proposes |
| budget/reservation conservation | allocation heuristics and concurrency strategy |
| exact effect claims and receipts | task ordering and orchestration method |
| unknown-outcome reconciliation | retry/replanning policy |
| exact artifact/evidence binding | implementation methodology |
| reviewer-independence predicates | reviewer topology/model choice |
| protected acceptance/promotion | planner completion claims |
| durable replay/recovery | human-facing board or planning UI |

A new workflow idea should normally change the planner, planning artifact, project profile,
context policy or projection. It should not require a new protected state machine unless
the experiment demonstrates a genuinely new authority/evidence invariant.

This is also a design test: if replacing the planning methodology requires invasive
changes to the authority ledger, the boundary is probably too coupled.

## 3. Generic planning contract

The permanent contract should not be “the PM creates work slices.” It should be:

> A planning role transforms an admitted objective plus current evidence into a versioned
> proposal for bounded work, decisions and plan amendments. Foundry validates and admits
> the effects of that proposal under protected policy.

Conceptually, a planning revision may carry:

```text
PlanRevision
  strategy_id / strategy_version
  objective/spec identity
  planner artifact
  proposed bounded work
  dependency/resource requests
  capability requests
  evidence/acceptance intent
  unresolved decisions
  evidence references
  superseded revision
```

The strategy-specific planner artifact is deliberately opaque to the protected kernel
except for bounded fields that the kernel genuinely must validate. A future strategy must
not require a migration merely because its internal planning representation differs.

For example:

```text
strategy = vertical-slices/v1
```

may later become:

```text
strategy = adaptive-goal-graph/v3
```

while both ultimately propose bounded assignments, dependencies, capabilities, budgets
and evidence obligations through the same admission boundary.

## 4. PM / Shaper responsibility

The current software workflow may continue to call the planning role `pm`. Conceptually,
the useful responsibility is closer to **PM / Shaper** than to a status-moving project
manager.

A PM/Shaper may:

- interpret an admitted objective and current evidence;
- choose a planning strategy permitted for that objective/project;
- identify coherent outcomes or other useful planning units;
- expose important unknowns before implementation;
- propose bounded tickets/assignments and dependencies;
- propose role/capability/context needs;
- propose allocation within an already authorized envelope;
- revise the plan when new evidence invalidates an assumption;
- park, split, amend or reprioritize future work;
- identify the next operator decision when authority or product judgment is required;
- propose that work appears complete.

It may not:

- mint authority, capability or budget;
- rewrite acknowledged history;
- turn an unknown effect into success;
- weaken mandatory checks or independence requirements;
- establish its own evidence claims as receipts;
- accept, integrate, publish or deploy merely by asserting completion.

In compact form:

```text
PM/Shaper proposes the plan.
Workers execute bounded work.
Reviewers independently challenge candidates.
Foundry governs authority, evidence and acceptance.
```

## 5. Vertical work slices: useful strategy, not ontology

A promising present strategy is to shape human-recognizable **vertical work slices**.
A slice describes a domain outcome that is meaningful from a distance and may contain
many machine-level tickets.

Example:

```text
Slice: subscription-safe Pi execution

Outcome:
  A real Foundry assignment can execute through Pi using an authorized subscription
  route, survive interruption/reconnection, produce an evidence-bound candidate and
  reach independent review.

Underlying work:
  characterize auth
  implement adapter
  cancellation/reconnect
  usage/billing evidence
  conformance tests
  integration fixture
```

This is preferable to making the operator track six unrelated “Working” cards. The
operator steers the recognizable outcome while Foundry may parallelize bounded work
beneath it.

But **work slice is not a protected authority object**. Do not add slice-specific budget,
acceptance, effect or lifecycle tables merely to support this representation. A slice can
be a versioned planning/projection identifier that groups already-authoritative objective,
spec, ticket, evidence and outcome identities.

If vertical slices later prove inferior, replace them.

Candidate alternatives include:

- capability/goal lattices;
- dynamically expanded task DAGs;
- blackboard planning;
- uncertainty/frontier-driven planning;
- repeated next-best-action planning with no persistent slice tree;
- domain-specific workflow representations.

The protected contract should survive each substitution.

## 6. Human WIP is different from agent concurrency

For an agent factory, “limit WIP” should initially mean **limit human cognitive WIP**,
not “allow only N agents to run.”

A useful initial policy may be:

```text
human-visible active outcomes: 1-2
machine work within them: bounded by resource/capability/budget policy
```

One human-facing slice could contain several developers, researchers, checks and reviewers.
That can preserve operator focus without sacrificing safe machine parallelism.

Treat this as planning policy first, not a kernel invariant. If measured evidence later
shows that a slice-level WIP ceiling deserves enforcement, it may be promoted through
normal reviewed policy rather than being baked into the core from anecdote.

## 7. Human work projections, not another source of truth

The current ticket/status board remains useful as an operational and diagnostic view. It
should not be the only human interface to work-in-progress.

The higher-level abstraction should be a replaceable **Human Work Projection** derived
from authoritative state plus the current planning artifact.

One possible vertical-slice projection:

```text
Subscription-safe Pi execution

GOAL
  A bounded task executes through Pi without unauthorized paid usage.

CURRENT STATE
  Adapter path works in fixture environment.
  Production launch remains fail-closed.

EVIDENCE
  execution-contract fixture
  cancellation fixture
  artifact identity receipt

OPEN UNKNOWNS
  Can the selected route prove subscription-only behavior?

NEXT DECISION
  none / operator decision description

NEXT ACTION
  run route-attestation probe

UNDERNEATH
  4 assignments, 2 workers, 1 reviewer
```

Another future projection could instead show goals, decision frontiers or only operator
attention requests. The UI should not require slices as its permanent schema.

A desirable operator view may eventually answer:

```text
What is Foundry making true?
What changed?
What evidence exists?
What remains uncertain?
What needs me?
What will Foundry do next without me?
```

## 8. Continuity Capsule for handoff and resumption

Agent handoffs fail when a receiving agent must reconstruct state from transcripts,
status labels or an undifferentiated issue history. Provide a compact, replaceable
**Continuity Capsule** derived from current acknowledged state and evidence.

Conceptual fields:

```text
objective/spec/plan identity
planning strategy/revision
current state
delta since prior capsule
evidence refs
open unknowns
remaining risks
next decision + decision owner
next executable action
blocked-on refs
fresh-as-of event/revision
```

A capsule is context, not authority. It must link to exact evidence rather than replacing
it. It cannot mint a receipt, erase an unresolved failure or authorize a transition.
If a capsule is poor or stale, discard and regenerate it.

This makes resumption context intentionally smaller than a full transcript while retaining
a route to the underlying facts.

## 9. Foundry as an experimentation kernel

The stable kernel makes controlled workflow experimentation possible only if experiments
hold the governing contract fixed enough to make comparisons meaningful.

Examples of independent variables:

| Dimension | Example alternatives |
|---|---|
| planning | vertical slices vs goal graph vs next-best-action |
| model | different permitted model/reasoning profiles |
| harness | direct Pi RPC vs normalized harness adapter |
| context | broad bootstrap vs routed/retrieved context |
| tools | shell-heavy vs typed domain APIs |
| review | one strong reviewer vs staged specialist/adversarial review |
| concurrency | sequential vs bounded parallel |
| correction | immediate developer correction vs fresh-attempt replanning |
| stopping | fixed plan vs evidence-driven stop/escalation |

Useful dependent measures include:

- independently accepted outcomes by comparable task class;
- first-pass acceptance and defect escape;
- correction/review cycles and failed-work tax;
- operator steering/review/recovery/maintenance effort;
- wall-clock and queue latency;
- input/cache/output/reasoning tokens and context-window use;
- provider-reported monetary cost when trustworthy and available;
- tool-result/context bytes admitted to models;
- restart/recovery/unknown-effect burden;
- harness/Foundry maintenance overhead.

Never optimize one number in isolation. Fewer tokens with more rework, weaker evidence or
greater operator attention can be a regression.

Planning-strategy comparisons should use declared task classes, pinned relevant
configuration, the same protected acceptance boundary and a predeclared observation
window. Avoid claiming one strategy is generally superior from a few unmatched tasks.

## 10. Reorientation and context-switch tax

Foundry's observability should eventually measure the cost of resuming or switching work,
not just request token totals.

Candidate measurements:

- handoff/resume to first productive effect latency;
- model requests before the first productive effect;
- input tokens/context bytes consumed reconstructing prior state;
- repeated source/tool reads after handoff;
- repeated questions whose answer already exists in attributable evidence;
- stale-context failures;
- context compaction/retrieval overhead;
- operator minutes spent reconstructing “where are we?”;
- simultaneous human-visible planning units;
- correction/rework attributable to lost handoff context.

These observations belong in the canonical telemetry/analytics model with planning
strategy/revision as experimental dimensions. They do not become authority facts.

## 11. Sequencing and repair boundary

Do **not** reopen the current kernel repair merely to implement work slices, continuity
capsules or a new human projection.

The repair already provides or is building the required substrate: objectives/spec
revisions, PM proposals, common admission, bounded assignments, durable identity,
capabilities, budgets, receipts, evidence, review, acceptance and recovery.

Keep the active repair sequence authoritative. In particular:

1. finish the repaired lifecycle and its durable PM/admission path;
2. finish normalized end-to-end observations and accepted-outcome lineage;
3. prove the complete software lifecycle under the owning gates;
4. then add one planning/projection strategy as a post-repair experiment;
5. compare it against a baseline before promoting any heuristic to durable policy.

Do not add `WorkSlice` authority tables, a slice state machine, a second backlog or a
Turing-complete planning DSL as a shortcut.

The intended architectural property is stronger:

> Better workflow ideas should mostly replace planning intelligence and projections,
> while the trusted authority/evidence kernel remains stable.

That is the basis for Foundry becoming a system that can improve not only the code it
produces, but the way it organizes and performs work.
