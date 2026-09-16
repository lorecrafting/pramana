# Primer: What This System Is, How It Works, and What Everything Is Called — chapter 4

> Learning chapter. Corpus figures are recorded examples, not a live inventory; current contracts are in the architecture guide.
> [Contents](../PRIMER.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

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

**Recognized tiers**, not blanket reproducibility guarantees or proof of a query-time
generation service. The table records the original design intent; actual storage and
verification limits are in [TRANSLATION.md](../TRANSLATION.md):

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
