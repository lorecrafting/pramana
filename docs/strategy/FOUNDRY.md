# Foundry: trusted execution for model-directed work

[Strategy overview](../PRODUCT_STRATEGY.md) · [Roadmap](ROADMAP.md)
**Status:** post-repair investment proposal under the existing authority contract.

For the operator's Foundry-first investment direction, architecture boundaries and
lessons from FirstMate/Pi/OMP, read the [Foundry strategy brief](../../foundry/docs/STRATEGY.md).
That brief guides the repair investment; this chapter retains post-repair initiatives
and portfolio sequencing. Neither replaces the repair plan or workflow contract.

## Mission and boundary

Foundry is a trusted execution and governance kernel for model-directed work. Given a
bounded objective, capable models may propose how to decompose and perform the work;
Foundry supplies observable progress, controlled authority/expenditure, attributable
evidence, acceptance and recoverable failure. Software engineering in Pramāṇa is the
first workload and first customer, not the permanent role/workflow model.

The longer-term product option is the same dependable kernel across repositories and
across materially different workflows within one project, without Buddhist-domain or
Pramāṇa database dependencies. Independence is architectural; external demand is still
unproved. The current repair contract covers one operator, one machine and Pramāṇa. A
second-repository or non-software workflow pilot needs separately approved project
scope and policies; FR-22 is not blanket authorization for expansion.

Keep the standalone OTP system. It may require appropriate local libraries and
protected host provisioning; “standalone” does not mean zero dependencies, zero
operations cost or an unmeasured two-second test cycle. Pramāṇa must build and run
without Foundry. A Foundry assignment may invoke authorized project commands in an
isolated environment; Foundry's own authority store must not become Pramāṇa's Repo.

## Repair acceptance is the entry gate, not another initiative

[REPAIR-PLAN](../../foundry/docs/REPAIR-PLAN.md) and
[WORKFLOW-CONTRACT](../../foundry/docs/WORKFLOW-CONTRACT.md) govern. The former owns
status and ordering; do not copy its mutable ticket states into this strategy.
FR-22 owns end-to-end closure and unresolved limits, including a real autonomous
kernel repair under unchanged protected-root policy. Green component CI alone is
not that acceptance. This strategy neither closes tickets nor suspends obligations.

| Existing repair authority | Product implication after acceptance |
|---|---|
| FR-07/08 and the workflow contract | Consume the accepted transactional state, command and replay interfaces; do not build a parallel event store |
| FR-09/15a/16 | Provider use must satisfy installed harness, isolation, entitlement and bounded switching evidence |
| FR-10/11/12 | Lifecycle ownership, reconciliation and scheduling are foundations to use, not essay-derived replacements |
| FR-13/14/17 | Candidate, review, check, integration and activation identities remain distinct |
| FR-18/19/20/21 | Use honest projections, retention, constrained improvement and build provenance |
| FR-22 | Require the scenario evidence and explicit unsupported cases before post-repair autonomous product work |

A discovered contradiction returns to the owning contract through review. It does
not authorize a strategy rewrite of the repair queue or an operator-only kernel
that permanently removes the agreed autonomous repair capability.

## One operating model, not several overlapping stacks

Consolidate harness/graph/loop, the four-layer compound stack and the six-layer OS
into six responsibilities: **contract, context, tool boundary, durable state,
evidence, recovery**. These are a review vocabulary, not six new services.

The workflow kernel decides domain transitions; the protected verifier owns safety
and authority checks. Middleware can shape context or diagnostics inside those
boundaries. A plugin, model response or general evaluation tool cannot be allowed
to replace the checks that constrain it. Keep OMP as the current harness and Herdr
as initial optional presentation unless the governing contract is explicitly changed.

A subagent used as a tool returns bounded findings while the parent retains task
ownership. A lifecycle handoff changes the responsible assignment/role with durable
identity. Neither gains permission to accept its own work. Review must be independent
of the maker's authority and have the exact candidate, contract, source context and
raw evidence it needs—not merely a diff and one suggested test command.

