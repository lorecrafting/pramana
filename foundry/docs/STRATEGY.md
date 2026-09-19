# Foundry strategy brief

**Date:** 2026-09-18. **Type:** investment direction and design guidance, not an
implementation inventory or authorization to execute. Records the operator's
Foundry-first investment direction, the model-directed-work vision and the lessons from
FirstMate, Pi, OMP and no-mistakes. External capabilities below are source observations
at pinned revisions, not comparative performance measurements or certification on the
operator's machine.

[Documentation index](README.md) · [Repair plan](REPAIR-PLAN.md) ·
[Workflow contract](WORKFLOW-CONTRACT.md) ·
[Broader product strategy](../../docs/strategy/FOUNDRY.md)

## Working summary

Build a trusted execution and governance kernel for model-directed work, not another
comprehensive coding harness or a permanently hard-coded agent graph. Models may propose
task decomposition, roles, workflow shape, context, tools, checks and corrections.
Foundry owns admitted intent, identities, capability grants, durable acknowledged state,
budgets, external-effect control, evidence, acceptance, recovery and controlled
self-improvement.

Retain the standalone Elixir/OTP project, OMP as the current harness and Herdr as
initial optional presentation. A stronger model, different harness, accessible API or
new backend may improve planning without gaining spending, acceptance or deployment
authority. Model proposals remain inputs to protected deterministic checks.

Software engineering is the first workload to prove, not the permanent ontology of the
system. Prove one useful complete lifecycle, including correction and interruption,
before generalizing roles or workflow definitions. Measure operator effort per
independently accepted outcome, including preparation, review, recovery and Foundry
maintenance. Safety without useful completion and apparent productivity without valid
evidence are both failures.

## Authority and document ownership

The [repair plan](REPAIR-PLAN.md) owns ticket status, ordering, dependencies and
acceptance obligations. The [workflow contract](WORKFLOW-CONTRACT.md) owns identities,
transitions, budgets, isolation, integration and activation. Their current containment
remains binding. This brief closes no ticket, changes no production policy and creates
no parallel backlog. Investigations may inform blocked work; production implementation
and activation still require the owning prerequisites and evidence.

This brief owns the Foundry-first investment rationale and cross-project lessons.
The [broader Foundry chapter](../../docs/strategy/FOUNDRY.md) retains post-repair product
initiatives and portfolio sequencing. Funding the repair foundations first does not
silently waive its post-repair evaluation gates. One operator, one machine and Pramāṇa
remain the present scope; a second repository requires separately approved scope.
Pramāṇa must continue to build and run without Foundry.

## Product thesis

Given a bounded authorized objective, Foundry should let capable models direct useful
work while preserving independently checked outcomes, interruption safety and a durable
account of what actually happened. The longer-term differentiator is a replaceable,
project-portable workflow kernel that can accept model-proposed plans without giving the
planner power to alter the protected rules judging its effects.

Better models should remove pressure to encode planning intelligence, fixed role
taxonomies or elaborate task graphs in the protected core. They do not remove the need
for durable identity, authority, budgets, exact artifact binding, attributable evidence,
independent acceptance and reconciliation of uncertain side effects. Enforcing those
boundaries does not prove arbitrary work correct; useful specifications, real checks,
independent review and evaluation remain necessary. Number of agents, generated pull
requests and test coverage percentages are not the product outcome.

## Architecture to preserve

| Responsibility | Foundry owns | Reuse rather than rebuild |
|---|---|---|
| Authority | Authenticated policy, capabilities, reservations, effect claims and acceptance predicates | OS security primitives and appropriate transactional storage libraries |
| Workflow | Admission, pure decision/replay, scheduling, correction, cancellation and reconciliation for versioned workflow definitions | OTP supervision and ordinary concurrency mechanisms |
| Agent execution | A small versioned and tested execution/observation contract | OMP initially; Pi only as an evaluated alternative |
| Project tools | Approved capability/evidence surfaces for the current assignment | Git/compiler tools for software; typed project APIs where appropriate |
| Presentation | Honest projections and outstanding operator decisions | Herdr initially; future backends only after conformance evidence |

