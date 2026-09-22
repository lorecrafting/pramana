# Review briefing: EV-6 and EV-2, the clause-ID candidate

> **FROZEN at the review point.** This is the brief as it was handed to the reviewer, and it is
> left that way deliberately: half-updating it is what the re-review blocked on. Every number below
> was true at `dc9582b3` and several are not true now — 63 of 72 were classified then, 67 now. For
> the current state read [the findings](fr08b-ev6-ev2-review-findings.md) and the implementation
> log, never this file.

**Delta reviewed:** `16fc73db..dc9582b3`, eleven commits, on `repair/fr08b-kernel`.
**Gate at that delta:** green — 949 passed / 13 skipped / 1 excluded, six commands, clean tree;
the run is recorded in the implementation log's gate table.
**Outcome: BLOCKED**, twice — see [findings](fr08b-ev6-ev2-review-findings.md).
**Time budget: 25 minutes.** A previous unbounded brief ran 41 minutes and produced a worse
review than a bounded one. Spend the budget on the enumerations named below, not on breadth.

Read only this delta. The kernel's behaviour is unchanged by it: no `lib/` file is touched except
as a *subject* of measurement. What changed is the contract's annotation and what the test suite
can say about it.

## What the candidate claims

1. `docs/WORKFLOW-CONTRACT.md` now carries 196 clause-ID markers — 72 on from-state cells, 124 on
   outcome cells — and **the contract's text is unchanged**. `bin/contract_annotation_diff.exs`
   strips the markers from both sides and diffs against a revision.
2. Every **from-cell** obligation must carry a disposition: `{:guarded, atoms, why}` with atoms the
   kernel declares, `{:protected, why}`, `{:unguarded, why}`, `{:input, why}` or `{:effect, why}`.
   **63 of 72** are classified; 9 are held with stated reasons. The last two categories were added during
   the work, not designed in — see enumeration 6.
3. Every **outcome** obligation is in `@clauses` or `@uncited`, never both and never neither.
   124 obligations: 64 asserted, 60 recorded uncited. The punctuation splitter is deleted.

## The enumerations to attack, in priority order

**1. The four stale `@uncited` entries — the highest-risk judgement in the candidate.**
I claimed that `nonstart_pm`, `developer_exit_after_freeze`, `terminal_rejection` and
`nonstart_reviewer` each *assert* a clause previously recorded as unasserted, citing one assertion
per scenario (`proposals == %{}`; `candidate_id` and `phase == "candidate_frozen"`;
`disposition == "rejected"` surviving a refused event; `ordinals["developer"] == 0` and
`disposition == nil`). If any of those readings is wrong, a clause that nothing asserts is now
recorded as asserted — the coverage number lying in the flattering direction, which is the exact
defect this candidate exists to remove. **Check all four against their scenarios.** The fifth,
`blocked_result`, I split into "close developer" (asserted) and "no review" (not) — check that too.

**2. Is "enforced by the absence of a transition" a real category, or an excuse?** Four held
obligations — R4.07.f1/f2, R4.19.f1 and R4a.03.f1/f2 — name a from-state that nothing on their own
path refuses. `execution_observed` has no phase guard and its outcome is phase-independent;
`reviewer_closed`'s `require_attempt_phase ~w(reviewing)` sits only in the `verdict == "approved"`
branch, which R4.19's crash path never reaches; `pm_launch_settled` has no guards at all. In each
case the transitions the row *forbids* appear to be refused by other handlers.

If that reading is right, a sixth disposition is owed and these are not defects. If it is wrong,
**some of these are row :467 again** — a reducer-owned precondition nothing consults — and this
candidate has five of them recorded as "held" instead of as defects. I did not decide it alone,
having just had to correct a refusal-site count I was equally confident about. **This is the
judgement I most want overruled if it deserves overruling.**

