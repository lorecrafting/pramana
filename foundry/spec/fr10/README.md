# FR-10 Quint model: effects, claims, receipts and reconciliation

[`effects.qnt`](effects.qnt) is commit 0 of
[the FR-10 design](../../docs/fr-10/FR10-DESIGN-2026-09-23.md). It models the protocol **as
designed** (D1–D5 plus the operator's answers Q2–Q4), not today's code. Each store action
cites the protected operation it models in
`foundry/lib/pramana_foundry/durable_store/protected_primitives.ex` (`PP:<line>`, lines at
`33395c92`). The scope follows design §7: one ticket and attempt, and one semantic operation
with ordinal 0 (E0) and its retry, ordinal 1 (E1). There are two writer epochs, and each
effect has one reservation of one unit on a two-unit ledger. Failures injected: a
Gateway/Coordinator crash that starts a new epoch while the old worker may survive, a hard
kill of either epoch's worker, delivery from an old-epoch worker, and receipts that are
duplicated, reordered, late or dropped. There are also conflicting observations: the same
receipt id with a different digest.

**Found (details in [Findings](#findings)):**

- **A:** the D3 non-start evidence can release a unit whose launch is still in the delivery
  channel.
- **B:** a late timeout receipt from an old worker re-quarantines an effect that has already
  settled. This is today's code, not only the design.
- **C:** the design does not say what happens to a live retry when its predecessor is
  quarantined.
- **D:** the design's I5 text contradicts `close_attempt`.

## How to run

Node is required; Quint 0.32.0 was used. Run from this directory:

```sh
npx @informalsystems/quint typecheck effects.qnt
npx @informalsystems/quint test effects.qnt          # the four witness runs
npx @informalsystems/quint run effects.qnt --step=<variant> --invariant=<I1..I9|allInvariants> \
    --max-steps=30 --max-samples=20000 --seed=1       # random simulation
```

`quint verify` (Apalache) was **not** run, because this machine has no Java runtime ("Unable
to locate a Java Runtime"). No result below is exhaustive. Liveness ("every issued claim
eventually leaves issued") is not checked, because `quint run` checks only state invariants.

## Variants

The actions are shared. The variants differ only in a flag record passed to `stepV`.

| `--step` | D3 evidence | Stale `unknown` after a known outcome | 69614867 guard | Conflicting observations |
|---|---|---|---|---|
| `step` | as designed: issuer gone **or** channel quiet | quarantines (code) | on | injected |
| `stepDesignHonest` | as designed | quarantines (code) | on | none |
| `stepFixed` | F1: issuer gone **and** channel quiet | F2: absorbed | on | none |
| `stepFixedAdversary` | F1 | F2 | on | injected |
| `stepQ3Bug` | F1 | F2 | **off** (red control) | injected |

F1 and F2 are the corrections this model proposes. They are not in the design.

## Invariants

| | Meaning |
|---|---|
| I1 | At most one external start per claim and per semantic (generation, ordinal). No retry is live, meaning started or in the channel, while its predecessor is live: no blind relaunch |
| I2 | `available + held + consumed = 2`, and `held` and `consumed` match the reservation statuses |
| I3 | A `released` reservation means its external action never started |
| I4 | Each reservation reaches a terminal settlement at most once |
| I5 | An `unknown` or `reconciliation_required` claim with no known outcome keeps its unit held. The design's wording is narrowed; see finding D |
| I6 | A live retry (`pending`, `claimed` or `issued`) has a terminal predecessor |
| I7 | A delivered receipt, from any epoch, changes only its own claim |
| I8 | After `close_attempt`, every execution is `closed` and no external action is pending or running |
| I9 | Added for Q3: a claim leaves `reconciliation_required` only through the explicit recovery operation |

## Results (2026-09-23)

Random simulation used `--max-steps=30 --max-samples=20000 --seed=1` for each invariant.
Every sample ran the full 31 states, because a `stutter` step lets a step draw its nondet
picks again. "ok" means no violation was found in the samples; it is not a proof.

| Invariant | `step` | `stepDesignHonest` | `stepFixed` | `stepFixedAdversary` | `stepQ3Bug` |
|---|---|---|---|---|---|
| I1 | ok (random); **violated** (witness `blindRelaunchTest`) | **violated** | ok | ok | ok |
| I2 | ok | ok | ok | ok | ok |
| I3 | **violated** | **violated** | ok | ok | ok |
| I4 | ok | ok | ok | ok | ok |
| I5 | ok | ok | ok | ok | ok |
| I6 | **violated** | **violated** | ok | **violated** | **violated** |
| I7 | ok | ok | ok | ok | ok |
| I8 | **violated** | **violated** | ok | ok | ok |
| I9 | ok | ok | ok | ok (random, also 200k samples at seed 7); **violated** (witness `q3RedControlTest`) |

`stepFixed` also passes `--invariant=allInvariants --max-steps=40 --max-samples=200000
--seed=11`: no violation found in 311 s.

`quint test` passes all four witness runs:

- `q3RedControlTest`
- `q3GuardHoldsTest`
- `blindRelaunchTest`
- `channelEvidenceHoldsTest`

## Findings

**A. The D3 evidence does not prove channel quiescence.** D3 accepts **either** (a) the
issuer's epoch is fenced and its OS identity is gone, **or** (b) the backend reports no
start. Disjunct (a) proves only that the issuer is quiet. A delivery the dead worker
already handed to the channel can still start. Disjunct (b) alone ignores a live issuer
that has not dispatched yet. R1 requires both conditions: "the old worker **and** delivery
channel cannot still perform it" (`WORKFLOW-CONTRACT.md:353-354`). The shortest
counterexample, for I8, came from an earlier `stepDesignHonest` run at seed 1. It runs:

1. create → claim → issue E0
2. dispatch into the channel
3. crash (epoch 1)
4. kill both workers
5. `recoverySettle(0)` settles `non_started` on (a): the unit is released and the
   execution closes
6. `closeAttempt` succeeds while E0's delivery is still in the channel

The I3 trace continues to `externalStart(0)` on a `released` reservation.
`blindRelaunchTest` goes on to create, claim, issue and dispatch the retry E1 before E0
starts, so two launches run. **Fix F1:** require (a) **and** (b). Under F1 the same path
settles `unknown` and keeps the hold (`channelEvidenceHoldsTest`).

**B. A late `unknown` receipt re-quarantines a settled effect (today's code).**
`settle_with_receipts` quarantines any non-exact receipt when a known outcome is already
stored. An `unknown` receipt carries less information, not conflicting information
(`PP:1911-1916`). The counterexample below came from an earlier run (`stepDesignHonest`, I6, 300k samples,
seed 7); the 20k-sample run finds the same class of path:

1. The epoch-0 worker dispatches and emits a timeout `unknown` receipt. The receipt stays
   in flight.
2. Both workers die, and the action runs and fails.
3. The recovery principal settles E0 `failed` from the backend observation.
4. The retry E1 is created.
5. The stale `unknown` arrives. E0 goes `failed` → `reconciliation_required`.

E1 can then never be claimed or issued (`predecessor_current?` at `PP:3463-3486`), and
the attempt can never close. Only operator recovery, which Q3 requires, gets it out. A
routine timeout-then-outcome reordering needs a human. **Fix F2:** store a stale `unknown`
and leave the status unchanged. F2 is not a fix for conflicting known outcomes.

**C. Nothing defines what quarantining a predecessor means for its successor.** A genuinely
conflicting observation (R5) can quarantine E0 after E1 exists (`stepFixedAdversary`, I6).
The code allows this deliberately (the `close_attempt` comment, `PP:1553-1558`). The design
says nothing about the live retry: whether it is blocked, cancelled or allowed to proceed.
I6 as written in §7 cannot hold. This is an open design question; the model does not
answer it.

**D. The design's I5 is too strong.** §7's I5 says a quarantined claim keeps its unit held.
A claim that settled and was then quarantined had already moved its unit, and quarantine
moves no units (`PP:2001-2016`). I5 is therefore narrowed to claims with no known outcome.

**Design silences the model had to fill** (each is marked `ASSUMPTION` in the source):

- D1 does not map `failed` to an execution state. The model uses `running`, which needs
  termination evidence to close.
- D1 does not say whether a settlement may reopen a `closed` execution. The model assumes
  it never does.
- D1 does not say what `cancel_effect` does to the execution. The model closes it.
- §7's I6 omits `succeeded` as a legal predecessor, but `predecessor_guard` accepts it
  (`PP:3454`). The model follows the code.

## Red control

The known-bad variant is `stepQ3Bug`: F1, F2 and conflicting observations, with the
69614867 guard (`PP:1907-1908`) switched off. Random simulation did not reach its 11-step path, even at 200k samples. The
witness `q3RedControlTest` drives the path deterministically. To show the
failure, its expectation was temporarily changed to `.expect(I9)` and the test was run.
The change was then restored.

```text
$ npx @informalsystems/quint test effects.qnt --match=q3RedControlTest
    1) q3RedControlTest failed after 1 test(s)
       Error [QNT508]: Expect condition does not hold true
error: Tests failed
```

The trace, exported with `--out-itf`, runs:

1. create → claim → issue E0
2. dispatch
3. The worker emits `unknown`, and it settles: E0 is `unknown`.
4. A conflicting observation quarantines E0.
5. The action starts and succeeds, and the worker emits `succeeded`.
6. The receipt is delivered. `reconciled_settlement` runs because the stored history is
   unknown-only: E0 becomes `succeeded`, the unit is **consumed**, and `quarantined` is
   still set. **I9 is violated.**

With the guard on, the same path re-quarantines with the unit held (`q3GuardHoldsTest`).
With the expectation restored, all four witness runs pass.

## Not modelled

- Policy and control revisions and `fence_control_descendants`.
- Ledger generations and closure (`reservations_open?`) and `retired`.
- Leases, beyond the hold/release that follows the reservation.
- Process termination after a `running` execution.
- More than one crash.

Each is a candidate extension if commits 2–5 touch it.
