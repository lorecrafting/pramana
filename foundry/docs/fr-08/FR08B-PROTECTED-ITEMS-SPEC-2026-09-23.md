# FR-08B protected items: attempt close, reset fact, settlement binding

**Date:** 2026-09-23. **Type:** design spec. **Independently reviewed 2026-09-23 (Fable): PASS WITH
CHANGES**; the four changes (F1–F4) are folded in below and marked.
Taken at `33e6b95b` (`repair/fr08b-kernel`, gate green, 989 passed). Authorized as operator
maintenance by [the O1 sequencing decision](../orchestrator/O1-SEQUENCING-PROPOSAL-2026-09-23.md),
items 1–4. Line numbers are at `33e6b95b`.

## The rule every choice below follows

**A guarantee Core owns must not depend on a controller choosing to check it.** The kernel is
one controller among future ones ([orchestrator boundary](../ORCHESTRATOR-BOUNDARY.md)); an
external controller is untrusted. So a fact R5 or R4a requires is produced and enforced by the
protected layer, keyed on identities Core already owns (scope, attempt, execution, effect), never
on role names. The controller keeps what a role means and which disposition to claim.

## Item 1 — `terminal_settlement_v1`: a protected `close_attempt` operation

**Gap.** `attempt_settled` binds no protected fact (`transition_plan.ex:48` has no producer).
The contract's reading of attempt termination is "every owned claim terminal" (R4 `cancelled`
row, quoted at `kernel.ex` `require_settlement_source`), and R5 says "an attempt groups these
reservations but owns no fungible refill". No protected operation today states that every
effect and reservation under an attempt is settled: `settle_claim` closes one claim.

**Rejected alternative:** have the kernel require every execution it knows about to be closed.
It enforces R5 only for the executions the controller chose to record, so a controller that
omits one would terminate the attempt with a live reservation. That fails the rule above.

**Design.** New protected operation `close_attempt` with keys
`type scope ticket_id attempt_id`:

