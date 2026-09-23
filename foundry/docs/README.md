# Foundry documentation

Foundry is an independent OTP execution and governance system. [The overview](../README.md) describes
its implementation inventory and important containment limits. Neither a historical
review nor a model-free CI result establishes that live promotion or provider execution
is enabled.

Read the [strategy working summary](STRATEGY.md#working-summary) once for overall
direction: model-directed work under dependable authority, reused harnesses, independent
evidence and useful recovery. The strategy is context; the repair plan and workflow
contract still govern implementation.

## Start by the task

| Task | Read |
|---|---|
| Understand investment priorities or evaluate architecture/tooling | [Foundry strategy brief](STRATEGY.md), then the relevant governing repair contract |
| Understand Foundry's ecosystem position, what the kernel must own, and what should remain substitutable | [Ecosystem boundary and positioning](ECOSYSTEM-BOUNDARY.md), then [Foundry strategy](STRATEGY.md) and the governing workflow/repair contracts |
| Understand how Cloudflare/AX/Pi/Claude/Codex or another controller should drive Foundry without becoming authority | [Orchestrator boundary](ORCHESTRATOR-BOUNDARY.md), then [Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md), [Observability](OBSERVABILITY.md) and the governing workflow contract |
| Evaluate or implement the Pi replacement candidate and Claude-like ergonomics | [Pi harness design](PI-HARNESS.md), then the [checkpoint F feasibility record](fr-09/checkpoint-f-feasibility.md), its [independent blocker review](fr-09/checkpoint-f-review.md) and [independent correction PASS](fr-09/checkpoint-f-rereview.md), repair plan/workflow contract and affected FR-09/15a/18 requirements before implementation |
| Evaluate Jido/Jido.Harness/ACP before building a custom harness bridge | [Jido / Jido.Harness evaluation](JIDO-HARNESS.md), then [Pi harness design](PI-HARNESS.md), [Observability](OBSERVABILITY.md) and the same FR-09/15a/18 gates |
| Inspect the FR-15aA host/provisioning specification and executable inventory | [FR-15aA provisioning specification](fr-15a/provisioning-specification.md), its [machine-readable manifest](fr-15a/provisioning-manifest.exs), then the governing FR-15aB/FR-09 criteria; the specification enables no execution |
| Inspect the frozen FR-18A observation/query candidate | [FR-18A candidate and evidence](fr-18a/candidate.md), its [independent BLOCKER review](fr-18a/independent-review.md), [narrow correction rereview](fr-18a/correction-rereview.md), [final residual-B1 PASS](fr-18a/final-b1-rereview.md), the [bounded effect-query design](fr-18a/bounded-effect-query-design.md), [B5 implementation candidate](fr-18a/bounded-effect-query-candidate.md) [independent B5 BLOCKER review](fr-18a/b5-review.md) and the [B5 correction rereview PASS](fr-18a/b5-correction-rereview.md), then the governing FR-18A criteria and accepted FR-08A combined review; FR-18A remains blocked and this candidate enables no producer, activation or deployment |
| Resume active repairs | [Repair plan](REPAIR-PLAN.md), the current ticket's acceptance criteria and its referenced evidence |
| Implement FR-08B after its atomic prerequisite | [Command-ingress inventory and acceptance matrix](fr-08/fr08b-ingress-inventory.md), then the [atomic-composition diagnosis](fr-08/atomic-composition-diagnosis.md) and governing repair-plan section |
| Resolve FR-08B protected-result/domain binding | [Root-fact composition diagnosis](fr-08/fr08b-root-fact-composition-diagnosis.md), a proposed bounded interface correction with exact inspected revisions, then the [plan-binding implementation specification](fr-08/plan-binding-specification.md), the [replay revalidation design](fr-08/plan-replay-revalidation-design.md), its [frozen partial candidate](fr-08/plan-binding-candidate.md) and the [durable event vocabulary design](fr-08/event-vocabulary-design.md); none implements an end-to-end binding nor enables any execution |
| Understand current alignment, known source gaps and the FR-07→FR-08 disposition | [Independent alignment audit](ALIGNMENT-AUDIT-2026-09-19.md), then [repair plan](REPAIR-PLAN.md) and [FR-08 investigation](fr-08/investigation.md) |
| Inspect the exact disposition candidate and its independent verdict | [Candidate record](alignment-disposition-2026-09-19.md) and [Astra-high PASS](alignment-disposition-review-2026-09-19.md) |
| Inspect the H0 accepted-FR-07 boundary candidate and review | [H0 candidate](fr-08/h0-boundary-candidate.md) and [independent blocker review](fr-08/h0-boundary-review.md) |
| Understand execution authority | [Workflow contract](WORKFLOW-CONTRACT.md), then the applicable repair boundary |
| Review the frozen FR-08A atomic-composition correction | [Settlement-presence correction narrow PASS](fr-08/atomic-composition-presence-review.md), [prior presence BLOCKER](fr-08/atomic-composition-final-rereview.md), [earlier rereview](fr-08/atomic-composition-rereview.md) and [first review](fr-08/atomic-composition-review.md), each with exact candidate scope |
| Act on the positioning documentation merged in PRs #43–#46 | [Positioning audit](POSITIONING-AUDIT-2026-09-21.md) — fourteen obligations and eleven proposed edits against `d3e37183`, none applied; read it before extending `ORCHESTRATOR-BOUNDARY.md`, `CLOUDFLARE-OS.md`, `ECOSYSTEM-BOUNDARY.md`, `AX-SUBSTRATE.md` or `PLANNING-STRATEGIES.md` |
| Understand future project/role portability | [Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md), then the strategy and validation plan |
| Understand replaceable planning strategies, PM/Shaper responsibility, human work projections and workflow experiments | [Planning strategies](PLANNING-STRATEGIES.md), then [Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md), [Observability](OBSERVABILITY.md) and the governing strategy |
| Understand why repairs exist | [Architecture/lifecycle audit](AUDIT-2026-09-12.md) and its dated verification records |
| Inspect the durable store's actual tables, columns and constraints | [Generated schema reference](DURABLE-STORE-SCHEMA.md); it is generated from `database.ex` and a test fails if the two disagree, so prefer it over reading the schema by hand |
| Build or run model-free checks | [Independent CI](CI.md) and `ci/run.exs` |
| Review or resume FR-08B subcommit 1 (the pure kernel) | [Row-driven coverage design](fr-08/fr08b-row-driven-coverage.md) and [evidence tools](EVIDENCE-TOOLS.md), then the review record in order: [first findings](fr-08/fr08b-subcommit1-review-findings.md), [correction design](fr-08/fr08b-subcommit1-correction-design.md), [re-review briefing](fr-08/fr08b-subcommit1-rereview-briefing.md), [third briefing](fr-08/fr08b-subcommit1-review3-briefing.md), [fourth briefing](fr-08/fr08b-subcommit1-review4-briefing.md), [fourth findings](fr-08/fr08b-subcommit1-review4-findings.md) and the [second fourth-pass review of the evidence architecture](fr-08/fr08b-subcommit1-review4-sol-findings.md), then the [in-flight integration predicate briefing](fr-08/fr08b-integration-issued-review-briefing.md). Four independent reviews, four BLOCKs; the briefings carry what each one changed, and the two fourth-pass reviewers agreed on four things without seeing each other's work |
| Prepare FR-08B subcommit 2 (`decide/3` for the developer role) | [Reads inventory](fr-08/fr08b-subcommit2-reads-inventory.md) and [control/allocation inventory](fr-08/fr08b-subcommit2-control-inventory.md); both are bounded read-only inventories written before the interface froze, so confirm them against the current kernel before coding |
| Add or change a guard, transition, or a test that asserts a refusal | [Evidence tools](EVIDENCE-TOOLS.md); the gate enforces four of the five checks automatically, the guard mutation sweep is manual, and a green gate after adding a guard is not evidence the guard works |
| Observe the local system | [Observability](OBSERVABILITY.md), with the README's containment warnings |
| Evaluate the optional semantic assessor | [Assessor Stage A](ASSESSOR.md), issue #26 and the governing repair boundaries |
| Understand historical architecture choices | [Migration design](MIGRATION.md), [migration tickets](MIGRATION-TICKETS.md), [event sourcing](EVENT_SOURCING.md) |
| Plan FR-23 documentation retirement, or decide whether a Foundry document is evidence, current, superseded or retirable | [Documentation retirement inventory](DOC-RETIREMENT-INVENTORY-2026-09-22.md) — a classification of every file at `e374322b`, with grep evidence; it retired nothing and applied no banner |
| Inspect implementation history | [Implementation log](IMPLEMENTATION-LOG.md); use its reading route and active-ticket headings rather than preloading the append-only history |
| Review an agent assignment | The applicable [role documents](../../docs/README.md#foundry-role-contracts) and current workflow contract |

**The active repair plan, not the original eight-ticket migration sequence, owns
repair ordering.** A design-review approval applies to its named candidate; it is not
an endorsement of later revisions or evidence that a protected route is activated.
The plan contains 24 ticket nodes (FR-01–FR-23 plus FR-15a). FR-23 is a ticket covering
legacy retirement, module decomposition and hygiene; F23/F24 are audit findings routed to
existing owners. The `F` and `FR` prefixes distinguish findings from tickets. Its H0/F checkpoints and A/B slices do not form
a competing backlog.

## Provider and backend boundary

Shared repository instructions live in [AGENTS.md](../../AGENTS.md). They apply to
Claude, Gemini, DeepSeek, Codex and other providers. That neutrality does not relax
Foundry's launch policy, billing authorization, review identity or backend conformance.
Read the existing README and repair criteria before operating Herdr or any future adapter.

This documentation reorganization does not replace Herdr, enable automatic dispatch,
change launch profiles, promote an artifact or alter any repair ticket.

## Evidence and navigation

Dated audit, review, integration and attestation files are preserved as evidence, not
rewritten into one current narrative. Use [the complete documentation catalog](../../docs/CATALOG.md)
to find an individual record. One historical audit link points to a now-removed legacy
Python diagnostic; [the documentation audit](../../docs/audits/2026-09-15/README.md)
records that exception without rewriting the original evidence.

For current status, distinguish inspected source/containment from deployment truth. The
alignment audit did not inspect the loaded release; historical “live” statements and
component inventories therefore do not establish current wiring, activation or provider
execution. The [workflow contract's current-status route](WORKFLOW-CONTRACT.md) preserves
its dated design evidence while directing implementation to H0 and FR-08A/B.

[Repository map](../../docs/REPO_MAP.md) · [Shared workflow](../../docs/agents/WORKFLOW.md)
