# Project history — chapter 1

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

# Project history

**What happened, in order, and what surprised us.** This is a log: entries are written when
the work lands and are not edited afterwards, so a statement here is true *of its date* and
may be false now. If this file and `docs/STATUS.md` disagree about the present, STATUS is
right; if they disagree about the past, this is.

That distinction is why this file exists. These 2,000 lines sat under a heading called
"## Next" inside `STATUS.md`, where a historical sentence — "this bake holds two CBETA
collections" — read as a current claim. It was corrected four separate times before anyone
noticed the heading was the problem.

- **What is true now** → `docs/STATUS.md`
- **What to do next** → `docs/PLAN.md`
- **What we learned, as reusable rules** → `docs/RULES.md`

---

## There is no identity-free validation in this corpus, by any route — 2026-09-04

The windowing prototype fixed the Tibetan's unreachable cases, 16 → 0, on a probe that
scores itself: the query is 84000's English and a window is a substring of it. The obvious
way past that was the **Pāli**, which has eight human translators and can therefore compare
one human's words against another's index. It does not need windowing — `sujato` fits the
cap at a median of 150 tokens — so the plan was to *simulate* 84000's geometry there: pad
each chunk's `sujato` English with its neighbours' until it reaches ~840 tokens, then query
with `suddhaso`.

**Built, and the coarse arm came out at a median of 133 characters** — shorter than the
vectors it was meant to dwarf. Padding added nothing because there was nothing to add.

**The reason closes the question rather than just this attempt.** The 457 chunks `suddhaso`
and `sujato` share sit in **427 texts averaging 1.9 chunks each** — short Vinaya texts with
no neighbours. And that is not an unlucky subset: across the whole corpus **only two human
pairs overlap at all**, `suddhaso × sujato` (457 chunks, 427 texts, 1.9 average) and
`soma × sujato` (114, 73, 3.2), with a maximum of **16 chunks in any shared text**. Every
other pair of the eight human translators shares nothing.

**So an identity-free retrieval validation is unavailable everywhere.** Not on the Chinese,
where `patton` is the only human English. Not on the Tibetan, where `84000` is. Not on the
Pāli, where two humans overlap only in texts too short to exhibit the problem. The
`retrieval/*` gold cases inherit it too — 214 of 214 queries are verbatim renderings — and
`topical` is 49 cases, 9 of them Tibetan.

**What that makes the highest-leverage item on the plan is an acquisition, not a build.** A
single second English over a canon already held would give a real human ceiling, a
non-identity denominator for every "% of the human layer's value" figure, a second column
for the blinded fidelity sheet, and the validation the windowing decision needs. Four
blocked things, one conversation.

**Cost of establishing this: 457 vectors, 406 s of local embedding, deleted afterwards**,
corpus verified back at 1,066,026 with none unembedded. Against a 539,218-vector purchase
justified by a probe that cannot be checked.

## Truncation was doing more good than harm — 2026-09-04

The 320-token cap drops about two-thirds of every 84000 rendering, and `derge.D` scores
**8.5% on the line**, the weakest column this project publishes. Those looked like the same
fact, and the positional test said so: splitting each 84000 chunk vector at the cap,
**51.8% of queries have their own words in the part that was never embedded** — head
containment 0.597 against a tail's 0.764. On the Chinese the same test had come back 18–0
the other way, so this is specific to the canon with folio-sized renderings.

A mechanical ceiling, and an obvious remedy: raise the cap.

**The remedy is wrong, and 54 points wrong.** Priced on 60 vectors before spending anything
— the same content embedded a second time at 1024 tokens under a temporary translator id,
both arms restricted to the same 60 chunks so density could not vary, the temporary arm
deleted afterwards and the corpus verified back at 1,066,026 vectors with none unembedded:

| same 115 queries, same 60 chunks | top-10 | not in 100 |
|---|---|---|
| embedded at **320** tokens | **96 · 83.5%** | 19 |
| embedded at **1024** tokens | **34 · 29.6%** | 61 |

**The model is `BAAI/bge-m3`, unadapted, natively good for 8192 tokens**, so this is not a
fine-tune pushed outside its regime — the confound was checked and does not apply. What is
left is dilution: mean-pooling over 1024 tokens makes the vector a less specific
representation of any line inside it. **The cap was accidentally acting as a focusing
mechanism**, and the truncation everyone would call a defect was buying more than it cost.

