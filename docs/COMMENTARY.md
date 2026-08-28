# Commentaries, Treatises, and Linking Them to What They Explain

## First, the terminology, because it matters for the schema

"Śāstra" is not the general word for commentary. The canon distinguishes several
things, and so does our `text_role`:

| Term | Chinese | What it is | our `text_role` |
|---|---|---|---|
| **sūtra** | 經 | scripture, words attributed to the Buddha | `root` |
| **śāstra** | 論 | an independent systematic treatise (Nāgārjuna's *Mūlamadhyamakakārikā*, Vasubandhu's *Abhidharmakośa*) | `treatise` |
| **bhāṣya / vyākhyā** | 釋 / 疏 | a commentary *on* a named text | `commentary` |
| **ṭīkā** | 鈔 / 記 | a commentary on a commentary | `subcommentary` |

A śāstra is not primarily "commentary on a sūtra" — it is a work in its own right,
which is why it gets its own role. The Taishō itself makes the distinction: 釋經論部
(T1505–1535) is *Indian commentaries on sūtras* while 論集部 (T1628–1692) is
*independent treatises*, and we label them differently.

So the categories already exist and are populated: **352 treatises, 155 commentaries,
35 sub-commentaries** across the Chinese canon.

## ▸ BOTH HALVES EXIST NOW — 2026-08-27

This section used to open *"Nothing in the database says which text a commentary comments
on."* Both halves are built:

- **Which work** — `work_relations`, 89 `comments_on` rows, and `Pramana.Relations`.
- **Which line** — `commentary_alignments`, **21,686 lemma alignments over 42 pairs**,
  attaching commentary to **14,692 distinct root lines**, and `Pramana.Commentary`.

The second is what this document called *"the single highest-value piece of this
feature"*, and it is deterministic: a Chinese commentary quotes a phrase of its root and
then glosses it, so the alignment is already written in the text and only has to be read.
`mix pramana.commentary.align` reads it.

**The rule is uniqueness, not similarity.** A lemma anchors to a root position when its
8-character window occurs *exactly once* in the root. 云何為二 tells you nothing about
where a commentary is looking, because that phrase is everywhere; a window occurring once
tells you exactly. That is a measured property of the root text, so there is no threshold
to defend and no model in the path.

Measured on the four best-attested pairs, against the same commentaries paired with roots
they do **not** explain:

| | asserted | unrelated |
|---|---|---|
| root printed lines carrying an anchor | 70–78% | 0.5–1.9% |
| root quoted verbatim | 52–61% | 0.5–0.8% |
| consecutive anchors moving forward | 88–95% | ~50%, which is chance |

**The obvious gate was wrong and was nearly shipped.** Ranking by *what fraction of the
root is quoted* is scale-sensitive: T1736 quotes 2,288 distinct lemmas from the
80-fascicle Avataṃsaka and covers 3.3% of it, less than some incidental matches score. The
gate is spans per 10,000 characters of the **commentary**, which does not shrink as the
root grows. Over the 89 asserted relations and 40 null pairs, the floor of 25 admits 42
asserted pairs and **zero** nulls.

**A pair below the floor is not a refuted relation.** A commentary may paraphrase, and
several here plainly do; this method sees verbatim quotation and nothing else. Nothing
about a `comments_on` row changes when its pair fails to align.

See `Pramana.Commentary` for the full method, including what forward order says about a
commentary aligned to four different translations of the same sūtra.

## The design

A typed, directional relation table:

```
work_relations
  source_work_id     the commentary
  target_work_id     what it comments on
  relation           comments_on | subcommentary_of | translates | conflates
                     | abridges | quotes | parallel_of
  scope              whole_work | juan | passage
  target_urn         optional: the exact passage, when known
  confidence         certain | probable | asserted
  method             catalogue | manifest | lemma_match | llm
  evidence           jsonb
```

Three points carry the weight:

**`method` and `confidence` follow the same discipline as everything else.** A relation
asserted by a catalogue or a source manifest is not the same claim as one an LLM
inferred from similarity, and the difference must survive into the answer. Deterministic
first, LLM only for the residual, always labelled — `CLAUDE.md` invariant #5.

**Relations chain.** A sub-commentary comments on a commentary which comments on a
sūtra. Modelling that as a graph rather than a single `parent_id` is what lets you walk
from a modern explanation back to the root scripture, showing the intermediate layers
rather than collapsing them.

**`scope` and `target_urn` are the interesting part.** Work-level linking ("this
commentary is about T0262") is easy and only mildly useful. Passage-level linking
("this paragraph explains *this line*") is what makes a commentary genuinely helpful,
and it is already on the roadmap: **Phase 6 lemma-and-gloss (科文) parsing.** Chinese
commentaries quote the root passage and then explain it, so parsing that structure
yields `target_urn` deterministically — no inference required. That is the single
highest-value piece of this feature.

## How it plugs into queries

```
get_commentaries(urn, opts)      → what explains this passage, grouped by
                                   origin / role / period
search(..., include_commentary:) → expand hits to commentary on the matched work
resolve_root(commentary_urn)     → walk back to the scripture being explained
```

The reading flow this unlocks is the one you described: land on a dense canonical
passage, and get the layers of explanation attached to it — a Tang exegete, a Song
sub-commentary, a modern teacher — each labelled with when and where it was written, so
a 7th-century gloss is never mistaken for a 1990s one.

## Is it pluggable? Yes — and most of the plumbing already exists

A modern commentary arrives through the **local-source manifest** (task #16), and every
piece it needs is already built:

- `text_role: commentary` and `composition_origin` — populated and CHECK-constrained
- `date_range` — already on `works`, so "modern" is `date_start > 1900`, not a new flag
- `license_class: restricted` — modern work is in copyright; we publish the pipeline,
  not the corpus, and restricted content is excluded from any public surface
- `addressing: derived` — a modern commentary has no canonical page/line grammar, so
  its URNs are marked as not checkable against a printed edition
- **grouped tool responses** — a modern commentary cannot be returned flattened in with
  scripture, because the response shape separates them

What is missing is only the relations table and the query surface. **Task #36.** ▸ Both
shipped; a locally-added commentary declaring `comments_on:` gets work-level linking from
its manifest, and passage-level alignment from `mix pramana.commentary.align` if it quotes
its root verbatim — which a modern vernacular commentary generally will not, and that is
the honest limit of a method built on character identity.

## The rule that must not bend

A commentary explains scripture; it is not scripture. Same principle as invariant #7
for generated translations: helpful, attributable, and never citable *as* the root
text. The provenance axes already express this — the reason to build relations rather
than merge commentary into the same flat pool is exactly so the distinction survives
into the answer.
