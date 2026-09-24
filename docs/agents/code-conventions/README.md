# Code convention router

These are repository coding conventions, not proof that a check passed. Load only
the files that apply to the code being changed; do not preload the whole directory.

| Changing… | Read |
|---|---|
| Elixir, OTP, Mix or ExUnit in either project | [Elixir](elixir.md) |
| Phoenix routing, endpoints or generated web structure | [Elixir](elixir.md) and [Phoenix core](phoenix/core.md) |
| Ecto schemas, changesets, queries, seeds or migrations | [Elixir](elixir.md) and [Ecto](phoenix/ecto.md) |
| HEEx layouts, templates, components or forms | [Elixir](elixir.md) and [Phoenix HTML](phoenix/html.md); add [Phoenix core](phoenix/core.md) for generated layouts/authenticated live routes and [LiveView](phoenix/liveview.md) when live behavior is involved |
| LiveView pages, processes, streams, hooks or LiveView tests | [Elixir](elixir.md), [Phoenix core](phoenix/core.md), [Phoenix HTML](phoenix/html.md) and [LiveView](phoenix/liveview.md) |
| Phoenix JS/CSS/Tailwind assets | [Assets](phoenix/assets.md) |

Pramāṇa code should add a Phoenix file only when the touched code uses that framework surface. The shared Elixir file
contains a few explicitly marked Pramāṇa-only project defaults where they are relevant
to ordinary Elixir work.

## Phoenix upstream provenance

The Phoenix-derived guidance is **reviewed**, not blindly vendored. Local rules may
intentionally differ where this repository has stronger lifecycle, safety, testing or
structural requirements. [`UPSTREAM.exs`](UPSTREAM.exs) records the Phoenix version
locked by `pramana/mix.lock`, the exact reviewed upstream commit and complete file/blob
inventory under the watched Phoenix usage-rule directories, the complete local Markdown
convention inventory, and a separate exact snapshot baseline for Phoenix `main`.

From the Git root:

```sh
elixir bin/sync_agent_conventions.exs --check
```

is deterministic and network-free. It fails when the locked Phoenix version and the
reviewed convention metadata diverge, a local convention file is missing from the
manifest, or the manifest is structurally incomplete. After an intentional Phoenix
upgrade, run:

```sh
elixir bin/sync_agent_conventions.exs --review
```

to resolve the newly locked Phoenix tag once to an immutable commit and compare that
snapshot with the reviewed upstream directory inventory. That command uses the network
and **does not overwrite local conventions**; tag movement, added/removed rule files or
changed upstream blobs require semantic review before `UPSTREAM.exs` is advanced.

The scheduled upstream watcher similarly resolves Phoenix `main` once and reads every
watched directory at that immutable commit, avoiding torn inventories if `main` advances
mid-run. Phoenix `main` is an early-warning feed, not compatibility authority: usage-rule
drift opens or refreshes a maintenance issue but does not alter agent instructions. The
watcher does not auto-close that review issue when a baseline changes; closure remains
part of the human semantic-review workflow.

[Shared workflow](../WORKFLOW.md) · [Testing](../../TESTING.md)
