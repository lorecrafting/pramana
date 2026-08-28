# Pramāṇa

A citation-grounded retrieval substrate for the Buddhist canon, where **every quotation
can be mechanically proven to exist, in that form, at that place in a real printed
edition** — and where a Japanese-composed commentary can never be handed back as if it
were an Indian sūtra.

*Pramāṇa* (प्रमाण) is Sanskrit for "valid means of knowledge": the branch of Indian
philosophy concerned with how one knows a claim is true. That is the design brief.

New to the project? **[`docs/PRIMER.md`](docs/PRIMER.md)** explains it from the ground up —
no prior knowledge of Elixir, search systems, or Buddhist studies assumed.

---

## The corpus

| | |
|---|---|
| Texts | **17,099** |
| Segments (citable units) | **12,358,849** |
| Chinese works (CBETA) | 4,081 across **11 collections** — Taishō 2,471 · 卍續藏 1,230 · 嘉興藏 285 · 漢譯南傳大藏經 38 · seven alternative editions 57 |
| Pāli works (SuttaCentral) | 8,442 |
| Tibetan works (Degé Kangyur / Tengyur) | 1,195 / 3,380 |
| Retrieval chunks | 963,480 |
| Embedding vectors | **1,020,280** |
| English renderings | 241,409 by 7 translators, **searchable by their own words** |
| Commentary aligned to the line it explains | **27,254 lemmas** over 43 work pairs, 20,954 root lines |
| Curated cross-tradition parallels | 407,176 recorded, **24,717 (6.1%) openable** — the rest name witnesses this bake does not hold |
| Verbatim quotations between works | 141,073 across 1,301 works |
| Buddhist reading exceptions | 9,543 over a 44,348-character base |

Both integrity checks are green over every text: `mix pramana.verify --all` proves the
bake is a **reproducible** function of pinned inputs, and `mix pramana.integrity` proves
it is a **complete** one. Those are different questions — a pipeline that drops the same
content on every run passes the first and fails the second. `mix pramana.gate` runs both,
plus formatting, Credo, the test suite, a lockfile census and the eval ratchet, cheapest
first, and stops at the first failure.

**CBETA is 26 collections and this holds 11.** `Pramana.Coverage` says which are absent, by
name, in every survey response, because an empty result otherwise reads as the canon being
silent rather than as the shelf being short. It says the same about **Taishō volumes 56–84**
(547 works, not in CBETA at all), about the **6.1% of the parallel graph** whose other end
is a witness we do not hold, and about the **1,640 texts a `role:` filter cannot reach**
because only the Taishō has a 部 division table.

Each of those was a number nobody had published until something made it visible. That is
the pattern this project is built around: a gap that is stated is a gap a reader can work
with, and a gap that is silent reads as an answer.

---

## Measured retrieval quality

Nobody in this field publishes retrieval numbers. The nearest comparable project asserts
"~98% of served answers are trustworthy" with no reproducible benchmark. So here is ours,
produced by `mix pramana.evals` over the gold set committed in [`evals/`](evals/).

**1,400 cases · 0 stale · 0 errored · overall 93.1%**

| what it measures | cases | |
|---|---|---|
| **Quote verification** — the guard confirms a quotation that is really there | 300 | **100%** |
| **Quote rejection** — the guard refuses altered text and fabricated URNs | 301 | **100%** |
| **Provenance labelling** — origin and role match the Taishō's own catalogue | 300 | **100%** |
| **Absence** — the system returns nothing where it holds nothing | 4 | 75% |
| **Adversarial subset** | 305 | **99.7%** |
| **Retrieval @10** — two different tasks, see below | 446 | 83.9% |
| ↳ *Same-language*: a Chinese definitional formula → its passage | 232 | **96.1%** |
| ↳ *Cross-lingual*: an English rendering → the Pāli it renders | 150 | 80.0% |
| ↳ *Cross-lingual*: an English rendering → the Tibetan it renders | 64 | 48.4% |
| **Topical @10** — a natural question returns a passage that discusses it | 49 | 51.0% |
| ↳ Chinese question → Chinese passage | 12 | **91.7%** |
| ↳ English question → Pāli passage | 16 | 75.0% |
| ↳ English question → Chinese passage | 12 | **0%** |
| ↳ English question → Tibetan passage | 9 | 22.2% |
| **Answered from any tradition** — the reader got a good answer from *some* canon | 11 topics | **81.8%** |

