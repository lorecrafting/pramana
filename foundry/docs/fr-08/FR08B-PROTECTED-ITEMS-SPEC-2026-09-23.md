# FR-08B protected items: attempt close, reset fact, settlement binding

**Date:** 2026-09-23. **Type:** design spec, **awaiting independent review** before any code.
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
  reconciliation"), or any of their reservations has status outside
  `consumed released retired`.
- Writes one `root_attempt_closures` row keyed `(ticket_id, attempt_id)`; a second close is
  idempotent on an identical fact and refused otherwise.
- **`create_effect` refuses** `attempt_closed` for a closed `(ticket_id, attempt_id)`. Without
  this the closure is not terminal: a later effect would reopen R5 accounting under a settled
  attempt.
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

## Item 2 — `reset_fact_v1` producer

`"reset_fact_v1" => {"reset_generation", "new_generation"}`. `reset_generation`
(`protected_primitives.ex:1179`) already returns `new_generation` as the fresh ledger's public
fact and is role-free. Kernel `ticket_reset` checks the fact's `ledger_id` names the ticket's
ledger and its `generation` is the payload's.

**Open question for review:** ledgers are keyed `(ledger_id, generation, dimension)`. If one
ticket reset spans several dimensions it is several `reset_generation` operations, and a single
slot binds one. Either the slot binds a list, or R4's reset row is per-dimension. The reviewer
should say which the contract reads.

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
roles), so no role name enters Core. To verify in implementation: that `public_effect/1`
includes `execution_id`; if not, add it to the public fact rather than to the settlement.

## Item 4 — non-start after a policy revision (B3 item 5, Q5)

Per the approved Q5 reading: a proved non-start still settles after a policy revision, and the
**retry** is refused at the claim. Today the fail-closed check sits on the settlement path, which
strands the non-start. Move the policy-revision comparison from settlement to
`claim_effect`/`issue_claim` for effects created under the superseded revision. Role-free.

## Evidence each item ships with

Each guard gets a red control (remove the guard, the named test fails), per
[evidence tools](../EVIDENCE-TOOLS.md) rule 1. Item 1's tests: close refused with one
`unknown` effect, with one `reserved` reservation, accepted when all terminal, and
`create_effect` refused after close. Item 3: a settlement from execution A offered to execution
B's slot is refused. Re-attestation of the protected files follows the gate.

## Questions for the reviewer

1. Is `close_attempt` the right Core shape for "every owned claim terminal", or does the
   contract place this fact elsewhere?
2. Item 2's multi-dimension question.
3. Is refusing `create_effect` after close sufficient to make closure terminal, or is there a
   second path (reclaim, predecessor chains) that creates work under a closed attempt?
4. Anything here that bakes controller or role topology into Core.
