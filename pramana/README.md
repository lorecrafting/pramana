# Pramāṇa

This is the Pramāṇa project root (`pramana/` in the Git repository). Run the
commands below here. [Both products](../README.md) · [Topic index](docs/README.md).

Pramāṇa is an English-first, citation-grounded research substrate for Buddhist
texts. It retrieves original-language passages with provenance and checkable addresses,
keeps renderings distinct from source text, and provides deterministic citation checks.
A valid quotation does not by itself prove an interpretation or exhaustive corpus coverage.

Foundry is an independent sibling product, not part of this umbrella. Its
[overview and repair authority](../foundry/docs/README.md) are separate from the
research-product setup and commands here.

## Start here

| Reader | Entry point |
|---|---|
| Understand the repository | [Documentation index](../docs/README.md) and [system map](../docs/REPO_MAP.md) |
| Learn Pramāṇa from the ground up | [Chaptered primer](docs/PRIMER.md) |
| Set up Pramāṇa | [Development environment](docs/DEV_ENV.md) |
| Use research tools or the reader | [MCP](docs/MCP.md) and [reader](docs/READER.md) |
| Work on Foundry | [Foundry overview](../foundry/README.md) and [documentation](../foundry/docs/README.md) |
| Contribute with any model provider | [AGENTS.md](../AGENTS.md), the shared routing entry point |

## Pramāṇa's boundary

This project root is an Elixir/Phoenix umbrella with a PostgreSQL corpus, CJK Rust NIF,
standalone Rust text-reuse scanner and Python inference/training helpers.
The MCP surface is read-only; ingestion and other corpus mutations are CLI operations.
The reader has search, inventory, survey, passage, work and report-checking screens.
See the source-backed [architecture](docs/ARCHITECTURE.md), [CLI index](docs/CLI.md)
and [testing guide](../docs/TESTING.md), rather than duplicate tool/version counts here.

Source records cover Chinese, Pāli and Tibetan material, but neither corpus nor index
coverage is complete. [STATUS.md](docs/STATUS.md) contains generated figures from the
recorded database snapshot. Those figures and previously recorded evaluation outcomes
were **not** re-measured by the documentation audit. `mix pramana.doctor` and the
appropriate corpus checks report the state of the database actually connected.

`bake_id` identifies declared source inputs; the implemented retrieval stamp has
[count-based limitations](docs/ARCHITECTURE.md#identity-and-replay). This is not an
immutable, coexistent-snapshot database or a guarantee of identical search replay.

## Data and publication

**Publish the pipeline, not an assumed right to redistribute every ingested source.**
Sources and translations have distinct license metadata. `raw/` and live runtime state
are not tracked. A public deployment needs the intended dataset, verified permissions
and the [public deployment checks](docs/DEPLOY.md).

[Documentation audit and limitations](../docs/audits/2026-09-15/README.md)
