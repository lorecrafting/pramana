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
preconditioned transitions is rule 1's vacuous mechanism with a number attached. **That is not
hypothetical:** EV-5 measured the five families over the bounded search and `receipt_custody`
came back 0 of 58,324, so one of the five invariants EV-3 proposes to promote is currently
judged by nothing exhaustive. EV-3's denominators are the mechanism that would notice.

EV-5 also removes the reason this was blocked: the oracle EV-3 promotes now carries the cancel
exception, agrees with itself, and is asserted by a test that can fail.

**Cost.** Moderate. One module move, one call-site rename over a small vocabulary, one
harness hook, one red-control fixture.

**Resolved.** `SemanticInvariants` is now `State.violations/1` / `invariant?/1`; `valid?/1`
is `well_formed?/1` at all 15 sites; `Test.Harness.apply/2` is the single route from a test
to the kernel and asserts both validators on every accepted post-state, with
`r4_no_direct_apply_test.exs` keeping that true as new tests arrive. Two of the ticket's
instructions were **not** followed, and in both cases measurement rather than argument is
the reason:

- **`valid_attempt_order?/1`'s terminal conjunct stays in `well_formed?/1`.** The ticket
  calls it relational sitting on the wrong side, and it is relational. Dropped it and
  re-ran the search from all 3,358 corrupted states: 0 of 243,643 proposals returned
  `:kernel_raised`, so the totality objection to moving it was false — but 43,497
  transitions were then accepted, 753 producing a state `invariant?/1` calls clean, of
  which **406 overwrite a settled disposition** against R4's "set once on terminal". An
  assert-only oracle reports; only the validator refuses.
- **`terminal_custody` is deleted, not promoted.** Both its halves fire only on states
  `well_formed?/1` already refuses: over 6,716 corruptions of reachable terminal attempts
  the clause fired on all of them and the validator accepted **0**. It could never carry
  rule 1's failing fixture, and was reporting 0 violations out of 6,716 preconditioned
  states by construction. Five families remain, each with its own red control.

The denominator the ticket asked for is not a one-off measurement: `State.measure/1`
returns each family's `{precondition_held?, violations}` from the same code that produces
the violations, and the suite prints the per-family table after every run. `receipt_custody`
remains vacuous at the search's bound and is now visible as such on every run rather than
in a document.

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

**Measured, before the annotation pass.** `bin/clause_unit_probe.exs` reads the two maps out of
the test's own source and reports three numbers. The bookkeeping holds **118 entries** — 57 cited,
57 uncited, 4 partial — every one of which still anchors verbatim in its own row's outcome cell,
together reaching **5,500 of 5,932 outcome characters (93%)**. The remaining 7% is where the
punctuation unit shows:

**7 substantive obligations that no entry accounts for at all.** Each shares a
punctuation-delimited fragment with an asserted quote, and the splitter marks a whole fragment
covered if it *contains* any cited clause, so the obligation beside it is invisible:

| row | the obligation | swallowed by the cited quote |
|---|---|---|
| `freeze_failure` | Git/scope validation failure is invalid submission | "never a frozen result" |
| `malformed_submission` | and budget remains | "further submission allowed only while stream open" |
| `checks_start` | schedule root-mandated check workers before reviewer | "retaining immutable candidate" |
| `reset` | with newly bound checks/review | "queue a fresh developer attempt using retained evidence as context" |
| `nonstart_developer` | and immutable base/spec/policy lineage | "Keep the **same nonterminal attempt**" |
| `nonstart_reviewer` | immutable candidate/check receipts and reviewer ownership | "Keep attempt and ticket `awaiting_review`" |
| `nonstart_worker` | A retry references the predecessor and | "consumes its finite role-specific infrastructure allowance" |

This is the direction that flatters the number: coverage looks complete over text nothing asserts.

**7 places where two entries claim the same text.** Five are one shape — a cited quote spans a `;`,
covering two obligations, and the clause after the `;` is *separately* recorded as uncited, differing
only by the trailing period that makes the substring test miss the contradiction. So the same clause
is counted in both totals. One more has a `@partial` quote inside an `@uncited` one
(`no_valid_candidate`), and one has identical text in `@clauses` and `@partial`
(`nonstart_worker` — asserted and deferred at once).

**Reading the five scenarios settles which record is right, and it is not the conservative guess.**
Four of the five `@uncited` entries are stale — the scenario does assert the clause:
`nonstart_pm` asserts `objective["proposals"] == %{}` for "infer no proposal";
`developer_exit_after_freeze` asserts `candidate_id` and `phase == "candidate_frozen"` for "preserve
frozen candidate"; `terminal_rejection` asserts `disposition == "rejected"` survives the refused
event for "preserve terminal facts"; `nonstart_reviewer` asserts `ordinals["developer"] == 0` and
`disposition == nil` for "never enter developer retry or correction". The fifth,
`blocked_result`, is genuinely **two** obligations: "close developer" is asserted
(`executions["X1"]["lifecycle"] == "closed"`), "no review" is not asserted by anything.

