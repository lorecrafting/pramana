# Project history — chapter 12

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### Retrieval depth is worth +7 cases and costs 5.4x (#10) — measured, not adopted

The probe above suggested fusion depth was worth real recall. It is, across every
tradition, and the price is the reason it is not simply switched on. All 446 `retrieval`
cases, depth 60 (the shipped default, `limit * 3`) against depth 200:

| | depth 60 | depth 200 | |
|---|---|---|---|
| retrieval / chinese | 97.8% (227/232) | **98.3% (228/232)** | +1 |
| retrieval / pali | 53.3% (80/150) | **54.7% (82/150)** | +2 |
| retrieval / tibetan | 31.3% (20/64) | **37.5% (24/64)** | **+4** |
| **overall** | 73.3% (327/446) | **74.9% (334/446)** | **+7** |
| **wall clock** | **~50 min** | **4h25m** | **5.4x** |

**Nothing regressed**, which is what the pre-registered rule required, and Tibetan's 24/64
has now been produced three independent times — the depth-200 probe, an isolated Tibetan
arm, and this full run. Read the per-row gains carefully though: **only Tibetan's +4 clears
the one-case ANN wobble on its own.** Pāli's +2 and Chinese's +1 are inside it and should
not be quoted as established; the aggregate +7 is what carries.

**The cost is the finding.** 35.6 s per case against ~6.6 s, which is *more expensive than
per-tradition retrieval* (22.7 s/case) despite running one scan instead of three. The
lexical arm is why: at depth 200 it pulls 200 segments out of a 4.7M-segment bigram index
and maps every one to its containing chunk, and the 232 Chinese definitional-formula cases
hit that hardest. As a default it would take the 1,400-case gate from about an hour to
about five, on a check meant to run at every phase gate.

So depth ships as an **option**, not a new default. The middle was then measured, over the
same 64 Tibetan cases:

| depth | retrieval / tibetan | mean rank |
|---|---|---|
| 60 (default) | 31.3% (20/64) | 3.1 |
| **120** | **39.1% (25/64)** | 3.2 |
| 200 | 37.5% (24/64) | 3.0 |

**The whole gain arrives at depth 120.** 25 against 24 is one case, inside the ANN wobble,
so 120 and 200 are indistinguishable on recall and the extra 80 candidates buy nothing.

**The first wall clocks were cache weather, and an ABBA run replaced them.** Depth 120 had
timed at 13m12s against depth 200's 11m21s — backwards, since 120 does strictly less work.
Those arms ran hours apart, and this session already measured cache state moving
`coverage/1` by 5x. So the arms were re-run **back to back in one session, in ABBA order**
(60, 120, 120, 60) to cancel drift:

| arm | depth | recall | scoring time |
|---|---|---|---|
| 1 | 60 | 20/64 | 7m24s |
| 2 | 120 | 25/64 | 11m01s |
| 3 | 120 | **crashed** | — |
| 4 | 60 | 20/64 | 7m32s |

The two depth-60 arms agree to **1.8%**, which is what a usable cost baseline looks like
and what the earlier 5m16s figure was not. **Depth 120 costs 1.47x**, nothing like depth
200's 5.4x, and it carries the whole recall gain.

**And it is still not the default, because one arm in two died:**

    ** (DBConnection.ConnectionError) client timed out because it queued and checked out
       the connection for longer than 120000ms
       lib/pramana/retrieval/lexical.ex:296: Pramana.Retrieval.Lexical.run/4

A single **lexical** query exceeded the 120-second pool timeout and took the whole run with
it. Three things follow, and the last two matter more than the depth question:

- **A default that occasionally kills a multi-hour gate is not a default.** Depth 120
  sits on the edge of the timeout and which side it lands on depends on cache state.
- **The cost of depth is in the BIGRAM index, not in HNSW.** Every intuition here had been
  that depth buys vector-scan time; `lexical.ex:296` says otherwise, and it explains why
  the 232 Chinese definitional-formula cases dominated the 4h25m run. Tuning the vector
  side would have optimised the wrong half.
- **A lexical query can take over two minutes**, which is a live risk on the MCP surface
  and has nothing to do with evals. It is its own defect and its own task.

