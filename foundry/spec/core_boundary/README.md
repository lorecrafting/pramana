# Core boundary model: an adversarial controller against Core's guarantees

**Date:** 2026-09-23, at `df1ac5f8`. **Type:** Quint model and one Elixir probe. Neither is a
test in the gate.

The rule under test is "a guarantee Core owns must not depend on a controller checking it"
([O1 sequencing](../../docs/orchestrator/O1-SEQUENCING-PROPOSAL-2026-09-23.md),
[protected items spec](../../docs/fr-08/FR08B-PROTECTED-ITEMS-SPEC-2026-09-23.md)). The Core-owned
list comes from review C3 in
[the decide/3 design](../../docs/fr-08/FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md) and from the
protected items spec.

## Result

**As built, an adversarial controller breaks two Core guarantees: the infrastructure-limit
branch and settlement-to-execution identity.** It also forges two slot facts,
`attempt_settled.settlement` and `launch_planned.authority`. Every other Core guarantee
holds. The hard bounds all hold: a retry past the limit is still refused at `create_effect`,
and no work starts under a closed attempt.

### F1: an unbound non-start commits a literal settlement on the plan path

The fix at `969dcaf4` refuses `unconditional_v1` only when a plan *declares* a
`nonstart_settlement_v1` binding (`transition_plan.ex:382-384`). A plan that stages
`settle_claim(non_started)` and declares **no binding** is still valid:

- `validate_binding_discriminator/1` looks only at the bindings the plan declares
  (`transition_plan.ex:373-391`).
- `markers_occupy_declared_slots/2` walks those same bindings (`:545-603`). So a
  `launch_settled` whose `settlement` is a literal map is never inspected.
- `closes_named_execution?/4` runs once per binding (`:705-718`), so with no binding it never
  runs.
- Gateway picks `"unconditional"` without deriving anything (`gateway.ex:1328-1329`).

