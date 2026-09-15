# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 6

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### PostgreSQL and its extensions

| extension | what it adds |
|---|---|
| **pgvector** | a `vector` column type, distance operators, and HNSW/IVFFlat indexes |
| **pg_bigm** | bigram full-text indexing, which works on languages without spaces |

A **migration** is a versioned, ordered change to the database schema, stored as code so
the schema's history is reviewable and repeatable.

A **check constraint** is a rule the database itself enforces — for example, that a
licence class must be one of a known list, or that a `verified` reading must actually
state a reading. Rules enforced in the database cannot be forgotten at a call site. Two
real bugs here were caught by constraints refusing to write.

### MCP

**MCP** (Model Context Protocol) is a standard way for an AI model to call external tools.
The system exposes the corpus over MCP, so a model can call `get_passage` or `search` the
same way it would call any tool.

The MCP surface is **read-only**: tools read, the command line writes. A model can never
modify the corpus it is citing.

Current tools: `search`, `survey_corpus`, `get_passage`, `get_outline`, `get_commentaries`,
`get_parallels`, `verify_citation` — plus two **resources** (documents a model can read for
guidance rather than call).

`survey_corpus` deserves a note: it returns **exhaustive counts, not a ranked sample**. It
is the tool that supports claims about *how often* or *where* something appears, which a
top-20 result list cannot.

### Modal

**Modal** runs code on cloud GPUs on demand. Used for the embedding pass: an L4 GPU for 34
minutes, roughly $0.45, rather than 65 hours on a laptop.

---

## 19. How to actually run things

```bash
# Acquire and ingest
mix pramana.acquire_all             # download + pin every configured source
mix pramana.acquire                 # one source at a time
mix pramana.bake_all                # normalize + segment the Chinese canon
mix pramana.sc.ingest               # Pāli root text (8,442 works, ~53 s)
mix pramana.sc.translations         # English renderings into the pool
mix pramana.parallels.import        # SuttaCentral's curated relations
mix pramana.readings.seed           # reading exceptions from the glossary

# Retrieval plumbing
mix pramana.chunk                   # group segments into chunks
mix pramana.embed.export out.jsonl  # text out, for the GPU
mix pramana.embed.import in.jsonl   # vectors back in, sha-checked

# The checks that must pass at a gate
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test --cover
mix pramana.verify --all            # reproducibility
mix pramana.integrity               # completeness
```

Elixir and OTP versions are pinned with **mise** (a version manager). In non-interactive
shells the shims may be absent, so build commands use `mise exec --` and verify with
`elixir --version` rather than trusting `mise current` — a subtlety that once caused
builds to silently use the wrong Elixir.

---

## 20. Glossary

**Anchor** — an edition's own address for a piece of text (`0037a13`, `1.1`). The thing a
URN is built from and the thing a layer attaches to.

**ANN (approximate nearest neighbour)** — finding *nearly* the closest vectors very fast,
instead of the exact closest slowly. See HNSW.

**Apocrypha (疑偽經)** — texts composed in China that present themselves as translations
from Indian originals. 57 are flagged here. Not a value judgement: a fact about origin.

**Āgama** — Chinese collections translating an early Indian collection closely related to
the Pāli Nikāyas.

**Bake** — source text produced from recorded inputs; the identity does not freeze
all derived retrieval state or provide coexistent historical snapshots.

**BGE-M3** — the multilingual embedding model used here; 1,024 dimensions.

**Bigram** — a pair of adjacent characters. The indexing unit for languages without
spaces.

**bilara-data** — SuttaCentral's repository of segment-aligned Pāli text and translations.

**CBETA** — the Taiwanese association whose XML is the source of the Chinese material.

**Chunk** — a window of consecutive segments, ~300 characters, the unit that gets
embedded. Addressed by a range URN.

**Check constraint** — a rule enforced by the database itself.

**Credo / Dialyzer** — Elixir's style linter and static type checker.

**Derived addressing** — an address we invented because the source has no citation scheme;
always flagged, never allowed to resemble a canonical one.

**Ecto** — Elixir's database library.

**Embedding** — a list of numbers representing meaning; 1,024 per chunk here.

**Gaiji (外字)** — a character in the printed text with no Unicode codepoint. 133,049 in
this corpus.

