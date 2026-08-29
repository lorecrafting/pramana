# Feature Ideas

A backlog, not a plan. Nothing here is committed; `docs/ROADMAP.md` is the committed
scope. Marked **★** where the value-to-effort ratio is unusually good, mostly because
the feature falls out of infrastructure we're building anyway.

The recurring theme: because every span is URN-anchored, byte-verifiable, and
provenance-tagged, a surprising number of classic philology tools become nearly free.
Most of the ideas below are *harvesting* that, not new construction.

---

## 1. Scholar workflow — where the real users are

**★ `pramana verify-bibliography <file>`** — the killer app. Point it at a `.md`,
`.tex`, or `.docx` and it checks **every citation in a dissertation or paper** against
the corpus: does the reference resolve, does the quoted text match byte-for-byte, is
the edition right. This is `Pramana.Guard.check_output/1` (already planned for Phase 0)
aimed at human writing instead of model output. Nobody offers this, and every graduate
student in Buddhist studies needs it.

**★ "Find the source of this quote"** — paste a passage, get its location(s). Powered
by the Phase 6 quotation graph with no extra machinery. Solves a genuinely painful,
constant problem: tracking down an unattributed quotation in a secondary source.

**★ BibTeX / CSL export and a Zotero connector** — `pramana cite <urn> --style chicago`
emits a correct scholarly citation. Cheap to build, and it meets scholars inside the
tools they already use.

**★ Pandoc filter + Obsidian plugin** — write `[[pramana:cbeta.T:T0262@p0037a13]]` in
notes or a manuscript; expand at compile time into full citation plus quoted text.
Because URNs are stable and resolvable, this is mostly a lookup call.

**KWIC concordance** — keyword-in-context: every occurrence of a term with surrounding
context, sortable by left/right neighbor. The oldest tool in corpus philology, absent
from every AI-era Buddhist platform, and trivially derived from what we already store.

**Collocation analysis** — what co-occurs with 空 in Madhyamaka versus Yogācāra
sources. One SQL query away once provenance axes are populated.

**Export**: TEI, JSON, CSV, and plain text with apparatus, so people can take data out.
An open corpus tool that traps its data isn't open.

---

## 2. Corpus science — research nobody has run

**★ Formulaic phrase detection** — Buddhist texts are extraordinarily formulaic
(repeated pericopes, stock descriptions). Detecting and clustering formulas lets you
collapse near-duplicate search results *and* study formula variation across
translators. Falls out of the quotation graph's n-gram index.

**★ Mātṛkā extraction (numbered doctrinal lists)** — the canon is full of enumerated
sets: four noble truths, five aggregates, twelve links, thirty-seven factors. Extract
them structurally into a browsable index. This is literally what the Abhidharma
mātṛkā tradition was, rebuilt by machine — a pleasing and genuinely useful result.

**★ Stylometric attribution checking** — train on securely-attributed translator
corpora, then flag texts whose style doesn't match their attributed translator. This
directly serves the `attribution_confidence` column, which otherwise has to be filled
in by hand. Much of the canon is pseudepigraphic; this is real, publishable research.

**Citation-network centrality** — which passages does the tradition quote most? An
automatically-derived canon-within-the-canon. Straight out of the quotation graph.

**Stemma inference** — infer manuscript relationships from patterns of shared variant
readings. Classical textual criticism, automatable now that we're keeping the `<app>`
apparatus that everyone else discards.

**Vocabulary-based dating** — estimate composition dates for undated texts from
lexical profile, calibrated against securely-dated ones.

**Diachronic term drift** — how 空 / 道 / 法 shift from Han-era translations through
Kumārajīva to Xuanzang. Already flagged in `COMPETITIVE.md`; worth restating as a
first-class research product, not a demo.

---

## 3. Infrastructure

**★ Bakes as distributable artifacts** — `pramana bake pull cbeta@2026-08`. Content-
addressed, hash-verified, resumable. A package manager for corpora. Since the bake is
already `sha256(lockfile + pipeline_version + config)`, this is packaging, not design.

**★ Corpus changelog / time-travel** — CBETA revises its texts. When a citation's text
changes between bakes, scholars need to know. `pramana diff-bake A B` showing which
segments changed is a real scholarly service and a natural consequence of immutable
content-addressed bakes.

**Bake attestation** — sign bakes (sigstore/cosign) so a `bake_id` in a published paper
is cryptographically verifiable. Cheap, and it fits the project's entire thesis.

**★ Lite offline bake** — a SQLite + local-vector export for offline use, as
`tripitaka-mcp` does. Matters more than it sounds: many actual users are in monasteries
and retreat centers with poor connectivity.