The controller therefore chooses the branch (`below` or `reached`, whatever the limit says).
It also chooses the settlement's content and the execution it names. The trace:
`reserve(1)`, `create_effect(1)`, `claim(1)`, `issue(1)`, then one bundle that stages
`settle_claim(1, non_started)` and commits `launch_settled{execution: 2, settlement: <literal
for effect 2>}` (`run unboundBypassTest`). **Reproduced in code:**
`MIX_ENV=test mix run --no-start spec/core_boundary/unbound_nonstart_probe.exs` from
`foundry/` (in a worktree, point `MIX_DEPS_PATH` at the main checkout's `deps`). It prints
`GAP REPRODUCED`: `validate/1` and `bind/3` accept a plan that settles execution-A's effect
while committing a forged settlement for execution-B.

### F2: a proposal-carrier bundle is a second route to the same break

A v2 envelope may carry a precomputed `proposal` instead of a plan. Gateway commits it
verbatim, with no discriminator (`gateway.ex:1294-1295`), next to any staged protected
operations. The codec accepts any payload for a lifecycle event (`record_codec.ex:118-131`).
The existing test `atomic_bundle_test.exs:39` already commits a `settle_claim(non_started)`
this way. The B3 readings flagged this as "read, not run"
(`FR08B-B3-CONTRACT-READINGS-PROPOSAL-2026-09-22.md:281-284`). The model runs it. It breaks
`limitBranchHolds` and `settlementIdentity`, and forges `attempt_settled` for an open attempt
(`attemptSettledIsClosed`) and `launch_planned` for an unissued effect
(`launchPlannedIsIssued`).

**F1 and F2 share a root.** A slot-typed event can carry its slot as a literal. The candidate
fix, modelled as `stepFixed`, has two parts:

1. Every event whose type owns a slot (`transition_plan.ex:76-96`) must fill that slot through
   a declared binding. This generalizes the list-slot rule at `:60-65`.
2. A proposal carrier may not carry a slot-typed event.

Under `stepFixed` every Core invariant that ran held (`limitBranchHolds` and the seven hard bounds); the other slot invariants were cut short, see Checks. The fix is protected maintenance under R3,
so it needs an operator decision. Nothing here changes code.

## Guarantees modelled

| Invariant | Guarantee (C3 / spec) | Checks modelled |
|---|---|---|
| `casCurrent` | revisions/CAS: every committed event's expected ticket revision was current | `gateway.ex:1874-1893`, `:1895-1906` |
| `createdAtCurrentRevisions` | revisions: an effect names the policy and control revisions current at creation | `protected_primitives.ex:1254-1255` |
| `issuedUnderActiveControl` | control status and predecessor currency at issue | `:1347-1356` (claim), `:1405-1413` (issue), `:3171`, `:3473-3494` |
| `allocationConserved` | allocation at `reserve`: units are conserved, never overdrawn | `:1006`, releases at `:1762-1769`, non-start refund |
| `lineageWellFormed` | predecessor currency at creation | `predecessor_guard`, `:3435-3470` |
| `nonstartAllowance` | non-start allowance | `:1257`, `:3203-3228` |
| `closureTerminal` | attempt closure is terminal | `close_attempt` `:1559-1589`, `attempt_open` `:1229`, `:3326-3337` |
| `limitBranchHolds` | the limit branch equals the comparison at the effect's own policy revision | `:332-352`, `gateway.ex:1314-1326`, `transition_plan.ex:382-384` |
| `settlementIdentity` | a settlement names the execution whose effect it settled | `transition_plan.ex:705-718`, `:184-198` |
| `attemptSettledIsClosed` | `attempt_settled` names an attempt Core closed | `terminal_settlement_v1`, `transition_plan.ex:57` |
| `launchPlannedIsIssued` | `launch_planned` names an effect Core issued | `launch_authority_v1`, `transition_plan.ex:55` |

The model's world: one ticket, attempts {1, 2}, effects {1, 2} (effect *e* runs execution *e*),
one start ledger of 2 units, and policy revision 0→1 with the limit going from 2 to 1. Root
control is active or not. The controller's own pause and ticket cancel are separate state
that Core never reads. At every step the adversary picks any protected command or bundle, with
any carrier, discriminator, binding, branch label, execution, and current or stale revisions.
The last three branches of `adversary` are well-formed instances of moves already in the set.
They add no behaviour and only steer the simulator into deep states.

**Controller-side, confirmed not claimed by Core.** `ctlNoLaunchWhilePaused`,
`ctlNoLaunchWhileCancel` and `ctlExhaustedOnlyWhenShort` (pause, pending cancel and the
exhaustion choice) are expected to fail, as C3 says. Pause and exhaustion failed in the runs that completed; see Checks for the rest.

## Checks and bounds

`sh run.sh [samples=200000] [steps=20]` typechecks, runs `quint test`, and simulates every
property under `step` and `stepFixed` with seed 1. Java is not installed here, so Apalache
`verify` did not run. These results are bounded random simulation, not proofs.

**The session ended before the full matrix finished.** The results below come from
`run.sh 200000 20` with seed 1, plus the separate runs noted. Rows marked *not run* were cut
short and must be rerun before anyone relies on them.

| Property | `step` (as built) | `stepFixed` |
|---|---|---|
| `casCurrent`, `createdAtCurrentRevisions`, `issuedUnderActiveControl`, `allocationConserved`, `lineageWellFormed`, `nonstartAllowance`, `closureTerminal` | no violation (200k × 20) | no violation (200k × 20) |
| `limitBranchHolds` | **violated** (F1/F2) | no violation (200k × 20) |
| `settlementIdentity` | **violated** (F1/F2) | *not run* (cut short) |
| `attemptSettledIsClosed` | **violated** (earlier run, 3k × 20) | *not run* |
| `launchPlannedIsIssued` | *not run* at these bounds (3k × 20 found no violation there, too shallow) | *not run* |
| `ctlNoLaunchWhilePaused` | violated (3k × 20), as expected | *not run* |
| `ctlNoLaunchWhileCancel` | *not run* at these bounds (3k × 20 was too shallow) | *not run* |
| `ctlExhaustedOnlyWhenShort` | violated (3k × 20), as expected | violated (3k × 20), as expected |
| `witnessBelow`, `witnessReached`, `witnessClosedWithEffect` | not run | violated = reachable (50k × 15) |
| `witnessRetry` | not run | violated = reachable (200k × 20) |

`quint test` passes both scripted runs. `unboundBypassTest` reproduces F1 deterministically.

The witnesses guard against vacuity. They show that a retry after a non-start, both bound
branches, and a closure over a real effect all occur within the bounds. `run boundSettleTest`
walks the full below → retry → reached → close path deterministically.

## Red controls (EVIDENCE-TOOLS rule 1)

Delete one tagged line in a copy and run the simulation:

- **RED-A**: delete `disc == "limit"` (`transition_plan.ex:382-384`) and run
  `limitBranchHolds` under `stepFixed`. **Violated.** The trace revises the policy to limit 1,
  creates, claims and issues effect 1, then a *bound* `unconditional_v1` plan settles it as a
  non-start with ordinal 1 ≥ 1 and writes `below`.
- **RED-B**: delete `attemptOpen(s, a)` in `createEffect` (`protected_primitives.ex:1229`) and
  run `closureTerminal` under `step`. **Violated.** The trace runs `closeAttempt(1)` on an
  empty attempt, then `createEffect(2, attempt 1)`.

Both are restored in `core.qnt`.

## What the model leaves out

- **One generation.** The discriminator's ordinal counts per infrastructure generation
  (`protected_primitives.ex:208-214`), while the allowance counts every non-start in the
  attempt (`:3211-3224`). After a reset the discriminator can say `below` when `create_effect`
  refuses the retry. The result is a stranded retry, not a safety break.
- **Branch content.** Core selects the alternative *named* by the limit. The contents of each
  alternative are the controller's (`gateway.ex:1284-1293`), so `ticket_blocked` on `reached` is
  controller-side. The hard bound is the allowance.
- **Declared domain reads.** `:domain_read_not_checked` (decide/3 design commit 1) is not
  built at `df1ac5f8`. Only written projections and listed keys are CAS-checked. The model
  checks the ticket projection only.
- **Not modelled:** reclaim, quarantine after close, `cancel_effect` on issued claims, leases,
  multiple roles and objective scope. `required_dimension/2` names roles in Core
  (`protected_primitives.ex:3509-3511`). That is O0 §3.2 debt and out of scope here.
