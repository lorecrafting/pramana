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
2. **The Python embed sidecar** (Phase 1+) — BGE-M3 and Tibetan `botok`. This is the
   real container use case: an isolated Python/Torch environment we don't want
   polluting the host.
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