These are responsibilities, not five new services. Keep the protected verifier small:
it checks whether an exact operation is authorized and supported by receipts. It must
not become a second planner, scheduler, context engine or general plugin host. Most
feature work should propose a new use of existing authority, not enlarge authority.

Keep one transactional authority store and one domain reducer for live operation and
replay. Session transcripts, diagnostics, context caches and boards are evidence or
projections, never competing sources of acceptance or budgets. A working process is
not progress; progress is not completion; completion is not acceptance.

## Intelligence boundary: models direct, the kernel governs

Treat workflow intelligence as replaceable and increasingly model-driven. A model may
propose how to decompose an objective, which temporary roles are useful, which permitted
execution profile to use, what context or tools it needs, which checks to run, and how a
correction or sub-workflow should proceed. It may also propose a workflow amendment when
new evidence changes the plan. Those are planning decisions, not authority.

The protected system owns the facts that must not depend on the planner believing its
own story: principal and assignment identity, admitted capabilities, durable revisions,
budget reservations, effect claims and idempotency, unknown-outcome reconciliation,
exact artifact identity, check/review receipts, independence constraints, acceptance
predicates and promotion/activation. A model saying that a test passed, a retry is safe,
or its work is complete is not the corresponding receipt.

A model-generated workflow is therefore an untrusted proposal. Before execution, Foundry
validates it against the current operator/project policy, available capabilities and
budgets, then pins the admitted definition and its revision/digest. A mid-run change is
a new admitted decision, not a silent mutation of history. Project configuration may
request authority but cannot mint it.

Do not bake today's PM/developer/reviewer names or one software lifecycle into protected
storage and authority semantics. Preserve generic identities such as project, workflow,
workflow revision, role, assignment, principal, capability set, artifact/evidence type,
acceptance profile and execution profile. Current repairs may continue using the fixed
software workflow until it is actually proven; this direction is a post-repair
generalization constraint, not authorization to replace the active contract.

The same project should eventually be able to register materially different workflows
with materially different tool surfaces. A software-engineering workflow may receive an
isolated worktree, Git, shell and compiler tools; a content-authoring workflow may receive
only a typed Builder API, simulation and certification operations. Reusing the same
model in both cases does not imply equal authority. Avoid a Turing-complete workflow DSL
or a second orchestrator: start with small composable lifecycle primitives and introduce
generalization only after real portability evidence.

## Lessons to adopt selectively

### FirstMate: operational clarity without another orchestrator

Provide one operator-facing interface that answers what was requested, what is
progressing, what is waiting, which decision belongs to the operator, and what was
accepted. Start with a shallow structure: planner, bounded developers, independent
reviewers and optional diagnostic help. Do not build layers of agent managers before
an observed coordination limit justifies them.

FirstMate's [current-state reader][fm-state] distinguishes append-only status events
from attributable current execution evidence. Apply that distinction in Foundry's
canonical projections: execution liveness, meaningful progress, workflow wait reason
and accepted outcome are separate facts. A failed observation is unknown, not proof
of death. Pane motion or a worker's last message cannot authorize retries or success.

Its [supervision design][fm-supervision] separates deterministic event filtering from
model-assisted attention. Implement ordinary classification, deadlines, capacity and
deduplication in Elixir. An optional diagnostic model may investigate ambiguity and
propose recovery, but cannot decide that an unknown effect is safe to repeat or that
a mandatory check may be ignored. Model-free idle supervision should consume no model
requests. Persist operator decisions until explicitly resolved; displaying a question
or compacting a conversation does not resolve it.

Do not embed FirstMate as a second owner of Foundry dispatch, retries, cleanup or
completion. Borrow mechanisms and failure scenarios, not a competing authority store.

### Pi: explicit session contracts and replaceable execution

