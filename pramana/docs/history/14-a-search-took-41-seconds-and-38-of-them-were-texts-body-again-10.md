# Project history — chapter 14

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

### A search took 41 seconds, and 38 of them were `texts.body` again (#10)

The whole day's work on the lexical arm was optimising **0.03%** of the query. Profiled
after the depth work, five Chinese gold queries, warmed:

| | before |
|---|---|
| lexical arm | **14 ms** |
| semantic arm | **41,142 ms** |

A 41-second search is a product defect before it is a gate problem — an MCP caller waits
that long for one `search` call. Splitting it further: the query embedding is **555 ms**
and the database is **~38 s**, while the equivalent ANN query in `psql` runs in **357 ms**.
So it was never HNSW, never `ef_search`, and never the iterative scan.

**It was `texts.body`, in the three places the morning's fix did not touch.** Captured from
Repo telemetry, the semantic path emitted:

- **the ANN select**, which selected the whole `Text` struct — `body` included — for every
  candidate row, and this query over-fetches `limit * @vector_overfetch`;
- **an N+1 of ~120 queries**, one per result, each ~200–300 ms, each a
  `preload([s, t], text: {t, ...})` through a join in `Corpus.between/4` — and each one
  dragging a whole work to build a range span.

120 × ~250 ms is the missing 30 seconds.

**Four call sites, one defect, and the rule did not prevent it.** Rule 34 was written this
morning after fixing exactly this in `Retrieval.Lexical`, and by the afternoon the same
pattern was still live in `Corpus.between/4`, `Corpus.context/2`, `Corpus.fetch_span/1` and
`Semantic.single_search/2`. Writing the rule down did not sweep for other instances, and
nothing made the next author's `preload: [text: {t, ...}]` look wrong.

So it is a **shared function** now — `Text.preload_without_body/0` and
`Text.fields_without_body/0` — for the reason `Pramana.Batch` exists: the 65,535-parameter
limit was hit, written up as rule 14, and then hit again in a fresh call site. A rule in a
document does not survive being reimplemented; a function does.

**And the field list is now derived, not written.** The morning's fix listed every `texts`
column explicitly and its own comment admitted the list was "a drift surface" — a column
added later and not listed would read as `nil` with no error. `__schema__(:fields) --
[:body]` cannot go stale, so the drift surface is gone rather than merely tested.

Measured after, same five queries:

| | before | after | |
|---|---|---|---|
| semantic arm | 41,142 ms | **3,395 ms** | **12.1x** |
| hybrid search | 41,169 ms | **2,242 ms** | **18.4x** |

**And the gold set says it changed nothing but the clock.** All 446 retrieval cases:

| | before | after |
|---|---|---|
| overall | 334/446 (74.9%) | **334/446 (74.9%)** |
| chinese | 227/232, mean rank 1.98 | **227/232, mean rank 1.98** |
| pali | 82/150, mean rank 3.09 | **82/150, mean rank 3.09** |
| tibetan | 25/64, mean rank 3.24 | **25/64, mean rank 3.24** |
| **wall clock** | **2h23m** | **17m22s** |

Mean ranks agreeing to two decimals is stronger evidence than the hit counts: not merely
the same passages found, but in the same order. `evals/baseline.json` therefore stays valid
— nothing it records moved.

**This retires the gate tension recorded above, by 10.3x.** Verified with a real `--gate`
run rather than projected: **1,400 cases in 18m13s against 3h08m**, 90.0%, every row
identical to baseline including mean ranks, `gate OK — no case type regressed`.

| | before | after |
|---|---|---|
| the 901 non-retrieval cases | ~28 min | **8 s** |
| the 446 retrieval cases | 2h23m | ~17 min |
| **full gate** | **3h08m** | **18m13s** |

