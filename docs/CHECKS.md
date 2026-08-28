# Checks and Gates

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

## Every phase gate (the ⛔ CHECKPOINT tasks)

A checkpoint is a real stop. Do not start the next phase until all of it passes.

### 1. Code
```bash
mix format --check-formatted
mix compile --warnings-as-errors
mix test --cover            # coverage must not regress
mix credo --strict
mix dialyzer                # types; slow, so phase-gate only
mix deps.audit              # known CVEs in deps
mix hex.outdated            # note drift; upgrade deliberately
```

### 2. Architecture review
Re-read `CLAUDE.md`'s invariants and confirm the phase's code honors all seven.
Specifically audit:
- Does anything **in** `apps/pramana_web` read the DB directly — `Repo.`, `import
  Ecto.Query`, a handwritten query? (It must not: the web app is transport, the domain
  app owns the data.) This one has drifted once already, via an MCP resource that built
  its own aggregation.
- Did any domain logic leak into `priv/embed`? (It must not.)
- Can any tool return text without `urn` + offsets + `sha256`? (It must not.)
- Is any generated translation reachable as a top-level URN? (It must not.)
- Is the bake still reproducible from `sources.lock.json` alone?

Write findings into `docs/STATUS.md` under the phase heading. If an invariant was
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

## What CI can prove, and what it cannot

`.github/workflows/ci.yml` runs the mechanical half on every push: `mix compile
--warnings-as-errors`, `mix format --check-formatted`, `mix credo --strict`, and the full
test suite, against Postgres 18 with pgvector and pg_bigm. About four minutes.

**It cannot run `verify`, `integrity` or `evals`, and it never will.** Those check the
baked corpus, and the corpus is not in the repository: `raw/` is gitignored, CBETA is
non-commercial, and the licensing posture is that we publish the pipeline and each user
bakes their own copy. A CI job that appeared to gate the corpus would need one, and
putting a corpus in a public runner would break the licence this project is careful about.

So the split is honest rather than incidental:

| where | what | when |
|---|---|---|
| CI | compile, format, credo, 1,158 tests | every push |
| a machine with the bake | `mix pramana.gate` — plus verify, integrity, evals, lockfile | before a phase tag |

The toolchain versions in the workflow are pinned to `mise.toml` exactly. If they drift,
CI is testing something the developer is not running.

## Run it as one command

```bash
mix pramana.gate            # everything, cheapest first, stops at the first failure
mix pramana.gate --quick    # format, credo, tests, lockfile — about 15 s
mix pramana.gate --from integrity     # resume after fixing one step
```

Everything below is what that runs, and why. It exists because runnable-in-principle is
not the same as run: the CBETA X ingest shipped with `verify` green and `integrity` never
executed, and integrity had been failing on 1,228 texts the whole time. Nobody skipped it
on purpose — it was one more command at the end of a long day.

It does **not** replace §2, the architecture review, and says so when it passes.

**Three checks, in fact.** Neither of the above asks whether the *provenance record*
still resolves. This used to live here as a snippet to paste into IEx, which meant it ran
when someone remembered to paste it; it is now step 4 of the gate:

```elixir
for id <- Pramana.Sources.ids(), do: {id, Pramana.Acquire.Lockfile.verify(id)}
```

**Its first automated run found two sources broken and one merely unacquired**, all three
invisible for phases:

| source | what was wrong |
|---|---|
| `sc-translations` | 4,996 files recorded at `raw/sc-translations/` while the bytes sat in `raw/sc/bilara-data/` — one sparse checkout, three publications, three licences. The hashes were right; the base was inferred from the id. Entries now DECLARE a `raw_root`. |
| `sc-data` | 2 files recorded and **never written to disk at all** — the import fetched them into memory, hashed them, and dropped the bytes. That is invariant 3 inverted: `raw/` is the record a bake is reproduced from. Now persisted; the re-fetched hashes matched what had been recorded, so the claim was true and only the storage was missing. |
| `sat` | declared in the registry, never acquired, because #14 is blocked on an email. **Not a failure** — a permanently red check is one nobody reads. |

`verify` and `integrity` both work from paths recorded at ingest, so both stay green
when the lockfile itself is wrong — and "wrong" includes *incomplete*. Acquiring CBETA's
X collection replaced the `cbeta` entry rather than merging into it, dropping the
Taishō's 2,471 file records: a corpus of 3,701 CBETA texts with a lockfile that could
reproduce 1,230, and `Lockfile.verify/1` green over every file it still listed, because
it verifies what is recorded and cannot miss what is not. Check the **counts** as well as
the hashes; `mix pramana.integrity`'s census does this for the bake. The Tengyur landed with all 213 entries recorded as
absolute paths on one laptop: `Lockfile.verify/1` failed on every one of them, and
nothing else noticed, because a bake can be perfectly reproducible from files whose
recorded location no other checkout can find. Check every source, not the one you just
touched — the defect is in how a path was *written*, and it is invisible from the side
that reads it back on the same machine.

