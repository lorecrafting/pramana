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

Last reviewed: **2026-08-27** — A shipped. **B is done through the seventh CBETA
collection: 10 of 26 held, every text chunked and embedded, the reader at five screens.**

---

## Where the product stands

| | |
|---|---|
| corpus | **17,061 texts · 12,041,579 segments** · 3 traditions · 989,881 vectors |
| CBETA | **10 collections of 26** — T 2,471 · X 1,230 · J 285 · L 21 · P 13 · K 9 · A 9 · U 2 · S 2 · M 1 — 4,068 files locked |
| vector coverage | **100% of texts chunked, 100% of chunks embedded** — the 38% unreachable that `reachable_percent` exposed on 2026-08-26 is closed |
| reader | five LiveView screens — search `/`, **inventory `/inventory`**, survey `/survey`, passage `/passage`, work `/works/:id` |
| work relations | 90 `comments_on` · 82 `parallel_of` (41 pairs) |
| commentary alignment | **27,254 lemmas over 43 pairs**, attaching commentary to **20,954 root lines** — deterministic, no model |
| public exposure | **213,932 rows servable** · 34,697 forbidden by licence · 9,841 withheld pending a publication record (`mix pramana.public.check`) |
| eval | **93.1%** over 1,400 cases (`evals/baseline.json`, re-baselined 2026-08-27 over the seven editions) — 0 stale, 0 errored |
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

By that definition the *retrieval substrate* is close, and **a surface a human can use
now exists** — five screens, one of which exists to say what the corpus does *not* hold.
What is still thin is **coverage** (10 CBETA collections of 26, and Taishō 56–84 needs a
human to send an email) and **the deterministic enrichment that differentiates this
project** (#22 and A done, #23 unblocked but unstarted, commentary alignment untouched).

**The last of those is now the real gap.** Coverage has moved a long way in three days and
the reader went from nothing to five screens; root↔commentary alignment has not moved at
all, and it is the one item on this list that no general-purpose search tool will ever
produce for you.

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
cases. The mechanism is **genre overlap with the gold set**, not volume, so the remaining
23 collections sort into three groups that behave differently and should be taken in this
order:

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

**2. Genres the corpus does not contain at all — additive, non-competing.**

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

**This is the collection to take deliberately, not casually.** It competes with the Āgama
material head-on — the same discourses in Chinese, which is precisely the overlap that
cost X four cases — so it should land with a gate run of its own rather than folded into a
batch. The payoff is a three-way comparison nothing else offers: the Pāli, the Chinese
Āgama translated from a different Indic lineage, and a modern Chinese rendering of the
Pāli itself. `Compare.versions/2` and the parallel data are already shaped for it.

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

**Still to do before a demo is servable:** the public corpus has no chunks and no vectors,
so it is lexical-only today. Chunking is cheap; embedding 1.8M segments is a GPU spend and
a separate decision.

**Scope guard.** Phase 8 is a *renderer* over an API that already returns spans, URNs and
offsets. If it starts needing new domain logic, that is a signal the API is missing
something — fix the API, not the view.

### F. `topical/chinese` is still 0%

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
| **A hard similarity threshold for refusal** | **~45 retrieval cases to gain 1 absence case.** 0.75 is the lowest cut admitting no unanswerable query and it refuses 10% of answerable ones; the scale is per-language, so one cut-off fights two distributions. Reported instead. |
