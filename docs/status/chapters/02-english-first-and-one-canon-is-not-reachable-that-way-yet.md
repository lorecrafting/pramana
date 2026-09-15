# Recorded status details — chapter 2

> Recorded repository snapshot; corpus figures and runtime outcomes were not re-measured in this documentation audit.
> [Contents](../DETAILS.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

### English-first, and one canon is not reachable that way yet

**The reader asks in English; the canons stay in their own languages.** Measured 2026-08-30
by `mix pramana.recall --renderings`, over pairs that really are translations:

| task | work-level | on the line |
|---|---|---|
| **English → Tibetan / Pāli source** | **93.8%** | 54.2%† |
| same-language discourse correspondence | 28.8% | 4.8% |
| cross-lingual discourse correspondence | 0.6% | 0.4% |

† **Pooled over two populations that score 79.0% and 8.5% on this column** — read it per
canon, and see the anchor-width table below for why. Corrected 2026-08-31, rule 69.

An English query reaches Tibetan and Pāli source text **469 times in 500** — better than the
system handles *same-language* paraphrase. So the language barrier is not the problem it was
published as, and the earlier claim that it "costs 98% of achievable recall" is withdrawn.

**Chinese is reachable in English, and as of 2026-09-03 not barely.** The `2` below became
`14` when the MITRA tranche landed; the row is counted the same way as the others, so read
the chunk figures under it rather than the work count:

| canon | works | with an English layer |
|---|---|---|
| sc (Pāli) | 8,442 | 5,845 |
| derge (Kangyur) | 1,195 | 472 |
| **cbeta (Chinese)** | **4,263** | **14** |
| derge-tengyur | 3,380 | 0 |

**The work count misleads in both directions and the chunk count is the honest unit.** A
CBETA work is a whole Āgama, so the 2 human-covered works are **54 sūtras**; the 14 are
the top-10 by directed citation weight plus the four Āgamas. In chunks — the unit the
coverage curve below is drawn in — this is **27,956 of CBETA's 719,543, or 3.88%**, up
from 191 chunks and 0.027% on 2026-09-02. **12 of those 14 works are generated-only**
(`tier: t1`, invariant #8), so they are findable in English and not citable in it. See
`docs/PLAN.md` § E1.

**The translation-coverage curve is measured, and it prices E1** — `docs/PLAN.md` § E1.
Ablating Pāli's English layer, which is the only fully covered one, at 200 pairs per point,
seed 0.42. **Re-measured 2026-09-03 with both stages honouring the ablation**; before, the
reranker saw 100% of the English at every point on the curve:

| coverage | found the work | on the line |
|---|---|---|
| 100% | 88.5% | 79.0% |
| 50% | 79.0% | 41.0% |
| 25% | 59.5% | 22.0% |
| 10% | 41.0% | 9.0% |
| 5% | 32.0% | 4.5% |
| 2% | 18.5% | 1.5% |
| **0%** | **3.5%** | **0.0%** |

**These replace the earlier curve rather than deltaing against it, and the reason is rule
80.** Three things differ between the two runs, not one: the isolation repair, a different
`bake_id` (the old curve ran at 17:16 UTC on 2026-09-02, the current bake was built at
18:50 that evening), and 27,751 Chinese English vectors that have since joined the pool a
Pāli query searches. Six of the seven points moved down by 1–4.5 points and the 50% point
moved *up* by 6, which is on its own a reason not to attribute any of it. **A difference is
only an effect when one thing differs.**

**The 0% control is now genuinely zero on the line**, where it used to read 1.5%. That is
the repair working: with no English anywhere in the path an English query never lands on
the exact Pāli line, and the three cases that used to be credited were the reranker reading
the English the ablation had hidden.

The 0% row was the control while **CBETA sat at 0.027% coverage** with `topical/chinese`
at 0 of 12. Returns are still strongly concave — the first 5% of coverage buys a third of
the whole achievable gain — so a demand-weighted slice was the thing to price, not 720,000
chunks. **The prediction the premium was bounded against is essentially unchanged**:
interpolating the new curve, a *random* 3.6% reaches roughly 26% at work level where the
old one gave about 28%, against the demand-weighted 3.88% that reached 76.0%.

**And the demand-weighting premium is far larger than the curve predicted, 2026-09-03.**
This curve hid vectors *at random*, and predicted a random 3.6% would reach about 28% at
work level. A **demand-weighted 3.88%** reached **76.0%**. That gap is the reason the
top-100 ranking work was worth doing.

**▸ But the premium is not the whole gap, and this file says so 100 lines below.** The
curve was measured by ablating **Pāli**; the 76.0% is **CBETA**. *"Neither column supports
a cross-canon comparison"* — and the bias has a known direction, given in the same passage:
work-level flatters Chinese. The 1,670 queries are drawn from the **14 CBETA works that
have English**, while the Pāli ablation drew queries from a corpus where 5,845 works had
it. Finding the right work among 14 candidates is a different task from finding it among
5,845, and the difference inflates the Chinese figure.

So the gap contains the demand-weighting premium **plus** whatever separates ablated Pāli
from native CBETA, and nothing here separates them. **Isolating it needs a randomly
selected CBETA tranche to compare against** — you cannot ablate your way there, because
only the demand-weighted 3.88% has English at all, so every subset of it is still
demand-weighted. That is another tranche's cost to answer a question the top-100 ranking
has already been paid for, which is a reason to leave it unmeasured and say so rather than
to leave it unmeasured and not.

**What is not in doubt:** `topical/chinese` moved 0/12 → 6/12 on an unchanged gold set,
and production recall over the whole 1,670-case population went 46.8% → 76.0% at work
level. Those are within-corpus, before-and-after, same queries. The premium's *size* is
what is confounded, not the tranche's effect.

**Which slice, though, was ranked off an undirected graph and was wrong.** The quotation
graph is suffix-array shared-text detection: `a` and `b` are two sides of a match with no
"cites" direction, so 65.6% of "cross-work" pairs turned out to be inside one text family
— `T0220b`↔`T0220a` alone is 47% of it — and symmetric weight cannot tell a sūtra quoted
by many commentaries from a commentary quoting many sūtras. The undirected top-20 was 23%
catalogues and encyclopedias. Directed by the two signals already stored (a later work
cites an earlier one; a commentary cites a root) it is 85% root sūtras and 0% catalogues.
Rule 72. **Direction resolves only 20.2% of pairs**, because `text_role` is known for 54%
of works and `date_start` for 31%.

**A generated English layer is measured, not projected.** 205 Patton-covered chunks, five
arms, query held constant and the index varied one arm at a time. **Re-measured 2026-09-03
with experiment isolation repaired** — the first version of this table was produced while
every arm was reranked against the whole English layer, including the renderings that
defined the arm by their absence:

| index contents | found the work | on the line |
|---|---|---|
| no English layer | **38.5%** | **7.8%** |
| `gemma-2-9b-it`, the untuned base | **68.3%** | **27.8%** |
| `gemma-2-9b-it`, glossary-pinned | **71.2%** | **28.3%** |
| `Qwen2.5-32B-Instruct` | **73.2%** | **36.1%** |
| **`gemma-2-mitra-it`** | **83.4%** | **39.5%** |
| Patton, human | **84.4%** | **53.7%** |

**The conclusion is unchanged and two rungs came back identical to the digit.** The
ordering is what it was — mitra > qwen > pinned > base > floor — and MITRA beats its own
untuned base by **15.1 points**, the same margin to the decimal, with architecture, size,
prompt *and now the English layer* held constant. `patton` (173 · 84.4% · 110 · 53.7%)
reproduced exactly, which is how the sample was established: the original run's `--seed`
was recorded nowhere, and `0.42` returning two rungs digit-for-digit while the rungs the
leak touched moved is the evidence that these are the same 205 queries. Rule 82.

**The rung the leak was inflating was the floor, and only on the line.** `--translators
none` used to mean *no English vectors, then rerank against every rendering in the corpus*
— the control for "no English layer" was being reordered by the English it was the control
for. Work-level is unmoved at 38.5%, because reranking a fixed candidate list cannot
conjure the right work into it; on the line it was **11.2% and is 7.8%**.

**So generated English recovers 97.8% of the human layer's retrieval value**, not the 93%
first published: over a floor of 38.5%, Patton adds 45.9 points and MITRA adds 44.9. The
earlier figure was computed against a floor the reranker had been helping. These remain
controlled figures — isolating one translator also removes the 55,326 Pāli and Tibetan
English vectors that compete in production, which is why every row sits above the 46.8%
full-population baseline.

**What the second stage is worth, separable for the first time** — `--rerank false`, same
205 queries, same seed:

| rung | with rerank | vector-only | the reranker is worth |
|---|---|---|---|
| no English layer | 38.5% · 7.8% | 38.5% · 7.8% | **nothing, exactly** |
| `gemma-2-mitra-it`, 205 chunks | 83.4% · 39.5% | 77.6% · 36.1% | +5.8 work · +3.4 line |
| Patton, human | 84.4% · 53.7% | 83.4% · 51.2% | +1.0 work · +2.5 line |
| `gemma-2-mitra-it`, 27,956 chunks | 94.6% · 33.2% | 92.2% · 29.3% | +2.4 work · +3.9 line |

The first row **verifies the reranker's stated safety property as a control** rather than
as a moduledoc claim — *a candidate with no rendering scores 0 and keeps its fused
position* — which had never been checked. And the stage is worth **five times more to the
generated arm than to the human one**, which is what the mechanism predicts: the query *is*
Patton's text, so his vectors nearly saturate the first stage alone, while model English is
a looser vector match that string containment recovers.

**Scaled to 27,956 chunks the two columns still move in OPPOSITE directions**, both rungs
isolated, same 205 queries, same seed, index varied:

| MITRA index contents | found the work | on the line |
|---|---|---|
| 205 chunks — the ladder above | 171 · 83.4% | 81 · **39.5%** |
| **27,956 chunks — the tranche** | **194 · 94.6%** | **68 · 33.2%** |

Work-level rose 11.2 points and on the line **fell 6.3** — attenuated from the +13.6 / −6.8
first published, and the finding stands. This is not the anchor-width artifact of rule 69:
both runs score the same Patton anchors, so width is held constant.

**Displacement out of the result window was the obvious cause and it is refuted.** Re-run
at `--limit 200`, the retrieval layer's maximum, the figures are identical to the digit —
**194 · 94.6%, on line 68 · 33.2%** — so no covering span sits in ranks 101–200. The
covering chunk is out-ranked past 200 by same-work near-duplicates. **Density buys the
work and costs the line, and more `k` does not buy it back.** The reranker recovers +3.9 of
the 6.3 lost on the line, and costs nothing, which is the cheapest half of the remedy.

**And the line column was decomposed on 2026-09-04, which closed § E1's tranche question.**
`mix pramana.recall --renderings --to cbeta.T --within-work` constrains retrieval to the
correct work and reports where the covering chunk ranks inside it — separating a ranking
failure from a recall failure from an absent translation, which `on the line` reports
identically. 189 of 205 cases located, limit 200:

| arm | rank 1–10 | not in 200 | never generated |
|---|---|---|---|
| `patton`, human, 205 chunks | **171 · 90.5%** | 15 | 1 |
| `model:mitra`, **205 chunks** | **148 · 78.3%** | 27 | **0** |
| `model:mitra`, 27,956 chunks | 116 · 61.4% | 35 | **0** |
| `model:mitra`, 27,956, no rerank | 72 · 38.1% | 35 | **0** |

**`never generated` is zero in every generated arm**, so more coverage cannot move these
cases: the English is already in the index. The 55-case gap from human to production splits
with one thing varying at a time — **translation quality −23, density −32** — so density
costs more than quality, and buying more of the same shape is the larger of the two things
already hurting the column. The 35 not-in-200 are **identical with the reranker on and
off**, so they never enter the candidate window: a candidate-generation failure that no
reordering can reach, and **15 of them are out of reach with human English too.**

**These are WITHIN-work figures and are not comparable with the `on the line` column**,
which pays for competition between works as well. Rule 74.

**Every arm on that metric at identical density — 2026-09-04, and it is less flattering
than the aggregate.** All six restricted to the same 205 pilot chunks, so density is held
and only the English varies:

| arm | rank 1–10 | not in 100 |
|---|---|---|
| no English at all | **46 · 24.3%** | 92 |
| `model:mitra` | 148 · 78.3% | 27 |
| `gemma-2-9b-it`, glossary-pinned | 148 · 78.3% | 28 |
| `Qwen2.5-32B-Instruct` | 152 · 80.4% | 23 |
| `gemma-2-9b-it`, untuned base | 152 · 80.4% | 31 |
| **`patton`, human** | **171 · 90.5%** | 15 |

**Generated English recovers 82–85% of the human layer's within-work value** — 102 to 106
cases over a floor of 46, against the human's 125. On the aggregate work-level ladder the
same comparison reads **97.8%**. Both are true of what they measure, and **the within-work
figure is the one that describes a reader who wants the right line.**

**The four model arms span four cases out of 189 and are not distinguishable here.** No
ranking should be read into their order.

**▸ AND THE HUMAN ROW IS NOT A CEILING — 2026-09-04.** `mix pramana.recall --renderings`
samples **human** renderings as queries, so `--translators patton` indexes the very text
the query is drawn from: **65 of 65** checked queries are a literal substring of that arm's
own vector content. Every rung above is scored against it, and every "% of the human
layer's value" divides by it.

**Calibrated where the comparison is possible.** `suddhaso` and `sujato` render 457 of the
same Pāli chunks, so the query stays suddhaso's and only the index arm changes, with the
chunk set held so density cannot vary:

| index | top-10 of 108 |
|---|---|
| `suddhaso` — the query's own translator | **104 · 96.3%** |
| `sujato` — a different human, same passages | **88 · 81.5%** |

**Identity is worth ~15 points.** The magnitude does not transfer to another canon —
different translators, different corpus, n=108, rule 80 — but the direction does: **the
generated layer recovers MORE of a real human's retrieval value than the figures above
say**, because their denominator is inflated. Rule 84. Re-deriving the recovery figures
against a non-identity reference is owed, and cannot be done on the Chinese while patton is
the only human English over it.

**So MITRA's 15.1-point margin over its own untuned base is not within-work precision.**
The domain fine-tune buys cross-work discrimination: English distinctive enough to reach
the right *text*. It buys nothing measurable for finding the right *passage inside it*.
**And glossary pinning, the cheapest intervention available, did not help** — 148 against
the unpinned 152.

**`topical/chinese` moved off 0 for the first time on 2026-09-03 — 0 of 12 to 6 of 12.**
Against `evals/baseline.json` over all 1,472 cases:

| | baseline | 2026-09-03 |
|---|---|---|
| **`topical/chinese`** | **0/12 · 0.0%** | **6/12 · 50.0%** |
| topical, all traditions | 25/49 · 51.0% | 30/49 · 61.2% |
| overall | 1,359/1,472 · 92.3% | 1,364/1,472 · 92.7% |

**Publish the cost beside the gain: it is +6 on Chinese and −2 elsewhere.**
`topical/tibetan` fell 2/9 → 1/9 and `retrieval/pali` 119/150 → 118/150, while
`retrieval/tibetan` rose 29/64 → 30/64. These are deterministic runs over an unchanged
gold set, so those are real displacements rather than noise — 27,956 new English vectors
compete in one pool, and a case another canon used to win it no longer wins. Net **+5**.

**The mechanism the earlier 0% was blamed on is the one that moved.** A whole-corpus
search used to put 191 English vectors over the Chinese against 55,135 over the Pāli, and
the Pāli won every time. It is now 28,762 against 55,135, and six of twelve go the other
way. The prediction was arithmetic and the arithmetic held.

**Measuring it per canon broke the instrument, and that is the larger finding.**
`mix pramana.recall --renderings --to <namespace>`, 200 pairs each, seed 0.42 — the same
probe pointed at one canon at a time, with `derge.D` run as a control:

| canon | mean anchor width | found the work | on the line |
|---|---|---|---|
| `sc.ms` (Pāli) | **1.00 segment** | 178/200 · 89.0% | 158/200 · 79.0% |
| `cbeta.T` (Chinese) | **2.01 segments** | 126/200 · 63.0% | 74/200 · 37.0% |
| `derge.D` (Tibetan) | **6.94 segments** | 199/200 · 99.5% | **17/200 · 8.5%** |

**▸ SUPERSEDED. The `cbeta.T` row above was measured before rule 71**, so 41% of the
English chunks it searched were in scrambled sentence order, and before
`sample_renderings/3` was keyed on the anchor rather than on `t.id` — a re-ingest changed
every id, so the same seed no longer drew the same 200 pairs. Both the text and the
sample moved, and no delta against it is attributable.

**The replacement is not a sample.** The eligible population is 1,670 cases, small enough
to measure entirely, so it was:

| | found the work | on the line |
|---|---|---|
| `cbeta.T`, all 1,670 renderings, 2026-09-02 | **782 · 46.8%** | **539 · 32.3%** |
| **the same 1,670, 2026-09-03, after the tranche** | **1,269 · 76.0%** | **604 · 36.2%** |

A 200-case draw of the same population scored 49.0% / 32.5%, so the sample was mildly
optimistic and not misleading. **This is the number a model arm has to beat**, and it is
the last one here that will need a caveat about sampling: `--translators` now varies the
index instead of the sample, so arms are compared with the query held constant.

**▸ A SECOND MECHANISM WITH THE SAME SIGNATURE, found 2026-09-04 and not yet separated.**
`Pramana.Embed.@max_length` is 320 tokens, calibrated on the **source** layer (p99 293) and
never re-derived for the English one. Measured against the tokenizer: `84000` renderings
have a **median of 841 tokens and 99.3% exceed the cap**, `patton` 448 and 95.3%,
`model:mitra` 383 and 79.7%, while `sujato` is 150 and 0% and `suddhaso` 39 and 0%. **A wider anchor
makes a longer rendering, and a longer rendering is more truncated**, so anchor width and
embedding truncation predict the same ordering in the table below and neither is isolated.
Rule 80. `docs/PLAN.md` item 12.

**And the obvious remedy is refuted: embedding the same content at 1024 tokens instead of
320 is 54 points WORSE** — 96/115 against 34/115 on 60 held-constant chunks, with an
unadapted BGE-M3 that natively supports 8192. Mean-pooling over more tokens dilutes; the
cap was accidentally focusing. The fix for the Tibetan is **smaller units, not a bigger
window**.

**`on the line` scores whether the retrieved span CONTAINS the whole anchor, so it is
mostly a function of anchor width** — 84000 anchors English to folios of about seven Degé
lines, and the chunk that matched is often smaller than that. The column is inversely
ordered by width across all three canons, exactly. Rule 69.

**So the 93.8% / 54.2% pair above should be read per canon, not pooled**: 54.2% is an
average of 79.0% and 8.5% and describes neither. Neither column supports a cross-canon
comparison, and they fail in opposite directions — work-level flatters Chinese (2 works,
against 8,442 Pāli ones), on-line penalises it (anchors twice the Pāli's width). What
stands: the Taishō is reachable in English for the first time, and remains, for practical
purposes, unreachable to a reader who does not already know the Chinese to search for.
