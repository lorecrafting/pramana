# Layers: Translations, Readings, and Locally-Added Texts

Three capabilities that must be designed in from v1 even though they ship later,
because retrofitting any of them means a schema migration across the whole corpus.

The unifying idea: **a source text is a spine; everything else is a layer keyed to its
anchors.** Translations, pinyin, notes, and alignments are all annotations over the
same URN anchors, never separate documents.

---

## 1. Translation layers

**Yes — the corpus can hold a full machine translation of everything, per language.**

The schema for this already exists as a side effect of Phase 3. SuttaCentral's
`bilara-data` is segment-aligned root ↔ translation, so ingesting it forces exactly
the table we need. The *same* table that holds Sujato's English for `mn1:1.1` holds a
generated English for `T0262_009@p0037a13`. They differ only in metadata.

```
translations
  anchor_urn        FK -> the source anchor being translated
  lang              en, zh-Hans, ja, bo, es, ...
  text
  method            human | llm | hybrid
  translator        "Sujato" | model_id
  model_id          for reproducibility
  prompt_version
  glossary_id       which term glossary was pinned
  bake_id
  review_state      raw | reviewed | approved
  confidence
```

### The invariant that makes this safe

> **A machine translation is never citable as source.**

This is the real hazard. Once you generate English for the whole canon and store it
next to the canon, retrieval will happily hand back your own model's output as if it
were scripture — and it will look authoritative. Two structural defenses:

1. **Translations have no top-level URN.** They are addressed only as a rendering
   *of* a source anchor (`…@p0037a13#tr:en/bake7`). A citation always resolves to the
   source text, never to a derived layer.
2. **The citation guard rejects any quote whose URN resolves to `method != human`
   being presented as canonical.** The guard already exists; this is one predicate.

Machine translations are a *reading aid and a retrieval aid*. They are not evidence.

Serving both a pre-baked English layer *and* on-the-fly LLM translation, plus how to
handle several models producing several renderings, is its own design —
see **`TRANSLATION.md`**. Short version: multiplicity is first-class, ephemeral output
is cached separately from the bake, and promotion into the bake is an explicit gate.

### Why this also improves retrieval

This is the multi-vector trick from `ARCHITECTURE.md`, and it's the same work. Storing
an English layer per segment lets you embed the translation alongside the original —
which is the main mitigation for the weakest part of the system, cross-lingual
retrieval into Classical Chinese. Translating the corpus and improving search are the
same project.

### Terminology-consistent translation

Don't translate segment-by-segment with a bare model. Pin a glossary (DDB,
Mahāvyutpatti, the 84000 Skt–Tib–Eng glossary) per translation run, enforce it, and
record `glossary_id`. Two consequences: renderings stay consistent across 250M
characters, and you can show the chain — 空 ← *śūnyatā* ← *stong pa nyid* ← "emptiness"
— which is auditable in a way no other AI translation is.

---

## 2. Reading layers (pinyin and friends)

**Yes — and generalize it, because "pinyin" is one instance of a broader thing.**

Line-by-line translation is nearly free: because normalization preserves `<lb/>`,
Taishō line anchors already exist. A line-by-line view is a translation layer at line
granularity rather than passage granularity. No new architecture.

Readings need their own layer, with a `scheme` field:

| Language | Schemes |
|---|---|
| Chinese | pinyin, Wade-Giles, zhuyin, Middle Chinese reconstruction |
| Japanese | on'yomi, kun'yomi, kanbun kundoku marks |
| Tibetan | Wylie (deterministic), THL phonetic |
| Sanskrit/Pali | IAST, Harvard-Kyoto, Devanāgarī/Thai/Sinhala scripts |

### The trap: generic pinyin is wrong for Buddhist texts

A general library (pypinyin and friends) will confidently mis-read Buddhist
vocabulary, because transliterated Sanskrit follows conventional readings that ignore
the characters' ordinary values:

