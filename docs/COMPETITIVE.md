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

### The difference that is not a feature — audience

Everything below this line compares features, and for a long time that was the whole of
how this project understood the comparison. **The real difference is who each is for.**

fojin reads as built from Chinese, for readers of Chinese: a Chinese-language interface
and repository, 613 sources of Chinese canonical material, dictionaries serving somebody
who is already reading 漢文 and wants a term explained. Its scale in Chinese is genuine and
this project will not out-scale it there.

**This one is built for an English-speaking reader, and that is the strategy rather than a
translation feature.** The target is somebody who cannot search 遠行地 because they do not
know that is the thing to search for — and every architectural decision that looks
expensive is downstream of it:

| decision | why it follows from the audience |
|---|---|
| 244,763 English renderings anchored to source lines | the reader reads the English and cites the source; both have to be one object |
| the `translation` vector layer, and E1's whole budget | an English question must reach a Chinese line, which needs English *in the index* |
| the DILA glossaries, and Karashima scoped per translator | a reader without Chinese needs the lexicon far more than one with it |
| `/check`, the reader, `verify_report` | this audience arrives through a web page and an assistant, not through a Chinese-language corpus tool |
| invariant #8 — a machine translation is never citable as source | **the reader will rely on the generated English anyway**, so the boundary has to be structural rather than advisory |

**Two consequences that are easy to miss.**

The **on-line** figure matters more here than work-level. A reader who cannot check the
Chinese and is handed the right *work* with the wrong *line* has been given something that
reads authoritative and points at the wrong place. Cross-canon figures in `docs/PLAN.md`
§ E1 are quoted both ways for that reason.

And a correction, because the obvious inference from all this is wrong. It is tempting to
conclude that **`topical/chinese` measures the wrong deliverable** — that it asks only
whether a Chinese passage comes back, when a reader without Chinese needs one they can
read. **It does not.** The consumer of retrieval is a model, models read Classical
Chinese, and translating is the caller's job; the audience argument shapes the *product*
surfaces and not the retrieval measure. `docs/PLAN.md` § "The English layer is for
FINDABILITY" records the reasoning, and the payoff: if the caller translates, generated
English only has to make a passage findable, which is a far cheaper bar than making it
readable.

Interop, not rivalry: fojin-mcp and this surface mount in the same client, and a reader
who has both is better served than one who has either.

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

## Dharmamitra / DharmaNexus / MITRA — the one this file omitted

Sebastian Nehrdich and Kurt Keutzer (UC Berkeley), with Hamburg's Khyentse Center,
Tsadra and Tōhoku. **Missing from this analysis until 2026-08-30**, which is the more
serious error in it: they are the deepest technical group in the field.

- **BuddhaNexus (2020 →)** — intertextual text-matching across all four canons, FastText
  embeddings, `buddhanexus.net`. The thing this file claimed nobody had built.
- **DharmaNexus** — its successor, folded into MITRASearch.
- **MITRA (`arXiv:2601.06400`)** — 1.74M parallel sentence pairs across Sanskrit,
  Buddhist Chinese and Tibetan, plus **Gemma-2-9B models fine-tuned for translation and
  for embedding**, released openly: `buddhist-nlp/gemma-2-mitra-e`.

### Why MITRA-E matters more to us than anything else in this file

**BGE-M3 — the model this corpus embeds with — is one of their baselines.**

    cross-lingual parallel retrieval, P@1·P@5·P@10
      Sanskrit -> Chinese    MITRA-E  79·94·96     LaBSE  19·33·39
      Sanskrit -> Tibetan    MITRA-E  93·98·98     LaBSE  54·69·74

`docs/PLAN.md` § F measures cross-lingual retrieval here at **0.4%**, and proposes a
corpus-derived term table as the fix. **Those numbers are not comparable** — theirs is
sentence-level retrieval on their own benchmark, ours is passage retrieval over 12.5M
segments at a top-100 cap, and quoting 79% against 0.4% would be exactly the
apples-to-oranges error `docs/PROXIES.md` exists to record. But the direction is not in
doubt, and it suggests **the embedder is the bottleneck, not the vocabulary** — which
would make the term table the wrong build.

