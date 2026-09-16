# Project history — chapter 13

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

### What the fix did to the depth question (#10)

The same four-arm ABBA, before and after. Two runs of four arms each, back to back, one
session per run:

| arm | depth | before | after |
|---|---|---|---|
| 1 | 60 | 20/64, 455 s | 20/64, 453 s |
| 2 | 120 | 25/64, 682 s | 25/64, 675 s |
| 3 | 120 | **24/62, 940 s, 2 ERRORED** | **25/64, 672 s, clean** |
| 4 | 60 | 20/64, 456 s | 20/64, 388 s |

**Arm 3 is the whole result.** It crashed the first session, lost 1 case the second, lost 2
the third, and ran clean the fourth. The two depth-120 arms now agree to **0.4%** where the
same pair previously differed by **38%** — the variance left with the timeout, which is
what a fix to an intermittent early-exit scan should look like.

Depth 120's recall gain is now reproduced a **fifth** time: +5 cases, 20 → 25, well clear
of the documented one-case ANN wobble.

**The cost ratio is 1.5–1.7x, and deliberately not quoted more precisely than that.** This
run's own control loosened: the bracketing depth-60 arms came in at 453 s and 388 s, 15%
apart, against 0.2% in the pre-fix run. Taking the depth-60 mean gives 1.60x; taking arm 1
alone gives 1.48x. The ABBA exists to expose exactly this, and the honest reading is a
range. Nothing above depends on it — both recall figures reproduced exactly, and arm 3
running clean is categorical rather than a timing claim.

**Depth 60 moved by nothing — same 20/64, same 453 s.** That is the right result twice
over: depth 60 never hit the timeout, so its runtime should not change, and the trigram
noise the fix removed was contributing no hits to lose.

### The n-gram fix, validated outside the language that motivated it (#10)

The fix changes the fallback for **every** alphabetic query, so validating it on Tibetan
alone and shipping would have been rule 37 again — a fix measured on one workload and
credited against another. Run at the shipped default depth, so the n-gram change is
isolated from the depth question:

| | baseline | after |
|---|---|---|
| retrieval / pali (150 cases) | 53.3% (80/150) | 54.0% (81/150) |
| topical / pali | 56.3% (9/16) | 56.3% (9/16) |
| topical / chinese | 0.0% (0/12) | 0.0% (0/12) |
| topical / chinese-native | 100% (12/12) | 100% (12/12) |
| topical / tibetan | 0.0% (0/9) | 0.0% (0/9) |
| **answered from any tradition** | **72.7% (8/11)** | **72.7% (8/11)** |

**Nothing moved.** The single Pāli case is inside the documented one-case wobble and is not
claimed as an improvement; what it supports is the absence of a regression on the largest
affected category. The word unit cost the Pāli nothing, so the morphological fuzziness the
trigrams provided was not carrying those cases.

