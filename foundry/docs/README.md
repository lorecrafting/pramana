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
| Evaluate or implement the Pi replacement candidate and Claude-like ergonomics | [Pi harness design](PI-HARNESS.md), then the repair plan/workflow contract and affected FR-09/15a/18 requirements before implementation |
| Resume active repairs | [Repair plan](REPAIR-PLAN.md), the current ticket's acceptance criteria and its referenced evidence |
| Understand current alignment, known source gaps and the FR-07→FR-08 disposition | [Independent alignment audit](ALIGNMENT-AUDIT-2026-09-19.md), then [repair plan](REPAIR-PLAN.md) and [FR-08 investigation](fr-08/investigation.md) |
| Understand execution authority | [Workflow contract](WORKFLOW-CONTRACT.md), then the applicable repair boundary |
| Understand future project/role portability | [Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md), then the strategy and validation plan |
| Understand why repairs exist | [Architecture/lifecycle audit](AUDIT-2026-09-12.md) and its dated verification records |
| Build or run model-free checks | [Independent CI](CI.md) and `ci/run.exs` |
| Observe the local system | [Observability](OBSERVABILITY.md), with the README's containment warnings |
| Evaluate the optional semantic assessor | [Assessor Stage A](ASSESSOR.md), issue #26 and the governing repair boundaries |
| Understand historical architecture choices | [Migration design](MIGRATION.md), [migration tickets](MIGRATION-TICKETS.md), [event sourcing](EVENT_SOURCING.md) |
| Inspect implementation history | [Implementation log](IMPLEMENTATION-LOG.md); dates and candidate identities matter |
| Review an agent assignment | The applicable [role documents](../../docs/README.md#foundry-role-contracts) and current workflow contract |

**The active repair plan, not the original eight-ticket migration sequence, owns
repair ordering.** A design-review approval applies to its named candidate; it is not
an endorsement of later revisions or evidence that a protected route is activated.
The plan contains 23 ticket nodes (FR-01–FR-22 plus FR-15a); F23/F24 are findings routed
to existing owners, not missing tickets. Its H0/F checkpoints and A/B slices do not form
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
