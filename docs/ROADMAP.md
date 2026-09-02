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

## Where we are — audited 2026-08-28, phase table revised 2026-08-31

| phase | | |
|---|---|---|
| **0** Skeleton | ✅ complete, tagged `phase-0` | |
| **1** Chinese corpus | ✅ complete, tagged `phase-1` | and long since exceeded — 11 CBETA collections, not one |
| **2** Japanese delta | ⚠️ **the only unfinished phase behind us** | #15, #16 done. #14 (SAT, Taishō 56–84) blocked on an email a person must send. Gate deliberately **not tagged** while a known gap stands |
| **3** Pāli + parallels | ✅ complete | |
| **4** Eval harness | ✅ complete, tagged `phase-4` | 1,472 cases, published, and the gate ratchets on them |
| **5** Tibetan | ✅ complete | Kangyur and Tengyur both ingested; BDRC OCR correctly still out of scope |
| **6** Deterministic enrichment | ◐ **half** | quotation graph ✅, reading exceptions ✅, 科文 alignment ✅, authority linking ✅ (2,374 works, plus places, lineage chains and Wikidata ids). Translator fingerprinting is written and **ahead of its data** — it needs a genre-matched 異譯本 pair the corpus does not hold |
| **7** Research agent + translation | ◐ **report verification shipped**; translation not started, and it is now the critical path | `verify_report` byte-compares every citation in a document and re-runs the retrievals its figures rest on (`docs/PLAN.md` § H). Glossary-pinned generation is one of only two routes to an English layer over the Chinese canon — see the risk section below and § E1 |
| **8** Web reader | ✅ **shipped early** | five screens, and the public artefact builds |

**The shape of the remaining work is not what this roadmap assumed.** It planned eight
sequential phases; what is actually left is one blocked item (SAT), one half-finished phase
(6), one unstarted phase (7), and a long tail of coverage. Phase 8 shipped out of order
because the API made it cheap, exactly as predicted.

**Read `docs/PLAN.md` for what to do next.** This file is the plan as it was drawn; the plan
as it is now lives there, with evidence.

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

**Spikes, all resolved** (see `docs/HISTORY.md` for the evidence):
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

- SAT ingest **if it ever arrives** — send the request once and sequence nothing behind
  it (`docs/SOURCES.md`). The licence is settled (CC BY-SA 4.0); only the bulk copy is
  missing. If it never comes, the announced gap is an acceptable end state.
- **Instead, and first: CBETA's other collections.** ▸ **DONE, ten of them.** Written when
  the corpus held witness `T` and nothing else. X, J, N and the seven alternative editions
  (K, A, P, L, U, S, M) are all ingested — 4,081 works across 11 of CBETA's 26 collections.
  `Coverage.cbeta/0` reports the 15 still absent, by name, and `Coverage.taisho/0` was
  revisited exactly as this bullet asked.
- When SAT does arrive: dedupe vols 1–55/85 against CBETA by work ID, keeping both as
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

## Phase 6 — Deterministic enrichment (weeks 17–20) — ◐ HALF DONE

Where the unique features get built. Three of five shipped; the two that have not are
listed as **not started** rather than in progress, because nothing has been written.

- **Quotation graph** — suffix-array reuse detection across the full corpus, as a
  standalone Rust binary invoked as a port (see `docs/ELIXIR.md`)
- **Buddhist reading-exception dictionary** — 般若 *bōrě* not *bānruò*, 南無 *námó*,
  plus 呉音 go-on readings for the Japanese material. Generic pinyin libraries get
  these wrong, confidently, in exactly the passages users care about.
- ✅ **Quotation graph** — 141,073 verbatim reuses across 1,301 works
- ✅ **Reading exceptions** — 9,543 over a 44,348-character base
- ✅ **Commentary lemma-and-gloss (科文) parsing** — 27,254 lemmas over 43 work pairs,
  attaching commentary to 20,954 root lines, deterministically. `docs/COMMENTARY.md`.
- ◐ **Translator fingerprinting** from parallel Chinese translations (異譯本) —
  `Pramana.Translators`. Works per work-pair (求那跋陀羅 against the anonymous T0100 returns
  入處, 覺分, 緣生, 道跡, 法律 — his technical vocabulary). `compare_hands/3` keys on DILA
  authority ids so a translator is one identity across spellings, and is **ahead of the
  data**: six named pairs have parallel works and the richest, T0099 against T0210, is prose
  sūtra against verse, so it measures genre rather than hand. Needs a genre-matched pair the
  corpus does not yet hold. And
  **translation divergence scoring** — the same computation, applied to both human
  and machine renderings. Doubles as the corpus-wide difficulty map that prioritizes
  human review effort.
- ◐ **DILA authority linking** — `Pramana.Authority`, `mix pramana.authority.link`.
  **1,998 of 3,932 works (50.8%) carry a DILA person id**, 736 distinct people; Amoghavajra
  170 works, Dharmarakṣa 93, Yijing 47, Guṇabhadra 28. Refusal is the common outcome and is
  correct — half the bylines name someone DILA does not record under that spelling, name
  several people at once, or carry a dynasty no namesake shares.