Pi's [RPC contract][pi-rpc] is a useful example of structured headless integration.
A successful prompt response means accepted/queued/handled, not task completion.
Correlation IDs alone do not establish durable deduplication. Its documented abort
behavior also requires attention to queued work. Test lost acknowledgments, duplicate
submission, queued cancellation, session replacement and uncertain outcomes against
the actual harness, not a permissive mock.

Use Foundry's existing start/observe/prompt/interrupt/reconcile/close boundary. Keep
conversation continuity separate from workflow authority. The current contract chooses
a fresh developer after correction, not re-prompting the old developer; useful context
can transfer without reviving old execution authority.

OMP remains the baseline. A bounded Pi evaluation can test enforceability, reliability
and maintenance cost, but a migration requires explicit contract review and renewed
conformance. Do not fund multiple equally elaborate production adapters before one
works. Do not rewrite Foundry as a collection of Pi extensions.

### Isolation: reuse mechanisms, prove the whole boundary

The [Pi Gondolin example][pi-gondolin] demonstrates routing built-in tools into a
micro-VM while mounting the workspace read/write. This is an integration candidate,
not proof of Foundry's credential, network, request-budget or activation guarantees.
A different host/isolation topology also requires explicit review of the existing
account and provisioning contract; it cannot be silently substituted.

FR-15a/09 feasibility must inventory all candidate-controlled execution paths: shell,
file/custom tools, extensions, build hooks, language services, subprocesses, inherited
environment, network and shared writable state. Sandboxing one shell tool is insufficient
if another tool executes in a credential-bearing principal. Worktrees are not credential
or OS isolation; protected Git custody must not share candidate-writable authority.

First prove with synthetic credentials and controlled endpoints, then perform the
required bounded real-provider conformance under explicit authorization. Verify that
useful work can finish while tools cannot read reusable credentials, modify protected
state, or create model requests outside the claimed route. Missing proof keeps the
relevant capability disabled. A required upstream harness change should be narrowly
specified before downstream feature investment assumes compatibility.

### no-mistakes: review is an evidence subsystem

Its [agent interface][nm-agent] distinguishes structured-output rejection from provider
and process errors, preserves observed usage on failures, and exposes instruction
neutralization as a tested capability. Foundry reviewers need protected review rules
and trusted relevant project conventions; candidate-modified instructions are material
to inspect, not newly governing policy. Instruction suppression complements, rather
than replaces, credential, capability and filesystem separation.

Make the dependency chain explicit: specification/policy → frozen candidate → required
check receipts → independent review → integration → build → activation. Evidence names
its inputs. A changed candidate or base follows the workflow contract's renewed checks
and review, not an optimistic reuse of old approval. A fresh conversation or different
model alone does not establish independence.

Classify assertion failure, infrastructure failure, invalid artifact and unknown external
outcome separately. Correction, bounded infrastructure handling, validation and
reconciliation are different transitions; generic retry is not a safe default.

### OMP and context: improve feedback before adding more reasoning

Use the existing harness's useful editing and development tools before reimplementing
them in Foundry. Evaluate stale-edit refusal, language-aware diagnostics and bounded
structured results on real Elixir/Phoenix work. Edit anchors are not cryptographic
acceptance evidence or semantic correctness. A custom tool needs an observed recurring
failure and a measurable advantage over the existing toolchain.

FirstMate's [stable supervision prompt][fm-prefix] keeps changing event data out of its
stable prefix. Apply that discipline: trusted role instructions and conventions first;
versioned task/spec/candidate material next; changing observations last. Required context
must never be dropped to meet an arbitrary token limit. Policy changes invalidate stale
assumptions regardless of cache efficiency.

Retain required raw evidence. Summaries are attributed replaceable projections; lessons
are hypotheses until reviewed and tested for a named scope. A lesson cannot weaken a
mandatory gate. Start with task-specific context selection, not unlimited memory.

