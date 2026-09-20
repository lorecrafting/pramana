# Recorded status details — chapter 3

> Recorded repository snapshot; corpus figures and runtime outcomes were not re-measured in this documentation audit.
> [Contents](../DETAILS.md) · [Documentation](../../../../docs/README.md) · [Current architecture](../../ARCHITECTURE.md)

### What it can do

Hybrid retrieval (lexical bigram fused with BGE-M3 by RRF), exhaustive survey, a citation
guard that byte-compares every quoted span, **18 read-only MCP tools**, and a six-screen
LiveView reader — including `/check`, where a person pastes a report and sees which of its
claims survive. **Two of the five architecture audits in `docs/CHECKS.md` §2 now run on
every push** (`Architecture.BoundariesTest`) rather than being greps a person remembers at
a phase gate. The other three were performed by hand on 2026-09-03 and each found a live
defect, and **the judgement the section exists for — *has this stopped being the thing it
was designed to be?* — was taken the same day by a session that wrote none of the code.
The answer is no**, with three findings recorded as `docs/PLAN.md` items 9, 10 and 11 and
the reasoning in `docs/HISTORY.md`. **72,120 commentary lemmas** are aligned to the root lines they explain,
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

**▸ READ THE 92.7% AS A VERIFICATION SCORE.** Measured 2026-09-04: of the 1,472 gold
cases, **901 (61%) are `citation_guard` and `provenance`** — the model-independent
guarantees this project exists for — and **214 of 214 `retrieval_translation` queries are
verbatim prefixes of a rendering the index holds**, so that type is scored with the query
inside the thing it searches for (rule 84 prices that at ~15 points). **Only 49 cases, 3.3%,
ask a question in words nobody drew from the corpus**, and they score **30/49 · 61.2%**.
The gap between 92.7% and 61.2% is the gap between *can it prove what I quote* and *can it
answer what I ask*. `docs/PROXIES.md`.

**Eval: 92.7% over 1,472 cases** — 1,364 hits, 0 stale, 0 errored. `evals/baseline.json`
is the published record and this line is copied from it. **Advanced 2026-09-04**, after a
clean 33m31s gate over a fixed tree: it had recorded 1,359 / 92.3% since 2026-08-28, and
`--gate` writes a baseline only when none exists, so every gain since then had gone
unadopted. `topical/chinese` 0 -> 6, `topical/tibetan` 2 -> 1, `retrieval/pali` 119 -> 118,
`retrieval/tibetan` 29 -> 30. Not comparable with the earlier 93.1% over
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
