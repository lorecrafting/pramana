# Repository map: two systems

The current root is Pramāṇa’s umbrella, not a parent Mix build for both systems.
See [the structure review](REPOSITORY_STRUCTURE.md) for the ownership audit and
why a sibling layout is a separate post-repair migration, not a cleanup rename.

## Pramāṇa: research substrate

The root [Mix project](../mix.exs) is an Elixir umbrella. Its primary interfaces are
read-only MCP tools and a Phoenix LiveView reader over the same core domain.

| Path | Responsibility | Important boundary |
|---|---|---|
| `apps/pramana/` | Acquisition, normalization, citations, provenance, retrieval, evaluation | Owns corpus SQL and mutations; no web UI logic. It does depend on Phoenix PubSub, not the Phoenix web framework. |
| `apps/pramana_web/` | MCP, reader and web delivery | Calls domain functions rather than defining competing retrieval/provenance rules |
| `apps/pramana_native/` | Rustler NIF for CJK segmentation | Compiled Rust dependency of the umbrella |
| `native/quotations/` | Standalone Rust text-reuse scan | Seed-and-extend over JSONL files; Elixir owns database import, not the Rust process |
| `priv/embed/` | Python inference/training and Modal batch helpers | Receives exported text/tensors and returns artifacts; not a second corpus database layer |
| `config/` | Umbrella runtime and environment configuration | Development and production database variables differ |
| `sources.lock.json` | Source acquisition records | Not a complete backup of all mutable database state |
| `evals/` | Active gold cases and evaluation baseline | Retired one-off experiments are indexed in [retired files](RETIRED_FILES.md); do not delete the active baseline as generated junk |
| `bin/` | Pramāṇa wrappers and the shared documentation check | Foundry commands and intentionally disabled compatibility wrappers live under `foundry/bin/` |

The BEAM toolchain is pinned in [mise.toml](../mise.toml). Application dependencies
and coverage thresholds belong to the relevant `mix.exs` files; avoid copying their
counts into navigation pages. Rust uses a floating `stable` toolchain in the current
Docker/umbrella CI setup despite older comments claiming an exact pin.

See [architecture](ARCHITECTURE.md), [setup](DEV_ENV.md), [CLI index](CLI.md),
[MCP](MCP.md) and [reader](READER.md).

## Foundry: independent execution system

[Foundry's Mix project](../foundry/mix.exs) is not an umbrella child. Its declared
Hex dependency is `owl`, for terminal rendering. It builds and runs model-free tests
without Postgres, the corpus, Rust or the inference sidecar.

| Path | Responsibility |
|---|---|
| `foundry/lib/pramana_foundry/` | OTP coordinator, agent lifecycle, durable state, scheduling and telemetry |
| `foundry/lib/pramana_foundry/herdr/` | Existing typed execution-backend adapter |
| `foundry/roles/` | Agent role contracts; not provider-specific repository instructions |
| `foundry/ci/` | Isolated model-free build/test/provenance runner |
| `foundry/docs/` | Execution contracts, active repairs, designs and dated review evidence |
| `foundry/local/` | Ignored local runtime data, not portable tracked source |

Build independence does not imply live launch readiness. Real execution depends on
backend capabilities, authorized account/billing routes and the containment described
in [Foundry's README](../foundry/README.md). Start repair work with
[the Foundry documentation index](../foundry/docs/README.md), not old migration tickets.
No runtime migration or provider-conformance guarantee is established by this
map; future backends require their own implementation and acceptance evidence.

## Documentation boundaries

[AGENTS.md](../AGENTS.md) routes all models to the same shared workflow. Provider
entry files contain no competing policy. The human index is [docs/README.md](README.md).
Current contracts, operating procedures, recorded measurements and proposed designs
are distinct document types; one is not evidence of another.
