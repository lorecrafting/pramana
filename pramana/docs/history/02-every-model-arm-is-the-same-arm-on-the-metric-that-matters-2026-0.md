# Project history — chapter 2

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## Every model arm is the same arm, on the metric that matters — 2026-09-04

The within-work probe pointed at translation quality as the only lever left. So all six
arms were run on it at **identical density** — every one restricted to the same 205 pilot
chunks, so nothing varies but the English. 189 cases, seed 0.42, limit 100:

| arm | rank 1-10 | not in 100 |
|---|---|---|
| no English at all | **46 · 24.3%** | 92 |
| `model:mitra` | 148 · 78.3% | 27 |
| `gemma-2-9b-it`, glossary-pinned | 148 · 78.3% | 28 |
| `Qwen2.5-32B-Instruct` | 152 · 80.4% | 23 |
| `gemma-2-9b-it`, untuned base | 152 · 80.4% | 31 |
| **`patton`, human** | **171 · 90.5%** | 15 |

**The four model arms span four cases out of 189.** They are not distinguishable here and
no ranking should be read into their order — an intermediate reading of this run, taken
before the last two arms landed, said "Qwen edges MITRA" and did not survive the full
table. The human is **19–23 cases clear of every one of them**, five times the spread among
the models.

**So MITRA's 15.1-point margin over its own untuned base is not within-work precision.**
That margin is real and reproduced exactly under isolation; it measures **cross-work
discrimination** — English distinctive enough to reach the right *text*. It buys nothing
measurable for finding the right *passage inside it*, which is why the aggregate ladder and
this table disagree about the ordering. Two metrics, two different questions, and § E1 had
only ever asked the first.

**Glossary pinning, the cheapest intervention available, does not help**: 148 against the
unpinned 152.

**And the honest recovery figure is lower than the published one.** Over a floor of 46, the
human layer adds 125 cases and any model arm adds 102–106 — **generated English recovers
82–85% of the human layer's within-work value**, against **97.8%** on the aggregate
work-level ladder. Both are true of what they measure; the within-work figure is the one
that describes a reader who wants the right line, and it is the less flattering of the two.

**What it leaves.** Not another model arm, not a better prompt. In ascending cost: the
blinded fidelity sheet, to learn *how* the model English differs from Patton's rather than
by how much; human review, which `review_state` already exists for; or a model better than
any of the four tested. All three need a person to start.

**The probe's own first real use found a flaw in it**, which is worth recording because it
is the shape this project keeps meeting. The no-English arm came back `never generated:
189` and short-circuited every search, so the floor row measured nothing: asking "does this
arm have a translation vector" of an arm **defined** as having none answers no every time.
`nil` and `[]` differ, and here they must behave the same — the same distinction
`Pramana.Retrieval.RenderingScope` makes load-bearing one layer down, met again in a new
place. Fixed, pinned by a test, and the floor re-run.

## The line column is a ranking problem, and coverage cannot fix it — 2026-09-04

The within-work diagnostic the 2026-09-03 audit proposed and recorded as unverified. It
decides § E1 item 8, and the answer is **do not buy another tranche for the line column.**

Retrieval constrained to the correct work, limit 200, the same 205 cases at seed 0.42, the
covering chunk located for 189 by resolving each anchor and matching on character offsets.
One variable at a time:

| arm | rank 1-10 | not in 200 | never generated |
|---|---|---|---|
| `patton`, human, 205 chunks | **171 · 90.5%** | 15 | 1 |
| `model:mitra`, **205 chunks** | **148 · 78.3%** | 27 | **0** |
| `model:mitra`, 27,956 chunks | 116 · 61.4% | 35 | **0** |
| `model:mitra`, 27,956, no rerank | 72 · 38.1% | 35 | **0** |

**`never generated` is zero in every generated arm.** Every covering chunk already holds
English, so no further coverage can move these cases at all.

**The 55-case gap from human to production splits cleanly**: translation quality, with
density held at 205, is −23 cases; density, with the translator held at MITRA, is −32.
**Density costs more than quality does** — so another tranche of the same shape is not
merely useless to the line column, it is the larger of the two things already hurting it.
The earlier "density buys the work and costs the line" was read off two aggregate columns;
this measures it with the work held constant.

**35 cases are unreachable by any reordering**, and the reranker proves it: the not-in-200
count is *identical* with the stage on and off. They never enter the candidate window. That
is `Pramana.Retrieval.Rerank`'s own distinction — Pāli is a ranking failure and can be
reranked, Tibetan is a recall failure and cannot — and here 154 of 189 are the first and 35
the second. **15 of those 35 are out of reach with HUMAN English too**, so roughly 15 are
intrinsic and 20 were bought with density.

**And the reranker is the largest lever in the table and costs nothing**: 72 → 116 into the
top 10 within the work, +44 cases, already shipped.

**The remedy that result pointed at was then refuted too, before it was built.** The
subspan hypothesis says a covering span loses because it is averaged into a ~300-character
chunk vector. Median chunk geometry by outcome bucket is **identical** — 15 segments and
301–307 characters in every one of top-10, 11–50, 51–200 and not-in-200 — so chunk length
does not distinguish a case that lands first from one that never appears. And `patton` and
`model:mitra` restricted to the 205 pilot chunks search **the same chunk ids** and score
171 against 148: same container, different contents.

