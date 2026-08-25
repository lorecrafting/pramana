# Plan

**The living task list.** `STATUS.md` records what happened and what was learned; this
records what is *next* and why. Where they disagree, STATUS is the evidence and this is
the intent.

> **KEEP THIS UPDATED.** Every session that finishes an item, learns something that
> changes an estimate, or discovers new work must edit this file in the same commit as the
> change. An item whose evidence has gone stale is worse than no item, because it will be
> picked up and worked on against a number that is no longer true. If a measurement
> contradicts an item here, correct the item rather than quietly working around it.
>
> Three things trigger an edit: **finishing** an item, **discovering** work (add it to the
> backlog with its evidence), and **invalidating** an assumption (strike it and say why).

Last reviewed: **2026-08-24** — A shipped end to end. **B (CBETA X) is next.**

---

## Where the product stands

| | |
|---|---|
| corpus | 15,489 texts · 6,538,238 segments · 3 traditions · 617,038 vectors |
| work relations | 90 `comments_on` · **82 `parallel_of`** (41 pairs) |
| eval | **93.6%** over 1,400 cases (`evals/baseline.json`), 0 stale, 0 errored |
| retrieval@10 | 380/446 — zh 97.8% · pa 81.3% · bo 48.4% |
| answered from any tradition | 81.8% |
| one search | 2.2 s · full gate 20m52s |
| redistributable subset | 13,017 texts · 1.8M segments · 315k vectors |

**What "finished" means for v1**, restated so items can be judged against it: a scholar or
an LLM can ask a question of three canons, receive passages that are byte-verifiable
against a print edition, see the provenance of each, and follow parallels and variants
between them — with published numbers saying how often that works.

