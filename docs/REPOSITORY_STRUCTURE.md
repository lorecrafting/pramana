# Repository structure review

**Reviewed:** 2026-09-15 at `21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f`.
[Repository map](REPO_MAP.md) · [Cleanup and recovery](RETIRED_FILES.md) ·
[Product strategy](PRODUCT_STRATEGY.md)

## Migration status

The sibling-layout PR now implements the tracked-source portion of this proposal:
Pramāṇa under `pramana/`, unchanged Foundry location under `foundry/`, and a neutral
repository root. See [the current map](REPO_MAP.md) and [cutover/rollback](LAYOUT_MIGRATION.md).
The review below records the pre-migration baseline and remains the rationale;
it is not a claim that a live checkout, database or accepted release was relocated.

## Decision: valid now, clearer as siblings later

The current arrangement is technically sound: **a Pramāṇa umbrella at the repository
root, plus a standalone Foundry project in `foundry/`**. Directory nesting alone does
not make Foundry an umbrella child. The root Mix project uses `apps_path: "apps"`;
Foundry is outside that directory, has its own Mix project, lockfile, configuration,
release and CI. Root `mix` commands are not a build/test entry point for both products.

For two independently evolving products, a neutral root with `pramana/` and `foundry/`
as siblings is the preferred eventual organization. It makes ownership, working
directories and later extraction easier to understand. **The cleanup PR did not perform that move.** The separately requested migration
PR is reviewable now; coordinate its live cutover with active repair work. It is a path-contract migration, not a
correctness fix or a prerequisite for shipping either product.

Do not move Foundry into `apps/foundry/` to make the tree look symmetrical. Umbrella
children share configuration, dependency resolution and build paths. That would
change the boundary we need to preserve. A neutral root should not introduce a new
Mix umbrella covering both systems or a common dependency lockfile.

