# What Exists, and What We Do Better

## fojin (`xr843/fojin`)

Created March 2026 · 329★ · Apache-2.0 · `fojin.app`

10,500+ texts from 613 sources; ~680k embedded passages; Postgres+pgvector +
Elasticsearch 8 + BGE-M3; FastAPI/React; an `fojin-mcp` server; a knowledge graph of
110k entities / 28k relations; 32 dictionaries / 748k entries; 15 "master persona"
voices; three deterministic answer guards (citation whitelist, verbatim quote check,
trust labeling).

**It is a serious project.** Treat the citation guards and the MCP server as
validation of the approach, not as things to differentiate from.

### Where it's weak

| Gap | What we do |
|---|---|
| **Cross-canon alignment is only ~3,000 LLM-verified chunk pairs** — small, and embedding-derived alignment across Classical Chinese and Pāli is exactly where general multilingual models are least reliable | **SHIPPED (#18).** 407,176 hand-curated relations imported from SuttaCentral, **24,717 resolvable at both ends** — 8× their count, from decades of comparative scholarship rather than model inference, and typed by strength (`full` / `resembling` / `sections` / `mentions` / `retells`) so a passing mention is never presented as a parallel. |
| **No public eval set.** "~98% of served answers are trustworthy" is self-asserted with no reproducible benchmark | **SHIPPED (#19).** `evals/` holds 200 gold cases; `mix pramana.evals` scores them and the README publishes the result — including retrieval at 65.3%@10 and cross-lingual Pāli at 37.5%. Publishing the weak number is the point: it is what makes the strong ones credible. |
| **No variant readings.** CBETA's TEI carries a full `<app>/<lem>/<rdg>` apparatus across Song/Yuan/Ming/Koryŏ witnesses; fojin appears to flatten it | **SHIPPED (#45).** `compare_witnesses` returns the apparatus with each reading attributed — 消 → 銷 in 【宋】【元】【明】 — over the 572,701 segments that carry one. The attribution is the hard part: witness ids are declared per file and `wit1` means 38 different things across the canon, so each text carries its own map and an unresolvable id is returned as unidentified rather than guessed. |
| **No composition-origin modeling** — 613 sources flattened into one `source` field | The multi-axis provenance model. Your Taishō 56–84 requirement isn't a feature here; it's the schema. |
| **Master personas are a gimmick and a hallucination vector** — "answer in the voice of Nāgārjuna" invites the model to generate plausible-sounding doctrine | Replace with **doctrinal position tracking**: "how does *śūnyatā* differ across Madhyamaka, Yogācāra, and Tiantai sources?" — same appeal, grounded in retrieved passages, no voice mimicry. |
| **Translation is underused** — generic "translate this sutra" | Terminology-consistent translation: pin a glossary (DDB / Mahāvyutpatti / 84000) per request, enforce it, and *show the chain*: 空 ← śūnyatā ← stong pa nyid. Translation with a visible, auditable term map is a different product. |

### Re-checked at the Phase 3+4 gate — 2026-08-16

Their public repository: **331★** (was 329), no public evaluation set, no variant
readings, no composition-origin modelling. The positioning above still holds.

Two fairness notes, because a competitive doc that flatters you is useless:

- Their claim is **not** "we did nothing". The README now also cites alignment pairs at
  `confidence ≥ 0.75` with hand-verification showing 100% precision on samples. A hand
  check of a sample is real evidence. The difference is that a third party cannot rerun
  it — ours is a committed gold set and a command.
- **They still have more corpus and a shipped UI.** Nothing in this gate changes that.

And what we claim here that is **not yet true**:

| claim | actual state |
|---|---|
| Variant readings shipped | **Now true (#45).** `compare_witnesses` answers it, witness-attributed. |
| Doctrinal position tracking | Not built. Phase 7 (#27). |
| Terminology-consistent translation with a visible term chain | Not built. The glossary is seeded (376 terms) and the pool exists; the engine is Phase 7 (#26). |
| Quotation graph | **Built (#22).** `get_quotations` over verbatim reuse found by a standalone Rust scanner. |

## tripitaka-mcp (`dhamma-seeker/tripitaka-mcp`)

Created April 2026 · 6★ · MIT code, non-commercial data · `tripitaka-mcp.com`

Pāli-only: ~444k segments at SuttaCentral parity, 13 MCP tools, Postgres+pgvector
(hosted) or SQLite+FTS5 (local), MiniLM embeddings, RRF hybrid search, segment-level
citation with reader deep-links.

**Small, but the best-designed MCP surface in this space. Steal from it:**

- **`survey_corpus`** — returns *exhaustive* counts and all matched word-forms rather
  than top-k. This is the single best idea in either project: it stops the model
  from over-generalizing from five lucky hits, and it answers "how often does the
  canon actually say this?" — a question top-k retrieval structurally cannot.
- **`define_from_suttas`** — canonical self-definitions via formulaic patterns
  ("Katamañca X? …"). The Chinese analogue is 「云何為X」/「何謂X」/「所言X者」, the
  Tibetan is its own set. Cheap to implement, very high value.
- **Morphological parsing** — Pāli needs lemmatization, Chinese needs word
  segmentation, Tibetan needs syllable/particle splitting. Without it, lexical
  search silently under-recalls.
- **Dual hosted/local modes**, and **honesty about limitations** — it states plainly
  that its embeddings aren't Pāli-trained. Match that candor.

**Where we go beyond it:** four traditions instead of one; provenance modeling (which
it doesn't need with a single canon); cross-canon parallels; language-appropriate
embeddings and lexical indexes; local mode that keeps semantic search.

### Taken from it, after reviewing tripitaka-mcp.com

Reviewed 2026-08-14. Four things adopted, one rejected.

1. **Context-window discipline** — *"Even the longest sutta (DN 16, 1,664 segments)
   stays usable without flooding the context window."* This was a genuine gap: our
   `get_passage` returned one printed Taishō line, and Taishō lines are typographic,
   so results cut mid-sentence. **Built:** `Corpus.context/2`, `Corpus.outline/1`, and
   range-URN resolution.
2. **Outline mode** — which exposed a mistake of ours. CBETA ships a table of contents
   in `<cb:mulu>` and we were discarding it as navigation apparatus. Correct for body
   text, wrong overall. **Built:** captured as `texts.outline`.
3. **Inflected-form lookup** → variant Han characters (異體字) for us. *(Task #32.)*
4. **MCP resources, not only tools** — they expose 3; we exposed none, ignoring half
   the protocol. *(Task #33.)*
5. **Reader deep-links** (`/read/{id}#{segment}`, scroll-centred and highlighted),
   designed now so citations don't need reshaping in Phase 8. *(Task #33.)*

**Rejected:** their trigram keyword index. Trigrams cannot serve the two-character
queries that dominate Chinese; we use `pg_bigm`. They also concede their embeddings are
not language-specific, which is precisely the mistake we are avoiding.

---

## Features neither project has

Ranked by (differentiation × feasibility).

1. **Quotation graph.** Suffix-array/n-gram matching across ~250M characters to find
   verbatim reuse. Commentaries quote root texts constantly. Deterministic, no LLM,
   and it yields a real citation network: *"every text that quotes this passage."*
   Nobody has built this for the Buddhist canon at scale.

2. **Translator fingerprinting (異譯本).** Many works were translated into Chinese
   2–6 times — the Lotus Sūtra three times. Aligning parallel translations of the
   *same* work automatically produces a translator-term-equivalence table:
   how Kumārajīva, Xuanzang, and Paramārtha each rendered the same Sanskrit term.
   This is a goldmine unique to the Chinese canon and it falls out of alignment work
   you're doing anyway.

3. **Multiple-translation diff view.** Three Chinese Lotus Sūtras, aligned and
   diffed side by side. Immediately legible value; directly enabled by (2).

4. **Diachronic term semantics.** How 空 / 道 / 法 shift meaning from Han-era
   translations to Kumārajīva to Xuanzang. A real digital-humanities question the
   corpus can answer and no one has built.

5. **Variant-reading-aware retrieval.** Search that knows the Song edition reads
   differently, and says so.

6. **Agentic research mode.** Multi-hop: the model plans a retrieval strategy, runs
   surveys and cross-reference queries, and produces a sourced report with every
   claim URN-anchored. *This* is where "Claude-level intelligence over the texts"
   actually lands — not in a better chatbot, but in an agent that can run twenty
   retrievals and synthesize with verifiable citations.

7. ~~**Honest uncertainty.** When retrieval is weak, say so, with a measured number
   from the eval harness rather than an asserted percentage.~~ **▸ SHIPPED 2026-08-27.**
   Every hybrid response carries `semantic_confidence` — the top similarity and a band,
   `strong` / `weak` / `no_close_match` — calibrated on 56 queries with known and known-
   absent answers, plus `lexical_support` so the two arms can be read together. The
   combination fires for 6 of 10 unanswerable questions and **0 of 46 answerable ones**,
   paraphrases included.

   What makes this the differentiator rather than a feature: **a hard threshold was
   measured and refused.** The lowest cut-off admitting no unanswerable query rejects 10%
   of answerable ones — about 45 of 446 retrieval cases, to gain 1 absence case. The
   honest move was to report the number and let the caller weigh it, and the reason is
   published with the cost attached. `docs/PLAN.md` item D.

## The strategic read

fojin has more corpus; you will not out-scale it quickly there. **The UI half of that
sentence stopped being true on 2026-08-26**: `/`, `/survey`, `/passage` and `/works/:id`
ship, and the survey page in particular is not a search box — it counts every occurrence
and reports how concentrated they are, which is the question a ranked list cannot answer.
See `docs/READER.md`.

Compete on **verifiability and philological depth** instead. Provenance modeling,
variant readings, deterministic alignment, the quotation graph, and a published eval
harness are all things a general-purpose "Buddhist AI" project structurally
deprioritizes — and they compound into a corpus that is more *trustworthy*, which is
the only durable moat in a field where a confident wrong citation is worse than no
answer.

The bake is the asset. Models are commodities.
