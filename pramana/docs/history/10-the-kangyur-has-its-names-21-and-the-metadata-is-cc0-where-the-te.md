# Project history — chapter 10

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### The Kangyur has its names (#21) — and the metadata is CC0 where the text is not

**1,189 of 1,195 Kangyur works now carry a title**, up from 478, in English, Sanskrit and
Tibetan, with a Wylie transliteration and a BDRC identifier. From 84000's RDF export:
1,254 records covering 1,160 Tōhoku numbers, translated or not.

**The licence is not the one on the repository.** `data-rdf`'s README says CC BY-NC-ND —
the terms for the translations — while every record's own `adm:license` says `LicenseCC0`
with the label "Metadata related to the translations by 84000, provided under the CC0
License". Both are true of different things: the prose of a translation is restricted, the
fact that Toh 113 is called *Saddharmapuṇḍarīka* is not. Recorded as its own source,
`84000-rdf`, because it is its own publication — the same rule bilara-data forced, where
the repository claimed CC0 and the publication file said Public Domain Mark and CC BY-SA.
**This is the first CC0 content in the corpus.**

**Four descriptions of one text, each holding a different title.** A record describes the
abstract Indic work, the Tibetan translation, the Degé printing of it, and 84000's
English — so the Tibetan title is taken from the Degé printing, which is the edition this
corpus holds, and the Sanskrit from the Indic work. Reading any `skos:prefLabel` with the
right language tag would have attributed the printing's title to the Sanskrit original,
and a translator's name — which is also a `prefLabel` — to the sūtra.

A published title is never overwritten: where a translation exists, its own title page is
the better authority and was already stored, so the catalogue fills only what was empty
and records which source each title came from.

**The Wylie is computed, and checking it against 84000's own found two bugs.** The RDF
carries no transliteration, so `Pramana.Readings.Wylie` produces one from the Tibetan and
it is stored under a separate key — a claim by this code must be distinguishable from a
claim by the editors. 476 works have both, which makes an independent check possible:

    before   452 / 476 agree   (94.9%)
    after    454 / 476 agree   (95.4%)

Two real defects, both in constructions that are everywhere in Tibetan:

- **`བའི` came out `b'i`, not `ba'i`.** The rule "an explicit vowel sits on the root" is
  right for བདེ → `bde` and wrong for an *a-chung* suffix carrying the genitive: the བ
  keeps its implicit *a* and the འ takes the ི. That is most of the particles in the
  language — པའི, མའི, པའོ — and it was wrong in every one.
- **`ཤཱཀྱ` came out `shAkya` only after** recognising that a non-root stack carrying a
  SUBJOINED letter is a syllable of its own rather than a suffix; a suffix is always a
  single letter.

The 22 remaining differences are characterised rather than chased: about half are
genuinely different titles (the catalogue and the translation's title page name the text
differently, e.g. `spyan ras gzigs yum` against `spyan ras gzigs dbang phyug gi yum`), one
is 84000 storing Tibetan script in a Wylie field, and the rest are Sanskrit conjunct
notation (`kul+le` against `kulle`) and the `dags`/`dgas` prefix-root ambiguity, which
cannot be resolved without a lexicon. Six works stay untitled: five sub-parts of Toh 845
and one lettered variant, where the etext divides more finely than the catalogue.

Each record also carries the BDRC id of the Degé printing (`MW22084_0113`) — the handle a
IIIF manifest is addressed by, which is the catalogue half of the Phase 5 BDRC item, with
no OCR involved.

### The woodblock page, linked (#21) — and why the arithmetic had to go

A Derge passage now comes back with the photograph of the leaf it was printed on.
**64,828 of the corpus's 65,778 folio anchors — 98.6% — resolve to a BDRC page image**,
served over IIIF, attributed, and never copied or read. `get_passage` carries it as
`page_image`; a folio with no scan gets nothing rather than a neighbour.

