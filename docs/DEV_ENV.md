# Dev Environment

## Do we need Docker? Not yet, and not for Postgres.

Postgres + pgvector runs natively on macOS via Homebrew, which is what this project
uses for Phases 0–1:

```bash
brew install postgresql@18 pgvector
brew services start postgresql@18
export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"
```

No VM, no daemon, ~2s start, survives reboot. For local development this is strictly
lighter than any container option.

**The reason this matters more here than in a normal project:** the bake reads
hundreds of thousands of TEI files out of `raw/`. Container filesystem mounts on macOS
are the slowest part of every container runtime — virtiofs/gRPC-FUSE overhead on a
workload of many small files is severe. Running Postgres *and* the bake natively
avoids that entirely. Containerize the parts that don't touch `raw/`.

## Where containers do become necessary

1. **`pg_bigm`** — the bigram index for Chinese. Not in Homebrew, but it builds
   cleanly from source against Homebrew Postgres 18.4 in under a minute, so the
   database stays native:

   ```bash
   git clone --depth 1 --branch v1.2-20250903 https://github.com/pgbigm/pg_bigm.git
   cd pg_bigm
   export PATH="/opt/homebrew/opt/postgresql@18/bin:$PATH"   # for pg_config
   make USE_PGXS=1 && make USE_PGXS=1 install
   psql -d pramana_dev -c "CREATE EXTENSION pg_bigm;"
   ```

   Verify it tokenizes CJK: `SELECT show_bigm('如是我聞');` should return
   `{如是,我聞,是我,"聞 "," 如"}`. No `shared_preload_libraries` change is needed.
2. **The Python embed sidecar** (Phase 1+) — BGE-M3, and nothing else. This is the
   real container use case: an isolated Python/Torch environment we don't want
   polluting the host. (It was scoped to carry Tibetan `botok` too; that dependency was
   never taken and the plan is withdrawn — see `docs/ELIXIR.md`.)
3. **CI and deployment** — reproducible bakes elsewhere.

## Container runtimes on macOS, ranked for this project

| Runtime | Verdict |
|---|---|
| **OrbStack** | Best macOS experience. Sub-second start, markedly lower RAM/CPU than Docker Desktop, and the **fastest filesystem** of the options — which is the metric that matters here. Drop-in `docker`/`docker compose` CLI compatibility. Free for personal/non-commercial use; **commercial use requires a paid license**, which given this project's open-source non-commercial posture likely doesn't apply to you. |
| **Colima** | Free and fully OSS, Lima-based. `colima start --vm-type vz --mount-type virtiofs` gets respectable performance. CLI-only. The right pick if you want zero licensing questions ever. |
| **Podman** | Daemonless and rootless, free/OSS. Good security story. Slightly more friction with compose files (`podman-compose`). |
| **Rancher Desktop** | Free/OSS, bundles k3s. Heavier; only worth it if you want local Kubernetes. |
| **Docker Desktop** | Heaviest, and licensing cost at organization scale. No reason to choose it here. |

**Recommendation:** stay native through Phase 1. When the embed sidecar lands, install
**OrbStack** (free for this use case, best small-file performance). Choose **Colima**
instead if staying strictly OSS matters more than filesystem speed.

## Other ways to run Postgres for dev

- **Postgres.app** — GUI, easy version switching, bundles many extensions. Pleasant if
  you prefer a GUI, but you'd still install pgvector separately, and it's no lighter
  than Homebrew.
- **Separate test database** — Ecto already does this (`pramana_test`). No extra
  tooling needed; don't reach for testcontainers here.
- **Hosted (Neon, Supabase, RDS)** — all support pgvector. A poor fit for local
  development against a 250M-character bake (egress, latency, cost), but a reasonable
  target for the eventual public demo, which serves only the CC0/CC-BY subset.
- **Embedded/ephemeral Postgres** — not worth it; the extensions we need (pgvector,
  pg_bigm) make a managed local install simpler.

## Postgres tuning — TRIED AND REVERTED 2026-08-29, do not reapply without reading this

Homebrew ships `postgresql@18` with server defaults written for a much smaller machine, and
nothing in this repo changes them. Measured on 2026-08-29: `shared_buffers` **128 MB**,
`random_page_cost` **4.0**, `work_mem` **4 MB**, `maintenance_work_mem` **64 MB**. The
`random_page_cost` default assumes a spinning disk and actively steers the planner away from
index scans on an SSD.

**This block was applied on 2026-08-29 and removed the same day.** It produced no
measurable gain on any workload here and is the prime suspect in taking `mix pramana.verify
--all` from ~6 min of actual work to **46m48s** by pushing a 16 GB machine into swap — see
`docs/PLAN.md` § "Rejected, with evidence". It is kept here as a record of what was tried,
**not as a recipe**. The database is back on stock defaults.

Config lives at `/opt/homebrew/var/postgresql@18/postgresql.conf`. **Append the block below
rather than editing existing lines** — later settings win, so appending is a change you can
revert by deleting it, and back the file up first.

