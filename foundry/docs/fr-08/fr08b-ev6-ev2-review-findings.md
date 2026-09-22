# FR-08B EV-6 / EV-2 — independent review of the clause-ID candidate

Date: 2026-09-22

Reviewer: Claude Fable 5.1, fresh session, no stake in the candidate. Brief:
[the review briefing](fr08b-ev6-ev2-review-briefing.md), 25-minute budget, seven
enumerations in priority order.

Candidate inspected: `16fc73db..dc9582b3` on `repair/fr08b-kernel`, eleven commits. No `lib/`
file changes. Did not run the gate; ran the two shipped probes and the coverage test file alone.

## Verdict

**BLOCK**, on findings 1 and 2. The numbers reproduce — every count in the commit messages
and the doc tables is what the artifact prints — but three documents carry claims the tree
contradicts, and the "enforced by the absence of a transition" reading is wrong for two of
its four witnesses in two different ways.

## What reproduces

Everything the briefing quotes, checked rather than accepted:

```
cd foundry
elixir bin/contract_annotation_diff.exs 16fc73db
  # 196 markers added, contract text identical; both red controls pass
elixir bin/refusal_sites.exs
  # 71 sites, 47 inside require_*, 24 outside, 9 of those inline in do_transition
grep -o '{R4a\?\.[0-9]*\.f[0-9]*}' docs/WORKFLOW-CONTRACT.md | wc -l      # 72
grep -o '{R4a\?\.[0-9]*\.o[0-9]*}' docs/WORKFLOW-CONTRACT.md | wc -l      # 124
grep -o '{R4a\?\.[0-9]*\.[fo][0-9]*}' docs/WORKFLOW-CONTRACT.md | sort | uniq -d   # none
TMPDIR=/private/tmp mix test test/pramana_foundry/workflow/r4_coverage_test.exs
  # green; prints "124 - 64 asserted, 60 recorded uncited"
```

`@from_obligations` (test file lines 403–668) holds 63 distinct keys: 40 guarded, 16 input,
5 protected, 1 effect, 1 unguarded; `@from_unclassified` holds 9. Matches `dc9582b3`'s message.
Twenty-seven `kernel.ex:NNN` citations in the disposition entries were spot-checked by line
and all land on the guard they name (one nit under observations).

`require_all_executions_closed/1` (`kernel.ex:1303`) and `require_cleanup_complete/1`
(`:1746`) are the same predicate: both iterate attempts → executions and test
`lifecycle != "closed"`, one with `Enum.any?` and one with a comprehension. Claim confirmed.

## Finding 1 — three documents carry claims the tree contradicts. BLOCK.

This is the shape the previous three rounds blocked on, and the candidate's own commit
`c40ae691` says it caught one instance of it. Three remain at `dc9582b3`.

**1a. `docs/EVIDENCE-TOOLS.md:31`, the mechanism table.** The "From-cell classification" row
says each ID "must be `{:guarded, atoms}` with atoms the kernel declares, `{:protected, why}`,
or `{:unguarded, why}`". The executable artifact has five dispositions — `{:input, why}` and
`{:effect, why}` were added at `f0ae495e` and `ffff6f92` — and 17 of the 63 entries use them.
The repository's canonical description of the mechanism is the three-category set that the
candidate's own commit message calls "wrong in the expensive direction".

```
grep -n 'From-cell classification' docs/EVIDENCE-TOOLS.md
grep -c '{:input\|{:effect' test/pramana_foundry/workflow/r4_coverage_test.exs
```

**1b. `docs/fr-08/fr08b-evidence-reduction-tickets.md:308`.** The EV-6 row says
"delta `16fc73db..f0ae495e`" in the same cell as "63 of 72 classified". At `f0ae495e` the
count was 12 of 72 (its own commit message). The delta reference is three refresh cycles
stale next to a count that was updated.

**1c. `docs/fr-08/fr08b-ev6-ev2-review-briefing.md:3-4`.** "Delta to review:
`16fc73db..ffff6f92`, seven commits" and "Gate: green at `f2c73a63`". The file was last
modified at `dc9582b3`, the delta is eleven commits, and the body of the same file quotes
`dc9582b3`'s figures (63 of 72, four witnesses). The task prompt that commissioned this review
had to supply the correct delta and gate itself.

```
git log --format='%h %s' -- docs/fr-08/fr08b-ev6-ev2-review-briefing.md | head -1   # dc9582b3
git log --oneline 16fc73db~1..dc9582b3 | wc -l                                       # 11
```

