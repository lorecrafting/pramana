# FR-08B subcommit 1 — fourth review briefing

Date: 2026-09-20

Reviewer: a **fresh** Claude Fable 5.1 session, independent of the implementer and of all
three previous reviewers. Not a fork.

Candidate: see the "Candidate and evidence" section below, filled at freeze.

## Three blocks, and what changed between them

Reviews one and two returned BLOCK with the same finding shape: guards that refuse the
reported counterexample while the R4 row they claim to implement stays unexpressible. The
second reviewer stated it exactly — *"the correction fixed the eight counterexamples. It
did not fix the rows."*

The third attempt changed the **method**: R4's and R4a's rows are parsed out of the
contract and each is driven through the kernel. Review three returned BLOCK on that too,
but with a judgement worth more than the verdict — the method is sound and should be kept,
and it was not yet what its own design claimed. Its nine findings are closed.

Your job is the fourth pass, and the highest-value question has shifted. It is no longer
"does the kernel do what R4 says" — three reviews and five mechanisms have worked on that.
It is **whether the mechanisms themselves are sound**, because subcommits 2 through 5 will
be built on them, and a mechanism that passes while measuring nothing is the failure this
whole subcommit keeps reproducing.

## What to read, and one paragraph to disregard

[WORKFLOW-CONTRACT.md](../WORKFLOW-CONTRACT.md) **§R4 and §R4a** — the authority. Then
[the prior findings](fr08b-subcommit1-review-findings.md), [the row-driven
design](fr08b-row-driven-coverage.md), and the implementation log's last three entries.
Do not preload the plan, history or tutorial.

**Disregard the R3 paragraph "Observability is not authority."** Written by an implementer
in the same session as code written against it, marked in the contract as not independently
reviewed, and it proves nothing here. Judge against revision 3's R4/R4a rows.

## Disclosed against interest

This subcommit's failures have been **evidence** failures more often than code failures, so
the evidence is what deserves your hostility. Everything below is the implementer's own
finding, disclosed so you do not spend tokens rediscovering it — not because any of it is
settled.

- **A mutation was committed into the repository.** `421c0b2` shipped `:ok <- :ok` in place
  of `require_cleanup_complete/1`, because `git add -A` ran while the mutation sweep held
  the tree. Every local check passed, because the suite was measuring the mutation. It was
  found two commits later by an unused-function warning. Restored by exact string and
  verified byte-identical to the last unmutated revision; a sentinel now blocks the window.
  **Assume other things were committed while a tool held the tree, and check.**
- **The mutation sweep's first two runs were themselves vacuous.** It reported all 66 guards
  as surviving, because this repository uses a custom test formatter and the verdict matched
  ExUnit's default format. A tool built to find vacuous evidence produced vacuous evidence.
- **Every new check found something on its first run** — the outcome-drift guard, the
  `@partial` quote check, dead-guard detection, the exhaustive search. Two of those findings
  were errors in the *check* rather than the code. Treat a green mechanism as unproven until
  you have seen it go red.
- The third review found three of six guards untested, and the repair of one was a string
  replacement that silently did not apply, so a test was reported as added and did not exist.

## What to review, in priority order

### 1. Are the five mechanisms sound?

- **Row coverage.** From-cell drift fails (demonstrated). Outcome-cell drift now fails via
  clause citation — verify that, and verify a citation cannot be satisfied by an accidental
  substring. Does each scenario assert the clauses it cites, or merely name them?
- **Exhaustive search.** `KernelSearch` canonicalises away revisions and event ids before
  memoising. Is the canonicalisation lossy in a way that merges genuinely different states
  and so hides a reachable violation? Is depth 7 with one ticket a bound that actually
  exercises the invariants asserted over it?
- **Dead-guard detection.** The `@unreachable` list gives a reason per entry, in two kinds:
  deeper than the bound, or genuinely unreachable. Are the "genuinely unreachable" claims
  true, or is the proposer simply not offering the event that would trip them?
- **Clause coverage.** 54 clauses asserted, 59 recorded uncited. Is the fragmentation rule
  (`;` and sentence boundaries) producing meaningful clauses, or is it a count that flatters?
- **Guard mutation sweep.** Results are in the log. Any survivor is a guard no test
  exercises; check the ones recorded as expected.

### 2. Did `ticket_blocked` earn its place?

R4a's at-limit outcomes were being expressed through `ticket_parked`, whose own row is R4's
PM park. The third review called the split incoherent — two clauses deferred while their
identical sibling passed through the conflation the deferral cited. `ticket_blocked` is now
the block's own event, accepted from any working phase. Is that faithful to R4a, or has one
event been replaced by another that is too permissive? Is `@blockable_phases` right?

### 3. The findings claimed closed

Nine from review three. For each, the question that failed three times: does the guard
express the row, or only refuse the reported sequence?

### 4. Anything the tools cannot see

The coverage harness builds its own sequences, so it cannot see a row the kernel has made
unreachable in practice. The walks sample. The search is bounded. Name what falls between
them.

## Settled facts — supplied as given

Spot-check at most one or two, and say so. Do not run the full suite; concurrent runs
produce spurious physical-fault failures. You may run the workflow suites one at a time
with `TMPDIR=/private/tmp` and a fresh `MIX_BUILD_PATH`.

## Out of scope

FR-08A; `decide/3`; the R4a control/allocation product (B3); the durable vocabulary
extension; `terminal_settlement_v1` and `reset_fact_v1` producers.
