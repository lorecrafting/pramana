# Documentation

Pramāṇa's product references are in [its own index](../pramana/docs/README.md); this
index adds the plan, strategy, testing and repository docs. Start with the
[repository map](REPO_MAP.md).
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
| Change documentation | [Maintenance](MAINTAINING_DOCS.md) |

## Plan, strategy and Foundry

The [plan](PLAN.md) lists open work. The [phase record](ROADMAP.md) describes phases, not
runtime guarantees. [Product strategy](PRODUCT_STRATEGY.md) proposes the post-repair
direction; its [strategic roadmap](strategy/ROADMAP.md), [decision register](strategy/DECISIONS.md),
[research register](strategy/RESEARCH.md) and pilot documents inform planning but admit no tickets.

Foundry lives in [lorecrafting/foundry](https://github.com/lorecrafting/foundry). Pramāṇa's one dependency on it, the
`foundry_g0` pilot gate, is described in [the strategy](PRODUCT_STRATEGY.md#dependency-on-foundry).

## Research and historical evidence

[Model-reader alternatives](../pramana/docs/AGENT_MODELS.md), [harness proposals](../pramana/docs/HARNESS.md),
[ideas](../pramana/docs/IDEAS.md), [competitive research](../pramana/docs/COMPETITIVE.md) and the
[SAT correspondence draft](../pramana/docs/sat-request-email.md) are not executable commitments.

[History](../pramana/docs/HISTORY.md) and [proxy studies](../pramana/docs/PROXIES.md) retain incident context and
negative results. Retired documents, scripts and experiments are indexed
in [retired files](RETIRED_FILES.md), with pinned recovery links. The [rule index](../pramana/docs/RULES.md)
keeps stable rule numbers while splitting the long bodies into focused pages.

## Complete catalog

[Documentation catalog](CATALOG.md) lists the documentation paths. It is a lookup
reference, not something agents should preload.
