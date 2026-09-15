# Why every proxy lied — chapter 1

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

# Why every proxy lied

**The most expensive lesson in this repository, and the one most likely to be repeated.**
A Tibetan LoRA improved every cheap measurement — 3.4× on in-batch top-1, 2× on held-out
MRR, **19× on discrimination** — and scored **0%** on the gold set it was built to improve.

It has its own file because it is a self-contained case study about *evaluation
methodology*, not a rule and not an incident report, and because three modules cite it by
name when explaining why they refuse a shortcut.

---

## Three ways to publish a number that answers a different question — 2026-09-03

All three surfaced scoring the E1 MITRA tranche, none of them broke anything, and each
would have produced a confident figure that could not be compared with the one it was
placed beside.

**1. The default sample answers a different question than the baseline.**
`mix pramana.recall --renderings --to cbeta.T` is the invocation written down for the
production verdict. It takes `@default_sample` **200** and, with no `--seed`, orders by
`random()` — an unseeded 200-draw. The figure it is compared against, **46.8% / 32.3%**,
was deliberately measured over the **entire 1,670-case population** so that there would be
no seed to match and no draw to argue about. Running the documented command and reporting
the delta would have been exactly the sampling error this project retracted once already,
committed by following its own runbook. **`--sample 1670` is the invocation.** A default
is not a measurement decision, and a command that is copied into a doc inherits whatever
default it had on the day.

**2. There are two files that look like the eval baseline and only one is.**
`evals/scorecard.json` holds **249** scored cases; `evals/baseline.json` holds **1,472** —
the gold set. Both have `overall`, `by_type` and `by_type_tradition` keys with identical
shape, so reading the wrong one produces a well-formed comparison against a population
four-fifths absent. Here it would have reported the baseline as 79.5% against a run of
92.7% and made a **+13 point** improvement out of a file mismatch. The `topical/chinese`
row happened to read 0/12 in both, which is what made it survive a first check. **The
baseline is the one `--gate` reads: `evals/baseline.json`.**

**▸ MADE STRUCTURAL 2026-09-04.** Documenting a trap leaves it armed. The file is now
`evals/scorecard-249case-2026-08-18.json` — **its population is in its name**, which is
rules 22, 44 and 54 applied to a filename, and it can no longer be picked up by someone
reaching for "the scorecard". A partial run written to a path that looks like the baseline
is the thing to avoid recreating: name a narrowed run for what it measured.

**▸ WHAT THE 92.7% IS A SCORE OF — measured 2026-09-04, and it is not what the number
looks like.** The gold set is 1,472 cases, and its composition decides what the headline
means:

| file | cases | share | what the query is |
|---|---|---|---|
| `citation_guard` | 601 | 40.8% | verification — is this quote real, at this address |
| `provenance` | 300 | 20.4% | metadata — who composed it, when, in what role |
| `retrieval_definition` | 232 | 15.8% | a **source phrase**: *I have this quote, where is it from* |
| `retrieval_translation` | 214 | 14.5% | **a stored rendering, verbatim** |
| `topical` | **49** | **3.3%** | **a question in the reader's own words** |
| `translation_rendering` | 40 | 2.7% | |
| `commentary_gloss` | 32 | 2.2% | |
| `absence` | 4 | 0.3% | |

**All 214 `retrieval_translation` queries are verbatim prefixes of a rendering the index
holds** — checked, 214 of 214, not sampled. So that case type is scored the way rule 84
describes: the query is inside the thing it is searching for. `Pramana.Retrieval.Rerank`
says as much in prose — *"the query IS the rendering of the expected passage"* — and rule
84 now puts **~15 points** on what that is worth.

**None of this makes the eval wrong, and the composition matches the thesis.** This project
exists to establish *warrant*, and **901 of 1,472 cases — 61% — are verification and
provenance**, which is exactly the guarantee `CLAUDE.md` says is model-independent. A
citation guard scored at 100% is the headline claim, honestly measured.

**What it does mean is that the headline is a verification score, not a retrieval one**, and
the two should never be quoted as though the first vouched for the second. **49 cases —
3.3% — ask a question in words nobody drew from the corpus**, and those score **30/49,
61.2%**, against an overall 92.7%. The distance between 92.7% and 61.2% is the distance
between *can it prove what I quote* and *can it answer what I ask*, and this project is
much better at the first, which is the one it promised.

**A practical consequence, recorded because it bit the same day.** An identity-free
validation of a retrieval change cannot use `retrieval/*` at all. For the Tibetan the only
identity-free signal is `topical/tibetan` — **nine cases**, currently 1 of 9 — which is too
small to steer on. Anything that claims to improve Tibetan retrieval either finds a
non-84000 English source or reports against a probe it cannot fully trust, and says which.

**3. A mechanism that explains the data is not evidence for the mechanism.** Scaling
MITRA from 205 to 27,956 chunks moved the controlled rung's columns in opposite
directions: work-level 81.0% → **94.6%**, on the line 40.0% → **33.2%**. The obvious
account is displacement — `covers?/2` needs the covering span inside the limit-100
window, and thousands of new sibling chunks from the same work crowd it out. It fits the
data, it fits the hit log full of *"rank 1, the work but NOT the parallel line"*, and it
is **wrong**. Re-run at `--limit 200`, the maximum the retrieval layer allows: **194 ·
94.6%, on line 68 · 33.2%** — identical to the digit. Not one covering span sits in ranks
101–200.

