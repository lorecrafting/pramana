# Plan

**The living task list.** `HISTORY.md` records what happened, `RULES.md` what was learned; this
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

Last reviewed: **2026-08-27** — A shipped. **B is done through the seventh CBETA
collection: 10 of 26 held, every text chunked and embedded, the reader at five screens.**

---

## Where the product stands

| | |
|---|---|
| corpus | **17,281 texts · 12,586,964 segments** · 3 traditions · **1,037,264 vectors** |
| CBETA | **16 collections of 26** — T 2,471 · X 1,230 · J 285 · **I 101** · N 38 · **GA 51** · **F 27** · L 21 · P 13 · K 9 · A 9 · U 2 · S 2 · **GB 2** · M 1 · **ZS 1** — 4,340 files locked |
| vector coverage | **100% of texts chunked, 100% of chunks embedded** — the 38% unreachable that `reachable_percent` exposed on 2026-08-26 is closed |
| MCP surface | **17 read-only tools** — `search_translations`, `get_glosses`, `get_works_by_person` and `get_person` all added 2026-08-28 |
| reader | five LiveView screens — search `/`, **inventory `/inventory`**, survey `/survey`, passage `/passage`, work `/works/:id` |
| work relations | 90 `comments_on` · 82 `parallel_of` (41 pairs) |
| passage parallels | 407,176 recorded · **24,717 openable (6.1%)** — the rest name witnesses this bake does not hold |
| commentary alignment | **27,254 lemmas over 43 pairs**, attaching commentary to **20,954 root lines** — deterministic, no model |
| public exposure | **213,932 rows servable** · 34,697 forbidden by licence · 9,841 withheld pending a publication record (`mix pramana.public.check`) |
| eval | **92.3% over 1,472 cases** (`evals/baseline.json`) — 0 stale, 0 errored. Not comparable with 93.1%/1,400: the denominator grew by two case types, one scoring 70%. Compare per row |
| new gold sets | **rendering 70.0%** (40 cases, mean rank 1.68) · **gloss 100%** (32 cases, a regression detector — see below) |
| retrieval@10 | 374/446 — zh 96.1% · pa 80.0% · bo 48.4%\* |
| absence | **75%** — and the failing case is real and stays red; see item D |
| answered from any tradition | 81.8% |
| noise floor | 1 case same-index · **6 cases across an index rebuild, 4 of them Tibetan** |
| full gate | 26m53s at 0.9 cases/s |
| redistributable subset | 13,017 texts · 1.8M segments · 315k vectors |
| CI | GitHub Actions on every push — compile `--warnings-as-errors`, format, credo, 1,198 tests |

**Every retrieval row went DOWN when X landed, and that is not a regression in the
retrieval system.** 1,230 mostly-commentarial works joined the corpus, and a commentary
that quotes a definitional formula is a legitimate match for it — 云何為二法 now ranks
X0771 釋摩訶衍論疏 above the Āgama passage the gold set wants. The system is answering a
harder question over a larger corpus. Published numbers, not vibes, means publishing this
one too.

**What "finished" means for v1**, restated so items can be judged against it: a scholar or
an LLM can ask a question of three canons, receive passages that are byte-verifiable
against a print edition, see the provenance of each, and follow parallels and variants
between them — with published numbers saying how often that works.

**▸ BY THAT DEFINITION v1 IS MET — 2026-08-28.** Each clause, and what answers it:

| the sentence says | what does it |
|---|---|
| ask a question of three canons | 17 read-only MCP tools · five reader screens · 17,281 texts across Chinese, Pāli and Tibetan |
| passages byte-verifiable against a print edition | `Pramana.Guard` byte-compares every quote; `verify --all` re-normalizes from `raw/`; the CBETA linehead is checkable against the printed page |
| see the provenance of each | four axes, plus `witness_name` and `authority_id` — the edition by name and the person the byline denotes |
| follow parallels and variants between them | curated parallels, the apparatus, 141,073 quotations, and **27,254 commentary lemmas** attaching commentary to the line it explains |
| published numbers saying how often | 1,472 cases in `evals/baseline.json`, and the gaps published beside them |

**This paragraph said the opposite three days ago** — *"#23 unblocked but unstarted,
commentary alignment untouched… the one item that no general-purpose search tool will ever
produce for you"*. Both shipped. It is left visible rather than deleted, because the plan's
value is that it records what was believed as well as what is true.

**Then the line moved, deliberately.** v1 as *written* is met; v1 as *scoped* now includes
four things added by decision after the definition was, and the honest reading is that **v1
is no longer met** — two of the four are designed and unbuilt:

| added to v1 | state |
|---|---|
| lineage chains | ✅ `Authority.lineage/1`, `teacher_chain/2`, exposed on `get_person` |
| Wikidata q-ids | ✅ `external_ids` on `get_person`; 1,446 of the linked works' people carry one |
| **place authority** | ◐ designed, unbuilt — § A3. `place_id` is stored on 12,134 people and resolves to nothing |
| **Phase 7 research agent** | ◐ designed, unbuilt — § H, and it is a *report verifier*, not an agent |

That is a scope decision, not a slip, and it is recorded here rather than by editing the
sentence above — because a definition that quietly grows to match what got built measures
nothing. The clause table stands as the record of what the original definition asked for and
when it was answered.

**What remains and is NOT v1.** Taishō 56–84 needs an email a person must send, and the
`phase-2` tag is withheld until it resolves — stamping a gate green over a known gap is how
gates stop meaning anything.

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

### A2. Authority identity, dates and lineage — ▸ DONE 2026-08-28

**A byline is not a person, and until this landed the corpus could only say what the
edition printed.** `mix pramana.authority.import` reads DILA's person authority
(CC BY-SA 3.0) into two tables:

    49,259 people · 46,157 relations · 2,910 with an external id
    7,711 with a birth date · 8,840 with a death · 16,134 with a sect · 12,134 with a place

8 relations were dropped for naming a person the file does not define. `works.authority_id`
links **2,374 works at 60.4%** of resolvable bylines — see `Pramana.Authority` for why the
first measurement of that said 74% and was wrong.

**Dates are bounds, and the schema refuses to let that be forgotten.** 1,515 works now
carry `date_start`/`date_end` derived from the attributed person's lifespan, each stamped
`date_basis: authority_lifespan`, with a CHECK making a date-without-a-basis
unrepresentable. 1,298 have both ends, 195 are *no later than*, 22 *no earlier than*.

Two errors were caught on the way and both are the same shape — **a false precision is
worse than an absence**:

- The first version coalesced the ends, so a person recorded only by death produced
  `1798 – 1798`, which reads as "composed in 1798" and means "composed no later than". 217
  works said that.
- The first date *filter* then read the resulting null lower bound as "could be any year",
  and returned that same 1798 work under `composed_before: 400`. The filter now falls back
  to the known end — the coalesce storage refuses, because storing a claim and testing one
  are different acts.

**Reachable, per rule 60.** `search` gained `composed_after`/`composed_before` on **both**
retrievers, and `get_person` (tool 16) returns dates as ranges with both ends, sect, place,
recorded teachers and students, and a Wikidata q-id where DILA has one — 1,446 of the
linked works' people do. Every dated search carries `Coverage.dated/0`, because the filter
reads 1,515 works of 17,281 and a query that silently discards 91% of the shelf is rule 44
with a nicer interface.

**What is deliberately not done.** `date_basis` admits `catalogue` and `colophon` and
nothing in the corpus is either. A colophon date is the only one that is really the
*work's* date rather than its author's; it needs a source that states it, and no such
source is acquired. The enum exists now so that filling it later is a data change rather
than a migration, and so a reader can see that every date currently held is the weakest of
the three kinds.

---

## Next

### B. CBETA's other collections — ▸ 10 OF 26 HELD, 2026-08-27

**▸ J (嘉興藏) ACQUIRED AND BAKING, 2026-08-27.** 287 files, 105 MB, network-only and run
alongside code work — the one stage `docs/PLAN.md` says is safe to overlap, and it was.

Three things this collection confirms, all of them fixes made this morning working on
data they were not written against:

- **`Lockfile.merge_source/1` held.** The cbeta entry went 3,707 → **3,994** files. X's
  acquisition had deleted the Taishō's 2,471 records; J's added to them.
- **Two works span volumes — JB271 (31+32) and JB277 (32+33).** Without the assembly fix
  they would each have silently lost a volume, exactly as X's six did. The census caught
  them **before** the bake rather than after, which is the whole point of counting from
  the source.
- **The lineation is single (`ed="J"` only) and the bylines follow the rule** — 明 時蔚說
  普壽集, both 說 and 集 being composition verbs. No new normalizer, no new grammar.

J also names itself: `<sourceDesc>嘉興大藏經（新文豐版）</sourceDesc>`, so
`Pramana.Cbeta.Collections` gains a third **sourced** name. The rule that a collection's
name is not written down until the files that state it are on disk is now three for
three.

**Note the work ids carry a letter**: `J40nB492` → `JB492`. The path pattern already
allowed it.

