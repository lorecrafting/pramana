# FR-08B B3 gap inventory: R4a controls crossed with roles

**Date:** 2026-09-22. **Type:** inventory only. It changes nothing: no code, no test, no
contract text, no classification in `r4_coverage_test.exs`. **Taken at commit `3727f2e8`**
(`repair/fr08b-kernel`). Handlers and guards are cited by function name, not line number.
Paths are relative to `foundry/` unless stated.

This is groundwork for [B3](fr08b-kernel-correction-design.md#b3--r4a-control-crossing-at-the-specified-ordering-point),
not a design. It says what [R4a](../WORKFLOW-CONTRACT.md#r4a) requires, what the kernel does
today and what is missing. It updates the
[subcommit 2 control inventory](fr08b-subcommit2-control-inventory.md), which was taken at
`a798579`. Its table gave only what the contract requires. This one adds the kernel side and
a test for every claim. Where the two disagree, this one is the later reading. It does not
replace that document.

## Verdict key and evidence rule

- **IMPLEMENTED**: the kernel does it, and a named test exercises it.
- **PARTIAL**: part of the obligation is done. A claim with no test behind it is marked
  *unwitnessed* (EVIDENCE-TOOLS rule 3).
- **ABSENT**: nothing in the kernel does it.
- **NOT-KERNEL**: the contract assigns the decision to protected policy or the adapter. The
  cell still records whether the kernel can *express* the outcome.

Test names are written as `file :: describe test`. Row-driven tests are named by their
scenario, e.g. `r4_coverage_test :: every contract row is driven nonstart_developer`.
No test was run to write this document. Each cited test was read, not executed.

## Three facts that decide most cells

1. **No transition reads control.** `transition/3` passes the whole state to
   `do_transition/4`, but every clause binds that state as `_state`. `paused`, `draining`
   and `stop_status` are written by `do_transition("control_changed", ...)` and read by no
   transition. `State.new/0`'s `control.generation` is written by nothing. Per-ticket
   `cancel_requested` is read only by `require_cancel_requested/1`, from
   `cancellation_finalized` and from `require_settlement_source/2`'s `"cancelled"` branch.
   No `*_planned` handler reads it. `r4_coverage_test.exs` already records this as
   `R4.04.f3 => {:unguarded, "B3. ..."}`.
2. **There is no `decide/3` and no plan producer.** `Workflow.Kernel.Plan` does not exist
   (see the comment in `durable_store/transition_plan.ex`). The design says control is "an
   ordinary prestate read under CAS ... named in `domain_reads`". At this commit that has no
   implementation:
   - `TransitionPlan`'s `@read_kinds` is `~w(state ticket objective pm)`, with no `control`
     kind.
   - Nothing outside `transition_plan.ex` reads `domain_reads`.
   - `apply/2`'s `check_revision/2` checks only the addressed entity's revision, so a
     control change between planning and applying a ticket event goes unseen.

   See also the four mismatches in the [reads inventory](fr08b-subcommit2-reads-inventory.md).
3. **The control sentences have no clause IDs.** R4a's paragraph beginning "Control state is
   evaluated after recording non-start ..." carries none, so it is in neither `@clauses` nor
   `@uncited`. Neither is R4's "Controls:" paragraph. Clause coverage cannot count any pause,
   drain, cancel or generation obligation below except R4.04.f3 (a from-cell) and the row
   outcomes quoted per cell.

## The matrix

Every cell is detailed in the sections that follow.

| Role | Pause | Drain | Cancel | Policy revocation / generation | Infrastructure limit | Allocation exhaustion | Ordering rule |
|---|---|---|---|---|---|---|---|
| Developer | ABSENT | PARTIAL | PARTIAL | NOT-KERNEL | IMPLEMENTED | PARTIAL | ABSENT |
| Reviewer | ABSENT | PARTIAL | PARTIAL | NOT-KERNEL | IMPLEMENTED | PARTIAL | ABSENT |
| Mandatory check | ABSENT | PARTIAL | PARTIAL | NOT-KERNEL | PARTIAL | PARTIAL | ABSENT |
| Build | ABSENT | PARTIAL | PARTIAL | NOT-KERNEL | PARTIAL | PARTIAL | ABSENT |
| Integration | ABSENT | PARTIAL | PARTIAL | NOT-KERNEL | PARTIAL | PARTIAL | ABSENT |
| PM planning | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT | ABSENT |

Counts over 42 cells: **IMPLEMENTED 2, PARTIAL 18, ABSENT 17, NOT-KERNEL 5.** The table
above is the source; recount from it rather than from this sentence.

Markers used below: **[READ]** the answer depends on a contract reading. **[PM-DEFERRED]**
the answer depends on the PM lifecycle deferred until the orchestrator boundary exists
([R4a.03.f2 review](fr08b-r4a03f2-review-2026-09-22.md)). **[TOPOLOGY]** B3 would add
role-specific surface that [the boundary](../ORCHESTRATOR-BOUNDARY.md#foundry-core) puts
above Core.

## What R4a requires, quoted once

The cells below refer to these by letter.

- **(P)** R4a, no ID: "Pause retains the recoverable phase but forbids issue until resume."
  R4 Controls, no ID: "pause blocks new productive issuance, allowing receipt
  processing/cleanup."
- **(D)** R4a, no ID: "Drain forbids developer and PM replacement launches, so their work
  becomes `blocked(draining)` with the same resume phase and ordinal; reviewer,
  mandatory-check and already-admitted finalization retries remain eligible under the
  existing drain rule." R4 Controls, no ID: "Drain blocks new tickets, PM and developer
  issuance but permits already admitted checks, reviews and integration to settle."
- **(C)** R4a, no ID: "Cancel settles the proved non-start/refund and finalizes cancellation
  when no other issued work remains; it never retries." R4.27.o1: "cancel pending/unissued
  effects".
- **(G)** R4a, no ID: "If policy revocation or a budget-generation change makes a retry
  ineligible, preserve the role-specific phase/owner and block or exhaust it; every retry
  reserves from the current permitted generation. An old-generation refund settles that
  generation under R5 and cannot finance the new retry implicitly."
- **(O)** R4a, no ID: "Control state is evaluated after recording non-start and before
  queuing its successor." And: "Non-start settlement, domain transition, infrastructure
  ordinal and reservation settlement commit together."
- **(R4.04.f3)** "queued; ...; no pause/drain/cancel". This is the only control conjunct with
  an ID.

## Cells, by role

### Developer

| Control | What the kernel does today | Verdict and evidence |
|---|---|---|
| Pause (P, R4.04.f3) | `launch_settled` keeps the attempt and sets `queued` with `resume_phase: developing`, so the phase is retained. `launch_planned` (`require_phase`, `require_no_open_developer`, `require_cleanup_complete`, `open_attempt`, `add_execution`) never reads `paused` | **ABSENT.** The ban on issue has no refusal. Recorded as `R4.04.f3 {:unguarded}` in `r4_coverage_test.exs`. The retention half is the ordinary non-start outcome, see Infrastructure limit |
| Drain (D) | `ticket_blocked` from `queued` accepts `resume_phase: developing`, because `require_honest_resume_target` admits the stored target from `queued`. It leaves the ordinals alone. `launch_planned` never reads `draining` | **PARTIAL.** `blocked(draining)` with the same resume phase and ordinal is expressible. It is witnessed only for a different reason string: `r4_coverage_test :: every contract row is driven nonstart_developer` drives the same event from the same state with `developer_launch_infrastructure`. The ban on replacement launch is **ABSENT**. **[READ]** the reason spelling, see Q3 |
| Cancel (C) | `launch_settled` is accepted under `cancel_requested` because it does not read it. `attempt_settled(cancelled)` needs only `require_cancel_requested`. `cancellation_finalized` needs `require_cancel_requested`, `require_no_active_attempt` and `require_all_executions_closed`. `launch_planned` never reads `cancel_requested` | **PARTIAL.** Settling then finalizing is expressible but *unwitnessed* after a non-start: `every contract row is driven cancel_finalized` goes through `stream_sealed`/`developer_closed`, not `launch_settled`. "Never retries" is **ABSENT**: a `launch_planned` after the cancel is accepted |
| Policy / generation (G) | `add_execution` keeps only `authority.execution_id`, dropping `policy_id`, `policy_revision`, `control_revision` and `infrastructure_generation`. `infrastructure.generation` changes only in `ticket_reset`. The block outcome (`ticket_blocked`) and the exhaust outcome (`attempt_settled(exhausted)`) are both expressible | **NOT-KERNEL.** Whether a retry is still eligible, and refund financing, are protected policy and R5. The kernel's outcome is witnessed by `every contract row is driven reset` (a non-start, then `attempt_settled(exhausted)`). **[READ]** Q5: `ProtectedPrimitives.infrastructure_discriminator/3` fails closed once policy is revised (`atomic_bundle_test :: a policy revised after the effect was created fails closed`), so the non-start plan cannot bind at all. The row says instead to "preserve ... and block or exhaust" |
| Infrastructure limit (R4a.01.o7, o8) | `launch_settled` then `ticket_blocked(developer_launch_infrastructure, resume developing)`, with the attempt still active. The choice is made by `TransitionPlan`'s `infrastructure_limit_v1` discriminator, which is protected | **IMPLEMENTED.** `r4_coverage_test :: every contract row is driven nonstart_developer` asserts the block, the retained active attempt and the resumed relaunch. o7 and o8 are in `@clauses`. The protected selection is witnessed by `atomic_bundle_test :: an ordinal at the policy limit selects the exhausted branch` and its "below" sibling. The kernel's own ordinal is never read (O0 U1) |
| Allocation exhaustion (R4a.01.o9) | `attempt_settled(exhausted)` is allowed from attempt phase `active` by `require_settlement_source`, and `apply_terminal_phase` sets the ticket `exhausted` | **PARTIAL.** The kernel side is witnessed by `every contract row is driven reset`, which asserts attempt `exhausted` and ticket `exhausted` after a non-start. R4a.01.o9 is still in `@uncited`. Choosing exhaustion over the limit block needs an allocation discriminator. It is **ABSENT** (`@discriminator_kinds` is `~w(infrastructure_limit_v1)`), and the design says it "does not exist and must be specified". The exhausted settlement's `settlement` field is not bound, see Settlement binding |
| Ordering (O) | `launch_settled` writes `queued` and `developer_launch_non_started` unconditionally. Nothing reads control before or after | **ABSENT.** **[READ]** Q1 |

### Reviewer

| Control | What the kernel does today | Verdict and evidence |
|---|---|---|
| Pause (P) | `review_planned` (`require_phase`, `require_active_attempt`, `require_attempt_phase`, `require_checks_passed`, `add_execution`) never reads `paused` | **ABSENT.** **[READ]** Q2: R4.15's from-cell carries no control conjunct |
| Drain (D) | Nothing reads `draining`, so a reviewer retry stays eligible | **PARTIAL, unwitnessed.** It holds only because nothing reads drain. No test plans a reviewer under `draining: true` |
| Cancel (C) | `review_settled` is accepted under cancel. `attempt_settled(cancelled)` is allowed from `awaiting_review`. `review_planned` never reads `cancel_requested` | **PARTIAL.** Settle then finalize is *unwitnessed*. "Never retries" is **ABSENT** |
| Policy / generation (G) | As for the developer. `ticket_blocked` from `awaiting_review` is allowed, and so is `attempt_settled(exhausted)` from `awaiting_review` | **NOT-KERNEL.** The block is witnessed (`nonstart_reviewer`). Exhausting from `awaiting_review` is *unwitnessed* |
| Infrastructure limit (R4a.02.o7, o8, o9) | `review_settled` returns the ticket and attempt to `awaiting_review` and keeps the candidate. Then `ticket_blocked(reviewer_launch_infrastructure, resume awaiting_review)` | **IMPLEMENTED.** `every contract row is driven nonstart_reviewer` asserts the block, the resume phase and the retained candidate and checks. Note that R4a.02.o7 and o8 sit in `@uncited` although this scenario asserts o8. That undercounts, which is the safe direction |
| Allocation exhaustion (R4a.02.o10) | `ticket_blocked(reviewer_budget)` goes through the same path. `attempt_settled(exhausted)` is allowed from `awaiting_review` | **PARTIAL, unwitnessed.** No test uses `reviewer_budget` or exhausts from `awaiting_review`. The choice is "under protected policy", and no allocation discriminator exists |
| Ordering (O) | `review_settled` writes `awaiting_review` unconditionally | **ABSENT.** **[READ]** Q1 |

### Mandatory check

| Control | What the kernel does today | Verdict and evidence |
|---|---|---|
| Pause (P) | `check_planned` (`require_attempt_phase`, `require_active_attempt`, `add_check`, `add_execution`) never reads `paused` | **ABSENT.** **[READ]** Q2: whether a check counts as "productive issuance" |
| Drain (D) | Nothing reads drain | **PARTIAL, unwitnessed.** "Remain eligible" holds only because nothing reads drain |
| Cancel (C) | `check_settled` is accepted under cancel. `attempt_settled(cancelled)` is allowed from `checking`. `check_planned` never reads cancel | **PARTIAL.** Finalizing is *unwitnessed*. "Never retries" is **ABSENT** |
| Policy / generation (G) | The outcome rows are R4.14.o3's "blocked(check_infrastructure)/exhausted" | **NOT-KERNEL.** The block is witnessed (`check_infrastructure_failed`). Exhausting from `checking` is *unwitnessed* |
| Infrastructure limit (R4a.04.o2 → R4.14.o3) | `check_settled` keeps `checking`, deletes the unsettled check so `add_check` can re-reserve it, and consumes the `check` ordinal. The block is `ticket_blocked` from `awaiting_review` | **PARTIAL.** The retry is witnessed by `every contract row is driven nonstart_worker`. The block is witnessed only after `check_recorded(infrastructure_failed)` (`check_infrastructure_failed`), not after `check_settled`. `@partial` records this row's allowance as unreachable |
| Allocation exhaustion | `attempt_settled(exhausted)` is allowed from `checking` | **PARTIAL, unwitnessed.** `@partial` for `check_assertion_failed` records "or blocked(drain)/exhausted needs the R4a limit product" |
| Ordering (O) | There is no check queue. A retry is simply the next `check_planned`, and nothing reads control | **ABSENT** |

### Build

The kernel has no build phase. `build_planned` guards only `require_active_attempt`, and
`build_settled` guards only that plus `close_execution`. The contract names build in R4a.04
and in "check/build workers" but gives it **no R4 row**. **[READ]** Q4 covers every build
cell.

| Control | What the kernel does today | Verdict and evidence |
|---|---|---|
| Pause | `build_planned` never reads `paused` | **ABSENT** |
| Drain | Nothing reads drain. Whether build is a "mandatory-check" retry or a "finalization" retry is not stated | **PARTIAL, unwitnessed** |
| Cancel | `build_planned` is accepted under cancel | **PARTIAL.** Settle then finalize is *unwitnessed*. "Never retries" is **ABSENT** |
| Policy / generation | Same shape as the check cells | **NOT-KERNEL.** The kernel outcome is *unwitnessed* for build |
| Infrastructure limit | `build_settled` consumes the `build` ordinal. The block would be `ticket_blocked` from whichever phase the build ran in | **PARTIAL, unwitnessed.** `kernel_properties_test :: after a non-start settlement the owner is queued with no live execution` lists `build_settled`, and `KernelWalk` proposes it, but the test asserts only that *some* settle occurred (`checked > 0`), not that this one did. The block is *unwitnessed*, and there is no "existing row" to apply |
| Allocation exhaustion | No row. `attempt_settled(exhausted)` is allowed from phases `active`, `checking`, `awaiting_review` and `reviewing` | **PARTIAL, unwitnessed** |
| Ordering | Nothing reads control | **ABSENT** |

### Integration

| Control | What the kernel does today | Verdict and evidence |
|---|---|---|
| Pause | `integration_planned` (`require_phase`, `require_no_ref_receipt`, `require_issuer_terminated`, `require_active_attempt`, `add_execution`) never reads `paused` | **ABSENT.** **[READ]** Q2 |
| Drain | Nothing reads drain. Integration is "already-admitted finalization" | **PARTIAL, unwitnessed** |
| Cancel | `integration_planned` is accepted under cancel. `attempt_settled(cancelled)` is allowed from `ready_to_integrate`, and `cancellation_finalized` then takes the `cancelled` branch because `integration_occurred?` is false | **PARTIAL.** *Unwitnessed* after a non-start. "Never retries" is **ABSENT** |
| Policy / generation | R4.21.o3: "blocked under drain or budget exhaustion". `require_settlement_source` does not allow `exhausted` from `ready_to_integrate` or `integrating`, which is consistent | **NOT-KERNEL.** The kernel's `ticket_blocked` outcome is *unwitnessed* |
| Infrastructure limit (R4a.04.o1, o2 → R4.23) | `integration_settled` moves both ticket and attempt to `ready_to_integrate` and consumes the `integration` ordinal | **PARTIAL.** The effect of the settle is witnessed by `kernel_test`'s call-site rows for `integration_settled`, which are refusals only, and by the same `kernel_properties_test`, with the same `checked > 0` caveat as build. A block after a non-start is *unwitnessed*: `integration_failure` drives R4.23's other route, `integration_recorded(infrastructure_failed)`. **[READ]** Q6: R4.23.o1 says "Same phase", while the kernel leaves `integrating` |
| Allocation exhaustion | R4.21.o3 gives a block. It is expressible through `ticket_blocked` | **PARTIAL, unwitnessed** |
| Ordering | Nothing reads control | **ABSENT** |

### PM planning — every cell [PM-DEFERRED]

`pm_launch_planned` returns `{:ok, objective}` and records nothing. `pm_launch_settled`
consumes the objective's `pm` ordinal with no guard, which is `R4a.03.f2 {:unguarded}`. The
objective has no phase, no `blocked` state, no `resume_phase`, no `cancel_requested` and no
execution register (`@objective_keys`). Nothing that R4a.03 or B3 asks of a PM outcome can
be stored.

| Control | Verdict and evidence |
|---|---|
| Pause | **ABSENT.** There is no PM issue to forbid, because `pm_launch_planned` records nothing |
| Drain | **ABSENT.** "blocked(draining) with the same resume phase and ordinal" has no objective state to land in |
| Cancel | **ABSENT.** Cancel is ticket-only (`cancellation_requested` addresses a ticket) |
| Policy / generation | **ABSENT.** The decision is NOT-KERNEL, but the kernel cannot express the block-or-exhaust outcome |
| Infrastructure limit (R4a.03.o4, o5) | **ABSENT.** There is no `pm_launch_infrastructure` block. Both clauses are in `@uncited`. The ordinal is counted per objective, while the protected layer requires a `ticket:attempt:pm` work owner (O0 U9) |
| Allocation exhaustion (R4a.03.o5) | **ABSENT.** There is no `pm_budget` block |
| Ordering | **ABSENT.** The "PM queue" (R4a.03.o4) has no representation in the kernel |

`every contract row is driven nonstart_pm` asserts only o1, o2 and o6. It leaves the owner
kept, no proposal and no ticket admitted. The ordinal it asserts is consumed without any
guard.

## Settlement identity binding

The design says: "The kernel must bind the settlement to the execution it settles: claim,
receipt, role, work owner, effect, predecessor and infrastructure generation ... the adapter
must not be left to invent the check."

The settle events are `launch_settled`, `review_settled`, `check_settled`, `build_settled`,
`integration_settled` and `pm_launch_settled`. `attempt_settled` is listed separately because
it too carries a `settlement` field. The **Protected side** column is what
`TransitionPlan.bind/3` and `ProtectedPrimitives.persist_nonstart_settlement/3` already
bind. It is listed so that nothing is counted twice: a field bound there is not a kernel gap
unless the link *between* the bound fact and the event's own fields is missing.

| Field | Kernel binds today | Protected side binds | Gap |
|---|---|---|---|
| Execution | Ticket settles name `execution_id`. `close_execution/4` checks that it exists in the named attempt (`require_execution`), that its role is in the event's role set (`require_execution_role`) and that it is not already closed (`require_not_closed`). `review_settled` adds `require_reviewer_execution`. Tests: `kernel_test :: a launch settlement naming an execution the attempt does not own is refused`, `... :: a review settlement cannot close another role's execution`, and `nonstart_developer`'s `:wrong_execution_role` | Nothing. `@settlement_fields` has no `execution_id` | **No layer links the settlement fact to the execution it closes.** `pm_launch_settled` names no execution at all (review finding 2) |
| Effect | Nothing. `add_execution` drops `authority.effect_id`, and `settlement.effect_id` is never read | The settlement is keyed by `effect_id` and taken from `settle_claim`'s result, not a caller copy (`atomic_bundle_test :: copied settlement carrier is bound to authoritative receipt-derived settlement`) | Nothing checks that `settlement.effect_id` is the effect whose authority minted the named `execution_id`. The pairing is known at plan time and then thrown away |
| Claim, receipt | Nothing | `receipt.claim_id == claim.claim_id`, and `receipt.outcome == "non_started"`. `atomic_bundle_test :: bounded settlement rejects every scalar that diverges from accepted provenance` | None beyond the effect gap, if the protected binding counts as "not the adapter" (Q7) |
| Role | The event type fixes the role recorded on the execution at plan time, from the event type rather than `authority.role`. `settlement.role` and `authority.role` are never compared | `settlement.role = effect.role`. The discriminator refuses a mismatch (`atomic_bundle_test :: a settlement role disagreeing with the effect fails closed`) | `@slots` maps an event type to an output kind, not to a role. Nothing refuses a reviewer effect's settlement bound into `launch_settled.settlement`, or a reviewer authority in `launch_planned.authority`. *Unwitnessed either way* |
| Work owner | The ticket through `check_entity_addressing`. The attempt through `require_active_attempt`. `settlement.work_owner`, `authority.ticket_id` and `authority.attempt_id` are never compared with the payload | `work_owner = effect.assignment_id`. The ordinal is counted per `(role, work_owner, generation)` | Nothing compares the event's `ticket_id`/`attempt_id` with the bound fact's owner. `bound_carriers_agree` checks only that the fact sits in its slot |
| Predecessor | Nothing | `validate_nonstart_predecessor`: the same role, owner and generation, and ordinal + 1. The divergence test above tampers with `predecessor_effect_id` | The chain rule itself (ordinal + 1) has no test that names it: **PARTIAL, unwitnessed** |
| Infrastructure generation | `infrastructure.generation` changes only in `ticket_reset` and is never compared with `settlement.infrastructure_generation` | Taken from `effect.phase_generation`. `reset_fact_v1` has no producer, so `ticket_reset.generation` cannot bind (O0 K15) | Two generation counters that nothing checks against each other. An old-generation settle after a reset is refused only through attempt identity (`:not_the_active_attempt`), not through generation |
| Ordinal / duplicates | `consume_infrastructure_ordinal` counts on its own and ignores `settlement.ordinal` (O0 U1). A distinct duplicate settle is refused by the phase guard, `require_check`, or `require_not_closed`, depending on the role. *Unwitnessed as a duplicate-receipt test*. Redelivery of the same event is covered by `kernel_test :: a redelivery of the event an entity last applied is an idempotent no-op` | Authoritative. `atomic_bundle_test :: duplicate non-start cannot advance infrastructure and conflicting receipt quarantines` | For PM, a late settle for PM0 consumes a second ordinal (review finding 2). The limit decision uses only the protected ordinal, so the kernel counter is not counted twice |

**`attempt_settled.settlement`** has no slot in `TransitionPlan`'s `@slots`. The kernel never
reads it, and tests pass `%{"schema_version" => 1}`. R4a.01.o9's exhaustion, R4.10.o4 and
every other terminal disposition therefore arrive with a settlement that is caller-supplied
and bound to nothing. This is the `terminal_settlement_v1` producer gap (O0 E4/U3) seen from
the settle side.

## Contract-reading questions (flagged, not resolved)

- **Q1: where is "queuing its successor"?** *Reading A:* the successor is the next
  `*_planned`, so the ordering rule is met by refusing the retry under control, and each
  settle keeps its one fixed effect. That is R4.04.f3's shape and the earlier inventory's
  "the kernel does not queue". *Reading B:* the settle's own move to
  `queued`/`awaiting_review` *is* the queuing, so control must choose among
  `queued`/`blocked(draining)`/cancel-finalize **inside the same atomic bundle**, as a plan
  alternative the way `infrastructure_limit_v1` chooses. Under B the design's "prestate read
  in `domain_reads`" needs a `control` read kind, which does not exist.
- **Q2: does pause bind checks, builds, integration and reviewers?** R4a's pause sentence has
  no qualifier. R4's reads "pause blocks new **productive** issuance", and a later R4 sentence
  separates "All productive roles and check/build workers". R4.15 (reviewer) and R4.20
  (integration) carry no control conjunct, while R4.04 does. *Reading A:* pause forbids every
  issue. *Reading B:* pause forbids developer and PM (and maybe reviewer), while
  check/build/integration continue as settlement of admitted work.
- **Q3: `drain` or `draining`?** R4.13.o2 and R4.17.o3 say `blocked(drain)`. R4.21.o3 says
  "blocked under drain". R4 Controls and R4a say `reason=draining` / `blocked(draining)`.
  `kernel_test` uses `"drain"`. Is this one reason or two?
- **Q4: where does build sit?** It has no R4 row and no phase. R4a.04.o2's "apply that phase's
  existing infrastructure retry/block row" has nothing to apply, and drain eligibility
  depends on whether build is a check or finalization.
- **Q5: policy revision between issue and non-start.** (G) says preserve and block or exhaust.
  The only discriminator fails closed on a revised policy, so the bundle is rejected and the
  non-start stays unsettled. Is fail-closed the contract's "block", or a second outcome the
  contract does not list?
- **Q6: integration non-start phase.** R4a.04.o1 says "Preserve its candidate/deployment
  phase", and R4.23.o1 says "Same phase with bounded integration-effect retry".
  `integration_settled` moves to `ready_to_integrate`. *Reading A:* the phase is
  `integrating`, and the kernel is wrong. *Reading B:* a proved non-start never began
  integrating, so `ready_to_integrate` is the honest scheduling phase, as with the
  developer's `developing → queued`.
- **Q7: does protected binding satisfy "the kernel must bind"?** Claim, receipt, predecessor
  and generation are bound by the protected layer, which is not the adapter. *Reading A:* the
  obligation is met for those fields, and only the settlement ↔ execution/owner/role link is
  open. *Reading B:* the reducer must itself compare the bound fact with its own state, which
  requires keeping `effect_id` at plan time.
- The inventory in `r4_coverage_test.exs` already holds the rest: `@from_unclassified`
  R4a.02.f1/f2 ("frozen candidate awaiting review" versus `review_settled`'s
  `~w(reviewing)`), and `ticket_reset`'s generation comment.

## Correctness-owned versus controller-possible

The operator's standing direction is not to grow the reference kernel beyond correctness
fixes until the orchestrator boundary exists. The split below follows the contract's own
assignment of ownership, and where the contract does not say, the O0 Split pattern: Core
decides the fact, and the controller authors the alternatives
([O0 §6](../orchestrator/O0-AUTHORITY-INVENTORY-2026-09-22.md#6-seams-named-only), seam 2).

**Correctness: the contract makes the reducer own it**

1. **R4.04.f3: refuse developer issue under pause, drain or a pending cancel.** It is a
   from-cell of a reducer row, and it is already recorded `{:unguarded}` as B3. The fix is a
   refusal in `launch_planned`, with one refusal test per conjunct (EVIDENCE-TOOLS known
   gap 1).
2. **Settlement ↔ execution/effect/role/owner link.** The design says outright that the
   adapter must not invent this, and no layer holds it today. It could be placed in the
   kernel (keep `effect_id` at plan time) or in `TransitionPlan` (carry `execution_id` in
   the settlement fact, or cross-check it against the payload). Both are Core, not
   controller. The `TransitionPlan` option does not grow the kernel. **[READ]** Q7 sets the
   minimum.
3. **"Cancel never retries" for the other roles**, only under Q2 reading A, and scoped to
   R4.27.o1's "cancel pending/unissued effects". A root control cancel is already enforced
   protected-side. `allowed_effect?`, `claim_effect`, `issue_claim` and `reclaim_claim`
   require control status `active`, and `fence_control_descendants` cancels unissued
   descendants (`fr08a_critical_corrections_test :: control cancellation revokes claimed
   descendants and preserves no implicit credit`). The gap is the **per-ticket** cancel,
   which the protected layer does not represent.
4. **PM settle naming its execution** (R4a.03.f2). This is correctness, but
   **[PM-DEFERRED]** by operator decision. O0 §4 puts the Core form as a role-agnostic
   execution register for an objective-owned execution, not a `pm_closed` event.

**Controller-possible: can sit above Core**

5. **Choosing the successor after a non-start**: `queued`, `blocked(draining)`,
   `blocked(<role>_launch_infrastructure)`, `exhausted` or cancel-finalize. Each outcome is
   already expressible through `ticket_blocked`, `attempt_settled` and
   `cancellation_finalized`, witnessed as the cells above say. Only *which* one is chosen is
   missing. That selection is the alternatives a plan producer (`decide/3`) or a controller
   writes. **[TOPOLOGY]** under Q1 reading A. Under reading B it becomes a protected
   discriminator over control. That is Core, and it needs a new discriminator kind, not new
   kernel vocabulary.
6. **Drain's role taxonomy**: developer and PM forbidden, reviewer, check and finalization
   eligible. **[TOPOLOGY]** This is exactly the "permanent PM/developer/reviewer topology"
   the boundary keeps out of Core. Core needs only "this execution kind is not issuable
   under drain", with the list of kinds supplied as controller or profile input.
7. **Reason vocabulary**: `draining`, `developer_launch_infrastructure`,
   `reviewer_launch_infrastructure`, `reviewer_budget`, `pm_launch_infrastructure`,
   `pm_budget`. **[TOPOLOGY]** O0 S4 puts block and resume in Core and the resume and reason
   vocabulary in the controller. `ticket_blocked` already takes a free reason, so B3 needs
   no new kernel surface here.
8. **The allocation discriminator** (developer `exhausted` versus the limit block, reviewer
   `reviewer_budget` versus `exhausted`, PM `pm_budget`). This is protected Core, not
   kernel: the design calls it a "second discriminator primitive". Whether the limit is
   reached is Core. What happens to the work there is controller-authored alternatives.
9. **Pause for check/build/integration**, only under Q2 reading B: a controller scheduling
   choice, with no reducer refusal.
10. **Every PM cell beyond item 4.** **[PM-DEFERRED]** and **[TOPOLOGY]** together: the PM
    queue, PM drain and PM budget blocks depend on objective phase state that the kernel
    does not have. By O0 §4, the meaning of "PM" belongs to the controller.

## What this inventory did not do

It ran no test, no gate and no sweep. It did not verify that each cited test fails when its
guard is removed (rule 6). A cited test is evidence of exercise, not of discrimination. It
did not read `gateway.ex` beyond the discriminator path, nor the R5 ledger. It classifies no
from-cell and edits no `@uncited` entry. Where it notes a citation discrepancy (R4a.02.o8
asserted but listed uncited), that is for the next classification pass to act on.
