# Roadmap

Decisions locked: open-source self-hosted · all four traditions in v1 ·
Postgres+pgvector single DB · MCP + HTTP API first · **Elixir/Phoenix**
(see `docs/ELIXIR.md`).

**Scope warning, stated once.** All four traditions in v1 is the ambitious call.
Chinese, Japanese, and Pāli are clean structured text; **Tibetan is a different kind
of problem** — partial etext coverage and a source (BDRC) that is mostly page images.
The mitigation below is to ingest Tibetan from 84000/OpenPecha only in v1 and treat
BDRC OCR as post-v1. If the schedule slips, Tibetan is the thing to cut back, not
the provenance model or the eval harness.

---

## Phase 0 — Skeleton ✅ COMPLETE (tag `phase-0`)

Prove the whole pipeline end-to-end on **one sūtra** before scaling anything.

- Umbrella scaffolding (`pramana`, `pramana_web`, `pramana_native`), credo, native
  Postgres 18 + pgvector (pg_bigm deferred to Phase 1 — see `docs/DEV_ENV.md`)
- Core Ecto schemas: `works`, `witnesses`, `segments`, `provenance`, `embeddings`
- Acquire (Req) + normalize (Saxy) **CBETA T0262 (Lotus Sūtra) only**
- URN parser/resolver + `verify(urn, text)` — build this first; everything depends
  on it. Binary pattern matching makes the Taishō page/register/line grammar clean.
- One MCP tool: `get_passage(urn)`, served from Phoenix

**Spikes, all resolved** (see `docs/STATUS.md` for the evidence):
- **BGE-M3 through Bumblebee** — viable for dense: BGE-M3 declares
  `architectures: ["XLMRobertaModel"]`, which Bumblebee supports. Its sparse/ColBERT
  heads are two loose `.pt` linear layers, portable to Nx.
- **Rustler** — `apps/pramana_native` builds `jieba-rs` on Rust 1.97.1, with FFI
  byte-preservation tests for Han variants and plane-2 glyphs.
- **MCP** — `anubis_mcp` (the maintained fork; `hermes_mcp` is a year stale).

**Exit: MET.** A model fetches an exact Lotus Sūtra passage by URN and the guard
verifies the quote byte-for-byte — including catching a single-character 譯→說
alteration and refusing a fabricated URN.

## Phase 1 — Chinese corpus (weeks 2–5)

- Full CBETA normalize (done): gaiji mapping, `<lb/>` preservation, `<app>` apparatus,
  juan boundaries — Saxy streaming, **Oban** for concurrency and resumability. Broadway
  was dropped here: it earns its place when a slow stage must backpressure an upstream
  *stream*, and the input is a static list of 5,005 files. It may return for the
  embedding stage, where a slow sidecar genuinely needs to throttle producers.
- Chinese word segmentation via the `jieba-rs` Rustler NIF; `pg_bigm` lexical index
- **Retrieval chunks** (done): ~300-char windows over segments, since a printed line
  is far too small and too typographic to embed. 299,317 chunks from 4.7M segments.
- BGE-M3 embeddings, HNSW index, RRF hybrid search — over CHUNKS, not segments
- Provenance axes populated; apocrypha (疑偽部) flagged
- Tools: `search_hybrid`, `get_passage`, `get_work`, `survey_corpus`
- **Reading affordances** (done): context windows, outline mode from `<cb:mulu>`, and
  range-URN resolution — a single Taishō line is typographic, not syntactic, so it
  usually cuts mid-sentence and is unreadable alone
- **Variant-character (異體字) query expansion** — searching 說 must be able to find 説.
  Query-side only: stored text stays byte-identical to the witness
- **MCP resources** — corpus guidance and inventory, so the model uses provenance
  filters rather than guessing

**Exit:** hybrid search across the full Chinese canon with verifiable citations.
Gaiji test suite green.

## Phase 2 — Japanese delta + provenance enforcement (weeks 6–7)

The differentiator. Small phase, high value.

- SAT ingest; dedupe vols 1–55/85 against CBETA by work ID, keeping both as
  distinct witnesses
- Vols **56–84 → `composition_origin: japanese, text_role: commentary`**
- **Grouped tool responses** — results bucketed by origin and role so Japanese
  commentary can never arrive flattened in with Indic sources
- Provenance filters exposed in every search tool
- **Local-source manifest path** (`sources/local/*/manifest.yaml`) — add a one-off
  text with declared provenance and license without touching pipeline code. Test it
  with Huang Nianzu's 無量壽經解: modern, in-copyright, and commenting on a contested
  會集本 conflated edition, so it exercises every provenance axis at once.
  See `docs/LAYERS.md`.

**Exit:** ask a doctrinal question, get Chinese translations and Japanese
commentaries in visibly separate buckets, each correctly labeled.

## Phase 3 — Pāli + first cross-canon parallels (weeks 8–10)

- `bilara-data` ingest (CC0, already segment-aligned — the easiest source)
- Ingest `sc-data` hand-curated Āgama↔Nikāya parallels
- Multi-vector embeddings: source text + English gloss + hypothetical questions
- Tools: `get_parallels`, `compare_versions`, `define_from_canon`
  (「云何為X」 / "Katamañca X?")
