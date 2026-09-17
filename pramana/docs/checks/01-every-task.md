# Checks and Gates — chapter 1

> Topic reference. Historical measurements retain their original scope; use the current architecture and testing guides for operational guarantees.
> [Contents](../CHECKS.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

# Checks and Gates

> For the current command matrix and exact evidence limits, start with [TESTING.md](../../../docs/TESTING.md).
> The detailed rationale below includes historical incidents; old counts/timings are not current acceptance evidence.

The discipline that keeps this stable across many sessions. Tasks reference this file
rather than restating it.

## Every task

Before marking a task complete:

```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test
mix credo --strict
```

All four must pass. A task with failing tests is `in_progress`, not `completed`.

**If the task changed the corpus, also run `mix pramana.docs.figures`** — or just
`mix pramana.gate --quick`, which includes it. Corpus counts in documentation live in
`<!-- figures:key -->` blocks and are generated; the check fails when regenerating would
change one, and `--write` fixes it. Nothing is lost by regenerating: the numbers in a stale
block were describing a corpus that no longer exists.

It refuses on an empty database rather than rewriting the documentation to zeroes, so it is
safe to run in a checkout with no bake — it simply says it did not check.

## Every phase gate (the ⛔ CHECKPOINT tasks)

A checkpoint is a real stop. Do not start the next phase until all of it passes.

### 1. Code
```bash
mix pramana.gate --quick    # format, compile, credo, hex.audit, deps.audit, test --cover, dialyzer, lockfile, coherence
mix pramana.doctor          # not a check — the state a session opens with
mix hex.outdated            # note drift; upgrade deliberately — not in the gate
```

**Six of these are `mix pramana.gate --quick`, and for two phases they were not.** This
block listed seven commands; the gate ran three of them, so *"the gate passed"* and *"the
phase-gate code checks passed"* were different statements that read identically.
`compile --warnings-as-errors`, `dialyzer` and `deps.audit` are now steps.

`mix hex.audit` is a separate gate from `mix deps.audit`: Hex audits the locked Hex packages against current Hex security advisories and retirements, while `deps.audit` keeps the existing mix_audit check. A green `deps.audit` result does not substitute for `hex.audit`.

One stays out, deliberately: `hex.outdated` is asked for here to **note** drift, and a
dependency being upgradable is not a failure — a gate step that cannot fail is noise.

**`--cover` came in on 2026-08-28, and this block was wrong about why it was out.** It said
`--cover` "needs a stored baseline to compare against, which does not exist yet". The
baseline had existed the whole time: `test_coverage: [summary: [threshold: n]]` in each
app's `mix.exs`, raised at four separate gates. Mix fails the run itself when coverage falls
below it — nothing needed building.

The cost of that mistake was measurable. With the gate running plain `mix test`, pramana_web
fell from 93% to **77.5%** and no check said a word, while `mix.exs` went on recording 93.
See `docs/PLAN.md` § Backlog for the reset and the restoration targets.

**Not a gate step, and deliberately:** `mix pramana.evals.sweep` runs the gold set across a
grid of retrieval configurations. It answers *which settings are best*, which is a question
for a person choosing a default — the gate's job is that the chosen default has not
regressed. A search over configurations that ran on every commit would also be the fastest
way to overfit `evals/baseline.json`.

### 2. Architecture review

**Two of the five audits below now run on every push.** `Architecture.BoundariesTest`
checks the two that were already being performed as greps — nothing in `apps/pramana_web`
reads the database, and `priv/embed` imports nothing outside the tensor stack and speaks
no domain vocabulary. The 2026-08-28 review recorded both as grep counts, and a check
somebody runs by hand at a phase gate is a check that runs once a phase, on the honour
system, long after the commit that broke it.

**It does not replace this section and must not be read as doing so.** It carries an
`unmechanised/0` list naming the three audits it cannot perform, and a test asserts that
list is present, so a green suite cannot quietly come to mean a completed review.

**Each rule has an allowlist with a reason, on purpose.** These boundaries will move —
another tensor library, some future reason the web app needs something. Widening a rule is
one reviewed line in a diff; the escape hatch is what makes the distinction between
*evolution* and *drift* real. A rule with no escape hatch is a rule somebody deletes the
first time it is inconvenient, which is strictly worse than a visible list of exceptions.

Re-read `CLAUDE.md`'s invariants and confirm the phase's code honors **all eight** — this line said "all seven" while `CLAUDE.md` listed eight, which is a review that cannot notice the one it does not count.
Specifically audit:
- ~~Does anything **in** `apps/pramana_web` read the DB directly~~ — **now mechanical**,
  `Architecture.BoundariesTest`. (It must not: the web app is transport, the domain app
  owns the data.) This one has drifted once already, via an MCP resource that built its
  own aggregation.
- ~~Did any domain logic leak into `priv/embed`?~~ — **now mechanical**, same file, by
  vocabulary and by import list.
- ~~Can any tool return text without `urn` + offsets + `sha256`?~~ — **partly mechanical
  since 2026-09-03**, `Architecture.BoundariesTest`. Performing it by hand for the first
  time found two live violations: `get_readings` returned the passage text with a URN and
  no sha256, offsets or provenance — while its own note said *"the text, not its
  pronunciation, is what is citable"* — and `get_glosses` returned a lemma, a verbatim
  quotation of the root, with no anchor of its own. **Both had been shipping.** The test
  now fails on a tool that emits quotable text with no sha256 in the module, which is the
  failure that actually happened. **It cannot prove correspondence** — that the sha256 is
  *of* the text beside it, or that a new response shape carries offsets at all — so
  reading a payload is still a person's job. Presence is mechanical; belonging is not.
- Is any generated translation reachable as a top-level URN? (It must not.) — **audited by
  hand 2026-09-03.** The structure holds: a rendering is a URN *fragment*, so it cannot be
  addressed without naming the source anchor it renders, and `search_translations` returns
  `anchor_urn` and `rendering_urn` separately with `citable_as_source: false`, `method`,
  `tier`, model id and prompt hash. **But `get_passage` crashed on every rendering URN** —
  `KeyError: key :sha256`, because a rendering span has no offsets into a witness and named
  its hash `content_sha256` where `Pramana.Corpus` names it `sha256`. A tool that raises is
  not leaking, so the invariant held; a tool that raises is also not answering. It now
  answers and leads with `layer: "translation"` and `citable_as_source: false`, and invents
  no offsets, because a fabricated range is the false precision the guard exists to prevent.
- Is the bake still reproducible from `sources.lock.json` alone? — **audited by hand
  2026-09-03, and it holds.** `Lockfile.verify/1` proves the *forward* direction, that every
  locked file is on disk with its recorded hash. The audit asks the *reverse*: does every
  file the corpus actually used appear in the lockfile? That is the direction the 2026-08-26
  incident broke, when acquiring X replaced the Taishō's lockfile entry and left 3,701 baked
  texts reproducible from 1,230. Checked over every text recording a `source_file` — **13,807
  paths across four sources, 0 not in the lockfile.**

  **It did find that CBETA recorded ABSOLUTE paths** — 648 of 648, including
  `/Users/…/pramana/` — so the provenance resolved on one machine and nowhere else.
  `mix pramana.derge.ingest` already had a `relative/1` helper for exactly this and the
  lesson had not reached `mix pramana.bake` (rule 41). Now relative; `mix pramana.integrity`
  reads both shapes via `Path.expand/1`, so no re-bake is required to read rows written
  before the change.

  **Two false alarms on the way, both worth knowing.** Comparing the stored path to the
  lockfile path raw reports every file missing, because the lockfile stores paths relative
  to the source's raw root and a text stores them from the repository. And a work spanning
  volumes records several paths in one space-separated field, so a single-path lookup
  reports 75 of 1,195 Degé texts unreproducible. Both read exactly like a catastrophe.
  Rule 62.

Write findings into `docs/HISTORY.md` under the phase heading. If an invariant was
violated, fix it before the gate passes — invariant drift is what makes long projects
collapse, and it is much cheaper to fix inside the phase that introduced it.

### 3. Data integrity (from Phase 1 on)

**Two checks, and they answer different questions.** Running only the first is how a
real defect survived a passing gate.

```bash
mix pramana.verify --all        # reproducibility: is the pipeline deterministic?
mix pramana.integrity           # fidelity: did the pipeline LOSE anything?
```

`verify` re-normalizes every text from `raw/` and byte-compares against the stored
body. That catches silent corruption — the highest-consequence bug class here.

`integrity` counts the bake against the **raw XML**: every `<lb/>` produced a line,
every line with printed content got a segment, every `<g/>` is reachable. This is the
check `verify` structurally cannot do, because **a pipeline that drops the same content
every run drops it identically on both sides of a re-normalization comparison**, and
the check passes. That is not hypothetical — 10,590 printed lines, 473 rare characters
and 266,547 characters of interlinear note text were unreachable in a corpus that
verified clean. **Reproducibility is not fidelity.**

Check 1 **reconciles** rather than compares: an X file carries its own `ed="X"` lineation
beside the earlier 卍續藏經 reprint's `ed="R055"`, and only one of them is the text's, so
every `<lb/>` in the body must be either a line or a counted skip (`IR.foreign_lb`).
Comparing raw `<lb/>` against lines alone reported 1,228 correct X texts as `lb_lost —
raw 46, bake 25`. **A check deriving a number from raw markup has to derive it by the
same rule the pipeline uses**, and a check that cries wolf is worse than one that is
missing: that failure sat unseen because the X ingest ran `verify` and never this.

Its fourth check answers a question the other three cannot: **did every acquired file
reach the corpus at all?** Counted from the lockfile before any parsing — files → works
→ texts loaded — because checks 1–3 each begin at a text row, and from inside a row a
work that lost half of itself looks perfect. Six CBETA X works were in exactly that
state, each having been overwritten by its own second volume, and `mix pramana.verify`
passed over all 3,701 CBETA texts: each survivor re-derived byte-identically from the
one file it recorded. What found it was `1,236 files` against `1,230 works`.

Note `--sample N` on `verify` is **per text**, not a corpus-wide total. Use `--all` at
a gate.

**The checks time themselves.** Every run prints elapsed and a rate, so a gate run is
also a profile and a regression shows up as a number that moved. Rates rather than
totals, because a total ages the moment the corpus grows — this one doubled in a day.

Measured after the #18 optimisation, `--sample 2`, on the 15,489-text corpus:

| | texts | elapsed | rate |
|---|---|---|---|
| sc (Pāli) | 8,442 | 10s | 835.8/s |
| cbeta | 2,471 | 2m25s | 17.0/s |
| derge (Kangyur) | 1,195 | 21s | 55.2/s |
| derge-tengyur | 3,380 | 6m15s | 9.0/s |
| **whole corpus** | **15,489** | **21m09s** | **12.2/s** |

Re-measured 2026-08-27, after CBETA X (16,719 texts, 10.7M segments):

| | texts | elapsed | rate |
|---|---|---|---|
| `verify --source cbeta` (default sample) | 3,701 | 4m41s | 13.1/s |
| `integrity`, whole corpus | **16,719** | **13m18s** | **20.9/s** |

And after J, at `--all` — every segment, which is what a gate runs:

| | texts | segments | elapsed | rate |
|---|---|---|---|---|
| `verify --all`, whole corpus | **17,004** | **11,519,879** | **26m05s** | 10.9/s |

**`--all` is the expensive half of the gate and it is the half worth paying for.** The
sampled run checks 1,000 segments per text; this checks all 11.5M, and it is the only
form that can prove the sentence it claims — *body re-normalized from `raw/` and
byte-identical for every text*. Budget half an hour, and run `mix pramana.gate` in the
background rather than waiting on it.

The whole-corpus `integrity` run got *faster in rate* while the corpus grew by 1,230
texts, which looks wrong until you notice what those texts are: X works are small, and the
rate is per TEXT. This is why the table records rates and the paragraph above says a total
ages the moment the corpus grows — but a rate ages too, quietly, whenever the mix of what
is being counted changes.

Two things that table teaches. The Tengyur was **~90 minutes on its own** before #18 —
97% of the gate — and the per-source rows still sum to ~9 minutes against a whole-corpus
run of 21, because a full run holds **both** Degé edition maps in memory at once and
checks twice the segments. The optimisation trades memory for time, and at corpus scale
that trade is not free.