So **"57 asserted / 57 uncited" is wrong in both directions at once** — at least 7 obligations
invisible, at least 4 uncited entries stale, and 7 spans double-counted. Which is the ticket's
thesis, no longer as an argument.

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

## EV-5 — the relations test cannot fail, and 190 reachable states violate

Found by the seventh review, outside the delta it was reviewing. Not one of Sol's proposals;
recorded here because it is the same oracle EV-3 proposes to promote.

**What is wrong.** `r4_exhaustive_test.exs:141-148` — "every reachable state satisfies the
contract's relations, not just its shapes" — passes its lambda to `check/2` (`:207-231`),
which matches `{:violation, message}`. The lambda returns `{:error, message}`. The `_ -> nil`
clause swallows it, so **the test cannot fail**. Introduced in `028b4965`.

**What it was hiding.** Measured, not argued: at depth 6 from empty, **190 of 13,290 reachable
states** have `SemanticInvariants.violations != []`. The shortest is four events —
`ticket_admitted:queued` → `launch_planned` → `cancellation_requested` →
`attempt_settled:cancelled` — reporting "ticket is developing with no active attempt".

**It is probably the oracle, not the kernel, and that is the work.** `apply_terminal_phase`
returns the ticket unchanged for `cancelled` (`kernel.ex:1042-1043`), so a cancelled settlement
deliberately leaves the ticket in its working phase awaiting `cancellation_finalized`.
`phase_agreement/3`'s nil clause calls that "a ticket nothing can move", which is false while
`cancel_requested` is set — and a sibling clause in the same module already encodes a cancel
exception this one lacks, so the two halves of one oracle disagree. But the shortest path is
one of 190 and the rest are unclassified; deciding this from the first counterexample is the
exact move that produced six of the defects in this subcommit.

**Scope.** Fix the `{:error, _}` / `{:violation, _}` mismatch first and watch the test go red —
that is its missing red control, and the fix is worth nothing without seeing it fail. Then
classify all 190: each is either an oracle gap (add the exception, citing the contract row that
licenses it) or a kernel defect (its own candidate). Report rule 2's three numbers at each step.

**Why it sequences before EV-3.** EV-3 promotes `SemanticInvariants` out of `test/support` so
it judges every transition the suite drives. Promoting an oracle whose only exhaustive
application is dead, and which disagrees with itself on the cancel path, would propagate that
disagreement into `lib` and assert it everywhere. Fix the oracle, then promote it.

**Cost.** The mismatch is one word. The classification is the ticket.

**Resolved at `b3c110e3`.** The one word went in first and the test failed on the predicted
four-event path, which is the red control it never had. Then all of it was classified rather
than the first counterexample read. At the depth the suite actually runs — 7, not the 6 the
review measured — **1,002 of 58,324 reachable states violate, and every one is the same
clause**. Rule 2's three numbers per family:

| family | states checked | holding the precondition | violating |
|---|---|---|---|
| `phase_agreement/nil` | 58,324 | 1,002 | **1,002** |
| `phase_agreement/attempt` | 58,324 | 17,059 | 0 |
| `resume_target` | 58,324 | 26,143 | 0 |
| `terminal_custody` | 58,324 | 18,216 | 0 |
| `candidate_custody` | 58,324 | 7,245 | 0 |
| `receipt_custody` | 58,324 | **0** | 0 |

Violations equal preconditions exactly, so the clause was **never once satisfied** — it is not
a mostly-right invariant missing an exception. All 1,002 have `cancel_requested` set and every
attempt terminal-cancelled; **0** have no pending cancel. Verdict: **1,002 of 1,002 an oracle
gap, 0 kernel defects**, licensed by `WORKFLOW-CONTRACT.md:490`.

"A ticket nothing can move" was falsified by measurement rather than conceded to the contract:
**0** of the 190 at depth 6 are dead, each admits **at least 4** accepted successors, the gate
on immediate finalisation is `:executions_not_closed` / `:cleanup_incomplete` — row **:491**'s
cleanup condition, read out of the refusal set — and of the 35 that cannot reach a terminal
ticket phase within 3 further events, **35 of 35** do within 5.

