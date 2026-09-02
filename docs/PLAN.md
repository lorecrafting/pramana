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

## Start here — session of 2026-08-31

Previous session ended clean at **81aa830**. This one shipped **§ E1's first slice** — the
Chinese canon has an English layer for the first time. Read § E1 before picking anything
up; the short version is that it works, it is 54 sūtras of 4,263 works, and it moved no
corpus-wide number.

**Do these in order.** Items 2, 3 and 4 of the previous list all shipped on 2026-09-02 —
translator fingerprinting, L4 and L3 — leaving E1 alone at the top, where it needs a
decision rather than code.

1. **§ E1, the increment that can actually compete.** 3,354 renderings is 191 chunk
   vectors against 55,135 over the Pāli, and an English question asked of the whole corpus
   is answered by the Pāli every time. The pipeline, the anchoring, the licence question
   and both instruments now exist; **coverage is the only thing missing**, and there are
   exactly two routes to it: a licence conversation (BDK English Tripiṭaka) or
   glossary-pinned generation over a source anchor (`docs/TRANSLATION.md`, invariant #8).
   **Pick one and size it before building** — anything that does not reach a substantial
   fraction of 4,263 works will land where this slice did.
2. ~~**Translator fingerprinting**~~ ▸ **SHIPPED 2026-09-02** — `Translators.attested/3`
   and the `compare_translators` MCP tool. 601 shared Sanskrit headwords between
   Kumārajīva and Dharmarakṣa, **126 agreed and 475 diverged**. Phase 6's exit question,
   answered from a philologist rather than from n-gram rates.
3. ~~**L4 — cross-scheme URN resolution**~~ ▸ **SHIPPED 2026-09-02** — `Pramana.Citation`.
   The Taishō as an article prints it, and SuttaCentral segment ids. § L4 below.
4. ~~**L3 — answer-time repair and a trust vocabulary**~~ ▸ **SHIPPED 2026-09-02** —
   `Pramana.Repair`, five states. § L3 below.

~~L5 — the checker screen.~~ ▸ **SHIPPED 2026-08-31**, `/check`. See § L5.
~~#15 — the Tengyur's volume walk.~~ ▸ **RESOLVED 2026-09-01 by deleting the walk**, which
measured 15–20× slower than the fallback it existed to avoid. Rule 70.

**What changed on 2026-08-31 that is not obvious from the code.**

- **Patton's Āgama English was already here and was being thrown away.** 54 CC0 files,
  hashed into the `sc-translations` lockfile entry since #39, dropped at every ingest as
  `no_such_anchor` — the same counter the Pāli's legitimate elisions land in, so the loss
  read as noise. **Check what a skip counter is actually counting.**
- **Two of the architecture review's five audits were already greps**, so they are now a
  test that runs on every push — `Architecture.BoundariesTest`, with an allowlist per rule
  because the boundaries are expected to move. Each rule was proved to discriminate by
  breaking it on purpose. **The other three, and "has this stopped being the thing it was
  designed to be", are still owed by a person** and both `docs/CHECKS.md` and the gate's
  closing summary say so.
- **A prefix test on a URN is a parser** (rule 68). `Chunk.Vectors` excluded every
  range-anchored CBETA rendering — 2,089 of the first 3,354 — because CBETA puts the juan
  between the work and the `@`. Silent; the only symptom was a vector count nobody had an
  expectation for.
- **A source need not be stored.** `sc-lzh` is read, matched against CBETA, and discarded;
  what is kept is a Taishō address. Registered and pinned regardless — invariant #3 is
  about reproducing a bake, not about what ends up in `texts`.
- **A CBETA "work" is a whole Āgama**, so "2 of 4,263 works have English" and "54 sūtras
  have English" are the same fact and the second is the honest one. Any per-work ratio over
  CBETA needs this said beside it.

**What changed on 2026-08-30.**

- **The language barrier was never the problem.** English→Pāli/Tibetan retrieval is 93.8%;
  cross-lingual *paraphrase* is 0.4%. § F's headline claim is withdrawn, MITRA-E is not
  indicated, and the term table survives only as a **concept layer**, not a retrieval fix.
- **452 of 510 works in T2185–T2700 carried the wrong 部**, Nichiren's 立正安國論 among them,
  caught from SAT metadata before any text was fetched. Argument for metadata-before-text.
- **`--seed` never worked** in two separate ways, both fixed and both proven.
- **"547 works" was arithmetic, not a count.** It is at least 541.

**Do not redo — all recorded with evidence in § "Rejected, with evidence".** Concurrency in
`mix pramana.evals` (moved two cases for 1.19x). Postgres tuning (no measurable gain, prime
suspect in swap thrashing). MITRA-E adoption (the embedder is not the bottleneck).
**And do not re-acquire Patton's Āgama English** — it is ingested; § E1 records what it
did and did not do.

**Parked, needing a human rather than code.** SAT phase 2 — the ~4,200-fascicle text fetch —
is built and unstarted. `docs/SOURCES.md` forbids scraping the reader on reproducibility
grounds, and the 2026-08-15 letter promised not to. The follow-up is drafted for mid-September
in `docs/sat-request-email.md`. **Overruling that is a decision to record in the doc, not to
imply in a commit.**

---

## Where the product stands

| | |
|---|---|
| corpus | **17,281 texts · 12,586,964 segments** · 3 traditions · **1,037,455 vectors** |
| CBETA | **16 collections of 26** — T 2,471 · X 1,230 · J 285 · **I 101** · N 38 · **GA 51** · **F 27** · L 21 · P 13 · K 9 · A 9 · U 2 · S 2 · **GB 2** · M 1 · **ZS 1** — 4,340 files locked |
| vector coverage | **100% of texts chunked, 100% of chunks embedded** — the 38% unreachable that `reachable_percent` exposed on 2026-08-26 is closed |
| MCP surface | **17 read-only tools** — `search_translations`, `get_glosses`, `get_works_by_person` and `get_person` all added 2026-08-28 |
| English over Chinese | **3,354 renderings** over **2 of 4,263** CBETA works (54 Āgama sūtras) — new 2026-08-31, § E1 |
| reader | **six** LiveView screens — search `/`, inventory `/inventory`, survey `/survey`, passage `/passage`, work `/works/:id`, **check `/check`** |
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
| full gate | **32m22s** — evals 21m14s at 1.2 cases/s, integrity 11m02s, `verify --all` 7m09s over every segment (2026-08-31) |
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

**Then the line moved, deliberately.** v1 as *written* is met; v1 as *scoped* also includes
four things added by decision after the definition was — and **all four have now shipped**:

| added to v1 | state |
|---|---|
| lineage chains | ✅ `Authority.lineage/1`, `teacher_chain/2`, exposed on `get_person` |
| Wikidata q-ids | ✅ `external_ids` on `get_person`; 1,446 of the linked works' people carry one |
| place authority | ✅ § A3, 2026-08-28 — 59,335 places, historical region as well as modern path |
| Phase 7 report verifier | ✅ § H, 2026-08-28 — `verify_report`, and it is a verifier, not an agent |

That the line moved at all was a scope decision, not a slip, and it is recorded here rather
than by editing the sentence above — because a definition that quietly grows to match what
got built measures nothing. The clause table stands as the record of what the original
definition asked for and when it was answered.

**The bottom two rows read "◐ designed, unbuilt" until 2026-08-31**, four days after §§ A3
and H were marked ▸ DONE further down this same file, and `docs/STATUS.md` carried the same
claim. Nothing was wrong with the code; a summary table went stale above the sections it
summarises. **When you mark a section done, grep this file for the other place it is
counted** — rule 41, applied to prose.

**What remains and is NOT v1.** Taishō 56–84 waits on a reply to the request sent 2026-08-15, and the
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

`pipeline_version` went to **4** at this point, 2026-08-26 — it is 5 today, see § A4.
`config/dev.exs`'s pool timeout went 120s → 300s: assembling
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

### F. `topical/chinese` is still 0% — now measured over 496 cases rather than 12

**▸ MEASURED 2026-08-29.** The row has been 0% of **twelve** gold cases since it was first
scored, and this plan has said the honest thing about that all along: *twelve cases cannot be
steered on, and one case is 8.3 points.* `mix pramana.recall --parallels` reads SuttaCentral's
curated Pāli↔Chinese parallels as what they are — **scholars' cross-lingual relevance
judgements** — and there are 10,493 of them with both ends in this bake.

**▸ THE NUMBERS BELOW ARE WITHDRAWN — 2026-08-29, the same day they were published.** Two
defects, found by trying to read the successes rather than the failures.

**1. `--seed` never worked, so nothing here was reproducible.** `setseed` seeds one Postgres
session and `Repo.query!` takes whatever connection the pool offers, so the seed and the
`ORDER BY random()` it was meant to seed ran in different sessions. Eight calls with one seed
drew eight different samples. Fixed by pinning both to a transaction; rule 67, and the reason
no test caught it is in there too.

What was published as one seeded measurement was three unseeded draws:

    mode hybrid, limit 100, PRAMANA_EMBEDDING=1     control      cross-lingual   ratio
    run 1 (published as § F)                     26/125  20.8%   2/496  0.4%     1.9%
    run 2                                        33/125  26.4%   2/499  0.4%     1.5%
    run 3                                        23/125  18.4%   1/499  0.2%     1.1%

**The ratio was quoted to two significant figures and it moved by 70% across draws.** The
control moved by eight points. "1.9% of achievable recall" and "the language barrier costs
98%" were one sample read as a constant.

**2. Work-level scoring overcredits — but the cross-lingual hits are real, and an earlier
version of this paragraph said otherwise.** One inspected hit *was* boilerplate: run 3's
single success matched `Ayampi attho vutto bhagavatā`, the stock Itivuttaka closing formula,
present in **114 segments across 113 texts**, at rank 50 and not on the parallel line. From
that one case this section concluded there was no positive evidence at all. **That was
generalising from one case — rule 16 — and it was wrong**, and it survived long enough to be
committed because the first line-level measurement returned `on line 0.0%`, which agreed with
it. That zero was itself a bug: parallels store *point* URNs and the semantic arm returns
*chunk ranges*, compared with `==`. Rule 62, twice over, in one afternoon.

Scored by char-range containment instead, and drawn twice — the second sample is
**independent**, because audit-queue #9 replaced `setseed` + `random()` with a hash ordering
and the same seed therefore selects different cases:

    seed 0.42, sample 500, mode hybrid, limit 100    found        on line
    A. setseed sampling
       control (same language)                    26/125 20.8%   11/125  8.8%
       cross-lingual                               2/497  0.4%    2/497  0.4%
    B. hash sampling, independent draw
       control (same language)                    36/125 28.8%    6/125  4.8%
       cross-lingual                               3/497  0.6%    2/497  0.4%

**Read the ratio, never the raw count.** Cross-lingual line-level recall is 2 cases in both
draws; the control moved 20.8% → 28.8% between them. At these rates a 500-case sample is a
coin, and the stable quantity is cross **relative to** same-language: 1.9% and 2.1%
work-level.

**What replicates is the mechanism, and that is the finding.** Across two independent
samples, six hits:

| | |
|---|---|
| **line-level, all Dhammapada verse** | `dhp331` r13 · `dhp68` r34 · `dhp206` r83 · `dhp223` r47 |
| **work-level only, all the same formula** | `iti95` r50 · `iti45` r26 |

Four of six cross-lingual successes are **short Dhammapada verses**, matched on the line the
curators pointed at. The other two are the **same stock Itivuttaka closing formula** —
`Ayampi attho vutto bhagavatā`, present in 114 segments across 113 texts — landing in the
right book by way of a phrase that appears in every sutta of the collection. One sample made
that look like an anecdote; two independent samples make it a pattern.

**The control is what work-level scoring flatters**, in both draws: 26 found / 11 on line,
then 36 found / 6 on line. So the achievable-recall yardstick was inflated two- to six-fold,
and the barrier costs less than the 98% first published — but the honest statement is a
range, not a figure.

**The caveat that stops this becoming the next overstatement:** `dhp331` is a 138-character
text. For a Dhammapada verse of five segments, "found the work" and "found the line" nearly
coincide, so line-level scoring only discriminates on long works — which is exactly where the
control's 15 work-only successes live. Read `on line` as the honest number for long works and
as near-tautological for short ones.

Recall here is work-level by design — `Recall`'s moduledoc argues for it, and for the
quotation probe it is right. Against *parallels* it lets boilerplate earn credit, and at a
rate of two in five hundred, one boilerplate match is the entire finding. The probe now
reports `on line` beside `found`, requiring the parallel's own target line.

**▸ AND THEN THE FRAMING ITSELF FELL — 2026-08-30. It is not the language barrier.**

`mix pramana.recall --renderings` runs the identical machinery against pairs that really are
**translations** of one another — the 241,409 human renderings, 30,653 bo→en from 84000 and
210,756 pli→en from SuttaCentral, each anchored to the line it renders. Same seed, same
sample size, same cap:

    task                                          work-level   on line
    cross-lingual, TRUE TRANSLATION                  93.8%      54.2%   <- pooled; see below
    same-language, discourse correspondence          28.8%       4.8%
    cross-lingual, discourse correspondence           0.6%       0.4%

**The `on line` figure here is pooled over two populations that score 79.0% and 8.5% on
it** — Pāli, whose anchors are one segment, and Tibetan, whose 84000 anchors are folios of
about seven. It is an average of the two and describes neither. Corrected 2026-08-31; see
§ E1 and rule 69. The **93.8%** work-level figure and everything this section concludes
from it stand: the claim was that language costs almost nothing when a translation exists
to anchor on, and both populations reach their work.

**An English query reaches Tibetan and Pāli source text 469 times in 500.** BGE-M3 crosses
the language barrier better than it handles *same-language* correspondence. So:

- **"The language barrier costs 98% of achievable recall" was wrong**, and it was this
  section's headline. Language costs almost nothing when a translation exists to anchor on.
- **MITRA-E is not indicated.** No 9B model, no rented GPU, no 3,584-dim migration, no Gemma
  licence question. The embedder was never the bottleneck. Audit L2 is closed by this.

**The precise reading is an interaction, and it is sharper than "task, not language".** If
language were simply free, cross-lingual correspondence would land near the same-language
28.8% instead of 0.4%. The two compound: with an exact translation the embedding space aligns
the languages; with a *paraphrase in another language* there is nothing tight enough, lexical
or semantic, to bridge on.

**Which cuts against the term table as a retrieval fix.** Where two discourses genuinely share
little content, no vocabulary bridge retrieves one from the other, and a large part of that
0.4% is probably irreducible — the probe may be asking an ill-posed question rather than
exposing a fixable weakness. **The term table survives on entirely different grounds**: the
concept layer of the bhūmi case above, where 不動地 = acalā = the eighth ground, which is
term-level equivalence for lookup and expansion rather than passage retrieval.

**And the real finding is elsewhere.** English reaches Pāli at 93.8% and Chinese at 0% for
one reason that has nothing to do with retrieval: **there are 210,756 English renderings over
the Pāli canon and zero over CBETA.** See § E1.

**The control is still the finding.** Retrieving a *paraphrase* is hard even inside one
language: a parallel records that two discourses correspond, not that they share words, so
roughly 20% is what this corpus and this cap can do on the task at all. That yardstick was
nearly thrown away — an earlier version of the probe called anything under 50% a broken run,
a floor picked from nothing rather than from a measured distribution.

**What it does not establish.** Hybrid fuses lexical and semantic, and lexical contributes
essentially nothing across scripts, so this is the semantic arm's number. It says nothing
about whether a corpus-derived term table would fix it — that hypothesis is unbuilt, has an
instrument to be judged against, and **two line-level observations to build on**.

### The worked example the term table has to satisfy — the bhūmis

*"What happens on the seventh bodhisattva bhūmi, what is the 7→8 breakthrough, and what do
the commentaries across the canons say about it?"* — a question a real reader asks, measured
against this bake on 2026-08-30.

**In Chinese it already works, and better than a ranked list would.** Exhaustive counts:

    第七地    634 segments /  205 works        遠行地   802 /  237   (the 7th bhūmi)
    第八地    845 segments /  235 works        不動地 1,161 /  329   (the 8th)
    歡喜地  1,053 segments /  371 works        十地  19,096 / 1,414

So *where is the 7→8 transition discussed most densely* has a real answer, `get_commentaries`
walks to the works that explain those texts, and `get_glosses` finds the commentary anchored
to **that line** by 科文 lemma. The survey also returns the coverage caveat unprompted — the
Shingon and Tendai commentary on the bhūmis is in Taishō 56–84 and absent here, so an empty
result is not silence.

**Across the canons it fails, and the reason is measurable rather than vague:**

    glossary entries with a Tibetan equivalent   55,807
                        Sanskrit                 41,253
                        Chinese                   1,105   <- 2%

`acala` has **seven glossary entries with Tibetan and not one with Chinese.** Nothing in this
system knows that **不動地 = acalā = the eighth bhūmi.** That is exactly why § F specifies a
table built *from CBETA*, not from 84000's Tibetan-oriented glossary — and the 2% is the
number behind that qualifier.

**So the term table is not only a retrieval fix, it is the missing CONCEPT layer**, and this
is the acceptance test for it:

1. 不動地, acalā, dūraṅgamā and their Tibetan equivalents resolve to one concept
2. a Chinese bhūmi query reaches the Tibetan and Pāli material
3. `get_glosses` on a 7→8 passage returns commentary from more than one canon

**Nothing here encodes that the bhūmis are ORDERED**, that 7→8 is a recognised turning point,
or that "look at the lower bhūmis" is a sensible next move. A model given the passages can
reason that out; the retrieval layer cannot suggest it, and a term table alone will not fix
it either. That is a separate piece — an ordered-concept layer — and it should not be
smuggled into the term table's scope.

**And L2 comes first.** If the true-parallel probe shows BGE-M3 retrieving actual
translations well and discourse correspondences badly, the cross-lingual score is a statement
about the *task* and the term table's value is the concept layer above rather than the recall
number. That changes what success looks like before a line of it is written.

**And they point somewhere specific, now on four observations rather than two.** Every
line-level cross-lingual hit this probe has ever produced is a **Dhammapada verse**: short,
terse, verse-form, dense in concrete shared vocabulary, where the Chinese 法句經 is a close
near-verbatim rendering rather than a paraphrase. **Nothing discursive has ever crossed.**

So a term table should be **tested first against verse with high concrete-noun density** —
the case where the two languages share nameable things — and its failure on prose should be
the expected result rather than a surprise. The corresponding warning: the Itivuttaka
formula crossed twice **without carrying any meaning**, so a term table evaluated on
work-level recall would score those as wins. Judge it on `on line`.

### F.1 The route that is closed

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
| 7 | **Guard-refusal and caveat counters** | both signals are computed and discarded today (§ A6 items 1 and 3) | ▸ done — as counters, not a stored log |
| 8 | **Self-supervised parallel recall** | 141,073 quotations and the curated parallel graph are free relevance judgements. Needs no users | ▸ done — 100.0% over 1,891 decided pairs |

**Ordering notes that are not obvious.** 3 before 5 because `doctor` needs no design
decisions and pays every session; 4 before 5 because it is ten lines and removes the worst
debugging experience this project has had; 7 after 5 because counters want somewhere to go.
8 is last because it is the largest and overlaps `evals/`, which needs a judgement about
duplication before it is worth building.

---

## The audit queue — 2026-08-29

Found by auditing outward from two defects in `mix pramana.recall`, on the principle that a
fix which does not sweep for the other instances is not finished (rule 41). Ordered by
blast radius, not by effort.

| # | item | why here | state |
|---|---|---|---|
| 1 | **§ F says the hits are an artifact — they are not** | committed wrong in a03785c. 2 of 3 inspected hits DO cover the parallel line; only `iti95` was boilerplate. Generalised from one case, which is rule 16 | ▸ in flight, lands with the seeded numbers |
| 2 | **`Corpus.context/2` rejects range URNs, and the guard depends on it** | `resolve/1` was fixed to accept ranges because a range is a legitimate citation; `context/2` still does an exact `s.urn ==` match, so `Guard.spans_boundary?` takes its `_ -> false` branch and reports **"does not span a line boundary"** for every range citation. A multi-line quote is exactly when that diagnosis matters. Reachable from MCP `get_passage`, the reader and the guard | ▸ **FIXED 2026-08-29** — two layers deep: `fetch_segment/1` rejected the range, and the window was split by `&1.urn != focus.urn`, which a range URN can never satisfy. Both now key off ordinals, which work for a point and a range alike. Three tests, and the range one fails against the old code |
| 3 | **`mix pramana.verify --sample` has no `--seed`** | `ORDER BY random()` with nothing seeding it, so two runs check different segments. And **`CLAUDE.md` asserts "a measurement task takes `--seed`"**, which is false for it — fix the code or fix the claim, but they cannot both stand | ▸ done — `--seed` added, and `Pramana.Sampling.seeded/2` extracted so the next task cannot reimplement rule 67's bug |
| 4 | **A live check for pool-dependent defects** | rule 67: the test suite pins one connection and structurally cannot see this class — `setseed`, `SET LOCAL`, advisory locks, temp tables, `LISTEN`. The instrument is `mix pramana.gate`, which runs against a real database | open |
| 5 | **Query-embedding cache across runs** | the seed works now, so the same sample is drawn every run and its embeddings could be reused. **Deferred deliberately**: a stale cache serves wrong vectors silently, so it needs keying on model identity, and it is only worth that risk if measurement shows embedding still dominates after #6 | deferred, pending measurement |
| 6 | **The probe was sequential against a serving built to batch** | `Nx.Serving` starts with `batch_timeout: 100` so concurrent callers share a forward pass; every caller was `Enum.map`, so a 625-case run embedded one query at a time on eight cores for an hour | ▸ done, pending verification |
| 8 | **`mix pramana.evals` is sequential too — the gate's 27-minute step** | `Evals` iterates its 1,472 cases with `Enum.map`, so the gate's largest step embeds one query at a time on eight cores, exactly as `recall` did. **Higher stakes than #6**: evals is the ratchet against `evals/baseline.json`, so a numeric change is a false regression or a hidden one. Same equivalence bar, applied harder | ▸ **REVERTED 2026-08-29 — see § "Rejected, with evidence".** Concurrent run scores retrieval **368/446 (82.5%)** against baseline **370/446 (83.0%)**, 0 stale, 0 errors. Two cases moved. Do not ship until isolated: the candidates are (a) concurrency, (b) the Postgres tuning — **not** via parallel plans, which was checked: `EXPLAIN` gives a byte-identical plain `Index Scan` on the HNSW index at both 2 and 4 workers, with no `Gather` node. The live mechanism is `work_mem` 4 MB → 16 MB, which can change hash-versus-sort and therefore tie-breaking, (c) a baseline recorded under conditions not yet confirmed identical. A `--concurrency 1` run over the same 446 cases is the discriminator. Separately, the obvious form of the fix would have reintroduced the 4h25m loss: `score_case/2` rescues and catches, but `async_stream` reports a task that dies anyway as `{:exit, _}`, which `fn {:ok, r} -> r end` turns into a run-killing `FunctionClauseError`. Handled explicitly |
| 9 | **`ORDER BY random()` is PLAN-dependent, so the seed is only reproducible per configuration** | `random()` is volatile and evaluated per row, so which value each row gets depends on the order rows reach it — a parallel scan or a changed plan draws a different sample from the same seed. Tuning can therefore re-roll a seeded figure — **though when the tuning in `docs/DEV_ENV.md` was applied on 2026-08-29 it did not**: the same seed drew a byte-identical sample either side of it. Predicted as a certainty, measured as a non-event; the fragility stands, the urgency does not. `ORDER BY md5(salt || id)` is a deterministic function of the row and is immune to plan and parallelism alike | ▸ **DONE 2026-08-29, and the fragility was real.** Demonstrated across five planner configurations: the old ordering is stable under three and **changes under `enable_indexscan=off`**; the hash ordering is identical under all five. The earlier note that "the predicted re-roll did not happen" was true of that particular tuning and wrong as a general claim — the tuning was simply too small a plan change. **Keyed on the primary key**, after a first attempt keyed `source_urn ‖ target_urn`, which has 24,099 distinct values over 407,176 rows and left 94% of the table tied |
| 10 | **`verify` loads all 17,281 bodies at once — ~548M characters** | `scope/1` is `from(t in Text, preload: [:work])` with no `select`, so every body is resident before the first check runs, on a 16 GB box. This is the **fifth** call site of the problem that the `texts.body` work fixed in four — rule 41. It also caps how far #6-style concurrency can be pushed here | ▸ **done, and the first fix was worse than the bug.** Per-text loading bounded memory and cost 17,281 round-trips, taking `--all` to 46m48s. Chunked loading (200/query, 87 queries) restored bulk reads at bounded memory, and per-source iteration did the rest |
| 11 | **`mix pramana.verify --all` was SIGTERMed twice, and the gate depends on it** | died at 7 min and at 3.5 min with `SIGTERM received - shutting down` and no jetsam record. Per-source runs of the same work succeed easily — sc 4.9 s, cbeta 45 s — which points at `--all` holding all 17,281 bodies at once (#10) rather than at the checking itself. **Both kills were after the `shared_buffers` 128 MB → 2 GB tuning**, and there is no pre-tuning `--all` run in this session to compare, so the tuning is a suspect and not a convicted one. Every source passed at FULL coverage individually — sc 4.5 s, derge 3m52s, tengyur 1m02s, cbeta 1m14s over 10,788,972 segments — so only `--all` dies, which points at the materialised bodies rather than the checking | ▸ **FIXED and confirmed 2026-08-29** — `--all` now iterates sources internally and completes in **6m03s** over every one of 12,586,964 segments, against a ~26 min baseline and the 46m48s single-pass version. Sources come from the database, so coverage is 17,281 texts and not the 17,280 a hand-written loop checked |
| 12 | **`mix pramana.verify` prints its coverage without a denominator** | it reports `segments checked: 2,487,559` and `verify OK`, and without `--all` that is **23% of cbeta's 10,788,972** — the default samples 1,000 segments per text and nothing in the output says so. A reader sees a green check over 4,263 texts and reasonably concludes the corpus was verified. This is rules 22, 44 and 54 — *publish the gap, not just the total* — inside the gate's own verification step, and it nearly produced a fabricated 4.5× speedup here by comparing a sampled run against a full baseline | ▸ **done and confirmed** — prints `12586964 of 12586964 (every segment)`, or `409790 of 444673 (92.2% — SAMPLED)` when it is not |
| 13 | **Degé Kangyur's verify time is per-text body work — three wrong hypotheses first** | 1,195 texts / 461,302 segments in **3m52s**, against cbeta's 10,788,972 segments in **1m14s** — 1,988 seg/s versus 145,800. — but that framing is **wrong, and it was mine**. `started` is set *before* `editions(...)`, so the one-time volume walk is inside the measured elapsed, and `volumes_for(root, Derge)` eagerly `File.read!`s all 103 Kangyur volumes before parsing them. So the headline "73× slower per segment" divides a fixed startup cost by 1,195 texts and prints it as a per-text rate. ▸ **ANSWERED 2026-08-29, and every hypothesis along the way was wrong.** Measured: `--sample 1` checks 0.3% of the segments and still takes **3m11s of 3m52s**; the edition walk is **10.4s**; the Kangyur edition derives all 1,195 works successfully, so there is no silent fallback. The time is **per-text body work** — sha256 over each body plus the re-render comparison — across 1,195 large Tibetan texts, which *is* the byte-compare guarantee and not a defect. The four dead hypotheses, in order: missing volume walk, bad root path, fixed cost misreported as a rate (82% of it), silent fallback. **The reporting fix stands** — the walk is now timed and printed separately — but there is nothing here to optimise without weakening the check that caught the phantom lines in toh4100 and toh4150 | ▸ done |
| 17 | **`mix pramana.integrity` is now the gate's second-largest step and has never been profiled** | 11m02s on 2026-08-31, against `docs/CHECKS.md`'s recorded **13m18s** — so it has not regressed. It is simply that `verify --all` went ~26m → 6-7m in the 2026-08-29 audit and integrity did not move, and nobody has looked at it since it stopped being the small one. **Not urgent and not a defect**; noted so that the next person optimising the gate starts from the largest step rather than the most familiar one, which is rule 40 | open |
| 18 | ▸ **FIXED 2026-09-02** — projected from a trailing window instead of the running average. The window is the gap between ticks, which is noisy and tracks what the run is actually doing; a smooth estimate that is wrong by 3x is worse. Originally: **`mix pramana.evals` prints an ETA that is wrong by 3x, and wrongly in the flattering direction** | It divides total elapsed by cases completed. The 1,472 cases are two populations ~175x apart in cost: the ~930 that touch no embedder finished in **12 seconds**, about 13 ms each; the ~540 after them embed a query and run hybrid search at ~2.3 s. At 1,310 cases the printed estimate said `~2m01s left` and the measured marginal rate said ~6 minutes; it took 4m47s. An average over unlike populations predicts neither — **rule 69, in this project's own tooling** — and the fix is to estimate from a trailing window rather than the total. A few lines | open |
| 14 | ▸ **FIXED 2026-09-02.** `summarize/2` had carried per-case outcomes since the incident; **`to_map/1` did not**, so the baseline on disk still held rates only and the ratchet could still say *something regressed* and never *what*. `to_map/1` now emits `cases` keyed by id, and the gate diffs them — including **on a pass**, because equal rates are consistent with one case flipping to a hit and another to a miss, which is the substitution audit item 7 names and had no way to check. The next `--gate` run records the detail; a baseline without it reports "no per-case detail" rather than flagging every case as new. Originally: **`evals/baseline.json` records no per-case detail, so a regression cannot be localised** | keys are `overall`, `by_type`, `by_type_tradition`, `stale`, `errors`, `total` — rates only. When the concurrent run scored retrieval 368 against the baseline's 370 on 2026-08-29, **there was no way to identify which two cases moved**, and the only route to an answer was re-running the whole 446-case subset for ~20 minutes. A list of case ids and outcomes would have made it a diff. The ratchet can say *something regressed* and never *what* | open |
| 15 | **The Tengyur's precomputed volume walk fails silently, and has been failing** — ▸ **RESOLVED 2026-09-01 BY DELETING THE WALK.** The bug was real and one line: `volumes_for/2` returned `{volume, path}` for the Tengyur where `Edition.volume()` is `{pos_integer(), binary() | Enumerable.t()}`, so the walk parsed a *file path string* as Tibetan, found no lines and halted in 2 ms without opening a file. Two clauses of one function returning two shapes. **But fixing it made verification 15–20× SLOWER**, measured both sources both ways on one machine, all green and byte-identical: derge 3m16s walked against 13s per-work, derge-tengyur 20m30s against 1m01s. The mechanism is memory, not parsing — the walk holds every IR in the edition (891,169 Tengyur lines, 3.7 GB against 830 MB) and achieved parallelism halves, 181% CPU against 373%, because GC dominates; the fallback re-parses each volume ~16× inside `Task.async_stream` workers whose garbage dies with the task. The ~90-minute figure that justified the walk was true when written and stopped being true when audit #10 removed `texts.body` and made loading chunked — **nobody re-measured the optimisation those changes had obsoleted, which is rule 47**. Sixth instance of #10's own pattern. `Edition.reduce/4` is untouched and still the ingest's walk, where cross-volume threading has no per-work alternative | ▸ done |
| ~~15~~ | ~~original entry, kept for the reasoning it records~~ | `derive_edition("derge-tengyur")` returns `{:error, {:empty_volume, 1}}` in 2 ms, and `derive_edition/1` swallows it with `_ -> %{}`, so **all 3,380 Tengyur texts take the per-work fallback**. That walk exists precisely because verifying work-by-work parsed 212 volumes ~16 times each and took ~90 minutes — *"97% of the whole gate"*. It is not costing that today (Tengyur verifies in 1m02s), which is why nobody noticed, but the optimisation is dead and the failure is invisible by construction. **Do not "fix" the fallback — find why `volumes_at/1` reports an empty first volume**, and make the swallow report rather than degrade silently (rule 17: anything optional degrades quietly) | open |
| 16 | **The Taishō 部 table mislabelled 452 of 510 works in T2185–T2700** | ▸ **FIXED 2026-08-30, before the text ever arrived.** One row covered the whole range as 續經疏部 with `text_role: "commentary"`. SAT's 541 IIIF manifests each carry their own 分類, and the range is **four** divisions: 續經疏部 T2185–2245 (58), 續律疏部・續論疏部 T2246–2295 (50), **續諸宗部 T2296–2700 (402)**, 悉曇部 T2701–2731 (31). The 402 are the doctrinal writings of the Japanese schools — compositions, not commentary on anything. **T2688 is 立正安國論, Nichiren's *Risshō Ankoku Ron*, and the table filed it as a sub-commentary**; a test asserted that and passed. Nothing could have caught it: `provenance --check` validates that a number range sits inside its volume range, which one wrong row spanning 56–83 satisfies, and none of these works is loaded so `verify` and `integrity` were green over it — the § A4 pattern exactly. Five tests pinned the wrong data and were corrected with it | ▸ done |
| 7 | **"Retrieval is deterministic" — what the evidence actually supports** | ▸ **stated properly 2026-08-29, not proven.** Two independent observations: three queries returned bit-identical result lists across separate VM invocations, and a 446-case retrieval run reproduced a previously recorded baseline's rate **exactly** (370/446). **Neither establishes per-case determinism** — equal rates are consistent with one case flipping to a hit and another to a miss, which is precisely the substitution a rate cannot see. The claim that is safe is *stable in aggregate over 446 cases and bit-identical on the three inspected*. Per-case proof needs a baseline carrying case detail, which #14 now produces going forward but which `evals/baseline.json` did not record when it was written | ▸ done — claim narrowed to its evidence |

**What #6 must prove before it counts as done**, because a speedup that changes the numbers
is not a speedup: batching alters float accumulation, so a batched embedding need not be
bit-identical to a solo one, and near-tie rankings would flip. The check is a same-seed run
at `concurrency: 1` against one at `concurrency: 6`, compared case by case — not a timing.

---

## E1. An English layer over the Chinese canon — the top priority, 2026-08-30

### ▸ FIRST SLICE SHIPPED 2026-08-31 — 3,354 renderings, and `topical/chinese` did not move

`mix pramana.sc.chinese` and `Pramana.Sc.Lzh`. **The Chinese canon has an English layer
for the first time**, and the honest headline is that it covers **54 sūtras — 2 of 4,263
CBETA works** — and did not move the measurement it was built to move.

**It was already on disk.** Charles Patton's CC0 English of the Chinese Saṃyukta and
Madhyama Āgamas — 54 files — has been hashed into the `sc-translations` lockfile entry
since #39 and **discarded at every ingest**, because its anchors name SuttaCentral
addresses (`sa379:2.2`) while this corpus holds those Āgamas as CBETA.
`mix pramana.sc.translations` filed every segment under `no_such_anchor`, which is also
where the Pāli's legitimate elisions land, so the loss read as ordinary noise. The
sparse checkout did not fetch `root/lzh` at all, so the Chinese they would have been
joined through was never acquired either.

**What it does.** bilara's Chinese is used as a bridge and never stored, so the anchor
kept is a **Taishō** page-and-line address a reader can check against a print edition.
Both editions print the sutta number — CBETA writes `（三七九）`, and T0099's 1,350
markers and T0026's 222 are each unique — so the number gives a window and every segment
is matched inside it, in order and forward only. A number pointing at the wrong sutta
would match nothing and drop the work whole. Variant Han forms are folded and editorial
punctuation stripped **for the comparison only**, because `root/lzh/sct` is SAT-derived
and this corpus's Āgamas are CBETA.

| | |
|---|---|
| works anchored | **64** of 64 in `sa`/`ma` (208 of 272 lzh files are collections with no anchoring) |
| anchors exact | **3,758 — 86.9%** |
| anchors interpolated | 567 — 13.1%, each bounded by neighbours that matched, and stamped `anchor_method` |
| how wide a bounded anchor is | of the rows that span more than one line, interpolated ones average **2.49 printed lines, 8 at worst**, against 2.13 for exact ones. Not "somewhere in this sutta" |
| segments dropped | **2** |
| renderings stored | **3,354**, all CC0, `translator_id: patton`, over T0099 and T0026 |
| chunk translation vectors | **191**, embedded |

**The guarantee held, and it is checkable.** If a sutta number ever pointed at the wrong
passage, that work's exact-match rate would collapse to near zero — two unrelated sutras do
not agree character for character. Across all 64 works the **minimum is 57.1%** (sa162) and
the median 85.0%, with sa34 at 100%. No work is anywhere near the signature of a
mis-located window.

**And it did not move `topical/chinese`, which stays 0 of 12.** `--only topical` scores
**51.0%** against a baseline of 51.0%, every tradition row identical — chinese-native
91.7%, pali 75.0%, tibetan 22.2%. **Nothing regressed and nothing improved.** The reason
is arithmetic rather than mechanism: those cases search the whole corpus with no
tradition filter, so an English question is answered by **55,135** English vectors over
the Pāli against **191** over the Chinese.

**Isolated from that competition it is measurable — and measuring it broke the
instrument.** `mix pramana.recall --renderings --to <namespace>`, 200 pairs each, seed
0.42, hybrid, limit 100, the same probe pointed at one canon at a time. The third row was
run as a control and is the reason none of these three numbers can be compared with each
other:

| canon | mean anchor width | found the work | on the line |
|---|---|---|---|
| `sc.ms` (Pāli) | **1.00 segment** | 178/200 · 89.0% | 158/200 · 79.0% |
| `cbeta.T` (Chinese) | **2.01 segments** | 126/200 · 63.0% | 74/200 · 37.0% |
| `derge.D` (Tibetan) | **6.94 segments** | 199/200 · 99.5% | **17/200 · 8.5%** |

**Tibetan finds the work 99.5% of the time and the line 8.5% of the time**, and that is
not a fact about Tibetan retrieval. `Recall.covers?/2` scores a hit "on the line" when the
retrieved span **contains the whole anchor**, and 84000's anchors are folio-wide — about
seven Degé lines — so the chunk that matched is frequently smaller than the thing it has
to contain. The on-line column is inversely ordered by anchor width across all three
canons, perfectly, because that is what the predicate measures. Rule 69.

**So neither column supports a cross-canon comparison, and they fail in opposite
directions.** Work-level flatters Chinese — there are two CBETA works with any English, so
"found the work" means landing anywhere in a 32,000-segment text, against 8,442 Pāli works.
On-line penalises Chinese — its anchors are twice the width of the Pāli's, because
SuttaCentral segments a sentence where the Taishō breaks at seventeen characters.

**E1's second success criterion — "`--renderings` scores English→Chinese near the 93.8% it
already reaches for Pāli/Tibetan" — turns out not to be answerable as written**, because
93.8% was a pooled figure over two populations that score 79.0% and 8.5% on the same
column. What can be said: English reaches the Taishō, at 63.0% and 37.0% on a probe whose
two columns bracket the truth, and the corpus-wide measurement did not move.

**The mechanism does work, and a control is what establishes how much.** Scoped to
`source_id: cbeta`, "How is mindfulness of breathing taught?" returns the SĀ ānāpāna
sutras at ranks 1–4. It would have been easy — and wrong — to publish that as the
result: the nearest CBETA vectors to that query are `parallel_gloss/en/sujato` at
d=0.143 and 0.153, machinery that **predates this change**, with Patton's own vector
third at d=0.224. Rule 62. The new layer contributes and is not what produced the
top hit.

**What this says about the rest of E1.** The pipeline, the anchoring and the two
instruments now exist and the licence question is settled for this source. What does not
exist is coverage: 54 sūtras inside 2 of 4,263 works, and no route to the other 4,261 that
does not go through either a licence conversation (BDK) or generation. **A slice this size cannot
move a corpus-wide measurement, and that is the finding to carry forward** — the next
increment has to be large enough to compete, not merely non-zero.

**▸ THE GAP IS CLOSED, 2026-09-02, and the decision is recorded: if you write the
lockfile, re-record the bake — uniformly, no exceptions.** `bake_id` is a hash of
`sources.lock.json`, so writing it changes the id by definition, and a bake row that no
longer describes its inputs stamps every response with an id for a corpus that does not
exist. All **eleven** lockfile-writing tasks now record.

The case I had flagged as needing a judgement — `acquire_all` and `derge.images`, which
acquire without ingesting — resolves the same way: the bake's claim is about its *inputs*,
and the inputs changed even though nothing new is loaded. Exempting them would leave the
gate red after every acquisition and teach people its lockfile step is noise.

**It could not be fixed at the choke point.** `Lockfile.put_source/1` is the only way the
file changes, but a file-manipulation module writing a database row is a layering
violation and would break anywhere without a repo. So it is one line per task plus a
structural test — `Architecture.BoundariesTest` fails the build if a task writes the
lockfile and does not record.

**And that test passed with the call deleted, the first time.** It grepped for
`Bake.record` and the *comment above the call* contains those words — "four different
greps that matched a substring", already on `docs/ROADMAP.md`'s risk list, committed a
fifth time inside the test written to prevent the class. It strips comments now, and was
re-checked by deleting a real call and watching it go red.

**The original entry, for the reasoning:**

**A general gap, found by the gate and left for a decision.** `bake_id` is a hash of
`sources.lock.json`, so **any task that writes a lockfile entry changes it**, and a bake
row that no longer describes its inputs stamps every API response with an id for a corpus
that does not exist. `mix pramana.sc.chinese` now calls `Bake.record/1` like
`sc.ingest`, `derge.ingest` and `local.add` do. **Six of the ten tasks that write a
lockfile entry still do not:**

    acquire_all · derge.images · kangyur.catalogue · kangyur.translations
    parallels.import · sc.translations

Each one leaves `mix pramana.gate` red on `:bake_id_diverged` the next time it runs, and
the fix is one line each. It is not done here because two of them (`acquire_all`,
`derge.images`) acquire without ingesting, and whether a bake should be re-recorded when
only the *inputs* moved and nothing was loaded is a real question rather than an
oversight. **Decide it once and apply it to all six**, rather than adding a call where it
happens to be convenient.

**Not attempted, with its measured size.** Extending the fold table with the Taishō
glyph forms Unihan files under `kSemanticVariant` — 衞/衛, 繋/繫, 縁/緣, 増/增, 眞/真,
偸/偷, 擧/舉, 徳/德, 倶/俱 — would move roughly 466 anchors from interpolated to exact.
It is a hand-curated list against a residue that is evidence about two editions, and the
anchors it would sharpen are already bounded. Left undone deliberately.

**Three defects found on the way**, all latent, and the third only because rule 60's
question was asked of something already green — *can a model actually reach this?*

1. **`Pramana.Chunk.Vectors` excluded every range-anchored CBETA rendering.** It tested
   `String.starts_with?(anchor_urn, urn_prefix <> "@")`, and a CBETA line puts the juan
   in between — `pramana:cbeta.T:T0099_001@p0001a06` against a prefix of
   `pramana:cbeta.T:T0099`. **2,089 of the first 3,354 renderings** had no vector built,
   silently, with the count of vectors the only symptom. Now `Pramana.URN.addresses?/2`,
   with a test that fails against the old code. The same assumption in
   `mix pramana.tibetan.pairs` is scoped `WHERE translator_id = '84000'` and is correct
   for Derge anchors, so it is left alone rather than churned.
2. **And the same assumption again in `Pramana.Translations.covering/2`**, which matched
   `work_id` against `urn.work` — the juan for a CBETA address. So even once those 2,089
   renderings had vectors, `get_passage` on a Taishō line returned **no English for any of
   them**: correctly stored, correctly anchored, unreachable. Rule 41 is the reason this was
   looked for; the work is now read from the segment row rather than from the address, and
   the remaining four `urn.work` uses were swept and are all correct.
3. **`mix pramana.recall --renderings` reported hits per language with no denominator.**
   `frequencies_by(found, & &1.to)` — rules 22, 44 and 54 inside the instrument those
   rules are measured with. It now scores each namespace with its own denominator, and
   `--to` restricts the sample to one, because at 1.4% of the pool the Chinese canon
   draws about seven pairs in five hundred and cannot be scored at all.

---


**This project is English-first**: the reader asks in English, the canons stay in their own
languages, and every answer is anchored to the original. That is a positioning decision and
it is also what the measurements support — but it has exactly one hole, and it is large.

    canon                works    with an English layer
    sc (Pāli)            8,442    5,845   69%
    derge (Kangyur)      1,195      472   39%
    derge-tengyur        3,380        0
    cbeta (Chinese)      4,263        0    <-

**That table is the entire explanation for `topical/chinese` being 0%.** Not a weak embedder:
`--renderings` measures English→Tibetan and English→Pāli at **93.8%**. English reaches those
canons because there are 241,409 human renderings to reach them *through*, and fails on
Chinese because there are **none**. The Taishō is the largest thing this corpus holds — 4,263
works, 10.8M segments — and to an English-speaking reader it is currently unreachable except
by knowing the Chinese to search for.

**Two routes, and `docs/TRANSLATION.md` already designs the second.**

1. **Acquire what exists.** The BDK English Tripiṭaka (Bukkyō Dendō Kyōkai) has been
   translating the Taishō for decades; SuttaCentral carries English Āgama translations
   (Anālayo, Bingenheimer). Human-translated, citable as source, partial coverage. Licences
   must be read per work — BDK is not open by default.
2. **Generate the rest**, glossary-pinned, as a **layer over a source anchor that is never
   citable as source** (invariant #8). That invariant exists so this project's own model
   output cannot be served back as scripture, and this is the case it was written for.

**This is also where the term table finally earns itself.** Glossary-pinned generation needs
exactly the term equivalence § F could not justify on retrieval grounds — 不動地 pinned to
*acalā* and to "Immovable Ground" — so the concept layer and the English layer are one build,
not two.

### ▸ THE COVERAGE CURVE, MEASURED 2026-09-02 — and it prices the decision

The question E1 could not answer: matching Pāli's English coverage over CBETA is ~720,000
chunk translations, and **nobody had measured what fraction of that would do.** Pāli is the
only canon that can answer it, being the only one fully covered — 55,326 English vectors
over 44,719 chunks. `Pramana.Retrieval.Semantic`'s `translation_coverage` hides a
deterministic fraction of them, through the query that ships, and
`mix pramana.recall --renderings --to sc.ms` scores what is left. 200 pairs, seed 0.42,
identical at every point.

    coverage   found the work    on the line
      100%     179/200  89.5%   158/200  79.0%
       50%     146/200  73.0%    87/200  43.5%
       25%     124/200  62.0%    51/200  25.5%
       10%      89/200  44.5%    22/200  11.0%
        5%      73/200  36.5%    18/200   9.0%
        2%      38/200  19.0%     6/200   3.0%
        0%       8/200   4.0%     3/200   1.5%

**The 0% row is the control and it validates the instrument.** With no English layer an
English query still reaches the right work 4% of the time, through BGE-M3's own
cross-lingual space and the lexical arm. **CBETA today is at 0.027% coverage** — that row —
and its measured `topical/chinese` is 0 of 12. The curve and the observed failure agree.

**Returns are strongly concave, and the first reading of that was backwards.** Read from
the top, 100%→50% costs 16.5 points and looks like "no knee". Read as *what you get per
unit spent*, which is the purchasing question:

    0% ->   5%   +32.5 pts   6.5 points per 1% of coverage
    5% ->  25%   +25.5 pts   1.3
   25% -> 100%   +27.5 pts   0.37

**The first 5% buys 38% of the entire achievable gain; the last 75% buys 32%.** Early
coverage is worth ~17x more per unit than late.

**Demand is concentrated, and cheaply.** Cross-work citation only — see `docs/PROXIES.md`
for why the raw graph is 62% one repetitive sūtra quoting itself — the **top 100 works are
66.1% of the canon's citation weight and 73,565 chunks, 10.2% of CBETA.** That is the
curve's knee and the concentration peak landing on the same number.

**Tranches, so the first cheque is small.** Cost against citation weight captured:

    tranche   chunks   % of CBETA   % of citation weight
    top  10   16,112       2.2%          26.8%
    top  20   26,191       3.6%          37.1%
    top  30   42,198       5.9%          44.1%
    top  50   48,650       6.8%          53.3%
    top 100   73,565      10.2%          66.1%

**And it runs on Modal, not on an API vendor.** `bin/pramana-modal` is set up and verified
(modal 1.5.4), `priv/embed/modal_embed.py` already does BGE-M3 inference there and
`modal_train_tibetan.py` has run a LoRA fine-tune, so generation is an open-weights model
on the same rented GPU path — no Anthropic or OpenAI account, no per-token vendor bill.
`docs/GPU_RUNBOOK.md`.

That is worth stating because it was got wrong once: the absence of `ANTHROPIC_API_KEY` was
read as "no generation capability", which is the wrong question — this project's inference
has never gone through an API vendor. It does mean a judgement about `CLAUDE.md`'s "do not
let the Python sidecar grow": a translation sidecar is still tensor math and still holds no
domain logic, so it is the same exception embedding already is, but it is an exception
being used a second time and should be a deliberate decision rather than a drift.

**Start at top 20 — 26,191 chunks — because it is the cheapest run that can measure the
one unknown.** The demand-weighting premium is untested: the ablation hid vectors at
random, and the curve says a *random* 3.6% scores around 28% at work level. If a
demand-weighted top-20 beats that materially, the premium is proven and the rest can be
bought with confidence; if it does not, very little was spent finding out. Top 50 is the
likely stopping point either way — 6.8% of the corpus for 53.3% of the canon's citation
weight.

**So the thing to price is ~10% coverage, demand-weighted**: ~73,000 chunks. The ablation
says a *random* 10% takes English→Chinese from 4% to ~44.5% at work level; a
demand-weighted 10% should beat that, by an amount nobody has measured.

**Two caveats that must travel with any figure derived from this.** `on line` at 10% is
11.0%, far weaker than the 44.5% work-level number — a reader who wants the right *line*
is served much less well than one who wants the right work. And citation weight measures
what the tradition cites, which includes its own catalogues (T2157, T2148, T2153 rank high
and nobody reads them for doctrine) and is not the same as what an English reader asks.

**How to know it worked:** `topical/chinese` moves off 0% for the first time, and
`--renderings` scores English→Chinese somewhere near the 93.8% it already reaches for Pāli
and Tibetan. Both instruments exist.

**▸ Both halves of that criterion turned out to be wrong, 2026-08-31**, and the slice above
is how we found out. `topical/chinese` searches the whole corpus, so it cannot move until
the Chinese layer can outcompete 55,135 Pāli vectors — it is a **coverage** test wearing a
retrieval test's clothes. And 93.8% is a pooled figure over populations scoring 79.0% and
8.5% on its companion column, so "near 93.8%" names no target. **The replacement criterion
is `--renderings --to cbeta.T` compared against its own previous run**, plus a
tradition-scoped topical row if one is ever added. Rule 69.

---

## The English layer is for FINDABILITY, not readability — settled 2026-09-02

**Proposed and withdrawn the same day**, and the withdrawal is the useful part.

The proposal was an `answerable` case type: `topical/chinese` asks only whether a Chinese
passage comes back, and for a reader who cannot read Chinese that is not the deliverable,
so a case should assert that an English rendering came with it.

**That imports a product concern into a layer that is explicitly not the product.**
`CLAUDE.md`: *the LLM is a swappable reader that never touches the database.* The consumer
of retrieval is a model, models read Classical Chinese, and translating what comes back is
the caller's job. "Did the right Chinese line come back, with provenance and a verifiable
citation" **is** the right measure for this layer. `topical/chinese` stands as written.

**And the consequence is a cheaper E1, which is why this matters more than the
concession.** If the caller translates, the generated English layer only has to make a
passage *findable*, never readable. Three things follow, all of them testable:

  * **It may not need to be prose.** A dense English gloss per chunk — terms, names,
    doctrinal vocabulary, no connective tissue — could match better than a fluent
    translation: more retrievable surface per token, none of it spent on grammar. Cheaper,
    and plausibly higher recall. **Worth an A/B before generating at scale.**
  * **The quality bar becomes measurable rather than editorial.** No human has to judge
    whether the English reads well; the recall probe scores it. That removes a review
    bottleneck from the whole plan.
  * **Glossary-pinning stays essential, for a different reason.** Not so a reader is not
    misled, but so 方便, 權 and 善巧 land on the same English target and one query finds
    all three.

**The concern survives only on the human surfaces.** `/passage` and `/check` are read by
people, and invariant #8's structural boundary earns its keep there. That is a reader
concern; it does not gate E1 and it does not belong in the retrieval gold set.

### ▸ THE TIER DECISION — `docs/TRANSLATION.md`, 2026-09-02

Recorded there in full; the operative part for E1 is that **index English and reader
English are different products** and only the first is in this budget.

    index    consumed by the retriever    bar: does an English question reach the line
             NEVER served to a person     test: `recall --renderings --to cbeta.T`

    reader   consumed by a person         bar: is this a faithful rendering
             served, labelled, with       test: glossary compliance + consensus against
             the term chain visible             a human rendering where one exists

E1 buys the **index** tier: **prose** (the dense-gloss alternative was tested and
rejected 2026-09-02 — `docs/TRANSLATION.md`), glossary-pinned, scored by the recall probe,
never shown. The reader tier is generated on demand for passages somebody opens — small volume,
high bar — and is not a corpus-scale spend.

**And the boundary this project can honestly claim**, which belongs on the page and not
only in a doc: *you are reading the canon's actual words, at an address you can check.*
The guard proves the citation and never the interpretation, and saying so is the same
discipline that makes the rest of it trustworthy.

**The translation layer is meant to be replaceable.** The pool is keyed on
`anchor_urn + lang + translator_id`, so a better rendering — somebody else's model, a
scholar's revision, a published sangha translation — enters alongside rather than
replacing, and `mode: :compare` returns the disagreement with its attribution. The corpus
is the stable thing; renderings are expected to churn, which is why a rendering is a
fragment over a source anchor and never a top-level URN.

## Found by the architecture review — 2026-09-02

**`compare_translators` returns headwords with no URN, and the anchors to fix that now
exist.** A divergence row says "for *adhimāna-prāpta*, Kumārajīva used 增上慢 and
Dharmarakṣa 貢高" and attributes it to Karashima. It does not say **where** — and
`glossary_anchors` resolves 25,504 of those citations to lines this bake holds.

Attaching one anchor per side would make every divergence openable and byte-verifiable
instead of merely attributed, which is this project's whole thesis applied to its newest
surface. Not a violation of invariant #1 — a glossary headword is not a corpus span — and
still the obvious next increment. A join from `glossary_entries` to `glossary_anchors`,
and one extra field per side of the comparison.

## From the landscape review — 2026-08-30

Four things this project should have, as distinct from the parked ideas in `docs/IDEAS.md`.
They come from reading fojin and Dharmamitra rather than from asking a model what exists —
which mattered, since the assistant that prompted the review invented two projects outright.
`docs/COMPETITIVE.md` carries the corrected landscape.

| # | item | why it is not optional | state |
|---|---|---|---|
| L1 | **Dictionaries** | ▸ **SHIPPED 2026-09-02** — `mix pramana.glossary.dila`, 33,267 entries from five DILA glossaries. See below. Originally: **the largest functional gap in this project.** fojin ships 39 dictionaries, 747K entries — DPD, Mahāvyutpatti, Rangjung Yeshe, NTI Reader, Apte. We ship none. A scholar reading Classical Chinese without a lexicon is working one-handed, and **`define_from_canon` is not a substitute**: the canon defining 空 in its own formulae answers a different question from what 阿耨多羅三藐三菩提 transliterates. Licences vary per dictionary and must be tracked per source, exactly as text sources are | open |
| L2 | **Find out why BGE-M3 scores 51% in MITRA's benchmark and 0.4% here** — *before* buying either a term table or a new model | ▸ **CHEAPEST VERSION ALREADY RUN, 2026-08-30, and it redirects the question.** MITRA's benchmark includes BGE-M3 — the model this corpus embeds with — on Sanskrit→Chinese against 400,412 candidates:

    BM25 14·23·28 · LaBSE 19·33·39 · **BGE-M3 base 29·45·51** · BGE-M3 ft 40·59·65 · MITRA-E 79·94·96

**BGE-M3 reaches 51% P@10 there and 0.4% here.** A 31x larger haystack does not explain two orders of magnitude, so **the embedder is probably not the bottleneck** and neither a term table nor a 9B model is indicated yet.

The likely explanation is in § F's own text: *a parallel records that two discourses correspond, not that they share words*. MITRA benchmarks **true parallel sentences** — translations of one another. We benchmark **discourse-level correspondence**, which is a strictly harder task, and the 20.8–28.8% same-language control is evidence the difficulty is in the task rather than the language.

**The decisive experiment is cheap and uses data already held.** Run the probe against pairs that ARE translations of each other — the 30,653 aligned bo↔en folio pairs from 84000, or SuttaCentral's segment-aligned renderings — and compare with the discourse-parallel figure. If BGE-M3 does well on true parallels and badly on discourse correspondence, the diagnosis is the task and § F's framing needs rewriting, not its retrieval. Only if it does badly on BOTH is a better embedder implicated.

MITRA-E details, for when that question is actually reached: 9B params, **3,584-dim embeddings** against the current 1,024 — a 3.5x vector-store increase and a schema migration — asymmetric encoding (queries wrapped in an instruct prompt, corpus raw), and a Gemma-derived licence to read before adoption | open — **run the true-parallel probe first** |
| L3 | **Answer-time repair, and a trust vocabulary** | We diagnose citation failures in five distinct ways and **repair none of them**. fojin strips citations whose source was never retrieved, and downgrades non-verbatim "quotes" to plain prose. Diagnosis serves a caller who checks; repair serves the one who does not, and that is most of them. Adopt their four-word state vocabulary wholesale — `verified` / `citation_corrected` / `quote_relaxed` / `no_sources` | open |
| L4 | **Cross-scheme URN resolution** | The same passage is `fojin:cbeta/T0001.1`, `pramana:cbeta.T:T0001_001@p0001a01`, `T2185_.56.0001a01` and `mn1:1.1` depending on who cites it, so **a citation cannot be checked in the system that did not produce it**. fojin exposes `resolve_urn`; we parse four native grammars already. Teaching each resolver the other's scheme is small, mutual, and makes citations portable across the field. Best effort-to-benefit ratio on the list | open |

| L5 | **A "check anything" screen — one input, one verdict list** | `verify_report` shipped 2026-08-28 and had **no surface**: only an MCP call reached it. Rule 60 | ▸ **SHIPPED 2026-08-31** — `PramanaWeb.CheckLive` at `/check`, in the nav, nine tests. See below |

### L1 — dictionaries, shipped 2026-09-02

`mix pramana.glossary.dila` and `Pramana.Normalize.DilaGlossary`. **33,267 entries** from
DILA's TEI glossaries, taking `glossary_entries` from 56,382 to 89,649.

**Composing was rejected, on invariants rather than taste.** Mounting fojin's
`lookup_dictionary` would put text with no URN, no sha256 and no provenance record through
an API that promises all three (#1), depend on a service no lockfile pins (#3), and break
self-hosting for every user. There is also no MCP client in this codebase. And it buys
nothing: `docs/COMPETITIVE.md` already says fojin-mcp and this surface **mount in the same
client**, so composition works one layer up, for free, today.

**Chosen for accuracy over reach**, which was the brief. Karashima's three are glossaries
of *one translator's usage* and record what no general dictionary can — 佛 transliterating
*bodhi* rather than *buddha* in the earliest translations, Kumārajīva's 法 as an ordinary
adverb, Lokakṣema rendering *śrāvaka* as 阿羅漢.

| | |
|---|---|
| stored | shh 16,792 · mvy 9,379 · dharmaraksa 3,228 · kumarajiva 2,340 · lokaksema 1,528 |
| scoped to a work | 7,096 — the three Karashima glossaries, to T0263, T0262, T0224 |
| source-attested | 14,132, meaning a Sanskrit witness carries an actual reading |
| Taishō citations kept | **29,890** |
| corpus coverage | seeded 200-headword samples: shh 187/199, kumarajiva 190/199, mvy 140/199 |

**Polysemy is handled by refusing to resolve it.** One row per sense, `gloss_id` numbered
per headword, and `work_id` carrying the scope. 怛姪他 has five senses in Kumārajīva alone;
刹, 度 and 妙法 have four. Nothing here says what a word "means".

**Three defects found while building, all of which produced plausible output:**

1. **An unbounded `sa-witness` regex captured a Chinese quotation into the `sanskrit`
   column.** Karashima records a Sanskrit NON-correspondence as `K. not found at 32.16`
   with no `<quote>`, and the match ran on into the next parallel's Chinese. A line of the
   Lotus Sūtra was stored as the Sanskrit of 法, and attestation was inflated to 2,311.
2. **Bounding it to the FIRST witness block then under-reported it** to 2,064 — 法's real
   reading, *dharmatā*, sits in the second parallel behind the "not found". Karashima
   lists one witness per parallel passage. The true figure is 2,149.
3. **276 headwords carry no gloss in any language** — cross-references and variant
   spellings. They violate `glossary_entry_has_a_term`, and are **dropped and counted**
   rather than admitted by loosening a constraint that exists because an entry without a
   gloss is meaningless.

**Not taken:** Hopkins (18,441) and Nanshan Vinaya (3,218), same site and terms, both
duplicating strength already held. **Not acquirable:** the DDB is the scholarly standard
and is not open for bulk download — rights sit with individual article authors. Asked for,
not scraped, the same posture as SAT.

**Licence CC BY-NC-SA 4.0** — site-stated; the TEI headers name no version, so the
restrictive reading governs (rule 10). NC puts these where CBETA is: out of the public
artefact.

**▸ AND THE CITATIONS ARE ANCHORED — `mix pramana.glossary.anchor`, 2026-09-02.** 29,890
citations resolved against the bake: **25,504 to a line held (85.3%)**, **4,345 absences**
attested by a scholar who checked, 41 unresolved (0.1%). Opening one line of Kumārajīva's
Lotus now returns 方便 = *upāyakauśalya* and 無上道 = *agrabodhi*, **and `absent` entries
scoped to T0263** — the term Dharmarakṣa used, with no counterpart in Kumārajīva at that
line.

**A minus sign reverses the direction of counting**, and 285 citations use it. `27b-1` is
the *last* line of page 27b. Verified before implementing rather than inferred: the entry
citing `27b-1` quotes 能於四衆示教利喜 at line 29 of a register whose last line is 29, and
the entry citing `19a-6` is headed 方便 and marks that headword at line 24, which is
`29 - 6 + 1`. Unresolved fell 326 → 41.

The 41 were chased rather than written off. 31 name a line CBETA prints nothing on —
`T.224` `448c4` is an `<lb/>` immediately followed by the next one, so rule 3 says it is
droppable and the normalizer was right. Checked against `raw/`.

### L4 — reading other people's citations, shipped 2026-09-02

`Pramana.Citation`. **The payoff was not convenience.** `Guard` scans prose for `pramana:`
URNs, so a report citing the Taishō the way every article cites it — `T. 262, 6a23` —
contained no citations at all. The guard reported **zero checked** and `/check` rendered
that as a document with nothing wrong with it: an absence of findings and a clean bill of
health were the same screen.

Two grammars, both read off data this project already holds rather than off a spec: the
**Taishō in print and SAT form**, including the from-the-foot `27b-1` verified during the
glossary anchoring, and **SuttaCentral segment ids**, which 244,763 renderings are keyed
on.

**fojin's `fojin:cbeta/T0001.1` is deliberately not implemented.** What the `.1` addresses
is documented nowhere this project could check, and a resolver that guesses returns
confident wrong passages — worse than one that returns nothing. Asking them is the next
step, and it is a conversation rather than a commit.

**Ambiguity is settled by the corpus, never by a rule.** `T 9, 6a23` might name text 9 or
volume 9 and scholars write both; a parsed work is accepted only if this bake holds it.
`sn22.51:1.1` is a segment id and `Matthew 3:16` is not, and no regex separates them — so
the segment table does. A checker that invents findings is worse than one that misses them.

### L3 — repair, shipped 2026-09-02

`Pramana.Repair`. We diagnosed citation failures five ways and repaired none. Four of the
five states are fojin's vocabulary adopted as `docs/PLAN.md` said to:

    verified            the quotation byte-matches. Untouched.
    quote_relaxed       the words are the corpus's and the punctuation or Han form was
                        not — the quotation is REPLACED WITH WHAT THE CORPUS PRINTS.
    citation_corrected  the words are real and the address was wrong; the URN becomes the
                        one the guard's own search found them at, and only if unique.
    no_sources          nothing supports it. The citation is stripped, the prose kept.

The fifth is ours, recorded as a deviation rather than hidden:

    flagged             repair needs a judgement — a quotation spanning a printed line
                        boundary needs a range somebody must choose, and a translation
                        quoted as source is invariant #8, not a typo.

**Repair never invents, and the guard is why it does not have to.** Every correction is a
substitution of something the corpus already said. `citation_corrected` uses `found_at`,
which `Guard.diagnose/1` produced by searching for the quoted words — a place they were
found, not a place they might be. A quotation found at three URNs gets `no_sources`, not
the first of the three: picking one produces a document whose citations all resolve and
some of which are wrong, which is worse than what came in.

Reachable from `/check` and in the `verify_report` payload. Nothing writes to the corpus —
it rewrites the caller's own document — so invariant #7 is untouched.

**And it found a defect in the guard on its first run.** See § "A URN at the end of a
sentence" below.

### A URN at the end of a sentence resolved to nothing — found 2026-09-02

`.` is legal inside a locator (`sc.ms:mn1@1.1`), so `Guard`'s URN pattern admitted it —
and swallowed the full stop closing a sentence. *"…as stated at
pramana:cbeta.T:T0262_001@p0001c17."* extracted a URN with a period on the end and the
guard reported `:not_found`: **a false accusation rather than a missed one**, in prose,
which is where citations mostly live.

`evals/` could not see it because its gold citations are constructed rather than written
in sentences — 601 quote cases, none of them a sentence. Rule 68 now carries it as a third
instance, together with the rule-41 half: trimming in `extract_urns/1` and not in the
quote-pairing map made every paired quotation miss its key, silently downgrading a byte
comparison to an existence check that reports `ok`. Both are pinned by tests that fail
against the respective wrong version.

### L5 — `/check`, shipped 2026-08-31

One textarea, one verdict list, and the deepest infrastructure here is now the visible
product rather than something buried behind an MCP call.

**Four decisions worth keeping.**

1. **Three verdicts, not two.** `unverifiable` — a replay recorded against another
   `bake_id` — has its own colour and never the failure colour. The corpus changed; the
   claim is not refuted and does not pass. A test asserts it, and that test **failed for
   the wrong reason first**: with no bake row in the test database `Bake.current_id()` is
   nil, every replay simply executes, and the screen rendered `verified`. The setup now
   records a bake. A test for a distinction has to be able to see the distinction.
2. **The summary states its denominator.** Never "verified" — how many were byte-compared,
   how many were checked for **existence** only because no quotation was attached, how many
   quoted a translation rather than the source. Rules 22, 44 and 54, on the screen where a
   reader will act on the number.
3. **An oversized paste is refused whole, not truncated.** `Report.verify/2` caps replay
   *execution*; the citation scan and the figure heuristic are regex passes over the whole
   document and are not capped by it. 200 KB, refused with a message — a silently shortened
   report would come back verified on the half that was read, which is rule 4 where it
   would do the most damage.
4. **It is synchronous, and the moduledoc says so.** 25 replays at ~1.2 s each holds the
   socket for tens of seconds. Bounded, not free. Correct for a self-hosted reader with one
   person in front of it; revisit before serving strangers, for whom the paste box is also
   the obvious way to make the corpus work on someone else's behalf.

**The format is on the page, as static help rather than a button that fills the box.** A
quotation needs no markup — paste prose with URNs in it — but nobody guesses a
`pramana-replay` block, and the one thing this screen does that nothing else does would
otherwise be unreachable without reading the source. That is rule 60 one level in. A
button filling the textarea with an example built from URNs that may not be in the
reader's bake would have demonstrated the format **by failing**, which teaches the wrong
thing on first use.

**Still not done:** no worked example that actually verifies against the reader's own
corpus. Doing it honestly means deriving one at mount from a segment the bake really
holds, which is a domain function this screen does not justify on its own.

**And one correction to make first.** `docs/COMPETITIVE.md` has said *"fojin has more corpus;
you will not out-scale it quickly there"*, and that has been shaping strategy. fojin reports
10,500+ texts (8,900 with full content); this bake holds **17,281 texts and 12,586,964
segments**. They count sources and volumes differently so it is not a clean comparison —
**measure it properly rather than conceding it.**

---

## Blocked

| item | blocked on |
|---|---|
| **#14 SAT / Taishō 56–84** | **SENT 2026-08-15** to `sat at l.u-tokyo.ac.jp` (text in `docs/sat-request-email.md`). No reply as of 2026-08-29. **Note it landed during Obon**, when Japanese universities are largely closed — 14 days is not yet a silence worth reading into. A follow-up in mid-September is the next step, not a workaround. |
| ~~**#41 T56–84 catalogue**~~ | ▸ **UNBLOCKED 2026-08-30 — a source did exist, and always had.** SAT serves a browsable Apache index at `/iiif/taisho/manifests/`, listing 5,750 IIIF manifests over 2,873 works, of which **541 fall in T2185–T2731 and span exactly volumes 56–84**. One request, no permission, saved to `raw/sat-iiif/`. It also corrected a published figure: the "547 works" this project has been reporting is `2731 - 2185 + 1`, the width of the number range, **not a count**. |
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

- ~~**`/inventory` is a ten-second page load, and one field is the whole cost.**~~ ▸ **FIXED
  2026-08-29** — `texts.char_count`, written with the body; snapshot 9,819 ms → 1,319 ms.
  Found 2026-08-29 while building `mix pramana.doctor`. `Inventory.snapshot/0` takes 9.8 s against
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

### Postgres tuning on this machine — 2026-08-29

**Applied, measured, reverted the same day.** `docs/DEV_ENV.md` recorded the block and now
records that it was withdrawn. The settings were reasonable in isolation — `shared_buffers`
128 MB → 2 GB, `random_page_cost` 4.0 → 1.1 on an SSD, `work_mem` 4 → 16 MB,
`maintenance_work_mem` 64 → 512 MB.

**It never produced a measurable gain on any workload here.**

    recall probe, concurrency 6      1.9 s/case before -> 2.1 s/case after
    verify, per source               unchanged; the gain came from parallelism
    evals, retrieval subset          sequential reproduced the baseline exactly either side

**And it is the prime suspect in a 7x slowdown of `verify --all`.** The parts sum to 6.2
minutes of work — cbeta 1m09s, sc 4.5s, derge 3m52s, tengyur 1m02s — while `--all` took
**46m48s**, on a 16 GB machine whose swap file grew 2 GB → 3 GB → 4 GB over the session with
2.9 GB in use. `--all` holds both Degé edition maps resident (4,575 works of IR) where a
per-source run holds one; handing 2 GB to Postgres on top of that is the difference between
fitting and paging.

**Two hypotheses were eliminated before landing on memory**, and both are worth not
repeating: the slowdown is *not* the 17,281 per-text round-trips (chunking restored bulk
queries and `--all` stayed at 46m48s, against 46m56s), and the eval scorecard change was
*not* caused by tuning (a sequential run after tuning reproduced the baseline exactly).

**The lesson is the sizing, not the settings.** A 16 GB machine that must simultaneously hold
a 2.2 GB embedding model, the BEAM, and a working set over a 12.5M-segment corpus does not
have 2 GB spare for a buffer cache. If this is revisited, measure **peak RSS and swap** first
and treat the memory budget as the constraint — not the Postgres defaults, which were
conservative for good reason here.

### Concurrency in `mix pramana.evals` — 2026-08-29

**Tried, measured, reverted the same day.** The eval loop is a sequential `Enum.map` over
1,472 cases and looked like the same defect `Pramana.Recall`'s probe had, where
`Task.async_stream` gave **3.1x with byte-identical output**. It is not the same.

    --only retrieval, 446 cases        retrieval row      wall clock
    baseline (recorded)                370/446  83.0%     —
    concurrency 1, after tuning        370/446  83.0%     878s
    concurrency 6                      368/446  82.5%     737s

**Two cases change answer under concurrency, and it buys 1.19x.** Sequential-after-tuning
reproduces the baseline exactly, which exonerates the Postgres tuning and leaves concurrency
as the cause. Embeddings are bit-identical batched or solo (max elementwise difference 0.0),
so the mechanism is most likely tie-breaking under concurrent query execution rather than
anything in the model — **and it was not chased further, because the trade fails on the
numbers regardless of mechanism**: a fifth of the runtime is not worth two moved cases in the
published ratchet.

**If you retry this, the bar is the same:** same case set at `1` and at `N`, compared row by
row, before any timing is quoted. And note what the obvious implementation would have cost —
`score_case/2` upholds *one case may not kill the run* with `rescue` and `catch :exit`, but
`async_stream` reports a task that dies anyway as `{:exit, _}`, and `fn {:ok, r} -> r end`
turns that into a `FunctionClauseError` that kills the run. That is the 4h25m loss this
module already records, reintroduced by the shape of the fix.

**What survives from the attempt:** per-case detail in the scorecard (audit queue #14),
because localising this took a 20-minute re-run that a case-level diff would have answered
instantly.

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
