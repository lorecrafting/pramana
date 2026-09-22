# Evidence tools: what runs automatically, what you must run

These check a **guarded reducer against a written contract**. Nothing in them is specific
to the workflow kernel — the inputs are a reducer, a proposer and a contract document — so
they carry to later tickets and to any future workflow. The kernel is simply the first
thing judged by them.

Read this before adding a guard, a transition, or a test that asserts a refusal.

## Why these exist

FR-08B subcommit 1 was independently reviewed four times and blocked four times. Almost
none of what the reviews found was wrong code. It was **green tests that tested nothing**:
a ratchet resting on a defect, a coverage claim measurement showed false, guards no test
exercised, a scenario named for a contract row that never asserted the row's distinction,
and a guard that could not fire claimed in a commit message as a fix.

Every one was found by a person reading code, at roughly 200,000 tokens a round. Anything
that converts a reading-check into a running-check is therefore worth more than another
reader and costs seconds.

## What runs in the gate, without you doing anything

`elixir ci/run.exs` runs `mix test`, and these are ordinary ExUnit tests. They are enforced
on every candidate whether or not the session knows they exist.

| Mechanism | Where | What it answers |
|---|---|---|
| **Row coverage** | `test/pramana_foundry/workflow/r4_coverage_test.exs` | Can the reducer express every row of the contract's governing tables? Rows are parsed out of `WORKFLOW-CONTRACT.md` at test time, never transcribed. Each scenario cites its clauses verbatim and a test checks the citations still exist, so editing the contract fails here. |
| **Clause coverage** | same file | How many of the contract's clauses does anything assert? A number that can only go down. |
| **From-cell classification** | same file | Does every from-state obligation have a refusal behind it? IDs are annotated into the contract's governing tables and parsed out at test time; each must be `{:guarded, atoms}` with atoms the kernel declares, `{:protected, why}`, or `{:unguarded, why}` — a recorded defect. It proves a guard EXISTS, never that the named one is right, and never that a test exercises it. |
| **Bounded exhaustive search** | `test/support/kernel_search.ex`, asserted in `r4_exhaustive_test.exs` | Every state reachable within a depth, with the exact event path to any violation. `:from` seeds it from a driven state, because depth is spent on the way in. |
| **Semantic invariants** | `State.invariant?/1`, asserted by `Test.Harness` after every accepted transition and by `r4_exhaustive_test.exs` over the reachable set | Are the facts in an accepted state mutually coherent? Distinct from `State.well_formed?/1`, which checks shapes. This is the only mechanism that inspects an effect body's result rather than a guard's decision. It asserts; it does not refuse — `apply/2` never calls it. |
| **Harness routing** | `test/pramana_foundry/workflow/r4_no_direct_apply_test.exs` | Does every test call site actually reach the kernel through the wrapper that asserts? A wrapper nothing is obliged to use decays into one nothing uses, and the claim it supports stays standing while becoming false. It scans for the module's last segment, not one spelling — the first version matched `WorkflowKernel` only and missed a fully-qualified call live in the same commit, which is the declared-reason inventory's one-of-two-spellings defect reproduced in a new mechanism. |
| **Guard reachability** | `test/pramana_foundry/workflow/r4_guard_reachability_test.exs` | Which declared refusals can actually happen. A guard nothing can trip is dead code that reads as a safeguard. |

If you add a guard or a transition and the gate stays green, **that is not evidence the
guard works**. See the sweep below.

## What you must run yourself

### Guard mutation sweep — `bin/guard_mutation_sweep.exs`

Neutralises each guard **call site** in turn and reports the ones whose removal no test
notices. A surviving mutation is a guard nothing exercises. It is the only mechanism at
call-site granularity, and the only one that can see a guard that is tested in one handler
and untested in its identical twin three handlers away.

```sh
cd foundry
TMPDIR=/private/tmp elixir bin/guard_mutation_sweep.exs                 # all sites, ~1 hour
TMPDIR=/private/tmp SWEEP_SITES=/tmp/sites.txt elixir bin/...           # only these guards
TMPDIR=/private/tmp SWEEP_SINCE=<rev> elixir bin/...                    # only guards whose lines changed
```

