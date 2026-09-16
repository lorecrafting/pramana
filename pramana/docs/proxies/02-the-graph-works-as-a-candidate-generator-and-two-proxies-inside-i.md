# Why every proxy lied — chapter 2

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## The graph works as a candidate generator, and two proxies inside it lied — 2026-09-02

The same graph, used the way it can be used: *which root-role work does this commentary
share most text with*. That is a candidate generator, not a reading of direction, and it
finds the pairs no title rule can — `T1509` 大智度論 shares 654 distinct passages with
`T0223` 摩訶般若波羅蜜經 and 12 with its runner-up. It shipped as
`mix pramana.relations.shared_text`. Two things inside it were proxies, and both lied.

**"How much text do they share" was measured as a row count, and that is a measure of
repetition.** A `quotations` row is one *occurrence*. `T1723` 妙法蓮華經玄贊 shares a single
29-character list of the ten stages with the Mahāprajñāpāramitā, which prints it five
times, and by row count those five copies of one string beat the Lotus Sūtra the commentary
is named after. `count(DISTINCT text_sha256)` also dissolved 50 of 171 apparent winners
into ties — their margin had been repetition all along. Rule 73.

**And the validation set was the other method's population.** The rule scored 20 of 26
against the links `title_match` already gives, which is genuinely independent evidence —
and all 26 were `text_role: commentary`, because a title rule can only reach a work whose
title names a root. The population being written to is 48% `treatise`, scored nowhere, and
its strongest proposals are five Sarvāstivāda Abhidharma śāstras pointed at the
Mahāprajñāpāramitā because both are full of the same list-formulae. The 76.9% was not
wrong; it described a population that was not the one being acted on. Rule 74.

**Fixing the constant underneath then withdrew the headline, which is the test that the
diagnosis was real.** Once title matching could reach subcommentaries and four-character
titles, ground truth went 26 → 38 works and the strong band fell from **13 of 13 to 14 of
17**. A precision that survives an enlargement of its ground truth has earned something; a
precision that does not was measuring the ground truth.

**What both have in common with everything else in this file: the number looked fine.**
76.9% over 26 cases with an honest denominator, published as such in `docs/PLAN.md`, and
neither transferable nor stable. The check that caught it was cross-tabulating the validation set
against the population by the variables the method could turn on — role, and weight of
evidence — which took one query.

**And the cross-tab found a third thing, which was not a proxy at all but the constant
underneath both of them.** The rule works *because* partners are restricted to
`text_role = 'root'`; unrestricted it scores 43.8%. That restriction also states a premise
about the literature — only scripture is commented on — and 論疏部 (T1816–T1850) is a
Taishō division whose defining purpose is commenting on 論, every 論 division being
`text_role: treatise`. So all 35 subcommentaries in the corpus were excluded by
construction, `mix pramana.relations.derive` holds the same constant so no ground truth
existed to expose it, and `T1830` 成唯識論述記 did not fail to resolve — **it resolved to
the Mahāprajñāpāramitā at `confidence: probable`**, because with the right answer filtered
out the runner-up looks like the answer. Rule 75.

`Pramana.Relations.may_explain/1` fixed it in the title matcher, where it is pure
containment: **18 works, T1816–T1850**, the Chinese Yogācāra and Awakening-of-Faith
exegetical core, reachable by nothing before. Subcommentaries stay refused in the
shared-text rule until that half lands, and the refusal now scores **0 of 4** — the
division table's prediction confirmed rather than argued. `docs/PLAN.md` item 4.

---

## Why every proxy lied

This is the finding worth keeping, and it cost ~$2.60 to buy:

| measurement | verdict | scope |
|---|---|---|
| in-batch top-1 | 0.044 → 0.148 (3.4×) | 24 candidates |
| held-out MRR | 0.162 → 0.327 (2×) | 24 candidates |
| discrimination gap, `bo` | +0.0098 → **+0.1883 (19×)** | adjacent vs random chunk |
| **gold-set retrieval** | **35% → 0%** | **617,038 competitors** |