**This section previously ended "Both halves are now fixed". That was wrong**, and it was
written the same morning the `texts.body` fix landed, on the assumption that the 32x
speedup removed the timeout. It did not. A four-arm ABBA re-run afterwards timed out again
on the same line, and the real cause turned out to be the n-gram fallback — see *The
two-minute lexical query was 135 OR'd LIKEs* below. The claim is corrected rather than
deleted because the mistake is the instructive part: **a speedup measured on one workload
was assumed to fix a timeout observed on another**, and the two workloads were Chinese
phrase queries and English n-gram fallbacks, which share a line number and nothing else.

The same timeout is what killed the depth-200 arm hours earlier; that death was invisible
because a `grep` in the pipeline swallowed the error while the loop still exited 0. The
progress heartbeat added the same day earned itself immediately — the log shows
`10/64 · 1m12s` and `20/64 · 2m24s` before the crash, so the failure point is known rather
than guessed.

**A process note that cost hours.** This run produced no output for 4h25m, so "how far
along is it" was unanswerable and three ETAs were wrong — all extrapolated from a Tibetan
arm that turned out to be the *cheap* tradition. The gold files also load alphabetically,
so the expensive Chinese cases run first, which makes any linear projection from early
elapsed time wrong in the same direction. `mix pramana.evals` now prints a progress
heartbeat for exactly this reason.

### The slow lexical query was `texts.body`, and it was 32x (#10)

`lexical.ex:296` in the crash stacktrace was `Repo.all`, and what it was fetching was the
whole corpus body, repeatedly. The query joined `texts` and preloaded through the join:

    |> join(:inner, [s], t in Text, on: t.id == s.text_id)
    |> preload([_s, t], text: {t, [:work, :witness, :source]})

A join-preload ships **every** column of the joined row, `texts.body` included — the
entire normalized work — **once per matched segment**, and the query over-fetches
`limit * 5` rows before ranking in Elixir. Bodies average **27,218 characters** and the
largest is **13,279,028**, so a 20-result search pulled 100 bodies through shared
buffers to read a title and a licence class off each. **Nothing in the result path reads
`body`**: `Corpus.span_from_segment/1` wants `work`, `witness_id`, `source_id`,
`source.license_class`, `volume` and `meta`, and `Corpus.body/1` fetches the body itself
when offsets need verifying.

The fix is a separate preload query selecting every `texts` column except `body`, which
also loads each DISTINCT text once instead of once per row.

Measured against the full dev corpus (15,489 texts, 6.5M segments), five Chinese
formulae, each warmed then timed 5x, minimum taken — and run **ABBA** because this
session had already been burned by cache weather:

| query | join-preload | separate preload |
|---|---|---|
| 一切有為法 | 278 ms | 13 ms |
| 四聖諦 | 542 ms | 7 ms |
| 無明緣行 | 285 ms | 10 ms |
| 如是我聞 | 147 ms | 10 ms |
| 般若波羅蜜多 | 151 ms | 4 ms |
| **total** | **1403 ms** | **44 ms** |

The repeat arms landed at 1491 ms and 47 ms — 6% and 7% apart, so the 32x is real and not
weather. This is warm-cache; the 120-second timeout was a cold one.

Two things this teaches:

- **`preload` through a join is not free, and its cost is invisible at the call site.**
  The one-line idiomatic form is the expensive one, and it gets more expensive the
  larger the widest column in the joined table is. `select: struct(t, [...])` in a
  separate preload query is the cheap form — and it must be `struct/2`, not a `%Text{}`
  literal, which loses the binding and makes Ecto refuse the query outright.
- **A column list in a `select` is a drift surface.** A new `texts` column not added to
  it reads as `nil` with no error anywhere. The test asserts the emitted SQL names every
  `Text.__schema__(:fields)` entry except `body`, so adding a column and forgetting this
  list fails a test instead of silently blanking a field.

### One case may not kill the run (#10)

The same crash exposed a second defect, and this one is a rule the project already holds
everywhere else: *one malformed file fails one job, never the bake* (`CLAUDE.md`). The
evals harness did not honour it. `score_case/2` had no rescue, so a single
`DBConnection.ConnectionError` propagated out of `Enum.map` and took **4h25m of scoring
with it**, discarding every case already completed. It happened twice, and the first time
a `grep` in the pipeline swallowed the error while the loop still exited 0.

