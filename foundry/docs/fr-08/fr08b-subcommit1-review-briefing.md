# FR-08B subcommit 1 — independent review briefing

Date: 2026-09-20

Reviewer: a **fresh** Claude Fable 5.1 session, independent of the implementer. Not a fork.

Candidate: `be1e19c` on `repair/fr08b-kernel`. Base: `main` at `a319b39`.

Review `git diff a319b39 be1e19c`. The commits are `7a08573`, `9d070e8`, `44f7244`,
`346e9bc`, `7094e34`, `202b8e4`, `be1e19c`.

## Scope

Subcommit 1 of [the kernel correction design](fr08b-kernel-correction-design.md): the pure
state and event contract. It answers **B1** of
[the pure-kernel review](fr08b-pure-kernel-review.md) and the reducer-level custody parts
of **B2**. There is no `decide/3` and no plan production; those begin at subcommit 2.
**B4 is discharged** by FR-08A's completion and is not in scope. **B3** is not in scope:
the R4a control and allocation product belongs to `decide/3`.

## Settled facts — supplied as given, do not re-derive

Spot-check any of these and say so, but re-establishing them as routine is waste.

- **Canonical gate passed** at `be1e19c`: `elixir ci/run.exs`, exit 0, all six stages, run
  serially on pinned Elixir 1.20.3 / OTP 29.0.5. Model-free suite **775 passed, 13 skipped,
  1 excluded at seed 0**. Provenance at `foundry/ci-artifacts/provenance.json`.
- **Full suite** outside the gate: 776 passed, 13 skipped at seed 0, serial, fresh
  `MIX_BUILD_PATH`. The gate's 775 differs by its one declared optional exclusion.
- **Kernel suites**: 40 tests at seed 0 (`kernel_test.exs` 30, `kernel_properties_test.exs` 10).
- **FR-08A attestation** is untouched: no file it pins is modified, and `ready=true`, 7 of 7,
  at subject `e491e41`.
- **No existing module references the new ones.** `Workflow.Kernel` has no callers, so no
  current behavior changes.
- **Non-vacuity was verified, twice.** Neutralising `require_workers_closed`,
  `require_developer_closed` and `require_reviewer_stream_sealed` fails exactly three table
  tests, one each. Re-introducing three of the eight walk-found defects fails exactly three
  properties, one each. Both were restored by reversing the edit, not by `git checkout`.

Do **not** ask for a full suite run. The change adds modules nothing calls; it cannot
affect unrelated modules, and concurrent full-suite runs produce spurious physical-fault
failures.

## What to review, in priority order

### 1. The prober's independence from the implementation — the highest-value question

`test/support/kernel_walk.ex` exists to find contract rows the kernel cannot reach. Its
premise is that proposals derive from **R4**, never from the reducer's guards, because a
prober built from the implementation can only reproduce it.

**The implementer tuned the prober and the kernel against each other, in a loop.** Each
time a row came back unreachable, one or the other changed. That is precisely the
circularity the design forbids, and the implementer cannot audit it.

The question to answer is: **was any proposal ever weakened to make a row reachable, where
the honest fix was in the kernel?** Two changes the implementer is least confident about,
offered rather than hidden:

- `role_execution/2` was changed to select only **open** executions of a role. Defended as
  R4 ("closure is terminal, so a settlement naming a closed execution settles nothing").
  Could equally be the prober being taught the implementation's answer.
- `ticket_parked` proposals were changed to use the ticket's **current** phase as
  `resume_phase`, at the same time as the kernel gained `require_honest_resume_target/2`.
  Both sides moved together, which is exactly the pattern to be suspicious of.

Judge these against the R4 text, not against the code.

### 2. Are the properties real, or vacuous?

`kernel_properties_test.exs` asserts laws over seeded walks. A property that passes because
the generator never reaches the interesting state is worse than no property.

- Is `@known_unreached` an honest ratchet, or is it hiding a kernel defect? It records the
  three integration rows as unreached. The implementer's claim is that they sit behind a
  `review_recorded:approved` → `reviewer_closed` sequence that fires about once across every
  walk in the suite — a depth limit, not a block. **That claim deserves testing**, because
  every previous time this was investigated it turned out to be a real defect instead.
- `refute "integrated" in phases` asserts a *negative*. Is that recording a limitation
  honestly, or entrenching one?
- Does the restart property actually prove restart safety? It round-trips state through
  `JSON`, not through the durable codec, because 22 of the 36 kernel event types are not
  yet in `RecordCodec`'s lifecycle vocabulary.

### 3. The eight defects and their corrections

All eight are enumerated in `202b8e4`'s message with the R4 clause each violates. Check
that each correction is the right one rather than the one that made a test pass, and
particularly that the `integration_recorded` / `attempt_settled` split now satisfies R4's
row ("integrated ticket; **terminal integrated attempt**") rather than merely no longer
contradicting itself.

### 4. Contract fidelity of the vocabulary

`fr08b-event-vocabulary-enumeration.md` claims every one of the 36 types is justified by an
R4 row or entity state. It was written to prevent unreachable rows and still missed
`worker_closed` and the settlement `execution_id` asymmetry. Assume it missed more.

## Out of scope

Whole-candidate re-audit of FR-08A; the R4a control/allocation product; `decide/3`; the
durable vocabulary extension; `terminal_settlement_v1` and `reset_fact_v1`, which are
recorded prerequisites for subcommit 3 in the enumeration.

## Recorded non-goals of this candidate

The kernel **records** worker closure rather than verifying it; verified process or session
termination is a protected reconciliation fact owned by FR-10. The 22 new event types
cannot yet be persisted; extending `RecordCodec` gates subcommit 2.
