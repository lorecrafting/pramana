# Status

**What is true right now.** Read this first in a new session, then `docs/PLAN.md` for what
is next.

This file used to be 3,896 lines and 38% of all documentation here, because it was also the
project log, the rules reference and a case study. Those are now three files, and this one
is only the present:

| | |
|---|---|
| what to do next, and what it is blocked on | `docs/PLAN.md` |
| what happened, in order | `docs/HISTORY.md` |
| rules learned from real defects, cited by number | `docs/RULES.md` |
| why cheap evaluation proxies lie | `docs/PROXIES.md` |

---

## Where we are

*Snapshot, not an accretion. Everything here is true today; the dated announcements this
section used to accumulate are in `docs/HISTORY.md`, where a sentence is allowed to age.*

### The corpus

**The counts below are generated.** `mix pramana.docs.figures` regenerates them from the
corpus and the gate fails when they are stale, because in one week this file and
`docs/PLAN.md` disagreed about the number of MCP tools while the directory settled it, and
`docs/ROADMAP.md` reported 27,254 commentary alignments when there were 72,120. Do not edit
between the markers; edit the corpus, or run the task.

<!-- figures:corpus -->
| | |
|---|---|
| texts | **17,281** |
| segments | **12,586,964** |
| chunks | **980,464** |
| vectors | **1,066,026** |
| renderings | **273,334** |
| glossary entries | **89,649** |
| quotations | **141,073** |
| MCP tools | **19** |
<!-- /figures -->

<!-- figures:relations -->
| | |
|---|---|
| work relations | **389** |
| comments_on | **269** |
| subcommentary_of | **38** |
| parallel_of | **82** |
| commentary alignments | **76,722** |
| root lines with commentary | **57,609** |
<!-- /figures -->

<!-- figures:derived -->
| | |
|---|---|
| commentary alignment | **100 of 184 alignable pair(s) — 77 distinct commentaries, 76,722 line alignments** |
| commentary -> root links | **194 of 3,923 commentarial works reach a root** |
| Tibetan work titles | **3,864 of 4,575 works named** |
<!-- /figures -->

Everything below this point is a person's prose about those numbers, and carries the usual
obligation: a measurement states its date, and a claim about what is *true now* is checked
against `mix pramana.doctor` when either file changes.

| | |
|---|---|
| Chinese (CBETA) | 4,263 works across **16 of 26 collections** — T 2,471 · X 1,230 · J 285 · I 101 · GA 51 · N 38 · F 27 · seven alternative editions 57 · GB 2 · ZS 1 |
| Pāli (SuttaCentral) | 8,442 works, **210,756** English renderings by 6 translators |
| Tibetan (Degé) | 1,195 Kangyur · 3,380 Tengyur, **30,653** English renderings from 84000 |
| English over Chinese | **3,354 human** renderings over **2 of 4,263** CBETA works, plus **28,571 generated** over **14 of 4,263** — 27,956 of them `model:mitra` across the top-10 by directed citation weight and the four Āgamas, new 2026-09-03. That is **27,956 of CBETA's 719,543 chunks — 3.88%**, up from 0.027%. Generated renderings are `tier: t1` and never citable as source (invariant #8) |
| commentary chains | **389 work relations** — 269 `comments_on`, 38 `subcommentary_of`, 82 `parallel_of`; **194 of 3,923 commentarial works reach a root, from 119**. The Tibetan 102 are new 2026-09-02 and are the first non-Chinese links: `toh4210` Pramāṇavārttika ← its vṛttis ← their ṭīkās. The **66 `shared_text`** are new 2026-09-02 and are the first found without a title: 大智度論 → 摩訶般若波羅蜜經. In rows the signals are `title_match` 240, `shared_text` 66, `manifest` 1; in distinct source works 156 / 66 / 1, and the difference is corroboration rather than duplication |
| commentary alignment | **76,722 lemmas over 100 pairs** — Chinese 74,644 over 83, **Tibetan 2,078 over 17, new 2026-09-03 and the first outside Chinese**. Forward order 86.7% over accepted pairs against 65.1% over the rest |
| Tibetan work titles | **3,864 of 4,575** named — the Kangyur's 1,189 from 84000, the Tengyur's 2,675 promoted out of `works.meta` on 2026-09-02. 711 have no title block in the edition |
| English renderings, all canons | **273,334** — 244,763 human by 8 translators, **28,571 generated** by 4 model arms (`tier: t1`, never citable as source) |
| glossary entries | **89,649** — 56,382 from 84000/Mahāvyutpatti plus **33,267** from DILA (Soothill-Hodous, Karashima ×3, Mahāvyutpatti), new 2026-09-02 |
| glossary anchors | **29,890** citations resolved against the bake — 25,504 to a line held (85.3%), **4,345 attested absences**, 41 unresolved |
| translators compared | Kumārajīva against Dharmarakṣa on the same sūtra: **601 shared Sanskrit headwords, 126 agreed, 475 diverged** — attested by Karashima, not inferred from n-grams |
| pipeline | **v5** · `verify --all`, `integrity` and `coherence` all green over every text |

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
Ablating Pāli's English layer, which is the only fully covered one, at 200 seeded pairs
per point:

