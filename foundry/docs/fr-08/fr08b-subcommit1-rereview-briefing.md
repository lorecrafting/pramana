# FR-08B subcommit 1 — correction re-review briefing

Date: 2026-09-20

Reviewer: a **fresh** Claude Fable 5.1 session, independent of the implementer and of the
first reviewer. Not a fork.

Candidate: `40ac559` on `repair/fr08b-kernel`. Review `git diff be1e19c 40ac559`.

## Why this is a full review of the corrections, not a narrow one

The repair plan escalates a narrow re-review when the correction touches a different file
or invariant family than the reported defect, or when a previous correction for that defect
already failed review. **Both conditions are met.** The corrections changed the state shape,
the execution addressing used by every closure path, eleven guards, the reachability prober
and four properties. A narrow pass scoped to eight findings would not see what that moved.

Out of scope even so: FR-08A, `decide/3`, the R4a control/allocation product, the durable
vocabulary extension, and `terminal_settlement_v1` / `reset_fact_v1`.

## What to read, and one paragraph to disregard

[WORKFLOW-CONTRACT.md](../WORKFLOW-CONTRACT.md) **§R4 and §R4a** — the transition rows, the
entity state vocabularies and the non-start recovery table. That is the authority.

**Disregard the R3 paragraph "Observability is not authority".** It was added by an
implementer in the same session as code written against it, is marked in the contract as
not independently reviewed, and proves nothing about this candidate. Judge against revision
3's R4/R4a rows.

Then: [the first review's findings](fr08b-subcommit1-review-findings.md) — the eight
blockers and eleven lesser findings this candidate answers — and
[the correction design](fr08b-subcommit1-correction-design.md), which states the diagnosis
the corrections were built on. Do not read the full plan, history or tutorial.

## Settled facts — supplied as given, do not re-derive

Spot-check any and say so; re-establishing them as routine is waste.

- **Full model-free suite: 791 passed, 13 skipped at seed 0**, run serially with a fresh
  `MIX_BUILD_PATH`. That is the previously reported 776 plus exactly the 15 tests added.
- **Kernel suites**: 42 table tests, 13 properties, 55 at seed 0.
- `foundry/bin/preflight.sh` passes: committed tree clean, forced compile with
  warnings-as-errors, formatting, quiet machine, real TMPDIR.
- **Non-vacuity was verified for all eight new guards**, one at a time: each was
  neutralised and exactly the intended tests failed, then reversed by exact string
  replacement. The pairs are `require_settlement_source` (3 tests),
  `require_check_unsettled` (1), the `unknown` lifecycle rule (1),
  `require_receipt_for_integration`'s converse (1), `review_settled`'s reviewer binding (1),
  `require_resume_phase` (1).
- **FR-08A attestation is untouched**; no file it pins is modified.
- **No existing module references the kernel.** It still has no callers.

Do **not** ask for another full suite run. Concurrent runs produce spurious physical-fault
failures.

## What to review, in priority order

### 1. Did the corrections fix the rows, or only the counterexamples?

This is the question the first review answered "no" to for correction 3 of `202b8e4`. For
each of the eight blockers, the test now asserts the corrected behaviour — but a guard that
refuses the reviewer's exact sequence and still cannot express R4's row is the same defect
wearing a regression control. Judge each against the row text.

Particular attention to `require_settlement_source/2`: it assigns each of the nine
dispositions a source row, and those assignments are an interpretation of R4 that nobody
has checked. `exhausted` is deliberately left unguarded, on the argument that every row
producing it turns on allocation, which is protected policy the kernel may not restate. Is
that right, or is it a hole?

### 2. Does the new state shape actually serve R4a, and did changing it break custody?

Executions are now addressed by the attempt that owns them rather than through
`active_attempt_id`. That touches every closure, settlement and observation path. The
question is whether custody survived: can an execution now be closed by an event that
should not reach it, can a settled attempt be mutated, can closure on a terminal ticket
resurrect anything?

Ordinals are now per role on the work owner, with objectives carrying the PM ordinal. Check
the decomposition against R4a's `(role, work_owner, ..., infrastructure_attempt_ordinal)`
record and its "per role and work owner" sentence — including whether `generation` belongs
on the owner rather than per role, which is the design's claim.

### 3. Is the new evidence honest?

`@known_unreached` is now empty and a variant-level ratchet was added with one entry. The
previous ratchet rested on a claim measurement showed to be false, so this one deserves the
same hostility.

- Is the empty type-level set real, or does it depend on the prober having been widened
  until it was true? The prober gained successor-ticket admission and many new variants in
  the same commit as the kernel guards — the same both-sides-moved pattern that produced
  finding 9.
- The single variant entry, `cancellation_finalized:after_integration`, is justified by a
  table test that drives the row in sixteen events. Verify that test actually reaches the
  row rather than something adjacent.
- `KernelWalk.variants/0` declares the variant universe from the contract's vocabularies
  with one stated exclusion (`execution_observed:closed`). Is that exclusion right, and is
  the universe complete?

### 4. New circularity

The first review confirmed circularity on `ticket_parked` and cleared `role_execution/2`.
The park proposal now offers fixed R4-derived targets. Look for the same pattern elsewhere,
especially wherever a proposal and a guard changed in this one commit.

## Recorded non-goals, unchanged

The kernel **records** worker closure rather than verifying it; verified termination is
owned by FR-10. The 22 new types still cannot be persisted. One new prerequisite is
recorded: `ticket_resumed` collides with `RecordCodec`'s legacy vocabulary, which raises at
compile time, and that blocks subcommit 2's codec extension.
