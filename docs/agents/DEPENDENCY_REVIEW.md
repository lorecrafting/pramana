# Compiler dependency review

**Executable runbook for Pramāṇa engineering.** Use native `mix xref` as a source
navigation aid before changing shared modules, interfaces, macros or file ownership,
and again when reviewing the candidate. This is not a new graph service, runtime
MCP tool, Foundry repair gate, architectural score or automatic test selector.

[Shared workflow](WORKFLOW.md) · [Repository map](../REPO_MAP.md) · [Testing](../TESTING.md)

## Safe starting point

Work in your own authorized development checkout/worktree, using the pinned
[toolchain](../../mise.toml) and installed project dependencies. Do not compile
untrusted changes in an operator or production runtime: Mix loads project/config
code, compilation executes macros, and `xref trace` recompiles its target file.
These commands do not request application startup, corpus acquisition or providers,
but that does not make arbitrary compile-time code side-effect-free.

From the Git root, record the context and compile before reusing manifests:

```sh
git rev-parse HEAD
git status --short
(cd pramana && MIX_ENV=test mix compile --force --warnings-as-errors)
```

Proceed only if compilation succeeds. `MIX_ENV=test` matches CI; record a different
environment explicitly and do not compare it as equivalent. Test support modules
may be compiled in this environment, but ordinary ExUnit test files are not a
complete part of this dependency graph. No database needs to be started for the
standard compile/xref commands; dependency setup and compilation still need the
project/native toolchain. Do not run `mix setup` to satisfy this runbook.

`--no-compile` below is valid only while the source, config, dependencies and build
artifacts remain those just compiled. Recompile after edits, branch switches,
merges or cache restoration. On dirty source, a commit SHA alone does not identify
the result: retain the relevant diff/new-file hashes or commit a review candidate.
If the required build is unavailable, use search and direct source reads and report
compiler evidence as unavailable, not an empty graph or a passing check.

## Find callers across the application boundary

For an interface change, search each application rather than only the defining one.
This also finds references to a target module from a different app, without merging
ambiguous file paths. Example from the Git root, after the successful compile above:

```sh
(
  set -eu
  for app in pramana/apps/*; do
    test -f "$app/mix.exs" || continue
    printf '\nApplication: %s\n' "$app"
    (cd "$app" && MIX_ENV=test mix xref callers Pramana.Release --no-compile)
  done
)
```

Replace `Pramana.Release` with the actual module under review. `callers` reports
referring **files**, labelled `compile`, `export` or `runtime`, not a complete
function/arity-level call graph. Keep the application heading with each path.
No output can mean no recorded references, an unknown module or unsuitable/stale
scope; first locate the definition and verify the compilation context. It never
proves that deletion is safe. `callers` and `trace` cannot run at the umbrella root.

Inspect the reported files and relevant tests. Supplement with literal searches
for the module/function, callback names, messages, configuration keys, SQL/schema
references and external consumers. Runtime-selected implementations, process
registrations, protocols and messages need explicit source/behavioral investigation.

## Ask a scoped question, not for the entire graph

Example from the Git root, using application-local paths:

```sh
(
  set -eu
  cd pramana/apps/pramana
  MIX_ENV=test mix xref graph --no-compile --sink lib/pramana/release.ex --only-nodes
  MIX_ENV=test mix xref graph --no-compile --source lib/pramana/release.ex
  MIX_ENV=test mix xref graph --no-compile --format stats
  MIX_ENV=test mix xref graph --no-compile --format cycles --label compile-connected
)
```

`--sink` follows dependents; `--source` follows dependencies. Both may include
indirect relationships. Graphs here contain only this application's files and
internal edges; use the callers loop for cross-app interface impact. Export and
compile dependencies take precedence over runtime references between a file pair.
High fan-in is a reason to inspect an interface, not evidence of bad design.
Compile-connected cycles are investigation targets, not an automatic refactor order.

To explain a dependency at source locations, deliberately recompile that file:

```sh
(cd pramana/apps/pramana_web && MIX_ENV=test mix xref trace lib/pramana_web/mcp/reply.ex --include-siblings)
```

`trace` executes compilation even if `--no-compile` is supplied; the flag only
suppresses the preliminary project compilation. The example therefore omits it.
`--include-siblings` on this trace includes declared `in_umbrella` dependencies,
not Foundry or every project in the Git repository.