| coverage | found the work | on the line |
|---|---|---|
| 100% | 89.5% | 79.0% |
| 25% | 62.0% | 25.5% |
| 10% | 44.5% | 11.0% |
| **0%** | **4.0%** | 1.5% |

The 0% row was the control while **CBETA sat at 0.027% coverage** with `topical/chinese`
at 0 of 12. Returns are strongly concave — the first 5% of coverage buys 38% of the whole
achievable gain, the last 75% buys 32% — so a demand-weighted slice was the thing to
price, not 720,000 chunks.

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

**A generated English layer is measured, not projected.** 205 Patton-covered chunks, three
model arms, query held constant and the index varied one arm at a time:

| index contents | found the work | on the line |
|---|---|---|
| no English layer | 38.5% | 11.2% |
| `gemma-2-9b-it`, the untuned base | 65.9% | 26.8% |
| `Qwen2.5-32B-Instruct` | 70.7% | 34.1% |
| **`gemma-2-mitra-it`** | **81.0%** | **40.0%** |
| Patton, human | 84.4% | 53.7% |

**Scaled to 27,956 chunks the two columns move in OPPOSITE directions**, measured
2026-09-03 on the same 205 queries, same seed, index varied:

| MITRA index contents | found the work | on the line |
|---|---|---|
| 205 chunks — the ladder above | 166 · 81.0% | 82 · **40.0%** |
| **27,956 chunks — the tranche** | **194 · 94.6%** | **68 · 33.2%** |

Work-level rose 13.6 points and on the line **fell 6.8**. This is not the anchor-width
artifact of rule 69 — both runs score the same Patton anchors, so width is held constant.

**Displacement out of the result window was the obvious cause and it is refuted.** Re-run
at `--limit 200`, the retrieval layer's maximum, the figures are identical to the digit —
**194 · 94.6%, on line 68 · 33.2%** — so no covering span sits in ranks 101–200. The
covering chunk is out-ranked past 200 by same-work near-duplicates. **Density buys the
work and costs the line, and more `k` does not buy it back.**

Generated English recovers **93% of the human layer's retrieval value** over the
no-English floor, and the domain model beats its own untuned base by 15.1 points with
architecture, size and prompt held constant. These are controlled figures — isolating one
translator also removes the 55,326 Pāli and Tibetan English vectors that compete in
production, which is why every row sits above the 46.8% full-population baseline.

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

### What it can do

Hybrid retrieval (lexical bigram fused with BGE-M3 by RRF), exhaustive survey, a citation
guard that byte-compares every quoted span, **18 read-only MCP tools**, and a six-screen
LiveView reader — including `/check`, where a person pastes a report and sees which of its
claims survive. **Two of the five architecture audits in `docs/CHECKS.md` §2 now run on
every push** (`Architecture.BoundariesTest`) rather than being greps a person remembers at
a phase gate; the other three, and the judgement the section exists for, still are not. **72,120 commentary lemmas** are aligned to the root lines they explain,
deterministically. English renderings are searchable by their own words.

