# R5 budget ledger — Quint model

`ledger.qnt` models the R5 budget ledger as the code implements it
(`foundry/lib/pramana_foundry/durable_store/protected_primitives.ex` at `df1ac5f8`; every
action cites its line). The contract is the "Budget ledger — R5" section of
[the workflow contract](../../docs/WORKFLOW-CONTRACT.md). Where the code and the contract
disagree, the model follows the code and marks the spot `DISAGREE`.

Bounds: a root → objective → ticket tree, two generations, one dimension, 1–2 units per
operation, two reservations, two effects. Modelled operations: `grant_ledger`,
`delegate_allocation`, `return_allocation`, `reserve`, `release_reservation`,
`create_effect` (activation), `claim_effect`, `issue_claim`, `cancel_effect`,
`settle_claim` (succeeded, failed, non_started, unknown, exact duplicate, conflicting and
foreign receipt ids, re-quarantine), `close_generation`, root and child `reset_generation`,
and `close_attempt`.

## How to run

Java is not installed, so Apalache `verify` was not run. All results below come from random
simulation with Quint 0.32.0 and the Rust backend:

```sh
cd foundry/spec/ledger
npx @informalsystems/quint typecheck ledger.qnt
npx @informalsystems/quint run ledger.qnt --backend=rust \
  --invariants PerNodeConservation NoNegative TreeConservation DelegatedMatchesChildren \
               HeldBacked NoUnitsCreated ClosedNeverGains \
  --max-steps=30 --max-samples=200000 --seed=7
npx @informalsystems/quint run ledger.qnt --backend=rust --invariant=QuarantineKeepsHeld \
  --max-steps=25 --max-samples=50000 --seed=1
```

## Invariants and results

| Invariant | Meaning | Result |
|---|---|---|
| `PerNodeConservation` | authorized = available + held + consumed + delegated + retired | holds (200k samples, 30 steps, seed 7) |
| `NoNegative` | no balance below zero | holds (same run) |
| `TreeConservation` | root authorized = Σ available+held+consumed+retired over the tree | holds (same run) |
| `DelegatedMatchesChildren` | the code's restart check `validate_ledger_tree` | holds (same run) |
| `HeldBacked` | held and consumed equal their reservations (`validate_reservations`) | holds (same run) |
| `NoUnitsCreated` | Σ available+held+consumed ≤ units granted; reset, return and close create none | holds (same run) |
| `ClosedNeverGains` | a closed generation has no availability and fixed authority | holds (same run) |
| `QuarantineKeepsHeld` | a claim quarantined while holding units keeps them held | **violated** (finding 1) |
| `HeldOwnerLive` | a held reservation's owner can still settle or cancel it | **violated** (finding 2) |
| `RestartValidActivated` | the code's restart check (`reservation_statuses`) on activated reservations | **violated** (findings 1 and 2) |
| `RestartValid` | the same check on every reservation | **violated** (finding 3) |

The per-node write guard `conserved?` is left out of the model on purpose, so the
conservation invariants test each action's arithmetic.

## Findings in the code

1. **A quarantined claim loses its hold when its generation closes.** Trace (seed 1, 25
   steps): e1 is claimed, issued and settled `unknown`. e2 is created on `obj/1` and claimed,
   but not issued. A `settle_claim` for e2 reuses e1's `receipt_id`. `observation_conflict?`
   (PP:1595) runs before any check on the claim's status, so it quarantines the
   **claimed, unissued** claim while its reservation is still `reserved`. Then
   `close_generation obj/1` runs: `revoke_unissued_generation` (PP:1689) releases every
   `reserved` reservation, whether or not its claim is quarantined, and
   `cancel_unissued_effect_owners` skips the `reconciliation_required` effect. The units go
   held → available → retired. The quarantine itself leaves a state that fails the restart
   check: `reservation_statuses` (PP:7584) expects `issued_unknown` for a quarantined claim
   with no receipts. Quarantining a `cancelled` claim the same way also fails the restart
   check.
2. **Closing one ledger strands another ledger's hold.** Trace (seed 1): e2 is created with
   r1 on `root/0` and r2 on `root/1`. `close_generation root/1` releases r2 and cancels e2.
   r1 stays `reserved` and holds units on `root/0`. No operation can release it:
   `release_reservation` and `cancel_effect` both refuse a cancelled owner. It is released
   only when `root/0` closes. Until then the restart check fails (a cancelled owner allows
   only released or retired reservations). `reservation_dimensions` (PP:3498) is the only
   check on which ledgers an effect's reservations may use, and it checks the dimension, not
   the ledger. The same trace works with `obj` and `tkt`.
3. **A proposed reservation owned by an existing effect fails the restart check.** Trace
   (seed `0x8e44`, 5 steps): r1 and r2 are reserved for e1, then `create_effect e1` lists
   only r1. r2 stays `proposed` under a `pending` effect, which the restart check rejects
   (PP:7575). `reserve` (PP:998) never checks the state of its owner.

The restart check is `ProtectedPrimitives.validate`, which runs when the database opens
(`database.ex:467`), not after each command. Each state above commits, and then the store
refuses to reopen. None of the three findings breaks numeric conservation.

## Where the code and the contract disagree

- `reserve` moves no units. The contract moves available → held at reservation time; the
  code does it when `create_effect` activates the reservation.
- A root reset does not reduce the old generation's authorized or retired units. It grants
  the new generation up to the old generation's available units as fresh authority.
  `NoUnitsCreated` still holds.
- `return_allocation` also requires the child to have nothing held and nothing delegated.

## Not completed

The session ended before these ran:

- The required red control has not been run. `SEEDED_BUG = true` in `ledger.qnt` makes a
  root reset refund the old generation's held units to the new generation. It is expected
  to fail `NoUnitsCreated`, but no run has shown that.
- `HeldOwnerLive` and `RestartValidActivated` were run with 20,000 samples and 25 steps,
  and each stopped at its first counterexample. `RestartValid` ran with 1,000 samples. No
  run was repeated with a larger bound after the invariants were refined.
- Apalache `verify` was not run because Java is not installed.
