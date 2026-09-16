# Code convention router

These are repository coding conventions, not proof that a check passed. Load only
the files that apply to the code being changed; do not preload the whole directory.

| Changing… | Read |
|---|---|
| Elixir, OTP, Mix or ExUnit in either project | [Elixir](elixir.md) |
| Phoenix routing, endpoints, layouts or generated web structure | [Elixir](elixir.md) and [Phoenix core](phoenix/core.md) |
| Ecto schemas, changesets, queries, seeds or migrations | [Elixir](elixir.md) and [Ecto](phoenix/ecto.md) |
| HEEx templates, components or forms | [Phoenix HTML](phoenix/html.md); add [LiveView](phoenix/liveview.md) when live behavior is involved |
| LiveView processes, streams, hooks or LiveView tests | [Elixir](elixir.md), [Phoenix HTML](phoenix/html.md) and [LiveView](phoenix/liveview.md) |
| Phoenix JS/CSS/Tailwind assets | [Assets](phoenix/assets.md) |

Foundry normally needs only the shared Elixir file. Pramāṇa code should add a Phoenix
file only when the touched code uses that framework surface.

## Phoenix upstream provenance

The Phoenix-derived guidance is **reviewed**, not blindly vendored. Local rules may
intentionally differ where this repository has stronger lifecycle, safety or structural
requirements. [`UPSTREAM.exs`](UPSTREAM.exs) records the Phoenix version locked by
`pramana/mix.lock`, the reviewed upstream blob identities, and a separate baseline for
Phoenix `main`.

From the Git root:

```sh
elixir bin/sync_agent_conventions.exs --check
```

is deterministic and network-free. It fails when the locked Phoenix version and the
reviewed convention metadata diverge. After an intentional Phoenix upgrade, run:

```sh
elixir bin/sync_agent_conventions.exs --review
```

to compare the newly locked version with the reviewed upstream sources. That command
uses the network and **does not overwrite local conventions**; changes require semantic
review before `UPSTREAM.exs` is advanced.

The scheduled upstream watcher runs `--watch-main`. Phoenix `main` is an early-warning
feed, not compatibility authority: drift opens or refreshes a maintenance issue but does
not alter agent instructions.

[Shared workflow](../WORKFLOW.md) · [Testing](../../TESTING.md)