**A commentary can now be linked to a root it never names.** `mix pramana.relations.shared_text`
reads the quotation graph as a candidate generator — *a commentarial work's root is its
dominant shared-text partner among `text_role: root` works* — and writes **66 links, 44 of
them for works that reached no root by any other method**. 大智度論 shares **654 distinct
passages with 摩訶般若波羅蜜經 and 12 with its runner-up**, and no title rule can see that
pair. With the fix below, commentarial works reaching a root went **119 → 194 of 3,923,
3.0% → 4.9%**.

**It refuses nearly twice what it writes, and the refusals are now measured rather than
argued.** Against the links title matching gives independently, scored written-apart-from-
refused because a blended figure charges the rule for proposals it declines to make:

| | works | correct |
|---|---|---|
| **written** — dominant root family, ≥ 5 shared passages | 17 | **14** |
| **written** — dominant root family, fewer | 12 | 6 |
| refused — a tie, or a role that is not written | 9 | **1** |

**The strong band read 13 of 13 until the ground truth grew**, and that is the honest
shape of a 38-case measurement: read the bands as evidence that every error sits below the
floor, in a tie, or in a refused role — never as a rate. Two of the three new errors are
the ground truth being *coarser* rather than wrong. Treatises are 82 of the 171 proposed
for and testable nowhere; the strongest five are Sarvāstivāda Abhidharma śāstras aimed at
the Mahāprajñāpāramitā because both are full of the same list-formulae. Rules 73, 74, 75;
`docs/PROXIES.md`.

**Chasing its blind spot found a wrong constant that predated it, and fixing that was
worth more than the rule.** Both Chinese linkers restricted the target of a `comments_on`
to `text_role: root`, encoding the premise that only scripture can be commented on.
**論疏部 (T1816–T1850) is a Taishō division whose defining purpose is commenting on 論, and
every 論 division is `text_role: treatise`** — so the corpus's 35 subcommentaries were
unlinkable by both, and `T1830` 成唯識論述記 did not fail to resolve but proposed the
Mahāprajñāpāramitā at `probable`. Rule 75.

`Pramana.Relations.may_explain/1` now makes the target role a function of the source role,
read off that validated division table. In `mix pramana.relations.derive` it is pure
containment, and it links **18 works, T1816–T1850** that nothing could reach: 成唯識論述記 →
成唯識論, 瑜伽師地論略纂 → 瑜伽師地論, 唯識二十論述記 → 唯識二十論, six commentaries on
大乘起信論, 因明入正理論疏 → 因明入正理論 — the Chinese Yogācāra and Awakening-of-Faith
exegetical core. A second constant sat behind the first: the generic-title floor was 5 and
成唯識論 is four characters, so it is now **3**, the lowest value admitting no error in a
full census of what each floor admits (at 2, 人本欲生經註 matches 生經). Title matching went
from 54 works and 110 relations to **78 and 138**.

**The shared-text half of that fix was then measured and refused, which is the more useful
result.** Letting the quotation graph take treatise partners scores **1 of 14** against the
ground truth the title fix created: two of the three 俱舍論 commentaries land on
Saṅghabhadra's `T1562`/`T1563`, which quote the Kośa at length. Shared text cannot tell the
work a commentary explains from another work that quotes it heavily, and among treatises
there is no `root`-shaped restriction left to make — so that population belongs to title
matching, which now holds it. Subcommentaries stay refused in the shared-text rule, and
that is now evidence rather than caution. `docs/PLAN.md` § "Rejected, with evidence".

**One failure mode survives that no widening reaches**: a sole partner satisfies
"dominant" trivially, so silence reads as dominance. `T1708` 仁王經疏 shares seven passages
with the `T0220` family and *nothing* with either 仁王經 above the scan's 20-character
floor. **`runner_up_passages: nil` in a relation's evidence means *unopposed*, not
*decisive*.**

