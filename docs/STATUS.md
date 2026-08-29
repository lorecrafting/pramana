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
| Pāli (SuttaCentral) | 8,442 works, 241,409 English renderings by 7 translators |
| Tibetan (Degé) | 1,195 Kangyur · 3,380 Tengyur |
| chunks · vectors | 980,464 · **1,037,264** |
| pipeline | v4 · `mix pramana.verify --all` and `mix pramana.integrity` both green over every text |

### What it can do

Hybrid retrieval (lexical bigram fused with BGE-M3 by RRF), exhaustive survey, a citation
guard that byte-compares every quoted span, **16 read-only MCP tools**, and a five-screen
LiveView reader. **27,254 commentary lemmas** are aligned to the root lines they explain,
deterministically. English renderings are searchable by their own words.

**Bylines resolve to people.** 2,374 works carry a DILA authority id, and through it dates,
sect, place, recorded teachers and students, and a Wikidata q-id where one exists. 1,515
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
| `topical/chinese` | **0%** — no English layer over Chinese, and the deterministic bridge was tried and rejected |


### v1 as written is met; v1 as scoped is not

The definition in `docs/PLAN.md` — *a scholar or an LLM can ask a question of three canons,
receive passages byte-verifiable against a print edition, see the provenance of each, and
follow parallels and variants between them, with published numbers saying how often that
works* — is answered clause by clause there.

**Four things were then added to v1 by decision**, after that definition was written. Two
shipped (lineage chains, Wikidata ids). **Two are designed and unbuilt: place authority
(`docs/PLAN.md` § A3) and Phase 7's report verifier (§ H).** So the honest current answer to
"is v1 done" is **no**, and the reason is a scope decision rather than a slip.

Separately, **the phase-2 gate is not done** and is blocked on an email a person must send,
not on code.

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

The `zh 98.7` in the `#19` row above was **corrected to 97.1** on 2026-08-22. It was a
by-tradition figure that silently included the 40 provenance cases, so its sub-rows did
not sum to their parent — the same error the README carried and had fixed in b22949a,
left standing here. Recall@10 rows in this table mix case types by design; read them with
the case counts in `evals/baseline.json` beside them.