A crashed case is now its own outcome, `{:error, detail}`, and the loop continues.
The scoring rules follow from what an error actually is:

- **Not a miss.** A query that timed out is not the retriever failing to find the
  passage. Counting it as one publishes a recall regression that never happened.
- **Not stale either.** Stale means the gold set aged; an error means *we* broke. They
  are excluded from the denominator for the same reason and printed separately because
  the reader needs to know which one it is.
- **Never silent.** Errors get their own header line, their own section, a `[n ERRORED]`
  suffix on every affected row, and an `"errors"` key in `Score.to_map/1` so a JSON
  artefact carries the fact too. A rate over zero scored cases still prints as "no cases
  scored", not 0.0%.
- **`--gate` refuses to run at all** when any case errored. Errored cases are missing
  hits, so the ratchet would either report a regression that did not happen or — with no
  baseline on disk — *install* the under-measured run as the baseline every future run is
  compared against.

The last point is the one worth generalizing: making a long run fault-tolerant is only
half the job. The other half is making sure the shrunken denominator cannot be read as a
result.

### The two-minute lexical query was 135 OR'd LIKEs (#10)

The `texts.body` fix was 32x and did **not** fix the timeout. A four-arm ABBA re-run after
it died on the same line, so the cause was measured properly instead of assumed.

It is not the phrase stage. `:auto` runs the phrase first and falls back to n-grams when
the phrase returns nothing — which for a cross-lingual English query is *always*, since an
English sentence never appears verbatim in Tibetan source text. `ngrams/2` then windowed by
**grapheme at width 3** for anything not Tibetan, so a 145-character English sentence became
**135 distinct trigrams**, OR'd into one `WHERE`. `EXPLAIN` on the full corpus:

| stage | plan | est. cost |
|---|---|---|
| phrase — 1 pattern, 145 chars | Bitmap Index Scan on `segments_content_bigm_index` | 4,698 |
| ngram — 135 trigram patterns | **Seq Scan on segments**, 6,538,238 rows | 3,043,842 |

Past a tipping point the planner abandons pg_bigm and scans the whole table, testing one
substring per predicate per row. `LIMIT depth * 5` with no `ORDER BY` is what made it
*intermittent* rather than merely slow: the scan stops when it fills the limit, so runtime
depends on where matches fall in heap order. Depth 60 filled 300 in time; depth 120
sometimes failed to fill 600 inside the 120 s pool timeout.

**The cliff is selectivity, not a predicate count** — measured, having first assumed
otherwise. On one query the index survived 24 predicates; on another it was abandoned at
**10**. The difference is short common words, which is why the fix is one rule and not two:

- drop words under 3 characters — the exact analogue of the `@particles` list that already
  drops 之, 於, 者 from Chinese as "grammatical particles, not content". `to`, `at`, `in`,
  `on`, `by` are the same thing, and length says so without a dictionary.
- keep the **longest 20**. Length is a dictionary-free proxy for rarity, and rarity is what
  keeps the planner on the index. Longest-first held the index to 24 predicates on the
  query where first-20-in-order flipped at 10.

Verified over every alphabetic query in the gold set: **252 queries, 252 BitmapOr plans,
zero sequential scans.**

**This is the third instance of one defect.** The module already refuses jieba for Chinese
because "a single common character appears on nearly every line", and refuses grapheme
windows for Tibetan because `་པ་` matched 89.6% of segments. Latin script has the identical
pathology and nothing caught it, because `tibetan?/1` was the only script test and
everything else fell through to trigrams. The windows were simultaneously **useless** — a
Latin trigram is a fragment of no linguistic standing, and can only match the Latin-script
(Pāli) part of the corpus, so on a Tibetan question the whole lexical arm entered the
fusion as noise — and **expensive**, because 135 of them defeat the index.

**A known residue, left deliberately.** `the` is exactly at the length floor and survives.
It is the same shape as `་པ་`: a predicate that votes for nearly every Latin-script line.
Min-3 plus longest-20 is what was *measured* to keep all 252 gold queries on the index;
whether also dropping function words improves recall is an eval question, and `@particles`
is the precedent for fixing it if the eval says so.