**3. The obligation boundaries.** 124 spans were placed to respect 118 pre-existing quotes. Ask
whether any span mis-assigns text: specifically, whether a `@uncited` obligation's span absorbed
text that an asserted clause covers, or the reverse. The property I relied on is "every existing
quote falls inside exactly one obligation" — test it independently rather than taking it.

**4. The 63 from-cell classifications.** Two are unusual and both are mine to have got wrong:
`R4.02.f1` claims "draft" means *no ticket exists*, enforced by `resolve_entity/3` pre-dispatch and
the `:absent` function head; `R4.27.f1` claims an inline `if` at `kernel.ex:392` guards "nonterminal
ticket" with `:ticket_terminal`. Note also that R4.16.f1, R4.17.f1 and R4.18.f1 are the same guard
site counted three times, because those rows share `review_recorded`. The mechanism only checks the atom is *declared*, never that the
named guard is the right one — so a plausible atom borrowed from the wrong handler passes. That is
the hole to probe.

**5. The measured gaps.** Two claims that will be quoted later, so they should be attacked now:
"24 of the kernel's 71 refusal sites are outside the sweep's population" (`bin/refusal_sites.exs`,
which corrects an earlier by-eye count of 9), and
"`require_all_executions_closed/1` and `require_cleanup_complete/1` are the same predicate under two
atoms". Both were derived by reading; neither ships with a runnable check.

**6. The two dispositions added mid-candidate.** `{:input}` and `{:effect}` were both forced by
reading, and both exist to avoid recording `:unguarded` where the contract is implemented. That makes
them the mechanism's softest spot: **either could be used to explain away a real hole.** Attack the
six entries that use them — R4.02.f2, R4.03.f2, R4.27.f2, R4.17.f2, R4.18.f2 (`:input`) and R4.12.f2
(`:effect`). For R4.12.f2 specifically, check `maybe_finish_checks/1` really does implement "all
mandatory check receipts passed", including the `policy_empty_checks` branch, and that nothing is
lost by there being no refusal.

**7. Vacuity.** `check/4` (from-cell) and `partition/3` (outcome) each return empty lists when
neutralised, and each is caught *only* by its red control. Verify that the red controls actually
constrain — that they would fail for a detector that is subtly wrong rather than only for one that
returns nothing.

## Known weaknesses, stated so the review does not spend budget rediscovering them

- **A citation is not an assertion.** Nothing here proves a scenario's assertions discharge the
  clause it cites. Five scenarios were read closely; 59 citations were not.
- **The from-cell mechanism proves a guard exists, not that it is the right guard**, and not that
  any test exercises it. `declared_reasons/0` reads `kernel.ex` with regexes, so a refusal spelled a
  fourth way reads as a false gap — the safe direction, but still a wrong answer.
- **Three rows' guards disagree with their from-cell**, recorded in the entries: R4.04 and R4.20
  admit a phase the row does not name, R4.11 guards more than the row states. R4.20's widening is
  licensed by R4.21 sharing the handler; R4.04's is not pinned by anything.
- **`R4.24.f2` and `R4.28.f3` are deliberately unclassified.** A disjunction whose branches want
  different dispositions, and a clause whose answer is in the contract rather than the kernel.
- **`bin/contract_annotation_diff.exs` was wrong once and is fixed.** It stripped only the new side,
  which is correct exactly while the baseline carries no markers; the second annotation pass reported
  every previously-annotated row as changed. Both sides are stripped now. Ask whether the fix is
  complete, not whether the bug existed.
- **`bin/clause_unit_probe.exs` was added at `d79b408a` and deleted at `1fcb8b63`.** It measured
  structures the later commit removes, and its header said it would go. Its numbers are in the log;
  git holds the probe.

## What would constitute a BLOCK

A claim in a commit message, a doc table or a disposition entry that measurement contradicts. That
is what the previous three rounds blocked on, every time: not wrong code, but a number or a claim
that could not be reproduced or was quietly stale.
