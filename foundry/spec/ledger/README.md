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

### Fixes (2026-09-23)

Both fixes refuse the operation; neither moves units. The model still describes the code
at `df1ac5f8`, so `HeldOwnerLive` and `RestartValid` still report findings 2 and 3 until
it is updated to match. The probes are in
`foundry/test/pramana_foundry/durable_store/ledger_restart_probe_test.exs`: each drives
the real API to the refused operation, then reopens the database.

- **Finding 2 (5f021010).** `create_effect` refuses reservations on more than one
  `(ledger_id, generation)` with `reservation_ledger_mismatch`, next to the existing
  one-dimension check in `reservation_dimensions`. The other option, releasing the effect's
  other holds when `close_generation` cancels it, would add a held→available path on a
  ledger that was never closed; the contract allows that only on a proved unissued
  cancellation, and the refusal needs no such argument.
- **Finding 3 (5b701a57).** The restart check allows `proposed` only while the owner
  effect does not exist. Two operations broke that, so both are guarded: `create_effect`
  refuses unless it lists every proposed reservation the effect owns, and `reserve`
  refuses with `reservation_owner_exists` when the owner effect already exists.
- **Red controls.** Neutralising each guard in turn fails its probe on reopen:
  `{:protected_corrupt, "root_reservations", :transition}` for finding 2 and
  `{:protected_corrupt, "root_effects", "e1"}` for each half of finding 3.

The reopen property (`reopen_property_test.exs`) then found two more refused states, F1
and F2. Both have probes in the same file and fail them on reopen when their fix is
removed; afterwards `FOUNDRY_REOPEN_RUNS=2000` passes.

- **F1, reset of a delegating ledger (ff526eae).** `reset_generation` closes the old
  generation's delegated subtree, as the contract's R5 requires, but its result carried
  only the reset ledger. The closed descendant had no snapshot, so restart refused it
  (`{:protected_corrupt, "root_ledgers", :transition}`). Refusing the reset while units are
  delegated would contradict R5, so both reset variants now return every closed subtree
  ledger under `ledgers`, as `close_generation` does, and the restart check declares that
  carrier. The child reset had the same omission.
- **F2, a released reservation's owner.** The restart check requires an effect to list
  every reservation it owns in any status, but `create_effect` checked only proposed ones.
  A reservation reserved and then released before its owner existed was left out, and
  restart refused the effect (`{:protected_corrupt, "root_effects", "e1"}`). `create_effect`
  now refuses with `unlisted_owned_reservation` (renamed from
  `unlisted_proposed_reservation`) unless it lists every owned reservation. A released one
  cannot be activated, so that effect id can never be created: fail-closed, and the
  operator question is whether a released reservation should free its owner id.

## Where the code and the contract disagree

- `reserve` moves no units. The contract moves available → held at reservation time; the
  code does it when `create_effect` activates the reservation.
- A root reset does not reduce the old generation's authorized or retired units. It grants
  the new generation up to the old generation's available units as fresh authority.
  `NoUnitsCreated` still holds.
- `return_allocation` also requires the child to have nothing held and nothing delegated.

## Red control

`SEEDED_BUG = true` in `ledger.qnt` makes a root reset refund the old generation's held
units to the new generation. Run 2026-09-23 on a scratch copy with the command in "How to
run" restricted to `--invariant=NoUnitsCreated` (30 steps, 200,000 samples, seed 7):
**violated**, reproducible with `--seed=0x2f40093 --backend=rust`. With `SEEDED_BUG = false`
the same invariant holds (table above), so the check is not vacuous.

## Not completed

The session ended before these ran:

- `HeldOwnerLive` and `RestartValidActivated` were run with 20,000 samples and 25 steps,
  and each stopped at its first counterexample. `RestartValid` ran with 1,000 samples. No
  run was repeated with a larger bound after the invariants were refined.
- Apalache `verify` was not run because Java is not installed.

Independent review of the fixes for findings 1–3 and FR-10 B, including a sibling of the cancel fix: [findings](../../docs/fr-08/ledger-fr10b-review-findings-2026-09-23.md).
