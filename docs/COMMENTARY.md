# Commentaries, Treatises, and Linking Them to What They Explain

> Implementation and dated research notes. Current code distinguishes Chinese grapheme and Tibetan syllable alignment, with source-specific acceptance gates; paragraphs describing earlier floors are historical, not the active policy. See `Pramana.Commentary` and its tests.

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

- **Which work** — `work_relations`, **269 `comments_on` and 38 `subcommentary_of` rows**,
  and `Pramana.Relations`. Run `mix pramana.doctor` for the live figure; these age.
- **Which line** — `commentary_alignments`, **72,120 lemma alignments over 76 pairs**,
  attaching commentary to **54,343 distinct root lines**, and `Pramana.Commentary`.

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
root is quoted* puts the denominator on the wrong object. T1742 quotes T0278 at density
69.2 with 82.4% forward order — comfortably real — and covers **0.3%** of it, which is
below what unrelated pairs score; any root-coverage threshold strict enough to exclude the
null band would have discarded it. The gate is spans per 10,000 characters of the
**commentary**, which does not shrink as the root grows.

**And the floor itself was mis-calibrated for an afternoon.** It was set to 25 against a
40-pair null set whose p90 was 10.8. Tripling that set to 120 pairs moved the observed null
*maximum* to 28.4 — 25 admitted three of them. The floor is now **30**, the lowest value
rejecting all 120, and it costs three asserted pairs. A threshold calibrated against a thin
tail is calibrated against nothing; the way to find that out is to enlarge the tail rather
than reason about it.

## It is not a Chinese-only method any more — 2026-09-03

The Degé prints a tsheg between syllables, so the **syllable** is Tibetan's unit the way
the grapheme is Chinese's, and no dictionary is needed to find it. Measured, the premise
holds better there than here:

| | windows unique in the root |
|---|---|
| `T0223`, 8 graphemes | 62.0% |
| `toh4210`, 6 syllables | **99.8%** |

`toh4224` → `toh4210`, the Pramāṇavārttika vṛtti against its kārikā, goes from 19,499 spans
at 52.1% forward order — noise — to **182 spans at 97.8%**. 17 Tibetan pairs now align,
2,078 lemmas, the first passage-level commentary outside Chinese.

**Tibetan carries a forward-order gate that Chinese does not**, and the difference is
evidence rather than language. 17 of the 40 Tibetan pairs clearing the density floor sit at
chance, because works like `toh4220` and `toh4223` both point at `toh4224` — sibling
commentaries sharing their common root's words. In Chinese the low-forward pairs are
commentaries aligned to a different *translation* of their root, which is a real alignment
and informative. Both Tibetan thresholds — density 20, forward 80 — are the only pair
admitting none of 468 nulls.

**A pair below the floor is not a refuted relation.** A commentary may paraphrase, and
several here plainly do; this method sees verbatim quotation and nothing else. Nothing
about a `comments_on` row changes when its pair fails to align.

**▸ RESOLVED 2026-09-03: the floor is no longer one number.** 論疏部 has its own, 14,
calibrated the same way over its own null set — each subcommentary against twelve treatises
it does not explain, 264 pairs, maximum 13.5 against the sūtra population's 28.4. Sūtras
share enormous formulaic material with each other and treatises share much less, so
coincidence scores lower and the bar can be lower with it. `Pramana.Commentary.min_density/1`.

**The tail moved when the set grew, exactly as it did the first time**: 64 nulls maxed at
2.6 and a floor of 3 looked defensible; 264 nulls max at 13.5. And the corroboration is
that the pairs newly admitted average **86.5% forward order** against 84.3% over all
accepted Chinese pairs — density called them noise and sequence says otherwise.

The paragraph below is what that measurement started from.

**And the floor was calibrated on one population, which is now visibly not the only one.**
Since 2026-09-03 the aligner also reads `subcommentary_of`, so 論疏部 works — a 論疏 quoting
its śāstra — are measured too. Of the first twelve, **one clears the floor** (`T1820`
佛遺教經論疏節要, density 108.5). The other eleven are not noise: forward order runs
**66–83%** against ~50% for chance, which is this section's own discriminator for real 科文
structure. Śāstra exegesis has the structure and quotes less verbatim than sūtra exegesis,
and a floor set by 120 null pairs of the latter rejects nearly all of the former.
**Whether 30 is right for that population is an open question with numbers attached**, and
moving it needs its own null set — the same enlargement that set it at 30 in the first
place.

See `Pramana.Commentary` for the full method, including what forward order says about a
commentary aligned to four different translations of the same sūtra.

**And note what the floor does NOT do: it gates on density, and forward order is only
reported.** On Chinese the two agree, so nothing showed. On Tibetan they disagree
completely — `toh2231` → `toh2229` scores density 554.1 against a floor of 30, with forward
order at **57.4%**, which is chance. The windows match everywhere and in no order, because
eight characters is about two Tibetan syllables. Only the source guard in
`mix pramana.commentary.align` keeps those out, and it was written for a performance reason
that turned out to be a `String.slice/3` defect. Enforcing the discriminator is
`docs/PLAN.md` item 2, and it is now **priced rather than owed**. The null set did not need
building: the Tibetan relations are a population where the premise is known false.

