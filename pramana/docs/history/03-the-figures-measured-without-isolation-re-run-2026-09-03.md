# Project history — chapter 3

> Historical evidence. Statements and commands below describe their recorded context, not current operating instructions.
> [Contents](../HISTORY.md) · [Documentation](../../../docs/README.md) · [Current architecture](../ARCHITECTURE.md)

## The figures measured without isolation, re-run — 2026-09-03

`ed0c154` repaired the defect: `--translators` and `--translation_coverage` restricted
candidate generation and not ordering, so every arm of the model ladder was reranked
against the whole English layer. It left the re-runs owed. These are them — 17 rungs,
3,655 cases, one BEAM and one warm serving.

**Re-running it at all needed a new handle, and finding that out is rule 82.** An arm is
named by a `translator_id`, and `model:mitra` covered **205 pilot chunks** when the ladder
was measured and **27,956** the next day, under the same id. Re-running by translator alone
would have compared a dense arm against sparse ones and attributed the difference to the
model — and it would have *confirmed* the conclusion, which is the version of this mistake
that never gets caught. `Pramana.Translations.chunks_covered/1` and
`--translation-chunks-of` pin a rung to a chunk set; the pilot rung is reconstructed from
rows nothing overwrote.

**The sample was recoverable, which nothing had recorded.** The original ladder's `--seed`
is in no commit, log or scratch file. `0.42` reproduces it: `patton` came back
173 · 84.4% · line 110 · 53.7% and the 27,956-chunk rung 194 · 94.6% · line 68 · 33.2%,
**both identical to the digit**, while the rungs the leak touched moved. So this is a
before/after on the same 205 queries, established rather than assumed.

**The conclusions survive.** The ladder's ordering is unchanged and MITRA still beats its
own untuned base by **15.1 points, the same margin to the decimal** — now with the English
layer held constant as well as architecture, size and prompt.

**The rung the leak was inflating was the floor, and only on the line.** `--translators
none` meant *no English vectors, then rerank against every rendering in the corpus*: the
control for "no English layer" was reordered by the English it was the control for.
Work-level is unmoved at 38.5%, because reranking a fixed candidate list cannot conjure the
right work into it. On the line it was 11.2% and is **7.8%**. So the lift every arm was
credited with had been measured against a floor that had been given a hand — and
**"generated English recovers 93% of the human layer's value" was understated: it is
97.8%.**

**The second stage is now separable, and the control it most needed came back exactly
right.** `--rerank false` on the no-English arm returns 38.5% · 7.8%, identical to the
reranked run — which is the reranker's own stated safety property, *a candidate with no
rendering scores 0 and keeps its fused position*, verified as a control for the first time
rather than asserted in a moduledoc. The stage is worth **+5.8 work-level points to the
generated arm and +1.0 to the human one**: the query *is* Patton's text, so his vectors
nearly saturate the first stage alone, while model English is a looser vector match that
string containment recovers.

**The Pāli coverage curve was re-run and cannot be deltaed against its predecessor**, which
is rule 80 arriving uninvited. Three things differ, not one: the isolation repair, a
different `bake_id` — the old curve ran at 17:16 UTC on 2026-09-02 and the current bake was
built at 18:50 that evening — and 27,751 Chinese English vectors that have since joined the
pool a Pāli query searches. Six of seven points moved down by 1–4.5 and the 50% point moved
*up* by 6. The new figures replace the old rather than measuring a change in it. What the
repair visibly fixed is the control: **0% coverage now scores 0.0% on the line** where it
read 1.5%, those three cases having been credited to a "no English" arm by a reranker
reading the English the ablation had hidden.

**And the run itself was 2.5x too slow, for a week, in the harness that produces every
published retrieval figure.** See the architecture review below, finding 4. The re-runs
were budgeted at 3¼ hours and took 1¾.

## The architecture review's remaining question, by a session that wrote none of it — 2026-09-03

`docs/CHECKS.md` §2 ends with the question the section exists for: **has this codebase
quietly stopped being the thing it was designed to be?** The 2026-09-02 review said in its
last line that it is "the one nobody can delegate, and it is not answered here." This
answers it, and the only reason it is worth anything is that the session writing it wrote
none of the code: the previous session produced roughly 35 of the last 65 commits,
including all three of the hand audits above it, so on that question it would have been
its own reviewer.

