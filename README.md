# Pramāṇa

Foundry, which shared this repository until 2026-09-23, now lives in
[lorecrafting/foundry](https://github.com/lorecrafting/foundry) with its full history. Its pre-split history remains here.

| Product | Purpose | Start here |
|---|---|---|
| **Pramāṇa** | Citation-grounded Buddhist textual retrieval and a source reader | [Product overview](pramana/README.md), [setup](pramana/docs/DEV_ENV.md), [reference index](pramana/docs/README.md) |
| **Foundry** | Independent agent-workflow coordination, evidence and recovery | [lorecrafting/foundry](https://github.com/lorecrafting/foundry) |

Pramāṇa keeps its three-app umbrella under `pramana/apps/`.

## Development entry points

```bash
mise install
(cd pramana && mise exec -- mix deps.get)
(cd pramana && mise exec -- mix test)       # needs PostgreSQL + extensions and Rust
mise exec -- elixir bin/check_docs.exs      # repository checks; no corpus/provider
```

Database setup is an explicit operation; follow the selected product's guide first.
`bin/pramana-mix` forwards to Pramāṇa from any working directory. Existing root
`bin/pramana-mcp`, `bin/pramana-modal` and `bin/pramana-tranche` paths are compatibility
wrappers; their implementations live in `pramana/bin/`.

## Existing checkouts

Read [the cutover and rollback guide](docs/LAYOUT_MIGRATION.md) **before changing
an active checkout**. This migration moves tracked source, not ignored corpora,
model weights, databases, credentials, accepted releases or running worktrees.
Do not use `git clean -fdx` to resolve leftover directories: an existing checkout may
still hold ignored Foundry state under `foundry/` (see [the repository map](docs/REPO_MAP.md#foundry-moved-out)).
A merge is not live activation.

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
