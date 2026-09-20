# Project history — chapter 9

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

### The Derge ingest (#21) — the edition is the unit, and the header is not the book

**The Kangyur is in: 1,195 works, 461,302 lines, 12,109 texts and 5,647,069 segments
across three traditions.** `mix pramana.derge.ingest` walks the 103 volumes in printed
order in 4m35s; `mix pramana.verify --source derge` re-derives every one of the 1,195
texts from `raw/` byte-identically in 75s. URNs read `pramana:derge.D:toh8@14.1b.1`.

**The numbers in the section above were wrong, and this section's are checked.** The
normalizer's own report said 1,196 works and 461,414 lines. Ingest says 1,195 and
461,302, and the difference is not a regression — it is 102 lines of Esukhia's
distributor note (see below) plus one work that only ever existed as a double count.

Four things this stage settled:

- **A volume is not the unit of loading, and the loader will not tell you.**
  `Loader.load/2` is idempotent by replacing a text's segments, so a work loaded once per
  volume keeps its **last** volume and silently discards the rest — twelve volumes of
  Vinaya, in a text that reports a plausible length and resolves every URN it contains.
  Works are assembled across volumes in `Derge.Edition` and loaded once. 75 of the 1,195
  span more than one volume; Toh 8 spans thirteen.
- **`<teiHeader>` was being read as scripture.** Every volume's `<publicationStmt>`
  carries a 416-byte distributor note, and the normalizer buffered all character data
  regardless of where it sat. In a volume that opens with a work already running — 102 of
  the 103 — that note flushed into the work as its first line, with a URN that resolves.
  Nothing errored: it is text, in a text, with an anchor. The only tell was the anchor
  itself, `2..`, because no folio had been read when it was emitted.
- **What found it was a count that shares none of the parser's assumptions.** Not line
  counts — those agreed. `Derge.Audit` adds up the non-whitespace bytes of character data
  inside `<text>` and knows nothing about folios, markers or works: **290,863,399 in the
  edition against 290,863,330 in the bake, and the 69-byte difference is volume 1's title
  page**, which belongs to no Tōhoku number and is dropped on purpose. That reconciliation
  now runs in `mix pramana.integrity`, per volume, and the rule it enforces is that **only
  the first volume may drop anything** — a later volume dropping its preamble is the exact
  shape of the 146,962-line bug.
- **Four leaves in the edition are inserted rather than numbered** and are labelled
  `33xa`, `93xb`, `354xa`, `355xb`. 65,975 folios take the regular form and exactly 8 do
  not, which is the kind of thing worth counting before writing the pattern that parses it.

Provenance is `indic` / `root` / **`probable`**, not `certain`: the Kangyur's claim to
Indic origin is a claim about where the collection places a text, and it is wrong for a
few (the *mdzangs blun* was assembled from Chinese). Per-work correction is what the 84000
catalogue join is for. The dkar chag is loaded as what it is — `tibetan` / `catalogue` /
`certain`. Titles are absent by design: this etext titles volumes, not works, and 84000
publishes a title for every Toh number in four languages.

### The 84000 join (#21) — 30,653 English folios anchored to Tibetan lines

84000's published Kangyur translations are in, keyed onto the Derge text they translate:
**30,653 renderings across 472 works**, and **478 of the 1,195 Tibetan works now have
titles** in English, Sanskrit, Tibetan and Wylie. An anchor reads
`pramana:derge.D:toh113@51.100a.1-51.100a.7#tr:en/84000`, and it resolves: the English
"His subtle body is adorned by the thirty-two signs" comes back beside
`སུམ་ཅུ་རྩ་གཉིས་མཚན་རྣམས་ཀྱིས། །ཕྲ་བའི་སྐུ་ནི་ལེགས་པར་བརྒྱན།`, line for line.

**The anchor is a range because the two editions cite at different grains.** Ours are
lines, 84000's are folios, so a folio's English renders about seven of our lines and is
stored against the range of exactly those. Anchoring it to the folio's first line would
have been a smaller change and a false claim.

Four things this cost, all of them the same lesson — *the file describes its own location
three times and the three disagree*:

- **`<biblScope>` is prose, `<location>` is arithmetic, and the folio reference in the
  body is the folio.** For Toh 883 the prose says volume 100, the page arithmetic says
  folio 122a, and the reference says 123a. Our Derge etext has it at volume 101, folio
  123a — so the volume comes from `<location>` and the folio from the reference, and
  nothing is computed. Only checking all three against the Tibetan we already had could
  have told us that.