The bounded Stage-A implementation for issue #26 is documented in
[Assessor Stage A](ASSESSOR.md). It is an advisory experiment with deterministic fallback,
not a production provider route or an acceptance authority.

## Investment milestones within the repair plan

| Milestone | Owning repair work | Evidence before expanding investment |
|---|---|---|
| Feasibility and durable foundation | FR-07/08; bounded investigations informing FR-15a/09 | Actual binding/store/replay proof and executable evidence for a viable harness/tool separation |
| One useful complete task | FR-09–13, FR-15a/15 and their prerequisites | Authorized execution, frozen candidate, real checks, independent review and bounded correction |
| Recovery and controlled integration | FR-10–14, FR-16 and their prerequisites | Interrupted effects reconcile; stale work cannot advance; budgets and ownership survive restart |
| Controlled self-update | FR-17, FR-20/21 and their prerequisites | A real kernel repair activates under unchanged protected authority; rollback preserves acknowledged work |
| Operational acceptance | FR-18/19/22 and all remaining obligations | Useful delivery, honest status, bounded maintenance, real-host/provider evidence and explicit unsupported cases |

These group evidence, not a substitute dependency order or permission to close a parent
ticket early. Demonstrate a correction cycle plus interruption before concurrency. Give
checks, reviewers and admitted finalization capacity ahead of new developers. A cosmetic
board update is not proof of autonomous kernel repair. Do not restore an old snapshot
over newer acknowledged commands to claim successful rollback.

## Resource allocation and evaluation

Assign one architecture/integration owner, explicit durable-state/workflow ownership,
execution/isolation ownership, and genuinely independent verification. These are
responsibilities, not a mandatory headcount. Additional capacity should first improve
real execution environments and independent falsification, not multiply conflicting
edits to shared authority code. Preserve ongoing ticket ownership and unpublished work.

Prioritize state-machine/replay tests, crash-boundary tests, adversarial authority tests
and positive delivery controls. Deliberately break selected protections and require tests
to detect those mutations. A test that derives its expectation from the same broken
implementation is weak evidence. Refusing everything must fail useful-delivery acceptance.

Track both safety and usefulness: operator effort per accepted change, correction and
recovery burden, queue versus execution time, unresolved outcomes, stale-evidence rejection,
budget conservation, and observed versus unknown usage. No assumed model savings or
unmeasured throughput claims. Self-improvement proposals need a baseline, fixed evaluation,
regression checks, effort cap and rollback decision outside the candidate's control.

Postpone multi-machine fleets, deep agent hierarchies, broad plugin marketplaces,
automatic policy learning, custom terminals/harnesses and generalized memory platforms.
The [broader strategy](../../docs/strategy/FOUNDRY.md) owns later repository portability,
context/tool experiments and Superlogical evaluation. Do not put an unverified future
presentation backend on the repair critical path.

## How to use this brief on a task

Read the working summary once when entering Foundry work. For design, new dependencies,
provider/backend changes or investment decisions, read the relevant section as well.
Then work from the current repair ticket, governing contract, source and exact evidence.
State which responsibility a proposed change belongs to, which failure it addresses,
and how both safe refusal and useful completion will be tested. Do not preload every
linked source or append an unrelated initiative to the repair queue.

## Source observations

The following pinned sources informed the 2026-09-17 comparison. Their capability claims
are not installed-backend conformance, privacy/billing authorization or benchmark evidence.
Recheck current licensing and integration terms before copying code or adding dependencies.

[fm-state]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/bin/fm-crew-state.sh
[fm-supervision]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/docs/pi-supervision-branch.md
[fm-prefix]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/bin/fm-branch-prompt.sh
[pi-rpc]: https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/rpc.md
[pi-gondolin]: https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/examples/extensions/gondolin/index.ts
[nm-agent]: https://github.com/kunchenguid/no-mistakes/blob/71cd9110543eeac67fd76180f2bdabd355395ec2/internal/agent/agent.go