### 4a. Comparing two runs

```bash
mix pramana.evals.compare evals/baseline.json evals/scorecard-new.json
mix pramana.evals.compare a.json b.json --rebuilt    # an index rebuild sits between them
```

**A delta smaller than the noise floor is not a result**, and the floor is a count and a
proportion at once. Two runs of the identical configuration against the identical index
differ by about **one case**, concentrated in `retrieval/pali` — but one case is 0.67
percentage points on a 150-case row and **25 points on a four-case one**, so the same
absolute difference is noise on one row and a finding on another. The task applies both
tests; the first version applied only the count and reported `absence 1/4 -> 3/4` as
within noise, which is a tool arguing a reader out of a real result.

**`--rebuilt` is needed more often than it looks.** An HNSW rebuild is not deterministic —
the graph is built with randomisation, so reindexing the same vectors yields slightly
different approximate neighbourhoods, and adding vectors perturbs queries that have nothing
to do with them. `retrieval/tibetan` is where this surfaces, because BGE-M3 packs Tibetan
at 0.9727 mean pairwise cosine against 0.84 for Pāli: its candidates are near-ties by
construction and reorder under any graph change. Every import, re-embed and chunk-size
experiment involves a rebuild.

### 4. Evals (from Phase 4 on)
```bash
PRAMANA_EMBEDDING=1 mix pramana.evals --gate
```
Scores the committed gold set in `evals/gold/` and fails if any case type regressed
against `evals/baseline.json`. A ratchet, like the coverage threshold: a number that
rises becomes the new floor; one that falls fails the gate. Record the numbers in
`docs/STATUS.md` and the README.

Three things to know before reading the output.

**Run it with the embedding serving.** Without `PRAMANA_EMBEDDING=1` the harness scores
the lexical path alone and says so. That is a real number for a smaller system and is
not the one the README publishes. The harness found this the hard way: `Hybrid` silently
skipped semantic retrieval for any caller that omitted `:serving`, and the first run
scored 0/40 on cross-lingual retrieval that works.

**Stale is not failure.** A case whose expected URN no longer resolves, or whose quoted
text has changed, is reported as `stale` and excluded from the rate. After a re-bake that
is the honest signal — *the gold set is out of date* — and counting it as a miss would
bury it in a number that went down.

**Regenerate the gold set after a re-bake** with `mix pramana.evals.derive`, and re-read
the cases before committing. The derivation is seeded, so it is reproducible.

**For a retrieval change, this is not confirmation — it IS the decision.** A Tibetan LoRA
adapter scored 3.4× on in-batch top-1, 2× on held-out MRR, and **19× on a
related-vs-unrelated discrimination gap**, and then retrieved **0 of 20** Tibetan cases
against the real index, down from 7. Three separate proxies endorsed a model that
destroyed retrieval. They measured pair-matching among two dozen candidates and local
geometry between neighbouring chunks; retrieval ranks against 617,038 competitors. Treat
any proxy gain as a hypothesis until the gold set agrees, and never adopt on proxies alone.

**Check the arithmetic before believing a null result.** The set must be large enough to
show the effect you are looking for. Two questions in one session were undecidable for
this reason: a fix touching 6.3% of Pāli chunks implied ~1.26 affected cases out of 20,
and `retrieval/tibetan` swung 7→8 and 7→5 across index rebuilds **with nothing relevant
changed**, because HNSW is approximate and Tibetan's vectors are the corpus's
worst-separated (0.9727 mean pairwise cosine), so its candidates are near-ties. On 20
cases a ±2 swing is ±10% and buries anything subtle. The set was widened to 1,400 cases
for this reason — `retrieval/pali` 20→150, `retrieval/tibetan` 20→64.

**`topical/*` did not widen and cannot, at present.** Those cases come from a curated
doctrinal-term list, and terms are rejected when they are *too common to measure* —
སྟོང་པ་ཉིད occurs in 20,500 segments, so "was it found" carries no information.
`topical/tibetan` stays at 9 cases and `topical/chinese` at 12. They are the hardest and
most valuable questions in the set, and they remain statistically undecidable.

**Budget the runtime, and measure it on a machine that stays awake.** The 1,400-case set
used **62 minutes of CPU**, against ~5 minutes wall for the old 249. Treat the CPU figure
as the reliable one: the wall clock on that run read 8h20m, but the laptop was asleep for
part of it, so that number is an artifact and not a measurement.

**Clean wall-clock timings, finally taken** (2026-08-22, all with the embedding serving):

| run | cases | wall | rate |
|---|---|---|---|
| full set, `--per-tradition` | 1,400 | **3h09m** | 0.1 cases/s |
| `--only topical`, `--per-tradition` | 49 | 29m11s | ~36 s/case |
| `--only topical`, default | 49 | 5m22s | ~6.6 s/case |

**`--per-tradition` costs about 5.5x** and is DB-bound, not CPU-bound — ~35% CPU
throughout, because it runs three `source_id`-filtered iterative scans per query instead
of one unfiltered one. Budget hours, not minutes, before scoring a configuration with it.