**Run it when you add or change a guard**, scoped with `SWEEP_SITES` to the guards you
touched — minutes rather than an hour. `SWEEP_SINCE` cannot express "re-check the
survivors", because the fix for an untested guard is a *test*, so the reducer's diff is
empty.

It is **not** in the gate: an hour per run makes it an audit, not a gate step. That is a
cost decision, not a statement that it matters less. Historically it has found more real
defects per run than any other mechanism here — which is why the cost is worth attacking
rather than accepting. [COVERAGE-GUIDED-SWEEP.md](COVERAGE-GUIDED-SWEEP.md) is the design
that would move it into the gate: one instrumented run maps each site to the tests that
evaluate it, and each trial then runs only those tests instead of the whole suite. Same
mutation, same verdicts, a fraction of the work. Read it before optimising this script or
rebuilding it as pure instrumentation, which is unsound for a reason recorded there.

Gotchas, each of which has cost real work:

- It writes a sentinel at `/private/tmp/guard-mutation-sweep.running`, and
  `bin/preflight.sh` **fails while one exists** — a green preflight taken during a sweep
  describes the mutation, not the candidate.
- **Never `git add -A` while it runs.** A neutralised guard was committed that way once,
  and every check passed because the suite was measuring the mutation.
- Wait on the sentinel file, never `pgrep -f` — `pgrep` matches the waiting command's own
  line and the loop deadlocks.
- It does not write to the repository. If it reports the target changed, someone else
  edited it; nothing was overwritten, and no result from that run is trustworthy.

## The rules that make any of this worth anything

These are not style preferences. Each was bought with a review round.

1. **Every mechanism ships with a red control.** A fixture that *must* fail. Five separate
   mechanisms in this subcommit shipped producing confident, clean, entirely vacuous
   results on their first run — a formatter mismatch, a parallelism bug, a sequence-offset
   bug, a predicate matching `nil`, a regex matching 108 of 114 sites. Every one would have
   been caught by a red control. The sweep now runs one at startup and halts if it fails.
2. **Every claim of absence reports its denominator.** "Zero violations" is meaningless
   without "out of N witnesses". `State.measure/1` returns each invariant family's
   `{precondition_held?, violations}` from the code that produces the violations, so the
   denominator cannot drift from the predicate, and the suite prints the per-family table at
   the end of every run. A family whose `held` column is zero is reporting nothing out of
   nothing — and the table is equally how a family stops looking vacuous: `receipt_custody`
   holds 0 of 58,324 over the bounded search and **8,411** over the transitions the suite
   drives — every witness it has comes from hand-driven tests, not from the search.

   The suite's own printed total is **judgements, not transitions**, and the distinction was
   caught by review inside this very paragraph. `Harness` counts 2,351,004 calls, but two
   modules run the depth-7 search from empty (`r4_exhaustive_test`,
   `r4_guard_reachability_test`) and a third walks depth 4 under `identity_key`
   (`r4_congruence_test`), so roughly half of that is the same transition judged again:
   **1,052,864 distinct transitions over 268,856 distinct states**, with raw distinct
   `(state, event)` at 1,086,897 as an upper bound consistent with it. A repeated judgement is
   not a witness. Quote the distinct figure, or say "judgements" and mean it.

   `terminal_custody` was deleted outright once measurement showed it could fire only on
   states `well_formed?/1` already refuses — 0 of 6,716.

   Measuring the bound is what collapsed two standing reachability claims: at depth 8 over
   238,000 states the unseeded search reaches 45 states with an attempt in `reviewing` and
   **zero** with a recorded verdict.
3. **Absence is not proof.** "No counterexample within the bound" is not "impossible", and
   the search's transitions come from a hand-written proposer. Label such a guard
   *unwitnessed*. Then either prove the invariant inductively — true initially, preserved
   by every accepted transition — or delete the guard. Do not record bounded absence as
   unreachability without saying so.
4. **A rule applied to a vocabulary is applied in one edit or not at all.** "Partial
   generalisation" — correcting a handler and not its identical sibling — is the single
   most repeated defect shape here, at six occurrences. Route the shared rule through one
   function; do not rely on remembering.