**Incremental bakes** — content-hash keying so a re-bake re-embeds only what changed.
This is already an invariant for Oban jobs; the CLI surface makes it visible.

**Backup story** — worth stating explicitly because it's unusually good: a bake is
reproducible from `sources.lock.json`, so the *lockfile is the backup*. No multi-hundred-
gigabyte dumps.

**Retrieval explain endpoint** — show dense/sparse/lexical contributions and RRF
scoring for a query. Essential for debugging recall, and it makes the system legible
rather than magical.

**Mini-bake in CI** — every PR bakes a fixed ~50-work subset and runs evals. Catches
normalization regressions at PR time, when they're cheap.

---

## 4. CLI

**★ `pramana grep`** — corpus-wide lexical/regex search with provenance filters, from
the terminal, no browser. The tool you'd actually reach for twenty times a day.

**`pramana repl`** — an IEx session with corpus helpers preloaded.

**`pramana lint`** — corpus health: unmapped gaiji, empty segments, unbalanced
brackets, suspicious codepoints, orphaned anchors. Run it in CI.

**`pramana diff <urn> <urn>`** — aligned, colorized diff of two witnesses or two
translations in the terminal.

**`pramana watch`** — re-bake on manifest change while developing a local source.

Plus the unglamorous things that make a CLI feel finished: shell completion, `--json`
on everything, sensible exit codes.

---

## 5. Reading and practice

**★ TTS with correct Buddhist readings** — falls directly out of the Phase 6
reading-exception dictionary. Every existing TTS says *bānruò* for 般若. Getting this
right is unique, and audio is how a great many people actually engage these texts.

**Recitation mode** — text, readings, and audio aligned for chanting.

**Vertical CJK text rendering and ruby/furigana** in the reader. Small touches, but
they signal to the people who care most that the project takes the texts seriously.

**Personal annotation layer** — user notes anchored to URNs, portable and exportable.
Natural given that everything is already anchored, and it's the feature that makes
people stay.

**Anki / spaced-repetition export** — term decks with real citations attached.

**Print/PDF export** with properly formatted critical apparatus.

---

## 6. Community

**★ Correction submissions as a layer** — users flag a bad segmentation, reading, or
alignment; corrections are stored as a layer *over* the immutable bake and never as an
edit to `raw/`. Preserves reproducibility while letting the corpus improve.

**★ Divergence-driven review queue** — surface the ~2% of passages where translations
diverge most and route them to human reviewers. This turns the Phase 6 divergence score
into a crowdsourcing engine and is what makes human-reviewed translation at canon scale
actually achievable. Strategically the highest-leverage community feature.

**Contributor credit tracking** — reviewers and correctors are named in the data. In a
scholarly community, attribution *is* the compensation.

**Shared local-source registry** — a public index of manifests and hashes (never the
texts), so people can share ingest recipes for licensed material they each own.

---

## 7. Agent and MCP surface

**MCP resources and prompts, not just tools** — expose curated reading lists and
research recipes as MCP prompts.

**MCP Apps inline viewer** — side-by-side source/translation rendering inside the chat
client, as `tripitaka-mcp` does. Worth copying.

**★ "Show your work" mode** — every retrieval the agent ran, replayable and inspectable.
This is what makes an AI answer *auditable* rather than merely confident, and it's the
natural extension of the project's thesis into the agent layer. `docs/AGENT_MODELS.md`
argues it should be done **before** any of the larger bets on that page, because it needs no
change to how a model reads the corpus.

**Answer caching keyed by `(question_hash, bake_id)`** — reproducible answers, which is
a genuinely unusual property for an LLM system and worth advertising.

**Model routing** — cheap model for triage and query planning, strong model for
synthesis. Meaningful cost control once traffic exists.

---

## Top ten, if forced to choose

Ordered by value-to-effort, given what the roadmap already builds:

1. `pramana verify-bibliography` — the scholar killer app
2. Find-the-source-of-this-quote
3. `pramana grep` + KWIC concordance
4. BibTeX/CSL export + Pandoc/Obsidian integration
5. Divergence-driven human review queue
6. Bakes as pullable, content-addressed artifacts
7. Corpus changelog / bake diffing
8. Mātṛkā (numbered-list) extraction
9. TTS with correct Buddhist readings
10. "Show your work" replayable retrieval traces

Common thread: **1–4 and 7 are largely packaging of infrastructure the roadmap already
requires.** They're where the leverage is. The genuinely new construction is 5, 8, 9,
and 10 — and each of those is a differentiator no competitor is positioned to copy
quickly, because each depends on the provenance and verification substrate rather than
on model quality.
