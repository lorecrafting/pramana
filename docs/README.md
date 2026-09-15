# Documentation

Two systems, one repository. Start with the [repository map](REPO_MAP.md).
For model-assisted changes, [AGENTS.md](../AGENTS.md) routes every provider through
[the same workflow](agents/WORKFLOW.md); it is deliberately not a manual or eager reading list.

## Pramāṇa: learn and use

| Goal | Read |
|---|---|
| Understand the purpose and pipeline | [Primer chapters](PRIMER.md) and [current architecture](ARCHITECTURE.md) |
| Set up a development checkout | [Development environment](DEV_ENV.md) |
| Query the corpus | [MCP reference](MCP.md) or [human reader](READER.md) |
| Understand source and index gaps | [Recorded status](STATUS.md), then `mix pramana.doctor` against the intended database |
| Find an operating command | [CLI index](CLI.md); inspect the task before executing |
| Add a source or local text | [Source catalog](SOURCES.md), [adding texts](ADDING_TEXTS.md) |
| Understand rendering layers | [Layers](LAYERS.md), [translation](TRANSLATION.md), [commentary](COMMENTARY.md) |

## Pramāṇa: build and verify

| Work | Read |
|---|---|
| Change source/retrieval behavior | [Invariants](pramana/INVARIANTS.md), [architecture](ARCHITECTURE.md), [rule triggers](agents/RULE_TRIGGERS.md) |
| Write code | Applicable [conventions](CODE_CONVENTIONS.md), [language boundaries](ELIXIR.md) |
| Run checks | [Testing](TESTING.md), then [detailed check rationale](CHECKS.md) |
| Work on embeddings or batch inference | [Embeddings](EMBEDDING.md), [GPU runbook](GPU_RUNBOOK.md), [compute decisions](CLOUD.md) |
| Diagnose behavior | [Pramāṇa observability](OBSERVABILITY.md) |
| Expose a public service | [Deployment boundary](DEPLOY.md) |
| Change documentation | [Maintenance](MAINTAINING_DOCS.md) and [audit findings](audits/2026-09-15/README.md) |

## Foundry: execution and repair

Use [the Foundry index](../foundry/docs/README.md), not Pramāṇa's corpus commands.
[Foundry README](../foundry/README.md) states containment limits;
[REPAIR-PLAN](../foundry/docs/REPAIR-PLAN.md) and
[WORKFLOW-CONTRACT](../foundry/docs/WORKFLOW-CONTRACT.md) route current work.
[CI](../foundry/docs/CI.md) is independent and model-free. Historical migration and
review records remain evidence for their named candidates, not proof of current activation.

### Foundry role contracts

[Developer](../foundry/roles/developer.md) · [Reviewer](../foundry/roles/reviewer.md) ·
[PM](../foundry/roles/pm.md) · [Hardening PM](../foundry/roles/hardening_pm.md) ·
[Steerer](../foundry/roles/steerer.md)

These roles and existing Foundry documents were not changed by the documentation PR.
Repository provider-neutrality does not rewrite their launch/billing or repair contracts.

## Plans, research and historical evidence

[Plan navigation](PLAN_INDEX.md) opens specific sections of the unchanged shared
[plan](PLAN.md). [Roadmap](ROADMAP.md) describes phases, not runtime guarantees.
[Product strategy](PRODUCT_STRATEGY.md) is intentionally outside this audit's substantive scope.

[Model-reader alternatives](AGENT_MODELS.md), [harness proposals](HARNESS.md),
[ideas](IDEAS.md), [competitive research](COMPETITIVE.md) and the
[SAT correspondence draft](sat-request-email.md) are not executable commitments.

[History](HISTORY.md), [proxy studies](PROXIES.md), and retained historical/design
sections preserve their context and negative results. The [rule index](RULES.md)
keeps stable rule numbers while splitting the long bodies into focused pages.

## Complete catalog and audit trail

[Documentation catalog](CATALOG.md) lists the documentation paths. It is a lookup
reference, not something agents should preload. [The audit inventory](audits/2026-09-15/INVENTORY.md)
records the original files, treatment and verification limits.
