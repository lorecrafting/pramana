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

## Re-review of the answer — 2026-09-22

Reviewer: Claude Fable 5.1, fresh session, no stake in the candidate and not the author of the
review above. Brief: four questions, 20-minute budget. Delta re-reviewed: `dc9582b3..f749c080`,
two commits. Did not run the gate; ran the coverage test file alone, both probes, and one direct
kernel probe written for question 1.

### Verdict

**BLOCK**, on question 3 only. The two reclassifications are right — the `{:unguarded}` one is
now confirmed against the running kernel, not just by reading — the three `:input`/held calls are
right, and the floor is honestly labelled. But answering the block reproduced the block: the answer
left one claim standing in the file it edited, and re-created finding 1b's exact shape in two of the
three documents finding 1 was about. Each is one line. None of them is about the code.

### What reproduces

```
cd foundry
TMPDIR=/private/tmp mix test test/pramana_foundry/workflow/r4_coverage_test.exs
  # 49 passed; prints "124 - 64 asserted, 60 recorded uncited"
elixir bin/refusal_sites.exs            # 71 / 47 / 24 "(a FLOOR - see the header)" / 9 inline
elixir bin/contract_annotation_diff.exs 16fc73db   # 196 markers, content preserved, red controls pass
grep -o '{R4a\?\.[0-9]*\.f[0-9]*}' docs/WORKFLOW-CONTRACT.md | wc -l               # 72
grep -o '{R4a\?\.[0-9]*\.[fo][0-9]*}' docs/WORKFLOW-CONTRACT.md | sort | uniq -d   # none
```

