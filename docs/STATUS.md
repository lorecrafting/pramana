# Status

**What is true right now.** Read this first in a new session, then `docs/PLAN.md` for what
is next.

This file used to be 3,896 lines and 38% of all documentation here, because it was also the
project log, the rules reference and a case study. Those are now three files, and this one
is only the present:

| | |
|---|---|
| what to do next, and what it is blocked on | `docs/PLAN.md` |
| what happened, in order | `docs/HISTORY.md` |
| rules learned from real defects, cited by number | `docs/RULES.md` |
| why cheap evaluation proxies lie | `docs/PROXIES.md` |

---

## Where we are

*Snapshot, not an accretion. Everything here is true today; the dated announcements this
section used to accumulate are in `docs/HISTORY.md`, where a sentence is allowed to age.*

### The corpus

| | |
|---|---|
| texts · segments | **17,281** · **12,586,964** |
| Chinese (CBETA) | 4,263 works across **16 of 26 collections** — T 2,471 · X 1,230 · J 285 · I 101 · GA 51 · N 38 · F 27 · seven alternative editions 57 · GB 2 · ZS 1 |
| Pāli (SuttaCentral) | 8,442 works, **210,756** English renderings by 6 translators |
| Tibetan (Degé) | 1,195 Kangyur · 3,380 Tengyur, **30,653** English renderings from 84000 |
| English over Chinese | **3,354 renderings** by 1 translator, over **2 of 4,263** CBETA works — new 2026-08-31 |
| English renderings, all canons | **244,763** by 8 translators |
| chunks · vectors | 980,464 · **1,037,455** |
| pipeline | **v5** · `verify --all`, `integrity` and `coherence` all green over every text |

### English-first, and one canon is not reachable that way yet

**The reader asks in English; the canons stay in their own languages.** Measured 2026-08-30
by `mix pramana.recall --renderings`, over pairs that really are translations:

| task | work-level | on the line |
|---|---|---|
| **English → Tibetan / Pāli source** | **93.8%** | 54.2%† |
| same-language discourse correspondence | 28.8% | 4.8% |
| cross-lingual discourse correspondence | 0.6% | 0.4% |

† **Pooled over two populations that score 79.0% and 8.5% on this column** — read it per
canon, and see the anchor-width table below for why. Corrected 2026-08-31, rule 69.

An English query reaches Tibetan and Pāli source text **469 times in 500** — better than the
system handles *same-language* paraphrase. So the language barrier is not the problem it was
published as, and the earlier claim that it "costs 98% of achievable recall" is withdrawn.

**Chinese is reachable in English for the first time, and barely.** Measured 2026-08-31,
after `mix pramana.sc.chinese`:

| canon | works | with an English layer |
|---|---|---|
| sc (Pāli) | 8,442 | 5,845 |
| derge (Kangyur) | 1,195 | 472 |
| **cbeta (Chinese)** | **4,263** | **2** |
| derge-tengyur | 3,380 | 0 |

Those 2 are T0099 and T0026, and the unit misleads in both directions: a CBETA work is a
whole Āgama, so 2 works is **54 sūtras**, and 2,761 of the 65,785 segments in those two
texts — **2,761 of CBETA's 10,788,972**. See `docs/PLAN.md` § E1 for what shipped and what
it measured.

**`topical/chinese` is still 0 of 12, and nothing regressed.** `--only topical` scores
51.0% against a baseline of 51.0%, every tradition row identical. A search of the whole
corpus puts 191 English vectors over the Chinese against 55,135 over the Pāli, and the
Pāli wins every time.

**Measuring it per canon broke the instrument, and that is the larger finding.**
`mix pramana.recall --renderings --to <namespace>`, 200 pairs each, seed 0.42 — the same
probe pointed at one canon at a time, with `derge.D` run as a control:

| canon | mean anchor width | found the work | on the line |
|---|---|---|---|
| `sc.ms` (Pāli) | **1.00 segment** | 178/200 · 89.0% | 158/200 · 79.0% |
| `cbeta.T` (Chinese) | **2.01 segments** | 126/200 · 63.0% | 74/200 · 37.0% |
| `derge.D` (Tibetan) | **6.94 segments** | 199/200 · 99.5% | **17/200 · 8.5%** |

**`on the line` scores whether the retrieved span CONTAINS the whole anchor, so it is
mostly a function of anchor width** — 84000 anchors English to folios of about seven Degé
lines, and the chunk that matched is often smaller than that. The column is inversely
ordered by width across all three canons, exactly. Rule 69.