**The mapping is BDRC's, and reading it replaced an inference that looked right.** The
obvious construction is arithmetic: two cataloguing cards, then folio *n* recto at leaf-side
2n−1, image name `<group><NNNN>.jpg`. It was built that way first, and the audit that
checked it against all 103 volumes said: 74 fit, **29 claim more leaf-sides than the scan
contains**. Volume 7 settles it — the etext prints folios 1a–287b, BDRC's canvas labels run
1a–287b, and there are **536 canvases where contiguous sides would need 574**. Sides are
missing from the middle of the scan, and nothing computable from a filename could know
which. A single omitted leaf silently shifts every page after it, so the reader is shown a
leaf that is *almost* the right one — the failure this project exists to prevent, arriving
as a photograph.

BDRC publishes the answer: every canvas is labelled with its folio (`1a`, `img. 3`, `1na/`,
`par grangs _3`). So the manifests are fetched and the labels read, which is invariant #2
applied to pictures — adopt the edition's own reference system, never invent one. The
proof it mattered is one line: `51.100a` is image **202**, and the arithmetic said 201.

Also settled here:

- **The volume-to-image-group mapping is derived, not assumed.** The group is in the
  etext's own directory name (`UT4CZ5369-I1KG9127`) and BDRC's record for that group
  confirms it says *"Volume 1 of bka' 'gyur (sde dge)"*. The ids do run consecutively from
  9127, and that is a coincidence of issue order rather than a fact to rely on.
- **The Degé restarts foliation inside a volume.** Volume 31 holds two texts numbered
  1–206 and 1–91, so `31.1b` names two different leaves and is disambiguated only by the
  work in the URN. Two volumes are like this. It does not affect the image lookup now that
  labels are read rather than counted, but it means a bare "D vol 31, f. 1b" is ambiguous
  in this edition.
- **The licence is the scan's, not the metadata's.** What is stored is BDRC's manifest —
  what exists and what it is called. The images stay at BDRC, are linked with attribution,
  and are never redistributed or read.

### The translators' own glossaries (#21) — Skt–Tib–Chi anchors, attested

Phase 5's last bullet asked for Mahāvyutpatti and 84000 glossary entries as Skt–Tib–Chi
anchors. The 84000 half was already in `raw/`: every translation ships with the
translator's glossary, and there are **58,820 entries across the published Kangyur**.

**56,382 stored: 41,253 with Sanskrit, 55,807 with Tibetan, 1,105 with Chinese, 41,480
with a definition — 16,741 distinct Sanskrit terms and 25,524 Tibetan.** Of those, **865
carry all three languages**: `dharma` / `ཆོས།` / `法`, `bodhisattva` / `བྱང་ཆུབ་སེམས་དཔའ།` /
`菩薩摩訶薩`, made by the people who did the translating rather than assembled by matching
strings.

**They work as anchors.** Sampled 60 of the three-way entries against the corpus itself:
the Chinese term occurs in the Taishō for 59 and the Tibetan in the Kangyur for 60 — **59
reachable in both canons at once**. The miss was a proper name the Chinese transliterates
differently, which is the expected shape of the failure.

**Most of the Sanskrit is a reconstruction, and the table says so per term.** 84000 marks
each form: Tibetan `attestedSource` 23,252, Sanskrit `sourceUnspecified` 22,442, Sanskrit
`attestedSource` only 575 in the sampled files (2,783 across the whole ingest). `yūpa`
beside `མཆོད་སྡོང་།` is a scholar's inference about a lost Indic original, not a quotation
from one, and storing the two identically would flatten that into a claim the edition does
not make — the same failure `composition_origin` prevents one layer up. `attested_only:
true` narrows a query to what a witness says, and the attestation is on every row returned
so a caller who never asks still cannot mistake one for the other.

**2,756 Sanskrit terms are rendered by more than one Tibetan**, and nothing here picks a
winner. `parivrājaka` appears as `ཀུན་ཏུ་རྒྱུ་བ།`, `ཀུན་དུ་རྒྱུ།` and — in one text —
transliterated rather than translated, `པ་རི་པ་ར་ཙ་ཀ`. `TermAnchors.renderings/2` returns the
set with how many texts chose each, which is the refusal `Pramana.Translations` makes about
whole passages, one word down. It is also Phase 6's translator-divergence measurement
arriving early and for free.

