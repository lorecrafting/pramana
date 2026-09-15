# Project history — chapter 15

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### `hnsw.ef_search` tracking the row limit does nothing — tried, measured, reverted

Looked like an obvious defect. `ef_search` was never set, so it sat at pgvector's default
of **40**, while the ANN query's SQL limit is `limit * @vector_overfetch` — after the
semantic arm moved to `limit * 6` that is **480 rows requested from a graph exploring 40**,
a 12x mismatch against pgvector's own guidance that `ef_search` be at least the limit. And
#43 had already recorded this exact class of failure: "the plain scan had been costing
recall all along — nothing failed; the answers were just further down."

A single-probe check seemed to support it: top-120 at `ef_search` 40 against 200 shared
**112 of 120** candidates with an identical top 10, so the difference lay in the tail — and
the depth work had just shown the tail is where Tibetan's +5 cases came from.

**All 446 retrieval cases, and nothing moved at all:**

| | baseline | ef_search = row limit |
|---|---|---|
| overall | 334/446 | **334/446** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| wall clock | 17m22s | 18m17s (**+5.3%**) |

Mean ranks identical to two decimals: not one scored case changed position.

**Why, and it was reasonable to work out beforehand:** the iterative scan already
compensates. `relaxed_order` with `max_scan_tuples = 200,000` keeps pulling candidates
until the limit is satisfied, which is exactly what a larger `ef_search` would otherwise
buy. The two knobs address the same shortfall, and this codebase already turned the other
one on. The 112/120 overlap was evidence *for* that reading — the scan recovers the tail —
and it was read instead as "the tail matters", which was true and beside the point.

**Reverted.** No gain, 5% cost, and a knob with no measured motivation is a future
maintainer's puzzle. Recorded here so the next person who notices `ef_search` at its
default does not spend the afternoon on it: **it is not a bug, it is subsumed by the
iterative scan.** If `iterative_scan` is ever turned off, this becomes live again.

### The reranker needs no model, and it is worth +46 cases (#10)

Once the Pāli diagnosis said "ranking, not recall", the obvious next step was a
cross-encoder. It was not needed. **The `retrieval` cases quote a published translation,
and we store that translation** — so comparing the query directly against each candidate's
rendering separates them far more sharply than a chunk embedding does, at zero inference
cost. Invariant #5 again: deterministic before probabilistic, and here the deterministic
answer is also the better one.

`Pramana.Retrieval.Rerank` scores bag-of-words **containment** — how much of the query
appears in the candidate's rendering — over `limit * 5` fused candidates, then cuts to
`limit`. Reranking only the top `limit` could never reach the mis-ranked gold, which sits
at a median rank of 37.

| | baseline | **shipped** |
|---|---|---|
| retrieval overall | 334/446 (74.9%) | **380/446 (85.2%)** |
| retrieval / chinese | 227/232, rank 1.98 | **227/232, rank 1.98** |
| retrieval / pali | 82/150, rank 3.09 | **122/150, rank 1.51** |
| retrieval / tibetan | 25/64, rank 3.24 | **31/64, rank 1.32** |
| topical overall | 21/49 (42.9%) | **26/49 (53.1%)** |
| topical / tibetan | 0/9 | **2/9** — first non-zero ever recorded |
| **answered from any tradition** | **72.7%** | **81.8%** |

Nothing regressed, so it ships as the default under #44's rule. `rerank: false` opts out.

**Two predictions were registered before the run; one held and one was wrong in the
useful direction.** Chinese flat was the falsifier — no English renderings exist over the
Chinese canon, so every candidate scores 0 and the order must return untouched. It did,
exactly. Topical was predicted flat-or-worse on the reasoning that a topical query matches
no stored rendering; it rose by 5, because containment measures how much of the *query*
appears in a rendering, and a doctrinal question's content words do appear there. **This is
not only a quote-matcher — it is an English lexical signal over renderings**, which is why
it helps real questions and not merely the anchor-pinpointing the gold set is built from.

**The caveat that has to travel with the +40 Pāli.** Those gold cases are DERIVED from
translation anchors: the query *is* the rendering of the expected passage. A
query-to-rendering matcher therefore solves them close to the way they were constructed,
and the metric flatters the mechanism. #20 already recorded that this case type measures
"pinpoint the anchor whose translation I quoted" while users ask topical questions. The
capability is real — *"I have this English quote, where is it from?"* is ordinary
scholarship, and the citation guard's workflow begins there — but **+40 on `retrieval/pali`
must never be quoted as a general retrieval improvement**. The honest general number is
`answered from any tradition`, 72.7% → 81.8%.

### The first version silently reordered the canons, and only the per-tradition rows caught it

Shipped as an aggregate it looked clean: 370/446, **+36**. Per tradition it was
`chinese 227/232, pali 122/150, tibetan 21/64` — Tibetan **down 4**, twice the documented
ANN wobble.

The cause was a join, and it is the fourth time this exact join has been written wrong
here. Measured:

    derge.D   30,653 range-anchored        0 exact-anchored
    sc.ms          0 range-anchored  210,756 exact-anchored

