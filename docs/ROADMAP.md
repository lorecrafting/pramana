# Roadmap

> Phase-planning record, not runtime acceptance evidence. For current code contracts use the documentation index; for active work use PLAN and Foundry REPAIR-PLAN. Corpus counts and historical completion claims require their original evidence.

Original phase-planning choices (not a new pilot commitment): open-source self-hosted ·
all four traditions in v1 ·
Postgres+pgvector single DB · MCP + HTTP API first · **Elixir/Phoenix**
(see `docs/ELIXIR.md`).

**Original scope warning.** All four traditions in v1 is the ambitious call.
Chinese, Japanese, and Pāli are clean structured text; **Tibetan is a different kind
of problem** — partial etext coverage and a source (BDRC) that is mostly page images.
The mitigation below is to ingest Tibetan from 84000/OpenPecha only in v1 and treat
BDRC OCR as post-v1. If the schedule slips, Tibetan is the thing to cut back, not
the provenance model or the eval harness.

---

<a id="where-we-are--audited-2026-08-28-phase-table-revised-2026-08-31"></a>

## Current source reconciliation — 2026-09-16, after PR #17

Rechecked at `e5d0bfc2b61018d5b2f202baa4f9841ac7531882`. These are implementation
states, not a new live corpus audit or approval of the proposed pilot. See
[PLAN's current disposition](PLAN.md#current-engineering-disposition--post-17-2026-09-16)
for the active task, human dependencies and unchanged Foundry ownership.

| Phase | Current disposition |
|---|---|
| 0–1: skeleton / Chinese corpus | Implemented; the recorded STATUS snapshot has 16 CBETA collections, not the older 11 below. No corpus acquisition was rerun for this reconciliation. |
| 2: Japanese delta | SAT bulk acquisition remains human-blocked; do not treat an old phase tag or catalogue implementation as delivery of the missing source. |
| 3–5: Pāli, evaluation, Tibetan | Infrastructure implemented; historical coverage/quality limits remain. Explicit eval-baseline acceptance and within-work diagnostics already exist. |
| 6: enrichment | Quotations, reading exceptions, commentary alignment, authority and glossary-based translator comparison exist. That does not establish a general translator/difficulty scoring system or complete relation coverage. |
| 7: report checking / translation | Report checking and batch generation/import already ship. PR #15 fixes evidence classification; PR #17 supplies v2 content identity; the report-release follow-up prevents treating another release's claims as false. Human fidelity review remains open. Full-corpus translation and the proposed query-time cache/promotion service are not complete. |
| 8: reader | Six screens exist, including `/check`. New pilot scope/export and generated-reading policies are separate proposed decisions. |

The old "translation not started", "unstarted phase 7", missing release split and
first-data-for-translator-comparison assumptions are superseded. The multi-corpus
substrate remains; the strategy proposes one selected scope per pilot, not deleting
other corpora or silently approving an all-traditions launch. Its operator gates remain.

**Release boundary:** `release_id` fingerprints recorded source identity and derived
translation/vector content. Report verification compares supplied identities and returned
receipts; it does not freeze code/defaults, retain historical rows or restore snapshots.
PR #16's dependency advisory fixes and both Hex audit commands are also already integrated.
PR #19 subsequently completed the per-page asynchronous `/check` lifecycle. The
[post-#19 argument-validation follow-up](PLAN.md#replay-argument-validation--post-19-2026-09-16)
rejects unsupported or wrongly typed replay arguments before tool invocation; it does not
expand release identity, retrieval policy, or public-hosting acceptance.

The phase sections below retain their original schedule and historical evidence. They are
not an independent executable queue; read PLAN and current code before reviving an item.

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

Retained enrichment plan. The current reconciliation above supersedes the old
"three of five"/"nothing written" labels; distinguish implemented mechanisms from
population coverage and proposed scoring systems.
- ✅ **Quotation graph** — 141,073 verbatim reuses across 1,301 works
- ✅ **Reading exceptions** — 9,543 over a 44,348-character base
- ✅ **Commentary lemma-and-gloss (科文) parsing** — deterministic, no model. The live
  counts are in `docs/STATUS.md`'s generated block and in `mix pramana.doctor`; this line
  carried them and said 27,254 lemmas over 43 pairs long after there were 72,120 over 76.
  `docs/COMMENTARY.md`.
- ▸ **UNBLOCKED 2026-09-02, by acquisition rather than by code.** The blocker below was a
  genre-matched 異譯本 pair. Karashima's glossaries of **Dharmarakṣa's and Kumārajīva's
  Lotus** are exactly that — the same sūtra, two translators, glossed term by term with
  Taishō citations now resolved to URNs, including **4,345 places where one translator's
  term has no counterpart in the other**. That is divergence evidence at term granularity
  from a scholar, which is stronger than anything `compare_hands/3` can derive from a
  string comparison. `docs/SOURCES.md`, DILA Glossaries.
- ◐ **Translator fingerprinting** from parallel Chinese translations (異譯本) —
  `Pramana.Translators`. Works per work-pair (求那跋陀羅 against the anonymous T0100 returns
  入處, 覺分, 緣生, 道跡, 法律 — his technical vocabulary). `compare_hands/3` keys on DILA
  authority ids so a translator is one identity across spellings, and is **ahead of the
  data**: six named pairs have parallel works and the richest, T0099 against T0210, is prose
  sūtra against verse, so it measures genre rather than hand. That was the original blocker; the acquired Karashima pair and glossary comparison
  supersede it. General translator fingerprinting is still distinct from that implemented
  term comparison. And
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
- Historical multi-hop research proposal: caller-owned agents may plan, survey and
  cross-reference through the read-only tools; this is not a new server-side agent
- Post-generation citation guard wired into all answer paths
- Batch glossary-pinned translation is implemented; the later fidelity experiments in
  PLAN supersede its earlier "not started" status
- **Full-corpus machine translation** into target languages, stored as layers with
  `method: llm` and full reproducibility metadata — never citable as source. Doubles
  as the cross-lingual retrieval fix, since the English layer gets embedded too.
- **Proposed, not implemented: on-the-fly translation** for retrieved spans, backed by the
  `translation_candidates` cache (keyed by content hash, kept out of the bake), plus
  the scored promotion pipeline that elevates good candidates into the next bake
- Doctrinal position comparison (replacing persona mode)

## Phase 8 — Web reader ✅ SHIPPED EARLY (was post-v1)

Now cheap, because the API already returns structured spans with URNs and offsets.
**LiveView**, not a separate SPA — a parallel-column reader is server-state-heavy and
mostly read-only, and this avoids maintaining a second API client.

- ✅ Six screens — search, inventory, survey, passage, work and report check. Clickable
  URN citations, variant-reading apparatus, commentary on the line, links out to the publishing edition.
  `docs/READER.md`.
- ✗ Parallel-column reader, quotation-graph visualisation, IIIF images beside the text
- ◐ **Public demo restricted to the CC0/CC-BY subset** — `mix pramana.public.bake` builds
  and verifies the artefact (13,017 texts, 0 CBETA); nothing is deployed. `docs/DEPLOY.md`.

## The lexicon layer — added to the roadmap after it shipped, 2026-09-02

Not in the original eight phases, which is worth saying plainly: this roadmap planned
texts, retrieval, enrichment and a reader, and **never planned a dictionary**. `docs/PLAN.md`
L1 called that "the largest functional gap in this project" and it came from reading the
competitive landscape rather than from this document.

What shipped: 33,267 entries from five DILA glossaries, and 29,890 of their Taishō
citations resolved to URNs — 25,504 to a line held, 4,345 attested absences.
`mix pramana.glossary.dila`, `mix pramana.glossary.anchor`, `docs/SOURCES.md`.

**The lesson for this file is that its gaps are not visible from inside it.** Eight phases
covering acquisition through reader looked complete, and a scholar reading Classical
Chinese without a lexicon is working one-handed. Read it against what a user is trying to
do, not against itself.

## Later — East Asian medical texts

Kanripo/CTEXT ingest; 黃帝內經, 傷寒論, 神農本草經. Japanese Kampo commentary maps onto
the same `composition_origin`/`text_role` axes as Taishō 56–84 with no schema change.

---

## Cost and risk

- **Embedding a full bake is the main recurring cost.** Roughly 250M+ characters of
  Chinese alone. Use `dev.yaml` subsets while iterating; batch full bakes rarely;
  cache by content hash so re-bakes only embed what changed.
- **Historical retrieval-risk diagnosis (2026-08-31).** The later isolated experiments
  and translation-fidelity findings in PLAN E1 supersede this diagnosis; the figures
  below retain their original scope, not the current outcome. Cross-lingual retrieval into
  Classical Chinese was named here as the biggest
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
