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

Last reviewed: **2026-08-26** — A shipped. **B (CBETA X) is baked and correct; what is
left of it is the GPU spend and a re-baseline.**

---

## Where the product stands

| | |
|---|---|
| corpus | 16,719 texts · 10,702,843 segments · 3 traditions · 617,038 vectors |
| chunks | 850,630 — **every text chunked**; X's 290,392 are **not embedded yet** (65.9%) |
| reader | LiveView search + passage at `/` and `/passage` |
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
(two CBETA collections of ~20), **the deterministic enrichment that differentiates this
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

**▸ THE SIX DEFECTS THAT INGEST LEFT BEHIND ARE FIXED — 2026-08-26.** Four were
invisible while the Taishō was the only collection held. The other two were what
`mix pramana.integrity` had to say, and nobody had run it since X landed: it was crying
wolf over 1,228 texts, and underneath that noise it was right about one.

1. **`embedding_coverage` reported `100.0%` while 38% of the corpus was unreachable.**
   The denominator was chunks, and X had never been chunked — so its 1,230 texts and
   4,068,303 segments were absent from the numerator *and* the denominator and cancelled
   out exactly. The field that exists to stop partial data being mistaken for a small
   canon was hiding a third of the canon. `coverage/1` now also reports
   `reachable_percent`, `unchunked_texts` and a `note`, and `docs/MCP.md`'s guide
   resource tells a caller to read both numbers. **This is still true and still
   unembedded** — it is now *stated* rather than hidden.
2. **Six works kept one of their two volumes.** X0240, X0367, X0714, X0822, X1568 and
   X1571 each reuse one work number across two volume files, and `bake_all` ran one job
   per FILE while `Loader.load/2` REPLACES a work's segments. Fixed by making the work,
   not the file, the unit of a job (`Pramana.Bake.WorkList`) and assembling the parts
   before loading (`IR.concat/1`) — the same shape as `Derge.Edition`.

   **The design question the last session left open is answered: no anchor rewriting is
   needed.** Juan numbering runs continuously across the volume break (X08n0240 ends at
   juan 44, X09n0240 opens at juan 45) and the URN already carries the juan, so the
   assembled works have **zero duplicate URNs** — 216,041 segments, 216,041 distinct.
   Only X1571 repeats page anchors between its volumes, and it repeats **22,616** of
   them, so each line now carries `meta["volume"]`: the URN was always unique, the
   *printed* locator was not.

       X0240    628,757 -> 1,111,576 chars       X0822   105,260 ->   340,494
       X0367    193,061 ->   349,657             X1568   285,419 ->   824,278
       X0714    312,279 ->   590,859             X1571 1,222,180 -> 1,763,147

   **2,233,055 characters recovered**, `verify OK` over all 3,701 CBETA texts afterwards.
3. **Acquiring X deleted the Taishō from `sources.lock.json`.** `put_source/1` writes a
   source entry whole, and CBETA is acquired one collection at a time, so the X run
   replaced 2,471 T file records with 1,236 X ones. **A corpus of 3,701 baked CBETA texts
   had a lockfile that could reproduce 1,230 of them** — invariant 3, broken in silence:
   `raw/` still held every byte, `verify` re-derives from the file a text names on disk,
   and acquisition reported success. `Lockfile.merge_source/1` now merges by path; when the pin has
   moved it replaces the entry only if the new fetch covers every path already locked,
   and otherwise refuses, because the untouched paths would keep a commit label they
   never came from. The entry is repaired to **3,707 files, every one re-hashed against
   `raw/`** (`Lockfile.verify` → `{:ok, 3707}`). **`bake_id` changed, and correctly** —
   the old one was computed over a lockfile that did not describe the corpus.
4. **A killed bake left its queue behind.** `bake_all` purged only `completed` and
   `discarded` jobs, so the next run enqueued a second copy of everything still
   `available` — 1,468 jobs for 1,230 works, and the connection contention that produced
   the nine statement timeouts blamed on a slow machine. It now purges the whole queue
   unless `--resume`.
