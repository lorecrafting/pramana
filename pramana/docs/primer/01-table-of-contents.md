# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 1

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

# Primer: What This System Is, How It Works, and What Everything Is Called

A ground-up guide for someone new to the project. No prior knowledge assumed — not of
Elixir, not of search engines, not of Buddhist textual studies. Read top to bottom the
first time; after that, use the [glossary](06-postgresql-and-its-extensions.md#20-glossary) as a lookup.

Everything here describes **this repository as it actually is**, with real numbers. Where
something is planned rather than built, it says so.

---

## Table of contents

1. [The one-sentence version](#1-the-one-sentence-version)
2. [The problem this exists to solve](#2-the-problem-this-exists-to-solve)
3. [The corpus: what texts are we talking about](#3-the-corpus-what-texts-are-we-talking-about)
4. [The pipeline, end to end](02-4-the-pipeline-end-to-end.md#4-the-pipeline-end-to-end)
5. [Stage 1 — Acquire](02-4-the-pipeline-end-to-end.md#5-stage-1--acquire)
6. [Stage 2 — Normalize](02-4-the-pipeline-end-to-end.md#6-stage-2--normalize)
7. [Stage 3 — Segment](02-4-the-pipeline-end-to-end.md#7-stage-3--segment)
8. [Stage 4 — Chunk](02-4-the-pipeline-end-to-end.md#8-stage-4--chunk)
9. [Stage 5 — Embed](02-4-the-pipeline-end-to-end.md#9-stage-5--embed)
10. [Stage 6 — Retrieve](03-vectors-from-scratch.md#10-stage-6--retrieve)
11. [Stage 7 — Resolve and verify](03-vectors-from-scratch.md#11-stage-7--resolve-and-verify)
12. [Addressing: the URN scheme](03-vectors-from-scratch.md#12-addressing-the-urn-scheme)
13. [Provenance: who made this text and when](04-addressing-levels.md#13-provenance-who-made-this-text-and-when)
14. [Layers: translations and readings](04-addressing-levels.md#14-layers-translations-and-readings)
15. [Parallels: the same discourse in two languages](04-addressing-levels.md#15-parallels-the-same-discourse-in-two-languages)
16. [Licensing, and why it is a column](05-16-licensing-and-why-it-is-a-column.md#16-licensing-and-why-it-is-a-column)
17. [The integrity machinery](05-16-licensing-and-why-it-is-a-column.md#17-the-integrity-machinery)
18. [The technology stack](05-16-licensing-and-why-it-is-a-column.md#18-the-technology-stack)
19. [How to actually run things](06-postgresql-and-its-extensions.md#19-how-to-actually-run-things)
20. [Glossary](06-postgresql-and-its-extensions.md#20-glossary)
21. [Where to read next](06-postgresql-and-its-extensions.md#21-where-to-read-next)

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
why [parallels](04-addressing-levels.md#15-parallels-the-same-discourse-in-two-languages) matter so much.

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