Two further gold sets measure the newest layers:

| | cases | |
|---|---|---|
| **Rendering** — an English phrase → the source line it renders | 40 | 70.0%, mean rank 1.68 |
| **Gloss** — a root line → the commentaries that quote it | 32 | 100%, and see below |

**The gloss row is a regression detector, not a quality measurement**, and it says so on
every case. No mechanical ground truth exists for which commentary explains which line —
that is a scholar's judgement the corpus does not record — so the cases are derived from the
alignment's own output. 100% means *it still says what it said*. What speaks to correctness
is the null set: **0 of 120 unrelated work pairs** cleared the alignment's density floor.

The rendering set was nearly built the same way and was rebuilt before it shipped. Selecting
phrases that the retriever already found would have reported 100% forever — able to catch a
regression, never able to show a weakness. Its cases now come from a property of the *text*,
and 12 of 40 miss.

**These numbers are `evals/baseline.json`.** If this table and that file disagree, the file
is right; every figure here was copied from it rather than remembered.

**The 83.9% retrieval aggregate mixes two tasks and should not be read as one number.**
Every Chinese retrieval case is a *definitional formula* — `云何為十一者常為十`, a phrase
that appears verbatim in the corpus, which the bigram index finds by substring. Every Pāli
and Tibetan case is *cross-lingual*: a translator's English, matched back to the source
passage it renders. Those are different difficulties, and 96.1% against 48.4% is not
evidence that Chinese retrieval is twice as good — it is evidence that exact-phrase lookup
is an easier problem than cross-lingual matching.

There are **no cross-lingual Chinese cases at all**, and that is not an oversight: all
55,135 English rendering vectors sit on Tibetan and Pāli chunks, because CBETA material has
no English translation layer in this corpus. The same gap is why `topical/chinese` is 0%.

**These are not comparable with the previously published 79.5% over 249 cases**, and the
difference is not an improvement. The gold set was widened 5.6× because 20 cases per
language could not decide anything: a fix touching 6.3% of Pāli chunks implied ~1.26
affected cases, and `retrieval/tibetan` swung by ±2 across index rebuilds with nothing
relevant changed. The overall rate rose only because the *mix* changed — near-perfect
categories went from 49% of cases to 64%. Compare per-row, never overall, and always with
the case count.

What widening actually revealed: the old per-language figures were noisy estimates.
retrieval/Pāli was 53.3% (n=150), not 55.0% (n=20); retrieval/Tibetan 31.3% (n=64), not
35.0% (n=20). Both old numbers sat inside their own sampling error. Those two rows have
since moved to 80.0% and 48.4% on real work, which the wider set could measure and the
narrow one could not. And it exposed a defect in the gold set
itself: one "altered quote" case had been altered into *itself*, so the guard verified it
correctly and was scored as having failed. Invisible at n=41, surfaced at n=301, and fixed
in the generator.

The four topical rows did **not** widen and cannot: those cases come from a curated
doctrinal-term list that rejects terms as too common to measure (སྟོང་པ་ཉིད occurs in 20,500
segments). They remain the hardest questions here and the least decidable.
`docs/HISTORY.md` has the isolation experiments behind the Pāli and Tibetan figures.

Reproduce with:

```bash
PRAMANA_EMBEDDING=1 mix pramana.evals
```

### Two questions, not one

The last two blocks measure different things and both are reported, because reporting
either alone misleads.

**Per-tradition reachability** asks "can an English query reach the *Pāli* witness of
this topic?" A correct answer from the Chinese canon counts as a miss, because the
question was whether that canon is reachable. This is the number that tells you a corpus
has gone dark.

