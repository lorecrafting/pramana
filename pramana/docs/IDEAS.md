# Feature Ideas

> Idea backlog, not an implementation inventory or approved execution queue. Check code and the owning plan before treating an idea as shipped or scheduled.

A backlog, not a plan. Nothing here is committed; `docs/ROADMAP.md` is the committed
scope. Marked **★** where the value-to-effort ratio is unusually good, mostly because
the feature falls out of infrastructure we're building anyway.

The recurring theme: because every span is URN-anchored, byte-verifiable, and
provenance-tagged, a surprising number of classic philology tools become nearly free.
Most of the ideas below are *harvesting* that, not new construction.

---

## 0. The commentary is the tradition's own answer, and nothing routes a model to it

**★★ Raised 2026-09-02 and not yet committed — this may belong in `CLAUDE.md` as a fourth
guard rather than here.**

The project has two rules about what may stand for what, and both run the same direction:
**invariant #8**, a machine translation is never citable as source, and
`docs/COMMENTARY.md`'s, a commentary is not scripture. Both protect the root text from
things below it.

**The missing one runs the other way: an interpretation the model supplies must not stand
where the tradition's own explanation exists.** Positively — where the canon glossed a
passage, the reader is told, and told whose voice it is.

Why it matters more here than in ordinary retrieval: a model's default gloss on `空` is
sediment from popular books, forum posts and translations of translations. Kuiji's gloss
is a different kind of object — attributable, dated, located, part of the tradition's own
self-understanding. Conflating them is what a project named *pramāṇa* exists to prevent;
the whole tradition is an argument about which means of knowing are valid.

**The concrete gap, and it is rule 60's shape.** `get_commentaries` exists,
`Pramana.Commentary` aligns a commentary line to the root line it explains, and
**`get_passage` says nothing about either**. A model landing on a dense line receives the
words, no signal that Vasubandhu explained *that* line, and improvises. The capability is
built and unreachable at the moment of use.

Four moves, cheapest first:

1. **`get_passage` reports availability** — `commentary: %{count: 3, urns: [...]}`. Small,
   and the only one that changes behaviour: a model told three commentaries explain this
   line will ask for them.
2. **Structural, not prompted.** The response already carries `citable_as_source: false`
   on a rendering — invariant #8 visible in the response shape. A canonical commentary
   carries author, date and address; a model's gloss carries none, and that absence is the
   signal. Invariant #4's method.
3. **An "unconsulted" check in the guard.** `Pramana.Guard` byte-compares quotes and
   cannot check meaning — but it *can* check whether an answer explaining a passage cited
   the commentary that exists for it. Presence is deterministic where correctness is not,
   and it is the same move as the citation guard: not "is this right" but "did you look".
4. **Label rather than blend.** `search(include_commentary:)` exists; commentary hits
   should arrive marked as explanation, not mixed into one ranked list.

**The honest limit.** 24 commentaries are aligned and 89 pairs are alignable, so this
would often answer "nothing glosses this line". That is fine and better than silence: *the
tradition did not gloss this passage, here is my reading, labelled as mine* is a true
answer. The failure to prevent is the model's reading arriving **unlabelled** where
Kuiji's was available.

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


---

## From the 2026-08-30 landscape review

Everything below came from actually opening the competing projects rather than asking a
model what exists — which mattered, because the assistant that prompted this review
invented two of them. See `docs/COMPETITIVE.md` § "Projects that do not exist".

### ★★ A shared benchmark for citation faithfulness

**The field cannot compare itself.** fojin reports `served_trustworthy_rate ≈ 98%`; this
project reports 100% over 1,891 quotation pairs and 92.3% over 1,472 gold cases. Different
data, different definitions, each self-scored. Nobody can tell which system is more
trustworthy, so nobody can improve against anyone.

A published, versioned, **CC0** adversarial set any system could run:

