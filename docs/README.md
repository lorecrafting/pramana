# Documentation

Commands and backticked paths in these docs are relative to the repository root.
Start with the [repository map](REPO_MAP.md).
For model-assisted changes, [AGENTS.md](../AGENTS.md) routes every provider through
[the same workflow](agents/WORKFLOW.md); it is deliberately not a manual or eager reading list.

## Pramāṇa: learn and use

| Goal | Read |
|---|---|
| Understand the purpose and pipeline | [Primer chapters](PRIMER.md) and [current architecture](ARCHITECTURE.md) |
| Set up a development checkout | [Development environment](DEV_ENV.md) |
| Query the corpus | [MCP reference](MCP.md), [human reader](READER.md), [report-check admission](REPORT_CHECK_ADMISSION.md) and [evidence-integrity behavior](EVIDENCE_INTEGRITY.md) |
| Understand source and index gaps | [Recorded status](STATUS.md), then `mix pramana.doctor` against the intended database |
| Find an operating command | [CLI index](CLI.md); inspect the task before executing |
| Add a source or local text | [Source catalog](SOURCES.md), [adding texts](ADDING_TEXTS.md) |
| Understand rendering layers | [Layers](LAYERS.md), [translation](TRANSLATION.md), [commentary](COMMENTARY.md) |

## Pramāṇa: build and verify

| Work | Read |
|---|---|
| Change source/retrieval behavior | [Invariants](INVARIANTS.md), [architecture](ARCHITECTURE.md), [rules](RULES.md), [rule triggers](agents/RULE_TRIGGERS.md) |
| Write code | [Code-convention router](agents/code-conventions/README.md), then only the applicable language/framework files; [language boundaries](ELIXIR.md) |
| Run checks | [Testing](TESTING.md), then [detailed check rationale](CHECKS.md) |
| Work on embeddings or batch inference | [Embeddings](EMBEDDING.md), [GPU runbook](GPU_RUNBOOK.md), [compute decisions](CLOUD.md) |
| Diagnose behavior | [Pramāṇa observability](OBSERVABILITY.md) |
| Expose a public service | [Deployment boundary](DEPLOY.md) |
| Change documentation | [Maintenance](MAINTAINING_DOCS.md) |

## Plan, strategy and Foundry

The [plan](PLAN.md) lists open work. The [phase record](ROADMAP.md) describes phases, not
runtime guarantees. [Product strategy](PRODUCT_STRATEGY.md) proposes the post-repair
direction; its [strategic roadmap](strategy/ROADMAP.md), [decision register](strategy/DECISIONS.md),
[research register](strategy/RESEARCH.md) and pilot documents inform planning but admit no tickets.

Foundry lives in [lorecrafting/foundry](https://github.com/lorecrafting/foundry). Pramāṇa's one dependency on it, the
`foundry_g0` pilot gate, is described in [the strategy](PRODUCT_STRATEGY.md#dependency-on-foundry).

## Research and historical evidence

[Model-reader alternatives](AGENT_MODELS.md), [harness proposals](HARNESS.md),
[ideas](IDEAS.md), [competitive research](COMPETITIVE.md) and the
[SAT correspondence draft](sat-request-email.md) are not executable commitments.

[History](HISTORY.md) and [proxy studies](PROXIES.md) retain incident context and
negative results. Retired documents, scripts and experiments are indexed
in [retired files](RETIRED_FILES.md), with pinned recovery links. The [rule index](RULES.md)
keeps stable rule numbers while splitting the long bodies into focused pages.

## Complete catalog

[Documentation catalog](CATALOG.md) lists the documentation paths. It is a lookup
reference, not something agents should preload.
