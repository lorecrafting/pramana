# Pramāṇa and Foundry

Two independent Elixir systems share this repository, not a build or a runtime.

| Product | Purpose | Start |
|---|---|---|
| **Pramāṇa** | Buddhist textual retrieval, provenance, citation checking and a human reader | [Product README](pramana/README.md) · [Docs](pramana/docs/README.md) |
| **Foundry** | Controlled agent-assisted software delivery, recovery and independent acceptance | [Product README](foundry/README.md) · [Docs](foundry/docs/README.md) |

Pramāṇa is an umbrella containing its domain, web/MCP and native applications.
Foundry is a standalone OTP project. Neither product is a child of the other's
Mix project; each has its own dependency lockfile and configuration.

## Working directories

```bash
# Pramāṇa
cd pramana
mix deps.get
mix test

```

In a separate shell, from the repository root:

```bash
cd foundry
mix deps.get
mix test
```

Read the product's setup and acceptance requirements before executing. At repository root, the optional
`bin/pramana mix <task>` wrapper selects Pramāṇa explicitly. There is no root Mix
umbrella and no implicit command that launches both products.

The shared, model-free documentation and layout checks run from repository root:

```bash
elixir bin/check_docs.exs
```

## Existing checkout: read before switching

The source move does **not** move a corpus, database, model cache, virtualenv,
Foundry state, accepted release or worktree. Existing operators must review the
[layout migration guide](docs/LAYOUT_MIGRATION.md), including explicit data-root
selection, checked-in manifests, project working directories and rollback.

## Navigation

[Repository map](docs/REPO_MAP.md) · [Shared documentation](docs/README.md) ·
[Product strategy](docs/PRODUCT_STRATEGY.md) · [Active plan](docs/PLAN.md)

[AGENTS.md](AGENTS.md) is the small provider-neutral entry point; the Claude and
Gemini files import it. Use the applicable product route, not both manuals.

The active Foundry [repair plan](foundry/docs/REPAIR-PLAN.md) and
[workflow contract](foundry/docs/WORKFLOW-CONTRACT.md) retain their authority.
A repository reorganization is not repair closure, launch permission or deployment.