Two things the classification produced that the ticket did not anticipate. **`receipt_custody`
is vacuous at the suite's own bound** — 0 of 58,324 states hold its precondition, because a ref
receipt sits roughly a dozen events from empty. Recorded, not fixed; it is EV-3's argument with
a denominator. And **`check/2` is now strict** rather than the one drifted lambda being
corrected: nine tests route through it and an unrecognised return raises, because fixing the
lambda leaves the swallow in place for the other eight. The duplicate encoding of row :490 was
deleted under rule 4 — it was correct and green, and that is exactly what made the dead test
look corroborated.

## Order to take them

| | Ticket | Cost | Gate |
|---|---|---|---|
| — | EV-4 congruence | **done** | Landed at `96ad2f22`, independently reviewed and accepted |
| — | EV-5 relations test | **done** | Landed at `b3c110e3`. Independently reviewed; the review blocked it on its own warrant text and found a larger defect, both answered — [log](../IMPLEMENTATION-LOG.md) |
| — | ~~row :467 guard~~ | — | **Not a candidate.** It is B3's, outstanding and designed; subcommit 2 owns it |
| — | ~~`apply/2` closure~~ | — | **Not a candidate here.** Found by EV-3's harness on its first run: **at least 20** `(type, key)` pairs in 14 event types produce a state `well_formed?/1` rejects, which bricks the log. A bound, not a count — `bin/closure_probe.exs` prints what it cannot see each run. Quarantined and measured in `IMPLEMENTATION-LOG.md`; needs its own candidate |
| — | EV-3 invariant split | **done** | Landed at `7e8e3921`. Independently reviewed three times, blocked three times, all answered at `2afe053f`, `c4b3721c`, `323112d5`. Its harness found the `apply/2` closure defect on first run |
| — | EV-6 from-cell conjuncts | moderate | **Landed; reviewed twice, blocked twice, both answered** — [briefing](fr08b-ev6-ev2-review-briefing.md), [findings](fr08b-ev6-ev2-review-findings.md). The candidate reviewed was delta `16fc73db..dc9582b3`, where 63 of 72 were classified. 72 from-cell IDs are annotated into the contract, content preservation proved against `16fc73db`, and every ID must carry a disposition. **Currently 67 of 72 classified, 5 held** — a count that moves, so it is stated on its own rather than pinned to a delta it was not true at. Outcome-cell IDs are EV-2's half of the same edit |
| — | EV-2 clause IDs | largest | **Landed; reviewed twice, blocked twice, both answered** — same candidate, same briefing and findings as EV-6. 124 outcome obligations annotated and consumed: `@clauses` and `@uncited` are ID sets that must exactly tile the contract, the punctuation splitter is deleted, and the count prints from the lists. 64 asserted, 60 recorded uncited |

EV-1 (coverage-guided sweep) is already designed and is sequenced by its own spike, not by
this table.

Each of these is a mechanism, so rule 1 applies without exception: it ships with a red
control or it does not ship. Five mechanisms in this subcommit produced confident, clean,
entirely vacuous results on their first run.

## EV-6 — the coverage number measures the outcome half of every row

Found while verifying the EV-5 review's largest finding. Not one of Sol's proposals, and not a
tidy-up: it is the reason an unimplemented contract *precondition* is found only by a human
reading prose against code.

