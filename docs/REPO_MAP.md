# Repository map

Two products share Git, not a Mix project, dependency lockfile or running application.
[Migration and cutover](LAYOUT_MIGRATION.md) · [Structure rationale](REPOSITORY_STRUCTURE.md)

| Root | Ownership / entry point |
|---|---|
| `pramana/` | Pramāṇa Mix umbrella; run its Mix commands here |
| `pramana/apps/pramana/` | Corpus, retrieval, citation, source and evaluation domain |
| `pramana/apps/pramana_web/` | Phoenix reader and read-only MCP surface |
| `pramana/apps/pramana_native/` | Rustler CJK segmentation NIF |
| `pramana/native/quotations/` | Independent Rust quotation scanner binary |
| `pramana/priv/` | Tracked model helpers and image metadata; ignored artifacts are data, not dependencies of Foundry |
| `pramana/sources/`, `pramana/sources.lock.json` | Tracked provenance; private text is separately ignored |
| `pramana/evals/` | Evaluation implementation inputs, gold cases and baseline |
| `pramana/docs/` | Maintained product guides, tutorials, rules and historical studies |
| `foundry/` | Independent Mix application, its configuration, lockfile, roles, tests, CI and execution contracts |
| `docs/` | Shared strategy, active plan, formal roadmap, workflow/conventions, audits, migration and compatibility bookmarks |
| `.github/workflows/` | Independent CI jobs; working directories and caches are explicit |
| `mise.toml` | Currently common pinned BEAM toolchain, inherited by both product directories |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md` | Provider-neutral root routing and thin compatibility imports |
| `bin/check_docs.exs` | Model-free repository documentation, path and wrapper checks |
| `bin/pramana` | Explicit command dispatcher into the Pramāṇa project, not the Foundry CLI |
| `bin/pramana-mcp`, `bin/pramana-modal`, `bin/pramana-tranche` | Narrow compatibility wrappers for former root entry points |

## Choose one build

Pramāṇa retains its three existing umbrella applications with shared internal
configuration and dependencies. Foundry stays outside that umbrella. There is no
root `mix.exs`, no `apps/foundry`, and no common root dependency lockfile.

From the repository root, `bin/pramana mix test` selects Pramāṇa; `(cd foundry &&
mix test)` selects Foundry. Both need their documented prerequisites. The root
`elixir bin/check_docs.exs` check needs neither application nor a corpus/provider.

[Pramāṇa setup](../pramana/docs/DEV_ENV.md) · [Foundry CI](../foundry/docs/CI.md) ·
[Testing scope](TESTING.md) · [Complete catalog](CATALOG.md)

## Four roots, not one overloaded path

**Repository root** holds Git and shared docs. **Project root** holds product source,
config and lockfiles. **Pramāṇa data root** selects untracked corpus/model/private-text
artifacts. **Foundry runtime root** remains the original operator-owned location,
independent of the current task checkout. A source move changes only the first two
relationships; it does not move or approve the latter two.

[Pramana.Paths](../pramana/apps/pramana/lib/pramana/paths.ex) makes the first three
explicit. The [Foundry contract](../foundry/docs/WORKFLOW-CONTRACT.md) and
[repair plan](../foundry/docs/REPAIR-PLAN.md) still own execution and acceptance.