**Start a session with `mix pramana.doctor`.** It prints which bake this is and whether it
still describes its inputs, what is loaded, what is declared and never acquired, and what is
missing — the state that was previously rediscovered with hand-written SQL. See
`docs/OBSERVABILITY.md` for what the running system can and cannot tell you about itself,
which as of the 2026-08-29 audit was *very little*, and now is five telemetry events, an Oban
failure handler and errors a model can branch on.

**Retrieval is measured against ground truth the corpus already holds.** `mix pramana.recall`
reads the 141,073 verbatim quotations as free relevance judgements: **100.0% over 1,891
decided pairs**, which bounds where retrieval failures can live — not in exact matching.
`--parallels` points the same trick at SuttaCentral's 10,493 Pāli↔Chinese parallels — the
axis `topical/chinese` has been 0% of twelve gold cases on.

**Its first published figure was withdrawn on 2026-08-29, the day it was published**, because
`--seed` did not work: `setseed` and the query it seeded ran on different pooled connections,
so three runs of one "reproducible" command gave cross-lingual 0.4%, 0.4% and 0.2% against
controls of 20.8%, 26.4% and 18.4%. Rule 67. The seeded measurement that replaced it reports
two numbers, because work-level scoring credits a hit anywhere in the right work:

| | found | on the parallel line |
|---|---|---|
| control (same language) | 26/125 · 20.8% | **11/125 · 8.8%** |
| cross-lingual | 2/497 · 0.4% | **2/497 · 0.4%** |
| cross vs same | 1.9% | **4.5%** |

**The barrier costs ~95% of achievable recall**, measured line to line — the 98% first
published came from a yardstick that work-level scoring had inflated 2.4×. Both cross-lingual
hits are genuine line-level matches, and both are Dhammapada verses. At a 0.4% rate a
500-case sample lands on 0, 1 or 2 hits without meaning anything, so this axis is read
control-relative and never by raw count. `docs/PLAN.md` § F.

The quotation figure above is drawn by the same sampling and was equally unseeded; 100.0% is
100% of whatever it drew, and the 1,891 is one draw's denominator.

**A report written in prose is now checked at all, and can be repaired.** `Pramana.Citation`
reads the Taishō as an article prints it — `T. 262, 6a23` — because `Guard` scans for
`pramana:` URNs and a scholarly document contains none, so the checker reported zero
citations and `/check` rendered that as clean. `Pramana.Repair` then acts on the diagnosis
in five states: `verified`, `quote_relaxed`, `citation_corrected`, `no_sources` and
`flagged`, the last being ours for the two cases where repair needs a judgement. **Every
correction is a substitution of something the corpus already said**; nothing is generated,
and an ambiguous quotation refuses rather than picking.

Building it exposed a defect in the guard that had been there throughout: **a URN closing
a sentence kept the full stop and resolved to nothing**, so a good citation was reported
`:not_found`. `evals/` could not see it — 601 quote cases, none of them written as a
sentence. Rule 68.

**A report can now be checked, not just a quotation.** `verify_report` byte-compares every
citation in a document **and re-executes the searches its figures rest on** — "appears
36,775 times across 1,904 works" and "no Japanese-composed text uses X" are the claims that
carry a report, and a citation guard structurally cannot reach either. A replay recorded
against a different bake comes back `unverifiable`, never `failed`: the corpus changed, and
saying otherwise would teach people to ignore the checker.

**`mix pramana.verify --all` re-derives every one of 12,586,964 segments in 6m03s**, from
~26 minutes — and the Degé half of that got faster again on 2026-09-01, when the
precomputed volume walk was **deleted** after measuring it at 15–20× slower than the
per-work path it existed to avoid (derge 3m16s → 13s, derge-tengyur 20m30s → 1m02s).
Rule 70.

It prints its own coverage — `12586964 of 12586964 (every segment)`, or
`409790 of 444673 (92.2% — SAMPLED)` when it is not. It reports the denominator because for
a long time it did not: a green `verify OK` over 4,263 texts could mean 23% of them checked.
It works one source at a time even for `--all`, which is a measured decision and not a
preference — see `docs/PLAN.md` audit queue #11.

