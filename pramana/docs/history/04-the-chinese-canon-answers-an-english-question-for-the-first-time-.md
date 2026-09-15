# Project history — chapter 4

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

## The Chinese canon answers an English question for the first time — 2026-09-03

`topical/chinese` had been **0 of 12 for the life of the project**. It is now **6 of 12**.

The tranche was 27,956 MITRA renderings over 14 CBETA works — the top 10 by directed
citation weight plus the four Āgamas — generated the day before and waiting on a GPU.
Embedding was the cheap part: 27,751 rows missing a vector, **3.7 minutes on a Modal L4 at
126.8 chunks/s**, 0 rejected on hash, dimension or id. Coverage went from **191 chunks to
27,956 of CBETA's 719,543 — 0.027% to 3.88%**.

**The production verdict, over the whole 1,670-case population:**

| `--renderings --to cbeta.T`, all 1,670 | found the work | on the line |
|---|---|---|
| before | 782 · 46.8% | 539 · 32.3% |
| after | **1,269 · 76.0%** | **604 · 36.2%** |

**It beat the curve by a lot, and the first account of *why* was overstated within the
day.** The ablation curve hid vectors at *random* and predicted about 28% at work level
for a random 3.6%; a demand-weighted **3.88%** reached **76.0%**. This entry's first
version called that gap the demand-weighting premium. It is an **upper bound** on it: the
curve was measured by ablating **Pāli** and the 76.0% is **CBETA**, so two things vary
rather than one, and the direction of the bias is known — these 1,670 queries pick the
right work among the **14** CBETA works that have English, where the Pāli ablation picked
among 5,845. Isolating the premium needs a *randomly* selected CBETA tranche to compare
against, which is another tranche's money to price a decision already taken. Bounded,
left unmeasured, and said so. **Rule 80**, and it was caught by a sentence sitting a
hundred lines below the claim in the same file.

**And the surprise is that the two columns disagree.** Work-level nearly doubled; the line
moved 3.9 points. In the controlled rung — same 205 queries, same seed, index varied — the
line column went the *wrong way*: 40.0% → **33.2%**, while work-level rose to 94.6%.

The obvious explanation was displacement out of the limit-100 result window, and it is
**wrong**. Re-run at `--limit 200`, the layer's maximum: identical to the digit, 194 ·
94.6%, on line 68 · 33.2%. Not one covering span sits in ranks 101–200. The covering chunk
is out-ranked *past 200* by same-work near-duplicates, and asking for more results does
not buy it back. **Density buys the work and costs the line** — which is the finding that
should price the next tranche, because work-level on covered works is near saturation
while a reader who wants the right *line* is served at 36.2%.

**The gain is also not free to the other canons.** Against `evals/baseline.json`: −1 on
`topical/tibetan`, −1 on `retrieval/pali`, +1 on `retrieval/tibetan`. Deterministic runs
over an unchanged gold set, so those are real displacements — 27,956 new English vectors
compete in one pool and two cases another canon used to win, it no longer wins. Overall
92.3% → 92.7%, net +5.

**Three measurement traps surfaced on the way**, none of which broke anything and each of
which would have published a number answering a different question — the documented
`recall` invocation defaults to an unseeded 200-draw against a baseline measured over all
1,670; `evals/scorecard.json` is a 249-case file shaped exactly like the 1,472-case
`evals/baseline.json`; and a mechanism that fits the data is not evidence for the
mechanism. `docs/PROXIES.md` has all three.

**One thing is unexplained.** A 1,670-case run died at 25 minutes with `tcp recv (idle):
closed` while Postgres was demonstrably healthy — 4 days up, no OOM, no timeouts
configured, 45 of 100 connections. The re-run passed the same case. `docs/DEV_ENV.md`
records what was ruled out.

## 41% of the English over the Chinese canon was scrambled, and every count said it was fine — 2026-09-02

Preparing a sample for the model bake-off, not auditing anything. Pulling coherent
passages with Patton's English beside them produced text that did not read:

    One time, the Buddha was staying at Anāthapiṇḍada’s Park in Jeta’s Grove of
    Śrāvastī. Thus I have heard: It was then that the Bhagavān addressed the monks …

**The cause is a sort on a key that is not unique.** `Pramana.Chunk.Vectors` assembled a
chunk's English with `Enum.sort_by(& &1.first)` — the start ordinal of each rendering.
A translator working finer than the edition's citation unit puts two renderings on one
printed line: SuttaCentral's `sa810:8.2` anchors to Taishō `p0208b06` and `sa810:8.3` to
`p0208b06-b07`, and both start at the same ordinal. **2,080 of Patton's 3,354 renderings
sit in such a tie.** `Enum.sort_by/2` is stable, neither query had an `ORDER BY`, and the
two result lists were concatenated `point ++ range` — which breaks every tie in favour of
the point anchor whether or not it reads first.