## Models direct; the kernel governs

Increasing model capability should shrink Foundry's hard-coded intelligence rather than
eliminate its protected kernel. Let models propose decomposition, temporary role names,
workflow topology, context/tool requests, execution profiles, tests, reviewers and
correction strategies. Do not invest in a large permanent planner hierarchy, fixed role
taxonomy or rule engine whose main job a stronger model can perform from current state.

Keep deterministic or protected the things whose truth cannot safely depend on the
planner: admitted objective/policy revision, principal and assignment identity,
capability grants, durable state transitions, request/budget accounting, effect claims
and duplicate suppression, exact artifact identity, check/review provenance,
independence requirements, acceptance predicates, reconciliation and promotion.
Protected policy may require gates omitted by a proposed workflow and a plan cannot
weaken them. A model may propose completion, retry or publication; receipts and policy
authorize the corresponding effect. Independence follows durable principal/authority
lineage and candidate ownership, not a fresh role name, session or model.

Post-repair workflow portability should be project-configurable rather than role
hard-coded. A project/workflow definition may declare requested roles, capability
requirements, context rules, evidence types, acceptance profile and project adapters.
Those declarations are requests: effective capability is the intersection of protected
operator policy, project scope, workflow/role allowance and the specific assignment.
Repository-controlled configuration can never grant itself secrets, billing authority,
arbitrary shell/network access or publication power.

Pin every admitted workflow definition/revision to the run that used it. If a model or
project changes the plan mid-run, record and admit a new revision instead of rewriting
history. Child work and sub-workflows inherit parent scope and budget ceilings unless
protected policy narrows them; composition cannot mint authority. Favor a small
vocabulary such as sequence, bounded parallel work, gates, handoff, correction and
sub-workflow invocation over an unconstrained executable workflow language. Generalize
only from observed needs.

This permits different workflows inside one project. For example, a future Lokacore
software workflow could use isolated Git/shell/compiler capabilities, while an approved
RPG content-authoring workflow could expose only its typed Builder API, simulations and
certification. The same model could serve as engine developer in one assignment and
quest author in another because authority follows the assignment, not the model name.
Released game/runtime artifacts should remain independently useful without Foundry or an
LLM. This is a future portability target, not part of the current Pramāṇa repair scope.

## Positioning: own the contract, not commodity infrastructure

Foundry must earn its custom infrastructure. Its durable product boundary is the
authority/evidence contract around model-directed work: admitted intent and capability,
durable identities and budgets, exact external-effect accounting, exact artifact/evidence
binding, independence constraints, acceptance, reconciliation and controlled promotion.
Agent loops, software-factory UIs, workflow runtimes, sandboxes, policy languages and
model routers are implementation choices unless the governing contract proves otherwise.

Before post-repair work adds or substantially extends one of those implementation layers,
run a bounded substitution evaluation against the strongest available alternative.
Current candidate classes include Warp Factories for software-factory orchestration,
LangGraph for agent/workflow runtime, Restate/Temporal/DBOS for durable execution,
Dagger plus OS/container/micro-VM primitives for execution isolation, and OPA/Cedar for
bounded authorization-policy evaluation. These names are candidates, not dependencies.

A substitution evaluation compares the actual Foundry cases—not feature lists—including
lost acknowledgments, duplicate delivery, unknown side-effect outcomes, durable budgets,
credential separation, exact candidate/receipt binding, independent review, mandatory
gates, cancellation, restart/replay, positive useful completion, local operating burden,
privacy/licensing and reversible migration. Adopt a candidate only where it lowers total
burden without weakening those properties. If it fully satisfies a layer, remove or avoid
duplicative Foundry code. If a future product satisfies the entire useful contract, using
it instead of Foundry is a valid success outcome.