By that definition the *retrieval substrate* is close. What is thin is **coverage**
(one CBETA collection of ~20), **the deterministic enrichment that differentiates this
project** (#22 done, #23 blocked, commentary alignment untouched), and **any surface a
human can use** (no reader).

---

## Now

### A. Work-level `parallel_of` — ▸ DONE 2026-08-24

**Shipped.** `mix pramana.relations.parallels` aggregates SuttaCentral's curated
passage parallels to the work, and `Relations.parallels_of/1` reads them.

    41 work pairs at >= 3 full parallels -> 82 rows (both directions)
    T0099 <-> T0100   706 full   雜阿含經 / 別譯雜阿含經
    T0210 <-> T0212   284 full   法句經 / 出曜經
    T0210 <-> T0213   278 full   法句經 / 法集要頌經

`work_relations` went from **90 rows, zero `parallel_of`** to 82 `parallel_of` rows
(32 `probable`, 50 `uncertain`).

**The claim was deliberately narrowed, and this matters for #23.** The item was written as
"assert 異譯本". The data does not support that word. 異譯本 means *an alternate translation
of the same Indic original*, and curated parallels cannot distinguish it from other
parallelism: T0099/T0100 are a real 異譯本 (the second's name says "separately
translated"), while T0099/T0125 are Saṃyukta and Ekottarika Āgama — **different
collections**, neither translating the other. Both share hundreds of passages. So the
relation asserted is `parallel_of`, never `translates`, and **#23 must treat these as
candidates rather than settled versions.**

**Threshold is a judgement, made visible.** Median pair shares **2** passages, p90 **4**,
max **736**. Two shared discourses is evidence about passages, not works, so `--min-full`
defaults to 3 and the count rides in `evidence` where it can be argued with.

**Reachable, not just stored.** `Compare.versions/2` now returns an `alternates` key —
absent until now because it would always have been empty — carrying `confidence`,
`evidence` and `attributed_author` per entry, and a `note` that refuses to call them
alternate translations. A T0099 passage returns 12, led by T0100 at 706 shared passages.

**Unblocks #23** (translator fingerprinting): `parallels_of/1` returns
`attributed_author` beside each pair, which is the join the feature needs — 求那跋陀羅
against 竺佛念 against 玄奘 on the same material.

---

## Next

### B. CBETA's other collections — the largest coverage gap

**Goal.** Ingest `X` (卍續藏), and then `J`, `B`, `K`, `L`, `N` as they prove out.

**Why.** This is meant to be a substrate for the Buddhist canons and it holds **one CBETA
collection out of ~20** — witness `T`, 2,471 texts. No permission is needed and the
pipeline is proven on 2,471 works.

**▸ SPIKE DONE 2026-08-24. The pipeline is ready; the decision is cost.**

Measured from the pinned catalogue (5,005 works across 26 collections):

| canon | works | MB | |
|---|---|---|---|
| T | 2,471 | 855 | held |
| **X** 卍續藏 | **1,236** | **676** | the prize — +50% on work count |
| J 嘉興藏 | 287 | 105 | |
| B | 204 | 125 | |
| N 南傳大藏經 | 83 | 56 | a Japanese rendering of the Pāli canon |
| 21 others | 259 | 137 | mostly tiny |

**The normalizer handles X unchanged** — verified by acquiring one real X work and running
it. The citation grammar is *identical* (`<lb n="0001a01"/>`, page/register/line, same juan
milestones), and title, author and licence notice all extract correctly. No new normalizer,
no new citation grammar. That was the main risk and it is gone.

**Provenance has an answer, and it is better than a volume table.** `Taisho.Divisions` is
the 部 table for the *Taishō* and cannot serve X — but X's own bylines carry the claim:

    唐 王勃撰      Tang dynasty, Wang Bo, COMPOSED   -> chinese
    後秦 佛陀耶舍…譯  Later Qin, Buddhayaśas, TRANSLATED -> indic

The verb is the discriminator: 譯 (translated) against 撰/述/著/集/錄/記 (composed).
**Validated against ground truth** on the Taishō, where division-derived provenance already
exists — 2,020 of 2,077 works agree, **97.3%**. This is the same principle that let the
Tengyur name itself from its own incipit rather than an acquired catalogue: the edition's
own statement beats an external table, and here it is checkable against one.

The 57 disagreements are not all the byline being wrong — the 部 table assigns by volume
*range*, so a Chinese-composed work inside an Indic division is mislabelled by the table
and correctly labelled by its byline. Worth inspecting before trusting either blindly.

**Still true, and unchanged:** `Coverage.taisho/0` reasons about Taishō volume numbers and
will not see X; corpus growth invalidates `evals/baseline.json` and triggers rule 7.

**Sequence.** acquire X (676 MB) → bake with byline provenance → chunk → **embed (GPU,
costs money)** → import + HNSW rebuild → verify + integrity → re-baseline.

**▸ IN PROGRESS 2026-08-24.** X acquired (1,236 files, 647 MB) and baking, without
embedding — the GPU spend stays a separate decision.

**Two bugs found, both invisible while the Taishō was the only collection held:**

1. **`pramana:cbeta.T:X1508`** — the single-work bake path used `pipeline.witness`, a
   static `"T"` in the registry, while the bulk path used the actual canon. The paths had
   always disagreed; with one collection, `"T"` was indistinguishable from correct. Fixed.
2. **284 of 1,236 works died on `segments_urn_index`.** CBETA re-emits `<lb>` when an
   element spans the line it opened on, so one printed line arrives as two fragments with
   the same number *and* edition. The Taishō survived only because its repeats carry
   nothing on the second occurrence, so the blank-line rule already dropped them; X's
   carry an inline note, which rule 3 says must stay addressable.

   **The first fix for this was wrong and was reverted.** Diagnosed from one file as
   "markup re-announces the line", it merged *adjacent* same-anchor fragments and cleared
   26 of 40 sampled failures — which looked like progress and was papering over the real
   cause. The truth, found by reading the raw XML instead of the parsed output:

       <lb ed="X" n="0019a11"/><lb ed="R055" n="0019a01"/>
       <lb ed="X" n="0019a12"/><lb ed="R055" n="0019a01"/>

   **X files carry TWO lineations.** `ed="X"` is the 卍新纂 numbering the collection is
   cited by; `ed="R055"` is the earlier 卍續藏經 reprint's, and one R line spans many X
   lines. The normalizer ignored `ed` and treated every `<lb>` as a line, conflating them —
   so the merge was joining an X line to an R line, which is nonsense.

   **The real fix is to keep only the collection's own lineation.** Measured across 60 X
   files: all 60 carry `ed="X"`, all 60 also carry `ed="R<num>"`, and **no `<lb>` lacks an
   `ed`**. Within `ed="X"` alone, **0 of 25 files have a repeated anchor** — filtering by
   edition removes every duplicate, and the merge was never needed.

   T is untouched: T09n0262 has 5,409 `<lb>`, every one `ed="T"`. `mix pramana.verify
   --source cbeta` reports **978 mismatches, all X, zero T** — exactly the works baked with
   the old normalizer, which the re-bake resolves.

**Landed: 1,230 X texts, `verify OK` over 3,701 CBETA texts / 2,089,631 segments,
byte-identical.** The corpus is now **16,719 texts**.

**KNOWN DEFECT, 6 works: volume-spanning texts keep only one volume.** Six X work numbers
appear in two volume files each — X0240 (X08+X09), X0367 (X20+X21), X0714 (X39+X40),
X0822 (X50+X51), X1568 (X80+X81), X1571 (X81+X82). `bake_all` runs one job per FILE and
`Loader.load/2` replaces a work's segments, so the second volume overwrites the first and
**one volume's text is silently lost**.

This is the Derge bug exactly, recorded there as "a volume is not the unit of loading, and
the loader will not tell you" — where 75 of 1,195 works spanned volumes and had to be
assembled in `Derge.Edition` before loading. The Taishō never showed it because CBETA gives
Taishō works split across volumes DISTINCT ids (`T0220a`, `T0220b`): 2,471 distinct numbers
across 2,471 files. X reuses the number.

**`verify` cannot catch it** — it re-normalizes the file the text records and compares, so
a text holding one volume re-derives from that volume and passes. Rule 2 again:
reproducibility is not fidelity. The check that would catch it is a count taken from the
SOURCE before parsing: files on disk (1,236) against works loaded (1,230).

**Fix:** assemble the two volumes before loading, as `Derge.Edition` does. That is a change
to the bake flow — currently one Oban job per file — so it is its own task, not a patch.

**Still open:** the GPU spend for embedding X, unchanged and still needing a human. And
whether X's second lineation (`ed="R*"`) should be preserved as alternative citation
metadata: scholars cite 卍續藏 by its original R page/line, and it is currently discarded.

**Exit.** X baked, byte-verifiable from `raw/`, provenance assigned by a stated rule,
integrity green, baseline regenerated.

### C. Public demo — newly unblocked

**Why it moved.** The Phase 2 gate recorded "the public corpus is currently EMPTY". That
stopped being true two phases ago and nobody noticed until 2026-08-24: **13,017
redistributable texts, 1.8M segments, 315k vectors**, and `redistributable_only: true`
returns real results end to end. The blocker was never the reader; it was having nothing
lawful to serve.

**Scope guard.** Phase 8 is a *renderer* over an API that already returns spans, URNs and
offsets. If it starts needing new domain logic, that is a signal the API is missing
something — fix the API, not the view.

### D. `topical/chinese` is still 0%

The last zero on the scorecard. Measured options, in order of evidence:

- **Query translation works**: 0% → **91.7%** on the 12 cases when the query is rendered
  into Chinese with the right term.
- **Term choice is worth ~50 points**: a defensible synonym drops it to 41.7%.
- **The glossary alone does not carry it**: 84000's glossary recovers 2 of 12 gold terms —
  shipped as `expand_terms:` and **off by default**, because +2 of 12 did not justify a
  third arm diluting RRF.
- **A glossary cannot handle a paraphrase at all**: "what did the buddha realise under the
  bodhi tree" expands to `[]`. The semantic arm answers it correctly *from the Pāli*.

**So the answer is both halves** — a model for paraphrase understanding, a **corpus-derived
term table** for register fidelity — which is what `docs/TRANSLATION.md` already specifies
as glossary-pinned translation. The missing piece is a term table built from CBETA itself
(every attested rendering, with occurrence counts, adjudicated as the topical gold terms
already are), not from 84000's Tibetan-oriented glossary.

**Caveat that should stop anyone over-investing:** `topical/*` is 12 cases and **cannot
grow** — its curated term list rejects terms too common to measure. One case is 8.3 points.
Judge this axis by `answered from any tradition`, not by the row.

### E. Tibetan recall — 24 cases unreachable

`retrieval/tibetan` is 48.4%, close to the ~51.6% ceiling reranking can reach. The
remaining misses are **absent from 200 candidates**: a recall failure no reordering fixes.
BGE-M3 packs Tibetan at 0.9727 mean pairwise cosine, so its candidates are near-ties by
construction.

The lever is a better embedder. **A LoRA was already tried and failed completely** — every
proxy said it worked and the gold set said `retrieval/tibetan` 0%. Do not retry without a
hypothesis for *why* it failed that the proxies could not see. Training data exists (30,653
aligned bo↔en folio pairs).

---

## Blocked

| item | blocked on |
|---|---|
| **#14 SAT / Taishō 56–84** | An email to `sat at l.u-tokyo.ac.jp`. Draft sits unsent in `docs/sat-request-email.md`. **Needs a human.** |
| **#41 T56–84 catalogue** | No source exists; arrives with #14 if access is granted. |
| **`phase-2` tag** | Withheld until #14 resolves or is formally moved. Stamping a gate green over a known gap is how gates stop meaning anything. |

---

## Can these run at the same time?

**Partly, and the split is not where you would guess.** From the Tengyur session: *"Run
these with the machine to themselves. Four concurrent jobs exhausted the Postgres
connection limit and the Tengyur pair took over two hours each under contention, against
~90 minutes alone."*

| stage | safe to overlap? |
|---|---|
| **Acquisition** (download from CBETA) | **Yes** — network and disk only, never touches Postgres |
| **GPU embedding** | **Yes** — runs on a *rented remote* GPU; local machine is idle waiting |
| Normalize / segment / load | **No** — saturates local Postgres |
| Vector import + HNSW rebuild | **No** — and rule: *drop the HNSW index before any bulk import* (69 s vs 40 min) |
| Eval runs | **No** — they are the measurement; contention invalidates every timing |

So the workable pattern is: **kick off acquisition and the remote GPU embedding, and do
code-only work while they run** — but stop code work that touches the database before the
local bake, import, and index rebuild, and never run an eval concurrently with any of it.

---

## Backlog

- **The gate cost/coverage question is settled for now** (20m52s), but if it creeps back
  above ~1h, revisit — and do **not** resolve it by lowering the gate's depth, which makes
  the number meaningless.
- **Commentary lemma-and-gloss (科文) parsing** → root↔commentary alignment. Phase 6,
  untouched, deterministic, a real differentiator.
- **`retrieval/chinese` has 5 stubborn misses** out of 232 and has not moved all year.
  Cheap to diagnose now that a search is 2.2 s; nobody has looked.
- **`priv/embed` sidecar** still owns Tibetan `botok`, which nothing uses — the lexical
  layer windows syllables directly and supersedes it. Consider deleting the dependency.

## Rejected, with evidence — do not redo

| tried | verdict |
|---|---|
| `hnsw.ef_search` tracking the row limit | **Zero change**, +5% cost. Subsumed by the iterative scan. Live again only if `iterative_scan` is disabled. |
| Global fusion depth 120 | ~4x cost for +7 cases. Superseded by **per-arm depth** — the gain was entirely semantic, the cost almost entirely lexical. |
| `balance: :tradition` round-robin | Moved neither tradition's rate and made answered-from-any-canon *worse*. Survives opt-in. |
| Tibetan LoRA | Every proxy said it worked; the gold set said 0%. See *Why every proxy lied*. |
| Doc-translation stage B (~$260–770) | Superseded by query translation, which is free and scored higher. |
