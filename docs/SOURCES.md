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
terms already granted, and stating the use. Until then:

- The 56–84 provenance rule is implemented and tested
  (`Pramana.URN.Taisho.provenance_for_volume/1`), so the material classifies itself
  correctly the moment it arrives.
- `Pramana.Coverage` states the gap in every survey response, so the absence cannot be
  mistaken for the Japanese tradition being silent.

### SuttaCentral `bilara-data` (Pali)
- `https://github.com/suttacentral/bilara-data` — **CC0, public domain**
- ~444k segments, already segment-aligned root ↔ translation
- Also grab `sc-data`: thousands of **hand-curated Āgama↔Nikāya parallels**. This is
  curated scholarship, free — ingest it instead of rediscovering it with embeddings.
- Segment IDs (`mn1:1.1`) are the field standard. Adopt them verbatim.

## Tier 2 — Structured but partial

### 84000 (Tibetan → English)
- `https://github.com/84000` — TEI, plus an API
- Kangyur/Tengyur translations, Toh numbers, Derge folio references
- Ships a **Skt–Tib–Eng glossary** — a direct cross-lingual anchor for alignment
- Coverage is partial and growing; treat completeness as a moving target

### OpenPecha / Adarsha / Esukhia (Tibetan)
- The actual Tibetan-language **etext**, openly licensed
- This — not BDRC — is where retrievable Tibetan text comes from

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