This is also the future-proofing rule: model capability growth should delete planning
heuristics; infrastructure maturity should delete infrastructure code. What should remain
stable is the contract that distinguishes a proposal from authority, activity from
evidence and completion claims from accepted outcomes.

## Elixir control plane; OS/sandbox security plane

Retain Elixir/OTP for long-lived coordination, supervision, workflow state/replay,
assignment lifecycle and recovery. Do not use BEAM process separation as the security
boundary for arbitrary agent-controlled tools.

Hard process/filesystem/network/resource boundaries belong to the host or a proven
execution backend. On Linux, evaluate native primitives such as namespaces, cgroups,
seccomp and Landlock, normally through a container/sandbox/micro-VM layer rather than a
new Foundry reimplementation. Non-Linux hosts need equivalently tested mechanisms.
Dagger is worth a bounded evaluation because it exposes typed execution objects and an
Elixir SDK, but its current Elixir SDK is beta and Dagger must still prove Foundry's
credential, egress and cleanup requirements before adoption.

The execution backend therefore remains replaceable beneath the Elixir authority/control
plane. Foundry should specify *what must be isolated and evidenced*, not own every kernel
mechanism used to achieve it.

## Jev as a fast semantic layer, not authority

The current Stage-A assessor already captures the appropriate Jev boundary. TypeSafe's
System One guidance keeps deterministic control flow and side effects in code while
models answer narrow typed questions with probabilities/confidence. If held-out
evaluation supports it, Jev can become a cheap reflex layer for context ranking,
diagnostic triage, progress/stuck signals, duplicate findings, risk classification and
execution-profile recommendations.

Those signals remain advisory. Deterministic policy decides whether a confidence range
may trigger a low-risk automatic path, require stronger-model/human verification, or do
nothing. Jev cannot establish entitlement, spend, durable state, reviewer independence,
safe retry of an unknown effect, acceptance or promotion. Keep a deterministic fallback
and a replaceable provider boundary because Jev is currently early access.

## First post-repair investment: useful context and honest feedback

Measure where the operator loses time, then try one bounded improvement. Candidate
I-F1 compiles task-specific context from the small repository router, governing
contract, active source/diff, dependencies, relevant rules and evidence references.
Routine tasks need less history than architecture work, but never zero constraints.

Keep compact observations with a route to underlying evidence: command, environment,
source revision, actual work performed, exit status, diagnostic locations and the
full artifact reference. A successful command that performed no expected work must
not count as productive completion. An empty queue can be healthy and idle; distinguish
**service health**, **eligible work**, **work attempted** and **accepted outcomes**.

Read-cache receipts are hints, not authorization or durable memory. Recheck the
file hash/revision before relying on cached content, and invalidate on external
changes. No universal 500-token ceiling or fifteen-line diagnostic can fit every
contract. Size limits must preserve decisive errors and mandatory context.

## Memory: evidence first, projections second

Use the accepted local transactional authority store. Diagnostic logs and retrieval
indexes are not competing sources of authority. Separate these record types:

| Record | Treatment |
|---|---|
| Raw command, artifact and test evidence | Retain under the owning security/retention policy with identity and access controls |
| Current state | Rebuildable projection of acknowledged decisions and external receipts |
| Task decision | Attributed decision with scope, rationale, author/authority, date and supersession |
| Lesson or skill candidate | Hypothesis until reviewed, tested and approved for the relevant scope |

Resolve the notebook's “summarize everything” versus “never summarize” conflict:
**retain required evidence; summaries are replaceable, attributable projections**.
Read-time selection can use those projections plus original evidence. A summary
cannot mint a passing receipt, authorize a transition or erase an unresolved failure.
“Save everything” is not permission to persist secrets or private inputs forever.

Promote useful lessons through failure → investigation → verified evidence → reviewed
rule/skill → relevant consultation. Automate proposals where authorized; do not let
a model silently make global policy from one anecdote. Measure recurrence reduction
and false alarms. Personal, task, project and shared scopes need explicit access and
promotion boundaries, even before any multi-user product exists.

