# Evidence-reduction tickets: the three proposals that had no home

The evidence-architecture review ([Sol's findings](fr08b-subcommit1-review4-sol-findings.md))
concluded that five evidence mechanisms is too many and that the set should collapse to two:
contract-to-predicate conformance, and instrumented exploration carrying semantic invariants
and first-failure witnesses. It made four concrete proposals. One — replacing the hour-long
guard mutation sweep with guard-site instrumentation — is designed in
[coverage-guided sweep](../COVERAGE-GUIDED-SWEEP.md). The other three were recorded in
[the repair plan](../REPAIR-PLAN.md#mechanical-evidence-discipline) as "not designed, not a
ticket". This document scopes them.

These are **not new FR nodes**. The FR namespace is closed at FR-23 by operator direction.
They are scoped work items inside FR-08B's remaining subcommits, the same way the repair
plan already scopes "stop hand-writing the second encoding of R4" there.

## Is this worth doing at all

Two questions decide it: does kernel testing continue, and does each proposal move
correctness rather than tidiness.

**Kernel testing continues.** FR-08B subcommits 2–5 are outstanding and every one edits
this kernel or the contract that judges it: 2 builds `decide/3` on the state shape, 3 adds
the reviewer role, 4 adds check and reviewer workers, 5 migrates four ingresses. FR-10,
FR-11 and FR-12 are in the same batch and build on the same reducer. The plan also
schedules a split of `kernel.ex` by event family before subcommit 5. Every one of those
passes is judged by the mechanisms below. This is not a closing subcommit's tidy-up; it is
tooling that four more reviewed passes will lean on.

**Correctness, honestly rated.** None of these three would have found the
`integration_recorded` / `infrastructure_failed` defect on its own — a person doing a
confirmation pass found that, and the thing that reproduces it is a seeded search, which
already exists. What they change is the standing of the numbers every future pass reports:

| Proposal | What it makes true that is not true now |
|---|---|
| EV-4 congruence | The search's denominators stop being conditional on an unproven quotient |
| EV-3 invariant split | The relational oracle judges every transition the suite drives, not only the ones the bounded search reaches |
| EV-2 clause IDs | The coverage number counts obligations instead of punctuation |

Ranked by payoff per unit of cost: **EV-4, then EV-3, then EV-2**. Ranked by how fast the
cost grows if deferred: **EV-2, then EV-3, then EV-4**. The sequencing below resolves the
two orders.

## EV-4 — canonicalisation congruence test

**Outcome.** `KernelSearch`'s state-merging key is proved to be a congruence: two states
with the same canonical key accept and refuse the same proposals, and their accepted
successors canonicalise identically.

**Why it matters more than it sounds.** Every "N states, M holding the precondition, 0
violating" this subcommit has recorded is computed over the *quotient*, not over the
reachable set. If the key over-merges, the search silently stops exploring a branch and
every denominator is overstated — including the 29,109/20,488/0 and 79,163/39,024/0 runs
that converted two sites from unwitnessed to redundant-given-an-invariant. Rule 2 exists to
make denominators meaningful; this is the test that makes rule 2's denominators load-bearing
rather than nominal. Sol looked for a counterexample and found none, which is grounds for
expecting it to pass, not grounds for skipping it.

**Scope.** A property test over sampled reachable states: for each pair sharing a canonical
key, assert equal accept/refuse decisions and equal error atoms across the full proposal
set, and assert that accepted successors share a key. Red control per rule 1: a deliberately
lossy key — drop `ticket["phase"]` — which must fail the test.

**Cost.** Smallest of the three. One test file, no kernel change, no contract change.

**Sequencing.** First, and independent of everything else. It validates the numbers EV-3 and
EV-2 will report.

## EV-3 — split `well_formed?/1` from `invariant?/1`

**Outcome.** The relational oracle lives in `lib` beside the shape validator, and is
asserted after every accepted transition the suite drives, not only over the states the
bounded search reaches.

**The current split is already wrong in both directions.** `State.valid?/1` is billed as a
shape validator and is mostly that, but `valid_attempt_order?/1` inside it is relational —
`active not in prior`, and the active attempt is not terminal. Meanwhile the rest of the
relational layer (`@legal_pairs` phase agreement, resume-target honesty, candidate, receipt
and terminal custody) lives in `test/support/semantic_invariants.ex`, is applied only by
`r4_exhaustive_test.exs`, and therefore judges only what the proposer reaches at depth.

**This is the class the sweep fundamentally cannot see.** The mutation sweep neutralises
conditions and asks whether a test notices. A handler can have every guard perfectly
exercised and still write the wrong phase, fail to clear stale metadata, or retain a pointer
it should clear — which is precisely the shape of the six recorded partial generalisations
and of the unfixed `infrastructure_failed` defect. Post-state coherence is unmeasured except
where the search happens to walk.

**Scope, and the decision inside it.** Move the relational predicates into
`PramanaFoundry.Workflow.Kernel.State.invariant?/1`, leaving `well_formed?/1` as the shape
validator (`valid?/1` becomes a deprecated alias or is renamed at every call site in one
edit — rule 4). Then the scope decision:

- **Recommended: assert, do not refuse.** The kernel does not call `invariant?/1` in
  `apply/2`. A test-harness wrapper asserts it after every accepted transition across the
  whole suite. Non-behaviour-changing, catches the class everywhere a test already drives,
  and defers the refusal question to evidence.
- **Deferred: refuse.** Having `apply/2` reject a transition whose post-state violates an
  invariant is a behaviour change on a gate-validated kernel and needs its own review. Take
  it only once the assert-only form has run clean for a full subcommit.

Red control per rule 1: a fixture post-state violating each invariant family, which must
turn the harness red. Denominator per rule 2: report how many accepted transitions the
suite drove and how many held each invariant's precondition — an invariant with zero
preconditioned transitions is rule 1's vacuous mechanism with a number attached.

**Cost.** Moderate. One module move, one call-site rename over a small vocabulary, one
harness hook, one red-control fixture.

**Sequencing.** Before subcommit 2. Subcommit 2 builds `decide/3` on this state shape, and a
proposer is exactly the consumer that wants a relational judgement of the post-states it
proposes. Moving the oracle afterwards means moving it under `decide/3`.

## EV-2 — semantic clause IDs in the contract

**Outcome.** R4 and R4a carry explicit clause identifiers (`R4.09.a`). `assert_clause/3`
verifies the quotation is still live and records the ID as exercised. Coverage becomes
`contract IDs − asserted IDs`, with no heuristic.

**What is wrong with the number today.** The clause unit is produced by
`String.split(~r/;|(?<=\.)\s+/)` — punctuation, not semantics. One assertion can cover
several fragments; one obligation can span two. `@uncited` is then a second transcription of
the contract, maintained by hand. Measured at HEAD: **57 clauses asserted, 57 uncited, across
32 rows, with 4 `@partial` entries.** The file's own comment says "54 clauses are asserted
and 59 are not" — an eighth hand-carried count weaker than its claim, and the cheapest
possible demonstration of why derived counts must come from the executable artifact. (Sol
caught the same shape on `@partial`: four keys, not the five the review prose claimed.)

**Why it is last on payoff and first on urgency.** It moves no correctness directly — it
makes one coverage number mean something. But its cost grows monotonically: every subcommit
adds contract rows, and every row adds fragments to transcribe into `@clauses` and
`@uncited`. It is cheapest now, with subcommit 1 closed and the contract stable, and it
never gets cheaper.

**The risk that sets its sequencing.** `WORKFLOW-CONTRACT.md` is the oracle. Editing it is
the highest-consequence edit in this system: `r4_coverage_test.exs` parses rows out of it at
test time, and every scenario's citation is checked against it. An ID-annotation pass must
be provably content-preserving.

**Scope.** Annotate clause IDs in the contract's governing tables; assert mechanically that
the annotation changed no clause text (normalise IDs out, diff against the pre-edit file —
the diff must be empty); replace `@clauses`/`@uncited` string lists with ID sets; delete the
punctuation splitter. Red control per rule 1: a fixture contract row whose ID set and
asserted set differ, which must fail.

**Cost.** Largest of the three, and concentrated in a single high-risk edit rather than
spread.

**Sequencing.** After EV-3, before subcommit 3. Do it while the contract is between
subcommits and no review is outstanding on it; never while a candidate is under review, for
the same reason the plan refuses to move `kernel.ex` under a reviewer.

## Order to take them

| | Ticket | Cost | Gate |
|---|---|---|---|
| 1 | EV-4 congruence | ~a day | Its own; no dependency |
| 2 | EV-3 invariant split | moderate | Before subcommit 2 builds `decide/3` |
| 3 | EV-2 clause IDs | largest | Between subcommits, before subcommit 3, no review outstanding |

EV-1 (coverage-guided sweep) is already designed and is sequenced by its own spike, not by
this table.

Each of these is a mechanism, so rule 1 applies without exception: it ships with a red
control or it does not ship. Five mechanisms in this subcommit produced confident, clean,
entirely vacuous results on their first run.
