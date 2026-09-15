# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 2

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## 4. The pipeline, end to end

Everything the system does with a text happens in this order. Each stage has a chapter
below.

```
   ┌──────────┐   the original files, downloaded once and hash-pinned
   │ ACQUIRE  │   → raw/  +  sources.lock.json
   └────┬─────┘
        │
   ┌────▼─────┐   parse messy publisher XML/JSON into one clean internal shape
   │NORMALIZE │   → IR (intermediate representation)
   └────┬─────┘
        │
   ┌────▼─────┐   cut into citable units, each with a real edition address
   │ SEGMENT  │   → segments  (5,185,767 rows)
   └────┬─────┘
        │
   ┌────▼─────┐   group segments into windows big enough to have meaning
   │  CHUNK   │   → chunks  (299,317 rows)
   └────┬─────┘
        │
   ┌────▼─────┐   turn each chunk's text into a list of numbers (a vector)
   │  EMBED   │   → embeddings (1024 numbers per chunk)
   └────┬─────┘
        │
   ┌────▼─────┐   a query comes in; find candidate passages
   │ RETRIEVE │   → ranked results, each with a URN
   └────┬─────┘
        │
   ┌────▼─────┐   re-fetch by URN and byte-compare the quotation
   │  VERIFY  │   → ok / mismatch / not found
   └──────────┘
```