- quotations altered by one character
- quotations that exist, but in a different work
- material genuinely absent from every canon
- provenance traps — a Japanese-composed text presented as an Indian sūtra
- **claims whose figures require re-computation**, not quote-checking ("appears 36,775
  times across 1,904 works")

This project is unusually placed to publish it: `evals/` already carries adversarial and
absence cases, and `docs/PROXIES.md` is a record of every cheap proxy that lied — the
rarest artifact in this field, because nobody publishes their failed measurements.

It costs nothing competitively. We would score well on it, and a field with one honest
yardstick beats a field of self-reported percentages.

### ★ Publish the provenance model as an open dataset

`composition_origin`, `text_role`, the 部 division table, the DILA authority links.
**No other project models any of it** — fojin's README does not distinguish an Indic
translation from a Chinese composition from a Japanese one. Released CC BY-SA, it becomes
shared vocabulary for *who composed this, where, in what genre*.

### ★ Contribute the division correction upstream

452 of 510 works in T2185–T2700 carried the wrong 部 here, **Nichiren's 立正安國論 among
them**, filed as sub-commentary. Found 2026-08-30 from SAT's own IIIF metadata. That is a
real philological correction and it belongs with SAT and CBETA, not only in this repo.

### Answer receipts

Every response already carries `bake_id`. Make it portable: a JSON receipt a scholar
attaches to a paper, that anyone can replay against that exact corpus state and get the
same answer. `verify_report`'s replay machinery is most of it.

### Corpus time-travel

*"As of bake X, this passage read Y."* Scholarship needs a stable reference and corpora
move underneath it. Content-addressing makes this nearly free here and impossible for a
hosted product that overwrites its index.

### Refusal quality as the headline metric

We measure it — 6 of 10 unanswerable questions caught, **0 of 46 answerable ones lost**.
Publishing *that* rather than recall@10 would reframe what the field competes on, from
"how much can you find" to "how reliably do you decline".

### ★ The claim checker

Give it a sentence — *"the Buddha said craving is the origin of suffering"* — and get every
canonical attestation across four canons **with provenance**, plus where it is **not**
attested. `survey_corpus` + parallels + `Coverage` composed. The absence half is the part
no other system can express, and it is what a translator or a practitioner actually wants.

### Entity graph and geo-map

fojin has 110K entities, 28K relations, 22K teacher-student lineage chains on a Deck.GL
map. We have DILA people and 59,335 places and do nothing visual with them. Not a
differentiator — they are ahead — but the data is already here.


---

## Product direction — "check anything", not "ask anything"

The obvious product is a box you ask about Buddhism that answers with citations. **fojin
already ships it** — RAG, clickable 【《經》卷N】 citations, three deterministic answer
guards, ~98% trustworthy at temperature 0. Building a second one competes on answer quality
and UI polish against a team with a shipping cadence and a Discord, which is not a race a
provenance project wins.

**The thesis says the answer is not the product; the warrant is.** *Pramāṇa* means "valid
means of knowledge". The differentiator was never a better explanation — it is that every
sentence can be checked, and that the system says when it cannot check one.

So: the same idea turned one degree. **One box you paste INTO.** A paragraph from a book, a
teacher's talk, a translation draft, or another AI's answer, and it returns

- every quotation byte-verified, with the five diagnoses the guard already distinguishes —
  editorial punctuation, orthographic variant, a quote running into the next line, real text
  at the wrong address, and the one case that is a fabrication
- **every figure re-computed**, not trusted — "appears 36,775 times across 1,904 works" is a
  claim no citation guard can reach and `verify_report` re-runs it
- provenance per citation: a Kamakura-era Japanese composition is not an Indian sūtra
- **what it cannot check, said plainly** — "this cites Taishō 62, which this corpus does not
  hold"

**Nobody offers this.** fojin's `/api/verify/quote` checks one quotation; this checks a
document including its arithmetic. And the demand exists already: people are asking general
assistants about the Dhamma and getting confident fabrications. A place to paste one and see
what survives needs no trust in *our* model at all — which is the only honest way to sell a
system whose founding claim is that the model is not trusted.

Tracked as **L5** in `docs/PLAN.md`.

### If a Q&A surface is built anyway, lead with refusal

Not the answer — the decline. This project measures it: **6 of 10 unanswerable questions
caught, 0 of 46 answerable ones lost**, and a hard threshold measured and *refused* because
it cost 10% of answerable queries to gain one absence case.

"I do not know, and here is why: that material is in Taishō 56–84, which this bake does not
hold" is a more trustworthy interface than a 98% badge, and it is the coverage doctrine made
visible rather than buried in a caveat field. **No other project in this space leads with
what it cannot do.** That is the opening.

### On fojin's UI, and the lesson to take rather than the criticism to make

15 master personas, a geo map, a timeline, a category treemap, read-aloud, force-directed
knowledge-graph visualisation — and the thing most people came for is several clicks in.
Breadth is what an aggregator optimises for and it is a reasonable choice for what they are
building.

The lesson is not "their UI is scattered". It is that **a project with one guarantee should
ship one screen that makes the guarantee visible**, and that this project has five reader
screens and no surface for the capability that is actually unique to it.
