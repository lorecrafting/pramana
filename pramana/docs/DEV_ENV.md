# Development setup

Choose the system first. [Foundry](../../foundry/docs/CI.md) has an isolated model-free
build; it does not need the Pramāṇa database or inference environment below.
These are repository-derived instructions, not evidence that setup ran in this audit.

## Pramāṇa prerequisites

Use [mise.toml](../../mise.toml) for the exact Erlang/Elixir toolchain. The umbrella also
needs Rust for `pramana_native` and PostgreSQL with the `vector` and `pg_bigm`
extension binaries installed on the **server**. `pg_bigm` is not `pg_trgm`.
See [umbrella CI](../../.github/workflows/ci.yml) for the currently exercised extension
installation recipe; [Dockerfile](../Dockerfile) builds the application release,
not the database server.

Do not create extensions in a database that has not been created. Install the server
extension packages first; the application's migrations create the required extensions.
Development credentials must be allowed to create the development/test databases and
install those extensions, or an operator must provision them separately.

From the Pramāṇa project root (`cd pramana` from the repository root):

```bash
mise install
mise exec -- mix deps.get
mise exec -- mix compile
(cd apps/pramana && mise exec -- mix ecto.setup)
mise exec -- mix phx.server
```

`mix ecto.setup` is a core-app alias that creates/migrates the configured database and runs its seeds;
it is **not** a corpus download. An empty reader is expected until sources are acquired
and ingested. Inspect [the source workflows](SOURCES.md) and [CLI index](CLI.md) rather
than assuming one bake command loads every tradition. Acquiring sources requires their
licenses, network access, storage and explicit operator intent.

Existing operators: read [the source-layout migration](../../docs/LAYOUT_MIGRATION.md)
and choose `PRAMANA_DATA_ROOT` explicitly before using legacy corpus/model files.
Tracked manifests and the source lockfile are under this project; data stays where
it already exists. Tests ignore the operator data-root environment for fixture safety.

## Database configuration

| Environment | Source | Important settings |
|---|---|---|
| Development | [config/dev.exs](../config/dev.exs) | `PGUSER` (otherwise OS user), `PGPASSWORD`, `PGHOST`, `PRAMANA_DATABASE` (otherwise `pramana_dev`) |
| Test | [config/test.exs](../config/test.exs) | Separate test database and sandbox settings; inspect this file before targeting any server |
| Production | [config/runtime.exs](../config/runtime.exs) | Required `DATABASE_URL` and `SECRET_KEY_BASE`; `APP_HOST`, `PORT`, `POOL_SIZE` and other runtime settings |

Do not point tests or a public bake at a research database by accident. Do not export
`MIX_ENV=test` or `MIX_ENV=prod` globally for unrelated commands. Use per-command settings.
`PRAMANA_SQL_LOG=1` enables development SQL logging; avoid exposing sensitive queries
or credentials in shared logs.

## Embeddings are optional at server startup

```bash
PRAMANA_EMBEDDING=1 mise exec -- mix phx.server
```

This opts into model loading; it also requires the expected local model artifacts and
compatible vectors in the chosen database. Without it, hybrid retrieval can fall back
to lexical and reports which retrievers actually ran. Loading a model is not evidence
that every source has been indexed. [Embedding](EMBEDDING.md) covers the artifact path.

Python is needed for the relevant batch inference/training helpers under `priv/embed/`,
including translation—not for every database command or Foundry model-free check.
No standalone HTTP `/embed` daemon is configured by this setup guide.

## Checks and troubleshooting

Use [testing](../../docs/TESTING.md) for documentation-only, umbrella, Foundry and corpus checks.
For a loaded research database, `mix pramana.doctor` reports source and retrieval-state
facts; read its warnings rather than treating command completion as a health attestation.

Before changing PostgreSQL memory or connection settings, measure the active workload
and memory available to all concurrent processes. The old laptop-tuning recipe was
explicitly reverted and is **not** a default to copy. Provider/database-hosting prices
and free-tier terms in older notes are not current setup requirements.

[Historical local setup and tuning notes](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md) are kept
for diagnosis, including the rejected settings; do not execute them as current guidance.

## Historical section bookmarks

These bookmarks open the retained pre-cleanup revision in Git history, not current instructions.
See [retired files](../../docs/RETIRED_FILES.md) for recovery and offline-access limits.

| Earlier section |
|---|
| <a id="dev-environment"></a>[Dev Environment](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#dev-environment) |
| <a id="do-we-need-docker-not-yet-and-not-for-postgres"></a>[Do we need Docker? Not yet, and not for Postgres.](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#do-we-need-docker-not-yet-and-not-for-postgres) |
| <a id="where-containers-do-become-necessary"></a>[Where containers do become necessary](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#where-containers-do-become-necessary) |
| <a id="container-runtimes-on-macos-ranked-for-this-project"></a>[Container runtimes on macOS, ranked for this project](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#container-runtimes-on-macos-ranked-for-this-project) |
| <a id="other-ways-to-run-postgres-for-dev"></a>[Other ways to run Postgres for dev](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#other-ways-to-run-postgres-for-dev) |
| <a id="postgres-tuning--tried-and-reverted-2026-08-29-do-not-reapply-without-reading-this"></a>[Postgres tuning — TRIED AND REVERTED 2026-08-29, do not reapply without reading this](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#postgres-tuning--tried-and-reverted-2026-08-29-do-not-reapply-without-reading-this) |
| <a id="too_many_connections-looks-like-a-failing-test-and-is-not--2026-09-02"></a>[`too_many_connections` looks like a failing test, and is not — 2026-09-02](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#too_many_connections-looks-like-a-failing-test-and-is-not--2026-09-02) |
| <a id="-refined-the-same-day-after-it-happened-again-during-a-full-gate"></a>[▸ REFINED the same day, after it happened again during a full gate](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#-refined-the-same-day-after-it-happened-again-during-a-full-gate) |
| <a id="a-long-run-died-of-tcp-recv-idle-closed-and-postgres-was-not-the-cause--2026-09-03"></a>[A long run died of `tcp recv (idle): closed`, and Postgres was not the cause — 2026-09-03](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#a-long-run-died-of-tcp-recv-idle-closed-and-postgres-was-not-the-cause--2026-09-03) |
| <a id="toolchain-pinning"></a>[Toolchain pinning](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#toolchain-pinning) |
| <a id="verify-the-pin-is-actually-in-effect"></a>[Verify the pin is actually in effect](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#verify-the-pin-is-actually-in-effect) |
| <a id="do-not-put-mix_env-in-misetoml"></a>[Do not put `MIX_ENV` in `mise.toml`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md#do-not-put-mix_env-in-misetoml) |
