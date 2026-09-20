# Repository map

Two independent products in sibling directories; there is **no repository-wide
Mix umbrella**. [Structure decision](REPOSITORY_STRUCTURE.md) ·
[Cutover/rollback](LAYOUT_MIGRATION.md) · [Documentation](README.md).

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

The three child Mix projects keep their relative `../../` links to this umbrella.
Their app names, source lockfile bytes and dependency locks did not change in the
migration. [Application overview](../pramana/README.md).

## Foundry: standalone project

Work in `foundry/`. Its [Mix file](../foundry/mix.exs), [runtime configuration](../foundry/config/config.exs),
[roles](../foundry/roles) and [CI runner](../foundry/ci/run.exs) are independent of
Pramāṇa. No shared application configuration, database, release or dependency lock
is introduced. The existing operator runtime root is unchanged.

[Repair authority](../foundry/docs/REPAIR-PLAN.md) owns execution acceptance and
remaining defects. A new folder layout neither repairs them nor authorizes activation.

## Shared repository files

Root `README.md`, `AGENTS.md`, provider shims, `mise.toml`, `.github/workflows/`,
`docs/` and `test/` are repository-level concerns. Root `bin/` contains shared checks
and deliberately retained compatibility wrappers, not a second copy of product logic.
`pramana/AGENTS.md` and `foundry/AGENTS.md` route back to the shared instructions.

[Product strategy](PRODUCT_STRATEGY.md), the still-active [plan](PLAN.md) and
[phase record](ROADMAP.md) remain shared. Pramāṇa topic references are under
`pramana/docs/`; Foundry operational references remain under `foundry/docs/`.

## Generated and local-only material

Each product owns its own `_build/`, `deps/`, coverage and native outputs.
Pramāṇa's product ignore file protects the new locations. Legacy root ignore
patterns remain to protect pre-migration data until an explicit operator cutover.
Databases, raw corpora, credentials, active worktrees and accepted Foundry builds
are not moved by Git source renames. [Retired-file recovery](RETIRED_FILES.md) is a
separate cleanup record, not an instruction to delete these local artifacts.