**Smaller units then, not a bigger window — and sizing killed that too, the same
afternoon.** 84000 averages **1.79 renderings per chunk, max 3**, so splitting yields two
or three pieces; and an individual rendering is a median of **454 tokens with 97.3% over
the cap**. Splitting halves the truncation and fixes nothing, while leaving a 454-token
vector that is still the diluted object the 1024 run showed is worse.

**The confound resolves, and in one direction.** Truncation looked like a rival to the
published "anchor width" account of the `on the line` column. It is not a rival — **it is
the mechanism by which anchor width hurts**: 84000 anchors to a folio of ~7 Degé lines, a
folio renders to ~454 tokens, and 454 tokens neither fits the window nor points at any one
line inside it. One causal chain.

**And the corpus already contains the evidence for what would work.** `sc.ms` anchors at
1.00 segment, its renderings are a median of **35 tokens**, none exceed the cap, and it
scores **79.0% on the line** — the best column here. Fine anchors, short renderings,
focused vectors. So the Tibetan needs an indexing unit smaller than 84000's own anchor:
sub-rendering windows, an index artifact with no URN of their own, which is a design
question rather than a parameter. The result returned is still the chunk, so nothing
uncitable is served.

**Prototyped the same day, additively, and it works.** 993 sentence-sized windows over the
same 60 chunks, under synthetic translator ids so no migration was needed, deleted
afterwards with the corpus verified back at 1,066,026 vectors:

| same 115 queries, same 60 chunks | rank 1 | top-10 | not in 100 |
|---|---|---|---|
| one vector per chunk (today) | 60 | 99 · 86.1% | **16** |
| sentence windows, ~60 tokens | 54 | 115 · 100.0% | **0** |

**The 16 → 0 is the finding; the 100% is not.** Those cases failed because the words sat
past the truncation point and were absent from the index — windowing puts them in, which is
mechanical. But the query is 84000's own English and a window is a literal substring of it,
so the window arm is flattered more than the chunk arm, whose vector is a superset instead.
Rule 84, and there is no unflattering query available because 84000 is the only English over
Degé. **Rank-1 also fell, 60 → 54**: windowing costs a little at the top while fixing the
tail.

**The full build is a decision, not a task.** 16.6 windows per chunk over 32,483 Degé
chunks is **539,218 vectors — 50.6% growth in an index of 1,066,026** — and local embedding
would take about five and a half days at the prototype's measured rate. It needs a
migration first, and then a validation the prototype cannot give: `evals`' own
`retrieval/tibetan` cases, whose queries nobody drew from 84000.

**Cost of learning this: 60 vectors, 180 seconds of local embedding, no GPU, nothing
mutated.** Against re-embedding 83,897 vectors on rented hardware to make retrieval worse.

## The human ceiling was the query matching itself — 2026-09-04

Chasing why 26 cases retrieve for patton and not for MITRA, after truncation had been
eliminated as their cause. The answer was not about MITRA.

**`mix pramana.recall --renderings` samples HUMAN renderings as queries.** With
`--translators patton` the index holds patton's renderings — and the query is one of them.
Checked directly: **65 of 65** queries are a literal substring of the patton arm's own
vector content.

**§ E1 already knew this and had applied it selectively.** Its own text: *"query with an
arm's own output and its own vector is the nearest neighbour, so every case is a hit by
identity … the dense-vs-prose experiment scored one arm 150-0 that way before its query was
changed to a second translator's words."* Every **model** arm was protected by that
reasoning. `patton` — the arm published as *"a human ceiling"*, the denominator of every
"% of the human layer's value" figure — was not.

**Measured, on the one canon where it can be.** Patton is the only human English over
CBETA, so the calibration runs on the Pāli, where `suddhaso` and `sujato` render 457 of the
same chunks. The query stays suddhaso's throughout; only the index changes:

| index | top-10 of 108 |
|---|---|
| `suddhaso` — the query's own translator | **104 · 96.3%** |
| `sujato` — a different human, same passages | **88 · 81.5%** |

**Identity is worth ~15 points**, density held. The magnitude must not be carried to
another canon — different translators, different corpus, n=108, rule 80 — but the direction
is not in doubt, and it runs **in the project's favour**: the generated layer recovers more
of a real human's retrieval value than published, because the published denominator is
inflated. Found while trying to explain why the models looked bad.

**Three designs, and the two discarded ones are the useful part.** The first constrained
retrieval to the correct work *and* to the shared chunks: 100.0% against 99.1%, both arms
at ceiling, and a probe where both arms are saturated cannot measure a difference between
them — the twin of the `:void` verdict `Pramana.Recall` already uses for a control that
finds nothing. The second dropped both constraints and read **43.5** points, but the
suddhaso index holds 459 vectors against sujato's 15,850, so density varied with the
translator and the gap could be read either way. Holding the chunk set equal gives **14.8**
— so roughly 29 of the 43.5 was density, which is consistent with everything else measured
this week. Rule 80, three designs deep, in one afternoon.