`topical/chinese` staying at 0% was **predicted before the run**, and the prediction is
worth as much as the number: those failures are a missing English layer over the Chinese
canon (#43), not a lexical-fallback problem, and a fallback fix cannot create a layer. Had
that row moved, the standing explanation for the 0% would have been wrong.

Under #44's rule — any change must be measured against answered-from-any-tradition before
becoming a default — the fix qualifies: 72.7%, unchanged.

### Depth is per ARM: the gain is semantic, the cost is lexical (#10)

Depth 120 was measured at **~4x** on the full 446-case retrieval set, not the 1.5–1.7x the
Tibetan-only ABBA implied — rule 37 rediscovered by projecting a ratio from one workload
onto another, twice in one session. That killed depth 120 as a global default. But the
cost and the benefit turned out to live in *different retrievers*, which the single `depth`
knob could not express.

Three arms over the 64 Tibetan cases, **prediction written down before the run**:

| arm | config | predicted | actual | time |
|---|---|---|---|---|
| 1 | both 60 (control) | 20/64 | **20/64** | 298 s |
| 2 | semantic 120, lexical 60 | 25/64 | **25/64** | 465 s |
| 3 | lexical 120, semantic 60 | 20/64 | **20/64** | 303 s |

**Semantic depth carries the entire gain; lexical depth carries none of it.** And lexical
depth is nearly free *here* — 303 s against a 298 s control — because a Tibetan gold query
is English, so the lexical arm has little to return however deep it looks.

The asymmetry has a mechanism on both sides:

- **The cost is lexical, and it is Chinese.** A definitional-formula query matches thousands
  of segments, so `limit * 5` over-fetch at depth 120 pulls 600 segments out of the bigram
  index and maps every one to its containing chunk — per-segment work scaling directly with
  depth, over the 232 Chinese cases that dominate the run.
- **The benefit is semantic, and it is Tibetan.** BGE-M3 packs Tibetan into a narrow cone
  (0.9727 mean pairwise cosine), so its candidates are near-ties and the right chunk sits
  deeper in the ranking. Looking further down is exactly what helps.

So `semantic_depth` and `lexical_depth` override `depth` per arm, both defaulting to it.

**The Tibetan probe's 1.56x did not transfer either.** On the full retrieval set,
semantic-120 with lexical pinned at 60 tracks **~2.3x** — better than global depth 120's
~4x, and nowhere near the cheap win the Tibetan arm implied. Deepening the *semantic* arm
is not free on Chinese: an iterative HNSW scan over 617,038 vectors asked for 120
candidates instead of 60 costs real time, and that lands on all 232 Chinese cases whether
or not they benefit. **Three times in one session a ratio measured on one workload failed
to transfer to another**, the third time after rule 37 had already been written down. The
rule is evidently easier to state than to obey; what actually catches it is running the
other workload.

So the trade is **2.3x across 446 cases to gain +5 cases that exist only in the 64 Tibetan
ones**.

**Decision rule, pre-registered before the full-set numbers were seen** — because three
wrong predictions in one session is exactly the condition under which a criterion invented
afterwards becomes a rationalisation:

- **Ship as default** only if `retrieval/tibetan` ≥ 24/64 **and** `retrieval/chinese` ≥
  226/232 **and** `retrieval/pali` ≥ 80/150. The tolerances are one case each, which is the
  documented ANN wobble; two is a real regression under the project's own gate rule.
- **Refuse** on any category down two or more, regardless of what Tibetan does. Chinese and
  Pāli are 382 of the 446 cases, so a genuine regression there outweighs +5.
- **Cost is not a veto for the retrieval default, but it is for the gate.** 2.3x on a
  1,400-case check meant to run at every phase gate is not acceptable. If this ships, the
  gate and the product run different depths — and that tension must be recorded rather than
  quietly resolved, because a gate that does not measure what ships is measuring the wrong
  thing.

**The rule was met on all three criteria, and it ships.** 446 cases, 0 errors, 1h50m:

| | old default | semantic 120 / lexical 60 | criterion |
|---|---|---|---|
| retrieval / chinese | 227/232 | **227/232** | ≥ 226 ✓ |
| retrieval / pali | 81/150 | **82/150** | ≥ 80 ✓ |
| retrieval / tibetan | 20/64 | **25/64** | ≥ 24 ✓ |
| **overall** | 328/446 (73.5%) | **334/446 (74.9%)** | |

Chinese did not move by a single case, which is the result that mattered most: it is 232 of
the 446, and a regression there would have outweighed the Tibetan gain outright. The Pāli
+1 is inside the wobble and is not claimed.

**334/446 is exactly what depth 200 scored** (74.9%, recorded above) — at **1h50m against
its 4h25m**. Depth 200's entire price was being paid by an arm contributing none of its
gain. That is the finding worth keeping from the whole depth investigation: *the question
"how deep should we look" had no single answer because it was two questions*, and three
sessions of ABBA arms went into tuning one knob that turned out to be two.

Shipped as `@lexical_multiplier 3` / `@semantic_multiplier 6` in `Hybrid`. An explicit
`depth:` still sets both arms, so nothing that passes one number changes meaning.

**Both consequences are now resolved, by a full run rather than an extrapolation.**

**The baseline is regenerated: 1,400 cases, 90.0% (1260/1400), 0 errored, 0 stale.** Run at
the shipped default with no experiment flags, so it measures what ships. The category diff
against the old baseline is the cleanest possible result:

| | old | new | |
|---|---|---|---|
| retrieval | 327/446 | **334/446** | **+7** |
| provenance | 300/300 | 300/300 | — |
| quote_verify | 300/300 | 300/300 | — |
| quote_reject | 301/301 | 301/301 | — |
| absence | 4/4 | 4/4 | — |
| topical | 21/49 | 21/49 | — |
| **overall** | **89.5%** | **90.0%** | |

**Retrieval is the only category that moved**, which is what a retrieval-depth change should
look like and is not guaranteed — #43 measured 1,665 gloss vectors displacing Pāli answers,
so a change rippling into another category is a real failure mode. The per-tradition figures
(chinese 227/232, pali 82/150, tibetan 25/64) reproduce the standalone 446-case run
**exactly**, from a separate execution.

**89.5% → 90.0% is a real +7 cases, unlike the last time this number rose.** When the set
grew 249 → 1,400 the average went 79.5% → 89.4% while nothing improved, because the mix
changed. Here the denominator is identical and only retrieval moved.

**The gate cost, measured rather than projected — and the honest figure is a range.** The
446 retrieval cases took **~2h23m** inside this run against **1h50m** for the same cases
standalone two hours earlier, and ~50 min at the old default. So the multiplier is somewhere
between **2.2x and 2.9x**, and the spread is not depth: the machine measurably slowed across
a six-hour session of continuous eval runs, with the Chinese block drifting from 24.9 s/case
to ~39 s/case. The full set now runs **3h08m** wall clock; the previously recorded "62
minutes" was CPU time and is not comparable.

That left a question that looked like a policy choice: a 3h gate is not something anyone runs
at every checkpoint, and running it shallower than the product means it stops measuring the
product.

**It was not a policy choice. It was a bug**, found within the hour — 38 of every 41 seconds
of a search were `texts.body` being shipped for nothing. See *A search took 41 seconds*
below. **The full gate now runs in 18m13s against 3h08m, a 10.3x speedup**, verified by an
actual `--gate` run: 1,400 cases, 90.0%, every row identical to baseline, `gate OK`.

Recorded here because the instinct to solve a cost problem with a sampling policy was wrong,
and would have permanently degraded the instrument to avoid profiling a query.
