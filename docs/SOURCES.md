# Sources

> Source catalog plus dated acquisition notes. A listed upstream is not necessarily acquired, licensed for your intended use, or fully ingested. Check the source registry, lockfile, task code and the actual database; external terms and remote availability were not reverified by the documentation audit.

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

**⛔ STILL BLOCKED for TEXT — but two things changed on 2026-08-30, and one of them was
never blocked at all.**

**The catalogue exists and always did.** SAT serves a browsable index at
`/iiif/taisho/manifests/`, listing 5,750 IIIF manifests over 2,873 works — of which **541
fall in T2185–T2731 and span exactly volumes 56–84**. One request, no permission, pinned at
`raw/sat-iiif/manifests_index_20260830.html`. This closes task #41, which this plan recorded
as *"no source exists"*. It also corrected a figure published here for months: **"547 works"
was `2731 - 2185 + 1`**, the width of the number range, not a count.

**Metadata is fetchable and is not text.** `mix pramana.sat.metadata` walks those 541
manifests — title, byline, 部 division, page extent — so `Pramana.Coverage` can *name* every
missing work rather than report a number. IIIF exists to be read by machines. Note the
licences differ: the **text is CC BY-SA 4.0, the page images are CC BY-NC-SA 4.0**, and only
the second is non-commercial. `Pramana.Acquire.SAT` fetches text and manifests, never images.

**The base-text survey is already public.** SAT and the National Institute of Japanese
Literature publish 底本調査 for the 日本撰述部 under CC BY-SA 4.0 — 2,749 rows covering 144
of the 541 works, naming the manuscript each was edited from and where it is held. Pinned at
`raw/sat-teihon/`, registered as `sat-teihon` with **dual attribution**, which is why it is a
separate source entry rather than a file under `sat`.

**None of that is the text.** Checked 2026-08-15, and again 2026-08-30. The data is CC BY-SA 4.0,
but SAT publishes no dump, no archive and no documented API; the site directs bulk
enquiries to `sat at l.u-tokyo.ac.jp`. Nor is there a usable mirror — the candidate
GitHub repositories are metadata only (`daizokyo/Taisho_shinshu_daizokyo`, 103 KB), a
handful of sample works (`..._txt`, four works), or a research pipeline rather than the
canon (`dangerzig/taisho-canon`), and **none carries a licence**.

Scraping the reader is not an option: it is the acquisition path this project's own
rules forbid (no pinned upstream, no `files_sha256`, nothing reproducible), quite apart
from being rude to a university service.

**The email was SENT on 2026-08-15** and is unanswered as of 2026-08-30 — though it landed
during Obon, so that is not yet a silence worth reading into. A follow-up is drafted in
`docs/sat-request-email.md` for mid-September; it cites SAT's own CC BY-SA 4.0 release of the
底本調査 as precedent, and it replaces the open-ended ask with a bounded one: the reader
returns a whole **fascicle** per request, so the material is about **4,200 requests**, a few
hours at one every three to five seconds — not the 28,800 pages an earlier estimate assumed.

The original ask was for a bulk copy of vols 56–84 under the CC BY-SA 4.0 terms already
granted, and stating the use. Note what that ask is and is not: **the
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
  | `sc-lzh` — SuttaCentral Taishō (`root/lzh/sct`) | **CC0-1.0** (per scpub39), corrected and re-punctuated from SAT 2018 (CC BY-SA 4.0) | n/a — **read and never stored** |

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

#### The Chinese half of bilara-data — `mix pramana.sc.chinese`, 2026-08-31

**bilara is not only Pāli.** `root/lzh/sct` is 272 Chinese texts and
`translation/en/patton` is Charles Patton's CC0 English of the Chinese Saṃyukta and
Madhyama Āgamas — **54 works, on disk and hashed into the `sc-translations` lockfile
entry since #39, and discarded at every ingest**, because their anchors name
SuttaCentral addresses (`sa379:2.2`) and this corpus holds those Āgamas as CBETA.
`mix pramana.sc.translations` filed all of them under `no_such_anchor`, which is also
where the Pāli's legitimate elisions land, so the loss looked like ordinary noise. The
sparse checkout did not even fetch the Chinese root they would have been joined through.

