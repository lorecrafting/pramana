# Checks and Gates — chapter 2

> Topic reference. Historical measurements retain their original scope; use the current architecture and testing guides for operational guarantees.
> [Contents](../CHECKS.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

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
| CI | compile, format, credo, the tests — **including the two mechanical architecture boundaries and the three docs-routing checks** | every push |
| a machine with the bake | `mix pramana.gate` — plus verify, integrity, evals, lockfile | before a phase tag |

The toolchain versions in the workflow are pinned to `mise.toml` exactly. If they drift,
CI is testing something the developer is not running.

## Run it as one command

```bash
mix pramana.gate            # staged checks; later stages stop after a failing stage
mix pramana.gate --quick    # omits verify/integrity/evals; still needs database state
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
against `evals/baseline.json`. An existing baseline changes only after reviewed
acceptance with `--gate --accept`; passing the gate alone does not advance it. Record
the exact command, candidate and result in the owning status/evidence record, not
duplicated unqualified totals in every entry point.

**▸ A rise did not actually become the new floor until 2026-09-03.** `--gate` writes the
baseline only when none exists, so every improvement since the first run went unadopted —
a run scoring 1,364 of 1,472 passed against a baseline recording 1,359, and a later slide
back to 1,359 would have passed in silence. **A pass now names every case type that moved
and in which direction, and the acceptance step is explicit:**

```bash
PRAMANA_EMBEDDING=1 mix pramana.evals --gate --accept
```

**Review the movements before running it.** The gain is reported beside the loss because
the two travel together — `topical/chinese` +6 and `retrieval/pali` −1 was one run, and a
net +5 describes neither. Adopting a baseline is a decision about what this project now
guarantees, which is why it is not a side effect of passing.

Four things to know before reading the output.

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
- Update `docs/HISTORY.md` (what happened) and `docs/STATUS.md` (what is now true).

Docs drifting from code is the main way a future session gets misled. Treat a doc
correction as part of the work, not overhead.

### 6. Commit and tag
```bash
git add -A
git commit -m "phase N: <summary>"
git tag phase-N
```
