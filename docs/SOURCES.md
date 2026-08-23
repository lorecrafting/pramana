# Sources

All four traditions land in v1. Ordered by ingest difficulty — do them in this order,
because each one's tooling makes the next cheaper.

## Tier 1 — Clean structured text, no OCR

### CBETA (Chinese)
- `https://github.com/cbeta-org/xml-p5` — TEI P5, git-pinnable
- Taishō vols **1–55 and 85**, plus 卍續藏 (X) and ~20 other collections
- ~250M characters; the backbone of the corpus
- **License: non-commercial, header must remain intact**
- Watch: ~30k gaiji glyphs; editorial punctuation; full `<app>` variant apparatus
  (Song/Yuan/Ming/Koryŏ) — that apparatus is a feature, not noise

### SAT Daizōkyō (Japanese)
- `https://21dzk.l.u-tokyo.ac.jp/SAT/` — all 85 Taishō volumes
- **License: CC BY-SA 4.0** — the most permissive major Chinese-script canon source
- **Its unique value is vols 56–84**: the Japanese-composed sectarian commentaries
  (Shingon, Tendai, Nichiren, Zen) that CBETA deliberately excludes. This is the
  delta that makes the provenance model necessary.
- Overlaps CBETA on vols 1–55/85 — dedupe by work ID, keep both as separate
  witnesses rather than discarding one

**⛔ BLOCKED: there is no bulk download.** Checked 2026-08-15. The data is CC BY-SA 4.0,
but SAT publishes no dump, no archive and no documented API; the site directs bulk
enquiries to `sat at l.u-tokyo.ac.jp`. Nor is there a usable mirror — the candidate
GitHub repositories are metadata only (`daizokyo/Taisho_shinshu_daizokyo`, 103 KB), a
handful of sample works (`..._txt`, four works), or a research pipeline rather than the
canon (`dangerzig/taisho-canon`), and **none carries a licence**.

Scraping the reader is not an option: it is the acquisition path this project's own
rules forbid (no pinned upstream, no `files_sha256`, nothing reproducible), quite apart
from being rude to a university service.

**Next step is an email**, asking for a bulk copy of vols 56–84 under the CC BY-SA 4.0
terms already granted, and stating the use. Note what that ask is and is not: **the
licence is not in question**. SAT has already released this material under CC BY-SA 4.0,
so the request is for a *copy of openly-licensed data*, not for permission. That is a far
easier thing to grant than an exception.

**Send it once, and sequence nothing behind it.** The odds are unknowable — an academic
group that has run a public interface for years without offering a dump has usually taken
a position rather than overlooked a feature, and academic email runs weeks to months. Treat
this as opportunistic. Until then:

- The 56–84 provenance rule is implemented and tested
  (`Pramana.URN.Taisho.provenance_for_volume/1`), so the material classifies itself
  correctly the moment it arrives.
- `Pramana.Coverage` states the gap in every survey response, so the absence cannot be
  mistaken for the Japanese tradition being silent.

**And if it never arrives, that is an acceptable end state.** A gap the system announces —
by division, work-number range and classification — is not the failure this project exists
to prevent. An unannounced one would be.

#### The better use of that effort: CBETA's other collections

This corpus holds witness `T` and nothing else from CBETA — **one of roughly twenty
collections**. `X` (卍新纂續藏經, ~90 volumes), `J` (嘉興藏), `B` (大藏經補編), `K` (高麗),
`L` (乾隆), `N` (南傳大藏經) and others are unacquired.

| | SAT vols 56–84 | CBETA's other collections |
|---|---|---|
| works | 547 | thousands |
| permission | must be asked for | **none needed** |
| pipeline | new | **built and proven on 2,471 works** |
| licence | CC BY-SA 4.0, settled | settled |

Same acquisition path, same TEI normalizer, same lockfile machinery. Waiting on an
uncertain reply for 547 works while thousands sit behind a pipeline that already works is
the wrong sequencing.

**One correctness note before doing it:** `Pramana.Coverage.taisho/0` reasons about Taishō
*volume numbers*. If Japanese-composed works arrive through another collection under
different numbering, coverage will not see them and the caveat will overstate the gap.
Revisit `Coverage` when a second CBETA collection lands.

