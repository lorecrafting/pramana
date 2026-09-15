# Recorded status details — chapter 4

> Recorded repository snapshot; corpus figures and runtime outcomes were not re-measured in this documentation audit.
> [Contents](../DETAILS.md) · [Documentation](../../README.md) · [Current architecture](../../ARCHITECTURE.md)

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
  sidecar's only remaining justification is the multi-vector question above. **Superseded
  a second time on 2026-09-02**: the sidecar now also runs generation for § E1, so it
  survives on that alone and the boundary was restated as *inference only, no domain
  logic* — `docs/ELIXIR.md` § 3.
- **Direction in the quotation graph resolves 20.2% of pairs**, from `text_role` and
  `date_start`, and every demand estimate rests on that fifth. **The obvious way to close
  it was measured and rejected**: citation markers (`經云`, `論曰`, `頌曰`) direct only 287
  of 48,650 pairs, 34× weaker, because the edges are mostly not citations at all — shared
  text between canonical works is usually formulaic phrasing or two renderings of one
  Indic original. `docs/PROXIES.md`. A better demand signal has to come from somewhere
  else: what readers ask, or `work_relations`. Rule 72.
- **705 Tengyur works have no title in any form** — no block in the edition, mostly
  continuations of a work spanning volumes. Closing it needs the Degé *dkar chag* or BDRC
  metadata, which is a new source with its own licence question.

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
| **English over Chinese · `/check` · architecture boundaries** | **1479** | unchanged | **every row identical to baseline, hit for hit** | gate **32m22s** — evals 21m14s, integrity 11m02s, verify 7m09s | 3,354 renderings anchored to Taishō lines; 191 vectors; `/check` is the sixth reader screen |

The `zh 98.7` in the `#19` row above was **corrected to 97.1** on 2026-08-22. It was a
by-tradition figure that silently included the 40 provenance cases, so its sub-rows did
not sum to their parent — the same error the README carried and had fixed in b22949a,
left standing here. Recall@10 rows in this table mix case types by design; read them with
the case counts in `evals/baseline.json` beside them.