**Test it, do not assume it.** The 496-case parallel probe is the instrument for that,
and it exists now. Two things to check first: 9B parameters makes the embedding pass a
rented-GPU job rather than an M1 one, and Gemma derivatives carry **Google's Gemma Terms,
not a standard open licence** — which for a project that tracks a licence per source is a
question to answer before adoption, not after.

## Projects that do not exist

Asked what Buddhist-canon LLM projects are out there, a general assistant produced
**"Tripitaka AI"** and **"Dharma Nexus"** with confident feature tables, a named model
(GPT-4), and a claimed consensus on r/theravada. Searched 2026-08-30: **no trace of
either as a distinct project.** "Dharma Nexus" is a garbling of DharmaNexus/BuddhaNexus;
"Tripitaka AI" appears to be `tripitaka-mcp` restated as a product.

Recorded here because the failure is instructive and will recur: a plausible-sounding
landscape is the easiest thing in this field to fabricate, and a competitive analysis
built on one is worse than none. Every project in this file has been opened and read.

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

1. ~~**Quotation graph.** … Nobody has built this for the Buddhist canon at scale.~~
   **▸ THE CLAIM WAS FALSE, corrected 2026-08-30.** BuddhaNexus has done exactly this
   since 2020 — intertextual matching across Pāli, Sanskrit, Tibetan and Chinese — and
   its successor DharmaNexus is a going concern with a research group behind it. See the
   Dharmamitra section below. The line survived here because nobody checked.

   What is still worth building is **not** the graph but what hangs off it: the quotation
   data is 141,073 free relevance judgements, and `mix pramana.recall` turns them into a
   retrieval measurement nobody else publishes. The asset is the *evaluation* the graph
   enables, not the graph.

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

**And the 2026-08-30 review narrowed the differentiators to three.** URNs, an MCP server,
verbatim quote checking, an eval regression gate and an Apache-2.0 rebuild-your-own-corpus
posture are all things fojin ships too; text reuse at canon scale is DharmaNexus's founding
work. What actually remains ours:

1. **Multi-axis provenance, enforced in the response shape.** fojin's README does not model
   composition origin at all. The demonstration is 2026-08-30: 452 of 510 works in
   T2185–T2700 were mislabelled, **Nichiren's 立正安國論 filed as sub-commentary**, and a
   test asserted it. Depth here is not a feature list, it is the thing that makes invariant
   #4 true rather than aspirational.

2. **Verification against the corpus rather than against the session.** fojin checks a quote
   is a substring of *what was just retrieved*. This project re-resolves the URN against a
   content-addressed corpus, byte-compares by sha256, checks provenance, and refuses a
   generated translation presented as source. And **`verify_report` re-executes the searches
   a document's FIGURES rest on** — "appears 36,775 times across 1,904 works" is a claim no
   citation guard can reach. Nothing found in this review does that.

3. **The coverage doctrine.** Publishing the gap with numbers — at least 541 works missing,
   10 of 26 collections absent, 6.1% of the parallel graph openable, a `role:` filter that
   reads 1,515 of 17,281 works and says so on every use. A discipline, not a feature, and
   the opposite of what a product is incentivised to do.

**"The bake is the asset, models are commodities" needs qualifying.** MITRA-E is a model
purpose-built for these four languages that beats the general-purpose embedder this corpus
runs on, in the one place this corpus is weakest. In this field the model is not
interchangeable, and pretending otherwise would cost the cross-lingual axis.

**Interop beats rivalry.** fojin-mcp and this MCP surface can be mounted in the same client
against different corpora. The honest pitch is not "more texts" — it is *the one that tells
you when it is wrong*.
