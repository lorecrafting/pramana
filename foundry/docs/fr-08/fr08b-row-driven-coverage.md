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
it; add one, or duplicate one, and the bijection test fails.

That sentence originally ended "Nothing is duplicated, so nothing can drift", and the third
review demonstrated it false. It was true of the **key** and false of everything the key
pointed at: `R4Rows.outcome/1` was defined and called nowhere, so an outcome cell could be
edited from "Terminal rejected attempt/ticket" to "Terminal integrated attempt/ticket" and
every test stayed green while the scenarios went on asserting the old outcome. Each
scenario's assertions were a hand transcription of that cell, which is precisely the
translation step where the first two corrections failed.

**Both cells are pinned now.** Each scenario cites the clauses it asserts, verbatim from the
outcome cell, and a test checks every citation is still a substring of the live row. Editing
an outcome now fails, naming the row, the citation and the text that replaced it —
demonstrated by doing it and reversing it. A citation does not prove the scenario asserts
what it cites; nothing short of the assertion can. It proves the assertion is pinned to the
contract's words rather than to someone's memory of them, which is the failure that
actually occurred.

The converse is tracked too: 54 clauses are asserted and 59 are not, so this suite tests a
little under half of what R4 and R4a say. That number was unknowable before and can only go
down.

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

## The hand-built half, and how it stops being hand-built

Each scenario has three parts, and they generalise very differently.

1. **The path to the row's precondition.** Hand-written today: `reviewing()` drives nine
   events to put a ticket in `reviewing`. This is the most brittle part of the suite and
   the target of the third review's sharpest question — "does each scenario drive the row
   it is NAMED for, or something adjacent?" A hand-built fixture cannot answer that,
   because the thing being asserted and the thing being built are the same author's guess.
2. **The input event.** A row-to-event mapping, currently implicit in each scenario.
3. **The outcome assertions.** A hand transcription of the outcome cell, now pinned to the
   contract's words by clause citation.

Part 1 is already generatable and should be generated. `KernelSearch` enumerates every
reachable state, so a row can declare its precondition — `attempt.phase == reviewing and
attempt.review.verdict == rejected` — and have the path found rather than built. That is
strictly stronger than the fixture: the search proves the precondition is reached, and a
precondition that becomes unreachable fails loudly instead of silently testing a state next
to the one intended.

Part 3 is the part that cannot be derived. An outcome cell is English, and translating
English to a predicate mechanically would be a fourth hand-maintained encoding of the
contract — the failure this whole document exists to stop. It stays hand-written and
clause-cited.

That leaves the shape a workflow declaration would take, if one is ever wanted: per row, a
**precondition predicate, an input event, and outcome predicates each citing their
clause**. The predicate language over state is the portable piece — phases, roles and
entity kinds differ between workflows, but "predicate, event, predicate" does not. Nothing
here commits to building that; it records what the shape would be, having been arrived at
from the correctness side rather than designed up front.

## Where it goes next

Batch C's entry in the repair plan asks for the prober's proposals to be generated from
this same row table, so the two hand-written encodings of R4 collapse into one. That is the
structural fix for the circularity finding: two encodings that cannot drift cannot be tuned
against each other. It is not done here — the row table currently carries from-state and
outcome text, not machine-readable guards or payload shapes, and generating proposals needs
both. Doing it would also retire `KernelWalk.candidates/1`, which is a larger change than
this subcommit should carry.