### SuttaCentral `bilara-data` (Pali)
- `https://github.com/suttacentral/bilara-data` — **not one licence, and not CC0.** The
  repository's `LICENSE.md` says CC0; its own `_publication.json` disagrees in two places,
  and the more specific statement governs. `Pramana.Sources` is the authority and records
  three separate entries:

  | id | licence | redistributable |
  |---|---|---|
  | `sc` — Mahāsaṅgīti Pāli root text | **CC-PDM-1.0** (Public Domain Mark, per scpub64) | yes |
  | `sc-translations` | **CC-BY-SA-3.0** — the weakest of the publications it covers (139 CC0, 1 CC BY-SA 3.0: scpub69, the Patna Dhammapada) | yes, with attribution and share-alike |
  | `sc-data` | **NOASSERTION** — no LICENSE file in the repository; terms unconfirmed as of 2026-08-15 | **no** |

  This entry previously read "CC0, public domain" for the whole repository, which is the
  repository-level claim the corpus already established is wrong — and it is the reason
  licence is recorded per *publication* rather than per repository everywhere else in this
  project. CC BY-SA carries attribution and share-alike obligations CC0 does not.
- ~444k segments, already segment-aligned root ↔ translation
- Also grab `sc-data`: thousands of **hand-curated Āgama↔Nikāya parallels** — curated
  scholarship worth ingesting rather than rediscovering with embeddings. It is *free to
  fetch* and **not established as redistributable**; this entry used to call it "free",
  which reads as a licence grant nobody has given. It is held as `redistributable: false`
  until someone confirms terms with SuttaCentral.
- Segment IDs (`mn1:1.1`) are the field standard. Adopt them verbatim.

## Tier 2 — Structured but partial

### The Tibetan pair — TWO sources, not one (#21)

The source text and its English translation come from different projects under
different licences, and they are registered separately. Merging them would put a
rendering under the same terms as the words it renders, and would lose the fact that
one of them is freely redistributable and the other is not.

**`derge` — Digital Derge Kangyur** (`CC-PDM-1.0`, public domain)
- `https://github.com/Esukhia/derge-kangyur`, TEI release `UT4CZ5369`; archived and
  continued at `OpenPecha/P000001`
- The Tibetan-language **source text**: the Esukhia–Barom proofread edition of the
  UVA–SOAS 2013 eKangyur, itself diff-proofread against BDRC, ACIP and Adarsha etexts
- "A mechanical reproduction of a Public Domain work, and as such is also in the Public
  Domain" — the project's own statement. The proofreading annotations are the editors'
  work; the text is not.

**`derge-tengyur` — Digital Derge Tengyur** (`CC-PDM-1.0`, public domain)
- `https://github.com/Esukhia/derge-tengyur`, plain-text release `deten_vol_txt_v1905`
  (2019-05), 213 volumes
- The Indian **commentarial** literature, Tōhoku 1109–4569 — a separate print from the
  Kangyur with its own editorial hand, which is why it is its own source id rather than
  another witness of `derge`. It loads with `text_role: "treatise"`; inheriting the
  Kangyur's `root` would call Vasubandhu the Buddha's word in every citation drawn from it.
- **Use the plain text, not the TEI.** The official TEI release carries 888,576
  milestones and every one is `unit="line"` — **zero** `unit="text"`, one `<tei:div>` per
  file — so nothing in it says which of the 3,380 works a line belongs to. (The Kangyur's
  TEI has 1,208 of them.) The plain text marks each work inline as `{D1109}`: 3,380
  markers, 3,380 distinct.
- The release is pinned at 2019-05 rather than tracking master, which has more editorial
  annotation (71 vs 70 markers in volume 1). A moving upstream is not a citable edition.
- Volume 213, the དཀར་ཆག catalogue volume, ships as a filename with **no bytes**.

**`84000` — Translating the Words of the Buddha** (`CC-BY-NC-ND-3.0`)
- `https://github.com/84000/data-tei` — TEI, plus an API and an RDF metadata export
- Kangyur/Tengyur **English translations**, Toh numbers, Derge folio references. A
  `translation` layer, never a source: `CLAUDE.md` invariant #7.
- Ships a **Skt–Tib–Eng glossary** — a direct cross-lingual anchor for alignment
- Coverage is partial and growing; treat completeness as a moving target
- **The first ND source in this corpus.** `sources.derivatives` exists because of it —
  see below.

#### How the Derge text is structured, and the one trap in it

103 volume files, 298 MB, **65,983 folio pages and 460,539 line milestones** — and
**1,125 Toh works**, which do not correspond to files at all. A work is delimited by
`<milestone unit="text" toh="N"/>` markers *inside* a volume, so one file holds dozens
of works. That is rule 23 again from the other direction: there, ten suttas shared one
file; here, one file holds a hundred texts.

The citation anchor falls straight out of the markup: `<p data-orig-n="1b">` is the
folio, `<milestone unit="line" n="3"/>` the line within it, so the locator is `1b.3` —
folio side and line, exactly how Tibetanists cite, and exactly parallel to Taishō
page-register-line.

