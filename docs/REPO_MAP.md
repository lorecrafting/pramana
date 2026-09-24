# Repository map

One product, Pramāṇa, under `pramana/`. The Git root holds repository tooling and
shared docs; it is **not** a Mix project. [Documentation](README.md).

## Pramāṇa: umbrella project

Work in `pramana/` or use `bin/pramana-mix` from the Git root.

| Location | Role |
|---|---|
| `pramana/mix.exs`, `mix.lock`, `config/`, `rel/` | Pramāṇa build/dependency/configuration/release root |
| `pramana/apps/pramana/` | Corpus domain, acquisition, citation, provenance, retrieval and evaluation |
| `pramana/apps/pramana_web/` | Phoenix reader and read-only MCP; depends on the domain |
| `pramana/apps/pramana_native/` | Rustler NIF for CJK segmentation |
| `pramana/native/quotations/` | Separate Rust quotation scanner; separate Cargo manifest |
| `pramana/priv/` | Native/model companions and project data assets; not the app's `priv/` |
| `pramana/sources/`, `sources.lock.json`, `evals/` | Provenance metadata and active evaluation inputs |
| `pramana/bin/`, `docs/`, `Dockerfile` | Product tooling, references and image build |

The three child Mix projects keep relative `../../` links to this umbrella.
[Application overview](../pramana/README.md).

## Foundry: moved out

Foundry moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry) on 2026-09-23, history included. Its
pre-split history stays in this repository; the last commit with `foundry/` is
`e1e4b3bf`.

## Shared repository files

Root `README.md`, `AGENTS.md`, provider shims, `mise.toml`, `.github/workflows/`,
`docs/` and `test/` are repository-level. Root `bin/` holds the dependency-free checks,
`bin/pramana-mix` and the `bin/pramana-mcp` launcher used by `.mcp.json`; product scripts
live in `pramana/bin/`. `pramana/AGENTS.md` routes back to the shared instructions.

The [plan](PLAN.md), [phase record](ROADMAP.md) and [product strategy](PRODUCT_STRATEGY.md)
are in `docs/`; Pramāṇa topic references are under `pramana/docs/`.

## Generated and local-only material

Build output, dependencies, coverage, native targets, the corpus (`raw/`), model
weights, PLTs, the Python virtualenv and local source text all live under `pramana/`
and are ignored by `pramana/.gitignore`. Databases and credentials live outside the
repository. [Retired files](RETIRED_FILES.md) indexes removed tracked files.