- **Translation pool + reading layer schema** — `bilara-data` forces these tables
  anyway (it's already multi-translator); defining them correctly now is what makes
  full-corpus machine translation (Phase 7) and line-by-line/pinyin views a feature
  rather than a migration. Includes tiers and selection policy — see
  `docs/TRANSLATION.md`.

**Exit:** "show me the Pāli parallel to this Āgama passage" works, sourced from
curated scholarship rather than embedding similarity.

## Phase 4 — Eval harness (week 11)

Deliberately its own phase. Do not skip it; do not let it slide past Phase 5.

- Gold set: 200+ questions with known-correct citations, spanning all traditions
- Metrics: recall@k, citation accuracy, quote-verification pass rate,
  provenance-labeling accuracy
- CI gate on retrieval regressions; **publish the numbers**

**Exit:** a public, reproducible benchmark. This is the credibility differentiator
against fojin's unverified "~98%."

## Phase 5 — Tibetan (weeks 12–16)

The long pole. Budget generously.

- 84000 TEI ingest, Toh numbers, Derge folio/side/line anchors
- OpenPecha/Adarsha etext; Tibetan syllable/particle segmentation
- Mahāvyutpatti + 84000 glossary as Skt–Tib–Chi anchors
- BDRC metadata and IIIF image links (catalog only — **no OCR in v1**)

**Exit:** three-way Chinese/Pāli/Tibetan retrieval with correct provenance.

## Phase 6 — Deterministic enrichment (weeks 17–20)

Where the unique features get built.

- **Quotation graph** — suffix-array reuse detection across the full corpus, as a
  standalone Rust binary invoked as a port (see `docs/ELIXIR.md`)
- **Buddhist reading-exception dictionary** — 般若 *bōrě* not *bānruò*, 南無 *námó*,
  plus 呉音 go-on readings for the Japanese material. Generic pinyin libraries get
  these wrong, confidently, in exactly the passages users care about.
- Commentary lemma-and-gloss (科文) parsing → root↔commentary alignment
- **Translator fingerprinting** from parallel Chinese translations (異譯本), and
  **translation divergence scoring** — the same computation, applied to both human
  and machine renderings. Doubles as the corpus-wide difficulty map that prioritizes
  human review effort.
- DILA authority linking; lineage chains; Wikidata Q-IDs

**Exit:** "every text that quotes this passage" and "how Kumārajīva vs. Xuanzang
rendered this term" both work.

## Phase 7 — Research agent + translation (weeks 21–24)

- Multi-hop agentic research mode: plan → survey → cross-reference → sourced report,
  every claim URN-anchored
- Post-generation citation guard wired into all answer paths
- Glossary-pinned translation with a visible term-mapping chain
- **Full-corpus machine translation** into target languages, stored as layers with
  `method: llm` and full reproducibility metadata — never citable as source. Doubles
  as the cross-lingual retrieval fix, since the English layer gets embedded too.
- **On-the-fly translation** for retrieved spans, backed by the
  `translation_candidates` cache (keyed by content hash, kept out of the bake), plus
  the scored promotion pipeline that elevates good candidates into the next bake
- Doctrinal position comparison (replacing persona mode)

## Phase 8 — Web reader (post-v1)

Now cheap, because the API already returns structured spans with URNs and offsets.
**LiveView**, not a separate SPA — a parallel-column reader is server-state-heavy and
mostly read-only, and this avoids maintaining a second API client.

- Parallel-column reader, clickable URN citations, variant-reading apparatus display,
  quotation-graph visualization, IIIF manuscript images beside the text
- Public demo restricted to the CC0/CC-BY subset

## Later — East Asian medical texts

Kanripo/CTEXT ingest; 黃帝內經, 傷寒論, 神農本草經. Japanese Kampo commentary maps onto
the same `composition_origin`/`text_role` axes as Taishō 56–84 with no schema change.

---

## Cost and risk

- **Embedding a full bake is the main recurring cost.** Roughly 250M+ characters of
  Chinese alone. Use `dev.yaml` subsets while iterating; batch full bakes rarely;
  cache by content hash so re-bakes only embed what changed.
- **Biggest technical risk:** cross-lingual retrieval quality between Classical
  Chinese and Pāli/Tibetan. Both reference projects have this problem and one admits
  it. The multi-vector English-gloss trick is the mitigation — validate it in Phase 3
  before committing to the Phase 5 timeline.
- **Biggest scope risk:** Tibetan. See the warning at the top.
- **Biggest correctness risk:** silent normalization corruption (gaiji, CJK
  normalization, lost `<lb/>`). Test suites in Phase 1, not later.
- **Stack risk:** the Elixir MCP library situation is unsettled (`hermes_mcp` →
  `anubis-mcp` fork). Mitigated by MCP being small enough to implement directly in
  Phoenix. Resolve in Phase 0.
- **Stack risk:** BGE-M3 multi-vector may not run under Bumblebee. Mitigated by the
  Python sidecar, which is the assumed default until the Phase 0 spike says otherwise.
