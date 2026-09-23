# Replaceable planning strategies and human work projections

**Date:** 2026-09-20. **Updated:** 2026-09-22 for LLM-proposed workflows and analytics.
**Status:** post-repair strategy/design guidance. This document
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

“Opaque” does not mean trusted or executable. If retained, the artifact is bounded,
content-addressed/contextual data under the applicable size, schema and retention rules.
It cannot install controller code, select a weaker protected policy, broaden a grant or
turn a strategy identifier into an admission bypass. Only the normalized proposal fields
accepted by the governing command/policy path may drive protected effects.

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

### 3.1 LLM-first planning and progressive commitment

The product is **LLM-proposed, Foundry-validated work**, not a workflow language that
replaces planning intelligence. A model may use prose, a goal graph, next-best-action
planning, an external controller's representation or a reusable template. Normalize only
consequential proposal fields needed by the accepted semantic protocol. The model's
private reasoning is not a required artifact or observation.

One bounded next-step proposal is valid; a complete upfront graph is not required. Later
evidence can justify another proposal or amendment. Already specified work should skip a
redundant planning-model call. The proposal/admission interface should be equally useful
to a deterministic controller, a human and an adaptive model.

Keep three layers distinct: protected authority/evidence/effects in Core; replaceable
controller scheduling/composition; and useful project/domain work. A small sequence,
bounded-parallel, handoff, gate, correction or durable-wait vocabulary may help the
Standard Controller, but is not a mandatory language for external controllers. A new
primitive needs demonstrated workload value, not speculation. No universal DAG schema,
role taxonomy or generic protected `advance()` operation follows from this direction.

### 3.2 Authoring ergonomics without a new authority plane

Start with a thin adapter over accepted operations and a machine-readable, versioned
catalog: input/output types, prerequisites, explicit outcomes, requested capabilities,
resource bounds, evidence requirements, retry/reconciliation behavior and valid/invalid
examples. Distinguish installed, compatible, permitted and actually granted. Discovery
must neither reveal protected configuration nor grant power. Reuse schemas and generate
docs/examples from shared definitions where practical, with drift checks.

The authoring loop is discover -> propose -> validate -> exercise isolated scenarios ->
repair from structured diagnostics -> inspect semantic diff -> submit for admission.
Diagnostics identify the exact step/path, violated requirement and relevant identities.
Reusable fragments are ordinary compositions, not privileged shortcuts. An unsupported
operation produces a missing-capability/escalation proposal, not an installed adapter.

Validate references and typed candidate/result flow, bounded nested expansion, declared
resource conflicts, supported controller versions and protected requirements. A lab must
exercise the real controller/Core interfaces or demonstrate explicit conformance; a toy
simulator does not certify production. A preflight pass is never an admission token.
Runtime authorization, isolation and evidence checks remain necessary at every relevant
boundary, including routes a hostile controller might invoke directly.

### 3.3 Safe dynamic replanning

Distinguish disposable thinking changes, scheduling within existing authority, and changes
to consequential admitted commitments. Only the last requires renewed protected admission;
policy may allow it automatically inside an existing envelope without an operator click
for every step. Admission still checks current policy, resources and exact revisions.

An amendment names the expected current revision, exact proposed change and affected
future work. Reject stale/concurrent amendments and durably record the admitted revision
before effects use it. Specify the safe transition point and what continues, drains,
cancels or blocks. Preserve issued effects, unknown reservations, consumed budget,
candidate/evidence bindings and the applicability of late results. Default template edits
affect future runs, not existing execution. A semantic diff must expose changed powers,
limits, effects, evidence/reviewer requirements and configuration, including unchanged gates.

Renaming steps, creating children or revising a plan must not replenish budget or reset a
hard correction allowance. Replay consumes recorded decisions/results, not new model calls.
Re-execution need not reproduce stochastic model output. Rolling back future configuration
does not undo completed external effects or erase acknowledged history.

### 3.4 State exactly which guarantees are enforced

For each claimed hard property, name its enforcement point and acceptance evidence.
Capabilities, conserved budgets, exact evidence, mandatory independence and unknown-effect
handling depend on the protected issuance/transition path and the accepted isolation and
recovery contracts. A controller-level `correction(max=2)` is only a strategy preference
unless issuance enforces that allowance across revisions, retries and descendants.
Unsupported enforcement must be reported as unsupported, not inferred from syntax.

Likewise, checking declared write scopes does not prove arbitrary worker code race-free.
Use actual resource/sandbox/integration contracts. Neither prompts nor hidden tool lists
are enforcement. Foundry does not guarantee optimal plans, correct arbitrary work, perfect
semantic reviews or completion despite an unavailable dependency. These limits belong in
both authoring diagnostics and the guarantee/enforcement/evidence matrix in issue #47.

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
it. It cannot mint a receipt, erase an unresolved failure, authorize a transition or
grant permission merely because it names a “next action.” The receiving assignment must
still be independently admitted and capability-checked. If a capsule is poor or stale,
discard and regenerate it.

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