**Goal, as written on 2026-08-24.** *Ingest `X` (卍續藏), and then `J`, `B`, `K`, `L`, `N`
as they prove out.* Nine of those ten landed in three days — X, J, and the seven editions
K/A/P/L/U/S/M — leaving `B` and `N`, and `N` is deliberately held back (see B2).

**Why it was the largest gap.** This is meant to be a substrate for the Buddhist canons and
it held **one CBETA collection out of 26** — witness `T`, 2,471 texts. It now holds ten,
17,061 texts, every one chunked and embedded. No permission was needed for any of them; the
gap that *does* need permission is Taishō 56–84, and that is an email a human has to send.

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

### B2. Which collection next — ordered by KIND, not by size

**J refuted the size heuristic on 2026-08-27.** 285 works of Ming/Qing Chan material moved
no retrieval number at all, while X's 1,230 works of sūtra exegesis cost four Chinese
cases. The mechanism is **genre overlap with the gold set**, not volume, so the collections
still unheld sort into three groups that behave differently and should be taken in this
order — N, group 3 below, was taken on 2026-08-28:

**1. ~~Alternative EDITIONS of works already held — the apparatus payload.~~ ▸ ACQUIRED
2026-08-27, AND THE STATED RATIONALE WAS WRONG.**

    K   高麗大藏經     9 works        A   趙城金藏      9
    P   永樂北藏      13             L   乾隆大藏經    21
    U   洪武南藏       2             S   宋藏遺珍       2
    M   卍正藏經       1                         57 works, all baked

The claim was that these are *other witnesses to works already held*, so acquiring them
would turn the 572,701 segments carrying a variant apparatus — which names 【宋】【元】
【明】【麗】 readings for texts the corpus holds only in the Taishō — into passages a
reader could open. **Measured after baking: of 57 works, 2 share a title with anything in
T, X or J.** Not 40, not 20. Two.

CBETA does not publish a parallel Koryŏ *text* of the Taishō's works. It publishes a
**selection of what is distinctive to each edition** — the Koryŏ's own collation record
(高麗國新雕大藏校正別錄), Song imperial compositions preserved there (御製秘藏詮, 御製逍遙詠),
phonetic glossaries (音義), Song catalogue records (大中祥符法寶錄, 景祐新修法寶錄), and in
L a run of Ming-Qing Chan recorded sayings (雪嶠信禪師語錄, 密雲悟禪師語錄). Rare material,
much of it digitised nowhere else — and **not** the variant-reading unlock.

**So the apparatus gap is still open, and it is not closable by acquiring CBETA
collections.** Opening a 【麗】 reading needs the Koryŏ text of *that Taishō work*, which
would come from the Korean Tripiṭaka Koreana project rather than from CBETA's K. That is a
new source with its own licence and citation grammar, not a collection flag.

**The acquisition was still worth it**, for reasons that survive the correction: 57 works
of rare material, and it exercised the assembly path four volumes deep (L1557) where
nothing before had gone past two.

**▸ RE-BASELINED 2026-08-27. The 57 works cost nothing measurable — with one honest
caveat.** 1,400 cases in 23m58s over a rebuilt HNSW index: **93.4% → 93.1%**, four cases,
inside the measured rebuild floor of six. Every guard, provenance and topical row is
unchanged to the case.

    retrieval/chinese   96.6% -> 96.1%   -1
    retrieval/pali      81.3% -> 80.0%   -2
    retrieval/tibetan   50.0% -> 48.4%   -1

**The caveat is the direction, not the size.** All three retrieval rows moved the same way,
and noise need not do that. Each is within its own floor and the total is within the
overall floor, so the honest statement is *consistent with noise*, not *proven to be
noise* — one sample cannot separate four cases of jitter from a small real displacement
cost, which is exactly the mechanism X demonstrated at a larger scale. If a later run over
the same index shows the same three rows down again, that is a second sample and it means
something.

**2. Genres the corpus does not contain at all — additive, non-competing.** ▸ **ACQUIRED,
BAKED, EMBEDDED AND GATED 2026-08-28, and the prediction held: `retrieval/chinese` is 95.7%
before and after, identical, not merely within noise.** 189 files, 182 works, 43.4 MB.
Baking is the next step. N demonstrated that displacement costs scale with the *volume of
competing material*; epigraphy and gazetteers are not scripture and cannot displace a
doctrinal query at all, so they extend what the corpus **is** at no measurable retrieval
cost. The lockfile is 4,340 files and CBETA is **16 of 26 collections**.

Three widths had to be checked, and the guard caught all five collections together: **GA
and GB are three digits** where their neighbours are two, and **I, GA and GB number their
first volume zero**, which `volume_token/2` rejected outright — rule 59. ZS also prints
*alphabetic* page numbers (`ZS01n0001_pa001a01`), which nothing parses yet but something
eventually will.


    I   北朝佛教石刻拓片百品  101   stone-inscription rubbings, Northern Dynasties
    F   房山石經           27   the Fangshan stone canon, carved 7th–12th c.
    GA  中國佛寺史志彙刊     58   temple gazetteers
    GB  中國佛寺志叢刊       2
    ZS  正史佛教資料類編      1   Buddhist passages from the official histories

Epigraphy and gazetteers are not scripture and will not answer a doctrinal query, so they
cannot displace one. They extend what the corpus **is** rather than how much of it there
is — and F in particular is a stone witness to texts held in print, so it belongs to group
1 as well.

**3. The one that will move numbers, and is worth it anyway.**

    N   漢譯南傳大藏經（元亨寺版）  83   a Chinese rendering of the Pāli canon

**▸ THE PREDICTION WAS WRONG, AND THE GATE SAYS SO — 2026-08-28.** This item said N was
"the one that will move numbers" and should get a gate run of its own because it competes
with the Āgama material head-on. It got one. **`retrieval/chinese` moved 96.1% → 95.7%, one
case, inside the rebuild noise floor.** Pāli unchanged, everything else unchanged.

**Three collections have now tested the heuristic and it is neither size nor genre — it is
the VOLUME OF COMPETING MATERIAL, which is their product:**

| | works | chunks | genre overlap with the gold set | cost |
|---|---|---|---|---|
| X 卍續藏 | 1,230 | ~285,000 | high — sūtra exegesis quoting definitional formulae | **4 Chinese cases** |
| J 嘉興藏 | 285 | ~30,000 | low — Ming/Qing Chan recorded sayings | 0 |
| N 漢譯南傳 | 38 | 30,399 | **highest** — the same discourses, in Chinese | 1 case, noise |
| I·F·GA·GB·ZS | 182 | 16,984 | **none** — rubbings, gazetteers, dynastic histories | **0, exactly** |

**Four collections now, and the model is cost ≈ volume × overlap — both factors, neither
alone.** N has maximum overlap and cost nothing because it is 4% of the pool. Group 2 has
meaningful volume and cost nothing because a stone rubbing cannot answer a doctrinal query.
Only X had both, and only X cost anything. `retrieval/chinese` is **95.7% before and after**
group 2 — not "within noise", identical.

N is the cleanest test available: maximum genre overlap, minimum volume. It is 30,399
chunks against 703,407 Literary Chinese chunks — **4.3%** — and displacement is a
competition for ranked slots, so 4.3% of the pool cannot displace much however well it
matches. X was ten times the volume at lower overlap and cost four times as much.

**The original claim below stands corrected, not deleted.** It read: *"It competes with the
Āgama material head-on — the same discourses in Chinese, which is precisely the overlap that
cost X four cases."* The overlap is real; the inference from it was not. The payoff is a three-way comparison nothing else offers: the Pāli, the Chinese
Āgama translated from a different Indic lineage, and a modern Chinese rendering of the
Pāli itself. `Compare.versions/2` and the parallel data are already shaped for it.

**▸ BAKED 2026-08-28. 38 works, 0 failed, 365s. `verify OK` over 4,081 CBETA texts and
2,428,757 segments, byte-identical.** Corpus 17,061 → **17,099 texts**, 12,041,579 →
**12,358,849 segments**.

**The census is the headline: 83 files, 38 works, and 16 of the 38 span volumes — 42%.**
N0018 spans **twelve**, three times the deepest case the assembly path had ever seen
(L1557 at four). Baked per file, this collection would have produced 83 works where there
are 38, with 16 of them keeping one volume of themselves — worse than X's six, which is
why the path exists. The depth record and the size record are different works: N0018 is
49,489 lines against L1557's 104,959, so the 600 s transaction ceiling was never at risk.

**Why the provenance work had to come first.** CBETA's byline for N0006 相應部經典 is
`通妙譯` — ends in 譯, so `composition_origin: "indic"`, correctly, and `text_role` is null
as it is for every non-Taishō collection. Before `witness_name` landed, a caller comparing
N0006 with T0099 雜阿含經 would have received two records differing in one letter, where one
is Guṇabhadra's c. 435 rendering of a Sarvāstivāda original and the other a 1990s Chinese
rendering of the Japanese rendering of the Pāli. It now says **"Chinese Translation of the
Pāḷi Tipiṭaka (Yuan Heng Temple Edition) 漢譯南傳大藏經（元亨寺版）"**.

