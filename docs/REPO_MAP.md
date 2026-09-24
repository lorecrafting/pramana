# Repository map

The repository root is the Pramāṇa Mix umbrella. Run Mix, asset, native and corpus
commands here. [Documentation](README.md).

| Location | Role |
|---|---|
| `mix.exs`, `mix.lock`, `config/`, `rel/` | Umbrella build, dependencies, configuration and release |
| `apps/pramana/` | Corpus domain, acquisition, citation, provenance, retrieval and evaluation |
| `apps/pramana_web/` | Phoenix reader and read-only MCP; depends on the domain |
| `apps/pramana_native/` | Rustler NIF for CJK segmentation |
| `native/quotations/` | Separate Rust quotation scanner; separate Cargo manifest |
| `priv/` | Native/model companions and project data assets; not an app's `priv/` |
| `sources/`, `sources.lock.json`, `evals/` | Provenance metadata and active evaluation inputs |
| `bin/` | `pramana-mcp` (used by `.mcp.json`), Modal/tranche wrappers and dependency-free repository checks |
| `ci/`, `Dockerfile`, `.github/workflows/` | CI fixtures, runtime image and workflows |
| `docs/`, `test/` | Documentation and repository-level checks run by `bin/check_docs.exs` |

The three child Mix projects use relative `../../` build, config, deps and lockfile paths.
[Architecture](ARCHITECTURE.md).

## Foundry: moved out

Foundry moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry) on 2026-09-23, history included. Its
pre-split history stays in this repository; the last commit with `foundry/` is
`e1e4b3bf`. Until 2026-09-24 Pramāṇa itself lived in a `pramana/` subdirectory.

## Generated and local-only material

Build output, dependencies, coverage, native targets, the corpus (`raw/`), model weights,
PLTs, the Python virtualenv and local source text are ignored by `.gitignore`. Databases
and credentials live outside the repository. [Retired files](RETIRED_FILES.md) indexes
removed tracked files.