**Corrected before this ticket was acted on.** The first draft called row :467's unguarded
conjuncts a defect no mechanism and no review had caught. The second half is false and the
correction is the ticket's best evidence: the **first** pure-kernel review caught it and filed it
as **B3** — "It never sees global pause/drain state and does not act on the ticket's cancel
control (`kernel.ex`, lines 744–773 and 840–881)"
([review](fr08b-pure-kernel-review.md#b3--r4a-dispositions-do-not-cross-current-controls-allocation-or-generations)) —
and [the correction design](fr08b-kernel-correction-design.md#b3--r4a-control-crossing-at-the-specified-ordering-point)
already specifies the full per-role control product. B3 is recorded as **outstanding** in the
repair plan and belongs to subcommit 2. So this is not an undetected defect, and the row :467
guard is not a separate candidate; it is B3's, already designed.

What survives, and it is the point: **a reviewer had to find it by reading, and it cost a review
round.** Every mechanism in the gate stayed green across the whole life of the defect, and still
would. That is the same economics `EVIDENCE-TOOLS.md` opens with — "anything that converts a
reading-check into a running-check is worth more than another reader" — applied to preconditions,
which is the half no mechanism covers.

**What is wrong.** `r4_coverage_test.exs`'s clause bookkeeping is built entirely on **outcome
cells**. `@clauses` are quoted from a row's outcome and a test asserts each is still a substring
of `R4Rows.outcome(id)`; `@uncited` is documented as "every clause of every **outcome cell** that
no scenario asserts". The **from-state cell** is used only as a verbatim lookup key — which makes
it drift-proof against contract edits, and that is genuinely valuable — but its conjuncts are
never enumerated, never asserted, and never recorded as uncited.

Measured, not argued: **32 rows carry 61 from-cell conjuncts, 28 rows carry more than one, and 0
of the 61 appear in the coverage number.** The "57 asserted / 57 uncited" figure is a count over
half of the contract.

**And 61 is a punctuation count, which is this ticket's own critique turned on its own number.**
Reproduced: `R4Rows.contract_rows() |> Enum.flat_map(fn {f, _} -> String.split(f, ";") end)` gives
exactly 61 across 32 rows, 28 with more than one. So the instrument is a semicolon, and EV-2's
objection to `@clauses` — "punctuation, not semantics" — applies here unchanged. What it cannot
see:

* **7 of the 61 carry a comma or an explicit `AND`** and are therefore certainly under-split:
  `developer closed, check capacity eligible`; `sealed stream has no valid candidate, verified
  exit/timeout`; `proved no ref change, command infrastructure failed`; `every owned session AND
  non-session claim terminal, cleanup reconciled`; and the three R4a rows, where the comma
  separates the role from its condition.
* **Slashes mean two different things and the split reads neither.** `queued/blocked` is a
  disjunction of phases; `no pause/drain/cancel` is a conjunction of three prohibitions;
  `dependencies/resources/profile/reservation eligible` is a conjunction of four.
* **The witness contradicts the denominator inside this document.** Row :467 splits to 3, and
  the measurement table below tests **5** — no cancel, no pause, no drain as separate rows.

This is why EV-6 cannot be bought cheaply by deriving conjuncts from punctuation, which was the
obvious way to do it without touching the contract. Obligation boundaries are a human judgement,
and hand-placed IDs are how that judgement gets recorded — the same judgement EV-2 adds to
outcome cells. The sequencing below ("with EV-2, not before it") holds for a measured reason
rather than for the filing convenience originally given. **The true obligation count is unknown
until the annotation pass is done; 61 is a floor.**

**Why that is not merely incomplete.** An unimplemented *outcome* clause shows up as uncited —
recorded, visible, countable. An unimplemented *precondition* shows up nowhere:

| mechanism | why it cannot see a missing precondition guard |
|---|---|
| Clause coverage | counts outcome cells only; from-cell conjuncts are not in either list |
| Row coverage | the row still drives — the scenario *satisfies* the conjunct instead of testing its negation |
| Guard reachability | keyed by error atom, and a guard that was never written has no atom |
| Mutation sweep | neutralises guards that exist; it cannot neutralise an absent one |
| `State.valid?/1` | shapes |
| `SemanticInvariants` | no clause about controls |

All six blind in the same direction, which is why review 3's question — "does each scenario drive
the row it is NAMED for, or something adjacent?" — has a second form nobody asked: **a
conjunctive precondition needs a refusal test per conjunct, and nothing checks that it has one.**

**The witness, and it is not subtle.** Row **:467** is "queued;
dependencies/resources/profile/reservation eligible; **no pause/drain/cancel**".
`do_transition("launch_planned", ...)` guards on `require_phase`, `require_no_open_developer` and
`require_cleanup_complete`, and consults none of the three. Measured at depth 6:

| condition | reachable states | accept a new `launch_planned` | shortest path |
|---|---|---|---|
| no cancel | 2,642 | **115** | 2 events |
| no pause | 2,304 | **101** | 2 events |
| no drain | 2,304 | **101** | 2 events |

Two events from empty. Worse than "launch does not check them": `paused` and `draining` are
written by `control_changed` (`kernel.ex:977-984`) and **read by no transition in the kernel**.
The reducer stores two control flags that affect nothing.

**Scope.** Enumerate from-cell conjuncts the way EV-2 proposes to enumerate outcome clauses, and
require each to be either asserted by a refusal test pinned to an exact atom (rule 5) or recorded
as deliberately outside the reducer with its reason. The second category is real and must stay
expressible: eligibility, "authenticated reset grants", and "proved no ref change" are protected
policy the kernel may not restate, which `require_settlement_source` already records at its own
site. The distinction to encode is **reducer-owned state vs protected fact** — `paused`,
`draining` and `cancel_requested` are all reducer-owned, which is exactly why row :467's three
conjuncts have no defence.

Red control per rule 1: a fixture row whose from-cell carries a conjunct no refusal test pins,
which must fail.

**Sequencing.** The row-:467 guard is its own candidate and comes first — it is a live reachable
defect and does not need this mechanism to exist. EV-6 then prevents the next one. It subsumes
part of EV-2: if clause IDs are being added to the contract's governing tables, from-cell
conjuncts should get them in the same pass rather than in a second edit of the same file.

**Cost.** Moderate, and it shrinks EV-2's if done with it.