`sc-lzh` is the first source here that is **read and never stored**. `Pramana.Sc.Lzh`
matches it against the CBETA text already held and keeps a **Taishō** address, so an
English reader following one of these citations arrives somewhere they can check against
a print edition. Loading bilara's Chinese as a second witness would have been less work
and would have pointed every reader at our own convenience copy. It is registered and
pinned regardless, because it is an input to an ingest and invariant #3 is about
reproducibility, not about storage.

    cd raw/sc/bilara-data && git sparse-checkout set root/pli/ms translation/en root/lzh/sct
    mix pramana.sc.chinese

### DILA Glossaries — the lexicon layer, INGESTED 2026-09-02

`https://glossaries.dila.edu.tw/` — TEI P5, bulk download, no key. Same institution whose
person and place authority this project already ingests. `mix pramana.glossary.dila`.

| glossary | entries stored | scope | attestation |
|---|---|---|---|
| Soothill-Hodous (1937, corrected by Muller 2002-3) | 16,792 | general | dictionary |
| Mahāvyutpatti | 9,379 | general | source |
| Karashima, Dharmarakṣa's Lotus | 3,228 | **T0263** | 2,604 source |
| Karashima, Kumārajīva's Lotus | 2,340 | **T0262** | 2,149 source |
| Karashima, Lokakṣema's Aṣṭasāhasrikā | 1,528 | **T0224** | dictionary |

**Chosen for accuracy, not reach.** L1 called dictionaries "the largest functional gap",
and the gap was never that we hold none — the 56,382 entries already here are
Tibetan-shaped, and *acalā* had seven with Tibetan and **not one with Chinese**.

Karashima's three are the reason this set is worth more than its size. They are glossaries
of **one translator's usage**, and they record things no general dictionary can:

    佛   Soothill-Hodous   Buddha, from budh "to be aware of"…
    佛   Lokakṣema         enlightenment; Buddhaship — a transliteration of Skt. bodhi

    法   Soothill-Hodous   Dharma. Law, truth, religion, thing, anything Buddhist…
    法   Kumārajīva        as a rule, normally, conforming to what is expected

In the earliest translations 佛 transliterates *bodhi*; Kumārajīva's 法 is frequently an
adverb. Karashima also records that **Lokakṣema often rendered *śrāvaka* as 阿羅漢**.

**Each entry carries Taishō citations** — `T.262` at `59b7`, with the Chinese quotation and
the Sanskrit witness beside it — so a gloss anchors to lines this corpus holds and can be
byte-verified. 29,890 citations are stored; resolving them to URNs is a separate step.

**Measured before it was built.** Seeded 200-headword samples against the CBETA text held
here: Soothill-Hodous 187/199, Karashima's Kumārajīva 190/199, the Mahāvyutpatti's Chinese
side 140/199.

**Rights record requires two layers.** The current DILA portal states CC BY-NC-SA 4.0,
but the exact digital-edition PDFs for all five files ingested here — Soothill-Hodous,
Kumārajīva, Dharmarakṣa, Lokakṣema and Mahāvyutpatti — each state CC BY-SA 3.0 and point
to the TEI source. The TEI headers themselves name Creative Commons without a version.
This is therefore a primary-source licence-version conflict, not a secondary-source
rumour. The coarse `dila-glossaries` registry entry deliberately retains the more
restrictive current NC posture for public-surface gating; it is **not** sufficient
authorization for every pilot operation. See
[`CHINESE_PILOT_RIGHTS.md`](strategy/CHINESE_PILOT_RIGHTS.md) for the
resource×operation boundary. In particular, "local" does not mean "automatically cleared
for any transformation or external model".

**Not taken:** Hopkins Tib-Skt-Eng (18,441) and the Nanshan Vinaya dictionary (3,218) are
on the same portal. Their own resource-specific notices still need review before use;
the portal-wide statement is not generalized to them merely because they share a site.
Both also duplicate strength this corpus already has — Tibetan-side and Chinese-only
respectively — and neither closes the measured gap.

