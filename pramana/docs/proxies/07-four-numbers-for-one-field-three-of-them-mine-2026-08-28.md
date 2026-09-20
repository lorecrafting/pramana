# Why every proxy lied — chapter 7

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../PROXIES.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

### Four numbers for one field, three of them mine — 2026-08-28

Sizing DILA's place authority before building it, `<geo>` coverage was measured and
published four times. The file did not change.

| measured over | pattern used | value |
|---|---|---|
| 8,510 entries (a 4 MB `Range:` request) | `<geo>` | 99.4% |
| all 59,335 entries | `<geo>` | 2.3% |
| the 284 places this bake cites | `<geo>` | **0.0%** |
| the same 284 | `<geo` | **100.0%** |

**The tag is `<geo cert="high">`.** A pattern matching `<geo>` finds the bare form, which is
what the head of the file uses, and silently reports absence everywhere else. It did not
error. It returned a plausible number.

Two failures, and the second is the one that cost the time.

**A prefix of an id-ordered file is a stratum, not a sample.** DILA assigns `PL` ids
thematically: the early ones are the Indian and Central Asian countries of Xuanzang's
travelogue, geocoded and glossed in English by someone; the tail is Chinese districts. A
`head -c 4000000` on 31 MB looked like a 9% sample. English placeName really is rare — 24
in that prefix, 1.2% file-wide, 4.9% among the places this corpus cites — so that half of
the first correction stood. The `<geo>` half did not.

**The number that confirms your correction is the one to re-derive.** 0.0% arrived while a
paragraph retracting the earlier 99.4% was already being written, and it agreed. That
agreement is exactly why it went out unchecked. Opening three actual records and reading
them — a minute of work — showed `<geo cert="high">` immediately, and is the second method
that should have been used before publishing the first.

**What it cost.** No code, because this was sizing. Three separate retractions in
`docs/PLAN.md`, which are kept rather than collapsed into the final number, and a feature
nearly designed away from coordinates that are present on **every place this bake cites**.


### A recall probe that reported 0.0% twice — 2026-08-29

`Pramana.Recall` measures retrieval against ground truth the corpus already holds: 141,073
verbatim quotations, each a statement that one passage occurs in two named works. If a search
for that passage surfaces only one of them, that is a recall failure nobody had to label.

It reported **0.0% recall over 120 pairs** on the first run and again on the second. Both
times the retriever was fine and the probe was wrong, and both times the number was
*plausible* — a broken measurement does not raise.

**A segment is the unit the index matches within.** A quotation spans lines, and the `\n` in
its stored text are real segment boundaries, so the concatenated passage cannot be found
inside any one segment. This is the same fact `Pramana.Guard`'s `:spans_line_boundary`
diagnosis exists for — written two items earlier in the same session, and walked into anyway.

**Punctuation must not be stripped when querying the index.** Everywhere else in this project
stripping CBETA's editorial punctuation is correct, because it is the editor's and not the
witness's. The index holds what the editor printed, so a stripped query matches nothing.
Stripping is right when comparing two passages to each other and wrong when asking the corpus
a question — the distinction is *what is on the other side of the comparison*.

The corrected figure, over 2,000 pairs with a fixed seed:

    decided     1,891      both works  1,891      recall 100.0%
    undecided     109      (result set filled the cap — absence is not evidence)

**What that number is worth, and what it is not.** It says lexical phrase retrieval reliably
finds both ends of an exact repeated passage, which bounds where retrieval failures can live:
not in exact matching. It says nothing about semantic or cross-lingual retrieval, which is
where `topical/chinese` has been 0% since it was first measured. A probe that confirms the
strong axis is worth having and is not evidence about the weak one.


### The cross-lingual number, and the control that nearly buried it — 2026-08-29

`topical/chinese` has been 0% of twelve gold cases since it was first scored. Twelve cases
cannot be steered on, so the axis was not stuck: it was unmeasured. SuttaCentral's curated
parallels are 10,493 Pāli↔Chinese relevance judgements made by scholars, sitting unused.

    control (same language)   26/125 decided   20.8%
    cross-lingual              2/496 decided    0.4%
    cross vs same                               1.9% of same-language recall

**The control is what makes the number mean anything, and it was nearly discarded.** The
first version of the probe called any control below 50% a broken run — a floor picked from
nothing, which is the mistake this document exists to record. Measured, same-language
paraphrase retrieval is ~21%, and that is very likely the real ceiling for the task: a
parallel records that two discourses *correspond*, not that they share words, and finding one
inside the top hundred of 12.5 million segments is genuinely hard.