`integrity OK` over all 17,099 texts: every `<lb/>` produced a line, every line with
printed content got a segment, all 305,942 gaiji reachable, 0 stranded. It also now names
**37 volume-spanning works** across the corpus, 16 of them N's.

**Still to do:** N is unchunked and unembedded, so it is lexically reachable and
semantically invisible — and the gate run this collection was supposed to get is only
meaningful after it is embedded. That is a GPU spend.

**Found while checking it, not fixed:** `text_role` is null for **1,640 texts** — every
non-Taishō CBETA collection, since only T has a 部 table. `role:` is a retrieval filter, so
a query for `["root"]` silently returns Taishō only. Assigning roles by byline verb is
tempting and refused for the reason `Cbeta.Byline` already gives about 撰: guessing puts a
wrong label on thousands of works. N makes it sharper, because N holds the whole Tipiṭaka —
sutta, vinaya and abhidhamma — so a single blanket role for the collection would be wrong
three ways.

**One of these cannot be loaded without a schema decision first.** CBETA's collection `D`
is 國家圖書館善本佛典, 64 works — and the Degé Kangyur is already witness `D`. **Witness ids
are global; collection ids are not.** `witnesses` is one table keyed by id, so loading
CBETA's D would attach 64 Chinese rare-book texts to the witness row that says *"Derge (sde
dge) Kangyur, par phud printing"*, and every URN would read `pramana:cbeta.D:D0001`
alongside `pramana:derge.D:toh1-1`. Nothing would raise. Found 2026-08-27 while naming the
CBETA witnesses from CBETA's own `canons.json`, which is when it became clear the two
namespaces were being treated as one. **Decide the namespacing before acquiring D**, and
note the same question is waiting for CBETA's `B`, `G`, `I`, `N` and any future source that
picks a single-letter sigil.

**Deliberately last:** B (204) and ZW (202) are miscellanies, G (60) and D (64) are
selections, and Y/TX/YP/LC (117 works between them) are **modern authors' collected
works** — Yin Shun, Taixu, Yen Pei, Lü Cheng. Those four are 20th-century scholarship
about the canon rather than canon, and loading them without a `text_role` that says so
would put a living author's essay in the same bucket as a sūtra. That is a provenance
question to answer before an acquisition question.

### C. The reader — ▸ FIVE SCREENS SHIPPED, first pass complete 2026-08-27

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
after — the exact failure `docs/HISTORY.md` records for the MCP tool. That is why the
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
this held **two when the function shipped**; 24 collections and 1,298 works were absent with
nothing saying so, which is the Taishō 56–84 failure one level up. (Eleven are held now —
the function is computed, so it has tracked every ingest since without an edit.) The counts are measured from the pinned catalogue
(`Pramana.Cbeta.Collections`, one git-tree call at `2b8ab8d5`), and **most entries have no
name on purpose**: each CBETA file states its own collection in `<sourceDesc>` — T's say
大正新脩大藏經, X's say 卍新纂大日本續藏經 — and for a collection we have not acquired there
is no such statement, so expanding `YP` into some canon would be a guess a reader could not
tell from a fact.

**▸ 2026-08-27 — the work browser and the apparatus shipped, and the reader's first pass
is complete.**

`/works/:work_id` is the outline as a first-class page, leading with provenance rather
than contents: an outline is usually the first thing anyone sees about a text, which makes
it the moment a text is misjudged. Without the axes, a Kamakura-period commentary and a
Kumārajīva translation look identical here — same shape, same 品 headings, same juan count.
T0099 shows 50 juan, 1,455 sections, 3,500 lines carrying a variant, and its four candidate
異譯本 with the shared-passage counts that are the evidence for each.

The apparatus now goes through `Apparatus.at/1`, so **witnesses are named from the text's
own header** — 【大】/【宋】/【元】 rather than `#wit1`, which means 38 different things across
the canon. A neighbouring line says a variant *exists* and does not print the raw id: a
sigil-shaped string in front of a reader is the exact failure that module was written to
prevent. `Apparatus.count_for_work/1` is new and in the domain, because a surface counting
`meta ? 'apparatus'` for itself is a second definition of what an apparatus is.

**▸ 2026-08-27 — survey and inventory land, and the reader is five screens.**

`/survey` renders `Retrieval.Survey`: **every** occurrence of a phrase, counted rather than
sampled, because a ranked list of ten invites *「this phrase appears in the Lotus」* when what
was measured is *「it ranked highly in ten results」*. `/inventory` renders
`Inventory.snapshot/0` and **leads with the gaps rather than the totals** — 17,061 texts is
an impressive number and an uninformative one, while *ten of CBETA's 26 collections, and
Taishō 56–84 entirely absent* is what decides whether this corpus can answer a question.
It is the only screen that answers the coverage question **before** a reader asks one; the
other four answer it beside results already requested.

Both compute nothing of their own. `Inventory.snapshot/0` had anticipated this since Phase
3 — *“Phase 8 will want the same numbers for the reader, and a second implementation is how
two surfaces start disagreeing about what the corpus contains”* — and it gained
`cbeta_coverage`, without which the provenance breakdown describes the Chinese material as
though it were the Chinese canon.

**▸ 2026-08-27 — deep links into the published editions, and a defect they exposed.**

Every passage now links into CBETA Online, SuttaCentral or 84000. Formats measured on ids
drawn from the corpus, never assumed: SuttaCentral **40 of 40** (three land on the range
that contains a short text, which the note states), 84000 **29 of 30** — it catalogues the
whole Degé, not only what it has translated. That covers the 13,017 SuttaCentral and
Tibetan texts, over three quarters of the works held, which had no link at all.

**Building them found that the CBETA linehead had been wrong for 725,650 segments** — 7.1%
of the CBETA corpus, emitted through the MCP tools and the passage page. Two constants, one
in the reader and one in acquisition, both assuming the Taishō's two-digit volume; plus
provenance handing over a volume *range* for the 18 works that span volumes. See rule 53.

**Still to build:** nothing on the reader's critical path. Another screen is not what this
needs next — the gap named at the top of this file is root↔commentary alignment, and the
reader will render it when it exists.

### D. The semantic arm cannot express ignorance — newly discovered, 2026-08-27

**What was found.** `absence` fell 100% → 75% when X landed, and the surviving failure is
real: for 本門戒體, a doctrine no text in this bake discusses, the lexical arm returns
**0 hits** and the hybrid returns **5**, all semantic, none of them about it. The semantic
retriever returns its k nearest neighbours regardless of distance, and there is no distance
at which it says nothing.

**Why nobody saw it.** The case passed for two phases because the `origin: ["japanese"]`
filter had an empty pool to search — no Japanese-composed work existed, so "empty" was free
and looked like refusal. X's 145 Japanese works gave the filter something to admit.

**Why it matters more than the number.** Every other guarantee here is about not making a
claim that cannot be checked. A retriever that always returns something puts a caller in
the position of deciding whether five plausible near-misses constitute an answer — and a
model, handed five passages, will generally use them. This is the retrieval-side twin of
the Coverage doctrine: *absence must be sayable.*

**▸ MEASURED AND RESOLVED 2026-08-27 — and the resolution is not the obvious one.**

48 queries probed before anything was built: 40 with known answers (20 Chinese
definitional, 20 English→Pāli/Tibetan) and 8 with none.

    top-1 similarity      min      max
      answerable         0.7188   0.9223     Chinese 0.72–0.80, English 0.76–0.92
      unanswerable       0.6042   0.7423

    gap (top1 - top10)
      answerable         0.0077   0.0957
      unanswerable       0.0055   0.0358     6 of 8 INSIDE the answerable range

**The gap statistic is dead, and it was my hypothesis.** The prediction registered before
the run was that a scale-free discrimination measure would separate where an absolute one
could not — the lesson the Tibetan adapter probe taught. It does not: `photosynthesis in
C4 plants` has a wider top1–top10 spread than 13 of 20 answerable Chinese queries.
Discrimination was the right lens there and the wrong one here.

**A hard threshold is refused on cost.** 0.75 is the lowest cut admitting none of the
unanswerable set, and it refuses **4 of 40 answerable queries — 10%, or ~45 of the 446
retrieval cases, to gain 1 absence case.** No cut-off does better, and the scale is
per-language anyway: English queries sit a whole band above Chinese ones, so one number
is fighting two distributions.

**Shipped: the system reports what it knows about its own answer.** `semantic_confidence`
carries the top similarity and a band — `strong` / `weak` / `no_close_match` — on every
hybrid response, through the MCP payload and above the reader's results. It is the same
shape as `retrievers`, `mode` and `embedding_coverage`: state the fact, let the caller
weigh it. Verified end to end:

    云何為念力                                   strong          0.7809
    本門戒體 (origin: japanese)                   weak            0.7068
    how to configure a PostgreSQL connection pool no_close_match  0.6267

`nil` when the semantic arm did not run, because "no model was loaded" and "the model
found nothing close" are different facts and only the second is about the corpus.