A **19× improvement in separating related from unrelated passages produced zero correct
retrievals.** The proxies measured pair-matching among two dozen candidates and local
geometry between neighbouring chunks. Retrieval ranks against six hundred thousand.
Training with in-batch negatives at temperature 0.05 taught the model to separate small
sets while destroying the global structure corpus-scale ranking depends on — the classic
shape of optimising the training objective rather than the task.

The damage was not uniform, and the pattern is diagnostic: `retrieval/chinese` held at
97.1% while Tibetan and Pāli collapsed. Chinese eval cases lean on lexical and
phrase-anchored matching; the languages that fell are the ones whose cases actually depend
on the vector space.

**Three probes were built to avoid exactly this, and none of them caught it.** The first
measured dispersion rather than discrimination (a random projection scores well and
retrieves nothing). The second compared the adapted model with itself, because
`PeftModel.from_pretrained` injects in place — it printed identical numbers to four
decimals and three confident `KEPT` verdicts. The third was correct, honest, and still
predicted the opposite of what happened. **No proxy available here can substitute for
running the eval against the real index.** That is now the rule: for a retrieval change,
the gold set is not confirmation of a decision already made on proxies — it *is* the
decision.

**Rollback confirmed.** Re-embedded with the stock model and re-scored: **78.7%
(196/249)** against the 79.5% baseline, with **seven of the eight categories
bit-identical** — provenance/chinese 40/40, retrieval/chinese 34/35, retrieval/pali 11/20,
topical/pali 9/16, topical/chinese-native 12/12, and both zero categories unchanged. Only
`retrieval/tibetan` differs, 5/20 against 7/20.

Two cases, and it is almost certainly **HNSW rebuild noise rather than an incomplete
restore**. The index is approximate, so a rebuild produces a different graph, and there is
a precedent from this same session: during the 512-window experiment `retrieval/tibetan`
moved 7/20 → 8/20 from a rebuild alone, with no change that could touch Tibetan. It moved
by one then and by two now.

That instability is itself a finding, and it points back at the same defect: **Tibetan
retrieval is unstable under index rebuild BECAUSE its vectors are the worst-separated in
the corpus.** At 0.9727 mean pairwise cosine the candidates are near-ties, and near-ties
resolve arbitrarily under approximate search. The 20-case gold set cannot distinguish a
±2 swing from a real change, which is the same statistical thinness that made the
320-vs-512 window question unresolvable.

What is kept: the adapter, `modal_train_tibetan.py`, `modal_probe_adapter.py`, and the
30,607-pair training set. What is discarded: the vectors. A future attempt should train
against corpus-scale negatives — mined from the index rather than from the batch — and
should treat any proxy gain as a hypothesis until the gold set agrees.

The architectural work the episode forced is kept too, and was worth having independently:
`Pramana.Embed` now separates what a vector **records** from where its weights **load
from**, and `build_serving/1` raises rather than embedding queries with weights that
disagree with the documents. Without it the eval above would have run stock queries against
adapted vectors and produced a number worth believing and entirely meaningless.

### The Tibetan training set is built, from data already here (#21)

BGE-M3 barely separates Tibetan (0.9727 mean pairwise cosine, below) and a cross-encoder
reranker scored it at *exactly chance*, so the embedder itself has to learn the language.
`mix pramana.tibetan.pairs` exports the training set — **30,607 pairs across 471 works**,
46 rejected — with no acquisition and no GPU.

**Folio-level, not chunk-level, and a measurement decided it.** 32,483 chunks carry both a
`source/bo` and a `translation/en` vector and look like ready-made pairs. They are not
used, because the English *overshoots*: a chunk's translation vector concatenates every
rendering overlapping the chunk, so it describes Tibetan outside the chunk's own span.

