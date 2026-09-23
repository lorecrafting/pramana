# Option 2 without reopening O1's timing: build FR-08B's protected items role-agnostic

**Date:** 2026-09-23. **Type:** proposal, **approved by the operator 2026-09-23** (all three decisions below, as
recommended). Taken at `57e41229` (`repair/fr08b-kernel`). Changes no contract text.

## What was asked, and the conflict in it

On 2026-09-23 the operator chose "option 2": move to the
[orchestrator adapter boundary](../ORCHESTRATOR-BOUNDARY.md), with the FR-08B kernel as the default
controller and no new guards except correctness fixes. That choice was framed without the
2026-09-22 operator-approved timing recorded under O1: **begin O1 only after FR-08B lands**, because
the [O0 inventory](O0-AUTHORITY-INVENTORY-2026-09-22.md) §1 found the kernel has no production caller
and the live coordinator never calls `Gateway`. An adapter built now would wrap code FR-08B is about
to rewire (O0 §6 seam 5: "O1's local reference adapter has nothing to wrap").

This proposal keeps that timing and reads option 2 as the part of the boundary work that does **not**
wait for FR-08B.

## The reading

[PR #49](https://github.com/lorecrafting/pramana/pull/49) ([planning strategies §2, §3.1, §11](../PLANNING-STRATEGIES.md))
merged the same morning and points the same way: composable workflow primitives, LLM-proposed
work and replaceable methodologies are post-repair (issues #47/#48, roadmap I-F3/I-F5), and its
design test is "if replacing the planning methodology requires invasive changes to the authority
ledger, the boundary is probably too coupled". Role names in Core fail that test; the items below
stop adding to the failure without refactoring what exists.

1. **The kernel is already the Standard Controller's layer.** R3 puts the workflow kernel under
   "autonomous exact-candidate repair", above the protected verifier; the boundary doc's
   "Default Foundry workflow kernel remains useful" and "Initial workflow is retained, then
   factored" keep it. Its role-named events (O0 §3.1) are controller vocabulary and may stay.
2. **The topology problem is in Core** (O0 §3.2): role-named slots, role budget dimensions, a
   role whitelist on non-start settlement, and every effect scoped `ticket:attempt:role`. The
   boundary doc says not to build "controller-specific state into the protected schema".
3. **Everything now blocking FR-08B is a Core change.** Subcommit 3 needs `terminal_settlement_v1`
   and `reset_fact_v1` producers (`transition_plan.ex:48` has neither); B3 still owes the
   settlement-to-execution/role check at bind and non-start settlement after a policy revision.
   All four are protected code, operator maintenance under R3, and all four will be written
   whichever option is chosen.

So the cheapest time to stop adding role topology to Core is while those four are written. Option 2
becomes: **write FR-08B's four protected items against execution identity, not role names, and add
no new role-named protected vocabulary.** O1 (the adapter itself) still starts after FR-08B lands.

## Scope of the first candidate, if approved

| # | Item | Role-agnostic form |
|---|---|---|
| 1 | `terminal_settlement_v1` producer | Bound from the protected operation that closes an execution, keyed by `execution_id`; no role in the producer. Which operation's result is authoritative is to be specified first (O0 U3) |
| 2 | `reset_fact_v1` producer | From `reset_generation`'s result; already role-free in `@operation_types` |
| 3 | Settlement binds to the execution it closes (B3 item 4) | `bind/3` compares the settlement's execution/effect/work-owner facts to the event's execution id; role follows from the execution, not from the event name (proposal Q4 reading, medium confidence on `TransitionPlan` as the home) |
| 4 | Non-start settles after a policy revision (B3 item 5, Q5) | Refuse the retry at the claim, not the settlement; no role branch |
| 5 | Probe U9 before 1–4 | Build an objective-scoped `create_effect` against the protected layer and record whether it is admissible. Answers whether PM executions can be generic at all, and costs one test |

**Explicitly not in scope:** renaming existing role-named slots or budget dimensions (a Core refactor
with attestation churn and no current consumer; that is O4 territory after a second controller
exists), the adapter, the CLI client, and any kernel event rename.

**Review:** one independent Fable review of the candidate, briefed on the delta per the repair
plan's review rules, plus the contract-row walk for the R4/R4a rows the producers bind.

## Decisions (approved 2026-09-23)

1. This reading of option 2 is accepted: O1 stays after FR-08B.
2. Items 1–5 are authorized as operator maintenance on protected files (`transition_plan.ex`,
   `gateway.ex`, `protected_primitives.ex` as needed), with re-attestation. U9 (item 5) goes first.
3. The planned `kernel.ex` split by event family (repair plan, Batch C) cuts along the
   generic/software line: execution lifecycle, settlement, control and cancel families in generic
   modules; developer/review/integration phases in software-specific ones. No definition format or
   DSL; full mechanism/definition extraction waits for a second workflow, per
   [the seam note](../fr-08/workflow-definition-seam.md) and PR #49.