**▸ THE SECOND SIGNAL IS MEASURED AND SHIPPED, and it is one-way.** `lexical_support`
now rides beside the band. Alone it is useless — it is zero for every English→Tibetan
query, so it detects the query's SCRIPT, not the corpus's ignorance. Combined it
separates, measured through `Retrieval.search/2` over 56 queries:

    lexical_support == 0 AND band != strong
      answerable, Chinese literal        0 of 20
      answerable, English -> bo/pli      0 of 20
      answerable, Chinese paraphrase     0 of 6
      unanswerable                       6 of 10

**When it fires it is reliable; when it is silent it means nothing.** Nothing in 46
answerable queries triggered it, paraphrases included — and paraphrase is the case that
would have killed it, since 眾生皆能成佛 appears nowhere as a literal string. Four
unanswerable queries slip through: three collect incidental n-gram overlap, and one —
如何申報所得稅, *how do I file income tax* — the semantic arm places in the `strong` band
outright. **The band alone can be confidently wrong**, which is the strongest argument
yet against ever making it a gate.

**And the first measurement of this was wrong.** It was taken by calling `Lexical.search/2`
in phrase mode rather than through the shipped path, which reported 8 of 8 rather than 6 of
10 and 0 lexical support for paraphrases rather than 28. The hybrid arm falls back to
character n-grams; the component does not. Third proxy to flatter a signal in one day.

**abs-001 stays red, and should.** Reporting is not refusing. Closing it means suppressing
results, and suppression costs ~45 retrieval cases at the only threshold that works.

### E. Public demo — newly unblocked

**Why it moved.** The Phase 2 gate recorded "the public corpus is currently EMPTY". That
stopped being true two phases ago and nobody noticed until 2026-08-24: **13,017
redistributable texts, 1.8M segments, 315k vectors**, and `redistributable_only: true`
returns real results end to end. The blocker was never the reader; it was having nothing
lawful to serve.

**▸ 2026-08-27 — and having lawful content was never the whole blocker either.**
`mix pramana.public.check` now reports what a public deployment of a given database would
actually serve, and this one is **not safe to expose**:

    forbidden by licence        34,697 rows   cbeta 4,043 · 84000 30,653 · 1 local
    withheld by uncertainty     76,040 rows   CC0 text, licence INFERRED not matched
    safe                       147,733 rows

Two things follow, and neither was in this item before.

**A filter is not an enforcement mechanism.** `license_class:` is an option on some
retrieval queries; `Corpus.resolve/1` takes no such option at all, so a public URN
endpoint over this database serves every text in it, CBETA included. The public demo must
run against a **separate bake from a lockfile holding only redistributable sources** —
enforced by the artefact, the way invariant #3 enforces reproducibility, not by every
caller remembering an option.

**The largest blocked bucket was our own caution, not a licence — ▸ AND IT IS FIXED.**
76,040 translation rows were CC0-1.0 and flagged `redistributable: false` because
`mix pramana.sc.translations` inferred the licence rather than matching the publication
record. **The publication says which files it covers, and says it as a path**: every record
in `_publication.json` carries a `source_url` pointing at the directory it publishes, so
the governing publication is the one whose directory contains the file. Matching on that
resolves **4,784 of 4,996 files exactly**, against a uid-prefix rule that could not match a
collection whose uid is not a prefix of its members — Brahmāli's `pli-tv-vi` is the whole
Vinaya Piṭaka and its works are `pli-tv-bu-vb-pj1`.

    withheld by uncertainty     76,040  ->  9,841
    servable                   147,733  ->  213,932

The remaining 9,841 are real: 83 files of Sujato's Jātaka, in the repository and absent
from `_publication.json`, plus his `name/` glossaries and four of Suddhāso's. Nothing local
can resolve those, and `redistributable` correctly stays false.

**▸ AND THE ARTEFACT EXISTS — `mix pramana.public.bake`, 2026-08-27.**

    pramana_public   13,017 texts · 1,797,144 segments · 210,756 renderings · 0 CBETA
    forbidden        0 rows
    bake_id          9539ef41…  (the research corpus is 0a687700… — never confusable)

A separate database from a derived `sources.public.lock.json`, not a query filter. The
reason is `Corpus.resolve/1`, which takes no licence option at all: a public URN endpoint
over the research database serves every text in it. **Safety is a property of what is
present.** The task refuses to run against a database whose name does not say `public`, and
verifies the result before calling it done.

**It found its own defect on the first run, and that is the part worth keeping.** The
Tengyur stage was passed `--source derge-tengyur` to a task whose switch is `--collection`,
and `OptionParser.parse/2` drops an unknown switch silently — so it re-ran the Kangyur, the
public corpus held 1,195 Tibetan texts instead of 4,575, every stage returned `:ok`, and the
bake reported **"✓ safe to expose"**. It had verified that nothing forbidden was present and
never asked whether anything expected was missing: the coverage doctrine failing inside the
artefact built to embody it. Every ingest now declares a row floor. See rule 57 — and all
**35** tasks in the repo now use `OptionParser.parse!/2` with `strict:`, because they all
had the same silent-typo behaviour.

**▸ CHUNKED, AND THE TRANSLATION LAYER IS SEARCHABLE — 2026-08-27.** 260,073 chunks in
116s, a 6.9× reduction on segments.

**Exercising the artefact found the defect that mattered most.** An English query reached
the lexical retriever, which reads `segments`, and came back with **Pāli passages sharing
character n-grams with the English** — three confident results with nothing to do with the
question. The 210,756 renderings that could have answered were reachable only through an
anchor the caller already had. On the public corpus, where those renderings are most of
what a reader can use, that was the whole surface.

`Translations.search/2` fixes it, with a GIN index on `to_tsvector('english', text)`.
Postgres FTS and not `pg_bigm`, which is the same rule as always read the other way round:
match the tool to the script, and English has whitespace, morphology and stop words.

Two decisions worth keeping:

- **A rendering is never fused into the ranked passage list.** It arrives in a section of
  its own, on the reader and in the domain. Fused, a fluent English sentence would appear
  as a peer of the text it translates and invariant #8 would survive only as a field
  somebody remembers to read.
- **All terms, then any term, and the answer says which.** The unit is one rendered *line*,
  so requiring every term in one row is far stricter than it looks — `Baka Brahmā` returns
  nothing while `Baka` and `Brahmā` each return the same discourse. The fallback is
  reported as `match: :any_term`, exactly as `Lexical` reports its `ngram` fallback.

**Still to do before the demo is servable:** no vectors, so it is lexical-only. Embedding
1.8M segments is a GPU spend and a separate decision. And it is not deployed — hosting is a
choice nobody has made.

**Scope guard.** Phase 8 is a *renderer* over an API that already returns spans, URNs and
offsets. If it starts needing new domain logic, that is a signal the API is missing
something — fix the API, not the view.

### F. `topical/chinese` is still 0% — and one route to it is now closed

**▸ THE DETERMINISTIC BRIDGE IS REJECTED, 2026-08-28.** Before building the term table
below, a cheaper hypothesis was registered and tested: an English question could reach a
Chinese passage with no model and no glossary, by walking data already held — English query
→ `Translations.search` → Pāli anchor → `text_parallels` → Chinese anchor.

**1 of 12.** And the diagnosis matters more than the score: it fails at the *parallels*
step, not the term step. Eleven of the twelve questions land on Pāli works with **no
openable Chinese parallel at all**, so there is nothing to check a term against.

**Which surfaced a number that had never been published.** `text_parallels` holds 407,176
passage parallels and **24,717 of them — 6.1% — have both ends in this bake.** The reader
has always reported this per work, where T0099 reads 1,958 recorded and 1,661 resolvable,
and that shape invites the impression that resolution runs at 85%.

Every unresolved row was checked and **none is a resolution failure**: all 363,047 name a
work no source here provides, chiefly the Vinaya prātimokṣa witnesses SuttaCentral collates
across Sanskrit manuscript finds and several Chinese recensions it publishes itself —
`san-mu-bu-pm-gbm` alone is 12,524. `Coverage.parallels/0` now states it and `/inventory`
shows it.



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

### G. Tibetan recall — 24 cases unreachable

`retrieval/tibetan` is 48.4%, close to the ~51.6% ceiling reranking can reach. The
remaining misses are **absent from 200 candidates**: a recall failure no reordering fixes.
BGE-M3 packs Tibetan at 0.9727 mean pairwise cosine, so its candidates are near-ties by
construction.

The lever is a better embedder. **A LoRA was already tried and failed completely** — every
proxy said it worked and the gold set said `retrieval/tibetan` 0%. Do not retry without a
hypothesis for *why* it failed that the proxies could not see. Training data exists (30,653
aligned bo↔en folio pairs).

---

### A3. Place authority — **v1 scope**, ▸ DONE 2026-08-28