**Not acquirable:** the Digital Dictionary of Buddhism is the scholarly standard and is
**not open for bulk download** — rights to individual articles are held by their authors.
Same posture as SAT: it is asked for, not scraped.

#### The citations are anchored — `mix pramana.glossary.anchor`, 2026-09-02

Karashima's entries cite the passages a gloss rests on, and those are Taishō addresses
this bake already holds. Resolved, a dictionary entry stops being a claim you take on
trust:

| | of 29,890 |
|---|---|
| **resolved** — a line this bake holds | **25,504 · 85.3%** |
| **absent** — a scholar checked and the term is **not** there | **4,345 · 14.5%** |
| unresolved — no such line here, or no address at all | 41 · 0.1% |

Opening one line of Kumārajīva's Lotus now returns 方便 = *upāyakauśalya* and 無上道 =
*agrabodhi* from his glossary — **and `absent` entries scoped to T0263**, meaning the term
Dharmarakṣa used has no counterpart in Kumārajīva at that line. That is per-line
cross-translation divergence, which is what `Pramana.Translators` has been short of data
for.

**`absent` is a status, not a failure.** 4,345 citations are Karashima having looked at a
specific line and recorded that the word is not there — attested absence by somebody who
checked, which `docs/PLAN.md` calls the highest-value signal a corpus project has.

**Two conventions had to be read out of the data rather than assumed.** A siglum names
whose translation is quoted (`Lk.` Lokakṣema, `Z.` 竺法護), and **a minus sign counts from
the foot of the register** — `27b-1` is the *last* line of page 27b, not the first. 285
citations use it, and reading them as ordinary line numbers put every one of them
somewhere wrong. Verified before implementing: the entry citing `27b-1` quotes
能於四衆示教利喜, which sits at line 29 where the register's last line is 29; the entry
citing `19a-6` is headed 方便 and marks that headword inside 以智、方便而演説之 at line 24,
which is `29 - 6 + 1`.

The remaining 41 were chased rather than written off: 31 name a line CBETA prints nothing
on. `T.224` `448c4` is `<lb n="0448c04"/>` immediately followed by the next `<lb/>`, so
nothing was printed there and the normalizer was right to drop it — rule 3, checked
against `raw/` rather than assumed.

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
- **Then link its commentaries — `mix pramana.derge.relations --write`.** Tibetan titles
  do not work the way `mix pramana.relations.derive` assumes: a Chinese commentary's title
  CONTAINS its root's, while a Tibetan one shares a **stem** and differs by genre suffix
  (`འགྲེལ་པ` vṛtti, `འགྲེལ་བཤད` ṭīkā, `ཚིག་ལེའུར་བྱས་པ` kārikā), so neither title contains
  the other. `Pramana.Derge.Genre` reads the suffix. Ritual genres are excluded by name —
  `སྒྲུབ་ཐབས` alone appears ~700 times, more than every commentarial suffix combined, and a
  sādhana shares its stem with every other sādhana for the same deity.
- **Its titles need promoting after an ingest — `mix pramana.derge.titles --write`.**
  The ingest reads each work's incipit into `works.meta` (`title_sa_ltn_computed`,
  `title_bo_ltn_computed`, `title_sa_bo_script`) and leaves `works.title` null, and
  `get_outline` and `search` read `title` — so 2,675 works that HAVE a title could not be
  found by it, the whole *pramāṇa* literature among them: `toh4210` is Dharmakīrti's
  Pramāṇavārttikakārikā and `toh4203` Dignāga's Pramāṇasamuccaya. The task promotes
  Sanskrit-first, writes only into a null so the Kangyur's curated English from 84000 is
  never overwritten, and is a no-op on a second run. 705 works have no title block at all
  — mostly continuations of a work spanning volumes — and stay nameless.
- The release is pinned at 2019-05 rather than tracking master, which has more editorial
  annotation (71 vs 70 markers in volume 1). A moving upstream is not a citable edition.
