# Making the guard mutation sweep a gate step

**Status 2026-09-22:** implemented as `bin/coverage_guided_sweep.exs`, not yet a gate step; results
and the one soundness hole found are in the IMPLEMENTATION-LOG entry of that date. The "Not
implemented" in the next paragraph was true when this note was written and is kept as written; this
status line supersedes it.

Design note. Not implemented. Written after the 2026-09-21 full sweep, whose
[verdict table](fr-08/fr08b-subcommit1-sweep-2026-09-21.md) is the answer key any
replacement must reproduce.

## The cost decision this overturns

[EVIDENCE-TOOLS.md](EVIDENCE-TOOLS.md) records the sweep as an audit rather than a gate
step, and says plainly that this "is a cost decision, not a statement that it matters
less". Two paragraphs earlier it records that the sweep "has found more real defects per
run than any other mechanism here". Those two sentences together are the argument: the
highest-yield mechanism is the only one a candidate can skip, and it is skipped by
forgetting.

An hour is the whole reason. The 2026-09-21 run took **5,047 seconds over 116 sites** on
four workers. Remove that and the mechanism moves into `ci/run.exs`, where it runs on every
candidate whether or not the session knows it exists — the property the other four already
have.

## Why the obvious instrumentation is not enough

The tempting design is to compile the kernel once with every guard site recording whether
it was evaluated and whether it ever refused, then run the suite once.

Half of that is exact:

> A site that never returns `{:error, _}` during the suite is a guaranteed survivor.
> Replacing it with `:ok` yields a program that behaves identically on every input the
> suite provides, so no test can notice.

The converse is false, and it is this repository's most expensive recurring bug shape. A
site that *does* refuse is not thereby caught: neutralise it and the `with` chain falls
through to the next guard, which refuses with a different atom, and any test asserting
`{:error, _}` rather than the exact atom stays green. That is rule 5.

It is not hypothetical. Two guards in `require_settlement_source` are recorded as
unwitnessed precisely because they are shadowed this way, and `checks_not_passed` sits in
`r4_guard_reachability_test`'s `@unreachable` because pinning a scenario's `{:error, _}` to
its atom revealed the guard it named was being shadowed by the phase check above it.

So decision-coverage instrumentation finds the *definite* survivors and silently misses the
fired-but-unasserted class — the class that hid for three review rounds. Shipped as a
replacement it would be the sixth mechanism in this subcommit to produce confident, clean,
vacuous results. Recorded here so it is not rebuilt.

## The design that is exactly equivalent

Coverage-guided mutation. The soundness property:

> If a test never evaluates site S, mutating S cannot change that test's outcome.

This holds because reaching S is decided entirely upstream of S, and the mutation changes
only S's own result. A test whose execution never arrives at S diverged before S mattered,
and is bit-identical under the mutant. It requires a deterministic suite, which `--seed 0`
gives.

Therefore:

1. **One instrumented run** produces a map: site -> the set of tests that evaluated it.
2. **Sites no test evaluates are survivors with no trial at all.** Free, and exact.
3. **Every other site gets its existing mutation trial, scoped to its own tests** — a
   handful rather than the whole suite. Same mutation, same verdict, a fraction of the work.

Nothing about the sweep's semantics changes, which is the main reason to prefer this over
replacing the mutation step: the verdicts come from the mechanism that produces them today.

## A second reason, found the hard way

On 2026-09-21 a test was added for the `"blocked"` branch of `require_settlement_source` at
`kernel.ex:1595`. It settled `failed` from `checking`, which exercises the failed/timed_out
branch at `:1585` — already covered. The test passed, the suite count rose, the row carried
`:1595` in its name, and the site it named was still a survivor. A six-clause `case` was
mapped to line numbers by eye.

The full sweep is the only mechanism in the stack that compares a test's claim against the
site it actually exercises. **The site-to-test map proposed above is exactly that check, and
it falls out of step 1 as a by-product.** The same map would also let `@sites` rows carry a
derived site identity instead of a hand-written line number, which is a standing defect
recorded in that table.

## The red control, which already exists

The 2026-09-21 run emits a verdict for all 116 call sites, and it is committed. That table
is an independent, mechanically produced answer key, available at the moment the new tool is
born rather than after it.

**The scoped tool must reproduce all 116 verdicts exactly.** Any disagreement means one of
the two is wrong, and the disagreement names the site to open.

## First task is a spike, not a document

Two unknowns, neither answerable by reasoning:

- Does `:cover` (OTP stdlib, already behind `mix test --cover`; this project has no
  `test_coverage` config, so it is greenfield) give clean per-test attribution under ExUnit,
  or does it need a formatter hook? The sweep already maps byte offset to line via
  `line_of`, so line-granular coverage is the right shape.
- What does the instrumented run cost? `:cover` typically slows execution several fold and
  per-test reset forces `async: false`. Acceptable once; fatal if it is the whole budget.

Only if `:cover` cannot deliver the attribution does this become an AST transform.

## What this does not fix

Hard-linked worker trees, the sentinel, the "never `git add -A` while it runs" rule and the
data-loss hazard class all survive, because trials still write a mutated file to disk. They
go away only in a design where neutralisation is a runtime flag compiled in once. That is a
later step and should not be scoped until the above is measured.

## Sizing

Unknown until the spike, deliberately. The estimate to distrust is the one written before it.