- **A partial match is the dangerous case, not a total mismatch.** 84000 numbers Toh 11's
  folios from the work's own beginning in its second volume — `F.92.b` where the Degé
  prints `1a` — and **428 of those 610 numbers exist in that volume of that work**. They
  anchor. They resolve, they byte-verify, and they attach English to a passage it does
  not translate. So a volume's spans are accepted or refused **together**, on a 95%
  threshold: 490 of the 503 volume-groups land completely, and the rest divide sharply
  into 99.4%/99.6% (84000 citing one folio past the end of ours) and 70%/67%/0%.
- **One translation can render two places in the canon at once.** A dhāraṇī printed twice
  in the Kangyur is translated once, with both editions' folio boundaries marked in one
  interleaved flow — `F.1.b`, `F.123.a`, `F.2.a`, `F.123.b`. Each `<bibl>` gets the whole
  translation cut at its own boundaries, which is why 385 files produced 478 work-level
  attachments.
- **A mirror keeps renamed files.** 11 Tōhoku numbers arrived twice because 84000 renames
  a file when a translation is revised (`the_gandhavyuha_sutra` → `the_stem_array`), and
  7 of those pairs differ in the text. The `<edition>` version decides, compared as
  numbers: `v 1.0.30` is newer than `v 1.0.7` and older than `v 1.1.1`, and string
  ordering gets both comparisons wrong.

Not stored, and counted rather than guessed at: 3 folio references that fit no location,
3 folios absent from our text, 7 refused volume groups, and 4 Tōhoku numbers that are
Tengyur texts this corpus does not hold.

**A folio-anchored rendering is reachable from a line.** `Translations.covering/2` finds
renderings whose anchor *contains* a span, and `select/2` falls back to it when nothing
matches exactly — so asking for `@51.100a.3` returns the folio's English, labelled
`covers: :containing_range` and carrying its own wider `anchor_urn`. Containment is by
**segment ordinal**, recorded on the rendering at ingest, because whether `51.100a.3` lies
inside `51.100a.1-51.100a.7` is a fact about Derge folios while ordinals mean the same
thing in every source. The exact-match path is unchanged: a Pāli rendering anchored to
its own segment id still matches exactly and carries no `covers`.

### Chunk sizes are a tokenizer question (#21) — and the Pāli was answering it wrong

Chunking the Tibetan meant choosing a chunk size for it, and the note in the last session
said to measure rather than guess. Measuring found that **the Pāli size had been wrong
since #40, and invisibly so**.

The embedder runs BGE-M3 at `max_length=320` with `truncation=True`. A chunk over that is
embedded **from its opening only**: the text stays whole in the database, the vector
silently describes a prefix, and every count in the system still agrees. Measured over
real chunks of each script with the actual tokenizer:

| script | chars | tok p50 | tok p95 | over 320 |
|---|---|---|---|---|
| Literary Chinese | 300 | 277 | 291 | 0.0% |
| Pāli | **1,200** | 461 | 535 | **76.2%** |
| Pāli | 700 | 258 | 307 | 0.5% |
| Tibetan | 1,200 | 206 | 266 | 0.3% |
| Tibetan | 1,400 | 242 | 309 | 3.2% |

