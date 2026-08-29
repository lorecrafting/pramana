# Primer: What This System Is, How It Works, and What Everything Is Called

A ground-up guide for someone new to the project. No prior knowledge assumed — not of
Elixir, not of search engines, not of Buddhist textual studies. Read top to bottom the
first time; after that, use the [glossary](#20-glossary) as a lookup.

Everything here describes **this repository as it actually is**, with real numbers. Where
something is planned rather than built, it says so.

---

## Table of contents

1. [The one-sentence version](#1-the-one-sentence-version)
2. [The problem this exists to solve](#2-the-problem-this-exists-to-solve)
3. [The corpus: what texts are we talking about](#3-the-corpus-what-texts-are-we-talking-about)
4. [The pipeline, end to end](#4-the-pipeline-end-to-end)
5. [Stage 1 — Acquire](#5-stage-1--acquire)
6. [Stage 2 — Normalize](#6-stage-2--normalize)
7. [Stage 3 — Segment](#7-stage-3--segment)
8. [Stage 4 — Chunk](#8-stage-4--chunk)
9. [Stage 5 — Embed](#9-stage-5--embed)
10. [Stage 6 — Retrieve](#10-stage-6--retrieve)
11. [Stage 7 — Resolve and verify](#11-stage-7--resolve-and-verify)
12. [Addressing: the URN scheme](#12-addressing-the-urn-scheme)
13. [Provenance: who made this text and when](#13-provenance-who-made-this-text-and-when)
14. [Layers: translations and readings](#14-layers-translations-and-readings)
15. [Parallels: the same discourse in two languages](#15-parallels-the-same-discourse-in-two-languages)
16. [Licensing, and why it is a column](#16-licensing-and-why-it-is-a-column)
17. [The integrity machinery](#17-the-integrity-machinery)
18. [The technology stack](#18-the-technology-stack)
19. [How to actually run things](#19-how-to-actually-run-things)
20. [Glossary](#20-glossary)
21. [Where to read next](#21-where-to-read-next)

---

## 1. The one-sentence version

**Pramāṇa is a search system over the Buddhist canon where every quotation can be
mechanically proven to exist, in that exact form, at that exact place in a real printed
edition — and where a Japanese-composed commentary can never be handed back as if it were
an Indian sūtra.**

The name is Sanskrit: *pramāṇa* (प्रमाण) means "valid means of knowledge" — the branch of
Indian philosophy concerned with how we know a claim is true. That is the whole design
brief in one word.

---

## 2. The problem this exists to solve

### 2.1 Why not just use ChatGPT?

Ask any large language model for a Buddhist scripture quotation and it will give you one.
It will be fluent, plausible, correctly formatted, and attributed to a specific text and
page. It will also, quite often, be **invented** — the passage does not exist, or exists
in different words, or exists in a completely different text.

This is not a bug that better models fix. A language model generates text that *looks
like* what should come next. A citation that looks right is exactly what it is built to
produce. There is no internal step where it checks.

For most subjects a wrong quotation is an inconvenience. Here it is the whole problem:
people make decisions about how to live based on what they believe the Buddha said. A
fabricated quotation with a real-looking citation is worse than no answer, because it
carries the authority of a source without the substance of one.

### 2.2 The two failure modes

**Fabrication.** The citation points at nothing, or the words are altered. The subtle
version is the dangerous one: a real passage, real citation, one word changed.

**Flattened provenance.** This one is specific to this corpus and much less obvious. The
Buddhist canon in Chinese contains, side by side in the same printed collection:

- Sūtras translated from Indian originals in the 2nd–8th centuries
- Chinese-composed treatises
- **Chinese-composed texts presenting themselves as translations from Sanskrit**
  (疑偽經, "doubtful and spurious scriptures" — apocrypha)
- Japanese sectarian commentaries written in the 13th–19th centuries

They look alike. They are printed alike. A naive search returns them alike. So a user asks
"what does Buddhism say about X", and gets a 14th-century Japanese Pure Land polemic
presented as scripture, with a correct citation. Nothing was fabricated. The result is
still profoundly misleading.

### 2.3 The response

Three commitments, which explain nearly every design decision in the codebase:

1. **Every citation is mechanically re-resolvable.** A URN goes in, the exact bytes come
   out, and the quoted text is byte-compared. The model is never trusted to cite
   correctly; a separate deterministic component checks it afterwards.
2. **Provenance is structural, not a note.** Where a text was composed, what role it plays,
   and how confident we are are separate typed fields that travel with every result and
   cannot be flattened by a caller.
3. **We refuse to guess.** When the data does not support a claim, the system returns
   `nil` rather than a plausible value. You will see this everywhere: readings that say
   "the ordinary reading is wrong" without saying what is right, volumes whose provenance
   is deliberately unattributed, licences recorded as "unknown" rather than assumed.

---

## 3. The corpus: what texts are we talking about

You do not need to be a Buddhologist to work on this, but a few names recur constantly.

### 3.1 The Chinese canon and the Taishō

The **Taishō Shinshū Daizōkyō** (大正新脩大藏經, "Taishō Revised Tripiṭaka") is a
100-volume edition of the Chinese Buddhist canon published in Tokyo between 1924 and 1934.
It is the standard scholarly reference edition — when an academic paper cites a Chinese
Buddhist text, it cites Taishō volume, page, register, and line.

Its citation format looks like `T0262_009, 37a13`:

| part | meaning |
|---|---|
| `T` | Taishō |
| `0262` | text number 262 — the Lotus Sūtra |
| `009` | fascicle (juan) 9 |
| `37` | printed page 37 |
| `a` | register — each page has three horizontal bands, a / b / c |
| `13` | line 13 within that register |

**This is a real, physical address.** You can pull volume 9 off a library shelf, turn to
page 37, look at the top third, count down 13 lines, and see the characters. That
verifiability is the foundation everything else is built on — which is why the system
adopts this addressing rather than inventing its own.

**Juan** (卷, "fascicle" or "scroll") is a division inherited from when texts were written
on scrolls. A long sūtra is divided into juan the way a book is divided into chapters.

### 3.2 CBETA

**CBETA** (Chinese Buddhist Electronic Text Association, 中華電子佛典協會) is a Taiwanese
non-profit that has digitised the Taishō and other collections into scholarly XML. This is
the source of the Chinese material here: **2,471 works, 4,740,246 segments, 90.6 million
characters**, all with their Taishō page/register/line markers preserved.

CBETA covers Taishō volumes 1–55 and 85. It **excludes volumes 56–84**.

### 3.3 SAT, and the gap

**SAT** (the SAT Daizōkyō Text Database, University of Tokyo) publishes the volumes CBETA
does not — 56–84, which are precisely the **Japanese-composed sectarian works**: Tendai,
Shingon, Zen, Pure Land, Nichiren commentaries.

So the one part of the canon most likely to be mistaken for scripture is the part hardest
to obtain. SAT has no bulk download. An email requesting access has been sent and is
unanswered. Until then the system **states the gap in every survey response**, because if
it silently returned nothing, an absence of Japanese results would read as the tradition
having nothing to say.

That is tracked as task #14, with #41 covering a safe partial step: ingesting the
*catalogue* (work numbers, titles, authors — bibliographic facts, not the text) so the
corpus can say "this exists and we do not hold it" rather than showing a silent hole.

### 3.4 The Pāli canon and SuttaCentral

The **Pāli Canon** (Tipiṭaka, "three baskets") is the scripture collection of Theravāda
Buddhism, preserved in Pāli, an ancient Indian language. Its major divisions:

| division | what it is |
|---|---|
| **Dīgha Nikāya** (DN) | "long discourses" |
| **Majjhima Nikāya** (MN) | "middle-length discourses" |
| **Saṁyutta Nikāya** (SN) | "connected discourses" |
| **Aṅguttara Nikāya** (AN) | "numerical discourses" |
| **Khuddaka Nikāya** | "minor collection" — includes the Dhammapada |
| **Vinaya** | monastic rules |
| **Abhidhamma** | systematic philosophy |

**SuttaCentral** is a project that publishes the Pāli canon plus translations, with a
citation scheme the field now uses: `mn1:1.1` means Majjhima Nikāya sutta 1, segment 1.1.
Its data lives in a repository called **bilara-data**, which is *segment-aligned*: the
Pāli and its English translation are broken into matching numbered units, so `mn1:1.1` in
the Pāli file and `mn1:1.1` in Sujato's English file are the same sentence.

This corpus holds **8,442 Pāli works, 444,673 segments**, and **210,756 English renderings
by 8 translators**.

**Sutta** (Pāli) = **sūtra** (Sanskrit) = a discourse attributed to the Buddha. The
Chinese **Āgama** collections are translations of an early Indian collection closely
related to the Pāli Nikāyas — which is why the same discourse often exists in both, and
why [parallels](#15-parallels-the-same-discourse-in-two-languages) matter so much.

### 3.5 Current size

| | |
|---|---|
| Texts | 10,914 |
| Segments (citable units) | 5,185,767 |
| Chinese works (CBETA) | 2,471 |
| Pāli works (SuttaCentral) | 8,442 |
| Locally-added texts | 1 |
| Retrieval chunks | 299,317 (Chinese; Pāli in progress) |
| Curated parallels | 407,176 (24,717 resolvable at both ends) |
| English renderings | 210,756 by 8 translators |
| Reading exceptions | 22 |

---

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

The word **bake** refers to running this pipeline over the whole corpus to produce a
finished, immutable dataset. See [§17](#17-the-integrity-machinery).

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

### Vectors, from scratch

An **embedding** is a list of numbers representing a piece of text's meaning. In this
system each chunk becomes **1,024 numbers** — a point in 1,024-dimensional space.

The useful property: **texts that mean similar things land near each other**, even with no
words in common. "The cessation of suffering" and 苦滅 land close together despite sharing
no characters and not even a writing system.

To compare two texts you compare their vectors arithmetically. This project uses **inner
product**, one of several standard distance measures; the vectors are normalised, which
makes inner product equivalent to cosine similarity but cheaper.

### The model

**BGE-M3** is the embedding model — a neural network that takes text and returns those
1,024 numbers. It is multilingual, which is why it can place Chinese and English near each
other at all.

Two honest limits, stated in the code:

- BGE-M3 is **not specifically trained on Literary Chinese**. Whether it is the right
  model here is an open question, and turning that opinion into a measurement is exactly
  what the Phase 4 evaluation harness (#19) is for.
- **Vectors from different models cannot be mixed.** Every value is a valid float; nothing
  fails loudly; ranking silently corrupts. The model id is stored with every vector and
  mismatches are refused.

### Why a GPU, and the export/import round trip

Embedding 299,317 chunks on a laptop takes roughly 65 hours. On a rented **L4 GPU** via
**Modal** (a service that runs code on cloud GPUs on demand) it takes **34 minutes and
about $0.45**.

Rather than ship the corpus and a database to the GPU, the system exports **text** and
imports **vectors**:

```
export  chunks → JSONL file of {id, content, sha256}
        ↓ (upload)
remote  run BGE-M3 → JSONL of {id, vector}
        ↓ (download)
import  re-check sha256 → write vectors
```

The sha256 re-check is the point. If the corpus were re-baked between export and import,
the text a vector was computed from no longer exists, and that vector is **wrong for the
chunk it claims to describe** — while looking completely normal, because it is still 1,024
valid floats. Check, refuse, and report which rows disagreed.

### Multi-vector embeddings (in progress, #40)

A chunk can carry more than one vector:

| kind | what it is | status |
|---|---|---|
| `source` | the passage as printed | built |
| `translation` | the same span in English, one per translator | being built |
| `question` | hypothetical questions the passage answers | deferred to Phase 7 |

The reason is the system's weakest axis: **an English question reaching Literary Chinese**
depends entirely on the multilingual model's cross-language space, which is unproven here.
Embedding the English translation alongside gives the English query an English target,
while the result still resolves to the original-language anchor. `question` vectors would
need an LLM generation pass over 300k+ chunks; spending that before there is an evaluation
harness to measure whether it helps would be spending blind.

---

## 10. Stage 6 — Retrieve

There are two ways to find a passage, and they fail in opposite directions.

### 10.1 Lexical search — matching characters

Find passages containing the characters you typed. Fast, exact, and explainable.

Literary Chinese has no spaces between words, so the usual "split on whitespace" indexing
does not apply. The system uses **pg_bigm**, a PostgreSQL extension that indexes every
**bigram** (adjacent character pair). 佛性 is indexed as itself; a search for it finds
every passage containing those two characters adjacently.

**Where it fails:** 佛性 ("buddha-nature") will not match 如來藏 ("tathāgata-garbha") even
though they name the same doctrine. And a query in the wrong orthography returns nothing
at all — which is why there is **variant-character normalization**: 眾/衆/众 are the same
character in different historical forms, and a query using one form must find passages
using another. The system holds 6,447 variant classes derived from the Unicode Han
database. Before that existed, searching 众生 returned 0 results where 眾生 returned
thousands, silently.

### 10.2 Semantic search — matching meaning

Embed the query, then find the chunks whose vectors are nearest.

Comparing against all 299,317 vectors exactly would be slow, so pgvector builds an
**HNSW** index (*Hierarchical Navigable Small World*) — a graph structure that finds
approximate nearest neighbours very fast. This is called **ANN**, approximate nearest
neighbour: you trade a small chance of missing a result for a very large speed gain.

**The trap this project hit:** if you ask an ANN index for 20 results and *then* filter
them (say, to one division of the canon), you may be left with 3, because the index found
20 globally-nearest neighbours and 17 were filtered away. It looks like the corpus has 3
matches. It doesn't. The fix is pgvector 0.8's **iterative scan**
(`hnsw.iterative_scan = relaxed_order`), which keeps walking the graph until it has enough
results that survive the filter. Any query combining a vector ordering with a selective
`WHERE` needs this, and it will keep being true as the corpus grows.

### 10.3 Hybrid — using both

Lexical is precise but literal; semantic is flexible but fuzzy. **Hybrid search** runs
both and merges the rankings using **RRF** (*Reciprocal Rank Fusion*).

RRF is deliberately simple: for each result, score `1 / (k + rank)` in each list, with
`k = 60`, then add the scores. A passage ranked #1 by lexical and #30 by semantic beats one
ranked #10 by both. Crucially it uses only **ranks**, never the raw scores — so it does not
matter that a bigram similarity and an inner product are not on comparable scales.

Hybrid is the default entry point. A real example: querying 眾生皆能成佛 ("all beings can
become buddhas") — a paraphrase appearing nowhere as a literal string — returns
故眾生無不成佛 at 0.817 similarity. The bigram index structurally cannot find that.

---

## 11. Stage 7 — Resolve and verify

### Resolve

**Resolution** is turning a URN back into the passage it addresses. Give
`pramana:sc.ms:mn1@1.1`, get back `Evaṁ me sutaṁ—` with its hash, offsets and provenance.

### The citation guard

The **guard** is the component that makes the whole project's promise real. It:

1. extracts every URN from a block of generated text
2. re-resolves each one against the corpus
3. **byte-compares** any quoted text against what is actually there

It runs **after** generation and **outside** the model. Nothing about it depends on which
model produced the text, so it works identically for any model, now or later.

The comparison is exact after trimming whitespace — deliberately not fuzzy. "Close
enough" is exactly how a misquotation survives review.

Its verdicts:

| verdict | meaning |
|---|---|
| `:ok` | the URN resolves and the quote is really there |
| `:bad_urn` | malformed address |
| `:not_found` | well-formed, but addresses nothing — do not cite it |
| `:quote_mismatch` | the passage exists; the words are not what was claimed |
| `:not_citable_as_source` | it is a machine translation being presented as scripture |

It also reports `existence_only` — citations with no recognisable quotation were checked
only for *existence*, which is a materially weaker guarantee, so it is never folded into
"verified".

**What it deliberately does not do:** judge whether a citation *supports* the claim it is
attached to. That is interpretation. The guard answers only the mechanical question, and
its value lies in that answer not being fuzzy.

---

## 12. Addressing: the URN scheme

A **URN** (Uniform Resource Name) is a permanent identifier. This project's grammar:

```
pramana:<source>.<witness>:<work>[@<locator>[-<locator_end>]][#tr:<lang>/<translator>]
```

Examples:

```
pramana:cbeta.T:T0262_009@p0037a13                 Lotus Sūtra, juan 9, page 37a line 13
pramana:cbeta.T:T0262_009@p0037a13-p0037b02        a range, verified as one unit
pramana:sc.ms:mn1@1.1                              Majjhima Nikāya 1, segment 1.1
pramana:sc.ms:mn1@1.1#tr:en/sujato                 Sujato's English *of* that segment
pramana:local-huang-nianzu-jie:jie@sec12.p3        a locally-added commentary
```

| component | meaning |
|---|---|
| `source` | who published the data — `cbeta`, `sc`, `sat`, `local-…` |
| `witness` | which physical edition — `T` (Taishō), `ms` (Mahāsaṅgīti) |
| `work` | the text's own identifier |
| `locator` | the address within the work, in the tradition's own grammar |
| `#tr:…` | a *rendering* fragment — see below |

A **witness** is a manuscript or printed edition testifying to a text. The same work
survives in several, and they differ. Naming the witness in the address means a citation
says not just "the Lotus Sūtra" but "the Lotus Sūtra as printed in the Taishō".

### Why translations are a fragment

A translation is addressed as `<anchor>#tr:en/sujato` — a fragment *hanging off* a source
address, never a top-level URN of its own.

This is structural enforcement of the rule that **a translation is never citable as a
source**. Strip the fragment and you are holding a real source citation. There is no way
to hold a rendering alone, so there is no way to accidentally present one as the text.

### Addressing levels

| level | meaning |
|---|---|
| `canonical` | the tradition's own citation scheme (Taishō lines, SuttaCentral segment ids) |
| `edition_page` | a printed page in a specific modern edition |
| `derived` | we made it up because the source has no citation scheme — flagged as such |

`derived` is never allowed to look like `canonical`. The promise of the URN scheme is that
a citation can be checked against a physical page; where it cannot, the result must say so.

---

## 13. Provenance: who made this text and when

**Provenance** means origin — the history of where something came from. Here it is a set
of separate typed fields on every text, and they travel into every search result.

| axis | values | question it answers |
|---|---|---|
| `composition_origin` | `indic`, `chinese`, `japanese`, `korean`, `tibetan`, `unattributed` | Where was this actually *composed*? |
| `text_role` | `root`, `commentary`, `sub_commentary`, `treatise`, `ritual`, `catalogue` | Is this scripture or someone's explanation of it? |
| `attribution_confidence` | `certain`, `probable`, `disputed`, `apocryphal` | How sure is the field? |
| `addressing` | `canonical`, `edition_page`, `derived` | Can a human check this against a book? |

The axes are **separate on purpose**. A Chinese-composed apocryphal sūtra is
`origin: chinese` + `role: root` + `confidence: apocryphal`. Collapsing those into one
"type" field would lose exactly the distinction that matters.

For the Chinese canon these are populated from the Taishō's own **division** (部) table —
the editors' own classification of the 100 volumes into sections like 阿含部 (Āgama
section), 般若部 (Prajñāpāramitā section), 疑似部 (doubtful/spurious section). That gives
**1,781 Indic works, 555 Chinese, 135 deliberately unattributed, and 57 flagged apocrypha**.

Search results arrive **in buckets keyed by these axes**, each labelled in plain language
("Japanese-composed commentary"), so a caller cannot flatten them by accident.

The 135 "deliberately unattributed" are the 古逸部 (Dunhuang manuscripts and recovered
texts) — where the honest answer is that nobody knows, and the function that supplies
provenance returns `nil` rather than a guess.

### 13.1 A byline is not a person

Those four axes say what *kind* of text this is. They do not say who made it, and the field
that looks like it does — `attributed_author` — is a **byline**: the string the edition
printed. `劉宋 求那跋陀羅譯`, `宋 求那跋陀羅譯`, `劉宋 天竺三藏求那跋陀羅譯`. Three strings,
one man. Search the text for any of them and you find a third of his work.

So bylines are linked to **DILA's person authority** (CC BY-SA 3.0, ~49,000 people), and the
id — not the string — is the identity. `provenance.authority_id` rides on every passage, and
`get_works_by_person` takes it.

**The rule for linking, and what it refuses.** A byline matches when it contains an authority
name of two or more characters, longest first, **and the dynasty agrees**. That last clause
costs 21 points of coverage and buys the number its meaning: an earlier version checked the
dynasty only when a name was ambiguous — reasoning that a unique name needs no
disambiguation — and linked `宋 道隆述` to a *Tang* 道隆, which is precisely the
coincidence-of-characters case the check exists to refuse. **Whether a name is ambiguous says
nothing about whether the match is right.**

Roughly 40% of bylines link to nobody, and that is a **refusal, not a gap**: they name someone
the authority does not record under that spelling, name several people at once, or carry a
dynasty no namesake shares. A wrong link merges two people permanently, and every later
question about "the same translator" inherits the error silently. No link is ever `certain` —
the name is certainly in the byline; that it denotes *this* person rather than an unrecorded
namesake is an inference.

### 13.2 What an identity buys: dates, lineage, place

Once a byline is a person, three things follow, and each carries a caveat that is part of the
answer rather than a footnote to it.

**Dates are bounds, not dates.** A work's `date_start`/`date_end` come from the attributed
person's lifespan, so they answer *which century* and never *which year* — Amoghavajra was
born in 705 and did not translate at birth. `date_basis` records where a date came from, and
a CHECK constraint makes a date without a basis unrepresentable. Where only one end of a life
is recorded, only one end is stored: half a bound is stored as half a bound, because
`772 – 772` reads as "made in 772" and means "made no later than 772".

`search` filters on this with `composed_after` / `composed_before`, and **the filter reaches
1,515 works of 17,281**. Every dated search returns that denominator, because an undated work
is *unaddressed* by the filter, not excluded on evidence.

**Lineage is reported, never inferred.** Teacher and student come from DILA and carry the
source that states them. Nothing here derives a relationship from shared dates, shared sect,
or co-occurrence in a text — inferred lineage is how a scholarly claim gets manufactured out
of a coincidence. A chain can branch, and it can **cycle**, because sources disagree about who
taught whom and the authority records the disagreement. A cycle is data; walking it forever is
the bug.

**A place resolves into two region schemes.** `place_id` resolves against ~59,000 imported
places into a modern administrative path (`中國-浙江省-杭州市-下城區`) *and* a historical
region — 江南東道, a Tang circuit. The second is the one a scholar means by "a Jiangnan
translator", because that is a claim about the Tang and says nothing about Zhejiang. The
person authority's own spelling of the place is kept beside the resolved record rather than
corrected against it: two files, maintained separately, allowed to disagree.

One trap worth knowing if you ever touch that data: DILA publishes `<geo>` as **longitude
first**, which is the reverse of TEI's own convention. Read as documented, every place in this
corpus lands in the Arctic Ocean.

---

## 14. Layers: translations and readings

The governing idea: **a source text is a spine; everything else is a layer keyed to its
anchors.** Translations, pronunciations, notes and alignments are all annotations over the
same addresses — never separate documents.

### 14.1 The translation pool

There has never been "the" English translation of this material. The Chinese canon
contains 2–6 translations of the same Sanskrit work (異譯本, "alternative translations" —
the Lotus Sūtra exists three times). SuttaCentral carries Sujato, Brahmali, Patton and
others on overlapping suttas.

So the schema holds a **pool**, and callers supply a **selection policy** rather than
expecting one answer. Model disagreement is not a new problem introduced by LLMs; it is
the normal condition of the field, and the machinery built for the human case handles the
machine case unchanged — a human translator and a model are the same kind of row,
differing only in metadata.

**Tiers**, which say what it costs to trust a rendering:

| tier | what | reproducible | citable as |
|---|---|---|---|
| **T0** | a human translator | yes | a person |
| **T1** | generated during a bake, with a pinned model + prompt + glossary | yes | a model + config |
| **T2** | generated at query time | no | provisional |

**No tier is citable as *source*.** A rendering is always evidence of how someone read the
passage, never evidence of what the passage says.

A selection policy looks like:

```elixir
Translations.select(anchor,
  lang: "en",
  prefer: ["t0", "t1", "t2"],   # tier order
  translator: "sujato",          # or pin one explicitly
  mode: :compare,                # return the whole pool, not one
  redistributable_only: true
)
```

It always reports `alternatives` — how many renderings were **not** shown. A passage with
four English translations displayed as one reads as a passage with one.

### 14.2 The reading layer

**Readings** are pronunciations: pinyin for Chinese, Wylie for Tibetan, on'yomi for
Japanese, IAST for Sanskrit and Pāli.

These are **computed at render time, never stored per character** — a pronunciation for
every character of a 250-million-character corpus is billions of rows of derivable data.
What is *not* derivable is the exceptions, and those are what the table holds.

The reason exceptions are a required asset rather than a nicety: a general pinyin library
mis-reads Buddhist vocabulary **confidently**, because transliterated Sanskrit follows
conventional readings that ignore the characters' ordinary values.

| written | correct | what a naive library says |
|---|---|---|
| 般若 | bōrě | *bānruò* |
| 南無 | námó | *nánwú* |
| 迦葉 | jiāshè | *jiāyè* |

They cluster in exactly the passages a reader most wants help with. The same problem
recurs in Japanese, where Buddhist texts use 呉音 *go-on* readings rather than 漢音
*kan-on* (経 is *kyō*, not *kei*).

And names in Chinese characters are frequently **not Chinese**: 元曉 is the Korean monk
Wŏnhyo, not "Yuánxiǎo"; 道隱 is the Japanese Dōin, not "Daoyin".

Crucially, a row may **decline to give a reading**: `status: "unverified"` with no reading
records that the ordinary reading is wrong *without inventing a replacement*. Twelve of
the twenty-two seeded rows are exactly this.

---

## 15. Parallels: the same discourse in two languages

The Chinese **Āgamas** and the Pāli **Nikāyas** descend from a shared early Indian
collection. The same discourse often survives in both, sometimes with revealing
differences. Identifying those correspondences is decades of comparative scholarship.

SuttaCentral publishes **388,074 hand-curated relations** between texts in Chinese, Pāli,
Sanskrit and Tibetan. This project ingests them rather than approximating them with
embeddings — an embedding could guess at this and would be worse, unexplainable, and
unattributable.

**The relation type is a claim about strength**, and is never flattened into "related":

| relation | count | meaning |
|---|---|---|
| `full` | 353,874 | a full parallel |
| `resembling` | 22,512 | resembles without being a parallel |
| `sections` | 10,834 | a section corresponds |
| `mentions` | 730 | mentions in passing |
| `retells` | 124 | retells the story |

Flattening these would let a passing mention be presented as a parallel.

Of 407,176 stored pairs, **24,717 resolve at both ends** — meaning we hold both texts and
can quote both. So SA 1 (Chinese, `T0099`) and SN 22.12 (Pāli) can be put side by side,
each independently verifiable.

---

## 16. Licensing, and why it is a column

The project's posture is: **we publish the pipeline, not the corpus.** Different sources
come with genuinely different terms, and those terms have to be enforceable by a query —
not remembered by a person.

| source | licence | may we republish? |
|---|---|---|
| CBETA | non-commercial | **no** |
| SuttaCentral Pāli root | Public Domain Mark | yes |
| SuttaCentral translations | mostly CC0, one CC BY-SA 3.0 | yes, with obligations |
| locally-added modern commentary | in copyright | **no** |

So `license_class` and `redistributable` are structured columns, and any public surface
sets `redistributable_only: true` once and then *cannot* serve restricted content by
accident.

Three lessons already learned here, each the hard way:

- **A source's own LICENSE file is not the licence.** bilara-data's LICENSE.md says CC0
  throughout; its own publication metadata records Public Domain Mark for the Pāli root
  text and CC BY-SA 3.0 for one translation. Licence belongs to the *publication*.
- **What we believe and what we will act on are two columns.** Where a rendering's exact
  publication cannot be identified, the licence is inferred from its siblings — good
  enough to hold and search under, not good enough to republish on. `license_class` says
  the first; `redistributable` says the second.
- **A declared filter that does nothing is worse than no filter.** `license_class` was
  recorded and displayed from the start, which made it *look* enforced, while nothing
  could actually filter on it. Every declared filter now has a test proving it changes the
  result set.

---

## 17. The integrity machinery

### The bake

A **bake** is an immutable snapshot of the corpus, identified by

```
bake_id = sha256(sources.lock + pipeline_version + config)
```

Same inputs → same id → same corpus. It appears in every tool response, so an answer can
be tied to exactly the dataset that produced it.

This is why query-time generated translations are **never** written into the baked pool:
if they were, two people with the same `bake_id` would have different corpora, and
reproducibility would quietly die.

### Two different checks, and the distinction between them

This is one of the most useful ideas in the project.

**`mix pramana.verify`** re-runs the pipeline from `raw/` and byte-compares the result
against what is stored. It proves **reproducibility**: the bake is a deterministic
function of pinned inputs.

**`mix pramana.integrity`** counts what is in the *source files* against what is in the
database — every `<lb/>` marker, every gaiji. It proves **completeness**: nothing printed
was lost.

> **Reproducibility is not fidelity.** If the pipeline drops something on every run, it is
> absent from both sides of `verify` and the check passes happily. Only counting against
> the source catches loss.

Both are required at a phase gate, and both are green over the whole corpus. This document
deliberately quotes no text or segment count: the last one written here went stale within
two ingests, and `Pramana.Inventory.snapshot/0` computes it.

### The gate: CI for a dataset, not just for code

Ordinary CI answers *does the code work*. Here the deliverable is a dataset of millions of
segments, so there is a second question — *is the data still what it claims to be* — and it
needs different checks entirely.

`mix pramana.gate` is all of them as one command, **ordered cheapest-first and halting at
the first failure**, so a formatting error costs two seconds rather than being discovered
after the eval run.

It runs in **stages**, because most of the ordering in a checklist is an artefact of the
order somebody typed it in rather than a real dependency: `credo` does not read `dialyzer`'s
output, and `integrity` does not read `verify`'s. Only three orderings here are real —
`format` alone first because it is two seconds and fails often; `compile` alone next because
everything after it assumes built beams *and* because concurrent `mix` invocations in one
`MIX_ENV` contend on the build lock; and `evals` alone last, because an eval run **is** the
measurement and contention invalidates its timings. Everything between those fans out.
A stage runs every one of its steps even after one fails, and reports them all, so three
broken cheap checks are seen in one pass rather than across three runs.

**Code checks — about a minute in total:**

| step | what it answers |
|---|---|
| `format --check-formatted` | costs nothing, fails often, so it goes first |
| `compile --warnings-as-errors --force` | warnings are failures. `--force` because incremental compilation will not re-emit a warning in a file it did not rebuild |
| `credo --strict` | style and consistency linting |
| `deps.audit` | known CVEs in dependencies |
| `test --cover` | the suite, plus the coverage ratchet described below |
| `dialyzer` | static analysis of the BEAM: unreachable clauses, impossible patterns. It found a defensive `parse_date(nil)` clause that could never match, because `Regex.run/2` yields `""` for a capture group that did not participate, never `nil` |

**Data checks — most of an hour:**

| step | what it answers |
|---|---|
| lockfile | every file `sources.lock.json` records still exists in `raw/` with a matching sha256 — for **every** source, not the one just touched |
| `verify --all` | re-normalize every text from `raw/` and byte-compare: the pipeline is **deterministic** |
| `integrity` | count against the *source files*: nothing printed was **lost** |
| `evals --gate` | 1,472 gold retrieval questions scored against a committed `evals/baseline.json` |

Steps 8 and 9 are the pair described above, and running only the first is how a real defect
survived a passing gate. The lockfile check is there because *both* of them work from paths
recorded at ingest, and stay green when the lockfile itself is wrong — where "wrong"
includes incomplete, which is exactly how the Taishō's 2,471 file records went missing while
every check stayed green.

**Why one command.** `docs/CHECKS.md` specified this as a list a person had to remember. The
CBETA X ingest shipped with `verify` green and `integrity` never executed — and integrity
had been failing on 1,228 texts the whole time. Nobody skipped it on purpose; it was one
more command at the end of a long day.

`--from <step>` resumes after a fix without repaying for the steps that passed, and
`--quick` runs the code half only.

### Test coverage, and the ratchet

**Coverage** is the fraction of your code that runs at least once while the test suite
executes. Elixir measures it with `mix test --cover`: it instruments every module, runs the
tests, and reports the percentage of lines each module executed. 100% would mean no line
went untouched.

Coverage is a **negative** signal, and it is worth being precise about why. High coverage
does not mean the code is correct — a test that calls a function and asserts nothing still
marks every line as covered. But *low* coverage is conclusive: those lines have never run
in any test, so nothing at all is known about them. It tells you where you are blind, not
where you are safe.

A **ratchet** is what turns that measurement into a standard. You record a minimum in
`mix.exs`:

```elixir
test_coverage: [
  summary: [threshold: 83],
  ignore_modules: [~r/^Mix\.Tasks\./, ...]
]
```

Mix fails the run when coverage falls below it. The rule attached to it is one-directional:
**raise it when coverage rises; never lower it to make a run pass.** That asymmetry is the
whole mechanism. Coverage can only go up, one gate at a time, and no individual commit can
buy itself an exception. `pramana_web` climbed 82 → 91 → 92 → 93 that way, one gate each.

`ignore_modules` matters as much as the number. 90% is Mix's default and this umbrella
cannot honestly hold it: CLI shells over already-covered domain functions, OTP application
callbacks, and NIF stubs whose Elixir bodies are *replaced by Rust at load time* and can
never execute. Excluding those and defending a real number beats a threshold nobody can
meet — a standard people cannot reach is one they learn to route around.

Two traps, both of which this project fell into:

**The option nests.** `test_coverage: [threshold: n]` is silently ignored; it must be
`test_coverage: [summary: [threshold: n]]`. Written the wrong way it looks configured and
Mix goes on applying its own default.

**A threshold nothing runs is a comment.** `docs/CHECKS.md` called a coverage regression a
gate failure from the beginning, and the ratchet was raised at four real gates. But when
`mix pramana.gate` became the way the suite is run, its test step was plain `mix test` — no
`--cover`. Over the following phases `pramana_web` fell from **93% to 77.5%** while
`mix.exs` went on recording 93, and every gate passed. Two shipped MCP tools turned out to
have no test at all.

The fix, on 2026-08-28, was three parts, and the shape of it generalises: the gate now runs
`mix test --cover`; the untested tools were tested (9.5% → 100%, 31.3% → 100%); and **the
thresholds were reset to what is actually true** so that they can fail. The restoration
targets stay recorded in `docs/PLAN.md`. Resetting downward looks like exactly the thing the
rule forbids, and the distinction is worth holding onto: lowering a number *you are
currently meeting* is gaming the ratchet, while recording a number you are *not* meeting, so
that it can be enforced tomorrow, is the opposite. An unenforceable 93 protected nothing for
months; an enforced 81 makes the next regression impossible.

Phase 2's gate was run and the tag **deliberately withheld**, because one of its tasks is
blocked on SAT. Recording that honestly is worth more than a green tag.

### The invariants

Eight rules, in `CLAUDE.md`, that everything else defends:

1. **No unattributed text ever leaves the API.** Every returned span carries its URN,
   hashes, offsets and full provenance.
2. **Never invent citation IDs.** Adopt each tradition's existing citation grammar.
3. **`raw/` is append-only and never edited.** Fixes happen in a normalizer, where they
   are visible in review.
4. **Provenance is multi-axis, never a single `source` string.**
5. **Deterministic before probabilistic.** Where curated scholarship exists — a parallel,
   an alignment, a quotation — use it rather than an embedding's guess.
6. **Every retrieval change runs against `evals/`.** Recall and citation accuracy are
   measured, not asserted.
7. **The MCP surface is read-only.** Tools read; the command line writes. A model can
   never modify the corpus it cites.
8. **A machine translation is never citable as source.**

Alongside these sits the rule that defines the guard: *the model is not trusted to cite
correctly — the citation guard re-resolves every URN and byte-compares the quoted span.*

---

## 18. The technology stack

### Elixir and the BEAM

**Elixir** is a functional programming language running on the **BEAM**, the virtual
machine built for Erlang telephone switches. Chosen here because the work is naturally
concurrent (thousands of files to parse, batches to embed) and the BEAM is very good at
running many independent tasks that must not take each other down when one fails.

You will see these repeatedly:

| thing | what it is |
|---|---|
| **Phoenix** | the web framework — serves the MCP endpoint |
| **Ecto** | the database layer: schemas, queries, migrations |
| **Mix** | the build tool; `mix something` runs a task |
| **Oban** | background job queue, backed by Postgres — used for the bake |
| **umbrella app** | one repository holding several applications (`pramana`, `pramana_web`, `pramana_native`) |

An **umbrella** keeps the core domain logic (`pramana`) independent of the web layer
(`pramana_web`) — so the corpus is usable without a web server, and the web layer cannot
smuggle domain rules into itself.

### PostgreSQL and its extensions

| extension | what it adds |
|---|---|
| **pgvector** | a `vector` column type, distance operators, and HNSW/IVFFlat indexes |
| **pg_bigm** | bigram full-text indexing, which works on languages without spaces |

A **migration** is a versioned, ordered change to the database schema, stored as code so
the schema's history is reviewable and repeatable.

A **check constraint** is a rule the database itself enforces — for example, that a
licence class must be one of a known list, or that a `verified` reading must actually
state a reading. Rules enforced in the database cannot be forgotten at a call site. Two
real bugs here were caught by constraints refusing to write.

### MCP

**MCP** (Model Context Protocol) is a standard way for an AI model to call external tools.
The system exposes the corpus over MCP, so a model can call `get_passage` or `search` the
same way it would call any tool.

The MCP surface is **read-only**: tools read, the command line writes. A model can never
modify the corpus it is citing.

Current tools: `search`, `survey_corpus`, `get_passage`, `get_outline`, `get_commentaries`,
`get_parallels`, `verify_citation` — plus two **resources** (documents a model can read for
guidance rather than call).

`survey_corpus` deserves a note: it returns **exhaustive counts, not a ranked sample**. It
is the tool that supports claims about *how often* or *where* something appears, which a
top-20 result list cannot.

### Modal

**Modal** runs code on cloud GPUs on demand. Used for the embedding pass: an L4 GPU for 34
minutes, roughly $0.45, rather than 65 hours on a laptop.

---

## 19. How to actually run things

```bash
# Acquire and ingest
mix pramana.acquire_all             # download + pin every configured source
mix pramana.acquire                 # one source at a time
mix pramana.bake_all                # normalize + segment the Chinese canon
mix pramana.sc.ingest               # Pāli root text (8,442 works, ~53 s)
mix pramana.sc.translations         # English renderings into the pool
mix pramana.parallels.import        # SuttaCentral's curated relations
mix pramana.readings.seed           # reading exceptions from the glossary

# Retrieval plumbing
mix pramana.chunk                   # group segments into chunks
mix pramana.embed.export out.jsonl  # text out, for the GPU
mix pramana.embed.import in.jsonl   # vectors back in, sha-checked

# The checks that must pass at a gate
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test --cover
mix pramana.verify --all            # reproducibility
mix pramana.integrity               # completeness
```

Elixir and OTP versions are pinned with **mise** (a version manager). In non-interactive
shells the shims may be absent, so build commands use `mise exec --` and verify with
`elixir --version` rather than trusting `mise current` — a subtlety that once caused
builds to silently use the wrong Elixir.

---

## 20. Glossary

**Anchor** — an edition's own address for a piece of text (`0037a13`, `1.1`). The thing a
URN is built from and the thing a layer attaches to.

**ANN (approximate nearest neighbour)** — finding *nearly* the closest vectors very fast,
instead of the exact closest slowly. See HNSW.

**Apocrypha (疑偽經)** — texts composed in China that present themselves as translations
from Indian originals. 57 are flagged here. Not a value judgement: a fact about origin.

**Āgama** — Chinese collections translating an early Indian collection closely related to
the Pāli Nikāyas.

**Bake** — an immutable corpus snapshot, identified by a hash of its inputs.

**BGE-M3** — the multilingual embedding model used here; 1,024 dimensions.

**Bigram** — a pair of adjacent characters. The indexing unit for languages without
spaces.

**bilara-data** — SuttaCentral's repository of segment-aligned Pāli text and translations.

**CBETA** — the Taiwanese association whose XML is the source of the Chinese material.

**Chunk** — a window of consecutive segments, ~300 characters, the unit that gets
embedded. Addressed by a range URN.

**Check constraint** — a rule enforced by the database itself.

**Credo / Dialyzer** — Elixir's style linter and static type checker.

**Derived addressing** — an address we invented because the source has no citation scheme;
always flagged, never allowed to resemble a canonical one.

**Ecto** — Elixir's database library.

**Embedding** — a list of numbers representing meaning; 1,024 per chunk here.

**Gaiji (外字)** — a character in the printed text with no Unicode codepoint. 133,049 in
this corpus.

**Gate** — a checkpoint ending a phase; the full check suite must pass to tag it.

**Guard** — the component that re-resolves every URN and byte-compares every quotation.

**HNSW** — *Hierarchical Navigable Small World*, the graph index that makes vector search
fast.

**Ingest** — the whole act of bringing an outside text in: download, parse, segment, store.

**Inner product** — the arithmetic used to compare two vectors here.

**IR (intermediate representation)** — the single internal shape every source is normalized
into, so downstream stages need not know about formats.

**Iterative scan** — pgvector 0.8 feature that keeps walking the ANN graph until enough
results survive a filter. Without it, filtered vector search silently under-returns.

**Juan (卷)** — a fascicle; a division of a work, inherited from scrolls.

**Lexical search** — matching characters. Fast, exact, literal.

**Locator** — the part of a URN addressing a position inside a work.

**MCP (Model Context Protocol)** — the standard by which a model calls these tools.

**Migration** — a versioned schema change, stored as code.

**Modal** — the service used to rent GPU time for embedding.

**Nikāya** — a division of the Pāli canon (DN, MN, SN, AN, Khuddaka).

**Normalize** — convert a publisher's format into the IR.

**Oban** — Postgres-backed background job queue.

**Parallel** — a curated correspondence between texts in different languages, typed by
strength.

**pg_bigm / pgvector** — PostgreSQL extensions for bigram text search and vector search.

**Pinning** — recording exact file hashes so the corpus is tied to specific bytes.

**Provenance** — where a text came from: composition origin, role, confidence, addressing.

**Rendering** — one translation of one anchor by one translator. Addressed only as a
fragment of a source URN.

**RRF (Reciprocal Rank Fusion)** — merging two ranked lists using only ranks, `1/(k+rank)`
with `k = 60`.

**Segment** — the smallest citable unit; one printed line, with its address. 5,185,767 of
them.

**Semantic search** — matching meaning via vectors.

**Sparse checkout** — cloning only part of a Git repository.

**Sutta / Sūtra** — a discourse attributed to the Buddha (Pāli / Sanskrit).

**Taishō (大正新脩大藏經)** — the standard 100-volume edition of the Chinese Buddhist canon,
1924–34. Its page/register/line addressing is the corpus's citation backbone.

**Tier (T0/T1/T2)** — how much provenance a translation has: human, baked-with-pinned-config,
or query-time ephemeral.

**Tipiṭaka** — "three baskets", the Pāli canon.

**URN** — the permanent citation address; the spine of the whole system.

**Variant characters (異體字)** — historically different written forms of the same
character (眾/衆/众). 6,447 classes are normalized in search.

**Witness** — a specific manuscript or printed edition testifying to a text.

---

## 21. Where to read next

In roughly this order:

| file | what it covers |
|---|---|
| `CLAUDE.md` | the seven invariants and the working rules — the constitution |
| `docs/ARCHITECTURE.md` | the pipeline stages in technical detail |
| `docs/SOURCES.md` | each source, its licence, and its citation grammar |
| `docs/LAYERS.md` | translations, readings, and locally-added texts |
| `docs/TRANSLATION.md` | the pool, tiers, selection policy, and the promotion pipeline |
| `docs/MCP.md` | the tool surface a model actually sees |
| `docs/READER.md` | the same corpus for a person — and the four things the view had to push back into the domain |
| `docs/CHECKS.md` | what must pass at a gate |
| `docs/STATUS.md` | where the project is right now
| `docs/RULES.md` | **58 rules**, each learned from a real defect and cited by number
| `docs/HISTORY.md` | what happened, in order
| `docs/PROXIES.md` | why every cheap evaluation proxy lied |
| `docs/GPU_RUNBOOK.md` | the embedding round trip, step by step |
| `docs/EMBEDDING.md` | model choice and cost |
| `docs/ADDING_TEXTS.md` | how to put a text of your own into the corpus |
| `docs/DEV_ENV.md`, `docs/ELIXIR.md` | getting a working environment, and the language |
| `docs/ROADMAP.md` | the phases and what each one is for |

If you read only one after this: **`docs/RULES.md`**. It is the
distilled experience of every bug this project has hit, and most of them are the kind that
produce results that look correct.