**So the only addressable thing left is translation quality.** Coverage cannot help,
density hurts, representation is not the mechanism, and the reranker's gain is banked. The
next purchase, if any, is *better English over the same passages* rather than more
passages — which is not the decision § E1 item 8 was written to make.

**Three proposed experiments were killed by sizing in one day** — `@min_coverage`, the
granularity hypothesis and the subspan namespace — for two counts and one 30-minute probe,
against a migration, an embedding run and a generation run. That is what rule 62 is for,
and it is the cheapest work this project does.

**Two things this session got wrong on the way, both recorded because the corrections are
the useful part.**

**Rule 62 killed the experiment I had recommended.** `@min_coverage 0.5` refuses **14 of
patton's 205 chunks and 0 of mitra's 27,956** — the generated layer is one rendering per
chunk, so the floor cannot bite it, and no experiment there can move an E1 number. I had
also called it free; admitting chunks means embedding them.

**And rule 68 broke the first version of the diagnostic, twice, in one script.**
`URN.addresses?/2` is a *prefix* test and was handed a whole chunk URN, so it never
matched; and `segments.urn = $anchor` drops every range-anchored rendering, which is 2,080
of patton's 3,354. It printed 0 at every rank and 167 of 205 "never generated" — a broken
probe wearing the clothes of a finding, in a codebase whose `CLAUDE.md` names this rule as
one of the four that keep re-earning themselves. What made it obvious was that the shape
was impossible rather than merely bad. **The fix is the rule's own prescription**: resolve
the anchor through `Corpus.resolve/1`, which accepts both forms, and join on character
offsets — columns that cannot be ranges.

The script also printed nothing per case, so "slow" and "stuck" looked identical for thirty
minutes, which is precisely what `Mix.Tasks.Pramana.Recall`'s progress printer exists to
prevent. Copying a probe and not its lessons.

## Making the audit stick — 2026-09-04

The 2026-09-03 architecture review found five things. Two were fixed in the commit that
found them; three were **written down**, which in this codebase is a known failure state —
`Docs.RoutingTest` exists because a rule was written, numbered, committed and never routed
to, so it fired after the defect rather than before it. These are the three, made
structural.

**The false claims are withdrawn, which was the urgent half.** `Pramana.Bake` said *"two
people with the same `bake_id` hold byte-identical corpora"*; `PramanaWeb.MCP.Reply`
promised *"`{tool, arguments, bake_id}` is enough to run the query again and get the same
answer"*; the MCP guide told a model to *"cite it for reproducibility."* None of the three
had been true since 27,751 renderings and 27,751 vectors landed under an unchanged id. All
three now say which half they mean: a resolved passage is still byte-identical, a search is
not result-identical. **The `release_id` split is still owed** — but leaving a false promise
up while the real fix is pending is the worse of the two failures, and stopping is cheap
where delivering is not.

**The ordering now discloses itself.** A hybrid response carries `reranked:` —
`%{ran: true, scored: n, promoted: n, tiers: [...]}` — and `tiers` is the point: `["t0"]`
is human English alone, `["t0", "t1"]` says generated text influenced this order. The
project's thesis is warrant, the span has always carried its own, and the rank carried none
while 27,751 CBETA chunks acquired machine English and no human English. `:not_run` is an
atom rather than a zeroed map for the reason `coverage/1` already gives: `%{scored: 0}`
cannot distinguish *ran and found nothing* from *was switched off*.

**And a scope rule can no longer be half-added.** `RenderingScope.rules/0` is the derived
list, and `RenderingScopeTest` asserts each member reaches **both** stages — the candidate
stage must declare it in `known_opts`, the reranker must emit a SQL condition for it. Proved
to discriminate by adding a fourth rule wired to nothing and watching both assertions fail
with the file and the fix named. This is the `Docs.RoutingTest` move applied to retrieval
scope: the list nobody has to remember. **The original defect was exactly this shape** —
two rules honoured by one stage and ignored by the other — so the repair is only worth
something if the next rule cannot repeat it.

**The gate's ratchet turned out to be a floor, and it announced itself on the first run
after being fixed.** `--gate` writes `evals/baseline.json` only when none exists, so every
improvement since the first run went unadopted: a run scoring **1,364 of 1,472 passed
against a baseline recording 1,359**, and a slide back to 1,359 would have passed in
silence. A pass now names every case type that moved, in both directions, and
`--accept` adopts the run. The 34m12s gate of 2026-09-03 printed:

    gate OK — no case type regressed against 1472 baseline cases

    ▸ THE BASELINE IS NOW OBSOLETE — net +6 case(s) against evals/baseline.json:
      retrieval: 370 -> 371 case(s)
      topical:    25 ->  30 case(s)

Acceptance is a separate flag on purpose. Advancing on every pass ratchets a run nobody
reviewed; failing when the system improves teaches everyone to ignore the gate. **The gain
is printed beside the loss** — `topical/chinese` +6 with `retrieval/pali` −1 was one run,
and "net +5" describes neither.

**A caveat on that gate, recorded rather than smoothed over.** Its `evals` step ran between
22:52 and 23:15 while `hybrid.ex` and `rerank.ex` were being edited, so it compiled a tree
mid-change. 1,472 cases came through the ordering-disclosure change with nothing regressed,
which is good news; it is **not** a clean gate over a fixed tree, and invariant #6 wants one
of those. That is finding 1 recurring within a day of being written up, which is roughly how
often this class of thing actually recurs.