Had the floor stood, a working measurement would have been thrown away as a fault, and the
project would still be quoting 0% of twelve.

**Read the ratio, not the rate.** 0.4% alone is moved by the corpus, the cap and the
difficulty of paraphrase retrieval. Against the identical task in one language it isolates
the language barrier: it costs 98% of the achievable recall. That is a checkable claim; "weak
cross-lingual retrieval" is not.

**Cost of getting here.** Three wrong readings before this one. `--mode lexical` silently ran
hybrid, because `:lexical` is not a mode and an unrecognised name falls back to `:hybrid` by
design — 3.6 s per query, mistaken for a slow lexical path. Phrase mode then reported 0.0%
cross-lingual with a 10% control, which the control correctly refused to publish. Only the
third run, with the serving loaded and the floor corrected, produced a figure worth writing
down.

## The quotation graph as a demand proxy — contaminated twice, 2026-09-02

Sizing E1's translation spend needs to know how concentrated demand is: if a few hundred
works absorb most retrieval, translating them buys most of the benefit. The quotation
graph — 141,073 verbatim reuses — looks like the obvious measure of which works the canon
itself leans on.

**First reading, and it was wrong: "the top 50 works are 82.3% of all quotations."**

That number is one text quoting itself. T0220b and T0220c are sections of the
大般若波羅蜜多經 and account for **87,659 of 141,073 quotations — 62% of the graph** —
and 66,841 of T0220b's point at T0220a, another section of the same sūtra. The Large
Prajñāpāramitā is famously repetitive; the detector is finding that repetition, correctly,
and it is not citation.

Measured across the whole graph: **92,545 of 141,073 pairs, 65.6%, join works sharing a
five-character id prefix** — the same work split into CBETA sections.

**Corrected to cross-work pairs only**, the graph is 48,528 quotations and the
concentration is real but weaker: top 50 works 53.3%, top 100 **66.1%**, top 200 78.4%.
The ranking becomes recognisable, which is the check that matters — 順正理論, 法苑珠林,
妙法蓮華經, 摩訶般若波羅蜜經, both Āgamas, 大般涅槃經, 大方廣佛華嚴經.

**A second contamination remains, smaller and named rather than corrected.** T2157
貞元新定釋教目錄, T2148 and T2153 眾經目錄 are **catalogues**: they enumerate texts, so
they quote hundreds of works and rank near the top while nobody reads them for doctrine.
Citation weight is a proxy for what the tradition cites, and the tradition includes its
own librarians.

**And the deeper limit, which no correction reaches.** This measures what the canon cites,
not what a modern English-speaking reader asks. They plainly correlate — the Lotus and the
Āgamas are on both lists — and they are not the same thing, and there is no data here that
measures the second. A figure derived from this should be read as "what the tradition
leans on", never as "what users want".

**The habit, again.** The first number was checked by looking at the ranking it produced,
which took thirty seconds and would have been skipped if the number had looked
unremarkable. It looked *excellent* — 82.3% is the answer you want when you are hoping
demand is concentrated — and that is exactly the condition under which this project has
been wrong before.

## The dense-gloss test that queried itself — 2026-09-02

`docs/TRANSLATION.md` asks whether index-tier English needs to be prose, since nobody
reads it. A dense gloss — content words only — would be about half the tokens, and at
~73,000 chunks that is real money.

**The first test said prose won 150 pairs to nothing.** It queried with the very text it
was scoring: `embed(t)` against `embed(t)`, cosine 1.0 by construction. That is not a
result, it is an identity — and it read as a clean, decisive negative, which is exactly
the shape rule 62 warns about.

**Fixed by using a second translator's rendering of the same chunk as the query.** 574
chunks carry two independent human renderings; one asks, the other answers. Corrected:

    mean margin over best distractor    prose 0.0989   dense 0.0549
    beats every distractor              prose  99.3%   dense  86.7%
    dense >= prose                                     4.7% of pairs
    length                              657 chars ->   348 (53.0%)

The conclusion survives and is now earned: **prose retrieves substantially better.** Half
the tokens costs nearly half the margin and 12.6 points of "would be retrieved at all",
and recovering that needs roughly double the coverage — more than the 47% saved.

**What this does NOT rule out.** It tested *mechanically stripped prose*, not a
purpose-written gloss. A model asked for "the terms, names and doctrinal vocabulary of
this passage" would write something different, and probably better, than a stop-word
filter produces. The cheap version of the idea is dead; the idea has not been tested.

And the embedder is a variable: BGE-M3 is trained on natural language, so stripping
function words moves the text off-distribution. A different model might not care.
