# Status

Living handoff document. **Update this at every checkpoint gate.** If you are a new
session with no context, read this first, then `CLAUDE.md`, then `docs/ROADMAP.md`,
then run `TaskList`.

---

## Where we are

**Phase 0, in progress.** Scaffold and URN foundation are done and committed; the
ingest path (acquire → normalize → segment) is not yet built.

### Done

- Git repo on `main`. First commit: `Phase 0: scaffold Pramana umbrella...`
- Phoenix 1.8.11 umbrella: `apps/pramana` (domain) + `apps/pramana_web`
- Toolchain pinned project-locally in `mise.toml`: **Erlang 29.0.5 / Elixir 1.20.3-otp-29**
- Postgres 18 + pgvector 0.8.6, running **natively** via Homebrew (no container)
- Migrations applied: `sources`, `witnesses`, `works`, `texts`, `segments`, `bakes`
- `Pramana.URN` — parse/format/round-trip, 5 locator grammars, rejects malformed input
- `Pramana.URN.Taisho` — page/register/line grammar; the mechanical vols 56–84 rule
- Quality gate green: 27 tests, `mix credo --strict` (69 checks), `--warnings-as-errors`

### Next

Task #1 (acquire CBETA T0262). Then #2 → #3 → #4 → #5, then the Phase 0 gate (#8).
Tasks #6 and #7 are spikes that must land before Phase 1 and can run in parallel.

---

## Decisions taken

| Decision | Rationale |
|---|---|
| Name: **Pramāṇa** | "Valid means of knowledge." The name is the thesis; survives the later medical-text expansion, which `dharma-*` would not. |
| Open-source, self-hosted | We publish the **pipeline, not the corpus**. Keeps CBETA's non-commercial clause and BDRC's restrictions out of our distribution entirely. |
| All four traditions in v1 | Ambitious. Tibetan is the acknowledged long pole and the designated thing to cut if the schedule slips. |
| One Postgres (no Elasticsearch/Qdrant) | The predicate-plus-vector query is the most important query in the system; splitting stores makes it awkward. |
| MCP + HTTP API first, UI last | The API-first order makes the Phase 8 LiveView reader a renderer rather than a second implementation. |
| Elixir/Phoenix, 3 exceptions | See `docs/ELIXIR.md`. Bake = concurrent, backpressured, fault-isolated file processing, which is what BEAM is for. |
| Native Postgres, not Docker | The bake reads hundreds of thousands of small files; container FS mounts on macOS are the slowest part of every runtime. See `docs/DEV_ENV.md`. |
| `.credo.exs` from `gen.config`, patched | A hand-written config silently **replaced** the default check set (3 checks ran instead of 69). Generate the full default and patch it; never hand-roll. |

## Open questions

- **MCP library** — `hermes_mcp` was forked to `anubis-mcp` after the maintainer left
  CloudWalk. Check both for maintenance before adopting; implementing JSON-RPC
  directly in Phoenix is an acceptable and possibly preferable fallback. *(Task #5)*
- **BGE-M3 under Bumblebee** — dense-only may work; multi-vector (sparse + ColBERT)
  is unconfirmed and is why we chose BGE-M3. *(Task #6)*
- **pg_bigm** — not in Homebrew, must be compiled from source. *(Task #10)*

## Surprises and gotchas

- `mise` requires `mise trust` in the project directory or the **global config
  silently wins** — an early `mise install` no-op'd because of this.
- `phx_new` latest is **1.8.9**; the `phoenix` library is **1.8.11**. They version
  separately.
- Homebrew Postgres uses your **OS username** as superuser with no password, not
  `postgres/postgres`. Config reads `PGUSER`/`PGPASSWORD`/`PGHOST` with those defaults.

## Metrics

Recorded at each gate from Phase 4 onward.

| Gate | Recall@10 | Citation accuracy | Full-bake time | Embedding cost |
|---|---|---|---|---|
| _(none yet)_ | | | | |