**`place_id: "PL000000009585"` is stored on 12,134 people and resolves to nothing**, because
the person authority was imported and the place authority beside it was not. They are the
same repository at the same pin — `sources.lock.json` already holds
`dila-authority @ 4c204f88` — so this is one more file out of a commit already recorded,
not a new source.

    authority_place/Buddhist_Studies_Place_Authority.xml   31.1 MB
    authority_place/districts.xml                           2.9 MB

**What it buys, measured against what this bake actually cites:**

    people with a place_id      12,134  across 4,310 distinct places
    ...of people we cite           287 distinct places, across 1,529 works
    people with a place NAME and no id   0

1,529 works is the same order of reach as the 1,515 that gained a date, and the entry
carries more than a label:

    <place xml:id="PL000000000001">
      <placeName xml:lang="zho-Hant">闊悉多國</placeName>
      <placeName xml:lang="eng-Latn">Khost</placeName>
      <location><place key="PLA000002">阿富汗</place><geo>67.868089 36.555275</geo></location>

**What it resolves to**, measured over the denominator that matters — the 287 distinct
places behind works in this bake, 284 of which resolve:

    <geo>               284 / 284   100.0%     coordinates
    <district>          284 / 284   100.0%     中國-浙江省-杭州市-下城區
    <country>           231 / 284    81.3%     江南東道 — the Tang circuit, not a modern state
    alternative names   111 / 284    39.1%
    English name         14 / 284     4.9%

That is richer than a coordinate. `<district>` is a **full modern administrative path**, so
places roll up by province and prefecture for free; `<country>` is the **historical** unit —
江南東道, 隴右道, 西突厥 — which is the one a scholar actually wants, because "a Jiangnan
translator" is a claim about the Tang and not about Zhejiang.

**Four numbers were published for this before that one, and three were my errors.** The
sequence is kept because it is the useful part:

| claim | value | why it was wrong |
|---|---|---|
| English placeName is a cross-lingual win | 24 of 8,510 | measured on a prefix; real answer 4.9% here |
| `<geo>` is near-universal | 99.4% | prefix again — right by luck |
| `<geo>` is 2.3%, and 0% for our works | **wrong** | the regex matched `<geo>` and the tag is `<geo cert="high">` |
| `<geo>` on our works | **100%** | correct |

The third is the one worth remembering: a **measurement bug reads exactly like a finding**,
and it survived because it was the number that confirmed the previous correction. See rule
62 and `docs/PROXIES.md`.

**Coordinates are `longitude latitude`, and nothing says so.** 于闐 is `79.828 36.9881` and
Khotan is 37.1°N 79.9°E. TEI's own convention for `<geo>` is latitude first, so reading the
element as documented gives a point in the Arctic Ocean. `cert="high"` rides on most of
them and must be stored beside the value, never dropped.

**Two things to get right, both already learned here:**

- **Rule 43.** dila-authority is now a source acquired in parts. The lockfile write must
  MERGE the place files into the existing entry — `put_source/1` would drop the person
  file's record exactly as acquiring X dropped the Taishō's 2,471.
- **A containing region is not a birthplace.** `<place key="PLA...">` nests a place inside
  a region, and flattening the two into one column is the same collapse rule 61 was written
  for. Store the id and the region separately.

**▸ BUILT.** `Pramana.Acquire.DILA` fetches the two place files **at the commit the source
was already pinned to** — resolving a fresh pin would put files from two commits under one,
which `Lockfile.merge_source/1` refuses outright. The person file's record survived the
merge, which is rule 43's whole point:

    dila-authority @ 4c204f88   3 file(s), verify OK
      51,371,527  authority_person/Buddhist_Studies_Person_Authority.xml
      31,101,686  authority_place/Buddhist_Studies_Place_Authority.xml
       2,886,399  authority_place/districts.xml

`Authority.parse_places/1` and `authority_places` hold **59,335 places — 58,500 with
coordinates, 38,048 with a historical region**. `Authority.person/1` resolves `place_id`
into both region schemes and `get_person` returns them, so the capability is reachable
(rule 60).

Two things the data forced, both of them refusals:

- **`district` is `:text`, not `:string`.** It runs to 536 bytes where a place spans modern
  borders, with Cyrillic and parenthesised English inside it. 255 was chosen from what a
  Chinese county name looks like.
- **257 districts are semicolon-separated LISTS of regions, and get no `district_path`.**
  Splitting `中國;蒙古;俄羅斯-…-Sakhalin` on `-` yields fragments that look exactly like a
  hierarchy and are not — rule 33. The raw string is always kept, so the refusal loses
  nothing.

**And it exposed a defect older than itself.** Adding two files to `sources.lock.json`
changed `bake_id` — correctly, since the answers changed — while the *recorded* bake row
still held the old id. Every MCP response was therefore stamped with an id for inputs that
no longer exist, and every `replay` record cited a corpus nobody could reconstruct.
Acquisition rewrites the lockfile; only a bake writes the row; nothing watched the gap.
**Acquiring the person authority had done the same thing weeks earlier, and every gate
since passed.** `mix pramana.gate` now recomputes it in the lockfile step, and the bake was
re-recorded — cheap, because `Bake.record/1` writes a row rather than re-baking. Rule 64.

**One decision left open, deliberately.** `date_basis` admits `catalogue` and `colophon`,
and a **locally added modern commentary declaring its own date through the manifest** is
neither — it is someone stating a fact about a book in hand. `docs/COMMENTARY.md` now flags
it. Decide it when the first such text lands, rather than mapping it silently onto the
nearest existing word, which is how an enum stops meaning anything.

**Deliberately not done: a region filter on `search`.** `composed_after` works because the
date was denormalised onto `works`; a region filter would need either the same
denormalisation or two more joins on the hot retrieval path, and which of those is right is
a measurement nobody has taken. `get_person` answers "where was this translator from"; "this
phrase, in works by Jiangnan translators" is the next step and is not this one.

**And a registry line to correct in the same change.** `Pramana.Sources` names this source
*"DILA Buddhist Studies Authority Databases (person, place, time)"*. At this pin
`authority_time/` and `authority_catalog/` contain **README files and no data**. The name
promises two databases that are not there — which is the failure `Coverage` exists to
prevent, sitting in the registry rather than in a result.

**`active_at` stays unresolved and that is not this item.** 1,227 people carry place names
where they were active, as strings with no ids, because DILA records them that way. Matching
them to place records by name is a probabilistic join over a 4,310-row table with repeated
names, and invariant #5 puts that behind everything deterministic. Store the strings, say
they are strings.

---

### A4. 122 Chinese works were labelled Japanese — ▸ FIXED 2026-08-28

**This is an invariant #4 violation, and it was found by cross-checking the new place data
against composition origin.** `CLAUDE.md` states the invariant as *"A Japanese Kamakura-era
commentary must never be presentable as an Indian sūtra"*; this is the same error running
the other way, and it is in the corpus now.

    X1172  淨土晨鐘        清 周克復纂     → composition_origin: japanese
    X1162  淨土資糧全集    明 袾宏校正…   → composition_origin: japanese
    X0931  十不二門指要鈔詳解  宋 可度詳解… → composition_origin: japanese

Ming and Qing authors from Zhejiang and Jiangsu, presented as Japanese-composed.

**The cause is Taishō volume numbering applied to a collection that is not the Taishō.**
`Divisions.provenance_for_target/1` asks the work's byline first, and falls through to
`volume_fallback/1` when the byline's verb is unrecognised. That fallback is
`Taisho.provenance_for_volume/1` — where **volumes 56–84 are the Japanese sectarian
corpus**. X volume 62 is not Taishō volume 62. The module's own comment says the fallback
"gives them nothing, because that rule is Taishō volume numbering too", and the code calls
it anyway.

**Blast radius, measured rather than assumed** — CBETA non-Taishō works carrying an origin:

    from the byline:               1,261
    from Taishō volume numbering:    122   ← all X, all volumes 56–84, all "japanese"

23 further X works are `japanese` **correctly**, because their byline says 日本. `ms` and
`D` look like fallback cases in a naive query and are not: SuttaCentral and the Degé are
loaded by their own ingests, which declare provenance explicitly.

**Why it stayed invisible.** It produces a *plausible* label on a plausible number of works,
in the one collection that is genuinely part-Japanese — the 卍續藏 is published in Japan and
its header even reads 卍新纂**大日本**續藏經. Nothing in the corpus contradicts it. The
contradiction only appears once a translator's **birthplace** is resolvable and can be set
against the origin of what they wrote, which is what A3 bought.

**▸ FIXED.** `volume_fallback/1` now applies only to the Taishō; every other collection
whose byline is silent gets `%{}`. An unlabelled work is a smaller problem than a mislabelled
one, which this module already said about `text_role` and did not honour here.

    X japanese   145 -> 23     the 23 are the bylines that say 日本
    X text_role  122 -> 0      the same bad fallback had set `commentary` too

`mix pramana.provenance` re-derives non-Taishō CBETA works through `Byline.provenance/1` —
**the same function the bake calls**, so a from-scratch bake and this pass agree rather than
one undoing the other. `pipeline_version` → **5**: no segment moved, but two corpora that
disagree about who composed 122 works must not share a `bake_id`.