**The non-retrieval half is the part nobody predicted, including twice by me.** I sized this
first at "~50 minutes" and then at "~21 minutes", both too pessimistic, because both times I
sized only the retrieval half I had been staring at. `provenance`, `citation_guard`,
`quote_verify` and `quote_reject` all resolve URNs through `Corpus.fetch_span/1` — one of
the four body sites — so 901 cases went from ~28 minutes to **8 seconds**. The same
estimation error as every other one today, in the flattering direction for once: **size the
whole thing, not the half you were looking at.**

A gate at 18 minutes is a different instrument from a gate at three hours: it can run on
every change rather than at phase boundaries. The tension was never depth against cost; it
was 38 seconds per search of pure waste, and no policy would have been the right answer.

**The lesson is about where the day went.** Every measurement was sound and every
conclusion followed from its evidence — the ABBA arms, the arm-attribution probe, the
pre-registered criteria. But the whole investigation optimised the lexical arm, which was
**0.03%** of the query, and the 41-second semantic arm sat unprofiled underneath all of it
because a *timeout stack trace pointed at `lexical.ex`*. The stack trace named the arm that
happened to hold the connection when the pool gave up, not the arm consuming the time.
**Profile the whole operation before optimising the part an error message names.**

### Translate the QUERY, not the canon (#43) — 0% to 91.7%, and term choice is worth 50 points

Stage B was scoped as generating English for ~300,000 Chinese chunks (~$260–770, plus
re-embedding, plus a 20:1 English-vector imbalance that #43 measured as likely to bury the
Pāli). The cheaper question was never asked: **`topical/chinese` and
`topical/chinese-native` are the same twelve questions in two languages**, scoring 0% and
100%. The passages are indexed and findable. Only the query is in the wrong language.

Two arms over those twelve, scored by the real harness with `expect_contains` **unchanged**
— only the query rewritten:

| arm | score | mean rank |
|---|---|---|
| English (shipped default) | **0.0%** (0/12) | — |
| **A — the term a translator would pick** | **91.7%** (11/12) | **1.0** |
| **B — a defensible synonym** | **41.7%** (5/12) | 2.8 |
| hand-written Chinese (gold) | 100% (12/12) | 1.25 |

**Translating the query recovers nearly everything, for no corpus change at all** — no
generated text stored, no new vectors, so the imbalance that blocked stage B never arises
and invariant #8 is not even engaged, because nothing generated is persisted. A
well-termed Chinese query returns at **mean rank 1.0**, better than the curator's own.

**And the whole risk is term choice, now quantified at ~50 points.** Arm B substituted
equally legitimate renderings and lost seven cases: 八聖道分 for 八正道, 四念住 for 四念處,
七菩提分 for 七覺支, 六處 for 六入處, 四等心 for 四無量心, 三十七菩提分法 for 三十七道品,
空定 for 空三昧. Each is real Buddhist Chinese; each is a register the *corpus does not
print here*, and lexical matching against a term the edition never uses returns nothing.

Two things make this trustworthy rather than a lucky sample:

- **The single Arm A miss was pre-registered.** Before scoring, the ambiguity note for
  top-021 read "緣起 vs 十二因緣 — the gold term is the latter". 緣起 was the one term where
  the natural translation and the canon's phrase diverge, and it is the one case that
  failed. The failure mode was predicted, not discovered.
- **Arm B's hit on top-021 is the inversion.** There the "alternative" happened to *be*
  the gold term, and it passed. The arms are measuring term choice, not query phrasing.

**This reverses the priority between the two candidate mechanisms.** Glossary term mapping
was assessed as too weak to matter — 84000's `glossary_entries` recovers only 2 of 12 gold
doctrinal terms as a *retrieval* method. But as a *constraint on translation* it is the
difference between 91.7% and 41.7%. `docs/TRANSLATION.md` already specifies the shape:
glossary-pinned translation with a visible term-mapping chain. It is not an enhancement to
query translation; it is the part that works.

**Caveats, because twelve cases is twelve cases.** One case is 8.3 points here, so Arm A
against Arm B is decisive while 91.7% against the gold's 100% is not. `topical/*` cannot
grow without more curated terms (it rejects terms too common to measure), so this axis
stays statistically thin by construction — the finding to bank is the *ordering* of the
arms, not their exact rates.

