# FR-08B subcommit 1 — independent review findings

Date: 2026-09-20

Reviewer: fresh Claude Fable 5.1 session, independent of the implementer, per
[the briefing](fr08b-subcommit1-review-briefing.md).

Candidate: `be1e19c` on `repair/fr08b-kernel`. Base: `main` at `a319b39`.

## Verdict: BLOCK

The candidate delivers B1's envelope-level properties — closed vocabulary, exact payload
key sets, revision and sequence ordering, no entity creation by projection. It does not
deliver the reducer-level custody R4 requires, and two of its findings reproduce B1's own
headline counterexample one step removed.

The implementer confirmed findings 1, 2, 4 and 8 by direct reading before accepting the
verdict; the reviewer reproduced all eight blockers with hand-driven sequences.

## The finding that matters most

**The property suite's evidence was standing on a kernel defect.**

The briefing asserted that `review_recorded:approved` → `reviewer_closed` fires about once
across the suite, and that the three integration rows sit behind that single sequence — a
depth limit rather than a block. Measured on the suite's exact configuration, that sequence
fires **zero** times, and no walk ever reaches `ready_to_integrate`.

Worse, the review rows the ratchet counted as *reached* were reached through a defect: all
nine attempts that arrived at `review_planned` did so only because `check_recorded:passed`
overwrote a non-passed check (finding 4). Twenty-nine such overwrites occur across the 65
walks. Finding 5 is the other half — `check_settled` permanently poisons the attempt — so
two defects were cancelling each other, which a variant-blind ratchet cannot see.

The integration rows *are* reachable: a hand-built R4-legal sequence reaches all three,
and so do the same seeds with `check_settled` removed from the proposal set. The kernel is
not hard-blocked. The stated explanation was simply false, and the real causes are kernel
finding 1 and the prober's inability to admit a replacement ticket.

This is the fourth time a coverage claim in this repair has been refuted by executing it
rather than reading it, and the first time the refuted claim was the evidence mechanism
itself.

## Blocking findings

| # | Defect | R4/R4a row violated |
|---|---|---|
| 1 | `attempt_settled` has no source-state guard; only `integrated` is guarded | Terminal states reachable without their lifecycle; B1's premise; the module's own property 3 |
| 2 | `cancellation_finalized(after_integration)` never checks that integration occurred | "If integration occurred: integrated and cancel_finalized(after_integration)" |
| 3 | Executions in a settled attempt can never be closed; developer close requires a frozen candidate | "closed requires verified termination"; rows 8, 9, 11, 13; R4a restart |
| 4 | `check_recorded` is not write-once; a failed check relabelled `passed` reaches review | "failed candidate never goes to approval"; "separate write-once sealed result" |
| 5 | `check_settled` permanently poisons the attempt, masked by finding 4 | R4a check-worker row; R4 row 13 "pending same phase" |
| 6 | `@known_unreached` rests on a false justification and on finding 4 | — (evidence integrity) |
| 7 | `integration_recorded`/`attempt_settled` split is not atomic or exclusive | "integrated ticket; terminal integrated attempt" |
| 8 | `unknown` counts as closed for the integration row | "prior role/check workers closed"; R4a `unknown` permits no replacement |

Finding 2 is reachable in three events from an empty state and yields an integrated ticket
with zero attempts, no candidate, no checks, no review and no ref receipt. That is B1's
headline counterexample, which subcommit 1 exists to eliminate. No walk could see it: the
prober proposes only the `cancelled` disposition.

## Significant findings

- **9. Prober circularity on `ticket_parked`, confirmed.** The prober proposes
  `resume_phase` = the ticket's current phase; `require_honest_resume_target/2` accepts it;
  together they produce a blocked ticket with no reason and no resume target, from which
  resume fails forever. Both sides moved to agree on a state R4 forbids. The honest kernel
  fix — exclude `blocked` and terminal phases from a resume target, and keep the stored
  target when parking an already-blocked ticket — was not made. A second case: the
  prober's at-limit park overwrites the `developing` target R4a requires `launch_settled`
  to retain.
- **10. The prober is stricter than the kernel on settlement-to-execution binding.**
  `reviewer_closed` gained `require_reviewer_execution`; `review_settled` did not, so it
  closes any execution and leaks the reviewer's. The prober's own role filter hid this.
- **11.** The `integrating` retry and block rows are unexpressible.
- **12. The infrastructure ordinal is one counter per ticket shared by every role, and
  objectives have none** — while R4a sets the limit "per role and work owner" and names a
  PM limit.
- **13.** R4's execution `result` entity state is declared and never written.

`role_execution/2` selecting only open executions was judged **not** circular: R4a's
"duplicate or late receipt cannot increment the ordinal" is satisfied by the kernel's own
refusal. That suspicion is discharged.

## Lesser findings

14 policy-empty check set unreachable; 15 `ticket_parked` accepts `developing`;
16 `cancellation_finalized` does not require owned executions closed; 17 the reachability
ratchet is type-level while the prober's coverage model is variant-level, and findings 2
and 8 sit exactly in that gap; 18 the restart property is a determinism plus JSON-shape
check mislabelled as an R4a restart property, and the sequence-monotonic property tests
the walker's own counter rather than the kernel; 19 the terminal-ticket guard is
over-broad, refusing cleanup evidence on integrated tickets rather than only transitions.

## Disposition of the eight `202b8e4` corrections

Right: 1, 6, 7 (verdicts), 8 (`reviewer_closed`). Right direction, over-broad: 2 (see 19).
Right with a hole beside it: 4 (`unknown`, see 8). Made the test pass without satisfying
the row: 3 (see 7). Half a fix: 5, applied without role binding (see 10).

Corrections 7 and 8 each applied a correct principle to one event and not to its sibling —
write-once to verdicts but not checks, execution binding to `reviewer_closed` but not
`review_settled`. That pattern, not the individual misses, is the lesson.