5. **Pin every refusal assertion to its exact error atom.** `assert {:error, _}` is
   satisfied by any guard in a `with` chain, so it passes while the guard it was named for
   does nothing. This hid most of a class for three reviews.
6. **No guard is described as working until a neutralisation has turned a test red.**

## Known gaps, so they are not rediscovered

- **Every mechanism here can only see a guard that exists.** Nothing detects a contract
  condition with no guard at all, and all six are blind in the same direction: guard
  reachability is keyed by error atom and an unwritten guard has no atom; the sweep
  neutralises guards that are present; row coverage still counts the row as driven because the
  scenario *satisfies* the condition instead of testing its negation; clause coverage counts
  **outcome cells only**, so a from-state conjunct is in neither `@clauses` nor `@uncited`;
  `State.well_formed?/1` is shapes; `State.invariant?/1` has no clause for controls. Measured:
  **32 rows carry 61 from-cell conjuncts and 0 of the 61 appear in the coverage number** — where 61
  is what splitting each from-cell on `;` yields, so it is a floor and not an obligation count; 7 of
  the 61 carry a comma or an explicit `AND`, and row :467 splits to 3 where its own measurement
  tests 5. The witness is row :467's "no pause/drain/cancel", unguarded on `launch_planned` and
  violated **two events from empty** in all three conjuncts, with `paused` and `draining` written
  by `control_changed` and read by no transition at all. It was found by the **first** pure-kernel
  review, reading, and filed as **B3** — which is the cost this gap imposes rather than a
  counterexample to it: every mechanism here was green for the defect's whole life and still is.
  So **a conjunctive precondition needs a refusal test per conjunct, and nothing checks that it
  has one.** [EV-6](fr-08/fr08b-evidence-reduction-tickets.md) now closes the enumeration half of
  this: all **72** from-cell obligations carry an ID in the contract and must each be classified,
  and the ID set is parsed out at test time so a contract edit fails rather than drifts. **3 of the
  72 are classified so far** — row :467's, including its `{:unguarded, ...}` entry, which is what
  makes B3 countable — and the remaining 69 are a recorded ratchet, because classifying one is a
  per-row reading pass against its handler. Until a row is classified, its conjuncts are still the
  check to do by hand. `bin/contract_annotation_diff.exs` is the proof that an annotation pass
  changed no contract text, and its header states the three things it does not prove.
- The sweep's population is every non-definition `require_*(` call. A refusal expressed any
  other way is outside it.
- **`r4_no_direct_apply_test.exs` matches call-site TEXT, so five spellings reach the kernel
  unseen**, each confirmed live in a scratch copy: a capture (`&Kernel.apply/2` then `f.(s, e)`),
  an alias rename (`alias ... as: K` then `K.apply(s, e)`), reflection
  (`apply(Mod, :apply, [s, e])`), and the parenless and space-before-paren call forms. The
  alias-rename case is the same class as the defect the scanner was built after — one of several
  spellings, matched by one. The same blind spots apply to its `apply_unchecked(` pin. A
  compile-time check over the AST would close this; text matching cannot.
- Nothing except the sweep checks that a test exercises the site it *claims* to. On
  2026-09-21 a row named `kernel.ex:1595` and exercised `:1585`; it passed, and the site it
  named stayed a survivor. A site-to-test map would close this, and is the by-product of the
  design above.
- The declared-reason inventory reads the kernel's source with regexes, so a refusal spelled
  a third way is invisible to it. It scanned for one of the two current spellings for three
  reviews. `KernelSearch.reasons_in/1` has a red control over every shape known today; a new
  shape needs a new fixture row.
- Guard reachability is keyed by **error atom**, so it cannot express "this guard cannot
  fire *at this call site*" when the same atom fires elsewhere. Two such sites exist and are
  recorded at the site in `kernel.ex`. Only the sweep can currently see that class.
- The proposer (`test/support/kernel_walk.ex`) and the reducer are two hand-maintained
  encodings of the same contract and can be tuned against each other.
- Translating a contract clause in English into a predicate is a human step and cannot be
  mechanised without replacing the contract with a formal language. Concentrate review
  there.