84000 anchors a rendering to a folio **range**; SuttaCentral anchors one to a **segment
id**. A join written on `anchor_urn = segment.urn` therefore scores **100% of Pāli and 0%
of Tibetan** — and it did not merely fail to help Tibetan. Tibetan queries retrieve Pāli
candidates too, and only those were scorable, so **the reranker promoted the Pāli above the
correct Tibetan answer**. Completing the join took Tibetan from 21 to **31** — past its
25-case baseline, because now it is scored rather than displaced.

**The lesson is about the scorecard, not the join.** A +36 aggregate would have shipped a
mechanism that quietly ranked one canon above another as an artifact of which anchor form
the author happened to have in mind. For a project whose fourth invariant is that a
Japanese commentary must never be presentable as an Indian sūtra, silently reordering the
traditions is the more serious defect, and the aggregate could not see it. **Cross every
headline number with tradition before believing it** — which is exactly what #42 concluded
when `topical/chinese` 0% and `chinese-native` 100% were invisible in both margins.

### The reranker verdict was right about Tibetan and wrong about the system (#10)

The section below concluded "Tibetan's problem is RECALL, not order" and demoted the
reranker on that basis. The measurement was sound and the generalisation was not: it was
taken over 64 Tibetan cases and applied to a retrieval metric that is **150 Pāli cases**.
Pāli had never been probed. It is now, and it fails the opposite way.

| | **Pāli (150)** | Tibetan (64) |
|---|---|---|
| gold at rank ≤ 10 | 82 (54.7%) | 24 (37.5%) |
| **gold at rank 11–200** | **44 (29.3%)** | 9 (14.1%) |
| gold absent from 200 | **24 (16.0%)** | 31 (48.4%) |

**Tibetan cannot be reranked and Pāli can.** Half of Tibetan's gold never enters a
200-candidate pool, so no reordering reaches it. Pāli's gold is retrieved **84% of the
time** and simply sits too low: mis-ranked gold sits at 11, 11, 12, 13, 13, 13, 14, 15,
15, 16, 17, 20, 21, 24 … median **37**, and 30 of the 44 are at rank 62 or better.

**A perfect reranker takes `retrieval/pali` from 82/150 to at most 126/150** — **+44
cases**, against +9 for Tibetan. Overall retrieval would go 334/446 → up to 378/446. That
is the largest single gain available anywhere in the system, and it needs **no training**:
a cross-encoder over the top 50–100 is an off-the-shelf model.

**Why the earlier conclusion inverted the priority.** Tibetan is the weakest language, so
it drew the attention; but it is 64 cases against Pāli's 150, and the thing that helps it
(a better embedder — recall) is the expensive, uncertain option that already failed once as
a LoRA. The thing that helps Pāli (a reranker — ordering) is cheap and untried. The
sentence "a reranker first, then a Tibetan-fine-tuned embedder" was reversed on Tibetan
evidence, and reversing it back is correct for the corpus as a whole: **rerank for Pāli,
embed for Tibetan, and they are different problems needing different tools.**

This is the fourth instance today of a ratio or conclusion measured on one workload and
applied to another (rule 37), and the first where the error was in a *published
conclusion* rather than an estimate.

### What a reranker could actually fix (#10) — 14%, and half the misses are unreachable

The standing plan was "a reranker first, then a Tibetan-fine-tuned embedder". Before
building one, the cheap question: **a reranker reorders the candidate pool and cannot
introduce a passage retrieval never returned — so is the right answer in the pool?**
All 64 `retrieval/tibetan` cases, probed to depth 200:

| | cases | |
|---|---|---|
| gold at rank ≤ 10 | 24 (37.5%) | already a hit |
| gold at rank 11–200 | **9 (14.1%)** | **everything a reranker could fix** |
| gold absent from 200 | **31 (48.4%)** | **recall failure — no reranker helps** |

Mis-ranked gold sits at ranks 12, 14, 14, 17, 28, 30, 48, 177, 194 — median 28, and two
of the nine are barely in the pool at all.

**A perfect reranker takes `retrieval/tibetan` from 37.5% to at most 51.6% at this depth,
and cannot touch the other half.** That is a real gain and a bounded one, and it is not
where the constraint is: **nearly half of Tibetan retrieval never surfaces the right
passage in two hundred candidates.** Recall is the problem, so the fine-tuned embedder —
which changes what gets retrieved — is the higher-value work, and the order in the bullet
above was backwards. #10 already established that a Tibetan LoRA must be judged on the
gold set rather than on proxies; this says which metric it has to move.

**An unexpected second reading, NOT yet a claim.** The eval scores these same 64 cases at
**31.3% (20/64)** using `limit: 20`, which makes Hybrid's over-fetch depth 60. This probe's
own top ten, at depth 200, holds **24**. Same cases, same `covers?/2` rule, +4 cases from
retrieval depth alone. That is above the documented one-case ANN wobble but not far enough
above it to bank, and it is consistent with #43's finding that a wider scan returns better
neighbours rather than merely more of them. It needs a gold-set run at a configurable
depth before anyone believes it — the #10 rule applies to encouraging probes too, and this
is one.