**Answered from any tradition** asks "did the reader get a good answer from anywhere?"
Either canon counts. This is what someone using the system cares about, and at **81.8%**
it is a very different picture from the 0% and 75.0% above it. Until the two were
separated (#44), answering correctly from the other canon was scored as a failure.

### The finding that matters

The last three rows are the same kind of question asked three ways, and they isolate a
single failure. **Chinese retrieval is not broken — cross-lingual retrieval into Chinese
is.** Ask in Chinese and the corpus answers perfectly; ask the identical question in
English and it answers not at all.

The reason is structural, not a tuning problem. Phase 3 built a second vector per chunk
holding an English rendering, which is why an English question reaches Pāli at 75.0%.
Phase 5 gave Tibetan the same layer, from 84000's published translations — and Tibetan
topical retrieval is **22.2%** anyway, because 84000 has translated 385 of ~1,169 Tōhoku
numbers and **95% of the Kangyur therefore has no English vector to cross on**. A layer
over a twentieth of a canon is a thin layer for topical questions.
**The Chinese canon has no such layer** — no English translation exists for it in this
corpus — so an English query must cross into Literary Chinese inside BGE-M3's own
multilingual space, which `Pramana.Retrieval.Semantic` has said from the start is
unproven on this material. Now it is measured: it does not work.

One deterministic route out was tried and **rejected on evidence**: walk an English query
to a Pāli anchor through the translation layer, then to a Chinese passage through the
curated parallels. **1 of 12**, and it fails at the parallels step rather than the term
step — eleven of the twelve questions land on Pāli works with no openable Chinese parallel
at all. That is what surfaced the 6.1% figure above.

That makes an English gloss layer for Chinese chunks the highest-value retrieval work
available, ahead of any parameter tuning — with a caveat measured the hard way. A free
pilot attached human English from curated Chinese↔Pāli parallels to 1,616 Āgama chunks
and moved English→Chinese from 0% to 33.3%. It also cost Pāli recall, because English
vectors from every tradition compete in one space: 1,665 gloss vectors were enough to
displace Pāli answers, and a full canon pass would add ~300,000 against 14,781 Pāli ones.
The layer is therefore built and **opt-in** (`vector_kinds: ["source", "translation",
"parallel_gloss"]`) until there is a tradition-balancing story. See `docs/HISTORY.md`.

### What these numbers do not say

Publishing a benchmark obliges you to publish its limits.

- **The two retrieval rows measure different tasks.** `retrieval` asks the system to find
  the one anchor whose exact text was quoted; `topical` asks whether a natural question
  returns a passage that genuinely discusses the topic. The second is easier and is what
  users actually do. Reporting only the first would understate the experience; reporting
  only the second would flatter it.
- **Topical ground truth is a term, not an anchor.** A case passes when a returned passage
  contains the canon's own term for the topic — `satipaṭṭhān`, `四念處`. Terms occurring
  in more than 2,500 segments are rejected at derivation as too common to measure
  anything; `涅槃` at 49,397 would have passed on almost any retrieval at all.
- **The derived retrieval queries are not paraphrases.** They are a translator's own
  English, or the canon's own definitional formula. Hand-written paraphrase questions are
  the topical set; the two are scored separately and never averaged.
- **Results vary slightly between runs, pass rates included.** Approximate nearest-neighbour
  search with `relaxed_order` does not return a fixed ordering. Two runs of an identical
  build differed by one case in each of `retrieval` (68.0% / 66.7%) and `topical`
  (60.0% / 57.5%), and mean ranks move by ~0.05. An earlier version of this file claimed
  pass rates were stable; that was wrong, and the gate now tolerates a one-case drop
  rather than treating noise as a regression.
- **No single headline figure is meaningful.** Guard pass rate and retrieval recall
  measure different things. The scorecard reports per type, and crossed with tradition,
  because that cross-tab is where the 100%/0% split above became visible at all — both
  margins hide it.
- **Over half the Pāli `retrieval` cases (21 of 40) quote text that occurs in more than
  one place.** This literature was composed to be memorised, so stock passages recur
  verbatim — `sn12.1@3.1` appears 15 times. A case therefore expects **every**
  byte-identical location; scoring against one arbitrary copy measured luck and would
  have published 27.5% where 37.5% is true.

### The gate

`mix pramana.evals --gate` compares against `evals/baseline.json` and fails if any case
type drops. It is a ratchet, like the test-coverage threshold: numbers that rise get
recorded, numbers that fall fail the build.

---

## What it does

- **Addresses everything by URN.** `pramana:cbeta.T:T0262_009@p0037a13` is Taishō volume 9,
  page 37, upper register, line 13 — a physical location you can check on a library shelf.
  Citation ids are never invented; each tradition's own grammar supplies them.
- **Verifies quotations deterministically.** The citation guard re-resolves every URN and
  byte-compares the quoted span, outside the model and after generation.
- **Keeps provenance structural.** Composition origin, text role, attribution confidence
  and addressing level are separate typed fields that travel into every result and cannot
  be flattened by a caller.
- **Treats translation as a pool, not a winner.** There has never been "the" English
  translation of this material. Callers supply a selection policy and are told how many
  renderings were withheld. A rendering has no top-level URN — it is addressed as a
  fragment of the source it renders, so it cannot be cited as scripture.
- **States what it does not have.** Taishō volumes 56–84 (the Japanese-composed sectarian
  corpus) are absent, as are 23 of CBETA's 26 collections, and every survey response names
  them — because silence would read as the tradition having nothing to say.
- **Says how close its best answer was.** Semantic search returns its nearest neighbours
  whatever the distance, so it cannot fall silent on a question the corpus cannot answer.
  Every hybrid response therefore reports the top similarity and a band; a hard cut-off
  was measured and refused, because the only threshold that admits no unanswerable query
  also rejects 10% of answerable ones.

---

## Reading it as a person

```bash
mix phx.server                        # http://localhost:4000
PRAMANA_EMBEDDING=1 mix phx.server    # loads BGE-M3 (~80 s, ~2.2 GB) for hybrid search
```

| | |
|---|---|
| `/` | search, **bucketed by composition origin and text role** — never a flat ranked list |
| `/survey?q=…` | every occurrence counted, not the best twenty, with how concentrated they are |
| `/passage?urn=…` | a line in its printed context, with variants, rare characters, translations, parallels, a link to the published edition and the photograph of the woodblock leaf |
| `/works/:id` | a work's structure, leading with provenance |

See [`docs/READER.md`](docs/READER.md). The reader is a *renderer*: it computes nothing
about the corpus, and five times so far a screen that needed corpus logic meant the domain
was missing a function.

---

## Stack

Elixir/Phoenix umbrella · PostgreSQL 18 with pgvector and pg_bigm · BGE-M3 embeddings on a
rented L4 via Modal · MCP server exposing **fourteen** read-only tools · Phoenix LiveView reader with five screens.

---

## Documentation

| file | what it covers |
|---|---|
| [`docs/PRIMER.md`](docs/PRIMER.md) | **Start here.** The whole system from the ground up, plus a glossary |
| [`CLAUDE.md`](CLAUDE.md) | The eight invariants everything else defends |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Pipeline stages in technical detail |
| [`docs/STATUS.md`](docs/STATUS.md) | What is true right now |
| [`docs/RULES.md`](docs/RULES.md) | **58 rules**, each learned from a real defect and cited by number |
| [`docs/HISTORY.md`](docs/HISTORY.md) | What happened, in order — true of its date, not of today |
| [`docs/PROXIES.md`](docs/PROXIES.md) | Why every cheap evaluation proxy lied, and what it cost |
| [`docs/MCP.md`](docs/MCP.md) | The tool surface a model actually sees |
| [`docs/READER.md`](docs/READER.md) | The same corpus for a person, and what each screen insists on |
| [`docs/CHECKS.md`](docs/CHECKS.md) | `mix pramana.gate`, and what CI can and cannot prove |
| [`docs/SOURCES.md`](docs/SOURCES.md) | Each source, its licence, its citation grammar |
| [`docs/EMBEDDING.md`](docs/EMBEDDING.md) · [`docs/GPU_RUNBOOK.md`](docs/GPU_RUNBOOK.md) | Model choice, cost, and the embedding round trip |

---

## Licensing

**We publish the pipeline, not the corpus.** Sources carry genuinely different terms —
CBETA is non-commercial and not redistributable; SuttaCentral's Pāli root text is Public
Domain Mark — so `license_class` and `redistributable` are structured columns a query can
enforce, and a public surface sets `redistributable_only: true` once.

`raw/` and locally-added text are gitignored and never committed.
