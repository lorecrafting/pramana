# FR-08B subcommit 1 — fourth review briefing

Date: 2026-09-21

Reviewer: a **fresh** Claude Fable 5.1 session, independent of the implementer and of all
three previous reviewers. Not a fork.

Candidate: `c71fc70` on `repair/fr08b-kernel`. Base: `main` at `a319b39`. Evidence in
"Settled facts" below.

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
- **The sweep's own result was dismissed once, wrongly.** A later full sweep reported 19
  guards no test exercises. The implementer judged the number a tooling artefact and moved
  on; the supervisor disagreed, neutralised one guard by hand, and all five suites stayed
  green. The number was real. It is now 4, and the four are the guards recorded as
  unreachable — see "Settled facts". **The lesson to apply to this briefing: a number in it
  being explained is not the same as it being investigated.**
- **Of those four, only one was re-verified in the session that froze this candidate.**
  `checks_not_passed` was argued from the code and probed by search. The reasons given for
  `reviewer_already_closed`, `no_stored_resume_phase` and `candidate_frozen` were written in
  an earlier session and were carried forward unchecked. Priority-1 item three is aimed
  straight at them.

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
- **Guard mutation sweep.** Full results and both of its corrections are in "Settled
  facts". The question that remains open: a dead *call site* is invisible to every
  mechanism here except an hour-long sweep, because `@unreachable` is keyed by error atom.
  Two such sites were found this pass. Is there a cheaper mechanism?

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

Measured on `4358d44`, not transcribed from memory:

| | |
|---|---|
| Workflow suites | **131 passed**, seed 0 |
| Full model-free suite | **867 passed, 13 skipped**, seed 0, serial (`--max-cases 1`), fresh `MIX_BUILD_PATH`, **460s** |
| Canonical gate `elixir ci/run.exs` | **GATE_RESULT** |
| `bin/preflight.sh` | passes; 4 pre-existing test-file warnings, none in the files this candidate touches |
| Guard mutation sweep | 66 call sites; **4 survive** |

The full-suite count is the previously recorded 796 plus exactly the 71 tests added since
— 56 in the pass before this one, 15 in this one. The delta is the check; the absolute
number alone would not have caught a suite that quietly stopped being loaded.

### The mutation sweep, in full

Read this section before the priority list; it is the part of the evidence most likely to
be wrong, and it changed twice while this candidate was being frozen.

**The count the supervisor refused to let go.** A full sweep reported **19 guards no test
exercises**. The implementer judged it a tooling artefact and moved on. The supervisor
disagreed, neutralised one guard by hand, and all five suites stayed green. Three causes:

1. **Loose assertions.** A refusal asserted as `{:error, _}` is satisfied by any guard in
   the `with` chain, so neutralising the one a test was named for still matched, via
   whichever guard refused next. This was review one's finding 9, deferred as cosmetic. It
   was not cosmetic; it was hiding most of the other two causes.
2. **Guards added without tests** — fifteen, several arriving with the corrections that
   closed review three's findings.
3. **Guards that cannot fire** — four at the time.

**Then the tool turned out to be understating itself.** Writing *this briefing*, in the
sentence below asking you to check whether the sweep's granularity was honest, it became
clear it was not. The sweep neutralised by **global** string replacement, so identical
call-site text was mutated in every handler holding it and one red test anywhere cleared
all of them. It reported "guard call sites: 66". **There are 108.**
`require_active_attempt(ticket, payload["attempt_id"])` appears twelve times;
`require_attempt_phase(ticket, ~w(active))` five. Fifty texts occur once and were measured
honestly; the other sixteen cover fifty-eight occurrences of which at most sixteen had ever
been measured, so **42 call sites had never been individually exercised**.

That is the fourth time this one tool has produced evidence weaker than its own claim.

Swept per occurrence, **37 of those 42 had no test at all**. Each now has one. Final
re-sweep of all 62 previously-unmeasured occurrences: **6 survive**, and they are exactly
the six recorded as unable to fire.

| Guard, and its site | Why it cannot fire |
|---|---|
| `require_reviewer_open` | every route to a closed reviewer on a `reviewing` attempt is refused earlier |
| `require_resume_target` | every path into `blocked` stores a resume target |
| `require_no_candidate` | `artifact_frozen` sets the candidate and leaves `active` in one step |
| `require_checks_passed` | **found this pass** — shadowed by the attempt-phase guard above it |
| `require_no_active_attempt` in `ticket_reset` | **found this pass** — `attempt_settled(exhausted)` is the only route to `exhausted` and clears the slot. Its twins in `ticket_amended` and `cancellation_finalized` both fire. |
| `require_attempt_phase(~w(reviewing))` in `reviewer_closed` | **found this pass** — reaching it needs an approved verdict off `reviewing` with a sealed-and-open reviewer, and the only thing that moves the attempt closes that execution on the way |

The last two are properties of a **call site**, not an error atom, so `@unreachable` in the
guard-reachability suite cannot hold them — `:attempt_still_active` is reachable, just not
from `ticket_reset`. They are recorded in `kernel.ex` at the site, with their measurements.
**The gap is real and is not closed: nothing but the sweep can see a dead call site, and
the sweep costs an hour.** Naming a better mechanism is welcome.

### How the unreachability claims were checked, and why the first check was nearly worthless

`@unreachable` asks whether an error atom ever fired in the bounded search, which conflates
"no sequence can trip this guard" with "the prober never offered the event that would". So
each claim was re-checked by searching reachable **states** for the guard's own trip
condition. Then the bound was measured, and the measurement was unflattering:

| reachable at depth 8, unseeded, 238,000 states | count |
|---|---|
| attempt phase `reviewing` | 45 |
| attempt phase `awaiting_review` | 156 |
| **any recorded verdict** | **0** |

Two claims were therefore resting on 45 and 156 witnesses, and anything past a verdict could
not be bounded at all. `KernelSearch` now takes `:from`, so the budget is spent where the
question is. Seeded from a sealed reviewer: 164,648 states, 13,846 holding an approved
verdict, and the two thin claims re-checked against real coverage.

**That option produced a vacuous result on its first run** — one state, zero of every
predicate, because proposals restarted sequence numbering at 1 against a seed at 10 and were
all refused as `out_of_order_event`. It looked exactly like a proof that nothing was
reachable. Fifth vacuous first run of this session.

**It then overturned a hand argument.** `reviewer_closed`'s approved branch had been reasoned
unreachable; the loose form of that reasoning has 3,612 witnesses. The conclusion survived
on the exact precondition and the reasoning did not — which is the same "two wrong calls in
one hand-maintained list" that this subcommit keeps producing.

### Known limit of all of the above

Every number here is bounded, and the transitions still come from the prober. "No reachable
state satisfies this predicate" means no state the prober can build within the depth, so a
guard is only as unreachable as the proposal set is complete. The seeded search narrows that
gap; it does not close it. Four of the six survivors also rest on the *reachability* of
their trip condition rather than on a proof, and the reasons are claims you may attack.

One more, disclosed because it bit twice: a state probe reported 774 witnesses for "attempt
phase is not active" because the predicate matched `nil` — no attempt at all. It was caught
by reading the counterexample path it printed, which ended in `attempt_settled:cancelled`.
Predicates over absent entities are the shape to distrust in everything above.

## Out of scope

FR-08A; `decide/3`; the R4a control/allocation product (B3); the durable vocabulary
extension; `terminal_settlement_v1` and `reset_fact_v1` producers.