**Three quarters of the Pāli vectors described about the first two thirds of their
chunk.** Pāli recall@10 is 37.5% against Chinese at 98.7% (#19), and this is a plausible
mechanical contributor — the vectors were built from truncated text while the eval scored
against the whole. Sizes are now the largest whose 95th percentile fits the window: Pāli
700, Tibetan 1,200. Tibetan costs 0.151 tokens per character against Pāli's 0.425, which
is why the same window holds so much more of it.

**Re-chunking the Pāli then hit a defect that had been there all along.** SuttaCentral
numbers a merged section `53-55.1`, so the hyphen is inside the locator as well as being
the character this grammar joins two locators with. `URN.parse/1` split it, and the chunk
builder — which built its range URN from *parsed* locators — emitted `mn12@53-53`: an
address naming a segment that does not exist, identical for every chunk in the section,
and a unique-index violation the moment two landed in one insert. **412 chunks in the
corpus were addressed that way and none of them resolved.** Range URNs are now built from
the raw locator text, and `Pramana.Corpus` resolves a range it cannot split by looking the
URN up as a stored chunk — identity answering what arithmetic cannot.

Two more things the re-chunk forced:

- **`mix pramana.chunk --source`.** `--force` discards the vectors of every text it
  touches, and the corpus holds 299,317 Chinese vectors that cost GPU time. "Re-chunk the
  Pāli" must be sayable without putting those in the blast radius; narrowing a destructive
  operation is not a convenience. (Found the hard way: a `--force` run without it had
  already discarded 527 Pāli vectors before failing.)
- **Translation vectors could not see a range-anchored rendering.** The builder joined
  `translations.anchor_urn` to `segments.urn` by equality, and all 30,653 84000 renderings
  are anchored to folio ranges — so Tibetan would have had no English route into it at
  all. The join now also accepts renderings carrying `ordinal_start`/`ordinal_end`, and
  coverage is counted over the chunk's own segments so two overlapping folios cannot claim
  more of it than it has.

### What the Tibetan measured (#21) — and the two hypotheses it refuted

The Kangyur is embedded and the evals now cover three traditions. **The gold set could
not see Tibetan at all until it was fixed**, and that is the finding worth keeping:

- `mix pramana.evals.derive` joined `translations.anchor_urn` to `segments.urn` by
  equality — the **third** place that join has been wrong — so it found none of the
  30,653 range-anchored 84000 renderings and generated zero Tibetan cases, while
  hardcoding `tradition: "pali"` on everything it did generate. Tibetan would have been
  reported as *not measured* rather than measured and weak, which is the more dangerous
  of the two.
- Cases are now sampled **per tradition** (20 Pāli, 20 Tibetan, 35 Chinese), the tradition
  comes from the data, and a case is admitted only if its anchor resolves.
- Rule 18 arrived from the other side. Where the Pāli's SOURCE repeats verbatim, the
  Tibetan's TRANSLATION does: "Homage to all buddhas and bodhisattvas. Thus did I hear at
  one time." is the published English of **102 separate anchors**, over Tibetan that is not
  byte-identical because each names its own sūtra. Identical renderings now count as one
  equivalence class.
- Nine Tibetan topical cases, with the terms adjudicated by the corpus rather than
  asserted: of twelve proposed, three were rejected as too common to measure
  (ཤེས་རབ་ཀྱི་ཕ་རོལ་ཏུ་ཕྱིན་པ at 19,099 segments, སྟོང་པ་ཉིད at 20,500,
  མྱ་ངན་ལས་འདས་པ at 4,242) and **none as absent**.

**The numbers**, 249 cases, overall 79.5% (the run written as the new baseline; a
second run of the same build put topical/pali at 62.5%, which is the one-case wobble the
README already documents):

| | | |
|---|---|---|
| retrieval / chinese | 97.1% (34/35) | unchanged |
| retrieval / pali | 55.0% (11/20) | new sample |
| **retrieval / tibetan** | **35.0% (7/20)** | first measurement |
| topical / chinese-native | 100% (12/12) | unchanged |
| topical / pali | 56.3% (9/16) | was 75% |
| topical / chinese | 0.0% (0/12) | unchanged — no English layer |
| **topical / tibetan** | **0.0% (0/9)** | first measurement |
| quote verify / reject / provenance / absence | 100% | unchanged |

**Topical Tibetan is 0% for a structural reason, not a retrieval one.** 84000 has
published 385 of ~1,169 Tōhoku numbers, so **95% of the Kangyur has no English vector at
all** and an English topical question can only reach the twentieth of it that does. It is
the same shape as the Chinese 0%, with a different cause: Chinese has no English layer,
Tibetan has one over a twentieth of the text.

**Two hypotheses for the Pāli topical drop, both refuted by measurement.**

1. *The Tibetan English layer displaces Pāli.* This is what #44 predicted and what the
   first English demonstration looked like. Measured over the 16 topical/pali queries:
   **Tibetan occupies 1 of 160 result slots.** It is not displacing anything. (The same
   experiment confirms the English layer is what makes English→Pāli work at all: with
   `vector_kinds: ["source"]` the rate collapses to 1/16.)
2. *The smaller Pāli chunk returns a window too narrow to contain the term.* Scoring
   containment over the chunk **± 3 segments** — the passage a reader would actually see —
   gives **10/16 either way**. The retriever is not landing near the term and being cut
   off; it is not landing there.

What remains is the chunk size itself: 700 characters covers less ground than 1,200, and a
broad topical question is answered by breadth. That is a real trade — **anchor-precise
retrieval up, topical recall down** — and it is not an argument for reverting, because
1,200 was never honestly embedded: 76% of those vectors described two thirds of their
chunk. The honest alternative is to raise the embedder's 320-token limit for the alphabetic
scripts and keep the wider window, paying for it in GPU time. Untested.

**Under #44's rule the Tibetan layer stays a default**: it was measured against
answered-from-any-tradition before shipping, and the drop there (9/11 → 8/11 topics) is
attributable to the Pāli chunk change, not to Tibetan taking slots.
