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

Last reviewed: **2026-08-24**.

---

## Where the product stands

| | |
|---|---|
| corpus | 15,489 texts · 6,538,238 segments · 3 traditions · 617,038 vectors |
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

### A. Assert 異譯本 relations — unblocks #23  ▸ IN PROGRESS

**Goal.** Populate `work_relations` with `parallel_of` for alternate Chinese translations
of the same Indic original, from catalogue metadata already held.

**Why now.** It is the only item that is pure code over data already in the database — no
acquisition, no GPU, no money — and it unblocks a differentiator `docs/COMPETITIVE.md`
already claims. Measured 2026-08-24: `work_relations` holds **90 `comments_on` and zero
`parallel_of`**. `Pramana.Compare` documents the gap; the relation vocabulary has the slot;
nothing fills it.

**Exit.** `parallel_of` populated with a stated derivation and a count; `Pramana.Compare`
returns alternate translations for a work that has them; a test proving the relation
changes what the API returns.

**Then #23 becomes possible:** translator fingerprinting and divergence scoring — "how
Kumārajīva and Xuanzang rendered this term" — which is a named differentiator and currently
cannot run at all.

---

## Next

### B. CBETA's other collections — the largest coverage gap

**Goal.** Ingest `X` (卍續藏), and then `J`, `B`, `K`, `L`, `N` as they prove out.

**Why.** This is meant to be a substrate for the Buddhist canons and it holds **one CBETA
collection out of ~20** — witness `T`, 2,471 texts. No permission is needed and the
pipeline is proven on 2,471 works.

**Not as cheap as it looks — spike first.** `mix pramana.acquire --canon X` already exists,
so acquisition is likely config. But:

- **Provenance has no answer for X.** `Pramana.Taisho.Divisions` is the 部 table for the
  *Taishō*; X has its own arrangement. A collection ingested without it arrives with no
  composition-origin or text-role axis, which violates the spirit of invariant #4.
- **`Pramana.Coverage.taisho/0` reasons about Taishō volume numbers** and will not see
  works under other numbering (ROADMAP says this explicitly).
- Corpus growth invalidates `evals/baseline.json` and triggers rule 7 (re-run integrity and
  filter checks after growth, not just after code changes).

**Sequence.** spike acquisition on a handful of X works → decide the provenance story →
normalize/segment/load → chunk → embed (GPU) → import + HNSW rebuild → verify + integrity →
re-baseline.

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