**What it would cost architecturally**, and the reason this is a decision rather than a
merge: it puts a model in the query path, which today has none. Search would stop being a
pure function of `bake_id` — the same question could return different passages on different
days — and it adds ~0.5–1 s to a search now running at 2.2 s. Neither touches the bake,
reproducibility of the corpus, or what is citable. A translation cache keyed by query hash
(ROADMAP anticipates one for Phase 7) makes the determinism objection largely go away.

### The glossary arm: the mechanism works, the term source does not (#43)

Built on the finding above — translate the query, and use a glossary rather than a model
because a glossary can expand to *every* attested register where a model must gamble on
one. `Pramana.Retrieval.Terms` maps English doctrinal vocabulary to Chinese from 84000's
1,105 English↔Chinese glossary pairs, and `Hybrid` fuses it as a **third arm**, so the
existing arms are untouched and nothing that works for Pāli or Tibetan can regress by
construction.

It works, on exactly the queries it can see. "What are the four noble truths?" expands to
`["四聖諦"]` and goes from **miss to rank 3**. And then the gold set:

| | before | with the arm |
|---|---|---|
| topical / chinese | 0.0% (0/12) | **16.7% (2/12)** |
| topical / pali | 56.3% (9/16) | 50.0% (8/16) |
| **answered from any tradition** | **72.7% (8/11)** | **63.6% (7/11)** |

**Two of twelve — which is the number this document already recorded and I argued myself
out of.** Sizing #12 established that "`glossary_entries` (84000) recovers 2 of 12 gold
doctrinal terms". Reading the glossary dump directly, I saw 四聖諦 and 四念處 alongside many
near-misses and called it "richer than 2 of 12 implied". It was not: the near-misses —
八聖道分 for 八正道, 菩提分法 for 七覺支, 四念住 for 四念處 — are **the wrong register for this
corpus**, which is precisely the 50-point failure mode measured in the arm B experiment an
hour earlier. The evidence to predict 2/12 was already in hand and was not applied.

**So it stays opt-in and off** (`expand_terms: true`). Under #44's standing rule a change
must be measured against answered-from-any-tradition before becoming a default, and this
one moves it the wrong way. The Pāli and topic losses are single cases, inside the
documented wobble, so the honest reading is not "it regresses" but "**+2 of 12 does not
justify a third arm diluting RRF**".

**The bottleneck is the term source, not the design.** 84000's glossary is oriented to the
Tibetan canon, and its Chinese equivalents come from translation traditions CBETA does not
print. A term list built *from this corpus* — every attested rendering, with occurrence
counts, adjudicated the way the topical gold terms already are — would plug into the same
arm unchanged.

**And a limit worth stating plainly, because it bounds the whole approach.** A glossary
fires on vocabulary. Measured directly:

    "What are the four noble truths?"                            -> ["四聖諦"], rank 3
    "What are the 4 things the buddha said when he was
     enlightened"                                                -> [], miss
    "what did the buddha realise under the bodhi tree"           -> [], miss

Both paraphrases return **8 of 8 Pāli results and no Chinese** — and the semantic arm
answers them *correctly* from the Pāli, with `Cattāri ariyasaccāni` at rank 4 on the first.
So a reader asking a paraphrase is not empty-handed today; they simply never receive the
Chinese witness. That is what `answered from any tradition` measures, and it is why the
three mechanisms are complementary rather than competing:

| | paraphrase | reaches Chinese |
|---|---|---|
| semantic arm | yes | **no** (0%, no English layer) |
| glossary arm | **no** (fires on vocabulary) | yes |
| LLM query translation | yes | yes, if term-pinned |

`docs/TRANSLATION.md` already specifies the combination — glossary-pinned translation with
a visible term-mapping chain. The measurements now say why neither half suffices alone: the
model supplies paraphrase understanding, the glossary supplies term fidelity, and the
glossary this corpus needs is one it has not got yet.