**The trap: volume 103 is the dkar chag**, the edition's own catalogue. Eight Toh
markers appear there as well as in the text volumes, and a normalizer that treats every
marker as the start of a work would emit eight extra works whose content is a fragment
of a list of titles — short, plausible-looking, and colliding on the URN with the real
text. The numbers are not subtle once measured:

| | median characters between markers |
|---|---|
| volume 103 (dkar chag) | **24** |
| every other volume | **7,804** |

`ཕྱག་དང་།` — "homage, and" — is what Toh 539 looks like in the catalogue. It is a title in
a running list, not a text. Folio numbers also restart at `1a` in every volume, so those
eight would have collided on the anchor too.

The two join on **Toh number and Derge folio**, which both sides carry. That is the same
shape as the Pāli pair (bilara root text plus translations keyed by segment id), and it
is why a Tibetan passage can be shown beside its English without either being mistaken
for the other.

### Licences have four axes, not three

`sources` recorded `commercial_use`, `redistributable` and a coarse `license_class`.
Creative Commons has a fourth switch — **no-derivatives** — and nothing in the corpus
needed it until 84000.

ND is not a stronger NC. They constrain different acts: `commercial_use` and
`redistributable` govern who may **receive** the text; `derivatives` governs what may be
**made** from it. This pipeline makes things constantly — it segments, chunks, embeds,
and Phase 7 will translate. Whether any of those is a derivative work is a judgement for
the deployment, but the schema has to be able to record the constraint so the judgement
has something to attach to. Folding ND into `nc` would delete the question.

Recorded **per source**, defaulting to permitted, because a column added later must not
silently restrict every source that predates it.

## Tier 3 — Images, needs OCR

### BDRC / BUDA (the "Digital Tibetan Buddhist Treasury")
- `https://library.bdrc.io/` — 30M+ pages, the largest Tibetan collection anywhere
- **Overwhelmingly scanned page images, not searchable text**, and restrictively
  licensed. Plan this as an OCR program, not an ingest task.
- v1 use: catalog metadata, RIDs as authority identifiers, and IIIF image links so a
  reader can show the manuscript page beside the text. Full-text OCR is post-v1.

## Supporting data

### Reading dictionaries — INGESTED (#24)

- **Unihan** (`Unicode-3.0`, redistributable with notice) —
  `https://www.unicode.org/Public/UCD/latest/ucd/Unihan.zip`. `Unihan_Readings.txt` only.
  `kMandarin` supplies the ordinary reading of a character; `kHanyuPinyin`, `kXHC1983`,
  `kTGHZ2013` and `kHanyuPinlu` together supply the **attested set** — every reading
  anybody records for that character. The Buddhist readings are in there: 葉 is listed
  `yè, shè`, 般 is `bān, bō`. What is missing is which one applies where.
- **CC-CEDICT** (`CC-BY-SA-4.0`) —
  `https://www.mdbg.net/chinese/export/cedict/`. Supplies compound readings. Share-alike
  propagates to `priv/readings/exceptions.tsv`, whose rows record `authority=cc-cedict`.

Neither is corpus text, so neither gets a row in `sources`: that table gates what can be
*served*, and a dictionary is a build input. Both are pinned in `sources.lock.json` by
content hash, because the derived artifact is only reproducible against the exact input.

- **DILA authority databases** — person/place/time authority records, ~22k
  teacher–student lineage chains. The backbone of any knowledge graph.
- **DDB** (Digital Dictionary of Buddhism) — Chinese Buddhist terminology
- **Mahāvyutpatti** — the canonical Sanskrit–Tibetan term correspondence table;
  exact, citable cross-lingual anchors
- **Digital Pali Dictionary**, **Monier-Williams** (Sanskrit)
- **GRETIL** — Sanskrit etexts, for surviving Indic originals
- **Wikidata** — Q-IDs for people/places, for external linking

## Later expansion: East Asian medical texts

The architecture generalizes without change, because the provenance shape is
*identical*: a base text, layered commentary, and a Japanese reception layer.

- **Kanripo / Kanseki Repository** — Chinese classics in TEI, same tooling as CBETA
- **CTEXT** — Chinese Text Project
- Core works: 黃帝內經, 傷寒論, 神農本草經, 本草綱目
- Japanese Kampo (漢方) commentary sits in exactly the same relation to Chinese
  medical classics as Taishō 56–84 does to the Chinese canon. The
  `composition_origin` / `text_role` axes carry over unmodified — which is a good
  sign the model is right.

## License handling

Every source row carries `license_class`. The API can be configured to exclude
classes, so a deployment can serve only CC0/CC-BY content. We publish the **pipeline,
not the corpus** — each user bakes their own from upstream, which keeps CBETA's
non-commercial clause and BDRC's restrictions out of our distribution entirely.