None of these is a wrong number in the artifact. All three are prose that stopped tracking
the artifact, which is the defect class this candidate exists to make impossible for the
coverage number. Fix: one edit across the three files (rule 4).

## Finding 2 — "enforced by the absence of a transition" is wrong for two of four witnesses. BLOCK.

The held-entry comment (test file ~lines 620–640) and the briefing state that R4.07.f1/f2,
R4.19.f1 and R4a.03.f1/f2 "each name a from-state that nothing on their own path refuses"
and that "in each case the transitions the row FORBIDS are refused by other handlers". Read
against the three handlers:

**2a. R4.19.f1 is consulted on the crash path, inline, and already fits `{:effect}`.** The
comment says `reviewer_closed`'s `require_attempt_phase ~w(reviewing)` "sits only inside the
`verdict == "approved"` branch, which the crash path never reaches". True of the `require_*`
call. But the crash branch itself is guarded by the phase:

```
kernel.ex:835   is_nil(verdict) and attempt(ticket, attempt_id)["phase"] == "reviewing" ->
kernel.ex:844   true -> {:ok, ticket}
```

The event is accepted either way and the conjunct decides the outcome — a no-verdict close
on an attempt not in `reviewing` closes the execution and silently changes nothing else.
That is `{:effect, why}` by the candidate's own definition ("implemented as a BRANCH INSIDE
THE EFFECT: the event is accepted either way and the conjunct decides the outcome"). No sixth
category is needed for this witness; the entry was held because the reading stopped at
`require_*` calls, which is the same boundary error `e81cdabe` corrected for refusal sites.

**2b. R4a.03.f2 "planning execution" is not enforced by anything, because the kernel does
not record one.** `pm_launch_planned` is `{:ok, objective}` unchanged (`kernel.ex:248-250`);
`pm_launch_settled` is `consume_infrastructure_ordinal(objective, "pm")` with no guard
(`:255-256`). So a `pm_launch_settled` on an objective that never planned a launch is
accepted and charges a PM infrastructure ordinal. Compare the developer row R4a.01, whose
`launch_settled` guards `require_phase ~w(developing)` and `require_active_attempt/2`
(`:442-443`) and is classified `:guarded`. The comment's "the transitions the row FORBIDS are
refused by other handlers" has no handler to point at here: nothing refuses settling a launch
that was never planned. This is row :467's shape — a reducer-owned precondition nothing
consults, with a state-changing effect (an ordinal consumed) proceeding from a state the row
does not cover — or, more precisely, a precondition the state cannot represent. Either way it
belongs in `{:unguarded, ...}` as a recorded defect, not in a held list explained by a category
that would make it look fine.

```
sed -n 246,256p lib/pramana_foundry/workflow/kernel.ex
```

**2c. R4.07.f1 and R4a.03.f1 — the reading holds.** `execution_observed` (`:548-563`) guards
attempt, execution, not-closed and open-lifecycle, and its effect is phase-independent; the
forbidden transition (exhaustion from `candidate_frozen`) is refused by
`require_settlement_source/2`, which the scenario pins to `:wrong_attempt_phase`. `R4a.03.f1`
"PM" is the event type, i.e. `:input` by the candidate's own definition, as is `R4.07.f2`
"developer exit/timeout/abnormal exit" (it is what the observation reports). Neither needs
holding.

Net: of the four witnesses, one is `:effect`, two are `:input`, one is a defect, and one
(R4.07.f1) is the only candidate for a genuine "absence of a transition" — which is the
single witness the candidate said was not enough to invent a category on. The sixth
disposition is not owed. What is owed is reclassifying these five and recording R4a.03.f2.

## Finding 3 — enumeration 1: the four reclassified `@uncited` entries. Observation.

Each checked against its scenario and its `@clauses` entry:

| row | clause | assertion | verdict |
|---|---|---|---|
| `nonstart_pm` | R4a.03.o2 "infer no proposal" | `objective["proposals"] == %{}` (line 2144) | asserted |
| `developer_exit_after_freeze` | R4.07.o2 "preserve frozen candidate" | `candidate_id == "cand-1"`, `phase == "candidate_frozen"` (1062-1063) | asserted |
| `nonstart_reviewer` | R4a.02.o4 "never enter developer retry or correction" | `ordinals["developer"] == 0`, `disposition == nil` (2058, 2054) | asserted |
| `terminal_rejection` | R4.26.o2 "preserve terminal facts" | `state[...]["disposition"] == "rejected"` after a refused apply (1874) | asserted, weakly |
| `blocked_result` | R4.09.o2 "close developer" / R4.09.o3 "no review" | `lifecycle == "closed"` (1193) / nothing | cited / `@uncited` — correct split |

