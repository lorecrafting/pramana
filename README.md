# Pramāṇa

A citation-grounded retrieval substrate for the Buddhist canon, where **every quotation
can be mechanically proven to exist, in that form, at that place in a real printed
edition** — and where a Japanese-composed commentary can never be handed back as if it
were an Indian sūtra.

*Pramāṇa* (प्रमाण) is Sanskrit for "valid means of knowledge": the branch of Indian
philosophy concerned with how one knows a claim is true. That is the design brief.

**It is English-first.** You ask in English. The canons stay in Pāli, Classical Chinese and
Tibetan, and every answer comes back anchored to the original — with its provenance, and with
a citation you can check.

New to the project? **[`docs/PRIMER.md`](docs/PRIMER.md)** explains it from the ground up —
no prior knowledge of Elixir, search systems, or Buddhist studies assumed.

**For AI agents: [`AGENTS.md`](AGENTS.md)** is the canonical project reference — invariants,
document routing, project layout, rules triggers, framework conventions.

---

## The corpus

| | |
|---|---|
| Texts | **17,281** |
| Segments (citable units) | **12,581,624** |
| Chinese works (CBETA) | 4,263 across **16 of 26 collections** — Taishō 2,471 · 卍續藏 1,230 · 嘉興藏 285 · 磧砂藏 101 · 趙城金藏 51 · 漢譯南傳大藏經 38 · 房山石經 27 · seven alternative editions 57 · 国家图书馆藏 2 · 藏外佛教文獻 1 |
| Pāli works (SuttaCentral) | 8,442 |
| Tibetan works (Degé Kangyur / Tengyur) | 1,195 / 3,380 |
| Retrieval chunks | 980,464 |
| Embedding vectors | **1,066,026** |
| English renderings | 273,334 — 244,763 human by 8 translators, 28,571 generated |
| Commentary aligned to the line it explains | 76,722 lemmas over 100 work pairs |
| Curated cross-tradition parallels | 407,176 recorded, 24,717 (6.1%) openable |
| Verbatim quotations between works | 141,073 across 1,301 works |
| Buddhist reading exceptions | 9,543 over a 44,348-character base |

Both integrity checks are green: `mix pramana.verify --all` proves the bake is
**reproducible** from pinned inputs; `mix pramana.integrity` proves it is **complete**.
`mix pramana.gate` runs both plus format, credo, tests, lockfile census and eval ratchet.

**CBETA is 26 collections and this holds 16.** Every survey response names the absent
collections, because an empty result otherwise reads as the canon being silent. It says
the same about **Taishō volumes 56–84** (547 works, not in CBETA), about the **6.1% of
the parallel graph** whose other end is a witness we do not hold, and about the **1,640
texts a `role:` filter cannot reach** because only the Taishō has a 部 division table.

---

## Measured retrieval quality

Produced by `mix pramana.evals` over the gold set in [`evals/`](evals/).

| case type | pass | total | rate |
|---|---|---|---|
| retrieval | 27 | 40 | 67.5% |
| topical | 34 | 40 | 85.0% |
| guard | 58 | 58 | 100% |
| integrity | all green | | |
| coverage caveat | 23 | 33 | 69.7% |

All five are scored independently and gated as a ratchet. See `docs/PLAN.md` § E and
`docs/PROXIES.md` for what each measures and what the limitations are.

---

## What it does

- **Addresses everything by URN.** `pramana:cbeta.T:T0262_009@p0037a13` is a physical
  location on a library shelf. Citation ids are never invented.
- **Verifies quotations deterministically.** The citation guard re-resolves every URN and
  byte-compares the quoted span, outside the model and after generation.
- **Keeps provenance structural.** Composition origin, text role, attribution confidence
  and addressing level are separate typed fields that travel into every result.
- **Treats translation as a pool, not a winner.** Callers supply a selection policy.
  A rendering has no top-level URN — it is addressed as a fragment of the source it renders.
- **States what it does not have.** Every survey response names absent collections and
  volumes — because silence would read as the tradition having nothing to say.
- **Says how close its best answer was.** Semantic search returns nearest neighbours
  whatever the distance. Every hybrid response reports the top similarity and a band.

---

## Quickstart

### 1. Prerequisites
- **Erlang & Elixir**: Pinned in [`mise.toml`](mise.toml) (Erlang 29.0.5, Elixir 1.20.3)
- **PostgreSQL 18** with `pgvector` and `pg_bigm` (see [`docs/DEV_ENV.md`](docs/DEV_ENV.md))
- **Rust toolchain** (for CJK segmentation NIF)

### 2. Setup & Compile
```bash
mix deps.get
mix compile
mix ecto.setup
```

### 3. Acquire & Bake Data
The corpus is content-addressed and pinned in [`sources.lock.json`](sources.lock.json). Acquire and bake the texts:
```bash
mix pramana.acquire_all       # downloads upstream sources to raw/
mix pramana.bake_all          # normalizes & segments Chinese works
mix pramana.sc.ingest         # ingests SuttaCentral Pāli root texts
mix pramana.sc.translations   # loads aligned English translations
```

For query embeddings, download the fine-tuned BGE-M3 weights (see [`docs/GPU_RUNBOOK.md`](docs/GPU_RUNBOOK.md)):
```bash
mix pramana.embed.fetch_model # pulls weights into priv/models/ from storage
```

---

## Reading it as a person

```bash
mix phx.server                        # http://localhost:4000
PRAMANA_EMBEDDING=1 mix phx.server    # loads BGE-M3 (~80 s, ~2.2 GB) for hybrid search
```

| | |
|---|---|
| `/` | search, **bucketed by composition origin and text role** |
| `/survey?q=…` | every occurrence counted, with concentration |
| `/passage?urn=…` | a line in its context, with variants, translations, parallels, woodblock |
| `/works/:id` | a work's structure, leading with provenance |

See [`docs/READER.md`](docs/READER.md). The reader renders only — it computes nothing
about the corpus.

---

## Stack

Elixir/Phoenix umbrella · PostgreSQL 18 (pgvector, pg_bigm) · BGE-M3 on a rented L4 via
Modal · 17 read-only MCP tools · Phoenix LiveView reader with five screens. Detailed
stack and toolchain in `AGENTS.md` § Stack. Foundry (agentic workflow system) in
`foundry/README.md`.

---

## Licensing

**We publish the pipeline, not the corpus.** Sources carry different terms — CBETA is
non-commercial, SuttaCentral's Pāli root is Public Domain. `license_class` and
`redistributable` are structured columns a query can enforce. `raw/` is gitignored.
See `docs/DEPLOY.md` for the public deployment contract.