**The short answer is no, and the long answer is that a second corpus grew up beside the
first in two days and none of the machinery that governs the first has caught up with it.**

**The eight invariants hold, and they hold structurally rather than by good intentions.**
No unattributed text: `Translations.store/1` computes `text_sha256` itself, so no caller
can ship a hash that does not cover the text beside it, and `search_translations` returns
that hash against that text. No invented citation ids: a rendering is
`anchor_urn <> "#tr:" <> lang <> "/" <> translator_id`, a fragment that cannot be written
without naming the source anchor it renders. Provenance multi-axis: `Translations.provenance/1`
returns fourteen fields including `method`, `tier`, `model_id`, `review_state` and an
explicit `citable_as_source: false`. MCP read-only: **zero** `Repo.insert`, `Repo.update`
or `Repo.delete` anywhere in `apps/pramana_web`, and `Reply`'s moduledoc records that a
per-session trace was refused *because* it would be a write path from the model's side.
`raw/` untouched: every `File.rm` in `Pramana.Acquire.Archive` is on a temp download, and a
corrupt cached archive is refetched rather than trusted.

### 1. Invariant #6 is violated in the working tree right now

*"Every retrieval change runs against `evals/`. Recall@k and citation accuracy are
published numbers, not vibes."*

The full gate finished at **19:41**. `ed0c154` — the only change to retrieval behaviour
that day, and the one that made `Hybrid.maybe_rerank/3` pass `opts` so a scope can reach
the second stage — was committed at **19:54**. The commit immediately before it that
touches `rerank.ex`, `a0d6deb` at 19:21, is documentation only; its diff changes moduledoc
prose and nothing else. **So the day's retrieval change has never been scored against
`evals/`, and the gate that is being cited as covering the day's work predates it by
thirteen minutes.**

`docs/PLAN.md` lists "ONE full gate, when the machine is quiet" as the first thing owed and
frames it as scheduling — two sessions, one 16 GB machine, `mix pramana.gate` unable to get
a database connection while an import runs. All of that is true and none of it makes the
change evaluated. And the audit in the same file already found the compounding half: the
gate **passes without advancing the baseline**, so a green gate is compared against
`evals/baseline.json`'s 1,359 / 92.3% no matter what the run scored.

### 2. `bake_id` no longer identifies what answered, and every response says it does

