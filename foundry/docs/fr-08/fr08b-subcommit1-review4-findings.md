# FR-08B subcommit 1 — fourth independent review findings

Date: 2026-09-21

Reviewer: fresh Claude Fable 5.1 session, independent of the implementer and of the three
previous reviewers, per [the briefing](fr08b-subcommit1-review4-briefing.md).

Candidate: `34d6833` on `repair/fr08b-kernel`. Base: `main` at `a319b39`. Commits after the
candidate verified documentation-only (`git diff --stat 34d6833 HEAD`: two `.md` files).

## Verdict: BLOCK

Three kernel defects with short reproducing sequences (findings 1–3), each an instance of
the same-sibling pattern the previous three reviews named, and two of the five mechanisms
pass while measuring less than they claim (findings 4–5). The row-driven method and the
clause pinning are sound and should be kept (findings 7–8). The four "genuinely
unreachable" claims hold (finding 6).

Every defect below was reproduced by executing the kernel, not by reading. The probe is a
single ExUnit file driving `Kernel.apply/2` with the same event shapes as
`r4_coverage_test.exs`; the sequences are inline so they can be re-driven without it.

## Blocking findings

### 1. `review_settled` erases a recorded verdict — R4's precedence rule is violated in one event

**Sequence** (from the coverage suite's `verdict("approved")` fixture, i.e. admit → launch
→ freeze → seal X1 → close X1 → checks_started → check_planned C1 → check_recorded passed →
review_planned R1 → stream_sealed R1 → review_recorded approved):

```
review_settled {attempt A1, execution R1}
```

**Result**: accepted. `attempt.review` becomes `nil`, attempt and ticket return to
`awaiting_review`, the reviewer infrastructure ordinal is charged. Same for `rejected` and
`correction`.

**Rows violated**: R4 prose, "A valid frozen developer candidate or **validated review
result takes precedence over later execution exit status**." R4a's reviewer row is
conditioned on "frozen candidate **awaiting review**" — not one with a verdict. R4's
scheduling paragraph: "waiting or unknown ownership is visible, **not charged as a launch
failure**" — a reviewer that sealed its stream and delivered a verdict is charged as a
non-start.

**Pattern**: the developer sibling is guarded (`launch_settled` requires ticket
`developing`, which `artifact_frozen` leaves) and the integration sibling is guarded
(`require_no_ref_receipt` on `integration_settled`). The reviewer sibling is not. This is
the fourth review to find one rule applied to some siblings and not others.

**Fix is one existing guard**: `:ok <- require_no_recorded_verdict(ticket)` in
`review_settled`'s `with`. Then drive it: a `nonstart_reviewer` refusal after a verdict,
asserting the exact atom.

**Why no mechanism saw it**: the row harness parses two tables; the precedence sentence is
prose below them, so no row cites it (finding 8). The prober does propose `review_settled`
after a verdict, but unseeded depth-7 search reaches zero verdicts (finding 4) and no
exhaustive invariant says a verdict is never erased.

### 2. `check_settled` deletes a `passed` receipt; the attempt then reaches review with a mandatory check gone

**Sequence** (from the `checking` fixture):

```
check_planned  C1 / K1
check_planned  C2 / K2
check_recorded C1 passed
check_settled  C1 / K1          <- accepted; checks map is now ["C2"]
check_recorded C2 passed        <- attempt phase awaiting_review, checks ["C2"]
```

**Rows violated**: R4 "Check run … Execution result: **separate write-once sealed
result**"; R4a worker row "Preserve … **verified inputs** … infer no successful check …
receipt" — it does not infer one, it erases one; R4 row 11 "**all** mandatory check
receipts passed" is then satisfied by an attempt that lost one of its mandated checks.

**Fix is one existing guard**: `:ok <- require_check_unsettled(ticket, check_id)` in
`check_settled`. A retryable run (`timed_out`, `failed/infrastructure_failed`) is reset to
`pending` by `check_planned` before any new execution exists, so this refuses only the
case where a receipt is already sealed.

### 3. Stale `resume_phase` produces livelocked states outside R4's phase pairs, in 7 events