- 般若 is **bōrě**, not *bānruò*
- 南無 is **námó**, not *nánwú*
- 阿闍梨 is **āshélí**
- 迦葉 is **jiāshè**, not *jiāyè*

There are hundreds of these, and they cluster in exactly the passages users most want
readings for. So a **Buddhist reading-exception dictionary is a required asset**, not
an optimization — sourced from DDB and Buddhist dictionaries, which record these.
Nobody else's AI Buddhist tool gets this right; it's a cheap, visible differentiator.

The same problem recurs in Japanese: Buddhist texts use 呉音 *go-on* rather than 漢音
*kan-on* (経 is *kyō*, not *kei*), which matters directly for the Taishō 56–84 material.

### Storage

Do **not** store a reading per character — that's billions of rows over the full
corpus for data that is mostly derivable. Instead: generate readings at render time
from a dictionary plus the exception table, cache per segment, and store *only* the
exceptions and any hand-corrected overrides. Readings are a computed layer with a
correction table, not a materialized corpus.

---

## 3. Locally-added texts (one-off commentaries)

**Yes — and this needs to be a first-class ingest path, not a special case.**

A documented manifest format lets anyone add a text to their own bake without touching
pipeline code:

```yaml
# sources/local/huang-nianzu-wlsj/manifest.yaml
id: huang-nianzu-wlsj-jie
title: 佛說大乘無量壽莊嚴清淨平等覺經解
author: 黃念祖
provenance:
  witness: local
  composition_origin: chinese
  text_role: commentary
  date_range: [1980, 1995]
  attribution_confidence: certain
comments_on:
  work: xia-lianju-conflation      # NOT a Tang translation — see below
license:
  class: restricted                 # modern, in copyright
  redistributable: false
citation_grammar: section-paragraph # no canonical page/line grammar exists
format: markdown
```

### Why Huang Nianzu is the ideal test case

It stresses the provenance model in exactly the ways a canonical text can't:

1. **It's modern and under copyright.** Not in CBETA or SAT, not public domain. This
   is precisely why "we publish the pipeline, not the corpus" is the right posture — a
   user adds it to *their* bake, and we redistribute nothing. `license_class:
   restricted` also means it's automatically excluded from any public demo.

2. **It comments on a 會集本 — a conflated edition.** Xia Lianju's 1930s edition of the
   Larger Sukhāvatīvyūha was stitched together from the five surviving Chinese
   translations, and its canonical status is genuinely contested in Pure Land
   scholarship. A flat `source` field would silently present this as "the Infinite
   Life Sutra." The multi-axis model says what it actually is:
   `witness: xia-lianju-conflation`, `text_role: conflation`, with explicit links to
   the five underlying translations. A user asking what the sutra says gets told
   *which edition*, and that this one is a modern conflation rather than a Tang
   translation. **This is the clearest possible demonstration of why provenance is
   several axes and not a string.**

3. **It has lemma-and-gloss structure** — quote a sutra passage, then explain it. The
   Phase 6 commentary parser aligns it to its root text deterministically, so
   "what does Huang Nianzu say about this passage?" works without any manual mapping.

### Citation grammar for local texts

One-offs usually arrive as plain text, Markdown, or a PDF — with no canonical
page/line grammar. They get a **derived** URN
(`pramana:local.huang-nianzu-wlsj:jie@sec12.p3`) that is explicitly flagged
`addressing: derived`, so it is never mistaken for a checkable print-edition
reference. Retrieval must surface that distinction, since the whole promise of the URN
scheme is that a citation can be verified against a physical page — and here it can't.

---

## Roadmap placement

- **Schema for translation + reading layers: Phase 3**, alongside `bilara-data`
  ingest. The tables are needed then anyway; getting them right costs nothing extra
  and retrofitting them later costs a full-corpus migration.
- **Local-source manifest path: Phase 2**, when provenance enforcement is built. It's
  the best available test of whether the provenance axes actually work.
- **Buddhist reading-exception dictionary: Phase 6**, with the other enrichment assets.
- **Full-corpus machine translation: Phase 7**, with glossary-pinned translation.