| rule | Chinese kept | Tibetan admitted |
|---|---|---|
| forward ≥ 65 | 74 of 76 | 6 of 98 |
| **forward ≥ 70** | **69 of 76** | **2 of 98** |
| density ≤ 250 | 72 of 76 | 37 of 98 |
| forward ≥ 75 and density ≤ 250 | 58 of 76 | 0 of 98 |

Forward order separates; density does not. **The seven Chinese pairs lost at 70 are the
cross-translation cluster** — real alignments to a real work the commentary is not quoting
— so gating at 70 asserts that the right sūtra in the wrong translation is not an
alignment. That is a claim about what the corpus should say, and it is left to a person.

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
  confidence         certain | probable | asserted | uncertain
  method             catalogue | manifest | title_match | lemma_match
                     | shared_text | llm
  evidence           jsonb
```

Three points carry the weight:

**`method` and `confidence` follow the same discipline as everything else.** A relation
asserted by a catalogue or a source manifest is not the same claim as one an LLM
inferred from similarity, and the difference must survive into the answer. Deterministic
first, LLM only for the residual, always labelled — [the shared invariants](pramana/INVARIANTS.md) invariant #5.

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
- `date_start` / `date_end` — on `works`, **and populated since 2026-08-28**, so "modern" is
  `date_start > 1900` rather than a new flag. This bullet said "already on `works`" while
  those columns were null for all 17,281 texts: true of the schema, false of the corpus, and
  the exact shape of doc failure [the shared invariants](pramana/INVARIANTS.md) § *Keeping the documentation true* exists for.

  **Read `date_basis` with them.** The 1,515 populated today are `authority_lifespan` —
  bounds derived from the attributed person's life, answering *which century* and never
  *which year*. That is enough to keep a Tang exegete apart from a Song sub-commentary,
  which is what the paragraph above promises, and it is **not** enough to date a work
  precisely.

  A locally added modern commentary declares its own date through the manifest, and that is
  a different kind of claim from a lifespan bound — someone stating a fact about a book they
  have in hand. `date_basis` admits `catalogue` and `colophon` and neither quite names it;
  which value a manifest date takes is **undecided**, and it should be decided when the
  first one lands rather than mapped silently onto the nearest existing word.
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

## The tasks that build the graph

    mix pramana.relations.derive        commentary -> what its title names, by containment
    mix pramana.derge.relations         the same for Tibetan, from stem and genre suffix
    mix pramana.quotations.scan         verbatim text reuse across works, into the quotation graph
    mix pramana.relations.shared_text   commentary -> root, from that graph
    mix pramana.commentary.align        lemma -> the root LINE it quotes (科文)

All are **deterministic and re-runnable**, which is invariant #5 and also what makes them
safe: a re-run converges on the same graph rather than accumulating a second copy of it. The
quotation graph is 141,073 verbatim reuses, and `Pramana.Recall` reads it as free relevance
judgements — every one is a statement that a passage occurs in two named works, which is a
retrieval test nobody had to label.

### Reaching the commentaries no title names

Most Chinese commentarial works never name their root — 大智度論 explains 摩訶般若波羅蜜經
and says so nowhere — so `mix pramana.relations.derive` cannot reach them, and
`mix pramana.doctor` prints how few it does.

`mix pramana.relations.shared_text` reaches them through the quotation graph, **as a
candidate generator and not as a citation graph**, which it is not (rule 72,
`docs/PROXIES.md`). The rule is *a commentarial work's root is its dominant shared-text
partner among works whose `text_role` is `root`*, and the direction comes from `text_role`
rather than from the edge, which carries none. `Pramana.Quotations.Roots` holds it, with
the two counting decisions that make it work — distinct passages rather than quotation rows
(rule 73), and partner *families* rather than work ids (rule 72) — and the measurement
against the title-matched links, which is the only independent ground truth available.

**It refuses more than it writes, and the refusals are the interesting part.** A tie is not
a root. `text_role: treatise` is a role nothing has tested and which need not be about
another text at all: its strongest proposals are five Sarvāstivāda Abhidharma śāstras aimed
at the Mahāprajñāpāramitā, because both are full of the same list-formulae. Rule 74.

`text_role: subcommentary` is refused for a different and sharper reason. **論疏部
(T1816–T1850, "Śāstra exegesis") explains 論, and every 論 division in
`Pramana.Taisho.Divisions` is `text_role: treatise`** — so restricting targets to root
scripture excludes, by construction, the only works a subcommentary can be about. Rule 75.

`Pramana.Relations.may_explain/1` is the fix: the target role follows the source role,
read off that division table rather than assumed. It landed in the title matcher first,
where it is pure containment — **18 works, T1816–T1850**, the Chinese Yogācāra and
Awakening-of-Faith exegetical core, reachable by nothing before. The shared-text half is
still owed (`docs/PLAN.md` item 4), so subcommentaries stay refused here; the refusal now
scores **0 of 4** against the ground truth that fix created, which is the division table's
prediction confirmed rather than argued.

Every refusal is derived, counted and printed rather than silently never generated.

## The rule that must not bend

A commentary explains scripture; it is not scripture. Same principle as invariant #7
for generated translations: helpful, attributable, and never citable *as* the root
text. The provenance axes already express this — the reason to build relations rather
than merge commentary into the same flat pool is exactly so the distinction survives
into the answer.