**`--depth` above the default can exceed the database connection timeout and kill the
run.** Measured on 64 Tibetan retrieval cases, ABBA order to cancel cache drift:

| depth | recall | scoring time |
|---|---|---|
| 60 (default) | 20/64 | 7m24s and 7m32s |
| 120 | 25/64 | 11m01s, and **one arm in two crashed** |
| 200 | 24/64 | 4h25m over the full 446-case set |

The crash is a `DBConnection.ConnectionError` at `Lexical.run/4` — a single **bigram**
query holding the connection past 120,000 ms. The cost of depth is in pg_bigm, not in
HNSW, which is the opposite of what everyone assumed and means the vector side is the
wrong place to tune it.

**Time an eval configuration with arms run back to back in one session.** Two depth-60
arms an hour apart differ by 40% (5m16s vs 7m24s); two run consecutively differ by 1.8%.
A single timing taken today and compared against one taken this morning is measuring the
page cache.

The semantic cases are what cost: 75 → 446, each a query embedding plus a filtered HNSW
search over 617,038 vectors. Plan for a long-running background job, use
`--only retrieval` when iterating, and run the whole set at a gate.

**`Semantic.coverage/1` is no longer part of that bill.** It counted 560,238 chunks on
every search for a number the harness never reads; the harness now passes
`coverage: false` and the API surface still computes it. Measured end to end on
`--only topical`, identical scores both ways: **6m43s → 5m22s, ~1.65 s per case**, so
roughly **14 minutes** off a full run.

Its cost is not one number, which is worth knowing before quoting it: **~520 ms warm**
over twelve consecutive calls, **~2,700 ms cold** immediately after a long eval had
evicted the chunk pages. The ~1.1 s figure previously recorded here sat between the two
and matched neither. An estimate of ~8 minutes was written into a commit message before
this was measured; the observed saving is nearly twice that, and the estimate was wrong.

**Percentages are not comparable across a widening.** Every denominator changed, so the
pre-widening 79.5% and any figure after it measure different sets. Re-baseline in the same
commit that changes the gold set, and say so.

**Readings are scored separately**, because the claim is comparative rather than
absolute:

```bash
mix pramana.readings.check          # --verbose for the per-form table
```

It runs the Buddhist test set through both the reading dictionary and the per-character
baseline, and raises if any form is read wrongly. Scoring the baseline *in the same run*
is deliberate: "a generic library fails on this vocabulary" is a measurement, and if that
number ever rises the claim needs revisiting rather than defending. Half the set is
controls the baseline already gets right — a dictionary that fixes hard cases by breaking
easy ones is not an improvement, and `broken` counts exactly that.

### 5. Docs sync
- Does `docs/ROADMAP.md` still describe what we actually built? Amend if not.
- Do `ARCHITECTURE.md` / `LAYERS.md` / `TRANSLATION.md` match the implemented schema?
- Is `CLAUDE.md`'s layout section accurate?
- Update `docs/STATUS.md`: what's done, what's next, decisions taken, surprises found.

Docs drifting from code is the main way a future session gets misled. Treat a doc
correction as part of the work, not overhead.

### 6. Commit and tag
```bash
git add -A
git commit -m "phase N: <summary>"
git tag phase-N
```

## Periodic (every ~3 phases)

- `mix dialyzer` across the whole umbrella with no ignore file growth. **Run it more
  often than this schedule says.** It was recorded as "0 errors, and no ignore file
  exists — none has ever been needed" at the phase-4 gate and was found at **9** on
  2026-08-22, all predating that session. Seven were one cause — three mix tasks built a
  source map inline instead of reading `Pramana.Sources`, and the copies had already
  drifted, so the lockfile and the database stated different licence terms for `sc`. The
  other two were specs that lied: a `toh: String.t()` that is nil for 84000's placeholder
  records, which made dialyzer call a live guard dead code. It runs in **22 seconds** once
  the PLT is built, which is cheap enough that "phase-gate only" is the wrong cadence for
  it.
- Dependency upgrade pass — deliberate, one PR-sized change
- Re-read `docs/COMPETITIVE.md`: has fojin shipped something that changes our
  positioning? Is our differentiation still real?
- Bake cost review: what does a full bake cost in time and tokens now?

## Security review

Run `/security-review` before any deployment task and at the Phase 7 gate. Specific
concerns for this project:
- Prompt injection via corpus text — canonical texts are trusted, but **locally-added
  sources and any OCR output are not**. Text from a manifest-added source must never
  be treated as instructions.
- The Python sidecar must not be reachable from outside the compose network.
- License gating must actually exclude `restricted` content from any public surface.

## What "stable" means here

The invariants in `CLAUDE.md` are the definition. Tests prove behavior; the checkpoint
architecture review proves the *shape* is still right. Both are required — a codebase
can be fully green and still have quietly stopped being the thing it was designed to
be.