The implementer disclosed the first case in the log ("the guards refuse it, so nothing is
broken") and left it for review. It is broken: the ticket cannot make progress by any
productive event, only by cancellation. And it is not one case — every phase-advancing
transition leaves `resume_phase` untouched, and `require_honest_resume_target` accepts the
stored value unconditionally, so each retained target becomes a lie one transition later.

**Sequence 3a** (found by the exhaustive search at depth 7 when given the invariant it lacks):

```
ticket_admitted queued
launch_planned  A1 / X1
launch_settled  X1               -> queued, resume_phase developing   (R4a, correct)
launch_planned  A1 / X2          -> developing
artifact_frozen                  -> awaiting_review, attempt candidate_frozen, resume_phase STILL developing
ticket_blocked  resume developing   (honest: stored target)
ticket_unblocked developing      -> ticket developing, attempt candidate_frozen, candidate cand-1
```

From here: `checks_started` → `wrong_source_phase`; `attempt_settled` exhausted / failed /
blocked → `wrong_attempt_phase`; `artifact_frozen` → `wrong_attempt_phase`. `launch_planned`
is accepted (after sealing and closing X2) and opens a third developer execution on a
frozen attempt, which is R4 row 7's "No new developer" broken. No path to review or
integration exists.

**Sequence 3b** (second instance, same defect, reviewer side):

```
… reviewing fixture …
review_settled  R1               -> awaiting_review, resume_phase awaiting_review (correct)
review_planned  R2
stream_sealed   R2
review_recorded approved
reviewer_closed R2               -> ready_to_integrate; resume_phase STILL awaiting_review
ticket_blocked  resume awaiting_review
ticket_unblocked awaiting_review -> ticket awaiting_review, attempt ready_to_integrate
```

From here `review_planned` → `wrong_attempt_phase`, `integration_planned` →
`wrong_source_phase`, `checks_started` → `wrong_attempt_phase`.

**Rows violated**: R4's phase tables give (ticket, attempt) pairs; `developing` with
`candidate_frozen` and `awaiting_review` with `ready_to_integrate` are not among them.
"Unlisted public transitions are rejected." R4a reviewer row: "the same attempt/candidate
remain resumable" — resumable to where they were, not to a phase the candidate predates.

**One-site fix** rather than clearing the target in every advancing transition (which is
the same-sibling trap again): in `require_honest_resume_target`, accept the *stored* target
only when the ticket is `queued` or `blocked` — the two phases in which R4a's rows leave a
retained target — and only the current phase otherwise. Both sequences are then refused at
`ticket_blocked`, and the legitimate R4a case (queued ticket, stored `developing`) still
drives. Then add the invariant to `r4_exhaustive_test.exs` so the search proves it:
`developing ⇒ active`, `awaiting_review ⇒ candidate_frozen|checking|awaiting_review`,
`reviewing ⇒ reviewing`, `ready_to_integrate ⇒ ready_to_integrate`, `integrating ⇒
integrating`. With that invariant the search reports sequence 3a in the existing 3-second
run — I verified this.

This also reopens review one's finding 9 and review three's resume-target finding as
incompletely closed: the target was made honest at the moment of parking and not
afterwards.

### 4. Mechanism — the exhaustive suite proves two of its six invariants over zero witnesses

Measured on `34d6833` at the suite's own depth 7 and proposal set: **58,369 states; 0
integrated tickets, 0 ref receipts, 0 recorded verdicts, 0 `ready_to_integrate`, 0
`integrating`, 3 `reviewing`.**

"An attempt holding a ref receipt can only be terminally integrated" and "an integrated
ticket always has a ref receipt behind it" are therefore vacuous at the bound they are
asserted over. The "meaningful space" guard asserts only `queued developing awaiting_review
blocked`, which are reached by depth 3, so it would not notice.

This is exactly the briefing's own definition of the failure — a mechanism that passes
while measuring nothing — and it is the mechanism subcommits 2–5 will lean on. The
implementer measured the same emptiness for the unseeded search (0 verdicts at depth 8)
and built `:from` to answer it, but **no committed test uses `:from`**; the 164,648-state
seeded evidence is an ad-hoc run recorded in prose.

**Fix**: in `r4_exhaustive_test.exs`, run a second search seeded from a driven
`integrating` fixture (the coverage suite's, via `:from`) and assert the two integration
invariants and the terminal-evidence invariant over it; assert a witness count for each
invariant's antecedent (≥ 1 ref receipt, ≥ 1 integrated, ≥ 1 verdict) so a search that
stops reaching them fails instead of passing.

### 5. Mechanism — the sweep's population is one syntactic shape, and an untested guard sits outside it

The sweep's "108 call sites" is the count of `<- require_…(` matches, which I reproduced.
It is not the count of guard calls:

- **Six guard calls are inside `require_settlement_source/2`** (kernel lines 1524, 1541,
  1554, 1563, 1567, 1577), reached through *one* swept site in `attempt_settled`.
  Neutralising that site clears all seven disposition branches at once if any one test
  goes red — the global-replacement defect the log describes, one level down.
- **`integration_already_issued`** (the `superseded_base`-from-`integrating` branch) is
  asserted by **no test file**. `base_moved` drives only from `ready_to_integrate`. The
  sweep structurally cannot report it, so "6 survive, all six recorded as unable to fire"
  omits at least one untested guard that *can* fire.
- **Eighteen refusal sites are not `require_` calls at all** (`open_attempt`,
  `add_execution`, `add_check`, `cancellation_finalized`'s two branches,
  `ticket_unblocked`'s `resume_phase_disagrees`, both `ticket_terminal` sites, the
  `invalid_*` payload branches). They are covered only by the atom-level reachability
  suite, never per site.

Fifth time this tool's number is weaker than its claim. **Fix**: match every
`require_[a-z_]+(` not on a `defp` line and splice `:ok` at that offset — the splice is
valid in `do:`, `with`, and bare-expression positions — and print the count the regex does
*not* cover next to the count it does, so the claim is bounded by construction.

## Non-blocking findings

### 6. Dead-guard detection: the four "genuinely unreachable" claims hold, but two are protected by nothing

I verified each by enumerating every write site of the field the guard reads, not by trusting
the search:

- `checks_not_passed`: attempt phase `awaiting_review` is written only by
  `maybe_finish_checks` (all passed, or policy-empty with none), `review_settled` and
  `reviewer_closed`'s no-verdict branch; the last two do not touch `checks`, and every
  check-mutating event requires `checking`. Holds.
- `reviewer_already_closed`: a reviewer execution closes only via `review_settled` (nils the
  review) or `reviewer_closed` (nils it, advances on approval, or leaves a recorded verdict
  that `require_no_recorded_verdict` refuses first). Holds.
- `no_stored_resume_phase`: all seven writes of `phase = blocked` set a target in
  `@resume_phases`. Holds.
- `candidate_frozen`: `candidate_id` and phase `candidate_frozen` are written together, and
  nothing writes attempt phase back to `active`. Holds.
- `reviewer_closed`'s approved-branch `require_attempt_phase(~w(reviewing))`: the only
  events moving an attempt off `reviewing` after an approval are that branch (which closes
  the execution) and `attempt_settled` (after which the first `cond` arm returns). Holds.
  Note that after finding 1 is fixed this reasoning is unchanged.

The weakness: for the two entries that need a verdict, `resurrected` in the ratchet can
never fire because depth 7 reaches zero verdicts (finding 4). They are "unreachable" in the
suite by emptiness, not by search. Seeding fixes this the same way.

### 7. Clause coverage is honest; the fragmentation rule undercounts rather than flatters

Measured: 58 fragments are counted cited and **0** of them only via another row's
citation, so the flattened cross-row `cited` list is not flattering the count. One
artefact in the other direction: `nonstart_reviewer` cites "…; never enter developer retry
or correction" and the fragment "never enter developer retry or correction." (trailing
period) is listed in `@uncited` — a citation spanning `;` is not matched against its second
fragment. Conservative, so not blocking; strip terminal punctuation before comparing.

### 8. Row coverage: what the two tables cannot see

The parser reads R4's transition table and R4a's domain-owner table. Roughly half of R4 is
prose outside them — the precedence sentence (finding 1's rule), "Exhaustion seals the
current attempt", the controls paragraph, the scheduling paragraph, R4a's "Control state is
evaluated after recording non-start" and its restart sentence. None of these can be cited,
so the "54 asserted / 59 uncited" ratio is over the tables only. Record that boundary in
the design note; consider a third parsed source (numbered prose sentences) for the rules
that have already bitten.

Citations are pinned and the outcome-cell drift check works as described. I did not find a
citation satisfied by an accidental substring within its own row. The `nonstart_reviewer`
scenario asserts "immutable candidate/check receipts" only for the no-verdict state, which
is how finding 1 hid.

### 9. A cheaper mechanism for dead call sites

`KernelSearch.expand/4` has the event type in hand when it records a refusal. Record
`{event_type, reason}` pairs instead of atoms and key `@unreachable` by the pair. Both
known dead sites — `ticket_reset/:attempt_still_active` and
`reviewer_closed/:wrong_attempt_phase` — become expressible at search cost (seconds, not an
hour), and a guard that stops firing from one handler while its twins still fire is
reported. It does not separate two calls of the same guard within one handler; that
residue is what the sweep is for.

### 10. `ticket_blocked` and `@blockable_phases`

Defensible. R4 contemplates blocking with live work ("otherwise retain the lease and block
affected work", "If cleanup is unknown, block affected work"), and the kernel cannot see
allocation, so tying the reason to a prior settlement is protected policy. `reviewing` and
`integrating` have no R4a row blocking from them directly, but drain and unknown-cleanup
prose do. The real weakness is the honesty rule, which is finding 3, not the phase list.

### 11. Committed-while-held check

`git log -S'<- :ok' a319b39..34d6833 -- foundry/lib` returns only `421c0b2` and its
restore. No `:ok <- :ok` at the candidate. No sentinel present. Working tree clean before
and after this review.

### 12. Evidence spot-checked

- `r4_coverage_test.exs` at seed 0, fresh `MIX_BUILD_PATH`: **39 passed**.
- Depth-7 search on the candidate: 58,369 states; 10,024 hold an exhausted ticket, which
  matches the log's figure. (The log's "22,180 at depth 7" predates the forged-reference
  proposals.)
- The remaining numbers were taken as supplied.

## The nine review-three closures

Sampled through findings 1–3 rather than re-verified one by one, per the briefing's
priority order. The execution-binding closure holds (`close_execution` enforces role for
every settlement). The resume-target closure is the one findings 3a/3b reopen. The
`ticket_blocked` split (priority-2 question) is faithful to R4a's three at-limit clauses.

## Disposition

Findings 1 and 2 are each a one-line reuse of an existing guard plus a driven refusal.
Finding 3 is a one-site rule change plus one exhaustive invariant. Finding 4 is a seeded
second search with witness assertions. Finding 5 is a regex and a printed bound. None
needs new vocabulary. The mechanisms are worth keeping; they need to measure the space they
claim to.