The distinction follows [Mix's official umbrella documentation](https://mix.hexdocs.pm/Mix.Project.html#module-umbrella-projects).
Separate directories, separate repositories and private packages are different ways
to package independent projects; none is required merely because two projects share Git.

## What the current files actually own

| Location | Owner and reason to keep it |
|---|---|
| `mix.exs`, `mix.lock`, `config/`, `rel/`, `Dockerfile` | Pramāṇa umbrella build, dependencies, configuration and deployment; not expendable scaffolding |
| `apps/pramana/`, `apps/pramana_web/`, `apps/pramana_native/` | Pramāṇa domain, web/MCP and Rust NIF applications; their shared umbrella remains appropriate for the existing release |
| `native/quotations/`, `priv/embed/`, `priv/derge/` | Pramāṇa's other native/model/data companions; keep their different runtime and build roles explicit |
| `sources/`, `sources.lock.json`, `evals/gold/`, `evals/baseline.json` | Source provenance and active evaluation inputs; size or generated origin does not make them disposable |
| `foundry/` | Independent Mix application and its execution contracts, repair evidence, tests and operator tooling |
| `.credo.exs`, `.formatter.exs`, `.iex.exs` | Root Pramāṇa developer tooling; their location does not automatically apply those rules to Foundry |
| `mise.toml`, `.github/workflows/` | Repository-hosted tooling; workflows still need explicit ownership and working directories |
| `.mcp.json`, `bin/pramana-*` | Pramāṇa client/wrapper entry points; not a provider-neutral Foundry command surface |
| `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `bin/check_docs.exs` | Shared routing and documentation checks; keep small and independent of either live runtime |
| `docs/` | Currently mixed: shared navigation/strategy and Pramāṇa references; Foundry's detailed contracts remain under `foundry/docs/` |

The [three child Mix files](../pramana/apps) point to the root build/config/deps/lock paths.
[Foundry's Mix file](../foundry/mix.exs) does not. Its
[boundary tests](../foundry/test/pramana_foundry/boundary_test.exs) and
[CI workflow](../.github/workflows/foundry-ci.yml) explicitly support independence.
This is source evidence about organization, not a fresh live-system acceptance.

## Real rough edges, not just cosmetic asymmetry

**Working-directory ambiguity.** At the repository root, `mix test` belongs to
Pramāṇa; Foundry uses its own directory and CI. Keep this explicit in task routing.
The shared documentation checker is the deliberate repository-wide exception.

**Root and project paths are conflated in some tooling.** Pramāṇa's
[configuration](../pramana/config/config.exs) defines its project root relative to `config/`.
The MCP wrapper is selected by [`.mcp.json`](../.mcp.json), while documentation tests
and figure generation assume repository-relative `docs/`. A sibling migration must
distinguish Git root, project root, documentation root and runtime/data root.

**Build-context leakage across products.** The root Dockerfile builds Pramāṇa only,
but the prior `.dockerignore` did not exclude `foundry/` or `.git/`. This cleanup adds
both exclusions. In particular, ignored local Foundry state must not become eligible
input to an unrelated Pramāṇa image build simply because it lives below the context
root. Git ignores do not filter Docker context. This is a context boundary, not a
claim that the previous Dockerfile copied Foundry state into its final image, or
that a complete secret scan has been performed. See
[Docker's context documentation](https://docs.docker.com/build/concepts/context/#dockerignore-files).

**Scaffolding versus dependencies.** The unused Phoenix `images/logo.svg` had no
tracked consumers and is retired. Vendored daisyUI, Heroicons and topbar files are
imported by the CSS/JS pipeline and stay. The conventional favicon and robots file
stay. The native `echo` function is tested for Unicode/FFI fidelity, not disposable
hello-world code. Root configuration and the empty domain namespace module are not
removed simply because they originated with a generator.

**Historical names are not garbage classifications.** Foundry's implementation log,
JSONL fixtures, migration records, matching VM argument files and repair attestations
still belong to active contracts/tests or their review trail. They are untouched.
PLAN is large and mixed-purpose, but owns active repair work; separate its product
and historical sections only with that owner after repair closure. The existing
broad `*review*.json` ignore rule also deserves that owner's retention review; this
PR does not unignore potentially private local files as an incidental cleanup.

## Proposed layout from the original review

```text
repository/
  README.md                 two-product entry point
  AGENTS.md                 shared routing; thin provider shims beside it
  .github/workflows/        independent jobs with explicit project roots
  mise.toml                 common toolchain only while genuinely shared
  docs/                     shared strategy, decisions and repository policy
  bin/                      repository-wide checks only
  pramana/
    mix.exs, mix.lock        existing Pramāṇa umbrella, not a new architecture
    apps/                   domain, web and native applications
    config/, rel/           Pramāṇa runtime and release configuration
    Dockerfile              with an explicitly chosen build context
    native/, priv/          Pramāṇa native/model companions and assets
    sources/, evals/         source metadata and evaluation inputs
    sources.lock.json       existing provenance retained
    bin/, docs/             Pramāṇa commands and references
  foundry/
    mix.exs, mix.lock        existing standalone project
    config/, lib/, test/
    bin/, ci/, rel/, roles/, docs/
```

This schematic describes tracked source, not a direction to relocate ignored
corpora, credentials, live state, accepted builds or worktrees. Keep the current
checkout location and operator runtime root unless a separately reviewed operational
migration explicitly changes them. Moving Pramāṇa's tracked files alone need not
move Foundry's directory or its runtime root.

## Requirements carried into the structural PR

Proceed after repair acceptance, or under a separately agreed coordination window
with the repair owner. First map every consumer of repository and project paths:
CI and cache keys, Mix aliases/configuration, Docker COPY/context, asset tools,
release overlays, MCP clients, wrapper scripts, source acquisition/lockfile paths,
figure generation, documentation tests and Foundry project checkout/check commands.

Use one mechanical move commit, then explicit path fixes. Preserve module/application
names, behavior, source identities and independent lockfiles. Do not silently change
license/retention policies, move private data, add an inter-product dependency, or
renumber repair work. Scoped agent routers may be added at each project root, but
provider-specific instruction copies should not proliferate.

Require clean-checkout builds and tests for both projects, the standalone documentation
suite, native/assets/release verification, the chosen container build, and relevant
Foundry path/recovery acceptance in isolated environments. Confirm that neither
project needs the other's data or dependencies. Where corpus/provider evidence cannot
run, record the gap rather than declaring complete migration acceptance.

Provide rollback instructions, retained old-path bookmarks or deliberate compatibility
wrappers where needed, and a coordinated switch for local tooling. Keeping Foundry's
current directory minimizes churn but does not prove all assumptions survived.
Revisit separate repositories only if release cadence, access control, licensing or
external users actually require it; folder symmetry alone is not that evidence.