**The second half of the fix was abandoned on evidence.** The plan was to extend `@composed`
with the verbs actually present — 輯, 纂, 訂, 定, 答, 閱, 唱, 釋, 鈔, 次, 出, 節 — so most of
the 122 would become `chinese`. Measured against the Taishō, where the 部 table gives ground
truth, **that validation is impossible**:

    撰   234 works   223 chinese      the existing rule, confirmed
    譯 1,666 works 1,645 indic        ditto
    輯     4          纂 3            too few to judge
    訂 · 釋 · 鈔 · 節 · 次 · 閱        absent from the Taishō entirely
    出     2 works     0 chinese, 2 INDIC

These verbs are characteristic of the later 卍續藏 material and barely occur in the Taishō,
so there is no ground truth to check them against. **出 would have been an outright
mislabel** — both its Taishō occurrences are translations, which is what 出經 means. So the
122 are null, and null is honest. Extending the list needs a validation source that is not
the Taishō, and that is a separate piece of work.

**How it was found, and why nothing else could have found it.** `verify` and `integrity`
were both green over these 122 works, correctly — they were faithfully and reproducibly
mislabelled. It took a second, independently sourced fact about the same work: the
translator's **birthplace**, which § A3 made resolvable. See § A5.

---

### A5. `mix pramana.coherence` — the third check — ▸ SHIPPED 2026-08-28

**Every real defect found on 2026-08-28 came from the same move: two facts about the same
thing, derived independently, compared.** A single-source claim cannot be caught being
wrong. `composition_origin: japanese` on 122 Chinese works (§ A4) was internally consistent,
plausible, and sat in the one collection that genuinely is part-Japanese — nothing
contradicted it until a translator's **birthplace** became resolvable and could be set
against the origin of what they wrote.

The gate has two data checks and they answer different questions. This is the third:

| check | question | how it fails |
|---|---|---|
| `verify` | **determinism** — same inputs, same output | the pipeline is not reproducible |
| `integrity` | **fidelity** — nothing printed was lost | content was dropped from the source |
| **`coherence`** | **agreement** — independently derived facts about one work concur | a rule is applied outside its domain |

§ A4 is the case for it: `verify` and `integrity` were both green over those 122 works, and
correctly so. They were faithfully and reproducibly **mislabelled**.

**Each check is a threshold on an agreement rate, never a boolean.** Upstream data
legitimately disagrees with itself — DILA files a Yuan-era warlord under 明 because that is
the era he belongs to — so a check demanding 100% would be permanently red, which is the
failure mode `integrity` had while it cried wolf over 1,228 X texts. Pick the floor from the
measured distribution, as `docs/PROXIES.md` requires.

**▸ SHIPPED, in the gate, 3 s.** Four checks, and the first run corrected a written-down
number that nothing had re-checked:

    ok         dynasty_lifespan       5280/5320  99.2%, floor 97.0%
    ok         birthplace_origin       611/648   94.3%, floor 85.0%
    ok         byline_division        2044/2133  95.8%, floor 95.0%
    undecided  commentary_after_root     13/13   under the minimum population

`byline_division` is the one worth reading. `Pramana.Taisho.Divisions` claimed the byline
rule "agrees with this table 97.3% of the time" in a comment nothing recomputed; it is
**95.8%**, and the disagreements are structural rather than noise — which makes them
interesting rather than defective:

- `日本 永超集` (T2183) — byline says Japanese, table says Chinese, because the
  Japanese-composed catalogues sit in 目錄部. The byline is the more specific source.
- `唐 三藏法師義淨奉詔譯` (T2897) — byline says translated, table says Chinese, because the
  work is in **疑似部, the doubtful division**. A Chinese composition carrying a translator's
  byline is precisely what 疑似部 means, so the table is right and the byline is the forgery
  it was written to be.

`commentary_after_root` is `undecided` at 13 pairs and that is the design working: a check
that passed for want of data would report success it never earned. It becomes meaningful as
dates spread.

**The original measurements, taken 2026-08-28 before the suite existed:**

- **dynasty ↔ lifespan.** 4,401 people carry both; **4,354 agree (98.9%)** within a
  20-year boundary tolerance. The residual is upstream labelling, not our parse — 張士誠
  (1321–1367) is filed under 明, 楊英風 (1926–1997) under 清. This validates the date
  derivation end to end and is cheap to re-run.
- **birthplace region ↔ composition origin.** 印度 → 219 indic / 5 chinese; 斯里蘭卡 → 177
  indic / 0; 中國 → 611 chinese / 174 indic / **44 japanese**. The 174 are correct and
  expected — a Chinese monk *translating* an Indian sūtra is what the multi-axis provenance
  exists to express. The 44 were the thread that unravelled § A4.

**Three more that would have caught defects this project has already paid for:**

- **byline verb ↔ the 部 division table.** `Pramana.Taisho.Divisions` claims the byline rule
  "agrees with this table 97.3% of the time on the Taishō" and **nothing re-checks it**. A
  written-down number with no test is the doc failure this project has corrected four times.
- **a commentary postdates its root.** Newly checkable, because dates exist as of § A2. A
  violation is either a bad alignment or a bad date, and either is worth knowing.
- **URN linehead ↔ the collection's volume-number width.** Would have caught the two-digit
  volume bug that mis-cited **725,650 segments** and was then found a third time in
  acquisition. Rule 41's most expensive instance.

**What it is not.** Not a replacement for a human reading the data — every cross-check here
was *proposed* by noticing something odd, and no suite proposes its own checks. And not a
correctness proof: two independently wrong sources agree happily.

---

### A6. The feedback loop — signals, limits, and the ways it degrades — proposed 2026-08-28

**First, the premise deserves a challenge: most of what a feedback loop would buy is
available now, with no users at all.** The corpus is deeply redundant — 141,073 verbatim
quotations, curated passage parallels, and 異譯本 where the same Indic original was
translated two to six times. That redundancy is a **self-supervised eval**: if a query
retrieves a passage but not its known parallel, that is a recall failure detectable with
nothing but the corpus. Build that before instrumenting anyone, because it needs no traffic,
no privacy posture, and no waiting.

## What a query can actually tell you

Two populations, and they emit different things.

**A model, through MCP.** The tool and arguments (replayable); result count including zero;
which retriever arm answered and the score spread; **what it did next** — reformulated, drilled
into a URN, ran `survey_corpus`, or stopped; whether it then quoted, and whether the guard
passed or refused; which `Coverage` caveat fired.

**A person, through the reader.** The same queries plus which result they opened, and — the
strongest single human signal here — **whether they clicked out to CBETA Online or
SuttaCentral**. That means "I needed to verify, or your context was not enough", which is a
sharper judgement than dwell time.

## The unusual asset: this system can re-run its own history

Every response already carries `replay: {tool, arguments}` and `bake_id`. That is not a click
log — it is a **reproducible experiment**. Consequences, in order of value:

1. **Counterfactual evaluation on the real query distribution.** For every logged query,
   re-run it under the current and the proposed retrieval and diff. A retrieval change can be
   judged against what people actually ask before it ships, with no user involved and no gold
   labels required. This is the single highest-value item on this page and it needs only a
   log plus a harness.
2. **Corpus drift and retrieval drift become separable.** A result that changed between two
   observations changed because of the bake or because of the code, and `bake_id` says which.
   Without it every measurement is confounded.
3. **The log becomes a regression suite that grows by itself** — subject to the curation rule
   below.

## The guard already produces labelled data and throws it away

Every refusal is a labelled negative: this model, for this claim, produced this citation, and
it did not verify. Nothing else in the stack produces supervision that clean.

**The shape of the failure diagnoses the layer**, which is what makes this more than a
hallucination counter:

| failure shape | what it indicts |
|---|---|
| quote differs only in punctuation | normalization — CBETA punctuation is editorial |
| quote differs by one rare character | gaiji mapping, or a variant not in the table |
| URN off by one line | segmentation boundary |
| passage exists, cited at the wrong URN | **addressing**, not hallucination |
| URN does not exist at all | retrieval failed and the model filled the gap |

The last row is the important inversion: **a fabricated citation is usually a retrieval
failure wearing a disguise.** Counting which passages get invented tells you where the corpus
is hard to reach.

## Zero results are the highest-value signal a corpus project has

And they are ambiguous, so they need triage rather than counting. Deterministically:

- **Zero, and a caveat fired** → an acquisition priority with its cause already attached.
- **Zero, but `survey_corpus` finds it** → a *ranking* bug, not a coverage gap.
- **Zero, and a variant of the query finds it** → the variant table is missing an entry.
- **Zero, and a curated parallel of the target work has it** → an alignment opportunity.
- **Zero everywhere** → a true negative, and *that is valuable*: "the canon does not say this"
  is the answer this project exists to be able to give.

None of that needs a model, which is invariant #5 applied to the loop itself.

## Two mining ideas that feed deterministic infrastructure

