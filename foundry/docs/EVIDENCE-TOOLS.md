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
| **Bounded exhaustive search** | `test/support/kernel_search.ex`, asserted in `r4_exhaustive_test.exs` | Every state reachable within a depth, with the exact event path to any violation. `:from` seeds it from a driven state, because depth is spent on the way in. |
| **Semantic invariants** | `test/support/semantic_invariants.ex`, asserted in `r4_exhaustive_test.exs` | Are the facts in an accepted state mutually coherent? Distinct from `State.valid?/1`, which checks shapes. This is the only mechanism that inspects an effect body's result rather than a guard's decision. |
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
   without "out of N witnesses". Measuring the bound is what collapsed two standing
   reachability claims: at depth 8 over 238,000 states the unseeded search reaches 45
   states with an attempt in `reviewing` and **zero** with a recorded verdict.
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

- The sweep's population is every non-definition `require_*(` call. A refusal expressed any
  other way is outside it.
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