```conf
# --- BEGIN pramana tuning ---
# 16 GB machine that ALSO holds a 2.2 GB BGE-M3 model inside the BEAM, so these sit below
# the usual fractions: 2 GB rather than the customary 25%.
shared_buffers = 2GB
effective_cache_size = 6GB          # planner hint only, allocates nothing
work_mem = 16MB                     # per sort NODE per connection; the dev pool is 25
maintenance_work_mem = 512MB        # index builds — what the HNSW rebuild runs in
random_page_cost = 1.1              # NVMe, not the spinning disk 4.0 assumes
effective_io_concurrency = 200
max_parallel_workers_per_gather = 4 # max_worker_processes is 8
# --- END pramana tuning ---
```

Then `brew services restart postgresql@18` — `shared_buffers` needs a restart, not a reload,
so **never apply this while a bake, an eval run or a measurement is in flight.**

**It could once have re-rolled a seeded sample; it cannot now.** `random()` is volatile and
evaluated per row, so which value a row draws depended on the order rows reached it, and a
changed plan could therefore draw a different sample from the same seed. Applying this block
on 2026-08-29 did **not** move the sample — which was briefly read as evidence that the
worry was imaginary. It was not: the tuning was simply too small a plan change. Forcing
`enable_indexscan=off` moved it immediately, while the hash ordering that replaced it held
identical across five planner configurations.

Sampling now orders on `md5(salt || id)` — see `Pramana.Sampling` — so a seeded figure no
longer depends on the server's configuration at all, and this section is a record of a
tuning that was tried and withdrawn rather than a caveat you still have to reason about.

## `too_many_connections` looks like a failing test, and is not — 2026-09-02

`mix pramana.gate --quick` failed on its **test** step in 4 s with

    FATAL 53300 (too_many_connections) sorry, too many clients already

and the same suite passed standalone. Nothing was wrong with the code.

`config/dev.exs` sets `pool_size: 25`, Postgres ships `max_connections = 100`, and **every
long-lived process holds a full dev pool**. Two `mix pramana.mcp.stdio` servers and a
`mix phx.server` is 52 connections before any test runs; the umbrella test env then wants
`System.schedulers_online() * 2` per app plus Oban's notifier, across three apps.

**The symptom is the problem.** The gate reports its test step failed, which reads as a
regression in the code you just wrote, and the actual cause is a session left running in
another terminal. Check before debugging:

```bash
psql postgres -c "select datname, count(*) from pg_stat_activity group by 1 order by 2 desc"
ps aux | grep '[b]eam.smp'   # each mcp.stdio / phx.server holds pool_size connections
```

Then stop a server you are not using, or raise `max_connections`. **Do not lower
`pool_size` in `config/dev.exs` to make it fit** — 25 is what makes the bake and the eval
runs fast.

### ▸ REFINED the same day, after it happened again during a full gate

The paragraph above called this "a *concurrent sessions* problem rather than a per-process
one", and that is half right. It recurred on the full gate: `FAILED test (45s)` with all
1,567 tests passing, and 2,090 lines of `Oban.Notifiers.Postgres failed to connect` around
the real cause.

**Both halves are true, and only one of them is anybody's fault.** `mix pramana.bake` and
`mix pramana.evals` genuinely use 25 connections and should keep them. `mix
pramana.mcp.stdio` cannot: stdio serialises requests over a single stream and every MCP
tool handler runs sequential `Repo` calls on the caller's process — nothing in that path
fans out. It held 25 connections to use one, for the whole length of an editor session,
and two editors made that 50 of the server's 100.

So **that task now sets its own `pool_size: 4`** before `app.start`, which is a different
change from lowering the shared constant: a long-lived process's share of a finite budget
should be what it can use, not what the heaviest job needs. `mix phx.server` keeps the
full pool, because an HTTP transport really does serve concurrent requests.

The diagnosis above stands and the commands are still the first thing to run — the
per-process fix buys headroom, it does not make a stock `max_connections = 100` unlimited.

## Toolchain pinning

`mise.toml` pins exact Erlang/Elixir versions project-locally, deliberately not
`latest` — the reproducibility discipline that governs the corpus bake should govern
the build too. Note that mise requires `mise trust` before a project config takes
effect; without it, the global config silently wins.

### Verify the pin is actually in effect

A pin that is not applied looks exactly like a pin that is, which is the whole problem.

```bash
elixir --version        # must read 1.20.3, not whatever is on PATH
```

**Check the compiler, not `mise current`.** `mise current` reports what the config
*says*; it happily prints `1.20.3-otp-29` while a shell without the shims on `PATH`
builds with something else. That drift is silent — the build succeeds, and only the PLT
filename (`dialyxir_erlang-29.0.5_elixir-1.19.5.plt`) gives it away.

Shims are typically absent in non-interactive shells (scripts, CI steps, tool-driven
sessions), because activation happens in an interactive shell profile. There, prefix
explicitly:

```bash
mise exec -- mix test
```

### Do not put `MIX_ENV` in `mise.toml`

`mix test` sets `MIX_ENV=test` only when it is not *already* set. An `[env]` entry
pinning `MIX_ENV = "dev"` — even though dev is Mix's own default, so it looks like a
no-op — makes the whole suite run against the dev repo, which has no
`Ecto.Adapters.SQL.Sandbox` pool. The failure surfaces as a confusing sandbox error in
`test_helper.exs`, far from its cause.