**Reformulation pairs are implicit relevance judgements.** Query A returns nothing or is
abandoned; A′ succeeds. `(A, A′)` is a candidate synonym — and in this corpus that means
orthographic variants, 異體字, and the many transliterations of the same Sanskrit name. Those
feed the **variant table**, which is deterministic infrastructure rather than a model.

**English → Chinese pairs attack the one axis that has never moved.** `topical/chinese` is
**0% of 12** and has been since it was first measured, because no English layer exists over
the Chinese canon; `docs/PLAN.md` § F records two routes tried and rejected, and says what
remains is a corpus-derived term table. If a caller asks in English, gets nothing, and later
lands on a Chinese passage — by reformulating, or through a Pāli parallel — that pair is
**exactly the missing bridge, harvested from use**. It is the only proposal here that
addresses a known-hard failure rather than sharpening something that already works.

## How this degrades, which is the part to design against

1. **Popularity feedback.** Optimising for engagement promotes what is already findable, and
   in a canon the long tail *is* the scholarship. **Guard:** improvements must be demonstrated
   on a held-out set that is deliberately not traffic-weighted.
2. **Self-fulfilling evals.** Already paid for once here: the rendering gold set kept only
   phrases the retriever already found and had to be rebuilt. **Guard:** mined cases are
   *proposals*; a person promotes them.
3. **Corpus poisoning.** Invariant #7's stated reason. Anything user-supplied is untrusted
   input — local source text already is.
4. **Query confidentiality.** A scholar's queries reveal unpublished research direction. A
   query log is sensitive data and needs a retention policy before it has a first row.
5. **Model-specific overfitting.** Tuning to how one model phrases things breaks the *any LLM*
   thesis. **Guard:** segment by model, and require an improvement to hold across two.
6. **Reward-hacking the guard.** If quoting less makes verification easier, quotes will get
   shorter. Watch the quote-length distribution as a health metric, not just the pass rate.

## The architectural constraint, which follows from the thesis rather than from taste

**Nothing in this loop may change the response to a given (query, `bake_id`).** The moment it
does, `replay` stops replaying and the citation-of-a-retrieval property is gone. So: no
serve-time personalisation and no learned re-ranking in the request path. **Improvements ship
as a new bake or a new pipeline version** — which is the discipline this project already has,
and the loop must not become the exception to it.

Storage is append-only, outside the bake, keyed by `bake_id`, and never read during retrieval.
Human corrections land as an annotation layer carrying `method: human` and attribution — the
answer `docs/LAYERS.md` already gives for generated text.

## Order, and how you would know it is working

Free today: the guard's refusals are already computed, and `Coverage.caveat/0` already fires.
Both are discarded. Then: the query log; zero-result triage; **the counterfactual harness**;
reformulation mining; the English–Chinese term table; and last, the human correction layer,
which is the only item introducing a write path and must be designed against invariant #7
first rather than retrofitted.

**And the loop itself needs an eval, or it is a machine for generating plausible
improvements.** The test is whether a change driven by mined signal improves the *held-out,
non-traffic-weighted* gold set. If it does not, the loop is noise that feels like progress.

---

### H. Phase 7's first slice — **v1 scope** — verify a *report*, not just a quotation — ▸ SHIPPED 2026-08-28

**The research agent is not a thing this project builds, and saying so is the design.**
Invariant #7 keeps the MCP surface read-only and `CLAUDE.md`'s thesis makes the model a
swappable reader; an agent living inside the server would contradict both. What Phase 7
ships instead is the thing that makes **any** agent's report checkable — which is the same
move the citation guard already made for a single quotation, one level up.

**The gap is claims a citation guard structurally cannot reach.** `Guard.check_output/1`
byte-compares every quoted span, so a fabricated passage cannot survive. It says nothing
about the three claims that actually carry a report:

| claim | guard | what would check it |
|---|---|---|
| "T0262 says X" | ✅ byte-compare | already done |
| "X appears 36,775 times across 1,904 works" | ✗ | re-run the `survey_corpus` call and compare |
| "no Japanese-composed text uses X" | ✗ | re-run the search and confirm it is still empty |

The second and third are where a report goes wrong in the way that matters, because a
frequency claim generalised from twenty ranked hits reads exactly like one counted over ten
million segments.

**The piece that makes this possible already shipped.** Every tool response carries
`replay: {tool, arguments}` beside `bake_id` — added 2026-08-28 and described there as *"a
reproducible citation of a retrieval, exactly as a URN is one of a passage"*. Nothing yet
consumes it. This item is what consumes it.