The correct reading is stronger and less comfortable: the covering chunk is out-ranked
*past 200* by same-work near-duplicates, and **more `k` does not buy the line column
back**. The test cost one 205-case run. Rule 62 says re-derive a number that confirms what
you just concluded; this is its twin for *explanations* — a mechanism that would change
what gets bought next is worth the one command that can falsify it.

## Glossary pinning buys 4.3 points, and the spec asked for it without measuring — 2026-09-02

`docs/PLAN.md` specified the index tier as "prose, **glossary-pinned**". Nothing
implemented it, and building it was what showed the idea is two-sided rather than a
settled good.

**What a glossary actually holds.** Of 24,811 Chinese-English pairs, most are
*definitions rather than renderings* — `娑婆` glosses as "a transliteration of Sabhā (=
Sahā, the name of the world in which we live)", which is true and is not what a
translator writes. 4,533 entries survive a term-like filter, and **4,353 of those are
unanimous** across every glossary recording them, which is far better agreement than
`Pramana.Translators` found on Sanskrit headwords (475 of 601 disagreeing).

**But the first pinned prompt opened with `云何 = why?`** — a function word that is "how"
or "what is" at least as often — and `比丘 = bhikṣu`, which moves the English *away* from
the "monk" a reader types. Restricting pins to 3+ character compounds, where the
doctrinal vocabulary lives, leaves 1,723 terms and pins 119 of 205 passages.

**The hypothesis was genuinely two-sided.** Pinning buys vocabulary consistency, which is
what an index wants; it also pins the *lexicographer's* phrasing, and the index tier is
scored on whether a **reader's** English reaches the line. The glossary says `四念處` is
"four applications of mindfulness" while the gold set asks for "four **foundations**".

    arm                              found the work   on the line
    gemma-2-9b-it, unpinned           135/205 65.9%    55  26.8%
    gemma-2-9b-it, PINNED             144/205 70.2%    56  27.3%
    gemma-2-mitra-it, unpinned        166/205 81.0%    82  40.0%

**Pinning helps, by 4.3 points at work level and by nothing on the line.** That is 9 net
cases out of 205 — suggestive, not conclusive, and it is recorded here as suggestive.

**It does not change the model choice, which is the decision it was run to inform.**
Pinned `base` at 70.2% still trails MITRA's unpinned 81.0% by 10.8 points, more than
double what pinning buys — and MITRA has no instruction slot, its template being fixed, so
it cannot be pinned at all. The tranche runs MITRA unpinned.

**Two things that keep this honest.** Pinning demonstrably applied: 119 of 119 pinned
passages differ from their unpinned counterparts, so a null result would have meant "does
not help" rather than "never ran". And compliance is loose — told `舍衛國 = śrāvastī`, the
model wrote "Sravati" — so this measures pinning **as it behaves**, not as specified. A
model that honoured its pins exactly might score differently.

---

## The quotation graph is not a citation graph — 2026-09-02

Everything that ranks works by "cross-work citation weight" — which works get an English
layer, in what order, for how much money — reads a graph built by **suffix-array
shared-text detection**. Its edges mean *these two texts share a passage*. They have been
read all day as if they meant *this text cites that one*.

**Measured, and they do not.** Classical Chinese marks a citation: `經云`, `論曰`, `頌曰`
sit immediately before the quoted span, on the quoting side only. Over the 48,650
cross-family pairs, taking the quote's head against the segment it starts in plus the one
before:

    pairs                                   48,650
    quote locatable in its context          19,422   40%
    a citation marker on either side          ~394    0.8%
    DIRECTED by marker                         287    0.6%

**287 pairs, against 9,812 that role and date resolve.** The marker signal is 34× weaker
than the thing it was proposed to replace, and the reason is not that the markers are
missed — it is that **the edges are mostly not citations**. Shared text between two
canonical works is usually formulaic phrasing, a stock passage, or two translations of one
Indic original. Almost nobody says "the sūtra says" first.

**So a demand ranking off this graph is closer to a genre measure than an importance
measure**, and that explains what it produced: 法苑珠林, an encyclopedia, topped the
undirected ranking because sharing text with everything is what an encyclopedia does, and
catalogues followed for the same reason. Directing by `text_role` and `date_start` helped
because those encode something real about the works; markers cannot help, because the
relation being directed is largely not the relation assumed.

**Two things follow.** The tranche selected on 2026-09-02 stands — the directed top-10 is
Prajñāpāramitā, Lotus, Avataṃsaka, Ratnakūṭa, and adding the Āgamas covers the gold set —
but it was chosen by a proxy weaker than its name suggests, and a *better* demand signal
would come from somewhere else entirely: what readers ask, or what the commentarial
tradition actually explains (`work_relations`), not what shares phrasing.

And **the measurement was nearly void twice**. The first query substringed into
`texts.body`, megabytes per row, 97,300 times, and never finished. The second searched for
the whole 37-character quote inside a 17-character segment and returned 0 directed out of
48,650 — a clean, publishable-looking zero that meant only that the query was wrong. The
diagnostic that caught it was counting how many quotes were *locatable at all*, which the
first two versions never reported. **A zero with no denominator beside it is not a
finding.**

---
