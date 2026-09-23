# FR-08B B3 contract readings: a proposal for Q1–Q7

> **Approved by the operator, 2026-09-22:** all seven recommended readings are accepted as the interpretation B3 is built against. The contract text is unchanged. B3's kernel scope is items 1–3 of "if approved" below; items 4–5 are protected-code maintenance, scheduled separately because they touch attestation-pinned files.

**Date:** 2026-09-22. **Type:** proposal, **not approved**. The
[workflow contract](../WORKFLOW-CONTRACT.md) is **unchanged**, and so are the repair plan, the
code, the tests and `r4_coverage_test.exs`. The contract belongs to the operator; nothing here
takes effect until the operator accepts a reading. **Taken at commit `bc62a3b4`**
(`repair/fr08b-kernel`). Paths are relative to `foundry/` unless stated. Functions are
cited by name, not by line number.

This answers the seven contract-reading questions in the
[B3 gap inventory](FR08B-B3-GAP-INVENTORY-2026-09-22.md#contract-reading-questions-flagged-not-resolved)
(taken at `3727f2e8`). Cell verdicts (ABSENT, PARTIAL, NOT-KERNEL, IMPLEMENTED) and the
letters (P), (D), (C), (G) and (O) are that document's. It is subject to the operator's standing
direction of 2026-09-22: do not grow the reference kernel beyond correctness fixes until the
[orchestrator boundary](../ORCHESTRATOR-BOUNDARY.md) exists, and defer PM execution close
until then. Where the contract text genuinely allows it, this proposal prefers the reading that
keeps an obligation out of the kernel. Where the text makes the kernel own something, it says
so.

**Evidence rule.** Code was read, not run. No test, gate or sweep was run to write this. When
a test is cited it was read, and the citation shows only that the test exercises the code, not
that it would catch a fault there (EVIDENCE-TOOLS rule 6).

## Two facts found while answering, which the inventory did not record

1. **The protected layer has no pause or drain.** `root_controls` has two values:
   `status: "active"` and `status: "cancel_requested"`. `fence_control_descendants` refuses
   any other value with `:invalid_control_state`. `control_active?/1`, which `allowed_effect?`,
   `claim_effect` and `issue_claim` all call, tests only `status == "active"`. So pause and
   drain exist **only** as the kernel's reducer-owned `paused` and `draining` flags. No layer
   anywhere refuses an issue under pause or drain today. This matters for Q1 and Q2: R3 says
   that "for every effect claim the verifier independently checks: ... current control/policy
   revision". That places general control-on-issue enforcement at the protected claim, but
   the protected claim has no pause or drain to check.
2. **The kernel applies events one at a time, against the current state.** `apply/2` passes
   the whole current state to `transition/3`, and `check_sequence/2` requires the event's
   sequence to be greater than the last one. A guard in a `*_planned` handler that reads
   `state["control"]` therefore reads the control that is current *when the event applies*.
   The inventory's "a control change between planning and applying goes unseen" is true of a
   future plan producer that computes a proposal ahead of time and CASes only the ticket's
   revision. It is not true of the pure reducer. A kernel guard needs no `control` read kind
   today. A plan producer will need one when it exists.

## Q1: where is "queuing its successor"?

**Question.** When R4a evaluates control "before queuing its successor", does "successor"
mean the next issued execution, or the non-start settle's own move back to a scheduling phase?

**Competing readings.**

- *Reading A: the successor is the next issue.* The rule is met by refusing the next
  `*_planned` under control. Each settle keeps its one fixed domain effect. Support:
  - R4a, no ID: "The scheduler may create only the next effect referencing the recorded
    predecessor and only when current controls, allocation, resources and the finite
    infrastructure allowance permit it." This names the point where control is checked:
    creating the next effect.
  - R4a, no ID: "A retry is a new execution/effect with a new reservation and semantic
    operation ordinal, referencing that terminal predecessor. It is eligible only after ..."
    The retry is a new effect, not the settle.
  - R4.04.f3: "no pause/drain/cancel". The contract's only control conjunct with an ID sits
    on the *issue* row, "queued → create its launch intent and enter developing" (R4.04.o2).
    It does not sit on the settle.
  - R4a.01.o3: "return ticket `developing → queued` with `resume_phase: developing`". The
    move to `queued` is stated without any control condition.
  - R4a, no ID: "Restart after settlement but before redispatch therefore reconstructs
    exactly one queued/review/blocked owner and no live execution." Settlement and
    redispatch are separate moments, and any of the three owner states is acceptable between
    them.
- *Reading B: the settle's own move is the queuing.* Control must choose among
  queued, `blocked(draining)` and cancel-finalize inside the settle's atomic bundle.
  Support:
  - R4a.01.o7: "Below the infrastructure limit, queue a bounded developer retry." This
    "queue" is an outcome of the atomic settle row itself.
  - R4a, no ID: "Non-start settlement, domain transition, infrastructure ordinal and
    reservation settlement commit together." If control can change "the domain transition",
    it has to be evaluated inside this atomic unit.
  - R4a, no ID: "Drain forbids developer and PM replacement launches, so their work
    **becomes** `blocked(draining)` with the same resume phase and ordinal." This names a
    state outcome, not just a refusal.

**Recommendation: Reading A.** The strongest reason is that the contract states where
control is checked in so many words: "The scheduler may create only the next effect ... only
when current controls ... permit it." Reading B needs R4a.01.o7's "queue a bounded retry" to
mean "issue". The contract separates the two everywhere else, and o7 reads naturally as "the
retry becomes eligible to be queued for issue". "Becomes `blocked(draining)`" is still
reachable under A: a later `ticket_blocked` expresses it, and R4.04.f3 keeps the
queued-under-drain interval safe, because nothing can issue during it. Nothing in the text
requires the block to share the settle's transaction. A second reason, which does not decide
the question: under B, cancel-finalize would be bundled with a non-start settle, and that
skips R4.28.f3 ("cleanup reconciled"). The non-start settle does not establish that
condition. R4a.01.o5 releases the checkout lease only "after proving the checkout was never
exposed or mutated".

**Downstream.**

| | Reading A (recommended) | Reading B |
|---|---|---|
| Developer Ordering | Folds into the R4.04.f3 guard. Stays **ABSENT** until that guard lands. **Kernel-owned** | Stays **ABSENT**. Needs a `control` read kind in `TransitionPlan`, a control discriminator or plan alternatives, and a plan producer. That is Core, not the reducer, but none of it exists |
| Reviewer, check, build, integration Ordering (4 cells) | **ABSENT → NOT-KERNEL.** Choosing the successor is the controller's. Any refusal left over is carried by the Cancel column (and by Pause, if Q2 binds the role) | Stay **ABSENT**, Core-owned as above |
| Drain, "becomes `blocked(draining)`" | The controller writes `ticket_blocked(draining)`. That is already expressible (inventory item 5) | A Core discriminator selects it |
| Design's "prestate read in `domain_reads`" | Not needed by the reducer (fact 2). A wiring requirement for a future plan producer | Needed now |

**Confidence: medium.** Evidence that would change it: an operator ruling that the block must
commit atomically with the settle. For example, stop accounting might need to see no queued
owner under drain at any instant, since R4 Controls says "stop does not wait for a forbidden
fresh developer". That would force B.

## Q2: does pause bind checks, builds, integration and reviewers?

**Question.** Does pause forbid issuing every role, or only "productive" roles?

**Competing readings.**

- *Reading A: pause forbids every issue.* Support:
  - R4a, no ID: "Pause retains the recoverable phase but forbids issue until resume." No
    qualifier.
  - The contract's Deployment paragraph: "Each productive step has its own R1 claim and R5
    operation/start reservation." Here "productive" describes deployment steps, including
    build. That weakens any reading that takes "productive" to mean "model role".
- *Reading B: pause forbids productive issuance (developer, PM and probably reviewer), and
  check, build and integration continue as settlement of admitted work.* Support:
  - R4 Controls, no ID: "pause blocks new **productive** issuance, allowing receipt
    processing/cleanup."
  - R4 scheduling, no ID: "All productive roles **and** check/build workers consume
    configured process capacity." In the same section, the contract treats check and build
    workers as something other than productive roles.
  - R4.15 (reviewer), R4.11 (checks) and R4.20 (integration) have no control conjunct in
    their from-cells. R4.04 (developer) has one: R4.04.f3.

**Recommendation: Reading B for check, build and integration. The reviewer is left open.**
The strongest reason is that the R4 Controls sentence is the contract's own statement of what
pause *is*. It qualifies issuance as "productive", and two paragraphs later the contract
separates productive roles from check/build workers. R4a's pause sentence sits inside the
non-start paragraph and says what pause does to a successor. It is naturally read against the
general rule, not as a wider one. The reviewer is a model role, and so plausibly
"productive". But R4.15 has no pause conjunct, so the text neither includes nor excludes it
clearly.

**What stays fixed under both readings.** Only R4.04.f3 puts a pause conjunct on a reducer
row. The kernel's pause obligation is therefore the developer refusal, whichever reading the
operator picks. For every other role, the contract places control-on-issue at the protected
claim (R3: "For every effect claim the verifier independently checks: ... current
control/policy revision"), or leaves it to scheduling. That protected claim cannot express
pause today (fact 1). The gap is Core, outside the kernel.

**Downstream.**

| | Reading B (recommended) | Reading A |
|---|---|---|
| Developer Pause | **ABSENT**, kernel-owned (R4.04.f3) | Same |
| Check, build, integration Pause (3 cells) | **ABSENT → NOT-KERNEL.** No obligation. A controller may still choose not to schedule | Stay **ABSENT**. Owned by Core issuance (the verifier's control check), not the reducer, because no R4 row carries the conjunct |
| Reviewer Pause | **ABSENT → NOT-KERNEL** in the kernel sense. If pause binds reviewers, the Core issuance check enforces it, or the controller does | Same as the row above |

**Confidence: low on scope, medium on kernel ownership.** The Deployment paragraph's
"productive step" is real counter-evidence to B. What would change it: an operator statement
of what "productive" means in R4 Controls. Either answer leaves the kernel's pause obligation
at R4.04.f3.

## Q3: `drain` or `draining`? *Factual, not interpretive, for the code half*

**Question.** Is the drain block reason spelled `drain` or `draining`, and is it one reason
or two?

**What the code emits (factual).** The kernel **emits no drain reason at all**. The only
reason literals the kernel writes are `"developer_launch_non_started"` (in `launch_settled`)
and `"integration_failure"` (in `integration_recorded`). `ticket_blocked` and `ticket_parked`
copy a caller-supplied `payload["reason"]`. `State.well_formed?/1` constrains it only by
`optional_identifier?` (a non-empty valid string, or nil). Any spelling is accepted, and
nothing distinguishes one spelling from another.

**What tests pin (factual).** Nothing pins either spelling. `"drain"` appears in exactly three
places, all in `kernel_test.exs` call-site refusal rows: `ticket_blocked` refused with
`:invalid_resume_phase`, `ticket_blocked` refused with `:resume_target_not_current_phase`, and
`ticket_parked` refused with `:wrong_source_phase`. In each one the refusal comes from the
phase guard, and the reason string is incidental. `"draining"` never appears as a reason in
`lib/` or `test/`. It appears only as the control flag key (`State`'s `@control_keys`,
`control_changed`'s payload), which follows the contract's Control row "Orthogonal pause/drain
flags".

**The interpretive part left over: one reason or two.** R4.13.o3 and R4.17.o3 say
`blocked(drain)`, and R4.21.o3 says "blocked under drain". R4 Controls says "reason=draining",
and R4a says "`blocked(draining)`". **Recommendation: one reason, spelled `draining`.** The
strongest reason is that the only sentence written as an explicit key=value is R4 Controls'
"become blocked with resume_phase=queued and reason=draining". The row cells use `drain` as
shorthand inside a list of alternatives ("blocked(drain)/exhausted"). No sentence says the two
are different reasons.

**Downstream.** No cell moves. The inventory's **[READ]** on developer Drain is resolved. The
reason vocabulary belongs to the controller (O0 S4, inventory item 7), so it is **not
kernel-owned** under either spelling. Because the kernel never reads the reason, the
`nonstart_developer` scenario, which drives the same `ticket_blocked` from the same state with
another reason string, exercises the same code path. The expressible half of the developer
Drain cell does not need a separate test for the spelling.

**Confidence: high** for the factual half. **High** for "one reason". **Medium** for the
spelling. What would change it: an operator preference for `drain`. Nothing in the kernel
would have to change.

## Q4: where does build sit?

**Question.** R4a.04.f1 names a "build" worker, but R4 has no build row and the kernel has no
build phase. Is that build part of the ticket's candidate lifecycle, or the deployment build?

**Competing readings.**

- *Reading A: build is a candidate-phase worker, like a check.* Support:
  - R4 scheduling, no ID: "All productive roles and **check/build workers** consume configured
    process capacity."
  - R5, no ID: "Launch/start reservations belong to execution/check-run/**build** IDs". R5 also
    has a separate `starts.build` dimension.
  - R4 Controls, no ID: "Cancellation also covers check/build/import/ref/activation effects".
- *Reading B: build is the deployment build, after acceptance and outside the ticket
  lifecycle.* Support:
  - Integration section, no ID: "Build **accepted source** from pinned
    dependency/toolchain/config/role inputs in an isolated worker." This is the only place
    the contract says what a build does, and it is after acceptance.
  - "Deployment: requested→**built**→draining→stopped→... Each productive step has its own R1
    claim and R5 operation/start reservation. **Build failure retains running old service.**"
  - R4a.04.o1: "Preserve its **candidate/deployment** phase". The row names the deployment
    phase, and it lists build next to "activation worker".
  - R4 scheduling, no ID: "With capacity one, developer closes, checks run and close, then
    reviewer runs and closes." The per-ticket sequence has no build step.

**Recommendation: Reading B.** The strongest reason is that every sentence in the contract
that says what a build *does* describes building accepted source for deployment. The
sentences that group build with checks are about capacity and cancellation, which apply to
any worker. `build_planned` and `build_settled` came from the codec's `starts.build` slot
([vocabulary enumeration](fr08b-event-vocabulary-enumeration.md)), not from an R4 row. Their
guards reflect that: `require_active_attempt` only, with no phase. The drain question the
inventory raised does not depend on this reading. R4a's drain sentence gives a closed list of
what drain forbids, "developer and PM replacement launches", and build is not on it.

**Downstream.**

| | Reading B (recommended) | Reading A |
|---|---|---|
| Build row, 7 cells | **All → NOT-KERNEL.** Out of B3's ticket-lifecycle scope. They belong to the deployment/activation lifecycle, which the kernel does not model (FR-13/14 territory). Pause ABSENT, Ordering ABSENT, Drain/Cancel/Infra/Alloc PARTIAL all leave the matrix | Build is treated as a mandatory check. Drain stays PARTIAL (eligible). Pause follows Q2. Cancel is covered by the generic per-ticket cancel guard. Infrastructure limit needs a block row **the contract does not have**, so that needs a contract amendment |
| Kernel `build_*` events | Not extended. They remain an open question for the boundary work (keep them as a generic worker, or remove them). Not B3 | Need a phase or a block row |

One obligation survives either reading. R4 Controls' "Cancellation also covers
check/build/..." means a per-ticket cancel must refuse `build_planned` as long as the event
exists. That is part of the role-agnostic cancel guard below, not a build-specific rule.

**Confidence: medium.** What would change it: a design or operator statement that a
pre-review build of the candidate (a compile step alongside the checks) is intended. That
would make A right and would need an R4 row.

## Q5: policy revision between issue and non-start

**Question.** `infrastructure_discriminator/3` fails closed once policy has been revised. Is
that failure the contract's "block", or an outcome the contract does not list?

**Competing readings.**

- *Reading A: fail-closed is an acceptable "block".* Support: R3, no ID: "For every effect
  claim the verifier independently checks: ... current control/policy revision". Also "Bad
  lifecycle proposals can block progress, but cannot manufacture authority." Refusing to
  decide under a stale policy is the conservative direction.
- *Reading B: fail-closed is a gap, because the non-start must still settle.* Support:
  - R4a, no ID: "An issued launch with attributable proof that no process, backend session
    or model request started **settles** the R1 effect as `non_started`, closes that
    execution as `closed`, and settles its R5 start reservation exactly once as
    `released`." The contract gives no condition under which a proved non-start stays
    unsettled.
  - (G), R4a, no ID: "If policy revocation or a budget-generation change makes a retry
    ineligible, **preserve the role-specific phase/owner and block or exhaust it**". The
    named outcome is a domain state (blocked or exhausted), reached after settlement.
  - R4a, no ID: "An old-generation refund settles that generation under R5 and cannot
    finance the new retry implicitly." The old generation must settle.

**Recommendation: Reading B.** The strongest reason is that (G) is conditioned on the change
making "a *retry* ineligible". It keeps the settlement and puts the consequence on the retry.
Fail-closed on the *settle* bundle reverses that: the proved non-start, its reservation and
its execution slot stay held, which is the treatment R4a reserves for an `unknown` start. The
retry's ineligibility is already enforced where R3 puts it. `claim_effect` and `issue_claim`
require `policy.revision == effect.policy_revision`, and `allowed_effect?` checks the current
policy, so a retry needs a new effect under the current policy. The discriminator does not
need to refuse the settle to protect the retry. One observation, from reading only: a
proposal-bearing envelope reaches `atomic_domain_proposal/3` with no discriminator, and no
rule found in `Gateway` forces a non-start onto the plan path. So the stranding may be
avoidable today by committing a fixed block. That was read, not run, and it would bypass the
limit decision.

**Downstream.** No cell moves. The five non-PM (G) cells stay **NOT-KERNEL**, and PM (G)
stays **ABSENT** [PM-DEFERRED]. The fix is **protected, not the kernel or the controller**.
The discriminator should decide against a policy that does not fail closed on revision. That
could be the current policy's limit, which matches "every retry reserves from the current
permitted generation", or the recorded revision via the existing
`infrastructure_discriminator_at_revision/3`. Under R3's table this is **operator
maintenance**, and it would flip `atomic_bundle_test :: a policy revised after the effect was
created fails closed`. That test exercises the primitive directly, not the bundle outcome.
Under Reading A nothing changes anywhere, and the stranded settlement is accepted.

**Confidence: medium.** What would change it: an operator ruling that a policy revision
should quarantine in-flight non-starts until someone reviews them. That is a legitimate
choice, but it would need a contract sentence, because R4a does not list it.

## Q6: which phase does an integration non-start return to?

**Question.** After a proved integration non-start, should the ticket and attempt stay
`integrating` or return to `ready_to_integrate`?

**Competing readings.**

- *Reading A: stay `integrating`, so the kernel is wrong.* Support:
  - R4a.04.o1: "Preserve its candidate/deployment phase and verified inputs"
  - R4a.04.o2: "apply that phase's existing infrastructure retry/block row."
  - R4.23.o1: "Same phase with bounded integration-effect retry after old issuer
    termination".
- *Reading B: return to `ready_to_integrate`, the honest scheduling phase.* Support:
  - R4.20.o1–o2: "integrating ticket/attempt; root integration intent, then R1 claim/issue".
    Entering `integrating` *is* the issue step, just as R4.04.o2's "create its launch intent
    and enter developing" is for the developer. R4a.01.o3 undoes that step for a developer
    non-start ("return ticket `developing → queued`").
  - R4.23's from-cell is "proved no ref change {R4.23.f2}, **command infrastructure failed**
    {R4.23.f3}". That is a command that ran. A proved non-start never ran, so R4.23 is not
    "that phase's existing row" for it.
  - R4.21.f1 "ready_to_integrate/integrating; accepted base moved **before issuance**" names
    both phases as pre-issuance-compatible.

**Recommendation: Reading B.** The strongest reason is the parallel with the developer row:
the contract undoes the issue step's phase change on a proved non-start, and for integration
that step is `ready_to_integrate → integrating` (R4.20.o1). The code already relies on this:
`integration_planned` accepts both `ready_to_integrate` and `integrating`, so the retry is
expressible either way. `require_settlement_source`'s `superseded_base` comment records
`integration_settled` as a writer of attempt phase `ready_to_integrate` that "closes the
execution on the way". The only thing in conflict is `integration_settled`'s own comment
("preserve the phase"). That is a comment defect, not a behavioural one.

**Downstream.** No control cell moves. Integration's Infrastructure-limit cell stays
**PARTIAL**, because blocking after a non-start is still *unwitnessed*, but it loses its
**[READ]**. The target phase belongs to the controller (O0 K11: "target `ready_to_integrate`
is Controller"), so this is **not kernel-owned**. Under Reading A the kernel would need a
behavioural change to `integration_settled`, and the phase/attempt pairing would need
rechecking against `@legal_pairs`, which is new kernel work outside correctness.

**Confidence: medium.** What would change it: an operator reading that R4a.04.o2 points
integration non-starts at R4.23 regardless of whether the command started.

## Q7: does protected binding satisfy "the kernel must bind"?

**Question.** Do claim, receipt, predecessor and generation, which the protected layer
already binds, meet the settlement-identity obligation? Or must the reducer compare the bound
fact with its own state?

**First, a correction of attribution.** "The kernel must bind the settlement to the execution
it settles ... the adapter must not be left to invent the check" is the
[design's](fr08b-kernel-correction-design.md#b3--r4a-control-crossing-at-the-specified-ordering-point)
sentence, not the contract's. The contract does not contain it.

**Competing readings.**

- *Reading A: protected binding meets it. Only the settlement ↔ execution/owner/role link is
  open.* Support:
  - R3 table: the protected verifier owns "effect claims; receipt provenance; acceptance
    predicates".
  - R3, no ID: "Root-derived fields (claims, budget balances, ... policy and review/check
    receipt validity) **cannot be supplied by kernel events**."
  - R4a, no ID: "Every proved non-start atomically records `(role, work_owner,
    predecessor_effect_id, failure_class, infrastructure_attempt_ordinal)`" and "A duplicate
    or late receipt is idempotent by claim/receipt identity". `persist_nonstart_settlement/3`
    does exactly that.
  - The design's own last clause: "the adapter must not be left to invent the check". The
    protected layer is not the adapter.
- *Reading B: the reducer must compare them itself.* Support: the design's "The kernel must
  bind", read literally, and "Caller-supplied identifier sets do not satisfy this". Neither
  is a contract sentence.

**Recommendation: Reading A.** The strongest reason is that R3 assigns claim and receipt
provenance to the protected verifier and forbids kernel events from supplying root-derived
fields. A reducer that re-derives or restates them would copy protected truth into a
candidate-repairable component. `State`'s module note says the kernel "may not restate"
ledger truth. The link that stays open can be closed without the reducer. `root_effects`
already stores `execution_id`, `ticket_id`, `attempt_id`, `role` and `assignment_id` for each
effect. `TransitionPlan.bind/3`, or a Gateway check at bind time, can refuse a settlement
whose effect's execution, ticket, attempt or role disagrees with the event it is bound into,
or with the event type's role. That does not keep `effect_id` in kernel state.

**Downstream.** No control cell moves. The inventory's settlement-binding table resolves as
follows:

- Claim and receipt: **met** (protected).
- Predecessor: **met**. The chain rule is still *unwitnessed* by name.
- Generation: **met** protected-side. The kernel's own `infrastructure.generation` counter
  stays an unresolved O0 U1/K16 item, not a B3 binding gap.
- Execution, effect, role and work owner: **open**, and **Core, not kernel**. The fix goes in
  `TransitionPlan`/`Gateway`, which is protected code and so operator maintenance under R3.
- PM settle naming its execution: **[PM-DEFERRED]** either way.

**Confidence: high** that the contract makes the verifier own claim and receipt provenance.
**Medium** that `TransitionPlan` is the right home for the link rather than the reducer. What
would change it: a finding that `bind/3` cannot see the event payload's ids at bind time.
That would push the comparison into the reducer.

## Summary

| Q | Recommended reading | Confidence | Owner of what remains |
|---|---|---|---|
| Q1 successor | The next issue, not the settle. Control is checked at `*_planned` | medium | Kernel for the developer (R4.04.f3). Controller for choosing the successor |
| Q2 pause scope | "Productive" issuance only. Check, build and integration are not bound. Reviewer open | low (scope), medium (ownership) | Kernel for the developer only (R4.04.f3). Core issuance or the controller for others |
| Q3 drain spelling | Code emits none and tests pin none (**factual**). One reason, `draining` | high (fact), medium (spelling) | Controller (reason vocabulary) |
| Q4 build | The deployment build, outside the ticket lifecycle | medium | Not B3. Deployment/activation lifecycle |
| Q5 policy revision | Fail-closed is a gap. The non-start must settle, and the retry is refused at the claim | medium | Protected discriminator (operator maintenance) |
| Q6 integration phase | `ready_to_integrate` is correct. R4.23 is for a started command | medium | Controller (target phase). No kernel change |
| Q7 binding | Protected binding meets claim, receipt, predecessor and generation. The execution/owner/role link is open | high (reading), medium (placement) | Core `TransitionPlan`/`Gateway`, not the reducer |

**Projected matrix under all recommended readings.** This is a projection from readings alone,
with no code change. Recount from it, not from this sentence. Over 42 cells: **IMPLEMENTED 2,
PARTIAL 14, ABSENT 9, NOT-KERNEL 17** (from 2 / 18 / 17 / 5). The moves:

- Build: 7 cells → NOT-KERNEL (Q4).
- Reviewer, check and integration: Pause and Ordering, 6 cells → NOT-KERNEL (Q1, Q2).
- What stays ABSENT: developer Pause and Ordering, both closed by one R4.04.f3 guard, and the
  7 PM cells [PM-DEFERRED].

## If approved: the minimal correctness-owned scope for B3

These are obligations, not a design. Each is correctness, not growth: it adds refusals or
bindings, and no vocabulary, phase or role.

1. **Kernel: R4.04.f3.** `launch_planned` refuses under `paused`, under `draining` and under
   the ticket's `cancel_requested`, with **one refusal test per conjunct** (EVIDENCE-TOOLS
   known gap 1), and moves `R4.04.f3` from `{:unguarded}` in `r4_coverage_test.exs`. This one
   guard closes developer Pause, the ban half of developer Drain, developer "never retries"
   and developer Ordering. Corrections and rebases under drain (R4.13.o3, R4.17.o3, R4.21.o3)
   are covered too, because each one issues through the same `launch_planned`. The
   depth-6/depth-7 reachable-state denominators must be re-measured, not carried over.
2. **Kernel: per-ticket cancel never retries, for every role.** Every ticket-scoped
   `*_planned` (`check_planned`, `build_planned`, `review_planned`, `integration_planned`,
   plus item 1) refuses while `cancel_requested`, with one refusal test per handler. The basis
   is R4.27.o1 ("cancel pending/unissued effects") and R4 Controls ("Cancellation also covers
   check/build/import/ref/activation effects"). This belongs to the kernel because per-ticket
   cancel is reducer-owned state and the protected layer represents only a root-control
   cancel (fact 1).
3. **Kernel evidence only: witness settle-then-finalize after a non-start** for developer,
   reviewer, check and integration. These are tests, with no code change, and they discharge
   the *unwitnessed* half of each Cancel cell.
4. **Core, not the reducer: the settlement ↔ execution/ticket/attempt/role link** at bind time
   in `TransitionPlan`/`Gateway` (Q7). This is protected code, so it needs operator
   maintenance under R3.
5. **Core, not the reducer: a proved non-start settles under a revised policy** (Q5). The
   discriminator must not strand it. This is protected code, needs operator maintenance, and
   flips one `atomic_bundle_test` row.

**Explicitly outside this scope, under these readings:** choosing the successor
(`queued`/`blocked(draining)`/limit block/exhausted), drain's role taxonomy, the reason
vocabulary, pause for any role other than the developer, build lifecycle cells, the
integration target phase, every PM cell, and the allocation discriminator. The allocation
discriminator is a separate protected primitive that none of Q1–Q7 decides.