## CI reports and optional local export

[Pramāṇa CI](../../.github/workflows/ci.yml) publishes `pramana-xref-<checkout-sha>-<attempt>`
after the existing forced compile. It uses native commands, with no Graphify,
new project dependencies or second call-graph implementation. Inside the artifact:

| File | Meaning |
|---|---|
| `metadata.json` | Actual checkout SHA/tree, run/attempt, timestamp, environment, tools, application roots and explicit limits |
| `source-files.sha256` | Hashes of tracked Pramāṇa files, `mise.toml` and the producing workflow, relative to the Git root |
| `toolchain.txt` | Actual Mix/Elixir/BEAM version output |
| `<app>/graph.json` | Native file-to-file dependency map; names are relative to that app, not the Git root |
| `<app>/stats.txt` | Native per-app dependency statistics |
| `<app>/compile-connected-cycles.txt` | Native compile-connected cycle report; no cycles is a valid result |

The collector requires clean unchanged source, the expected checkout SHA and
nonempty compiled manifests/graphs. It validates graph labels, target nodes and
source-file existence. Reports are not reused from a cache, written into source,
or uploaded if collection fails. Artifact retention is seven days; retain relevant
findings and their evidence references in the PR, not a permanent graph dump.

On a pull request, the actual checkout can be GitHub's synthetic merge commit.
Compare `metadata.json` to the candidate/base being reviewed; do not call a graph
of that merge commit a head-only analysis. Artifacts may exist when later checks
fail. Generation success establishes collection, not test success or acceptance.

For a local export, create a new directory outside the checkout after compilation:

```sh
(
  set -eu
  report_dir="$(mktemp -d "${TMPDIR:-/tmp}/pramana-xref.XXXXXX")"
  cd pramana/apps/pramana
  MIX_ENV=test mix xref graph --no-compile --format json --output "$report_dir/graph.json"
  printf 'Local app-only graph: %s\n' "$report_dir/graph.json"
)
```

This local command emits only a graph, not the CI provenance bundle. Record its
source/environment separately. Native DOT export is also available for an optional
local renderer; no renderer is installed by this change. Do not flatten umbrella
paths into an allegedly complete inter-app graph: native umbrella-root output is
not namespaced, and identically named child paths can collide.

## Implementation and independent review handoff

Keep the ticket's governing instructions first. The planner/developer records a
small dependency note; the independent reviewer queries the candidate rather than
trusting that note as complete. A useful PR note is:

```text
Dependency evidence: checkout SHA/tree (or dirty diff), MIX_ENV, app scope, command/run.
Affected interface: module/function or message/schema being changed.
Inspected dependents: relevant app-qualified paths and what must stay compatible.
Dynamic/non-Elixir gaps: configuration, messages, native code or external consumers checked.
Verification: regression tests run, failures/unavailable checks, remaining uncertainty.
```

Use findings to add inspections and meaningful regressions, never to skip suites,
certify deletion, approve a candidate or bypass review. No evidence means unknown,
not no impact. Do not attach an entire graph to every agent prompt. Start with the
target module and expand only as needed; retain access to full source and raw output.
This runbook does not launch subagents, choose paid models or change Foundry roles.

## Scope and deciding whether this helps

The CI reports analyze only the Pramāṇa child applications. Foundry is a separate
Mix project and remains outside this implementation; its repairs, active worktrees
and execution policies are untouched. Rust NIF bodies, the separate quotation
scanner, Python helpers, runtime message routes and corpus relationships are not
represented as a complete graph by `xref`.

For initial real tasks, record whether the check found an overlooked caller,
changed the test plan, or only added work. Compare investigation and review effort
with ordinary source search; no speed/token saving is asserted in advance. Add a
wrapper, visualizer or Graphify only after a specific remaining gap is demonstrated.

Semantics verified against [the pinned Elixir xref source](https://github.com/elixir-lang/elixir/blob/v1.20.3/lib/mix/lib/mix/tasks/xref.ex).
The native JSON format is available in this pinned toolchain; deprecated
`Mix.Tasks.Xref.calls/1` and private compiler-manifest parsing are not used.