Pramāṇa's research notes remain separate from canonical sources and from this
engineering ledger. Similar provenance concepts do not justify shared tables,
credentials, embeddings or a required memory SaaS.

## Providers, budgets and recovery

Repository guidance applies to Claude, Gemini, DeepSeek, Codex and other providers.
That does not make all profiles eligible for automation. The current repair contract
permits only explicitly authorized subscription routes; paid OpenRouter/DeepSeek
use remains manual unless the operator changes policy through the proper authority.
No eligible route means wait with a reason. Provider choice, harness implementation
and terminal/session backend are three different decisions.

Do not freeze model brand names or price tiers into strategy. Evaluate permitted
profiles by task success, review effort, latency and total cost. Reviewer capability
must fit the risk; a cheaper model is not automatically an adequate grader. A new
API gateway is an optional dependency, not a reason to route around OMP or billing
isolation. Pramāṇa's user-facing model service needs its own approved policy; builder
subscription permission does not authorize serving public product queries.

Use the accepted budget ledger across retries, child work, handoffs, restarts and
switches. Preserve unknown outcomes for reconciliation; a context reset or profile
change cannot refill a budget. Reserve bounded recovery capacity and stop safely
before exhaustion. A model may propose completion or stopping; acceptance requires
evidence, while blocked, cancelled or budget-exhausted states are valid non-success
outcomes. Task prompts never override higher-priority safety or operator authority.

## Improve tools without replacing the system

Candidate I-F2 evaluates one mechanism at a time: structured diagnostics, AST outlines
and previewed edits, duplication checks, architecture-boundary checks, or UI test
capture. Retain ordinary source files and human-readable diffs. A syntactically valid
AST rewrite is not semantic correctness; an empty rewrite must report no change.
Browser/vision checks supplement functional and accessibility tests, not certify them.

Prefer small composable tools, but unrestricted evaluation inside a production BEAM
is not a safe shortcut. Evaluate in isolated workers with bounded interfaces.
The [research register](RESEARCH.md) treats Elixir Vibe packages as candidates, not
an adopted dependency set. No new framework earns a place without measured benefit
and an explicit maintenance/security cost.

## Portability and the Superlogical option

Candidate I-F3 first proves the accepted software workflow on one operator-selected,
non-Pramāṇa repository and compares the result with the best practical off-the-shelf
alternative for the same job rather than assuming custom Foundry orchestration is needed. Identify project-specific commands, roles and evidence adapters
without generalizing the entire platform. After that baseline, a stronger portability
proof is a separately authorized workflow with a materially different tool/evidence
surface in the same project, such as typed content authoring rather than Git/shell.
Evaluate onboarding effort, reliability and net operator effort before pursuing
multi-user hosting or a commercial package. This is a separate product hypothesis,
not a permanent support feature of Pramāṇa.

Retain Superlogical as the preferred **future candidate to evaluate** for session/
presentation integration, not a completed or feature-equivalent Herdr replacement.
Its public roadmap is not backend conformance evidence. I-F4 requires a real
available interface, ownership/cleanup and reconnect tests, failure reconciliation,
headless operation, credential/billing separation, licensing review and a reversible
cutover. If it changes execution rather than presentation, return to FR-09/15a's
contract boundary. Do not block the first Pramāṇa product workflow on its availability.

## Prevent endless infrastructure work

After H0, protect one primary research-product slice and allow one bounded Foundry
improvement alongside it, subject to operator capacity. Give every improvement a
baseline, success condition, effort cap and stop decision. If it does not improve
accepted delivery after review/rework/maintenance are included, revert or defer it.
Keep reliability fixes prioritized, but require evidence for “this platform will
make everything faster.” Do not let a second-repository experiment silently become
a generalized multi-tenant rewrite.
