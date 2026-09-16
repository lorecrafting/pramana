# Pramāṇa documentation

Pramāṇa is the umbrella in `pramana/`. Commands and backticked project paths in these
guides are relative to that directory unless stated otherwise. For shared workflow,
Foundry or product strategy use [the repository index](../../docs/README.md).

| Task | Read |
|---|---|
| Learn the project | [Product overview](../README.md), [primer](PRIMER.md), [architecture](ARCHITECTURE.md) |
| Set up or upgrade a checkout | [Development setup](DEV_ENV.md), [layout cutover](../../docs/LAYOUT_MIGRATION.md) |
| Query or read | [MCP](MCP.md), [reader](READER.md), [recorded status](STATUS.md) |
| Change source or retrieval behavior | [Invariants](INVARIANTS.md), [rules](RULES.md), [shared rule triggers](../../docs/agents/RULE_TRIGGERS.md) |
| Add sources | [Catalog](SOURCES.md), [ingestion](ADDING_TEXTS.md), [CLI](CLI.md) |
| Work with renderings or relationships | [Layers](LAYERS.md), [translation](TRANSLATION.md), [commentary](COMMENTARY.md) |
| Build, test or publish | [Shared code conventions](../../docs/agents/code-conventions/README.md), [language boundaries](ELIXIR.md), [checks](CHECKS.md), [deployment](DEPLOY.md) |
| Model or GPU work | [Embeddings](EMBEDDING.md), [GPU runbook](GPU_RUNBOOK.md), [cloud decisions](CLOUD.md) |
| Diagnose or understand past decisions | [Observability](OBSERVABILITY.md), [history](HISTORY.md), [proxy studies](PROXIES.md) |

[Shared testing](../../docs/TESTING.md) separates model-free, application, corpus
and live-provider evidence. The existing [active plan](../../docs/PLAN.md) and
[engineering phase record](../../docs/ROADMAP.md) remain shared pending their owners'
reconciliation; this source move does not renumber or complete their work.

[Evidence-integrity behavior](EVIDENCE_INTEGRITY.md) documents report statuses,
occurrence-safe repair, actual holdings, complete citation coordinates and release selection.