- Volume 213, the དཀར་ཆག catalogue volume, ships as a filename with **no bytes**.

**`84000` — Translating the Words of the Buddha** (`CC-BY-NC-ND-3.0`)
- `https://github.com/84000/data-tei` — TEI, plus an API and an RDF metadata export
- Kangyur/Tengyur **English translations**, Toh numbers, Derge folio references. A
  `translation` layer, never a source: [the shared invariants](INVARIANTS.md) invariant #7.
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

### The tasks that ingest the Tibetan pair

    mix pramana.kangyur.catalogue     titles the Kangyur from 84000's catalogue, links to BDRC
    mix pramana.kangyur.translations  84000's English as renderings of the Degé Kangyur
    mix pramana.kangyur.glossary      84000's per-translation Skt–Tib–En term anchors
    mix pramana.derge.images          BDRC's image lists, one per volume

Four commands rather than one because they are four different **claims**: what a text is
called, what it says in English, what its terms correspond to, and where its scans live. Each
can be absent without the others being wrong, and the Tibetan pair is two sources rather than
one for the same reason — see above.

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
  propagates to `apps/pramana/priv/readings/exceptions.tsv`, whose rows record `authority=cc-cedict`.

Neither is corpus text, so neither gets a row in `sources`: that table gates what can be
*served*, and a dictionary is a build input. Both are pinned in `sources.lock.json` by
content hash, because the derived artifact is only reproducible against the exact input.

### DILA authority databases — PERSON INGESTED, place next

`DILA-edu/Authority-Databases`, CC BY-SA 3.0, pinned in `sources.lock.json` and acquired in
parts — which makes rule 43 binding on the next fetch: the lockfile write must **merge**,
or the person file's record disappears the way the Taishō's 2,471 did.

Not corpus text and so no `sources` row: these describe people and places that appear across
every canon, and `Pramana.Sources` marks the tradition `reference` for exactly that reason.

- **`authority_person/`** — ▸ **ingested**. `mix pramana.authority.import` loads it into
  `authority_people` and `authority_relations`; `mix pramana.authority.link` attaches people
  to bylines and derives the works' date bounds. Counts are computed, not written here — run
  the task, or `Pramana.Coverage.dated/0`.
- **`authority_place/`** — ▸ **ingested.** 31.1 MB plus a 2.9 MB districts file, loaded
  into `authority_places`. Resolves the `place_id` already stored on 12,134 people into a
  modern administrative path *and* a historical region — 江南東道, not 浙江省 — plus
  coordinates. Read `Pramana.Authority.parse_places/1` before touching it: `<geo>` is
  **longitude first**, which is the reverse of TEI's convention.
- **`authority_time/`, `authority_catalog/`** — **no data at this pin.** Both directories
  contain README files only, so neither is declared in `Pramana.Acquire.DILA`. The registry
  named this source *"(person, place, time)"* until 2026-08-28, promising a database the
  upstream does not ship.

    mix pramana.readings.import   loads the built reading dictionary into the database
    mix pramana.glossary.import   a markdown glossary as pinned term renderings

Other reference data still wanted, none acquired:

- **DDB** (Digital Dictionary of Buddhism) — Chinese Buddhist terminology
- **Mahāvyutpatti** — the canonical Sanskrit–Tibetan term correspondence table;
  exact, citable cross-lingual anchors
- **Digital Pali Dictionary**, **Monier-Williams** (Sanskrit)
- **GRETIL** — Sanskrit etexts, for surviving Indic originals. **Scoped 2026-09-02 as
  `docs/PLAN.md` § S1** and deliberately not acquired: the licence is per-text "free for
  scholarly use" rather than a class the API can exclude by, and the citation grammar
  differs per work, which invariant #2 will not let us paper over. Note it is a set of
  **witnesses**, not a canon — most Indic originals are lost
- **Wikidata** — nothing is fetched from Wikidata, and `get_person` already returns q-ids
  for 1,446 of the linked works' people. They arrive as **DILA's pass-through**, so their
  correctness is DILA's claim; querying Wikidata itself is a separate, unmade decision

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