**A citation given as a RANGE can be diagnosed again.** `Corpus.resolve/1` has always
accepted ranges, because a range is a legitimate citation and a quoted passage is usually
longer than one printed line; `Corpus.context/2` did not, so `Guard.spans_boundary?` answered
"does not span a line boundary" for every ranged citation — the case where a quote most
likely does. Fixed 2026-08-29.

**The gate has a third data check.** `mix pramana.coherence` asks whether independently
derived facts about one work agree — `verify` proves determinism and `integrity` proves
fidelity, and both were green over the 122 works below. Four checks, 3 s, in the gate. Rates
and floors are computed; run it rather than quoting it.

**122 works stopped being Japanese on 2026-08-28.** They are Ming and Qing Chinese
compositions that Taishō volume numbering, applied to the 卍續藏 which does not use it, had
labelled `japanese` — an invariant #4 violation that `verify` and `integrity` were both
green over, because they were faithfully and reproducibly mislabelled. It was found by
setting the translator's birthplace against the origin of what they wrote. `pipeline_version`
is **5**. See `docs/PLAN.md` § A4, and § A5 for the check that would catch its family.

**Bylines resolve to people, and people to places.** 2,374 works carry a DILA authority id,
and through it dates, sect, recorded teachers and students, and a Wikidata q-id where one
exists. A `place_id` now resolves against **59,335 imported places**, giving both a modern
administrative path and the historical region — 江南東道 rather than 浙江省, which is the
unit a scholar means. 1,515
works can be filtered by period — as a **bound from the author's lifespan**, stamped
`date_basis: authority_lifespan`, answering *which century* and never *which year*. That
filter reads 1,515 works of 17,281 and says so on every use.

**Eval: 92.3% over 1,472 cases**, 0 stale, 0 errored — `evals/baseline.json` is the
published record and this line is copied from it. Not comparable with the earlier 93.1% over
1,400: the gold set grew by two new case types, one of which scores 70%. **Compare per row.**

### The boundary of the claim

**Guaranteed, model-independently:** the passage exists at the address given; the quoted
text is byte-identical to the witness, re-resolved and sha256-compared rather than
trusted; the provenance is right, so a Kamakura commentary cannot arrive dressed as an
Indian sūtra; frequency and absence claims are re-executed; and no generated rendering can
be presented as source.

**Not guaranteed:** that the English beside those words is a faithful rendering. A model
can retrieve a line correctly, cite it correctly, byte-verify it, and then paraphrase it
into something the Chinese does not say — every mechanical check here passes. **The guard
proves the citation, never the interpretation.**

So the claim is precise: *you are reading the canon's actual words, at an address you can
check.* `docs/TRANSLATION.md` carries the tier decision that follows from it — index
English is never served, reader English is labelled and scored — and why the translation
layer is built to be replaced rather than owned.

### What it deliberately says it cannot do

Each of these was a silent gap until something made it visible, and each is now reported in
the API rather than left to be inferred from an empty result:

| gap | size |
|---|---|
| Taishō volumes 56–84 | 547 works — CBETA excludes them, only SAT publishes them, **blocked on an email** |
| CBETA collections absent | 10 of 26 |
| parallel graph openable | **6.1%** — 24,717 of 407,176; the rest name witnesses not held |
| texts a `role:` filter cannot reach | **1,640** — only the Taishō has a 部 division table |
| `topical/chinese` | **0%** — an English layer now exists over **54 sūtras of 4,263 works** and cannot compete corpus-wide |


### v1 is met, as written and as scoped

The definition in `docs/PLAN.md` — *a scholar or an LLM can ask a question of three canons,
receive passages byte-verifiable against a print edition, see the provenance of each, and
follow parallels and variants between them, with published numbers saying how often that
works* — is answered clause by clause there.

**Four things were then added to v1 by decision**, after that definition was written, and
**all four have now shipped**: lineage chains, Wikidata ids, place authority
(`docs/PLAN.md` § A3) and Phase 7's report verifier (§ H).

**This section said the opposite until 2026-08-31**, claiming place authority and the
report verifier were "designed and unbuilt" — while `docs/PLAN.md` marked both ▸ DONE on
2026-08-28 and two paragraphs of this same file described them working, 59,335 places and
all. A fifth correction of a published claim about our own state, and the first one caught
by reading STATUS against PLAN rather than against the code. **Read the two together when
either changes.**