5. **`mix pramana.integrity` had been failing on 1,228 X texts, and nobody had run it.**
   The X ingest ran `verify` only. Integrity counts `<lb ` in the raw body and compares
   against IR lines — and after the two-lineation fix, half of every X file's `<lb/>`
   belong to the 卍續藏經 reprint and are correctly skipped, so the check read `raw 46,
   bake 25` and called it `lb_lost`. **The bake was right and the check was wrong**, which
   is the more dangerous way round: a fidelity check that cries wolf gets ignored.

   The normalizer had counted the skips all along — `skipped_lb`, with a comment saying
   it existed "so that filtering everything away is a loud failure rather than an empty
   text" — and then dropped the number on the floor when it built the IR. It is now
   `IR.foreign_lb`, and the check reconciles: **every `<lb/>` in a CBETA body is either a
   line or a skip.** Measured over all 3,701 CBETA texts:

       raw <lb>     13,156,723
       IR lines      8,989,044
       foreign lb    4,167,679
       unaccounted           0    (0 texts mismatched)
6. **One printed line in the corpus was a rare character and had no URN.** With the noise
   gone, integrity had exactly one thing left to say: `X0575: line_unaddressable — raw
   1756, bake 1755`. The segmenter's blank test was `text: "", notes: [], apparatus: []`
   and **omitted gaiji** — and a line whose entire content is one rare glyph has empty
   `text`, because gaiji are recorded as a mapping rather than substituted into the body.
   So it matched "nothing was printed here" exactly. It is the third time this project
   has dropped a line that was not blank, after note-only lines (v2) and `<note>` spanning
   `<lb/>` (v3), and gaiji are the one kind of content a reader cannot reconstruct from
   anything else.

   Counted across all 3,701 CBETA texts: **one line, X0575 0966b12, the character 䦚
   (CB12059)** — T has none, which is why the Taishō gate never saw it. It now resolves at
   `pramana:cbeta.X:X0575_001@p0966b12` with the mapping in `meta`.

**The check that would have caught #2 and #3 now exists.** `mix pramana.integrity` gained
a fourth check: a census taken from the lockfile **before any parsing** — files → works →
texts loaded. The first three checks all start from a text row, and from inside a row a
work that lost half of itself looks perfect. cbeta now reads `3,707 file(s) -> 3,701
work(s) -> 3,701 loaded`.

`pipeline_version` is **4**. `config/dev.exs`'s pool timeout went 120s → 300s: assembling
X1571 makes one transaction of 74,570 lines against T1912's 26,000, which is the capacity
answer that file's own comment prescribes.

**What is LEFT of B, and it needs a human for one line of it:**

- **▸ CHUNKED 2026-08-26.** `mix pramana.chunk --source cbeta` built **290,392 chunks in
  98 s**, leaving the Taishō's 2,471 embedded texts alone (the builder refuses to discard
  vectors without `--force`). The corpus now holds 850,630 chunks, and coverage reports
  **65.9%** — a number that would have read 100.0% both before and after this ran, under
  the old denominator.
- **Embed X — the one step that needs a human.** ~290k chunks; by the measured precedent
  (T: 299,317 chunks, 34 min, ~$0.45 on a rented L4) that is **~35 minutes and ~$0.45**.
  Then import + HNSW rebuild, dropping the index first (69 s against 40 min).
- **Re-baseline.** `evals/baseline.json` is dated 2026-08-23 and predates X, so rule 6
  says it is invalid. Run the gate ONCE, after embedding — running it now would measure a
  half-indexed corpus and cost a second 20m52s.
- **`Coverage` still knows only the Taishō.** `Coverage.taisho/0` reasons about Taishō
  volume numbers and cannot see X, so with X in, the absence of J/B/K/L/N is unstated —
  the same "absence reads as silence" failure the module exists to prevent, one level up.
  Small, and it should land before J.
- **X's second lineation (`ed="R*"`) is still discarded.** Scholars cite 卍續藏 by its
  original 卍續藏經 page/line, and we keep only `ed="X"`. Worth preserving as alternative
  citation metadata; not a defect, a missing affordance.

**Exit.** X baked, byte-verifiable from `raw/`, provenance assigned by a stated rule,
integrity green, baseline regenerated. **Everything but the embedding and the baseline is
done, and those are one sequence: chunk → embed → import → gate.**

### C. The reader — ▸ FIRST TWO SCREENS SHIPPED 2026-08-26

