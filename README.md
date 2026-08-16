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
| Texts | **10,914** |
| Segments (citable units) | **5,185,767** |
| Chinese works (CBETA / Taishō) | 2,471 |
| Pāli works (SuttaCentral) | 8,442 |
| Retrieval chunks | 327,754 |
| Embedding vectors | **342,535** (100% embedded) |
| English renderings | 210,756 by 8 translators |
| Curated cross-tradition parallels | 407,176 (24,717 resolvable at both ends) |

Both integrity checks are green over every text: `mix pramana.verify --all` proves the
bake is a **reproducible** function of pinned inputs, and `mix pramana.integrity` proves
it is a **complete** one. Those are different questions — a pipeline that drops the same
content on every run passes the first and fails the second.

---

## Measured retrieval quality

Nobody in this field publishes retrieval numbers. The nearest comparable project asserts
"~98% of served answers are trustworthy" with no reproducible benchmark. So here is ours,
produced by `mix pramana.evals` over a 200-case gold set committed in [`evals/`](evals/).

**240 cases · 0 stale · overall 81.7%**

| what is measured | cases | result |
|---|---|---|
| **Quote verification** — the guard confirms a quotation that is really there | 40 | **100%** |
| **Quote rejection** — the guard refuses altered text and fabricated URNs | 41 | **100%** |
| **Provenance labelling** — origin and role match the Taishō's own catalogue | 40 | **100%** |
| **Absence** — the system returns nothing where it holds nothing | 4 | **100%** |
| **Adversarial subset** | 45 | **100%** |
| **Retrieval @10** — find the one anchor whose text was quoted | 75 | **65.3%** (mean rank 2.8) |
| ↳ Chinese | 35 | 97.1% |
| ↳ Pāli, English query | 40 | 37.5% |
| **Topical @10** — a natural question returns a passage that discusses it | 40 | **55.0%** (mean rank 2.0) |
| ↳ Chinese question → Chinese passage | 12 | **100%** (mean rank 1.25) |
| ↳ English question → Pāli passage | 16 | 62.5% |
| ↳ English question → Chinese passage | 12 | **0%** |

Reproduce with:

```bash
PRAMANA_EMBEDDING=1 mix pramana.evals
```

### The finding that matters

The last three rows are the same kind of question asked three ways, and they isolate a
single failure. **Chinese retrieval is not broken — cross-lingual retrieval into Chinese
is.** Ask in Chinese and the corpus answers perfectly; ask the identical question in
English and it answers not at all.

The reason is structural, not a tuning problem. Phase 3 built a second vector per chunk
holding an English rendering, which is why an English question reaches Pāli at 62.5%.
**The Chinese canon has no such layer** — no English translation exists for it in this
corpus — so an English query must cross into Literary Chinese inside BGE-M3's own
multilingual space, which `Pramana.Retrieval.Semantic` has said from the start is
unproven on this material. Now it is measured: it does not work.

That makes generating an English gloss layer for Chinese chunks the highest-value
retrieval work available, ahead of any parameter tuning.

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
- **Mean ranks vary slightly between runs.** Approximate nearest-neighbour search with
  `relaxed_order` does not return a fixed order, so mean rank moves by ~0.05 run to run.
  Pass rates have been stable.
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
  corpus) are absent, and every survey response says so, because silence would read as the
  tradition having nothing to say.

---

## Stack

Elixir/Phoenix umbrella · PostgreSQL 18 with pgvector and pg_bigm · BGE-M3 embeddings on a
rented L4 via Modal · MCP server exposing nine read-only tools.

---

## Documentation

| file | what it covers |
|---|---|
| [`docs/PRIMER.md`](docs/PRIMER.md) | **Start here.** The whole system from the ground up, plus a glossary |
| [`CLAUDE.md`](CLAUDE.md) | The eight invariants everything else defends |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Pipeline stages in technical detail |
| [`docs/STATUS.md`](docs/STATUS.md) | Current state, and **"Rules that generalize"** — every hard-won lesson |
| [`docs/MCP.md`](docs/MCP.md) | The tool surface a model actually sees |
| [`docs/SOURCES.md`](docs/SOURCES.md) | Each source, its licence, its citation grammar |
| [`docs/EMBEDDING.md`](docs/EMBEDDING.md) · [`docs/GPU_RUNBOOK.md`](docs/GPU_RUNBOOK.md) | Model choice, cost, and the embedding round trip |

---

## Licensing

**We publish the pipeline, not the corpus.** Sources carry genuinely different terms —
CBETA is non-commercial and not redistributable; SuttaCentral's Pāli root text is Public
Domain Mark — so `license_class` and `redistributable` are structured columns a query can
enforce, and a public surface sets `redistributable_only: true` once.

`raw/` and locally-added text are gitignored and never committed.