Separately, **the phase-2 gate is not done** and is blocked on SAT's reply to a request
**sent 2026-08-15**, not on code and no longer on anyone here.

### Phases

**0, 1, 3, 4 complete and gated** (`phase-0`, `phase-1`, `phase-4`). **2** is the only
unfinished phase behind us and it waits on an email, not on code — #15 and #16 done, #14
blocked on SAT access, and the gate deliberately **not tagged** while a known gap stands.
**6** is under way: the quotation graph and commentary alignment ship; the rest does not.
**8** shipped early — the reader exists.

### The public artefact

`mix pramana.public.bake` builds a redistributable-only corpus into its own database —
13,017 texts, 1.8M segments, **0 CBETA** — verified by the bake and again at boot. Not
deployed anywhere; `docs/DEPLOY.md` has the hosting arithmetic.

## Open questions

- **BGE-M3 multi-vector in Nx** — port the two linear heads and drop the sidecar, or
  keep a bake-time sidecar? Decide in Phase 1 once dense works. *(Task #11)*
- ~~**Tibetan `botok`** has no Elixir/Rust equivalent, so the sidecar survives until at
  least Phase 5 regardless.~~ **Closed 2026-08-27, and it was never open in code.** Nothing
  imports `botok`; the syllable-window approach superseded it and four documents went on
  describing the dependency anyway — including `CLAUDE.md`, which a new session treats as
  binding and which was therefore standing invitation to add Python nobody needed. The
  sidecar's only remaining justification is the multi-vector question above. **Superseded
  a second time on 2026-09-02**: the sidecar now also runs generation for § E1, so it
  survives on that alone and the boundary was restated as *inference only, no domain
  logic* — `docs/ELIXIR.md` § 3.
- **Direction in the quotation graph resolves 20.2% of pairs**, from `text_role` and
  `date_start`, and every demand estimate rests on that fifth. **The obvious way to close
  it was measured and rejected**: citation markers (`經云`, `論曰`, `頌曰`) direct only 287
  of 48,650 pairs, 34× weaker, because the edges are mostly not citations at all — shared
  text between canonical works is usually formulaic phrasing or two renderings of one
  Indic original. `docs/PROXIES.md`. A better demand signal has to come from somewhere
  else: what readers ask, or `work_relations`. Rule 72.
- **705 Tengyur works have no title in any form** — no block in the edition, mostly
  continuations of a work spanning volumes. Closing it needs the Degé *dkar chag* or BDRC
  metadata, which is a new source with its own licence question.

---

## Metrics

| Gate | Tests | Recall@10 | Citation accuracy | Bake time | Segments |
|---|---|---|---|---|---|
| phase-0 | 148 | — | — | 62 ms (T0262 normalize) | 5,341 |
| task-10 | 175 | — | — | lexical query 5–40 ms | 5,341 |
| task-31 | 190 | — | — | outline 40 entries | 5,341 |
| **#9 full Taishō** | **227** | — | — | **190 s / 2,471 works** | **4,729,656** |
| #12 provenance | 257 | — | — | survey 88 ms exhaustive | 4,729,656 |
| #11 semantic (阿含部) | 284 | — | — | query 0.3–0.5 s; embed 1.29 chunks/s | 10,138 embedded |
| **#33 MCP resources + reader links** | **318** | — | — | hybrid search is now the MCP default | 10,138 embedded |
| **#13 Phase 1 gate** | **342** | — | verify --all + integrity green | **150 s / 2,471 works** | **4,740,246** |
| **#11 embeddings, full corpus** | **354** | — | — | embed 34 min / import 88 min | **299,317 chunks, 100% embedded** |
| **#15 provenance shape** | **377** | — | 3 origins in 3 labelled buckets | — | 299,317 chunks |
| **#17 Phase 2 gate** | **420** | — | licence filter now enforceable | import 88 → 38.7 min | 2,472 texts, 4,741,094 |
| **#36 work relations** | **444** | — | 89 commentary→root links | — | 2,472 texts |
| **#32 variant characters** | **465** | — | 众生 0 → 5 hits when expanded | — | 6,447 variant classes |
| **#34 glossary seed** | **483** | — | 10 rejected renderings, 1 unverified reading | — | 376 pinned terms |
| **#18a parallels** | **511** | — | sa1 → sn22.51 from curated data | import 29 s | 407,176 parallels, 3,064 anchors |
| **#38 Pāli root text** | **539** | — | verify --all + integrity green on 10,914 texts | ingest 53 s / 8,442 works | **10,914 texts, 5,185,767 segments** |
| **#39 translation pool + readings** | **582** | — | a generated rendering is rejected as source | translations ingest 4,996 files | **210,756 renderings, 8 translators, 4,601 shared anchors; 22 reading exceptions** |
| **#40 multi-vector + comparison tools** | **629** | — | an English query reaches a Pāli passage and cites the Pāli | chunk 84 s; embed 43,218 in ~5 min | **342,535 vectors: 300,165 source/lzh, 27,589 source/pli, 14,781 translation/en** |
| **#19 eval harness** | **651** | **65.3% @10** (zh **97.1** / pa 37.5) | **100%** verify + reject + provenance | evals 200 cases in 12 min | overall **87.0%**, 0 stale |
| **#21 Derge Kangyur ingest** | **870** | — | verify --source derge green on 1,195 texts; integrity closes to 69 bytes | ingest 4m35s / 103 volumes; verify 75 s | **12,109 texts, 5,647,069 segments; 1,195 Tibetan works, 75 spanning volumes** |
| **#21 84000 join** | **882** | — | an English folio resolves to the seven Tibetan lines it renders | ingest 36 s / 385 files | **30,653 renderings, 472 works, 478 titled; 7 volume groups refused** |
| **#21 Tibetan measured, three ways** | **909** | **retrieval@10 69.3%** (zh 97.1 / pa 55.0 / **bo 35.0**) | **100%** verify + reject + provenance | evals 249 cases in 15 min | overall **79.5%**, 0 stale; topical bo 0% — 95% of the Kangyur has no English layer |
| **#21 term anchors** | **952** | — | 59 of 60 three-way anchors reachable in both canons | glossary ingest 27 s / 396 files | **56,382 entries, 16,741 Skt / 25,524 Tib terms, 865 three-way; 2,756 divergent** |
| **#19 per_tradition decided** | **995** | **68.4% @10** under per_tradition (zh 97.8 / pa 42.7 / bo 21.9) vs **73.3%** default | **100%** verify + reject + provenance | full set **3h09m**; `--only topical` 5m22s | 1,400 cases, 0 stale; **opt-in confirmed** — 22 pinpoint cases lost for 2 topical; answered-from-any-canon 72.7% → 54.5% |
| **#10 the 41-second search** | **1042** | **retrieval@10 74.9%** (zh 97.8 / pa 54.7 / **bo 39.1**) | **100%** verify + reject + provenance | **full gate 3h08m -> 18m13s**; one search 41.1s -> 2.2s | 1,400 cases, **90.0%**, 0 stale, 0 errored; `texts.body` removed from 4 call sites |

| **audit: the seed, the guard, verify** | **1438** | unchanged | **no case type regressed over 1,472** | **gate 48m40s → 32m57s; `verify --all` ~26m → 6m03s** | 12,586,964 verified, every one |
| **English over Chinese · `/check` · architecture boundaries** | **1479** | unchanged | **every row identical to baseline, hit for hit** | gate **32m22s** — evals 21m14s, integrity 11m02s, verify 7m09s | 3,354 renderings anchored to Taishō lines; 191 vectors; `/check` is the sixth reader screen |

The `zh 98.7` in the `#19` row above was **corrected to 97.1** on 2026-08-22. It was a
by-tradition figure that silently included the 40 provenance cases, so its sub-rows did
not sum to their parent — the same error the README carried and had fixed in b22949a,
left standing here. Recall@10 rows in this table mix case types by design; read them with
the case counts in `evals/baseline.json` beside them.