The `terminal_rejection` assertion is on the pre-state: `Harness.apply/2` returned
`{:error, :ticket_terminal}` and `state` was never rebound, so the assertion cannot fail
independently of the refusal one line above it. In a pure reducer a refusal is preservation,
so the citation is not wrong, but it is the weakest form the known weakness "a citation is not
an assertion" takes. Not a block.

Related: `nonstart_pm` cites R4a.03.o6 "Admit no ticket and create no objective allocation"
and asserts only `state["tickets"] == %{}`. The second half is not asserted by anything and
the obligation is one ID, so it cannot be half-uncited. The known weakness, instantiated.

## Finding 4 — enumeration 5: `bin/refusal_sites.exs` cannot see the one spelling the repo already knows about. Observation.

The scanner is `~r/\{:error,\s*:(\w+)\}/`. `kernel.ex:80` refuses via
`|> ok_or(:unknown_entity_kind)` inside `apply/2`, which is the exact site Sol's finding 2 named
as invisible to `declared_reasons/0` in the previous round. So "of 71 `{:error, :atom}` sites,
24 are outside the sweep" is correct as literally scoped and under-counts refusals outside the
sweep by at least one; the red control pins two sites the regex does see and none it does not.
The doc paragraph lists function-head matching as an unseen shape but not `ok_or`. Not a block
because the denominator is stated (rule 2); it should say "literal" and the script should
count `ok_or(:` or say why not.

```
grep -n 'ok_or(:' lib/pramana_foundry/workflow/kernel.ex     # :80
```

## Finding 5 — enumerations 3, 4, 6, 7. Observations, nothing to answer.

- **Boundaries (3).** "Every existing quote falls inside exactly one obligation" is checked at
  test time by `every cited clause still quotes the obligation it names`
  (`String.contains?(obligations[id], quote)`) and by the `==` check on `@uncited`; a trailing
  fragment after a cell's last marker would surface as a `nil` ID in `unaccounted`. Ran green.
  No marker duplicated. I found no span that absorbs an adjacent clause's text.
- **R4.02.f1 and R4.27.f1 (4).** `resolve_entity/3` at `:145-153` returns
  `{:error, :entity_already_exists}` for a creating event on an existing entity and the
  `:absent` head is the only `ticket_admitted` clause; `:392` is the inline `if` producing
  `:ticket_terminal`. Both readings hold. `R4.26.f2`'s "ordinary" = the exclusions in
  `refuse_terminal_ticket/2` (`:212-219`) also holds.
- **R4.12.f2 (6).** `maybe_finish_checks/1` (`:1021-1029`) advances only when
  `policy_empty_checks` and `statuses == []`, or statuses non-empty and all `"passed"`. A
  `failed`/`infrastructure` status leaves the attempt in `checking`. Nothing is lost by there
  being no refusal; the receipt must be recorded either way. `:effect` is right. The five
  `:input` entries all name the event's own payload or type; none hides a state precondition.
- **Red controls (7).** From-cell: all three assertions are exact-list equalities, so a
  `check/4` that reported one extra or one fewer item fails, not only one returning `[]`.
  Outcome: `unaccounted == [sample]` and `absent == ["R4.99.o1"]` are exact; `sample in
  both.both` is membership only, which a `partition/3` returning every ID as `both` would
  pass — but that detector fails the main test's `found.both == []` first. Adequate.
- **Nit.** `R4.04.f3`'s entry cites `control_changed (kernel.ex:977-984)`; 977 is a blank
  line and the `paused`/`draining` writes are at 983-984. Harmless.

## What must be answered before ACCEPT

1. Finding 1a, 1b, 1c: one edit that makes EVIDENCE-TOOLS' table, the tickets table and the
   briefing header say what the tree says.
2. Finding 2a: reclassify `R4.19.f1` as `{:effect, ...}` citing `kernel.ex:835`.
3. Finding 2b: record `R4a.03.f2` as `{:unguarded, ...}` — a PM settle with no planned launch
   is accepted and charges an ordinal — or show the handler that refuses it.
4. Finding 2c is optional: `R4.07.f2`, `R4a.03.f1` as `:input`; `R4.07.f1` stays held or is
   the one witness for a category the candidate should then decide on with one witness, not four.
