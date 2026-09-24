# Pramāṇa

Citation-grounded retrieval over Buddhist canonical texts: original-language passages
with provenance and checkable addresses, a source reader and a read-only MCP server.
Start with the [product overview](pramana/README.md).

Foundry, which shared this repository until 2026-09-23, now lives in
[lorecrafting/foundry](https://github.com/lorecrafting/foundry). Its pre-split history remains here.

## Layout

| Path | Contents |
|---|---|
| `pramana/` | The Mix umbrella: apps, config, native code, source manifests, evals and product docs. Run product commands here. |
| `docs/` | Plan, strategy, testing, agent workflow and repository docs |
| `bin/`, `test/` | Repository checks that need no Mix dependencies, plus `bin/pramana-mix` and the MCP launcher |
| `.github/workflows/` | CI |

## Development entry points

```bash
mise install
(cd pramana && mise exec -- mix deps.get)
(cd pramana && mise exec -- mix test)       # needs PostgreSQL + extensions and Rust
mise exec -- elixir bin/check_docs.exs      # repository checks; no corpus/provider
```

`bin/pramana-mix` runs Mix in `pramana/` from any working directory. Database setup is an
explicit operation; follow [setup](pramana/docs/DEV_ENV.md). The corpus (`pramana/raw/`),
model weights, virtualenv and local source text are ignored and never committed. Do not
run `git clean -fdx`: it deletes them.

```bash
docker build -f pramana/Dockerfile -t pramana:local pramana
```

## Orientation

[Agent router](AGENTS.md) · [Documentation](docs/README.md) · [Repository map](docs/REPO_MAP.md) ·
[Testing](docs/TESTING.md) · [Plan](docs/PLAN.md) · [Product strategy](docs/PRODUCT_STRATEGY.md)