**▸ SHIPPED.** `Pramana.Report`, `PramanaWeb.MCP.ReplayExecutor`, and `verify_report`
(tool 17). A report is markdown; a claim resting on a retrieval carries the call that
produced it in a ```pramana-replay fence, which is a copy of the `replay` field every tool
response already returns. `assert` names response keys and the values the report claims for
them, dotted paths reach into nested maps, and an empty `assert` still re-runs the call —
proving the named retrieval still executes is worth something on its own.

**Two decisions the build forced:**

- **The executor is injected, and its whitelist is explicit.** `Pramana.Report` cannot call
  the tools it names — they live in `pramana_web` and the domain has no web dependency — so
  the caller supplies an executor. That executor holds a hand-written list of read-only
  tools rather than reading the server registry, because a replay record is **untrusted
  input** naming tools chosen by whoever wrote the report, and a future tool must not join
  that list by accident. `verify_report` is absent from its own table: a report asking to
  verify a report is a loop over untrusted input.
- **A per-report cap on replays.** Every record is a query; a document with ten thousand
  fences would otherwise be a denial of service. Excess records are reported as skipped and
  **prevent `ok?`**, because a report whose evidence was not all examined has not been
  verified.

**Three bugs the tests caught, and the first is worth remembering.**
`String.to_existing_atom` is the right tool for converting untrusted keys and it has a trap:
**an atom exists only once the module defining it has been loaded**, and module loading is
lazy. `get_person` with a perfectly valid `authority_id` failed with "no function clause
matching", because the key had been dropped. `Code.ensure_loaded!/1` before atomizing.
Second, `decode/1` matched the success shape before `isError`, so a tool's clear refusal came
back as `:tool_returned_unparseable_json` — an error about our parser. Third, a `~s(...)`
sigil containing parentheses does not close where it looks like it does.

**Shape, as designed.** A sourced report is claims, each carrying quoted spans, replay
records, or both.

- `Pramana.Report.parse/1` — claims with their URNs and replay records out of markdown.
- `Pramana.Report.verify/1` — quotes through `Guard`; **replay records by re-executing the
  named tool with the named arguments against the named bake, and comparing the figure the
  report states to the figure that comes back**.
- `mix pramana.report.verify <file>` and a `verify_report` MCP tool — a read, so it sits
  inside invariant #7 beside `verify_citation`.

**Three refusals it must make, and each is the point:**

1. **A replay against a different `bake_id` is `unverifiable`, never `failed`.** The corpus
   changed; the claim may well have been true. Reporting that as a falsehood would teach
   people to ignore the checker, which is the failure mode `integrity` had while it cried
   wolf over 1,228 X texts.
2. **A claim with no quote and no replay is `unsourced`, and that is a result.** Counting
   only what it can check and publishing a pass rate over that denominator is rule 44 in the
   one place it would be most embarrassing.
3. **It does not judge whether a citation supports its claim.** `Guard`'s moduledoc already
   draws this line and it holds here: mechanical warrant, never interpretation.

**Why this and not a fleet of skeptic subagents.** The verification pattern going around is
N independent models voting on whether a finding survives. Invariant #5 says that is for the
residual only — and here there is no residual: re-running a survey is arithmetic over the
bake, and a majority vote is strictly weaker than a recount. Adversarial verification earns
its place on questions with no deterministic check, such as whether a commentary alignment
is real. It has no place on *how often*.

**Not decided.** Whether a report format is markdown-with-conventions or a JSON sidecar; and
whether promotion of a verified report into anything durable exists at all in v1 — probably
not, because a stored report is a claim the corpus would then appear to make.

---

## The queue — 2026-08-29

Worked top to bottom. Each item stands alone; the ordering is cost and dependency, not
importance. Sources: § A6 (feedback loop), `docs/OBSERVABILITY.md` (audit).

| # | item | why here | state |
|---|---|---|---|
| 1 | **Guard mismatch diagnosis** | `:quote_mismatch` covers a fabrication, an edition that punctuates differently, and a citation naming the first of two lines. Three layers, one verdict | ▸ done |
| 2 | **Surface it** — `verify_citation`, `verify_report` | a diagnosis nobody reads is rule 60 again. NOT the reader: it renders passages and never verifies a quote, so it has no refusal surface | ▸ done |
| 3 | **`mix pramana.doctor`** | the state every session rediscovers with hand-written psql. Highest value per hour in the audit | ▸ done |
| 4 | **Oban failure handler** | ~10 lines. The stall that cost an afternoon was diagnosed with a print statement inside `perform` | ▸ done |
| 5 | **Domain telemetry, five boundaries** | bake, retrieval, guard, MCP call, acquisition. Free when unattached; the substrate for 7 | ▸ done |
| 6 | **Structured MCP errors** | nineteen hand-written strings across seventeen tools. A model cannot branch on prose | ▸ done |
| 7 | **Guard-refusal and caveat counters** | both signals are computed and discarded today (§ A6 items 1 and 3) | |
| 8 | **Self-supervised parallel recall** | 141,073 quotations and the curated parallel graph are free relevance judgements. Needs no users | |

**Ordering notes that are not obvious.** 3 before 5 because `doctor` needs no design
decisions and pays every session; 4 before 5 because it is ten lines and removes the worst
debugging experience this project has had; 7 after 5 because counters want somewhere to go.
8 is last because it is the largest and overlaps `evals/`, which needs a judgement about
duplication before it is worth building.

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

- **`/inventory` is a ten-second page load, and one field is the whole cost.** Found
  2026-08-29 while building `mix pramana.doctor`. `Inventory.snapshot/0` takes 9.8 s against
  ~300 ms for every coverage figure it reports combined; the difference is `chars`, which
  sums `length(body)` over 548 million characters and forces Postgres to detoast every text.
  The fix is a stored `char_count` on `texts`, set at load time — a migration, a backfill and
  a normalizer change, which is why it is not bolted onto the diagnostic that found it.
  `doctor` reads the total from the recorded bake instead.

- **Restore coverage to 85 / 93.** ▸ **ENFORCEMENT TURNED ON 2026-08-28**, and it exposed a
  15-point regression nobody could have seen.

  `docs/CHECKS.md` has always called a coverage regression a gate failure, and the ratchet
  was raised at real gates — pramana_web went 82 → 91 → 92 → 93 across four commits. Then
  `mix pramana.gate` became the way the suite is run, and **its test step was plain
  `mix test`**. With nothing enforcing it, coverage fell to **77.5%** while `mix.exs` went
  on recording 93.

  The gate now runs `mix test --cover`, and the thresholds are reset to what is true (83,
  81) so that they can fail. Two tools were tested up from nothing in the same change —
  `GetPerson` 9.5% → 100%, `GetGlosses` 31.3% → 100%, both of them **shipped tools with no
  test**, which is rule 60 met in the registry and missed in the suite.

  **What is left, and it is the Phase 8 reader**: `PassageLive` 54.6%, `WorkLive` 66.0%,
  `MCP.Server` 66.7%, `ReaderComponents` 70.0%, `SurveyLive` 78.6%, `SearchLive` 83.0%.
  Restoring 93 means LiveView tests for five screens. **85 and 93 remain the targets**; the
  reset is recorded here rather than forgotten, because the point of a ratchet is that a
  number nobody can defend is worse than a lower one that everybody must.

- **The gate cost/coverage question is settled for now** (20m52s), but if it creeps back
  above ~1h, revisit — and do **not** resolve it by lowering the gate's depth, which makes
  the number meaningless.
- ~~**Commentary lemma-and-gloss (科文) parsing** → root↔commentary alignment. Phase 6,
  untouched, deterministic, a real differentiator.~~ **▸ SHIPPED 2026-08-27.**
  `commentary_alignments`, `Pramana.Commentary`, `mix pramana.commentary.align`. **27,254
  lemma alignments over 43 pairs, attaching commentary to 20,954 distinct root lines.**

  The rule is uniqueness, not similarity: a lemma anchors where its 8-character window
  occurs *exactly once* in the root. Measured against roots the same commentaries do not
  explain — 70–78% of root lines carry an anchor vs 0.5–1.9%, and 88–95% of consecutive
  anchors move forward through the root vs ~50%, which is chance.

  **The obvious gate was scale-sensitive and was nearly shipped.** Root-coverage% puts the
  denominator on the wrong object: T1742 quotes T0278 at density 69.2 and 82.4% forward
  order while covering **0.3%** of it, below what unrelated pairs score. The gate is spans
  per 10k characters of the *commentary*.

  **The floor was then mis-calibrated, and re-measuring caught it.** 25 was chosen against
  a 40-pair null set with p90 10.8. At 120 null pairs the observed maximum is **28.4**, and
  25 admits three of them. The floor is **30** — the lowest value rejecting all 120 — which
  costs three asserted pairs. A threshold calibrated against a thin tail is calibrated
  against nothing.

  **▸ BOTH NEW CAPABILITIES ARE UNDER THE EVAL HARNESS — 2026-08-27.** Their numbers were
measured in scratch scripts, which is the "vibes" invariant #6 exists to forbid. Two case
types now carry them:

    rendering   40 cases   70.0%   mean rank 1.68
    gloss       32 cases  100.0%   regression detector, NOT a quality measurement

**The rendering set was nearly worthless and was rebuilt.** The first derivation kept a
phrase only if `Translations.search/2` already returned its anchor — a gold set selected by
the thing it measures, which would report 100% forever and could detect a regression but
never a weakness. It now takes ten words from the middle of a rendering by a property of
the *text*, with no reference to what any search does with them, and 12 of 40 miss. Every
miss is a formulaic phrase that matched a different line better, which is the answer a
useful benchmark gives.

**The gloss set cannot be rebuilt that way, and says so on every case.** No mechanical
ground truth exists for which commentary explains which line — that is a scholar's
judgement the corpus does not record — so the cases come from the alignment's own output.
100% means *the alignment still says what it said*, never *the alignment is right*. It will
catch a normalizer change that shifts offsets or a re-bake that drops a pair. What can
speak to correctness, and did, is the null set: 0 of 120 unrelated pairs cleared the floor.

**And the full gate is unchanged** — 1,400 cases, 93.1%, **+0 on every row**, same index so
the noise floor is 1. The commentary table, the translation index and the provenance change
touched nothing the retrievers do.

**Still open, and now visible:** 47 pairs align nothing. Some paraphrase rather than
  quote, which this method cannot see and which is where an LLM layer earns its place —
  labelled `method: "llm"`, which the table already has a column and a CHECK for.
- **▸ DIAGNOSED 2026-08-27 — `retrieval/chinese`'s stubborn misses.** Now 9 after X, and
  two unrelated causes. Seven are X displacement (commentaries quoting a formula, X holds
  6–8 of the top ten). **Two are the original stubborn ones and both return a CORRECT
  answer the gold set did not ask for**: def-062 finds 「云何為一法？所謂念法」 in the
  Ekottarika Āgama at rank 3 while the case pins 本事經; def-082 finds 「云何為十一？所謂
  阿練若」 in the same work and fascicle, a page from the pinned line. These are
  enumerative formulae that recur by construction, so there is no single passage to pin
  and **no ranking change can win them**. `retrieval/chinese` therefore has a ceiling
  below 100% that is not the system's fault.

  **A decision is needed and it is not mine.** `expect_urns` is a list, so widening the
  two cases is one line — but widening a gold case makes a number go up, which is
  shape-identical to explaining away a regression. Today's absence cases were corrected
  because an ingest falsified their stated premise; these are valid but narrow, which is a
  judgement about what the eval should measure.
- ~~**`priv/embed` sidecar** still owns Tibetan `botok`, which nothing uses.~~ **▸ DONE
  2026-08-27 — there was nothing to delete.** No Python file imports `botok` and no Elixir
  calls it; the dependency was never taken. What existed was four documents describing it,
  `CLAUDE.md` among them, which is the one a new session treats as binding. Corrected
  there, in `docs/ELIXIR.md`, `docs/DEV_ENV.md` and STATUS's open questions.

## Rejected, with evidence — do not redo

| tried | verdict |
|---|---|
| `hnsw.ef_search` tracking the row limit | **Zero change**, +5% cost. Subsumed by the iterative scan. Live again only if `iterative_scan` is disabled. |
| Global fusion depth 120 | ~4x cost for +7 cases. Superseded by **per-arm depth** — the gain was entirely semantic, the cost almost entirely lexical. |
| `balance: :tradition` round-robin | Moved neither tradition's rate and made answered-from-any-canon *worse*. Survives opt-in. |
| Tibetan LoRA | Every proxy said it worked; the gold set said 0%. See *Why every proxy lied*. |
| Doc-translation stage B (~$260–770) | Superseded by query translation, which is free and scored higher. |
| **A gap statistic (top1 − top10) to detect "no answer"** | **No separation.** 6 of 8 unanswerable queries have gaps inside the answerable range; `photosynthesis in C4 plants` spreads wider than 13 of 20 answerable Chinese ones. Measured on 48 queries, 2026-08-27. |
| **An English→Pāli→Chinese bridge for `topical/chinese`** | **1 of 12.** Walking `Translations.search` → the Pāli anchor → `text_parallels` → a Chinese passage reaches the expected term once. It fails at the PARALLELS step, not the term step: 11 of 12 questions land on Pāli works with no openable Chinese parallel at all. Measured 2026-08-28. |
| **A hard similarity threshold for refusal** | **~45 retrieval cases to gain 1 absence case.** 0.75 is the lowest cut admitting no unanswerable query and it refuses 10% of answerable ones; the scale is per-language, so one cut-off fights two distributions. Reported instead. |