- ✅ **Lineage chains and Wikidata Q-IDs** — shipped 2026-08-28, along with place authority
  (59,335 places, historical region as well as modern administrative path). The 50.8% figure
  above is **of 2026-08-27**; `docs/STATUS.md` carries the current one. Run
  `mix pramana.authority.link` rather than quoting either.

**Exit:** "every text that quotes this passage" and "how Kumārajīva vs. Xuanzang
rendered this term" both work.

## Phase 7 — Research agent + translation (weeks 21–24)

- **Report verification, not a research agent.** The agent is whichever model the caller
  brings — invariant #7 keeps this surface read-only and `CLAUDE.md` makes the model
  swappable, so an agent inside the server would contradict both. What ships is the thing
  that makes any agent's report checkable: quotes through `Guard`, and **frequency and
  absence claims re-executed from the `replay` record the tool response carried**. A
  citation guard cannot reach "appears 36,775 times" or "no Japanese text says this", and
  those are the claims that carry a report. Designed in `docs/PLAN.md` § H.
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

## Phase 8 — Web reader ✅ SHIPPED EARLY (was post-v1)

Now cheap, because the API already returns structured spans with URNs and offsets.
**LiveView**, not a separate SPA — a parallel-column reader is server-state-heavy and
mostly read-only, and this avoids maintaining a second API client.

- ✅ Five screens — search, inventory, survey, passage, work. Clickable URN citations,
  variant-reading apparatus, commentary on the line, links out to the publishing edition.
  `docs/READER.md`.
- ✗ Parallel-column reader, quotation-graph visualisation, IIIF images beside the text
- ◐ **Public demo restricted to the CC0/CC-BY subset** — `mix pramana.public.bake` builds
  and verifies the artefact (13,017 texts, 0 CBETA); nothing is deployed. `docs/DEPLOY.md`.

## Later — East Asian medical texts

Kanripo/CTEXT ingest; 黃帝內經, 傷寒論, 神農本草經. Japanese Kampo commentary maps onto
the same `composition_origin`/`text_role` axes as Taishō 56–84 with no schema change.

---

## Cost and risk

- **Embedding a full bake is the main recurring cost.** Roughly 250M+ characters of
  Chinese alone. Use `dev.yaml` subsets while iterating; batch full bakes rarely;
  cache by content hash so re-bakes only embed what changed.
- **Biggest technical risk: CONFIRMED, and now understood as coverage rather than
  retrieval.** Cross-lingual retrieval into Classical Chinese was named here as the biggest
  technical risk, with the multi-vector English-gloss trick as the mitigation.
  `topical/chinese` is **0% of 12** and has never been anything else. The gloss layer works
  where it exists — English→Pāli is 75%.

  **The diagnosis changed twice.** First on 2026-08-30: `mix pramana.recall --renderings`
  scores an English query reaching Pāli and Tibetan **source** text at 93.8% work-level, so
  BGE-M3 crosses the language barrier perfectly well *when a translation exists to anchor
  on*. The problem was never the embedder — it was that no English layer existed over the
  Chinese canon.

  Then on 2026-08-31, when one did. `mix pramana.sc.chinese` anchored **3,354 CC0 English
  renderings** to Taishō lines, and `topical/chinese` **did not move**, because those cases
  search the whole corpus and 191 English vectors over the Chinese meet 55,135 over the
  Pāli. So the axis is a **coverage** measurement wearing a retrieval measurement's
  clothes, and it will stay at 0 until the Chinese layer is large enough to compete.
  `docs/PLAN.md` § E1.

  Three routes out have now been measured, all recorded in `docs/PLAN.md`: 84000's glossary
  recovers 2 of 12 gold terms, a deterministic English→Pāli→Chinese walk through the
  curated parallels scores **1 of 12** (both § Rejected), and a real English layer over 54
  sūtras scores **0 of 12** because it is 1.3% of the Āgamas and 0.03% of CBETA's segments.
  The caution in PLAN item F stands: that row is 12 cases, cannot grow, and one case is 8.3
  points. **Judge this axis by "answered from any tradition" — 81.8% — rather than by the
  row.**
- **Biggest scope risk:** Tibetan. See the warning at the top.
- **Biggest correctness risk:** silent normalization corruption (gaiji, CJK
  normalization, lost `<lb/>`). Test suites in Phase 1, not later.
- ~~**Stack risk:** the Elixir MCP library situation is unsettled.~~ **Resolved in Phase 0**:
  `anubis_mcp`, the maintained fork. Fourteen tools ship on it.
- ~~**Stack risk:** BGE-M3 multi-vector may not run under Bumblebee.~~ **Resolved**: the
  Python sidecar is the path, it does tensor math only, and a full embedding run is 34
  minutes and ~$0.45 on a rented L4. `docs/GPU_RUNBOOK.md`.
- **Risk the roadmap did not name, and the one that has actually cost the most time:**
  every measurement in this project has been wrong at least once, and always in the
  flattering direction. A LoRA that improved every proxy and scored 0%; a threshold
  calibrated against a 40-pair tail; a gold set nearly built from the retriever's own
  output; four different greps that matched a substring. `docs/PROXIES.md` and `docs/RULES.md`
  exist because of this, and `docs/CHECKS.md` §2 is the only check that catches the class.
