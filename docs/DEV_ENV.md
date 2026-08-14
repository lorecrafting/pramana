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

1. **`pg_bigm`** (Phase 1) — the bigram index for Chinese. Not in Homebrew. Either
   compile from source against the brew Postgres (`make && make install` with
   `pg_config` on PATH — a few minutes), or use a prebuilt image. Try compiling first;
   it avoids putting the database in a container.
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
