# Documentation

Two systems in sibling project directories, one repository. Start with the [repository map](REPO_MAP.md).
See [the structure review](REPOSITORY_STRUCTURE.md) for current ownership and the
proposed sibling-project layout after repair acceptance.
For existing checkouts, read [cutover and rollback](LAYOUT_MIGRATION.md).
Pramāṇa references are in [its own index](../pramana/docs/README.md).
For model-assisted changes, [AGENTS.md](../AGENTS.md) routes every provider through
[the same workflow](agents/WORKFLOW.md); it is deliberately not a manual or eager reading list.

## Pramāṇa: learn and use

| Goal | Read |
|---|---|
| Understand the purpose and pipeline | [Primer chapters](../pramana/docs/PRIMER.md) and [current architecture](../pramana/docs/ARCHITECTURE.md) |
| Set up a development checkout | [Development environment](../pramana/docs/DEV_ENV.md) |
| Query the corpus | [MCP reference](../pramana/docs/MCP.md) or [human reader](../pramana/docs/READER.md) |
| Understand source and index gaps | [Recorded status](../pramana/docs/STATUS.md), then `mix pramana.doctor` against the intended database |
| Find an operating command | [CLI index](../pramana/docs/CLI.md); inspect the task before executing |
| Add a source or local text | [Source catalog](../pramana/docs/SOURCES.md), [adding texts](../pramana/docs/ADDING_TEXTS.md) |
| Understand rendering layers | [Layers](../pramana/docs/LAYERS.md), [translation](../pramana/docs/TRANSLATION.md), [commentary](../pramana/docs/COMMENTARY.md) |

## Pramāṇa: build and verify

| Work | Read |
|---|---|
| Change source/retrieval behavior | [Invariants](../pramana/docs/INVARIANTS.md), [architecture](../pramana/docs/ARCHITECTURE.md), [rule triggers](agents/RULE_TRIGGERS.md) |
| Write code | [Code-convention router](agents/code-conventions/README.md), then only the applicable language/framework files; [language boundaries](../pramana/docs/ELIXIR.md) |
| Run checks | [Testing](TESTING.md), then [detailed check rationale](../pramana/docs/CHECKS.md) |
| Work on embeddings or batch inference | [Embeddings](../pramana/docs/EMBEDDING.md), [GPU runbook](../pramana/docs/GPU_RUNBOOK.md), [compute decisions](../pramana/docs/CLOUD.md) |
| Diagnose behavior | [Pramāṇa observability](../pramana/docs/OBSERVABILITY.md) |
| Expose a public service | [Deployment boundary](../pramana/docs/DEPLOY.md) |
| Change documentation | [Maintenance](MAINTAINING_DOCS.md) and [audit findings](audits/2026-09-15/README.md) |

## Foundry: execution and repair

Use [the Foundry index](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/README.md), not Pramāṇa's corpus commands.
[Foundry README](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/README.md) states containment limits;
[REPAIR-PLAN](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/REPAIR-PLAN.md) and
[WORKFLOW-CONTRACT](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/WORKFLOW-CONTRACT.md) route current work.
[The 2026-09-19 independent alignment audit](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/ALIGNMENT-AUDIT-2026-09-19.md)
records current-source gaps and the accepted FR-07/FR-08 sequencing disposition without
becoming another backlog.
[CI](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/docs/CI.md) is independent and model-free. Historical migration and
review records remain evidence for their named candidates, not proof of current activation.

### Foundry role contracts

[Developer](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/roles/developer.md) · [Reviewer](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/roles/reviewer.md) ·
[PM](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/roles/pm.md) · [Hardening PM](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/roles/hardening_pm.md) ·
[Steerer](https://github.com/lorecrafting/pramana/blob/e1e4b3bf2c666f5d84652758afee446a0b21ebe1/foundry/roles/steerer.md)

These roles and existing Foundry documents were not changed by the documentation PR.
Repository provider-neutrality does not rewrite their launch/billing or repair contracts.

## Plans, research and historical evidence

[Plan navigation](PLAN_INDEX.md) opens specific sections of the unchanged shared
[plan](PLAN.md). [Roadmap](ROADMAP.md) describes phases, not runtime guarantees.
[Product strategy](PRODUCT_STRATEGY.md) proposes the post-repair direction for both systems.
Its [strategic roadmap](strategy/ROADMAP.md), [decision register](strategy/DECISIONS.md) and
[research register](strategy/RESEARCH.md) inform later planning; they do not admit tickets
or supersede Foundry repair authority.

[Model-reader alternatives](../pramana/docs/AGENT_MODELS.md), [harness proposals](../pramana/docs/HARNESS.md),
[ideas](../pramana/docs/IDEAS.md), [competitive research](../pramana/docs/COMPETITIVE.md) and the
[SAT correspondence draft](../pramana/docs/sat-request-email.md) are not executable commitments.

[History](../pramana/docs/HISTORY.md) and [proxy studies](../pramana/docs/PROXIES.md) retain incident context and
negative results. Superseded guide copies and unreferenced experiments are indexed
in [retired files](RETIRED_FILES.md), with immutable Git-history recovery links. The [rule index](../pramana/docs/RULES.md)
keeps stable rule numbers while splitting the long bodies into focused pages.

## Complete catalog and audit trail

[Documentation catalog](CATALOG.md) lists the documentation paths. It is a lookup
reference, not something agents should preload. [The audit inventory](audits/2026-09-15/INVENTORY.md)
records the original files, treatment and verification limits.