**78 of 191 chunks — 41% — held scrambled English.** The damage is worse than it sounds,
because what gets displaced is the topic sentence:

    before  Those inside the city are kept safe, and external enemies are kept at bay.
            “Furthermore, suppose the king’s frontier city makes a path all around it
            that’s cleared, level, and broad. Those inside the city are kept safe, …

    after   “Furthermore, suppose the king’s city digs a moat, making it quite deep and
            wide, and it’s maintained dependably. Those inside the city are kept safe,
            and external enemies are kept at bay. This is called the second …

The scrambled chunk leads with a generic consequence clause and repeats it, having lost
the content a query would match on. That is the text that was embedded.

**Nothing counted it.** The right number of renderings, the right number of chunks, full
coverage, no error, no warning — the same signature as the two defects found the week
before. It was found by *reading* the assembled English, which is rule 60's habit applied
to a layer rather than to a tool.

**The fix is to record what the ordinal cannot recover.** A printed line does not know
that `8.2` precedes `8.3`; the source does. `mix pramana.sc.chinese` now writes
`reading_order` — the sūtra's number followed by the segment's dotted path — and the
assembly sorts on it, finishing the key with `last` and the anchor URN so a source that
records nothing is still deterministic. Now rule 71.

**It is also a reproducibility defect, not only a correctness one.** Nothing pins the
order `Repo.all/1` returns, so a translation chunk's `content_sha256` need not survive a
re-bake — which is `bake_id` no longer determining contents, invariant #3.

**A corollary found in the same hour: `on_conflict: :nothing` means a correction cannot
land.** `Chunk.Vectors.insert/1` deliberately refuses to rewrite a changed row, because
that would leave a vector describing words that are no longer there. Correct — but it
then reported **"new translation rows: 0"** for 78 chunks whose text had changed, which
reads as "nothing to do". A write path that declines to write has to say so: the builder
now counts stale rows and prints them, and `mix pramana.vectors --refresh` drops and
rebuilds them. The 78 were rebuilt and re-embedded.

**A third instance, swept for and found benign.** `Pramana.Retrieval.Rerank` aggregates
the same renderings with `string_agg(DISTINCT t.text, ' ')` — no `ORDER BY`, so Postgres
emits them *alphabetically* — under a comment claiming "concatenated in reading order".
The score is a `MapSet` intersection, so order is unobservable and nothing is wrong with
the reranker. The comment was wrong and is the thing someone would copy; it now says why
the order is safe here and nowhere else.

**The bearing on E1.** The baseline this slice published — 63.0% work-level and 37.0% on
the line for `--renderings --to cbeta.T` — was measured against the scrambled text. Had a
model arm been run first, the difference would have been attributed to the model.
**Measure the substrate before the model**, and re-measure after any fix to the layer
being compared.

**And re-measuring it produced a fourth instance of silent degradation, this time in the
instrument.** The first re-run returned **`0/200 decided 0.0%`** against that 63.0%
baseline, which read as a catastrophic regression in the layer just repaired. It was
nothing of the kind: `Pramana.Embed.Serving` starts only under `PRAMANA_EMBEDDING=1`, and
`Pramana.Retrieval` degrades to lexical-only without it — correct for a search, which
should not crash, and wrong for a probe, because English words do not appear in Chinese
source text and so **every** cross-language case misses. The run printed a confident
0.0% with no warning.

`Pramana.Retrieval`'s own comment already records this failure — "the semantic arm
silently did not run" — arriving through a different door. `mix pramana.recall` now
refuses to start in a semantic or hybrid mode when the serving is not running, and says
what to set. Rule 17: a dependency that degrades has to be loud *somewhere*.

Two false alarms in one afternoon, in opposite directions: a real defect that every count
called healthy, and a healthy corpus that the instrument called dead.

---

## The Chinese canon gets an English layer, and it is not enough — 2026-08-31

§ E1's first slice. `mix pramana.sc.chinese` and `Pramana.Sc.Lzh`: **3,354 CC0 English
renderings anchored to Taishō lines**, the first English over the Chinese canon in this
corpus. 86.9% of anchors matched the two editions' text exactly; 13.1% are bounded by
neighbours that did and stamped as such; 2 segments were dropped.

**It was already on disk.** Charles Patton's English of 54 Saṃyukta and Madhyama Āgama
sūtras had been in the `sc-translations` lockfile entry since #39 and discarded at every
ingest, because its anchors name SuttaCentral addresses and this corpus holds those Āgamas
as CBETA. It landed in `no_such_anchor`, the same counter the Pāli's legitimate elisions
use, so it read as noise. The sparse checkout had never fetched `root/lzh` either.