Stored apart from `glossary_terms` on purpose: that table is a **policy** (376 hand-pinned
renderings for one Chinese commentary, answering *what should this be called*), this one is
**evidence** (*what did this translator call it, in this text*). Merging them would put a
decision and an observation in one row and lose which was which.

**What is still missing:** the Mahāvyutpatti proper. It is Toh 4346 — in the Tengyur, which
this corpus does not hold — so the imperial lexicon itself waits on that acquisition.

### The reading dictionary (#24) — the Buddhist readings were already in Unicode

The task was scoped as "a general pinyin library gets Buddhist vocabulary wrong, so build
a dictionary of the exceptions." That framing turned out to be half right in a way worth
recording.

Unihan's `kMandarin` — the field a per-character library reads — gives **佛 as *fú***.
佛 occurs 533,670 times in the canon and is *fó*; the *fú* reading exists because 佛 is
common in 仿佛 *fǎngfú*, and kMandarin records the commonest reading, not the right one.
So the single most frequent character in Buddhist Chinese is misread half a million times
by any method that reads characters one at a time.

But `kHanyuPinyin` lists 葉 as `yè, shè`. `kXHC1983` lists 若 as `rě`. 般 is `bān, bō`.
**The Buddhist readings are in Unicode already** — spread across four fields nobody
consults. Nothing needed inventing. What needed recording is *which attested reading
applies to which form*, which is exactly what an exception table is, and it turned the
integrity rule into something checkable: **every syllable of every asserted reading must
appear in that character's attested set**, or it does not ship. The hand-curated file is
checked the same way, and an unattested syllable fails the build rather than entering the
corpus as a fact.

Result: 9,543 exceptions over a 44,348-character base, from two independent sources that
agree on 96.8% of compounds. On a 46-form test set covering 1,751,507 corpus occurrences,
per-character scores **50%**, the dictionary **100%**, breaking none of the 23 controls.

**Half the test set is forms the naive method gets right.** A set of only hard cases
would show that the dictionary fires, not that it fires in the right places — and a
dictionary that "corrected" 菩薩 or 涅槃 would be worse than none.

Four filters, each added because the unfiltered output contained that mistake:

1. **Polyphone ambiguity** (1,168 characters skipped). 說 is *shuō*, *shuì* and *yuè*;
   picking one without context is the guessing this table replaces. 佛 survives only
   because its other reading is glossed "used in 仿佛" — a fact about one word, not about
   the character.
2. **Neutral-tone erosion** (2,957 rejected). CC-CEDICT records modern *spoken* Mandarin,
   where 知識 is *zhī shi*. Twentieth-century speech is not evidence about a
   seventh-century text.
3. **Cross-source attestation** (401 rejected). The filter that makes the result
   trustworthy rather than merely sourced: two independent authorities have to agree.
4. **Corpus occurrence** — measured, not enforced. 3,172 of 9,543 forms occur in CBETA,
   covering 1,927,240 occurrences. Scoping the artifact to today's corpus would make it
   wrong the moment a corpus is added.

**And the parameter limit for the fourth time.** `Pramana.Batch` was extracted after the
second and documented after the third, and `Readings.store/1` still blew up — because it
had no batching at all and had simply never been handed enough rows to notice. Offering
`chunk/1` leaves every call site free to forget. `Batch.insert_all/4` takes the same
arguments as `Repo.insert_all/3` and cannot be called without batching; every unbounded
write path now goes through it, including two that were latent (`Parallels.store_anchors`
unbatched, `Parallels.store` with a hardcoded 5,000). **A shared helper only helps if
using it is easier than not.**

One more, on shape of work rather than data: the corpus-occurrence check was first
written as `LIKE '%form%'` per form against the pg_bigm index. It measured **1.3 seconds
each** — because proving a form is *absent* is the expensive case — which is 3.6 hours for
13,000 forms. One streaming pass over the corpus answers the same question in 2m11s.
Index-per-item beats a scan only when the items are few.
