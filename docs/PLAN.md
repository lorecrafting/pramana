# Plan

**The living task list.** [History](HISTORY.md) records what happened and
[rules](RULES.md) what was learned; this records what is *next* and why.
Where they disagree, [STATUS](STATUS.md) is the evidence and this is the intent.

> **KEEP THIS UPDATED.** Every session that finishes an item, learns something that
> changes an estimate, or discovers new work edits this file in the same commit. An item
> whose evidence has gone stale is worse than no item. Three things trigger an edit:
> **finishing** an item (delete it; Git keeps it), **discovering** work (add it with its
> evidence), and **invalidating** an assumption (correct it and say why).

Last reviewed: **2026-09-24**, when the dated session logs, completed-PR records and closed
queues were cut from this file. They remain readable in [the full plan as of that date](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#plan)
and in Git history. A pointer below into that copy is dated evidence, not a fresh instruction:
reconcile it with current code before dispatching work from it.

## Open work

### Needs a person

- **The T0026 fidelity verdict.** `mix pramana.translate.bakeoff --work T0026 --anchors 25`
  produces the blinded sheet; rank it yourself, since a reader without Chinese can only rank
  fluency. Translation quality is the one lever [§ E1](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#start-here--session-of-2026-09-04) left open.
- **A second human English over CBETA passages Patton already covers**, so recovery figures
  stop dividing by an identity match. A licence conversation, not a GPU run.
  [Queue item 13](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#the-queue-in-order).
- **SAT / Taishō 56–84.** Sent 2026-08-15; the follow-up is overdue. See [Blocked](#blocked).
- **Tengyur works with no title** (3,864 of 4,575 named, per the generated figures below).
- **The Chinese pilot's human gates**: rights clearance, qualified evaluators, participant
  recruitment and D8, per the [pilot charter](strategy/PILOT_CHARTER.md) and
  [preflight](strategy/PILOT_PREFLIGHT.md). Implementation also waits on
  [Foundry's G0](PRODUCT_STRATEGY.md#dependency-on-foundry).

### Engineering

- **Restamp the release.** `mix pramana.doctor` reports the selected release STALE
  (`identity_version` v1/coarse → v2) on 2026-09-24, so responses name a release that is not
  the loaded one. `mix pramana.release.stamp`, then re-run the doctor.
- **The semantic arm cannot say "nothing".** [§ D](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#d-the-semantic-arm-cannot-express-ignorance--newly-discovered-2026-08-27):
  hybrid returns semantic neighbours for a doctrine no text discusses.
- **`topical/chinese` and Tibetan recall.** [§ F](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#f-topicalchinese-is-still-0--now-measured-over-496-cases-rather-than-12) and
  [§ G](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#g-tibetan-recall--24-cases-unreachable); Tibetan misses are absent from 200 candidates, a recall problem.
- **Public demo.** [§ E](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#e-public-demo--newly-unblocked); now bounded by the
  [deployment boundary](DEPLOY.md).
- **Hosting hardening deferred from #19–#23**: global/multi-session admission control and
  queue expiry. Reader translation defaults wait on strategy decision D4.
- **The feedback loop** proposal, [§ A6](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#a6-the-feedback-loop--signals-limits-and-the-ways-it-degrades--proposed-2026-08-28), unstarted.
- **Surviving Sanskrit witnesses**, [S1](#s1-the-surviving-sanskrit-witnesses--scoped-2026-09-02-not-started) below.

## Where the product stands

**The three blocks below are generated** — `mix pramana.docs.figures`, checked by the gate.
This table said 249 work relations when there were 269 and 17 MCP tools when the directory
held 18, so the counts no longer live in prose. Rule 77.

<!-- figures:corpus -->
| | |
|---|---|
| texts | **17,281** |
| segments | **12,581,624** |
| chunks | **980,464** |
| vectors | **1,066,026** |
| renderings | **273,334** |
| glossary entries | **89,649** |
| quotations | **141,073** |
| MCP tools | **19** |
<!-- /figures -->

<!-- figures:relations -->
| | |
|---|---|
| work relations | **389** |
| comments_on | **269** |
| subcommentary_of | **38** |
| parallel_of | **82** |
| commentary alignments | **76,722** |
| root lines with commentary | **57,609** |
<!-- /figures -->

<!-- figures:derived -->
| | |
|---|---|
| commentary alignment | **100 of 184 alignable pair(s) — 77 distinct commentaries, 76,722 line alignments** |
| commentary -> root links | **194 of 3,923 commentarial works reach a root** |
| Tibetan work titles | **3,864 of 4,575 works named** |
<!-- /figures -->

The rest of this table is prose about those numbers, and a measurement in it states its
date.

| | |
|---|---|
| CBETA | **16 collections of 26** — T 2,471 · X 1,230 · J 285 · **I 101** · N 38 · **GA 51** · **F 27** · L 21 · P 13 · K 9 · A 9 · U 2 · S 2 · **GB 2** · M 1 · **ZS 1** — 4,340 files locked |
| vector coverage | **100% of texts chunked, 100% of chunks embedded** — the 38% unreachable that `reachable_percent` exposed on 2026-08-26 is closed |
| English over Chinese | **3,354 human** renderings over **2 of 4,263** CBETA works (54 Āgama sūtras), plus **28,571 generated** over **14 of 4,263** — 3.88% of CBETA's chunks, new 2026-09-03, § E1 |
| reader | **six** LiveView screens — search `/`, inventory `/inventory`, survey `/survey`, passage `/passage`, work `/works/:id`, **check `/check`** |
| work relations | **389** — 269 `comments_on` · 38 `subcommentary_of` · 82 `parallel_of` (41 pairs). By signal, in ROWS: `title_match` 240, **`shared_text` 66**, `manifest` 1; in distinct source works, 156 / 66 / 1, because one relation asserted by two methods is two rows and that is corroboration rather than duplication |
| passage parallels | 407,176 recorded · **24,717 openable (6.1%)** — the rest name witnesses this bake does not hold |
| commentary alignment | **76,722 lemmas over 100 pairs**, attaching commentary to **57,609 root lines** — deterministic, no model. 2026-09-03: the run went from a projected 9 hours to 2 minutes, `String.slice/3` |
| public exposure | **213,932 rows servable** · 34,697 forbidden by licence · 9,841 withheld pending a publication record (`mix pramana.public.check`) |
| eval | **92.3% over 1,472 cases** (`evals/baseline.json`) — 0 stale, 0 errored. Not comparable with 93.1%/1,400: the denominator grew by two case types, one scoring 70%. Compare per row |
| new gold sets | **rendering 70.0%** (40 cases, mean rank 1.68) · **gloss 100%** (32 cases, a regression detector — see below) |
| retrieval@10 | 374/446 — zh 96.1% · pa 80.0% · bo 48.4%\* |
| absence | **75%** — and the failing case is real and stays red; see item D |
| answered from any tradition | 81.8% |
| noise floor | 1 case same-index · **6 cases across an index rebuild, 4 of them Tibetan** |
| full gate | **32m22s** — evals 21m14s at 1.2 cases/s, integrity 11m02s, `verify --all` 7m09s over every segment (2026-08-31) |
| redistributable subset | 13,017 texts · 1.8M segments · 315k vectors |
| CI | GitHub Actions on every push — compile `--warnings-as-errors`, format, credo, 1,862 tests |

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
| follow parallels and variants between them | curated parallels, the apparatus, 141,073 quotations, and **72,120 commentary lemmas** attaching commentary to the line it explains |
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

## S1. The surviving Sanskrit witnesses — scoped 2026-09-02, not started

**There is no Sanskrit canon, and the item has to be written as if there is not.** No
Sanskrit Tripiṭaka exists the way a Pāli canon or a Taishō does: most Indic originals are
lost, and the Āgamas survive in Chinese *because* the Sanskrit did not. What exists is a
survival set — Saddharmapuṇḍarīka, Aṣṭasāhasrikā, Laṅkāvatāra, Vimalakīrti in part;
Abhidharmakośa and the Madhyamaka and Yogācāra śāstras; Mahāvastu, Lalitavistara,
Divyāvadāna; and manuscript finds from Gilgit, Schøyen and Turfan. "Add Sanskrit" means
adding **witnesses**, not a fourth canon, and any plan phrased the other way is wrong
before it starts.

**What it buys is the pivot, and that is the argument for it.** Chinese-to-Tibetan term
correspondence currently rests on a glossary's *assertion* — `Pramana.Translators` joins
two Karashima glossaries on normalised Sanskrit and finds **475 of 601 shared terms
disagree**. With Sanskrit source text the same alignment can run through the shared
original: deterministic, checkable, and invariant #5's stated preference over the
probabilistic route we are presently forced onto. Nothing else in the corpus can do this,
because Sanskrit is the language the other three translate *from*.

**Shape: a dedicated ingest, not the pipeline behaviours.** `CLAUDE.md`'s rule decides it
— GRETIL is one file per work but the markup is not uniform (plain text, TEI and HTML in
the same collection), so this is `mix pramana.gretil.ingest` calling a normalizer and
`Corpus.Loader` directly, as SuttaCentral, Derge and 84000 all do. It edits no existing
source, adds nothing to `mix pramana.bake`, and adds a `Pramana.Sources` entry because
that is where the licence and the tradition are declared.

**Two blockers, and neither is architecture.**

1. **Licence, and it gates acquisition.** GRETIL is per-text "free for scholarly use"
   rather than uniformly CC0 or CC-BY, which does not map cleanly onto a `license_class`
   the API can exclude by. DSBC (Nagarjuna Institute) and SARIT are cleaner in places.
   **Read the terms before acquiring anything**, the way the Gemma terms were read on
   2026-09-02 rather than assumed — and expect the answer to be per-text, which may mean
   the source carries a licence per work instead of one for the source.
2. **Citation grammar, and it is the hard part.** Invariant #2 forbids inventing ids, so
   each text needs its own edition's numbering — Kośa kārikā numbers, Lotus chapter and
   verse — and GRETIL carries those inconsistently across files. A work whose grammar
   cannot be recovered is **not ingested**, rather than ingested under a made-up address.

**Scope it to the intersection, not the corpus.** The value is concentrated in the works
surviving in Sanskrit **and** Chinese **and** Tibetan — roughly 20-30 texts — because
that is where a pivot has two ends to join. That is a bounded ingest with a clear
acceptance test: for a work held in all three, does the Sanskrit anchor a Chinese term to
its Tibetan counterpart without consulting a glossary? Ingesting all of GRETIL is the
open-ended version of this item and should be refused.

**Priority: after E1.** E1 is what makes 4,263 CBETA works reachable by an English
reader, and it is the measured bottleneck (38.5% with no English layer against 89% for
Pāli). S1 improves *alignment quality* for works we already hold, which is a smaller and
less urgent gain than making a canon reachable at all. It is written down here so it is
costed rather than floating.

## Rejected, with evidence — do not redo

### Deriving `text_role` from a Chinese title suffix — 2026-09-03

**1,944 works carry no `text_role`, so no linker and no aligner can even consider them** —
1,230 of them the whole X collection, which is mostly commentarial. `Pramana.Derge.Genre`
derives Tibetan role from a genre suffix, so the obvious move is the Chinese equivalent.

**Measured against the Taishō works whose role comes from the 部 table**, which is
independent ground truth, and only two suffixes carry signal:

    suffix    n    commentarial   treatise   root
    論      166           15.7%      75.3%    2.4%
    疏       64           84.4%       6.3%    0.0%
    記       53           56.6%       9.4%    3.8%
    義       17           29.4%      52.9%   17.6%
    讚       27            3.7%      44.4%   51.9%
    傳       31            0.0%       3.2%    0.0%

`疏` predicts commentary and `論` predicts treatise. **`記` is a coin flip, `讚` is mostly
root** — a hymn rather than exegesis, so the rule that looks most obvious would be actively
wrong — and `傳` is biography from 史傳部.

**The yield does not pay for what honesty would cost.** The two reliable suffixes reach
**134 of the 1,944** roleless works — 7% — at 84% and 75% precision. And `works.text_role`
carries no confidence or basis column, so a derived role would be indistinguishable from
one the 部 table asserts. Doing it properly means a `text_role_basis` column, the way
`date_basis` already exists for exactly this reason, plus a backfill and every consumer
taught to read it. That is a schema change and a provenance claim for 7% of a population,
against a doctrine that an unlabelled work is a smaller problem than a mislabelled one.

**If it is ever revisited**, the finding to start from is that the suffix table above is
the whole signal — and that `記` and `讚` are the traps.

### Widening the shared-text rule's partners to treatises — 2026-09-02

**This is item 4's second half, and it is refused rather than owed.** The obvious
completion of `Relations.may_explain/1` is to let `Pramana.Quotations.Roots` take treatise
partners for `subcommentary` sources, the way title matching now does. Measured against
the 18 `subcommentary_of` links title matching produces, it scores **1 of 14 testable —
0 of 2 in the dominant band at five or more shared passages, 0 of 7 below it, 1 of 5 tied.**

**The three Abhidharma cases are the mechanism, and they are hand-checkable because
scoring cannot see them** — none of `俱舍論記`, `俱舍論疏`, `俱舍論頌疏` contains
`阿毘達磨俱舍論`, so no title link exists for any of them:

    T1823 俱舍論頌疏  ->  T1558 阿毘達磨俱舍論      334 passages   correct
    T1822 俱舍論疏    ->  T1562 阿毘達磨順正理論    108            wrong
    T1821 俱舍論記    ->  T1563 阿毘達磨藏顯宗論     47            wrong

`T1562` and `T1563` are Saṅghabhadra's treatises, which quote the Kośa at length — so two
of the three Kośa commentaries land on a work that *contains* their root rather than on
their root. **The shared-text signal cannot tell "the work this explains" from "another
work that quotes it heavily",** which is the failure that restricting partners to
root-role works suppresses. Among treatises there is no equivalent restriction to make:
`root` is a category, `the Kośa rather than its critics` is not.

**So the refusal in `Roots` is correct rather than merely cautious, and that population
belongs to title matching**, which now holds it — 18 links, deterministic containment. The
one case shared text gets right and titles cannot, `T1823 → T1558` at 334 passages, is real
and is not worth the other two.

Also measured and rejected the same day: **abstaining when a partner is unopposed**
(`runner_up_passages: nil`). `T1708` 仁王經疏 suggested it — seven passages with the
`T0220` family and nothing at all with either 仁王經 above the scan's 20-character floor —
but the cell does not hold up: unopposed proposals score **7 of 11** against **13 of 18**
for contested ones, and unopposed *at strength* is 3 of 3. There is no threshold there to
build on.

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

## History

Completed work is not kept here. The post-#17 to post-#23 PR records, the 2026-09-04 "Start here",
the numbered and audit queues, E1 and the landscape items, sections A–H and the backlog are in
[the full plan at 2ad8ed91](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md#plan). Findings that became rules live in [RULES](RULES.md);
incidents and measurements in [HISTORY](HISTORY.md).