**And `topical/chinese` did not move.** Still 0 of 12; `--only topical` scored 51.0%
against a baseline of 51.0% with every tradition row identical, so nothing regressed and
nothing improved. 191 English chunk vectors over the Chinese against 55,135 over the Pāli
answer the same English question, and the Pāli wins. Isolated from that competition,
`mix pramana.recall --renderings --to cbeta.T` scores 63.0% work-level and **37.0% on
line** over 200 seeded pairs.

**A control changed the story on the way.** Scoped to CBETA, "How is mindfulness of
breathing taught?" returns the SĀ ānāpāna sutras at ranks 1–4, which looked like the
result. The nearest CBETA vectors to that query are `parallel_gloss/en/sujato` at d=0.143
and 0.153 — machinery that predates this work — with Patton's own vector third at d=0.224.
Rule 62, caught before it was written down as a finding.

**Two latent defects surfaced.** `Pramana.Chunk.Vectors` excluded every range-anchored
CBETA rendering (2,089 of 3,354) by testing `urn_prefix <> "@"` against an address that
puts the juan in between — now rule 68 and `Pramana.URN.addresses?/2`. And
`mix pramana.recall --renderings` reported hits per language with no denominator, inside
the instrument rules 22, 44 and 54 are measured with.

## The coverage curve, and a demand proxy that was 62% one sūtra — 2026-09-02

E1's open question was a price: matching Pāli's English coverage over CBETA is ~720,000
chunk translations and nobody had measured what fraction would do. Pāli is the only canon
that can answer it, so its English layer was ablated at seven levels through the query
that ships.

**Returns are strongly concave.** The first 5% of coverage buys 38% of the achievable
gain; the last 75% buys 32%. My first reading of the curve was backwards — from the top it
looks like "no knee", because 100%→50% costs 16.5 points; the purchasing question is what
a unit *buys*, and by that measure early coverage is worth ~17× late coverage.

**The 0% control validated the instrument**: 4.0% with no English layer at all, and CBETA
sits at 0.027% coverage with `topical/chinese` at 0 of 12.

**Then the demand proxy lied, in the flattering direction.** "Top 50 works are 82.3% of all
quotations" is one repetitive sūtra quoting itself — T0220b and T0220c are 62% of the whole
graph, and 65.6% of all pairs join sections of a single work. Corrected to cross-work
pairs, concentration is real but weaker: top 100 works, 66.1% of citation weight, 10.2% of
CBETA's chunks. `docs/PROXIES.md` carries it.

It was caught by looking at the ranking the number produced — thirty seconds, and easy to
skip precisely because 82.3% is the answer one hopes for.

## Architecture review, the three audits a test cannot do — 2026-09-02

`docs/CHECKS.md` §2 asks for findings to be written here. Two of its five audits became
mechanical on 2026-09-01 (`Architecture.BoundariesTest`); these are the three that were
left, performed by reading.

**Can any tool return text without `urn` + offsets + `sha256`?** No, with one qualification
that is new today. `get_outline` looked like a candidate — its own file never says `urn` —
but the entries are built by `Corpus.outline/1`, which puts one on each. `survey_corpus`
returns counts rather than text.

**`compare_translators`, added today, returns Chinese and Sanskrit headwords with no URN.**
They are not corpus spans — they are lexical entries from a third-party dictionary, and
each response names Karashima and the licence — so invariant #1 is not violated on a
strict reading. But **the anchors now exist**: `glossary_anchors` resolves 25,504 of those
citations to lines this bake holds, and attaching one to each divergence would make every
comparison openable and byte-verifiable rather than merely attributed. Recorded as work,
not as a violation. `docs/PLAN.md`.

**Is any generated translation reachable as a top-level URN?** No. `Pramana.Translations`
addresses a rendering as a fragment over its anchor (`…#tr:en/patton`) and the guard's
`:not_citable_as_source` verdict is exercised by tests. Nothing added today creates a new
path to one: `Pramana.Repair` rewrites a caller's own document and never mints a URN, and
`Pramana.Citation` resolves foreign citations only to lines that already exist.

**Is the bake still reproducible from `sources.lock.json` alone?** Yes, and it is now
harder to break: the gate's lockfile step passed on 2026-09-02, and all eleven tasks that
write the lockfile re-record the bake, enforced by a structural test rather than by
memory.

**The judgement the section exists for** — *has this codebase quietly stopped being the
thing it was designed to be* — is the one nobody can delegate, and it is not answered here.