`@from_obligations` holds 67 distinct keys — counted with `awk` over the map, not taken from the
comment — split 40 `{:guarded,` / 18 `{:input,` / 5 `{:protected,` / 2 `{:effect,` /
2 `{:unguarded,`; `@from_unclassified` holds 5. (A naive `grep -c '{:effect'` says 3 because the
R4.19.f1 entry's *string* contains `{:effect}`; the tuple count is 2.) 40+18+5+2+2 = 67; 67+5 = 72.
`git show dc9582b3:…/r4_coverage_test.exs` counted the same way gives 63, so the "was 63, now 67"
story is what the tree says.

### Question 1 — the two reclassifications. Both correct.

**R4.19.f1 → `{:effect}`.** Read `reviewer_closed` whole (`kernel.ex:790-847`), not just the
`with`. The `with` guards attempt, execution, reviewer role and sealed stream, then closes the
execution; the `cond` that follows has four arms and only the second (`verdict == "approved"`,
`:818`) reaches a `require_*`. The crash arm is

```
kernel.ex:835   is_nil(verdict) and attempt(ticket, attempt_id)["phase"] == "reviewing" ->
kernel.ex:844   true -> {:ok, ticket}
```

so a no-verdict close on an attempt not in `reviewing` is accepted and takes the `true` arm. That is
the `{:effect}` definition verbatim. One wording nit, not a block: the new entry says the fall-through
"changes nothing", but the execution *was* closed by `close_execution/4` in the `with` before the
`cond` ran. The first review had it right — "closes the execution and silently changes nothing
else". The disposition is unaffected.

**R4a.03.f2 → `{:unguarded}`.** Confirmed by reading and by running.
`pm_launch_planned` is `{:ok, objective}` unchanged (`:248-250`); `pm_launch_settled` is
`consume_infrastructure_ordinal(objective, "pm")` with no `with` at all (`:255-256`);
`consume_infrastructure_ordinal/2` is a bare `update_in` (`:1164-1165`). Upstream, `apply/2`'s
pipeline (`:76-89`) is `check_state`, `Event.validate`, `check_entity_addressing`, `entity_kind`,
`classify`, then `advance` → `resolve_entity`/`check_revision`/`check_sequence` → `do_transition`;
nothing there knows what a planned launch is, because nothing ever writes one. I searched the
kernel for objective-level state that could carry it (`grep -n 'objective\[\|"planned"\|pm_execution'`):
the only objective field any handler consults is `"proposals"` (`:238`). Then the probe, against the
public `Kernel.apply/2` with the same envelope the test file's `event/5` builds, `objective_created`
followed directly by `pm_launch_settled`:

```
mix run -e '...'   # objective_created OBJ1, then pm_launch_settled OBJ1 with no pm_launch_planned
  after objective_created, pm ordinal = 0
  pm_launch_settled WITHOUT pm_launch_planned: ACCEPTED; pm ordinal = 1; well_formed=true invariant=true
```

Accepted, ordinal charged, and both validators pass the result — so this is a defect every
mechanism in EVIDENCE-TOOLS is blind to, exactly as its "Known gaps" bullet predicts. The
`{:unguarded}` entry is right, and "needs its own candidate" is the right disposition for it.

### Question 2 — `R4.07.f2`, `R4a.03.f1` as `:input`; `R4.07.f1` held. All three correct.

- `R4a.03.f1` "PM" is the role, and the role is the event type (`pm_launch_settled` is a separate
  `do_transition` head). Identical to `R4a.01.f1` "Developer" and `R4a.04.f1` "…worker", both
  already `:input`. The answer is right that holding it while classifying its siblings was rule 4's
  partial generalisation inside the inventory.
- `R4.07.f2` "developer exit/timeout/abnormal exit" is the payload of `execution_observed`
  (`payload["lifecycle"]`, guarded for shape by `require_open_lifecycle/1` at `:554`). It names
  what the observation reports, not a state precondition. `:input` per the file's own definition.
- `R4.07.f1` "candidate_frozen": `execution_observed` (`:548-563`) has no phase check of any kind
  — no `require_phase`, no inline conjunct, no branch. Its effect (write one execution's lifecycle)
  is the same in every phase, and the row's outcomes ("cleanup observation only; preserve frozen
  candidate; no new developer and no attempt failure") are what happens in every phase. It is not
  `:guarded`, not `:effect` (no branch), not `:input` (it is a state), and not obviously
  `:unguarded` (nothing the row forbids can happen through this handler). Holding it is the honest
  answer, and the comment now says why in three lines instead of a paragraph about a sixth category.
  Not a wrong hold.

### Question 3 — did answering the block introduce new stale claims? Yes. BLOCK.

The counts are right everywhere (67/40/18/5/2/2/5 in `EVIDENCE-TOOLS.md:31`, `:149-151`, the
briefing, the tickets row, the test comment and the log's "Final" line all match the tree). The
commit references are not.

**3a. `test/pramana_foundry/workflow/r4_coverage_test.exs:588`**, in the file the answer edited,
47 lines above the entry it added:

```
    # R4.19.f1 is held back, not classified - see @from_unclassified.
```

R4.19.f1 is classified at `:635` and is not in `@from_unclassified`. This is "a claim left standing
after the thing it described moved", the answer commit's own words for the defect, left standing by
the answer.

**3b. `docs/fr-08/fr08b-evidence-reduction-tickets.md:308`** now reads "delta `16fc73db..dc9582b3`
… 67 of 72 classified; 5 held". At `dc9582b3` the count was 63 of 72 and 9 held (counted above).
This is finding 1b's shape exactly — the cell that was blocked for pairing `..f0ae495e` with "63"
now pairs `..dc9582b3` with "67". The delta that has 67 in it ends at `36ac89b9`.

**3c. `docs/fr-08/fr08b-ev6-ev2-review-briefing.md:3-6, 22, 57`.** Same pairing: "Delta to review:
`16fc73db..dc9582b3`, eleven commits" and, three lines later, "kept as the record of what was
asked for" — but lines 22 and 57 were changed from 63 to 67, which is not what was asked for. The
file is now neither the historical record (it quotes post-answer numbers) nor current (its delta
and gate predate the answer). Pick one.

**3d. Observation, same file, line 4: "Gate: green at `dc9582b3` — … 949 passed / 13 skipped /
1 excluded".** No record of a gate at `dc9582b3` exists in the tree: `IMPLEMENTATION-LOG.md` has no
gate entry between `b3c110e3` (917 passed, line 2884) and `36ac89b9` (line 3933); no commit body in
`16fc73db~1..HEAD` mentions a gate except `f749c080`; `ci-artifacts/provenance.json` is untracked
and names `36ac89b9`. The 949 figure first appears in the tree for `36ac89b9`. The gate may well
have been run at `dc9582b3` — the first review's task prompt asserted it — but the answer edited
this line to state it as fact, and the repository's rule is that a measurement ships with its claim.
Either cite where it is recorded or say "per the commissioning prompt".

```
sed -n 588p test/pramana_foundry/workflow/r4_coverage_test.exs
git show dc9582b3:foundry/test/pramana_foundry/workflow/r4_coverage_test.exs \
  | awk '/@from_obligations %\{/{f=1} /^  \}$/{if(f){f=0}} f' | grep -c '^    "R4'     # 63
grep -n 'dc9582b3' docs/fr-08/fr08b-evidence-reduction-tickets.md docs/fr-08/fr08b-ev6-ev2-review-briefing.md
awk 'NR>2884' docs/IMPLEMENTATION-LOG.md | grep -n -i 'passed /'      # one hit: 36ac89b9
git ls-files ci-artifacts/provenance.json | wc -l                      # 0
```

Fix: one edit across three files (rule 4) — delete the comment at `:588`; make the tickets row's
delta `16fc73db..36ac89b9` (or `..f749c080`); make the briefing either the frozen record (restore
63/9, keep `..dc9582b3`, keep the "reviewed and blocked" note) or current (delta and gate to
`36ac89b9`), and source the gate claim.

### Question 4 — the floor. Correct and, for `kernel.ex`, tight; not sufficient. Observation.

**Is `ok_or(:unknown_entity_kind)` the only spelling missed?** In `kernel.ex`, yes:

```
grep -n '{:error, [^:]' lib/pramana_foundry/workflow/kernel.ex
  :75   @spec … {:error, atom()}           (a spec)
  :85   {:error, _reason} = error -> error (pass-through, not a site)
  :1875 defp ok_or(:error, reason), do: {:error, reason}
grep -n 'ok_or(' lib/pramana_foundry/workflow/kernel.ex     # :80 only, plus the two defp heads
```

So the true `kernel.ex` count is 72 sites, 25 outside the sweep, and the floor is off by exactly one.

**But the floor's file scope is also a boundary.** `apply/2` calls `Event.validate/1` at `:78`,
and `lib/pramana_foundry/workflow/kernel/event.ex:198,201` refuse with
`{:error, :invalid_semantic_event}`. Those are refusals outside the sweep too, in a file neither
the script nor the doc paragraph mentions. `bin/guard_mutation_sweep.exs:22` defaults its target to
`kernel.ex` as well. "Outside the sweep" is therefore at least 27 across the two files, and the
doc's "24 is a FLOOR" is a floor for one file of two.

**Is recording a floor enough?** It satisfies rule 2 — the denominator and its limit are stated —
which is why this is not a block. It does not satisfy the first review's ask, which was "count
`ok_or(:` or say why not"; the answer did neither, it wrote the miss down. With one occurrence,
adding `|ok_or\(:(\w+)\)` to the regex at `bin/refusal_sites.exs:58` and pinning
`:unknown_entity_kind` in the red control turns the floor into a count for `kernel.ex`, and is
smaller than the paragraph explaining the floor. The `event.ex` gap wants either a second file in
the scan or a sentence saying it is out of scope.

### What must be answered before ACCEPT

1. 3a: delete the stale comment at `r4_coverage_test.exs:588`.
2. 3b, 3c: the tickets row and the briefing must not pair a `..dc9582b3` delta with 67-of-72.
3. 3d: source the "green at `dc9582b3`" gate claim or attribute it.

Optional: 4 — one regex alternation and one red-control pin, and a sentence about `event.ex`.
Nothing in questions 1 and 2 needs answering; the reclassifications stand, and R4a.03.f2 now has a
running witness.