`Pramana.Bake`'s moduledoc: *"Two people with the same `bake_id` hold byte-identical
corpora, which is what makes a citation reproducible years later and what 'decoupled from
the LLM' actually means in practice."* `bake_id` hashes `[lock_digest, pipeline_version,
config]` — acquired bytes, normalisation, bake settings.

The current bake was built **2026-09-02 18:50**. Since then, under an **unchanged** id:
**27,751** `model:mitra` renderings were imported and **27,751** translation vectors were
embedded. Two people with that `bake_id` can hold corpora that differ by 28,571 renderings
and answer the same query differently.

This is not a footnote in one tool. `PramanaWeb.MCP.Reply.json/3` stamps `bake_id` on
**every** response of all nineteen tools, and its moduledoc states the promise explicitly:
*"`{tool, arguments, bake_id}` is enough to run the query again and get the same answer."*
The MCP guide resource instructs a model: *"`bake_id` — which corpus snapshot produced
this. Cite it for reproducibility."* Two reader screens print it. `docs/PLAN.md` recorded
the consequence for `verify_report` replays; the surface is the whole API, and the promise
is made in the module whose reason to exist is making it.

**An answer that names an id which no longer identifies what produced it is worse than one
that names none**, because the id is what a reader would check. The split named in
`docs/PLAN.md` — `source_bake_id`, `translation_set_id`, `vector_set_id`, `release_id` — is
the fix, and until it lands the honest thing is that this claim is currently oversold in
prose that ships to models.

### 3. Production ordering is now a function of unreviewed machine translation, undisclosed

`Rerank.renderings_for/3` joins `translations` on `lang` and the arm's scope. Not on
`method`, not on `tier`. **27,751 CBETA chunks now have machine-generated English and no
human English** — every one of them `tier: t1`, `method: llm`, `review_state: raw` — and
each can move a candidate up the result list.

Invariant #8 is not breached: nothing generated is citable as source, and the audit above
re-confirms the structure. Invariant #1 is not breached: every returned span still carries
its URN, offsets, sha256 and provenance. **What has no provenance record is the
ordering.** `Hybrid` reports `retrievers: ["lexical", "semantic", ...]` — the arms that
generated candidates — and says nothing about whether the reranker ran or whether a raw
model rendering is why a result is at rank 1.

The reranker's own moduledoc is the best witness against it: it promised to *"not touch
Chinese: no English renderings exist over the Chinese canon, so every candidate scores 0
and the order is returned unchanged"*, and records that this **stopped being true in the
commit that produced the headline figures.** The previous session found that and wrote
"nothing here is wrong as *production* behaviour — a reranker reading every rendering it
has is what a reranker should do." That is right, and it is not the whole test. This
project's thesis is *warrant*: a claim arrives with the evidence for it. The span has its
warrant. The rank does not, and as of 2026-09-03 the rank is partly the output of a model
nobody reviewed.

### 4. Rule 41, inside the instrument that produces every published figure

`Pramana.Evals` passes `coverage: false` on every search, with the saving measured in a
comment beside it: *"6m43s -> 5m22s, ~1.65 s saved per case … It is database time, so it
appears in no CPU profile and in nobody's intuition about why a run is slow."*

**`Pramana.Recall` did not** — and `Recall` is the harness behind the 46.8% -> 76.0%
production baseline, the four-arm model ladder, the Pāli coverage curve and the
cross-lingual parallels axis. Every case of every one of those runs counted 560,238 chunks,
probed each for a vector, and threw the answer away: `probe_rendering/4` and
`probe_parallel/4` read `%{results: results}` and nothing else.

Measured here rather than assumed, 25 cases, `--to cbeta.T`: **3.3 s/case -> 1.3 s/case**,
a 2.5x speedup, which matches the 3.3 s/case in the 2026-09-02 ladder logs almost exactly.
On the 1,670-case production run it is roughly **46 minutes of wall time spent on a field
nobody read.** Fixed in this commit. The fix was found, measured and written down a week
ago in one of the two harnesses and never swept to the other, which is rule 41 — the
most-tripped rule in this project — arriving in the measuring apparatus.

### 5. A shared definition that one of its two callers did not call

`Pramana.Retrieval.RenderingScope`, added the previous evening, says: *"A scope that only
one stage obeys is not a scope. This module is the one definition, and both stages read
it."* `Rerank` read it. **`Semantic` did not reference the module at all** — it went on
deriving `round(coverage * 100)` and its own translator predicate straight from `opts`.

Both implementations agreed on every input, checked clause by clause, so nothing was wrong
and nothing was measured wrongly. It is rule 41 one level up: a rule extracted into a
shared place while one of its callers keeps its own copy is a rule with two definitions
and a moduledoc claiming one. Fixed in this commit, and the new third rule was added in the
shared place only — which is the test of whether the repair took.

### The verdict

**It has not stopped being what it was designed to be.** The guarantees it advertises are
real, and they are enforced by structure — hash computed at the store, rendering addressed
as a fragment, provenance as a record rather than a string, no write path on the model's
side — rather than by prompting or by remembering.

**What has happened is that a second axis of state grew up beside the baked corpus in two
days, and nothing that governs the first governs the second.** The translation-and-vector
layer has no identity (finding 2), no disclosure in the response shape (finding 3), and no
eval run behind its retrieval change (finding 1). Three of the five findings are that one
fact wearing different clothes, and it is worth saying plainly because each was visible
only as a small local oddity: an id that did not move, a field that was not reported, a
gate thirteen minutes early.

The one idea is *"the corpus is baked into an immutable, content-addressed artifact; the
LLM is a swappable reader."* Half of that is still exactly true and is the half doing the
work. The other half — content-addressed — is now true of the source text and false of what
retrieval actually reads, while the API asserts it uniformly, nineteen tools at a time.
