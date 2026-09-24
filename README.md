# Pramāṇa

An English-first, citation-grounded research substrate for Buddhist texts. It retrieves
original-language passages with provenance and checkable addresses, keeps renderings
distinct from source text, and provides deterministic citation checks. A valid quotation
does not by itself prove an interpretation or exhaustive corpus coverage.

Foundry, which shared this repository until 2026-09-23, now lives in
[lorecrafting/foundry](https://github.com/lorecrafting/foundry). Its pre-split history remains here.

## Start here

| Reader | Entry point |
|---|---|
| Understand the repository | [Documentation index](docs/README.md) and [repository map](docs/REPO_MAP.md) |
| Learn Pramāṇa from the ground up | [Chaptered primer](docs/PRIMER.md) |
| Set up a checkout | [Development environment](docs/DEV_ENV.md) |
| Use research tools or the reader | [MCP](docs/MCP.md) and [reader](docs/READER.md) |
| Contribute with any model provider | [AGENTS.md](AGENTS.md), the shared routing entry point |

## Development entry points

```bash
mise install
mix deps.get
mix test                                  # needs PostgreSQL + extensions and Rust
elixir bin/check_docs.exs                 # repository checks; no Mix deps, corpus or provider
docker build -t pramana:local .
```

Database setup is an explicit operation; follow [setup](docs/DEV_ENV.md). The corpus
(`raw/`), model weights, virtualenv and local source text are ignored and never committed.
Do not run `git clean -fdx`: it deletes them.

## What it is

An Elixir/Phoenix umbrella with a PostgreSQL corpus, CJK Rust NIF, standalone Rust
text-reuse scanner and Python inference/training helpers. The MCP surface is read-only;
ingestion and other corpus mutations are CLI operations. The reader has search, inventory,
survey, passage, work and report-checking screens. See the source-backed
[architecture](docs/ARCHITECTURE.md), [CLI index](docs/CLI.md) and
[testing guide](docs/TESTING.md) rather than duplicate tool/version counts here.

Source records cover Chinese, Pāli and Tibetan material, but neither corpus nor index
coverage is complete. [STATUS.md](docs/STATUS.md) contains generated figures from the
recorded database snapshot. `mix pramana.doctor` and the corpus checks report the state
of the database actually connected.

`bake_id` identifies declared source inputs and `release_id` the stored renderings and
vectors; see [identity and replay](docs/ARCHITECTURE.md#identity-and-replay). Neither is
an immutable snapshot or a guarantee of identical search replay.

## Data and publication

**Publish the pipeline, not an assumed right to redistribute every ingested source.**
Sources and translations have distinct license metadata. `raw/` and live runtime state
are not tracked. A public deployment needs the intended dataset, verified permissions
and the [public deployment checks](docs/DEPLOY.md).
