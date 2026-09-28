# Fast quality-check audit — 2026-09-27

**Scope.** Compared Pramāṇa `535a6743` with LokaCore `63f22db` on their local
`main` branches. This is a source and compiler-manifest audit, not a corpus gate or
a live CI result. The [shared workflow](WORKFLOW.md) now uses LokaCore's role loop;
[testing](../TESTING.md) remains the owner of operating check commands.

## What exists here

Pramāṇa CI already runs forced warnings-as-errors compilation, formatting, full
Credo, tests and a release build. Its [xref collector](../../.github/workflows/ci.yml)
exports revision-labelled graphs for each umbrella app; the
[dependency review runbook](DEPENDENCY_REVIEW.md) uses `mix xref callers` and scoped
graphs. [Documentation CI](../../.github/workflows/docs.yml) runs the dependency-free
documentation, pilot-contract and convention checks. The
[architecture tests](../../apps/pramana/test/architecture/boundaries_test.exs) guard
web database access and sidecar imports, among other project-specific behaviors.

The local `MIX_ENV=test mix compile --force --warnings-as-errors` passed. A fresh
per-app `mix xref graph --no-compile` then found:

| App | Cycles | Compile-connected edges |
|---|---:|---:|
| `pramana` | 1 (`acquire/cbeta` → `normalize/cbeta` → `pipeline` → `segment/taisho`) | 1 (`quotations/roots` → `relations`) |
| `pramana_native` | 0 | 0 |
| `pramana_web` | 1 (reader components, LiveViews, router and endpoint) | 19 (`mcp/server` → tool modules) |

Thus LokaCore's `--fail-above 0` commands fail here at this revision. These edges
are visible in the existing reports. A zero gate would turn current CI red; an
arbitrary count allowance would assert an architectural limit this project has not
reviewed. Keep the graphs advisory and inspect touched callers. Reconsider a failing
threshold after the relevant cycle or compile edge has been assessed and removed.

## Transfer decisions

| LokaCore practice | Decision for Pramāṇa |
|---|---|
| PM brief, developer self-review, fresh independent reviewer, fix and scoped re-review | Adopted in [the shared workflow](WORKFLOW.md), without model-specific roles or mandatory review files. |
| `mix xref callers` and graph inspection | Already present; explicitly routed from the workflow. Graphs are per app and do not prove runtime-selected dependencies. |
| `ast-grep` syntax search and tested lint rules | Adopt syntax search in the workflow. Add a CI rule only for a new, specific invariant with a positive case and a red control. Current architecture tests already cover the obvious web/sidecar rules. |
| `Boundary` strict compiler | Defer. The [app-level map](../REPO_MAP.md) already exists, and architecture tests check parts of it. A stricter public-module map needs a reviewed interface, not a declaration of every call made today. |
| Sourceror | No LokaCore check uses it. It is an Elixir AST editing library, not a quality gate; no source rewrite here needs it. |
| File/function size limits | Defer as a gate. At this revision, 56 tracked non-test Elixir files exceed LokaCore's 300-line source limit and four tests exceed its 500-line test limit. Review touched files for unnecessary size without a repo-wide red check. |
| Credo complexity limits and red controls | Existing full `mix credo --strict` passed with zero issues. Its config uses the default check set; replacing it with four custom checks would drop established coverage. Keep current checks and require a red control for any newly added custom guard. |
| Minimal, meaningful tests | Existing [test guidance](../TESTING.md#behavior-first-test-maintenance) already asks for plausible regressions. Adopt independently checked expectations, controlled inputs, small fixtures and a focused red control for nontrivial new guards or behavior. |
| Small, accurate docs | Existing [maintenance guidance](../MAINTAINING_DOCS.md) already assigns one owner per fact. Add a final diff pass for duplicate facts and stale instructions, as LokaCore does at milestone gates. |
| TypeScript kernel, mobile and protocol checks | Do not copy: Pramāṇa has no corresponding TypeScript semantic kernel or phone app. |

The structural scans used `ast-grep --lang elixir -p ... --json`. No `use Boundary`
or Sourceror dependency was found in Pramāṇa; LokaCore has eight `use Boundary`
declarations and no Sourceror dependency. The file-size counts used tracked file
lengths. These facts describe the named revisions, not future checkouts.

For the Boundary decision, web source aliases 27 distinct `Pramana.*` domain
modules, including `Pramana.Retrieval.Semantic` and `Pramana.Cbeta.Collections`.
Fresh `mix xref callers` confirms web calls to both and no direct web caller of
`Pramana.Repo` in the compiled graph. Exporting all current callees would freeze
that broad surface as the contract. First identify a smaller public domain interface if a concrete
boundary violation or interface change calls for it.
