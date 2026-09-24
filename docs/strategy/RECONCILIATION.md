# Strategy reconciliation: what changed and why

[Strategy overview](../PRODUCT_STRATEGY.md) · [Research register](RESEARCH.md)
**Input:** the complete 1,529-line, 19-section strategy notebook at
[`713e8522e7028b767535695ffd6d1c4be1c89e29`](https://github.com/lorecrafting/pramana/blob/713e8522e7028b767535695ffd6d1c4be1c89e29/docs/PRODUCT_STRATEGY.md).
Its original wording and detailed subsections remain in Git; they are not duplicated
as another current strategy. This rewrite does not claim every external assertion
was independently verified or that the proposed strategy has achieved market fit.

## Diagnosis

The notebook's central ideas were useful, but append order had become apparent
priority. Repeated harness and memory taxonomies looked like separate engineering
commitments. Proposed schemas, numeric targets, vendor capabilities and existing
features were mixed with no consistent evidence level. The strategy needed fewer
independent bets, a first user/job, explicit tradeoffs and stop conditions.

The synthesis keeps two distinct product ambitions and one evidence-first principle.
It changes the unit of planning from “adopt another architecture” to “improve a
measurable research or delivery outcome.” It does not reduce Foundry to a minor
Pramāṇa utility or require an elaborate platform before the first product test.

## Disposition of every original section

| Original section | Disposition and current owner |
|---|---|
| 1. Executive summary/core thesis | Preserve evidence-first English access; replace universal authority and unsupported competitor claims. [Pramāṇa](PRAMANA.md) |
| 2. Personas/JTBD | Retain three audiences, prioritize a repeatable teacher/writer/study job as a hypothesis. [Pramāṇa](PRAMANA.md#customer-and-job) |
| 3. Progressive disclosure | Merge into one scoped find/inspect/assess/reuse workflow. [Pramāṇa](PRAMANA.md#one-complete-workflow) |
| 4. Feature specifications | Combine evidence canvas, inspector and export; narrow checker verdicts; defer large glossary/graph/collaboration expansion. [Roadmap](ROADMAP.md) |
| 5. Architectural alignment | Replace speculative module mappings with current reference links and missing-behavior checks. [Pramāṇa](PRAMANA.md), [Architecture](../../pramana/docs/ARCHITECTURE.md) |
| 6. Harness/graph/loop | Consolidate responsibilities; do not assert implemented multi-canon fan-out or immutable retrieval state. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md#one-operating-model-not-several-overlapping-stacks) |
| 7. Composable middleware | Retain modularity, but subordinate it to accepted authority; treat stream checks/compaction as candidates. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md), I-P2/I-F1 |
| 8. Four-layer compounding | Fold into verified lessons and independent acceptance; remove unsupported active/shipped labels. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md), [Validation](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/VALIDATION.md) |
| 9. Elixir Vibe/AST/replay | Keep bounded tooling experiments; remove blanket adoption, unsafe eval shortcut and unmeasured savings. [Research](RESEARCH.md#adopt-principles-evaluate-implementations), I-F2 |
| 10. Six-layer agent OS | Use one review vocabulary and existing repair interfaces; correct the efficiency metric. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md), [Validation](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/VALIDATION.md) |
| 11. Shared four-level memory | Preserve selective context, reject shared Foundry/corpus infrastructure. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md#memory-evidence-first-projections-second), I-P5 |
| 12. Citation/exegetical graph | Retain typed lineage exploration; require evidence for direction, coverage and limits. [Pramāṇa](PRAMANA.md#depth-only-when-it-helps-the-task), I-P4 |
| 13. Mem0/native memory fusion | Retain attributable records and retrieval experiments; reject proposed Foundry `Pramana.Repo`/pgvector coupling and default-verified facts. [Research](RESEARCH.md), [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md) |
| 14. Two independent brains | Make the independence authoritative; replace zero-dependency/latency claims with actual repair contracts. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md#mission-and-boundary) |
| 15. Event sourcing/read-time compilation | Resolve the summary contradiction: retain required evidence, allow replaceable projections, enforce privacy/retention. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md#memory-evidence-first-projections-second) |
| 16. Ecosystem/ingestion | Preserve complementarity and human scholarship; correct BDRC release assumption and qualify stakeholder claims. [Research](RESEARCH.md#buddhist-sources-and-stakeholders), I-P6 |
| 17. QM/multiplayer | Separate security from sharing; retain scoped promotion, defer collaboration until real demand. [Research](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/RESEARCH.md#engineering-sources), I-P7 |
| 18. Loop bounds/coordination | Reuse repaired ledger/lifecycle; distinguish healthy idle from productive success; allow safe non-success stops. [Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md#providers-budgets-and-recovery) |
| 19. Sixteen-part review prompt | Replace repetitive architecture endorsement with decisions, falsification and ticket readiness. [Decisions](DECISIONS.md#review-prompt-and-maintenance) |

## Contradictions resolved rather than preserved in parallel

| Earlier tension | Resolution |
|---|---|
| All canons at once versus a tractable launch | Recommend one scoped pilot, keep existing multi-corpus assets, gate automatic cross-canon synthesis separately |
| Shared Postgres Foundry memory versus standalone Foundry | Accepted local authority contract wins; no shared Repo or corpus service dependency |
| Lossless summary versus never summarize | Summaries are lossy/rebuildable projections, not sole evidence or authority |
| “Save everything” versus secure bounded operation | Retain required evidence under access/retention rules; exclude unnecessary secrets/private content |
| Few tools versus unlimited runtime evaluation | Small interfaces are desirable; arbitrary privileged evaluation is not |
| Run until tests pass versus bounded autonomous execution | Pass is one terminal outcome; blocked/cancelled/exhausted outcomes preserve evidence without false success |
| Root-text badge versus doctrinal truth | Separate textual match, provenance, rendering quality, interpretation and scope |
| Silent text reuse versus proven quotation direction | Matching establishes reuse evidence, not causality/chronology by itself |
| Independent reviewer versus reviewer starvation | Exclude maker authority, not necessary source, contract and raw evidence |
| No human intervention versus protected-root ownership | Retain authorized autonomous kernel/runtime repair; root/policy changes remain operator-owned |
| Provider agnosticism versus paid automatic fallback | Shared guidance does not widen eligibility or spending; current manual paid-use rule remains |
| BDRC February announcement versus a ready dataset | Require a real released artifact and its permissions before planning ingestion |
| Vendor memory/AST/replay claims versus local acceptance | Record source limits; test one implementation and benefit at a time |

## Corrections to implementation language

The current [architecture](../../pramana/docs/ARCHITECTURE.md) distinguishes input bake identity
from mutable loaded state. PR #17 subsequently added v2 content-based retrieval stamps;
that does not freeze historical rows, code or defaults. Do not advertise immutable replay
from those IDs alone. The current citation guard checks recognized quotations and
URN existence; it is not a clause-level doctrinal fact checker. Original `urn:cts:`
examples are not the repository's implemented `pramana:` grammar.

The [Rust quotation implementation](../../pramana/native/quotations) is described in the
current architecture as seed-and-extend, not the notebook's asserted suffix-array
production path. Proposed `passage_citations`, `UserTrail`, direct Foundry Ecto
memory and automatic multi-canon orchestration are not accepted as existing code
by this strategy. Module/table names belong in subsequent inspected designs, not
speculative product capability tables. Corpus counts remain in their owning snapshot.

## Scope protection and verification limits

The original 2026-09-15 strategy rewrite changed strategy and navigation only. Foundry
files, PLAN, the formal ROADMAP, application code, schemas, lockfiles, roles and runtime
policies were not edited by that rewrite. Repair context informs dependency mapping; it is not a repair review
or a fresh production acceptance. The previous documentation audit's exclusion of
product strategy remains true for that earlier audit and is not rewritten retroactively.

All 19 original sections were read and given a disposition. Selected primary
sources were checked where they materially affect the strategy; inaccessible or
incomplete trails are identified in the research register. No customer interviews,
new retrieval measurements, model runs, billing changes or partner approvals occurred.
Structural documentation checks are separate from acceptance of the strategy itself.