The word **bake** refers to producing source text from recorded inputs. The current
database is mutable and holds one current bake; it is not a multi-snapshot store.
See [§17](05-16-licensing-and-why-it-is-a-column.md#17-the-integrity-machinery) and [the current architecture](../ARCHITECTURE.md).

---

## 5. Stage 1 — Acquire

### What "ingesting" means

**Ingesting** is the whole act of bringing an outside text into the system: downloading
it, parsing it, cutting it into addressable pieces, and storing those pieces in the
database. When this project says "the Pāli ingest," it means the run that took 7,288 JSON
files from SuttaCentral and turned them into 8,442 texts and 444,673 database rows.

Acquire is the first part: **get the files, and record exactly which files you got.**

### Pinning, and why

Sources change. CBETA revises its XML; SuttaCentral publishes corrections. If the corpus
silently follows those changes, then a citation that verified last month may fail today,
and nobody can tell whether the text changed or the code broke.

So every acquired file is recorded in **`sources.lock.json`** with its SHA-256 hash — a
64-character fingerprint that changes completely if a single byte of the file changes.
This is called **pinning**: the corpus is pinned to specific bytes.

```json
{
  "id": "sc",
  "pin": { "type": "git", "commit": "79b4910…", "sparse": "root/pli/ms" },
  "file_count": 7288,
  "files": [
    { "path": "root/pli/ms/sutta/mn/mn1_root-pli-ms.json",
      "sha256": "02ac9cf9…", "bytes": 5568 }
  ],
  "license": { "spdx": "CC-PDM-1.0", "class": "public-domain", … }
}
```

Two rules follow, and both have already caught real bugs:

- **`raw/` is append-only.** Downloaded files are never edited in place. If the original
  is wrong, the fix belongs in the normalizer, where it is visible in code review.
- **A partial run never writes the lockfile.** A `--limit 1` run once rewrote the
  SuttaCentral entry to claim the source was a single file, while 8,442 works sat in the
  database. A pin describing less than what was ingested is worse than no pin, because it
  *would verify*.

### Sparse checkout

SuttaCentral's repository is 910 MB. We need 57 MB of it. **Sparse checkout** is a Git
feature that downloads only named subdirectories:

```bash
git clone --depth 1 --branch published --filter=blob:none --sparse \
  https://github.com/suttacentral/bilara-data.git
cd bilara-data && git sparse-checkout set root/pli/ms translation/en
```

The `commit` in the pin plus the sparse paths make the acquisition exactly reproducible.

---

## 6. Stage 2 — Normalize

### The problem

Publishers use their own formats. CBETA ships **TEI XML** (Text Encoding Initiative, the
scholarly standard for marking up texts) that looks roughly like this:

```xml
<lb n="0037a13"/>爾時佛告<note place="inline">古本作世尊</note>舍利弗
<lb n="0037a14"/>汝已慇懃三請豈得不說<g ref="#CB01234"/>
```

SuttaCentral ships flat JSON:

```json
{ "mn1:1.1": "Evaṁ me sutaṁ— ", "mn1:1.2": "ekaṁ samayaṁ bhagavā…" }
```

Writing a separate segmenter, chunker and search path per format would be unmaintainable.

### The IR

**Normalization** converts each format into one internal shape, the **IR**
(*intermediate representation*). Everything downstream sees only IR, so adding a source
means writing one normalizer and nothing else.

An IR holds a work id, title, and a list of **lines**, each with:

- `anchor` — the edition's own address for this line (`0037a13`, or `1.1`)
- `text` — the words
- `notes` — interlinear editorial notes
- `apparatus` — variant readings from other manuscripts
- `gaiji` — rare characters (below)
- `juan` — which fascicle

### Things that make this harder than it sounds

**`<lb/>` is a line *boundary*, not a container.** In TEI, `<lb n="0037a13"/>` marks where
a printed line *begins*; text simply flows until the next one. So any element that
accumulates text — a note, a variant reading — can begin on one line and end on the next.
If you buffer such an element and attach it wherever it ends, everything in between loses
its address. This bug has been fixed **twice** here (once for `<lem>`, once for `<note>`),
the second time costing 10,590 printed lines that had no citable address. Hence the rule:
*any buffered element that can span a line boundary must be split at that boundary.*

**Gaiji** (外字, "outside characters") are characters that exist in the printed text but
have no Unicode codepoint — rare variant glyphs, mostly. CBETA marks them `<g
ref="#CB01234"/>` with a lookup table giving a description or composition. There are
133,049 of them in this corpus. They cannot be silently dropped: a passage missing a
character is a passage that will fail verification for reasons nobody can diagnose.

**A line with only a note still needs an address.** If a printed line carries nothing but
an editorial note, it is still a printed line, and the next line's address depends on it
existing. Dropping "empty" lines quietly renumbered things.

---

## 7. Stage 3 — Segment

### What a segment is

A **segment** is the smallest citable unit: one line of the printed edition, with its
address. Segmenting is cutting the IR into these units and computing, for each one:

| field | what it is | why |
|---|---|---|
| `urn` | the full citation address | how anything refers to it |
| `content` | the exact text | what gets quoted |
| `content_sha256` | hash of the text | detects any change, however small |
| `char_start` / `char_end` | offsets into the whole text body | lets a range be sliced out |
| `byte_start` / `byte_end` | the same in bytes | UTF-8: 1 character ≠ 1 byte |
| `page`, `register`, `line`, `juan` | the printed coordinates | so a human can check the book |
| `ordinal` | position within the text | ordering, and finding neighbours |

There are **5,185,767** of these. They are the atoms of the whole system.

### The rule that matters most

**Never invent citation IDs.** The address always comes from the tradition's own citation
grammar:

- Taishō: `p0037a13` — page, register, line, exactly as printed
- SuttaCentral: `1.1` — their segment id, verbatim
- A locally-added PDF with no canonical addressing: a **derived** address, explicitly
  flagged as derived so nobody mistakes it for a checkable page reference

Inventing our own numbering would make citations unverifiable against any physical book,
which would defeat the point of the project.

For the Pāli, `page`, `register` and `line` are **null** — that edition has no printed
page in this sense. Manufacturing coordinates would be inventing something a reader
cannot check.

---

## 8. Stage 4 — Chunk

### What "chunking" means

A **chunk** is a window of consecutive segments, grouped together so that the text has
enough context to be *searchable by meaning*.

### Why segments are the wrong unit for search

A Taishō segment is one printed line — **18.2 characters on average**. The break is
typographic, not grammatical: the line ends where the column ends, mid-word if necessary.
In the Lotus Sūtra the name 阿若憍陳如 (Ājñātakauṇḍinya, one of the first five disciples)
splits across two lines as `…阿若憍` / `陳如…`.

Search by meaning on such a line is searching half a name. So chunks group ~15–20
consecutive segments into a window of about 300 characters — a real passage.

### The property that keeps chunks honest

A chunk's address is a **range URN** covering its members:

```
pramana:cbeta.T:T0262_009@p0037a13-p0037b02
```

Because that range is built from real edition anchors and not invented, a search hit is
verifiable by exactly the same machinery as a direct lookup. The chunk is a retrieval
convenience that never becomes a citation fiction.

Chunks stop at juan boundaries — a window spanning two fascicles would describe a passage
no printed edition contains — and they do not overlap.

### A size is a per-script decision

300 characters is right for Literary Chinese, where 300 characters is a substantial
passage. It is **wrong for Pāli**, where 300 Latin characters is a sentence fragment. The
same limit applied to both would silently under-chunk the Pāli. Chunk size therefore
belongs to the script, not to the system.

---

## 9. Stage 5 — Embed
