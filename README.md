# Pramāṇa and Foundry

Two independent Elixir projects share this Git repository. Choose the product before
running a command; the repository root is **not** a Mix umbrella for both.

| Product | Purpose | Start here |
|---|---|---|
| **Pramāṇa** | Citation-grounded Buddhist textual retrieval and a source reader | [Product overview](pramana/README.md), [setup](pramana/docs/DEV_ENV.md), [reference index](pramana/docs/README.md) |
| **Foundry** | Independent agent-workflow coordination, evidence and recovery | [Overview and containment](foundry/README.md), [current repair authority](foundry/docs/REPAIR-PLAN.md), [current alignment audit](foundry/docs/ALIGNMENT-AUDIT-2026-09-19.md), [independent CI](foundry/docs/CI.md) |

Pramāṇa retains its three-app umbrella under `pramana/apps/`. Foundry retains its
own dependencies, configuration, release and tests under `foundry/`. Neither is a
child of the other, and their lockfiles remain separate.

## Development entry points

```bash
mise install
(cd pramana && mise exec -- mix deps.get)
(cd pramana && mise exec -- mix test)       # needs PostgreSQL + extensions and Rust
(cd foundry && mise exec -- elixir ci/run.exs --output /tmp/foundry-ci-artifacts)
mise exec -- elixir bin/check_docs.exs      # repository checks; no corpus/provider
```

Database setup is an explicit operation; follow the selected product's guide first.
`bin/pramana-mix` forwards to Pramāṇa from any working directory. Existing root
`bin/pramana-mcp`, `bin/pramana-modal` and `bin/pramana-tranche` paths are compatibility
wrappers; their implementations live in `pramana/bin/`. They do not launch Foundry.

## Existing checkouts

Read [the cutover and rollback guide](docs/LAYOUT_MIGRATION.md) **before changing
an active checkout**. This migration moves tracked source, not ignored corpora,
model weights, databases, credentials, accepted releases or running worktrees.
Do not use `git clean -fdx` to resolve leftover directories. Foundry's operator
runtime root and all repair policy are unchanged. A merge is not live activation.

The Pramāṇa image now uses its own context:

```bash
docker build -f pramana/Dockerfile -t pramana:local pramana
```

## Shared orientation

[Agent router](AGENTS.md) · [Documentation](docs/README.md) ·
[Repository map](docs/REPO_MAP.md) · [Testing](docs/TESTING.md) ·
[Product strategy](docs/PRODUCT_STRATEGY.md) · [Structure decision](docs/REPOSITORY_STRUCTURE.md)

The shared plan remains in [docs/PLAN.md](docs/PLAN.md) while its existing repair
owners are active. Project-specific references live with their product; shared
strategy, governance, historical audit records and navigation stay at the root.