**Gate** — a checkpoint ending a phase; the full check suite must pass to tag it.

**Guard** — the component that re-resolves every URN and byte-compares every quotation.

**HNSW** — *Hierarchical Navigable Small World*, the graph index that makes vector search
fast.

**Ingest** — the whole act of bringing an outside text in: download, parse, segment, store.

**Inner product** — the arithmetic used to compare two vectors here.

**IR (intermediate representation)** — the single internal shape every source is normalized
into, so downstream stages need not know about formats.

**Iterative scan** — pgvector 0.8 feature that keeps walking the ANN graph until enough
results survive a filter. Without it, filtered vector search silently under-returns.

**Juan (卷)** — a fascicle; a division of a work, inherited from scrolls.

**Lexical search** — matching characters. Fast, exact, literal.

**Locator** — the part of a URN addressing a position inside a work.

**MCP (Model Context Protocol)** — the standard by which a model calls these tools.

**Migration** — a versioned schema change, stored as code.

**Modal** — the service used to rent GPU time for embedding.

**Nikāya** — a division of the Pāli canon (DN, MN, SN, AN, Khuddaka).

**Normalize** — convert a publisher's format into the IR.

**Oban** — Postgres-backed background job queue.

**Parallel** — a curated correspondence between texts in different languages, typed by
strength.

**pg_bigm / pgvector** — PostgreSQL extensions for bigram text search and vector search.

**Pinning** — recording exact file hashes so the corpus is tied to specific bytes.

**Provenance** — where a text came from: composition origin, role, confidence, addressing.

**Rendering** — one translation of one anchor by one translator. Addressed only as a
fragment of a source URN.

**RRF (Reciprocal Rank Fusion)** — merging two ranked lists using only ranks, `1/(k+rank)`
with `k = 60`.

**Segment** — the smallest citable unit; one printed line, with its address. 5,185,767 of
them.

**Semantic search** — matching meaning via vectors.

**Sparse checkout** — cloning only part of a Git repository.

**Sutta / Sūtra** — a discourse attributed to the Buddha (Pāli / Sanskrit).

**Taishō (大正新脩大藏經)** — the standard 100-volume edition of the Chinese Buddhist canon,
1924–34. Its page/register/line addressing is the corpus's citation backbone.

**Tier (T0/T1/T2)** — how much provenance a translation has: human, baked-with-pinned-config,
or query-time ephemeral.

**Tipiṭaka** — "three baskets", the Pāli canon.

**URN** — the permanent citation address; the spine of the whole system.

**Variant characters (異體字)** — historically different written forms of the same
character (眾/衆/众). 6,447 classes are normalized in search.

**Witness** — a specific manuscript or printed edition testifying to a text.

---

## 21. Where to read next

In roughly this order:

| file | what it covers |
|---|---|
| `CLAUDE.md` | the seven invariants and the working rules — the constitution |
| `docs/ARCHITECTURE.md` | the pipeline stages in technical detail |
| `docs/SOURCES.md` | each source, its licence, and its citation grammar |
| `docs/LAYERS.md` | translations, readings, and locally-added texts |
| `docs/TRANSLATION.md` | the pool, tiers, selection policy, and the promotion pipeline |
| `docs/MCP.md` | the tool surface a model actually sees |
| `docs/READER.md` | the same corpus for a person — and the four things the view had to push back into the domain |
| `docs/CHECKS.md` | what must pass at a gate |
| `docs/STATUS.md` | where the project is right now
| `docs/RULES.md` | **58 rules**, each learned from a real defect and cited by number
| `docs/HISTORY.md` | what happened, in order
| `docs/PROXIES.md` | why every cheap evaluation proxy lied |
| `docs/GPU_RUNBOOK.md` | the embedding round trip, step by step |
| `docs/EMBEDDING.md` | model choice and cost |
| `docs/ADDING_TEXTS.md` | how to put a text of your own into the corpus |
| `docs/DEV_ENV.md`, `docs/ELIXIR.md` | getting a working environment, and the language |
| `docs/ROADMAP.md` | the phases and what each one is for |

If you read only one after this: **`docs/RULES.md`**. It is the
distilled experience of every bug this project has hit, and most of them are the kind that
produce results that look correct.
