# Product strategy: Pramāṇa and Foundry

**Status:** proposed strategic baseline for operator review, 2026-09-15.
**Horizon:** product work after the Foundry repair backlog is accepted.
**Source baseline:** `713e8522e7028b767535695ffd6d1c4be1c89e29`.

This replaces the appended research notebook with a decision-oriented strategy. It
proposes direction, not shipped capabilities, budgets, implementation tickets or
permission to launch agents. The [repair plan](../foundry/docs/REPAIR-PLAN.md) and
[workflow contract](../foundry/docs/WORKFLOW-CONTRACT.md) retain execution authority.
[PLAN](PLAN.md) owns active work; [ROADMAP](ROADMAP.md) retains its existing phase
record. [PLAN's post-#17 reconciliation](PLAN.md#current-engineering-disposition--post-17-2026-09-16)
now checks the existing engineering baseline; it does not approve the pilot choices or
admit these strategic initiatives. V2 content identity is implemented, not immutable replay.

## The strategy in one page

**Build two independent products around evidence, not one universal agent platform.**
Pramāṇa helps people find, inspect and responsibly reuse Buddhist textual evidence.
Foundry helps an operator turn bounded software objectives into independently
checked, recoverable changes. Pramāṇa is Foundry's first demanding application,
not a permanent dependency or its only possible market.

The scarce resource is trustworthy progress per unit of human attention. More
corpus rows, agents, generated code or architectural layers are not progress unless
they improve a real research or engineering outcome.

| Choice | Proposed direction | Consequence |
|---|---|---|
| First Pramāṇa user | Teachers, writers and serious study leaders doing repeatable source work; scholars help evaluate accuracy | Validate a concrete research job before serving every persona equally |
| Initial product scope | One selected canon/collection per pilot workflow, with explicit scope selection | Keep existing multi-corpus infrastructure; defer automatic cross-canon synthesis |
| First complete experience | Question or quotation → scoped evidence → context and rendering → reusable citation | Improve the existing reader and MCP instead of rebuilding them around a chatbot |
| Trust promise | Show what was checked, against which source, and what remains uncertain | Byte matching is not doctrinal truth, interpretation, translation fidelity or exhaustive search |
| Foundry investment | Complete repair acceptance, then measure delivery and improve the demonstrated bottleneck | Do not rebuild a second kernel, budget system or verifier from essay-derived patterns |
| Long-term Foundry option | Portable standalone engineering system, proved on a second repository | Preserve independence now; delay multi-tenant platform work until demand is demonstrated |
| Research and dependencies | Borrow tested mechanisms; adopt packages only after bounded evaluation | No blanket adoption of a vendor's stack or benchmark claims |

The initial canon, pilot participants, effort allocation and operating budgets are
**open decisions**, not silently selected by this rewrite. A scoped pilot narrows
the new experience, not the stored corpus or existing users' access to supported tools.

## What makes this worth building

Pramāṇa's proposed advantage is the integrated path from an English question to
inspectable source context, provenance and a reusable evidence packet. Existing
archives, translators and model builders are potential complements, not inferior
systems to dismiss. Demand and advantage must be tested against the user's actual
archive-plus-search or model-assisted workflow. [Pramāṇa strategy](strategy/PRAMANA.md)
owns the customer, scope and trust contract.

Foundry's proposed advantage is controlled delivery with understandable failure and
recovery, across permitted providers, without requiring the operator to babysit
ordinary work. A multiplexer, model gateway or coding agent alone is not that
product. [Foundry strategy](strategy/FOUNDRY.md) owns the boundary and investment logic.

Both can accumulate useful assets: regression cases, source corrections, reviewed
rules and reliable workflows. This is a **compounding hypothesis**, not evidence
of an automatic moat or recursive model improvement.

## Sequence by evidence, not calendar promises

| Horizon | Question to resolve | Gate |
|---|---|---|
| H0 — repair acceptance | Can Foundry execute the agreed lifecycle safely, including recovery and authorized kernel repair? | Existing FR-22 evidence; no replacement checklist |
| H1 — choose and measure | Which research job and source scope warrant the next investment? What actually consumes operator time? | G1: pilot charter and baseline approved |
| H2 — complete one workflow | Can intended users independently find, inspect and reuse adequate evidence? | G2: observed task success and trust checks |
| H3 — repeat and improve | Do users return, and do selected Foundry improvements save net effort? | G3: repeat-use and engineering evidence |
| H4 — expand selectively | Which adjacent market or capability has earned investment? | G4: separate expansion decision for each product |

[Strategic roadmap](strategy/ROADMAP.md) defines gates and candidate initiatives.
These H/G identifiers are not the existing engineering phases or FR ticket numbers.
Foundry product discovery need not wait for Pramāṇa's commercial success; any second-
repository pilot does wait for repair acceptance and an explicit operator allocation.

## Non-goals for the first post-repair release

Do not pursue a universal Buddhist authority, an automatic doctrinal truth score,
a translation-model training program, a full-corpus OCR expansion, a generalized
memory SaaS, a new terminal multiplexer, or multiplayer translation rooms as launch
requirements. Preserve these as justified options where appropriate, not promises.
Do not introduce unrestricted production evaluation or weaken governance to reduce
tool count. Existing verified functionality is not removed just to narrow a pilot.

## Read only the chapter needed

| Need | Owner |
|---|---|
| Users, initial scope, UX, source and translation policy | [Pramāṇa](strategy/PRAMANA.md) |
| Repair handoff, autonomy, memory, providers and portability | [Foundry](strategy/FOUNDRY.md) |
| Horizons, dependencies, candidate initiatives and expansion gates | [Roadmap](strategy/ROADMAP.md) |
| Metrics, pilot design, experiment standards and sustainability | [Validation](strategy/VALIDATION.md) |
| Open choices and conversion into formal plans and tickets | [Decision and planning process](strategy/DECISIONS.md) |
| External sources, adoption policy and verification limits | [Research register](strategy/RESEARCH.md) |
| Where every original section went; contradictions resolved | [Reconciliation](strategy/RECONCILIATION.md) |

## How this becomes an execution plan

The operator reviews the choices and resolves the blocking decisions in the
[decision register](strategy/DECISIONS.md). After repair acceptance, PM rechecks
current source, open work and evidence, then elaborates only the next eligible
initiative. Approved changes update PLAN and the formal ROADMAP together. Research
notes and this strategy do not dispatch work, change budgets or authorize merges.

## Earlier section bookmarks

The original notebook remains available at its [immutable source revision](https://github.com/lorecrafting/pramana/blob/713e8522e7028b767535695ffd6d1c4be1c89e29/docs/PRODUCT_STRATEGY.md).
Principal section bookmarks below lead to their consolidated owners; detailed
historical claims are mapped in the reconciliation rather than copied into this page.

| Earlier section | Current owner |
|---|---|
| <a id="1-executive-summary--the-core-thesis"></a>1. Executive Summary & The Core Thesis | [Pramana](strategy/PRAMANA.md) |
| <a id="2-target-user-personas--jobs-to-be-done-jtbd"></a>2. Target User Personas & Jobs-to-be-Done (JTBD) | [Pramana](strategy/PRAMANA.md) |
| <a id="3-the-progressive-disclosure-ux-model"></a>3. The Progressive Disclosure UX Model | [Pramana](strategy/PRAMANA.md) |
| <a id="4-key-feature-specifications"></a>4. Key Feature Specifications | [Pramana](strategy/PRAMANA.md) |
| <a id="5-architectural-alignment-with-pramāṇa-umbrella"></a>5. Architectural Alignment with Pramāṇa Umbrella | [Pramana](strategy/PRAMANA.md) |
| <a id="6-systems-architecture-harness-graph-and-loop-engineering"></a>6. Systems Architecture: Harness, Graph, and Loop Engineering | [Foundry](strategy/FOUNDRY.md) |
| <a id="7-implementation-mechanism-the-composable-agent-middleware-pipeline-plug-for-agents"></a>7. Implementation Mechanism: The Composable Agent Middleware Pipeline ("Plug for Agents") | [Foundry](strategy/FOUNDRY.md) |
| <a id="8-the-4-layer-compounding-system-self-improving-agent-roadmap"></a>8. The 4-Layer Compounding System: Self-Improving Agent Roadmap | [Foundry](strategy/FOUNDRY.md) |
| <a id="9-the-elixir-vibe-ecosystem-beam-native-verification-anti-slop-linting--replay"></a>9. The Elixir Vibe Ecosystem: BEAM-Native Verification, Anti-Slop Linting & Replay | [Research](strategy/RESEARCH.md) |
| <a id="10-the-six-layer-agent-operating-system-harness-engineering-for-production-reliability"></a>10. The Six-Layer Agent Operating System: Harness Engineering for Production Reliability | [Foundry](strategy/FOUNDRY.md) |
| <a id="11-agent--scholar-memory-architecture-the-4-level-beam-memory-hierarchy"></a>11. Agent & Scholar Memory Architecture: The 4-Level BEAM Memory Hierarchy | [Foundry](strategy/FOUNDRY.md) |
| <a id="12-the-canonical-citation--exegetical-lineage-graph-subcommentaries-commentaries-and-root-sūtras"></a>12. The Canonical Citation & Exegetical Lineage Graph: Subcommentaries, Commentaries, and Root Sūtras | [Pramana](strategy/PRAMANA.md) |
| <a id="13-deep-analysis-of-mem0--native-tri-signal-memory-fusion-for-beam--postgresql-18"></a>13. Deep Analysis of Mem0 & Native Tri-Signal Memory Fusion for BEAM / PostgreSQL 18 | [Research](strategy/RESEARCH.md) |
| <a id="14-two-brains-two-architectures-the-decoupled-memory-divide"></a>14. Two Brains, Two Architectures: The Decoupled Memory Divide | [Foundry](strategy/FOUNDRY.md) |
| <a id="15-memory-is-the-wrong-abstraction-event-sourcing-read-time-compilation-and-context-asymmetry"></a>15. "Memory is the Wrong Abstraction": Event Sourcing, Read-Time Compilation, and Context Asymmetry | [Foundry](strategy/FOUNDRY.md) |
| <a id="16-ecosystem-positioning--integration-strategy-the-trusted-verification-consumer"></a>16. Ecosystem Positioning & Integration Strategy: The Trusted Verification Consumer | [Research](strategy/RESEARCH.md) |
| <a id="17-multiplayer-agent-harnesses--scoped-security-postures-lessons-from-ycs-qm"></a>17. Multiplayer Agent Harnesses & Scoped Security Postures: Lessons from YC's QM | [Research](strategy/RESEARCH.md) |
| <a id="18-empirical-loop-failure-modes--proactive-bounds-lessons-from-ial-scan--36000-repositories"></a>18. Empirical Loop Failure Modes & Proactive Bounds: Lessons from IAL-Scan & 36,000 Repositories | [Foundry](strategy/FOUNDRY.md) |
| <a id="19-prompt-for-multi-model-review"></a>19. Prompt for Multi-Model Review | [Decisions](strategy/DECISIONS.md) |
