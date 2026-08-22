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

Note `--sample N` on `verify` is **per text**, not a corpus-wide total. Use `--all` at
a gate.

**The checks time themselves.** Every run prints elapsed and a rate, so a gate run is
also a profile and a regression shows up as a number that moved. Rates rather than
totals, because a total ages the moment the corpus grows — this one doubled in a day.

Measured after the #18 optimisation, `--sample 2`:

| | texts | elapsed | rate |
|---|---|---|---|
| sc (Pāli) | 8,442 | 10s | 835.8/s |
| cbeta | 2,471 | 2m25s | 17.0/s |
| derge (Kangyur) | 1,195 | 21s | 55.2/s |
| derge-tengyur | 3,380 | 6m15s | 9.0/s |
| **whole corpus** | **15,489** | **21m09s** | **12.2/s** |

Two things that table teaches. The Tengyur was **~90 minutes on its own** before #18 —
97% of the gate — and the per-source rows still sum to ~9 minutes against a whole-corpus
run of 21, because a full run holds **both** Degé edition maps in memory at once and
checks twice the segments. The optimisation trades memory for time, and at corpus scale
that trade is not free.

**Three checks, in fact.** Neither of the above asks whether the *provenance record*
still resolves:

```elixir
for id <- Pramana.Sources.ids(), do: {id, Pramana.Acquire.Lockfile.verify(id)}
```

`verify` and `integrity` both work from paths recorded at ingest, so both stay green
when the lockfile itself is wrong. The Tengyur landed with all 213 entries recorded as
absolute paths on one laptop: `Lockfile.verify/1` failed on every one of them, and
nothing else noticed, because a bake can be perfectly reproducible from files whose
recorded location no other checkout can find. Check every source, not the one you just
touched — the defect is in how a path was *written*, and it is invisible from the side
that reads it back on the same machine.

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
part of it, so that number is an artifact and not a measurement. A clean wall-clock timing
has not been taken.

The semantic cases are what cost: 75 → 446, each a query embedding plus a filtered HNSW
search over 617,038 vectors — **and a `Semantic.coverage/1` count that measured ~1.1 s per
search**, which is database time and does not appear in the CPU figure at all. Plan for a
long-running background job, use `--only retrieval` when iterating, and run the whole set
at a gate.

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

- `mix dialyzer` across the whole umbrella with no ignore file growth
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
