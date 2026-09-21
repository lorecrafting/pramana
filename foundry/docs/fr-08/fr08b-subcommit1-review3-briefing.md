# FR-08B subcommit 1 — third review briefing

Date: 2026-09-20

Reviewer: a **fresh** Claude Fable 5.1 session, independent of the implementer and of both
previous reviewers. Not a fork.

Candidate: `4715c25` on `repair/fr08b-kernel`. Review `git diff 40ac559 4715c25`.

## What happened twice, and what changed

Two independent reviews blocked this subcommit. Both returned the same finding shape, and
the second stated it plainly: *"the correction fixed the eight counterexamples. It did not
fix the rows."* Guards refused the reported sequences while the R4 rows they claimed to
implement stayed unexpressible.

The third attempt changes the **method**, not just the guards.
[The row-driven design](fr08b-row-driven-coverage.md) is the argument;
`test/support/r4_rows.ex` and `test/pramana_foundry/workflow/r4_coverage_test.exs` are the
mechanism. R4's transition table and R4a's domain-owner table are parsed out of the
contract, and every row is driven through `Kernel.apply/2` with the contract's stated
outcome asserted. Rows stating a prohibition assert the refusal too.

**Your highest-value question is whether that mechanism actually works**, because if it
does not, this subcommit has failed three times and the next four are built on sand.

## What to read, and one paragraph to disregard

[WORKFLOW-CONTRACT.md](../WORKFLOW-CONTRACT.md) **§R4 and §R4a** — the authority. Then
[the two prior reviews' findings](fr08b-subcommit1-review-findings.md), the
[correction design](fr08b-subcommit1-correction-design.md) and the
[row-driven design](fr08b-row-driven-coverage.md). Do not preload the plan, history or
tutorial.

**Disregard the R3 paragraph "Observability is not authority."** It was written by an
implementer in the same session as code written against it, is marked in the contract as
not independently reviewed, and proves nothing here. Judge against revision 3's R4/R4a rows.

## Settled facts — supplied as given

Spot-check any and say so; re-establishing them as routine is waste.

- **Full model-free suite: 796 passed, 13 skipped at seed 0**, serial, fresh
  `MIX_BUILD_PATH`. Workflow suites: 60 at seed 0 (3 coverage, 44 table, 13 properties).
- `foundry/bin/preflight.sh` passes.
- **FR-08A attestation untouched**; no file it pins is modified. The kernel still has no
  callers, so no current behaviour changes.
- **All six new guards were verified non-vacuous**, each neutralised in isolation, each
  turning exactly the intended test red, each reversed by exact string replacement.

Do **not** run the full suite; concurrent runs produce spurious physical-fault failures.
You may run the three workflow suites, one at a time, with `TMPDIR=/private/tmp` and a
fresh `MIX_BUILD_PATH`.

## Disclosed against interest

These are the implementer's own findings from this pass. They are disclosed because this
subcommit's failures have twice been **evidence** failures, so the evidence is what most
deserves your hostility — not because they are settled.

- **The first non-vacuity sweep found three of six new guards untested.** Neutralising
  `require_running_developer`, the `exhausted` phase guard and the row-12/13 separation
  left all sixty tests green. The worst was row 12/13: a scenario named
  `check_infrastructure_failed` existed and a commit message claimed the rows were
  separated, while nothing in the scenario depended on `failed_check?/1`. Three refusal
  assertions were added and each now turns exactly one test red.
- **The repair of that had the same defect one level up.** The edit adding the missing
  `exhausted` assertion was a string replacement that silently did not match, so a test was
  reported as added and did not exist. A second sweep caught it.
- Assume this pattern recurs somewhere I did not sweep. **Every assertion in the new
  coverage suite is worth testing for vacuity**, not only the guards.

## What to review, in priority order

### 1. Does the row-driven harness do what it claims?

- `R4Rows.contract_rows/0` parses two tables out of the contract by header cell. Does it
  find exactly the right rows? Could a contract edit slip past the bijection test? Is
  keying on the verbatim from-state cell actually drift-proof, or is there a way for the
  inventory and the contract to disagree while the test stays green?
- The scenarios drive rows by constructing event sequences. **Does each scenario drive the
  row it is named for, or something adjacent?** That is precisely the failure the first
  review found in the old table tests — a test that did not establish what its name claimed.
- `@partial` holds five clauses. Are those genuinely blocked on the R4a limit product, or
  is that a convenient place to put work? Specifically: is deferring
  `blocked(reviewer_launch_infrastructure)` and `blocked(check_infrastructure)` to
  subcommit 2 correct, or should `ticket_parked` have been widened to reach them? The
  implementer's argument is that widening re-conflates R4's PM park row with R4a's
  infrastructure block. Test that argument.
- `@unexpressible` is empty. Two rows — `base_moved` and `reset` — were in it on the
  implementer's inspection and drove on first attempt. Is the empty set real?

### 2. Did the fixes fix the rows, or the counterexamples again?

The eleven findings of the second review are all claimed fixed. For each, the question is
the one that failed twice: does the guard express the row, or only refuse the reported
sequence? Particular attention to the settlement role binding, which the *previous*
correction claimed to have generalised "as one rule over the vocabulary" and had applied to
one event.

### 3. Is the state shape right?

`rejected_submissions` and `policy_empty_checks` were added to the attempt this pass. Are
they the right shape for R4's rows, or convenient fields? Does `State.valid?/1` remain total
over everything the reducer reads?

### 4. New circularity, and the prober

The prober was changed in the same commits as the kernel again — it gained settled-attempt
cleanup proposals and a corrected liveness rule. That is the both-sides-moved pattern that
produced a confirmed circularity in review 1. Check it.

Note the deliberate redundancy: the coverage harness builds its own sequences, so it cannot
see a kernel that has made a row unreachable-in-practice; the walks cannot see a row the
kernel cannot express at all. Both are kept for that reason. Say if you think that is wrong.

## Out of scope

FR-08A; `decide/3`; the R4a control/allocation product (B3); the durable vocabulary
extension; `terminal_settlement_v1` and `reset_fact_v1` producers.

## Recorded non-goals, unchanged

The kernel **records** worker closure rather than verifying it; verified termination is
owned by FR-10. A row driving in the coverage suite means the **reducer** can express it,
not that the mechanism behind it works — `reset` drives while `reset_fact_v1` has no
producer.
