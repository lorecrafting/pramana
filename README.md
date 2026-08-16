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

**200 cases · 0 stale · overall 87.0%**

| what is measured | cases | result |
|---|---|---|
| **Quote verification** — the guard confirms a quotation that is really there | 40 | **100%** |
| **Quote rejection** — the guard refuses altered text and fabricated URNs | 41 | **100%** |
| **Provenance labelling** — origin and role match the Taishō's own catalogue | 40 | **100%** |
| **Absence** — the system returns nothing where it holds nothing | 4 | **100%** |
| **Retrieval @10** — a query returns the passage scholarship points at | 75 | **65.3%** (mean rank 2.8) |
| ↳ Chinese | 75 | 98.7% (mean rank 2.18) |
| ↳ Pāli, cross-lingual | 40 | **37.5%** (mean rank 4.3) |
| **Adversarial subset** | 45 | **100%** |

Reproduce with:

```bash
PRAMANA_EMBEDDING=1 mix pramana.evals
```

### What these numbers do not say

Publishing a benchmark obliges you to publish its limits.

- **The retrieval queries are not paraphrases.** They are a translator's own English, or
  the canon's own definitional formula (`云何為X`). That tests whether the pipeline
  connects known text to the right anchor among 327,754 chunks — a real test, and an
  easier one than a question a person would actually type. Hand-written questions belong
  alongside these; they are not here yet.
- **Cross-lingual retrieval into Pāli is the weak axis, at 37.5%.** It is published
  because it is true. The likely cause is chunk granularity: a query quoting one sentence
  is matched against a vector covering a ~20-sentence window, and the signal dilutes.
  Related: 23.6% of English translation vectors exceed the model's 320-token window and
  are truncated (`docs/EMBEDDING.md`).
- **Mean ranks vary slightly between runs.** Approximate nearest-neighbour search with
  `relaxed_order` does not return results in a fixed order, so mean rank moves by ~0.05
  run to run. The pass rates have been stable across runs; the ranks are quoted to one
  decimal for that reason.
- **No single headline figure is meaningful.** Guard pass rate and retrieval recall
  measure different things; averaging them produces a number that sounds like an accuracy
  and is not one. The scorecard reports per type, always.
- **Over half the Pāli gold cases (21 of 40) quote text that occurs in more than one
  place.** This literature was composed to be memorised, so stock passages recur verbatim —
  `sn12.1@3.1` appears 15 times. Scoring against a single arbitrary copy measured luck, so
  a case expects **every** byte-identical location. Fixing that moved Pāli from 27.5% to
  37.5%; the earlier figure was a flaw in the gold set, not in the retriever.

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