**So the 93.8% / 54.2% pair above should be read per canon, not pooled**: 54.2% is an
average of 79.0% and 8.5% and describes neither. Neither column supports a cross-canon
comparison, and they fail in opposite directions — work-level flatters Chinese (2 works,
against 8,442 Pāli ones), on-line penalises it (anchors twice the Pāli's width). What
stands: the Taishō is reachable in English for the first time, and remains, for practical
purposes, unreachable to a reader who does not already know the Chinese to search for.

### What it can do

Hybrid retrieval (lexical bigram fused with BGE-M3 by RRF), exhaustive survey, a citation
guard that byte-compares every quoted span, **17 read-only MCP tools**, and a six-screen
LiveView reader — including `/check`, where a person pastes a report and sees which of its
claims survive. **27,254 commentary lemmas** are aligned to the root lines they explain,
deterministically. English renderings are searchable by their own words.

**Start a session with `mix pramana.doctor`.** It prints which bake this is and whether it
still describes its inputs, what is loaded, what is declared and never acquired, and what is
missing — the state that was previously rediscovered with hand-written SQL. See
`docs/OBSERVABILITY.md` for what the running system can and cannot tell you about itself,
which as of the 2026-08-29 audit was *very little*, and now is five telemetry events, an Oban
failure handler and errors a model can branch on.

**Retrieval is measured against ground truth the corpus already holds.** `mix pramana.recall`
reads the 141,073 verbatim quotations as free relevance judgements: **100.0% over 1,891
decided pairs**, which bounds where retrieval failures can live — not in exact matching.
`--parallels` points the same trick at SuttaCentral's 10,493 Pāli↔Chinese parallels — the
axis `topical/chinese` has been 0% of twelve gold cases on.

**Its first published figure was withdrawn on 2026-08-29, the day it was published**, because
`--seed` did not work: `setseed` and the query it seeded ran on different pooled connections,
so three runs of one "reproducible" command gave cross-lingual 0.4%, 0.4% and 0.2% against
controls of 20.8%, 26.4% and 18.4%. Rule 67. The seeded measurement that replaced it reports
two numbers, because work-level scoring credits a hit anywhere in the right work:

| | found | on the parallel line |
|---|---|---|
| control (same language) | 26/125 · 20.8% | **11/125 · 8.8%** |
| cross-lingual | 2/497 · 0.4% | **2/497 · 0.4%** |
| cross vs same | 1.9% | **4.5%** |

**The barrier costs ~95% of achievable recall**, measured line to line — the 98% first
published came from a yardstick that work-level scoring had inflated 2.4×. Both cross-lingual
hits are genuine line-level matches, and both are Dhammapada verses. At a 0.4% rate a
500-case sample lands on 0, 1 or 2 hits without meaning anything, so this axis is read
control-relative and never by raw count. `docs/PLAN.md` § F.

The quotation figure above is drawn by the same sampling and was equally unseeded; 100.0% is
100% of whatever it drew, and the 1,891 is one draw's denominator.

**A report can now be checked, not just a quotation.** `verify_report` byte-compares every
citation in a document **and re-executes the searches its figures rest on** — "appears
36,775 times across 1,904 works" and "no Japanese-composed text uses X" are the claims that
carry a report, and a citation guard structurally cannot reach either. A replay recorded
against a different bake comes back `unverifiable`, never `failed`: the corpus changed, and
saying otherwise would teach people to ignore the checker.

**`mix pramana.verify --all` re-derives every one of 12,586,964 segments in 6m03s**, from
~26 minutes, and now prints its own coverage — `12586964 of 12586964 (every segment)`, or
`409790 of 444673 (92.2% — SAMPLED)` when it is not. It reports the denominator because for
a long time it did not: a green `verify OK` over 4,263 texts could mean 23% of them checked.
It works one source at a time even for `--all`, which is a measured decision and not a
preference — see `docs/PLAN.md` audit queue #11.

**A citation given as a RANGE can be diagnosed again.** `Corpus.resolve/1` has always
accepted ranges, because a range is a legitimate citation and a quoted passage is usually
longer than one printed line; `Corpus.context/2` did not, so `Guard.spans_boundary?` answered
"does not span a line boundary" for every ranged citation — the case where a quote most
likely does. Fixed 2026-08-29.

**The gate has a third data check.** `mix pramana.coherence` asks whether independently
derived facts about one work agree — `verify` proves determinism and `integrity` proves
fidelity, and both were green over the 122 works below. Four checks, 3 s, in the gate. Rates
and floors are computed; run it rather than quoting it.

**122 works stopped being Japanese on 2026-08-28.** They are Ming and Qing Chinese
compositions that Taishō volume numbering, applied to the 卍續藏 which does not use it, had
labelled `japanese` — an invariant #4 violation that `verify` and `integrity` were both
green over, because they were faithfully and reproducibly mislabelled. It was found by
setting the translator's birthplace against the origin of what they wrote. `pipeline_version`
is **5**. See `docs/PLAN.md` § A4, and § A5 for the check that would catch its family.

**Bylines resolve to people, and people to places.** 2,374 works carry a DILA authority id,
and through it dates, sect, recorded teachers and students, and a Wikidata q-id where one
exists. A `place_id` now resolves against **59,335 imported places**, giving both a modern
administrative path and the historical region — 江南東道 rather than 浙江省, which is the
unit a scholar means. 1,515
works can be filtered by period — as a **bound from the author's lifespan**, stamped
`date_basis: authority_lifespan`, answering *which century* and never *which year*. That
filter reads 1,515 works of 17,281 and says so on every use.

**Eval: 92.3% over 1,472 cases**, 0 stale, 0 errored — `evals/baseline.json` is the
published record and this line is copied from it. Not comparable with the earlier 93.1% over
1,400: the gold set grew by two new case types, one of which scores 70%. **Compare per row.**

### What it deliberately says it cannot do

Each of these was a silent gap until something made it visible, and each is now reported in
the API rather than left to be inferred from an empty result:

| gap | size |
|---|---|
| Taishō volumes 56–84 | 547 works — CBETA excludes them, only SAT publishes them, **blocked on an email** |
| CBETA collections absent | 10 of 26 |
| parallel graph openable | **6.1%** — 24,717 of 407,176; the rest name witnesses not held |
| texts a `role:` filter cannot reach | **1,640** — only the Taishō has a 部 division table |
| `topical/chinese` | **0%** — an English layer now exists over **54 sūtras of 4,263 works** and cannot compete corpus-wide |


### v1 is met, as written and as scoped

The definition in `docs/PLAN.md` — *a scholar or an LLM can ask a question of three canons,
receive passages byte-verifiable against a print edition, see the provenance of each, and
follow parallels and variants between them, with published numbers saying how often that
works* — is answered clause by clause there.

**Four things were then added to v1 by decision**, after that definition was written, and
**all four have now shipped**: lineage chains, Wikidata ids, place authority
(`docs/PLAN.md` § A3) and Phase 7's report verifier (§ H).

**This section said the opposite until 2026-08-31**, claiming place authority and the
report verifier were "designed and unbuilt" — while `docs/PLAN.md` marked both ▸ DONE on
2026-08-28 and two paragraphs of this same file described them working, 59,335 places and
all. A fifth correction of a published claim about our own state, and the first one caught
by reading STATUS against PLAN rather than against the code. **Read the two together when
either changes.**

Separately, **the phase-2 gate is not done** and is blocked on SAT's reply to a request
**sent 2026-08-15**, not on code and no longer on anyone here.

### Phases

**0, 1, 3, 4 complete and gated** (`phase-0`, `phase-1`, `phase-4`). **2** is the only
unfinished phase behind us and it waits on an email, not on code — #15 and #16 done, #14
blocked on SAT access, and the gate deliberately **not tagged** while a known gap stands.
**6** is under way: the quotation graph and commentary alignment ship; the rest does not.
**8** shipped early — the reader exists.

### The public artefact

`mix pramana.public.bake` builds a redistributable-only corpus into its own database —
13,017 texts, 1.8M segments, **0 CBETA** — verified by the bake and again at boot. Not
deployed anywhere; `docs/DEPLOY.md` has the hosting arithmetic.

## Open questions

- **BGE-M3 multi-vector in Nx** — port the two linear heads and drop the sidecar, or
  keep a bake-time sidecar? Decide in Phase 1 once dense works. *(Task #11)*
- ~~**Tibetan `botok`** has no Elixir/Rust equivalent, so the sidecar survives until at
  least Phase 5 regardless.~~ **Closed 2026-08-27, and it was never open in code.** Nothing
  imports `botok`; the syllable-window approach superseded it and four documents went on
  describing the dependency anyway — including `CLAUDE.md`, which a new session treats as
  binding and which was therefore standing invitation to add Python nobody needed. The
  sidecar's only remaining justification is the multi-vector question above.

---

## Metrics

| Gate | Tests | Recall@10 | Citation accuracy | Bake time | Segments |
|---|---|---|---|---|---|
| phase-0 | 148 | — | — | 62 ms (T0262 normalize) | 5,341 |
| task-10 | 175 | — | — | lexical query 5–40 ms | 5,341 |
| task-31 | 190 | — | — | outline 40 entries | 5,341 |
| **#9 full Taishō** | **227** | — | — | **190 s / 2,471 works** | **4,729,656** |
| #12 provenance | 257 | — | — | survey 88 ms exhaustive | 4,729,656 |
| #11 semantic (阿含部) | 284 | — | — | query 0.3–0.5 s; embed 1.29 chunks/s | 10,138 embedded |
| **#33 MCP resources + reader links** | **318** | — | — | hybrid search is now the MCP default | 10,138 embedded |
| **#13 Phase 1 gate** | **342** | — | verify --all + integrity green | **150 s / 2,471 works** | **4,740,246** |
| **#11 embeddings, full corpus** | **354** | — | — | embed 34 min / import 88 min | **299,317 chunks, 100% embedded** |
| **#15 provenance shape** | **377** | — | 3 origins in 3 labelled buckets | — | 299,317 chunks |
| **#17 Phase 2 gate** | **420** | — | licence filter now enforceable | import 88 → 38.7 min | 2,472 texts, 4,741,094 |
| **#36 work relations** | **444** | — | 89 commentary→root links | — | 2,472 texts |
| **#32 variant characters** | **465** | — | 众生 0 → 5 hits when expanded | — | 6,447 variant classes |
| **#34 glossary seed** | **483** | — | 10 rejected renderings, 1 unverified reading | — | 376 pinned terms |
| **#18a parallels** | **511** | — | sa1 → sn22.51 from curated data | import 29 s | 407,176 parallels, 3,064 anchors |
| **#38 Pāli root text** | **539** | — | verify --all + integrity green on 10,914 texts | ingest 53 s / 8,442 works | **10,914 texts, 5,185,767 segments** |
| **#39 translation pool + readings** | **582** | — | a generated rendering is rejected as source | translations ingest 4,996 files | **210,756 renderings, 8 translators, 4,601 shared anchors; 22 reading exceptions** |
| **#40 multi-vector + comparison tools** | **629** | — | an English query reaches a Pāli passage and cites the Pāli | chunk 84 s; embed 43,218 in ~5 min | **342,535 vectors: 300,165 source/lzh, 27,589 source/pli, 14,781 translation/en** |
| **#19 eval harness** | **651** | **65.3% @10** (zh **97.1** / pa 37.5) | **100%** verify + reject + provenance | evals 200 cases in 12 min | overall **87.0%**, 0 stale |
| **#21 Derge Kangyur ingest** | **870** | — | verify --source derge green on 1,195 texts; integrity closes to 69 bytes | ingest 4m35s / 103 volumes; verify 75 s | **12,109 texts, 5,647,069 segments; 1,195 Tibetan works, 75 spanning volumes** |
| **#21 84000 join** | **882** | — | an English folio resolves to the seven Tibetan lines it renders | ingest 36 s / 385 files | **30,653 renderings, 472 works, 478 titled; 7 volume groups refused** |
| **#21 Tibetan measured, three ways** | **909** | **retrieval@10 69.3%** (zh 97.1 / pa 55.0 / **bo 35.0**) | **100%** verify + reject + provenance | evals 249 cases in 15 min | overall **79.5%**, 0 stale; topical bo 0% — 95% of the Kangyur has no English layer |
| **#21 term anchors** | **952** | — | 59 of 60 three-way anchors reachable in both canons | glossary ingest 27 s / 396 files | **56,382 entries, 16,741 Skt / 25,524 Tib terms, 865 three-way; 2,756 divergent** |
| **#19 per_tradition decided** | **995** | **68.4% @10** under per_tradition (zh 97.8 / pa 42.7 / bo 21.9) vs **73.3%** default | **100%** verify + reject + provenance | full set **3h09m**; `--only topical` 5m22s | 1,400 cases, 0 stale; **opt-in confirmed** — 22 pinpoint cases lost for 2 topical; answered-from-any-canon 72.7% → 54.5% |
| **#10 the 41-second search** | **1042** | **retrieval@10 74.9%** (zh 97.8 / pa 54.7 / **bo 39.1**) | **100%** verify + reject + provenance | **full gate 3h08m -> 18m13s**; one search 41.1s -> 2.2s | 1,400 cases, **90.0%**, 0 stale, 0 errored; `texts.body` removed from 4 call sites |

| **audit: the seed, the guard, verify** | **1438** | unchanged | **no case type regressed over 1,472** | **gate 48m40s → 32m57s; `verify --all` ~26m → 6m03s** | 12,586,964 verified, every one |
| **English over Chinese · `/check`** | **1474** | unchanged | **every row identical to baseline, hit for hit** | gate **32m22s** — evals 21m14s, integrity 11m02s, verify 7m09s | 3,354 renderings anchored to Taishō lines; 191 vectors; `/check` is the sixth reader screen |

The `zh 98.7` in the `#19` row above was **corrected to 97.1** on 2026-08-22. It was a
by-tradition figure that silently included the 40 provenance cases, so its sub-rows did
not sum to their parent — the same error the README carried and had fixed in b22949a,
left standing here. Recall@10 rows in this table mix case types by design; read them with
the case counts in `evals/baseline.json` beside them.