### 9.1 Observability by construction and reproducible questions

Supported controller operations should emit versioned observations automatically; model
prompts should not be responsible for remembering instrumentation. Correlate strategy and
workflow revision/amendment, component/controller versions, step definition and invocation,
parent/dependency/join, timing/wait reason and candidate/check/review relationships with
Foundry identities. These are post-repair analytical dimensions, not new FR-18 authority
objects. Dynamic planning needs an attributable execution history, not a full upfront DAG.

Natural-language question -> permitted structured query -> deterministic calculation ->
evidence-linked explanation. Return query/metric versions, filters, cohort and denominators,
snapshot/cutoff, coverage/source/quality and bounded drill-down to contributing records.
Enforce read scope, redaction and query limits; no unrestricted SQL, executable model query
code or default prompt-body retention. Unsupported questions and expired source evidence
produce explicit limitations, not invented totals. Reproduce numbers without the LLM.

Separate queue, active work, deterministic/external waits, review/correction and measured
human effort. Summed parallel worker time is not elapsed time. Derive an observed critical
path only from supported dependencies/timing and flag missing edges, clock uncertainty
and unfinished work. An observed association is not proof of causal benefit from reordering.
Model-inferred labels such as productive work retain their definition and uncertainty.

Include failed, retried, cancelled, corrected and unfinished work; define the zero-accepted
case honestly. Preserve provider-native total/cache/reasoning semantics and avoid duplicate
session/request accounting. Unknown usage is not zero. Test duplicate/conflicting/late
observations, replay ingestion and retention/compaction. Essential local accounting must
survive disabled or sampled trace export; OTel is an optional sink, not the dataset owner.

### 9.2 Governed optimization rather than self-approved metrics

The loop is observation -> explicit hypothesis -> exact workflow diff -> validator/lab ->
separately admitted bounded experiment -> independent evaluation -> ordinary adoption.
Begin with one concrete change, such as cheap checks before expensive review. Declare the
baseline, comparable cohort, varied configurations, acceptance requirements, observation
window and stop rules. Prefer controlled assignment where feasible; otherwise disclose
confounding and report an observational result. Sparse data may mean insufficient evidence.
Recorded review findings and later defect escapes are quality evidence distinct from time
and acceptance counts. An optimizer cannot rewrite its cohort, metric or judge to win.

Default adoption affects future runs. Active-run changes use section 3.3, preserving spent
budget, outstanding effects and exact candidate/evidence identity. Adoption and rollback
remain ordinary protected transitions, not telemetry-driven authority. Continuous
observation need not mean continuous LLM calls: use deterministic meaningful-event/cohort
triggers, deduplicated findings and finite analysis/experiment budgets. Include collection,
storage, querying, analysis-model consumption and operator effort in net-benefit accounting.

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

### Tracked delivery and handoff

[Issue #47](https://github.com/lorecrafting/pramana/issues/47) owns the post-repair thin
proposal/catalog surface, structured validation/lab, safe amendments, automatic controller
instrumentation and software/typed-content portability proof. Start with next-step work;
add reusable composition only when needed. Its instrumentation contract feeds
[issue #48](https://github.com/lorecrafting/pramana/issues/48), which owns reproducible
workflow queries, observed critical paths and bounded workflow-reshaping experiments.
Their detailed acceptance checklists are in the issues, not duplicated here. Both remain
open when this planning change merges; no feature is implemented by this document.

Both runtime tracks require G0/FR-22, the I-F3 software baseline and their accepted
interfaces, under [I-F3/I-F5](../../docs/strategy/ROADMAP.md). One bounded improvement runs
at a time. No active FR ticket depends on these post-repair implementations.

Issue #48's documentation-only A0 slice tracks the outstanding coordinated ownership
amendment for observability convergence steps 6/7: board/status to FR-18B, canonical
Improver consumption and existing model/context/tool efficiency validation to FR-20,
with FR-19B retention preserved and optional export not becoming a hard prerequisite.
That mapping must land in both relevant repair sections and the observability route
before it is treated as governing. This strategy does not silently change FR obligations
or claim that the handoff is already repaired. Broader workflow analytics remains #48.

The intended architectural property is stronger:

> Better workflow ideas should mostly replace planning intelligence and projections,
> while the trusted authority/evidence kernel remains stable.

That is the basis for Foundry becoming a system that can improve not only the code it
produces, but the way it organizes and performs work.