- Refuses unless `scope == "ticket:" <> ticket_id` (today's only admissible scope, U9).
- Loads every `root_effects` row with that `(ticket_id, attempt_id)`. Refuses
  `attempt_not_settled` if any has status outside `succeeded failed non_started cancelled`
  (so `unknown` and `reconciliation_required` block, per R4's "unknown ... blocks
  reconciliation"), or any reservation in an effect's **activated** set
  (`effect.reservation_ids`, `protected_primitives.ex:1322`) has status outside
  `consumed released retired`. **(F3)** Enumerating by the activated set, not by owner, means a
  stray `proposed` reservation, which holds no units, cannot block the close forever.
- Writes one `root_attempt_closures` row keyed `(ticket_id, attempt_id)`; a second close is
  idempotent on an identical fact and refused otherwise.
- **`create_effect` refuses** `attempt_closed` for a closed `(ticket_id, attempt_id)`. Without
  this the closure is not terminal: a later effect would reopen R5 accounting under a settled
  attempt. The review checked every other path (`reclaim_claim`, `issue_claim`,
  `first_settlement`, predecessor chains, `reset_generation`); none creates work under a closed
  attempt once `create_effect` refuses.
- **(F2) The closure is a ledger fact, not a claim that no receipt can ever arrive.** R5 requires
  a conflicting late receipt to quarantine its owner (`quarantine_conflicting_receipt`,
  `:1982-1997`), which can move a closed attempt's `succeeded` effect to
  `reconciliation_required`. That must still happen; refusing the receipt would break R5. It
  moves no units, so `attempt_settlement`'s totals stay true. The fact therefore means "the
  attempt's ledger was closed at this sequence", and quarantine after close is reconciliation
  work, not a reopened attempt.
- Result fact `attempt_settlement`: `schema_version scope ticket_id attempt_id effect_ids`
  (sorted) and per-dimension `consumed`/`released` totals. No role, no disposition.

Producer `"terminal_settlement_v1" => {"close_attempt", "attempt_settlement"}`; new slot
`"attempt_settled.settlement" => {"attempt_settled", "settlement", "terminal_settlement_v1"}`.
Kernel side: `attempt_settled` requires `payload.settlement.ticket_id/attempt_id` to equal the
payload's. The kernel's own "which disposition" guards are unchanged.

**Explicitly not covered:** `integrated` still rests on the caller-supplied `ref_receipt_id`
(O0 U3). Acceptance/promotion needs its own protected producer under FR-13/FR-14. The attempt
fact proves the ledger closed, not that the work was accepted.

**Objective-scoped work later.** The key is `(scope, attempt_id)` with scope checked against
the effect's own column, so when an objective scope becomes admissible (U9, deferred with the
PM lifecycle) PM planning attempts close through the same operation unchanged.

**Built 2026-09-23, two departures from the reviewed text.** (1) The closure table needs a
protected schema **v3 migration**: adding it to the current table set would make every v2 store
read as partial state and refuse to open, so v2 stores gain it additively on open
(`migration_attempt_closure_v3`), with a direct v2→v3 test. (2) A second close of a closed
attempt is **refused** (`attempt_closed`) rather than idempotent on an identical fact; command
idempotency already covers a retried command, and refusing is the stricter reading. Replay
records ticket and attempt on each effect, replays closures, refuses a replayed
`create_effect` under a closed attempt, and requires the table to equal the replayed set.

## Item 2 — `reset_fact_v1` producer

`"reset_fact_v1" => {"reset_generation", "new_generation"}`. `reset_generation`
(`protected_primitives.ex:1179`) already returns `new_generation` as the fresh ledger's public
fact and is role-free.

**(F4) Settled by review: one ticket reset spans several ledgers.** Ledgers are keyed
`(ledger_id, generation)` with `dimension` a column, and a ticket has one ledger per dimension.
R5's reset is per ledger generation (contract:595-602) while R4.25 is one ticket transition
granting "eligible units" (contract:488). So `ticket_reset.generation` binds a **non-empty list**
of `new_generation` facts, one per `reset_generation` in the bundle. The kernel holds no ledger
ids, so its check is ticket-agnostic: every fact's `generation` equals the payload's. Naming
which ledgers belong to a ticket would need a Core convention that does not exist, and is not
added here.

**Found while building it (2026-09-23): no accepted plan could reach any slot but a
settlement.** `validate/1` requires an accepted plan to name a discriminator, and the only kind
was `infrastructure_limit_v1`, which needs a non-start settlement. So `ticket_reset`, every
`*_planned.authority` and `control_changed.control` were producible but undeliverable; the
coverage test for admission slots called `derive_outputs/2`, never `bind/3`, and could not see
it. Fixed with `unconditional_v1`: exactly one alternative, named `"unconditional"`, selected by
Gateway without derivation and reconstructed as itself on revalidation. Item 1's
`attempt_settled` plans use it too. Built at the commit that follows this note, with an
end-to-end ticket reset through Gateway.

## Item 3 — settlement binds the execution it closes (B3 item 4)

`bind/3` fills `*_settled.settlement` from `settle_claim`'s `infrastructure_settlement`, whose
fields (`protected_primitives.ex:226-236`) name `effect_id` and `work_owner` but not
`execution_id`. Today nothing checks that the settlement belongs to the execution the event
names, so a settlement for execution A can close execution B.

**Design.** In `TransitionPlan.bind/3`, for every settlement slot: the same bundle's
`settle_claim` result also carries `"effect" => public_effect(effect)`; require
`settlement.effect_id == effect.effect_id` and `effect.execution_id ==` the event payload's
`execution_id` (and `ticket_id`/`attempt_id` likewise). Refuse `settlement_execution_mismatch`.
Identity only: which *role* an execution has stays a kernel check (`close_execution`'s allowed
roles), so no role name enters Core. Verified by review: every `settle_claim` branch returns
`public_effect`, which carries `execution_id` (`:3495`), and `markers_occupy_declared_slots`
already locates the carrying event. Scope: `nonstart_settlement_v1` slots only;
`attempt_settled.settlement` has no `execution_id`. **`pm_launch_settled`** (payload
`objective_id settlement`, no `execution_id`) is unreachable today (U9) and **fails closed**
rather than skipping the check.

## Item 4 — non-start after a policy revision (B3 item 5, Q5)

Per the approved Q5 reading: a proved non-start still settles after a policy revision, and the
**retry** is refused at the claim.

**(F1) Corrected by review.** There is no policy check on the settle path to move, and
`claim_effect` (`:1377`) and `issue_claim` (`:1435`) already compare revisions. The strand is in
`infrastructure_discriminator/3` (`:374`, `policy.revision == effect.policy_revision`). The
change: **drop that head-revision compare, and read the limit from the effect's own revision
via the existing `infrastructure_discriminator_at_revision/3` (`:330`, reads
`root_policy_history`)**. Reading the head instead would strand again whenever a revision drops
the role's limit (`:infrastructure_limit_undecidable`), and `gateway.ex:1218-1221` says the value
cannot be recomputed later. No retry path opens: a retry is a new `create_effect`, which checks
current policy (`:1282`), and `nonstart_allowance` counts prior non-starts regardless of revision
(`:3140-3146`). The test that flips is `atomic_bundle_test.exs:1097`. Role-free.

## Evidence each item ships with

Each guard gets a red control (remove the guard, the named test fails), per
[evidence tools](../EVIDENCE-TOOLS.md) rule 1. Item 1's tests: close refused with one
`unknown` effect, with one `reserved` reservation, accepted when all terminal, and
`create_effect` refused after close. Item 3: a settlement from execution A offered to execution
B's slot is refused. Re-attestation of the protected files follows the gate.

## Questions put to the reviewer (answered above)

1. Is `close_attempt` the right Core shape for "every owned claim terminal", or does the
   contract place this fact elsewhere?
2. Item 2's multi-dimension question.
3. Is refusing `create_effect` after close sufficient to make closure terminal, or is there a
   second path (reclaim, predecessor chains) that creates work under a closed attempt?
4. Anything here that bakes controller or role topology into Core.