`mix phx.server` now serves a search page at `/` and a passage page at `/passage?urn=…`,
both LiveView, both renderers over the same domain the MCP surface reads.

**What it renders, and why each part is not decoration:**

- **Results are bucketed by composition origin and role**, each bucket named in plain
  language. Invariant #4 enforced by the shape of the page: mis-attributing a Japanese
  commentary now requires ignoring a heading rather than merely missing a field.
- **Every hit carries its URN and sha256 on screen.** The URN is the edition's own
  grammar, so `T0262_001@p0001c19` reads as Taishō page/register/line to anyone checking
  against print.
- **Both silences are stated above the results** — what is not ingested
  (`Coverage.caveat/0`) and what is ingested but not vector-indexed (`coverage.note`),
  plus which retrievers actually ran. A phrase search says it never consulted meaning.
- **The passage page shows the printed context** (Taishō lines break mid-sentence), the
  variant apparatus, rare characters with their mappings, and the work's outline. The
  line whose only content is 䦚 renders as *"a rare character, below"* rather than as an
  empty row.

**Three things moved into the domain rather than being written in the view**, which is
the scope guard working as intended — if the reader needs corpus logic, the API was
missing it:

| moved | from | why |
|---|---|---|
| `Provenance.group/1` | the MCP search tool | two surfaces describing one bucket differently |
| `Retrieval.search/2` + `mode/1` | the MCP search tool | two surfaces routing `"semantic"` differently |
| `Lexical.known_opts/0` | private | so a dispatcher can drop `:coverage` before a phrase search, which RAISES on unknown options by design |

**And the atom-table bug was walked into a second time.** `String.to_existing_atom("phrase")`
in the LiveView raised on the first phrase search in a fresh VM and worked on every one
after — the exact failure `docs/STATUS.md` records for the MCP tool. That is why the
mapping is now a literal map in the domain, with a regression test.

**▸ 2026-08-27 — the passage page now carries versions, and Coverage knows the
collections.**

`Compare.versions/2` is rendered on the passage page: the whole translation pool (never a
winner, and a non-human rendering wears a badge saying it is not citable as source),
parallels with their strength, and work-level alternates labelled as *candidates for
異譯本, not established alternate translations*. Verified on SN 6.4, which shows Sujato's
English beside three parallels reaching into the Chinese canon — `T0100_006@p0412b07`,
`T0099_044@p0324b03` — from one Pāli line.

Two things the page had to be taught not to claim:

- **A section with nothing in it is not rendered.** `Compare.versions/2` returns `nil`
  rather than an empty structure precisely so this is possible; a "Parallels" heading over
  an empty list is the assertion *we looked and there are none*.
- **Parallels pointing at texts we do not hold are counted, not dropped.** T0099 has 1,958
  recorded and 1,661 resolvable — the other 297 are stated as unopenable, because a
  parallel we cannot show still tells a reader it exists.

**`Coverage.cbeta/0` closes the collections gap.** CBETA publishes **26 collections** and
this holds two; 24 collections and 1,298 works were absent with nothing saying so, which is
the Taishō 56–84 failure one level up. The counts are measured from the pinned catalogue
(`Pramana.Cbeta.Collections`, one git-tree call at `2b8ab8d5`), and **most entries have no
name on purpose**: each CBETA file states its own collection in `<sourceDesc>` — T's say
大正新脩大藏經, X's say 卍新纂大日本續藏經 — and for a collection we have not acquired there
is no such statement, so expanding `YP` into some canon would be a guess a reader could not
tell from a fact.

**Still to build:** a work browser (the outline as a first-class page), and the apparatus
as its own view. Neither needs new domain logic.

### D. Public demo — newly unblocked

**Why it moved.** The Phase 2 gate recorded "the public corpus is currently EMPTY". That
stopped being true two phases ago and nobody noticed until 2026-08-24: **13,017
redistributable texts, 1.8M segments, 315k vectors**, and `redistributable_only: true`
returns real results end to end. The blocker was never the reader; it was having nothing
lawful to serve.

**Scope guard.** Phase 8 is a *renderer* over an API that already returns spans, URNs and
offsets. If it starts needing new domain logic, that is a signal the API is missing
something — fix the API, not the view.

### E. `topical/chinese` is still 0%

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

### F. Tibetan recall — 24 cases unreachable

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