| pairing | bo median | en median | en/bo |
|---|---|---|---|
| chunk-level | 1,411 | 3,297 | **2.32** |
| folio-level | 1,515 | 1,721 | **1.14** |

That 2.32 is not English verbosity, it is over-inclusion. 84000 renders folio by folio, so
a folio's rendering corresponds to exactly the lines on it; chunk pairs additionally admit
up to half the Tibetan unrendered, since translation vectors are built at
`@min_coverage 0.5`. Folios are uniform physical units too (bo p90 1,630 against median
1,515), which is why the folio ratio band is so tight.

**Provenance is checked, not asserted.** Every pair carries the anchor it came from. On a
60-pair sample, **60/60 anchors resolve and 60/60 resolved spans contain the pair's own
Tibetan** — a training set whose provenance cannot be audited is the same problem as a
citation that cannot be verified. Spot-check of a pair at
`pramana:derge.D:toh127@55.155a.1-55.155a.7`: རྫུ་འཕྲུལ / "miraculous powers",
བྱང་ཆུབ་སེམས་དཔའ་སེམས་དཔའ་ཆེན་པོ / "bodhisattva mahāsattvas" — genuinely parallel.

**Hard negatives are deliberately not mined into the file.** They belong with the training
run, which knows its batch size and sampling strategy; baking them in fixes a choice that
should stay tunable. `work_id` and `anchor` are emitted so the obvious source —
same-work, nearby-folio Tibetan, the confusions that actually matter — is available.

One gap noted while doing this: `Pramana.Chunk.Vectors` computes a translation vector's
`coverage` and filters on it at 0.5, but does not persist it. Every existing pair is
therefore ≥50% covered by construction, and a 0.5 pair cannot be told from a 1.0 one.

### Tibetan n-grams were mostly one particle (#21) — the unit was wrong

`:ngram` is the recall fallback when a phrase finds nothing, and it windows the query by
**grapheme**, width 3. For Chinese that is right: a character is a morpheme, so `波羅蜜`
is pāramitā. A Tibetan grapheme is a *letter stack*, so the same rule cuts across the
tsheg. Windowing `སྟོང་པ་ཉིད` (śūnyatā) gave:

| window | segments matched (of 1,352,471) |
|---|---|
| `སྟོང་` | 82,903 (6.1%) |
| `ང་པ` | 267,757 (19.8%) |
| **`་པ་`** | **1,211,774 (89.6%)** |
| `པ་ཉི` | 149,136 (11.0%) |
| `་ཉིད` | 414,497 (30.6%) |

`་པ་` is the particle པ between two separators, and it is in **nine of every ten Tibetan
lines** — while the term itself is in 2.63%. Ranking counts how many distinct query terms
a passage contains, so the junk outvoted the signal.

Now the window is the **syllable**, width 2: `["སྟོང་པ", "པ་ཉིད"]` — 3.7% and 10.8%. The
worst window went from 89.6% to 10.8%, and the mean from 31.4% to 7.3%.

**No dictionary, deliberately.** This module already refuses jieba as the Chinese fallback
because it shatters transliterated Sanskrit and "a single common character appears on
nearly every line". `botok` is the same class of tool and this corpus is full of Tibetan
transliterations — `པྲ་ཛྙཱ་ཝརྨ` (Prajñāvarman) sits in a colophon. The tsheg is a
delimiter *the edition prints*, so splitting on it cannot mis-segment a name it was never
taught: `པྲ་ཛྙཱ་ཝརྨ` windows to `["པྲ་ཛྙཱ", "ཛྙཱ་ཝརྨ"]`. Windows also never cross a shad,
because the window is rejoined with a tsheg and searched as a substring — spanning a
clause break would fabricate a string the edition does not print.

That supersedes the plan to run `botok` in the Python sidecar, which would have repeated
for Tibetan the mistake already documented for Chinese.
