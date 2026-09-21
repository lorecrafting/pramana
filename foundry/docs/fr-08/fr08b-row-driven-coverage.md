# Driving R4's rows — design

Date: 2026-09-20

Supersedes the guard-by-guard method used for `be1e19c` and `40ac559`, both of which were
blocked by independent review.

## Why the method changed, not just the code

Two independent reviews, two BLOCK verdicts, and the same finding shape both times: a guard
refuses the counterexample the previous review reported, while the row it claims to
implement still cannot be driven. The second review put it exactly — "the correction fixed
the eight counterexamples; it did not fix the rows."

That is not two unlucky passes. Hand-writing one guard per event from a prose table has no
step that ever asks whether a row can be driven, so a guard written to stop a
counterexample and a guard derived from a row are indistinguishable by construction. Both
times the gap was found by a reviewer reading prose against code, because that was the only
mechanism capable of finding it — the table tests ask what the kernel accepts, and the
reachability walks ask what the prober can reach. Neither asks what the contract requires.

The repair plan already anticipated this: "prefer executable coverage assertions over prose:
a test that enumerates the contract's rows and fails when one has no destination is
durable, while a reviewer's row-by-row read is not."

## The mechanism

**The row set is parsed from the contract, not transcribed.** `test/support/r4_rows.ex`
reads `WORKFLOW-CONTRACT.md`, locates R4's transition table and R4a's domain-owner table by
their header cells, and returns their rows. The inventory holds only each row's **verbatim
from-state cell** as a handle key. Edit a row in the contract and the lookup fails, naming
it; add one and the bijection test fails. Nothing is duplicated, so nothing can drift.

**Every row must be driven.** `r4_coverage_test.exs` pairs each handle with a scenario that
applies real events through `Kernel.apply/2` and asserts the outcome the contract states. A
rejection anywhere in the sequence flunks, so "driven" means every event was accepted and
the stated outcome holds.

**Driving is not enough; prohibitions are asserted too.** A row that says "exit
notifications cannot overwrite this", "failed candidate never goes to approval" or "closes
*that* execution" is stating a refusal, and a scenario that only drives the happy path
would pass while the kernel accepted every contradiction. Those clauses assert the refusal.
This is what the previous correction got wrong on R4's integration row: it stopped a
ref-holding attempt settling `failed` and left every other way to contradict a recorded ref
wide open.

**Two ratchets, and they mean different things.** `@unexpressible` is for a row the kernel
cannot drive at all; it is currently empty. `@partial` is for a row that drives but whose
named clause cannot yet be expressed — because calling a mostly-working row "unexpressible"
hides what works, and calling it "driven" hides what does not. Each `@partial` entry quotes
the exact clause.

## What this found immediately

Six rows were undrivable when the harness was first run, which is precisely what the two
reviews had been reporting in prose. Two more — `base_moved` and `reset` — had been marked
unexpressible **by inspection** and turned out to drive on the first attempt. Two wrong
calls in one hand-maintained list is the argument for the list being executable.

## What it does not prove

Driving a row here means the **reducer** can express it. Subcommit 1 is the pure kernel, so
this says nothing about the mechanism behind the row. `reset` is the clearest case: it
drives, because the kernel validates its payload's shape, while `reset_fact_v1` still has
no producer in the durable codec, so the protected fact the payload carries cannot yet be
derived. That boundary is recorded beside the scenario rather than left for a reader to
discover.

Nor does it replace the reachability walks. The walks ask whether a row is reachable by
*some* sequence the prober will actually generate, which is a different question from
whether a hand-built sequence can drive it — the first catches a kernel that has quietly
made a row unreachable, the second catches a kernel that cannot express one at all. The
second review's finding 7 is the case for keeping both: the variant ratchet was empty of
`cancellation_finalized:after_integration` because the *prober* could not close a settled
attempt's executions, a defect the coverage harness would never see because its scenarios
build their own sequences.

## Where it goes next

Batch C's entry in the repair plan asks for the prober's proposals to be generated from
this same row table, so the two hand-written encodings of R4 collapse into one. That is the
structural fix for the circularity finding: two encodings that cannot drift cannot be tuned
against each other. It is not done here — the row table currently carries from-state and
outcome text, not machine-readable guards or payload shapes, and generating proposals needs
both. Doing it would also retire `KernelWalk.candidates/1`, which is a larger change than
this subcommit should carry.