Now rule 84: **the arm you treat as the reference is the one you forget to check.**

## A constant calibrated on one layer, applied to another — 2026-09-04

Chasing *how* the model English differs from Patton's rather than by how much. It did not
answer that question and found something larger on the way.

`Pramana.Embed.@max_length` is **320 tokens**, and its comment says why: *"p99 of real
chunk token lengths is 298; 320 covers everything with minimal padding."* True, and
measured — of the **source** layer. Against the real tokenizer, 300 vectors per layer:

| layer | median | p90 | p99 | max | over cap |
|---|---|---|---|---|---|
| **source** — what the cap was set on | 278 | 288 | 293 | 295 | **0.0%** |
| translation — `suddhaso` | 39 | 58 | 280 | 292 | 0.0% |
| translation — `sujato` | 150 | 229 | 286 | 318 | **0.0%** |
| translation — `brahmali` | 199 | 311 | 462 | 615 | 8.7% |
| translation — `model:mitra` | 383 | 462 | 529 | 688 | **79.7%** |
| translation — `patton` | 448 | 525 | 614 | 683 | **95.3%** |
| translation — **`84000`** | **841** | 1065 | 1617 | 2013 | **99.3%** |

**▸ These are the corrected figures.** The first version of this table sampled with
`ORDER BY id LIMIT 300`, which is insertion order rather than a sample — `sujato` read 35
tokens where a seeded draw gives **150**, four times out. Nothing qualitative moved, and a
figure drawn without a seed is an anecdote by this project's own standard.

**About 58,500 of 83,897 translation vectors are truncated at embedding time**, ~70%. For
84000 it is every one of 32,483, at a median of 875 tokens against a cap of 320 — **roughly
two-thirds of every Tibetan English rendering is absent from the index it exists to be
searchable in.** The 980,464 source vectors are fine, exactly as the comment promised.

**This is rule 74 applied to a constant instead of to a measurement.** The p99 that
justified 320 was a p99 of Classical Chinese source chunks; the English layer arrived later
and the constant went on being true of a population it no longer described. Nothing warned,
because the truncation is inside the tokenizer and produces a perfectly ordinary vector.

**It is confounded with a published finding, which is the part worth pausing on.**
`docs/STATUS.md` reports the `on the line` column as *"mostly a function of anchor width"*,
inversely ordered by width across all three canons exactly — 1.00 segment / 79.0%, 2.01 /
37.0%, 6.94 / **8.5%**. A wider anchor makes a longer rendering, and a longer rendering is
more truncated, so **anchor width and embedding truncation predict the same ordering** and
neither has been isolated. Rule 80. The anchor-width account may well be right; it is no
longer the only candidate, and Tibetan — the row that carries the claim — is where
truncation is worst.

**What it does NOT explain is the E1 quality gap**, and saying so matters: `patton` is
truncated *more* than `model:mitra`, 95.3% against 90.7%, and still scores 23 cases better
on the within-work metric. Truncation is not the dominant term everywhere, so the fix
should be measured on one arm before 83,897 vectors are re-embedded.

**Three wrong turns on the way here, all corrected by measuring.** The first was that
generated English might cover only the head of its chunk: refuted, MITRA renders the whole
thing. The second was that MITRA is verbose at 5.09 English characters per Chinese
character against Patton's 1.38 — **that was my own rule-68 bug**, an ad-hoc query joining
`translations` on `segments.urn` and so dropping every range-anchored Patton rendering.
Corrected from the vectors themselves, Patton's assembled English is **longer** than
MITRA's, 1,678 characters against 1,454. The third was reasoning about tokens from
characters at all, which is why the table above came from the tokenizer.

**And the qualitative read that started it is worth keeping.** Of the 26 cases where Patton
lands in the top 10 and MITRA does not, three or four are the model reciting a remembered
**Pāli** parallel instead of translating the Chinese in front of it — one renders a page of
the Chinese Madhyama Āgama as *"The Middle Length Discourses of the Buddha, Volume I,
Translated from the Pāli by Bhikkhu Ñāṇamoli and Bhikkhu Bodhi"*, and two reproduce the
Satipaṭṭhāna stock formula complete with its ellipses. That is a fidelity problem the
retrieval metric can only see sideways, and it is what the blinded sheet exists to
characterise.
