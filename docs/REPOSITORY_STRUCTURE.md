# Repository structure: sibling projects

**Source migration prepared:** 2026-09-15, following the cleanup at
`8d4e8ee5513dc631538f638fdf53e0678c8dc370`.
[Repository map](REPO_MAP.md) · [Operator migration and rollback](LAYOUT_MIGRATION.md) ·
[Cleanup recovery](RETIRED_FILES.md)

## Decision and implementation

Use a neutral repository root with independent `pramana/` and `foundry/` projects.
The earlier root-umbrella arrangement was valid; this change makes ownership and
working directories clearer without merging builds or turning Foundry into an
umbrella child. The operator requested preparation now; merging and switching an
active checkout still require coordination with the repair session.

Pramāṇa keeps its existing umbrella, module/application names, configuration within
that umbrella and dependency lockfile. Foundry keeps its directory, configuration,
lockfile, repair records and runtime. No new parent Mix umbrella is introduced.
[Mix's umbrella reference](https://mix.hexdocs.pm/Mix.Project.html#module-umbrella-projects)
explains the dependency/configuration boundary; Git co-location is separate from it.

```text
repository/
  README.md, AGENTS.md, CLAUDE.md, GEMINI.md
  mise.toml, .mcp.json, .gitignore
  .github/workflows/         explicit per-project jobs and shared checks
  bin/                      shared checks and narrow compatibility routes
  docs/                     shared strategy, plan, policy, migration, old bookmarks
  pramana/
    mix.exs, mix.lock        existing umbrella
    config/, rel/, Dockerfile, .dockerignore
    apps/                   domain, web/MCP, native NIF
    native/, priv/          native scanner, model helpers, tracked metadata
    sources/, sources.lock.json, evals/
    bin/, docs/, AGENTS.md
  foundry/
    mix.exs, mix.lock        existing independent OTP project
    config/, lib/, test/, bin/, ci/, rel/, roles/, docs/
    AGENTS.md               small shared-policy route
```

## Path contracts repaired

| Consumer | New contract |
|---|---|
| Mix commands | Run inside the selected project; root `bin/pramana` is an explicit convenience, not an implicit shared build |
| Pramāṇa config, lockfiles and assets | Resolve within `pramana/`; its three child Mix files keep their valid internal relative paths |
| Raw corpus, model weights and local private text | Explicit `PRAMANA_DATA_ROOT` can select the old location without moving data; ambiguous legacy data is not silently ignored |
| Acquisition tests | Test config binds data to each fixture's project root, ignoring an operator's external data environment |
| Source provenance / reproduction | Logical `raw/...` paths resolve against the selected data root; recorded absolute paths remain supported |
| Docker | Use `pramana/` as context; copy tracked folio-image metadata into application priv for release lookup |
| MCP and Modal | New product entry points plus narrow root compatibility routes; preserve stdout discipline, argv and failure status |
| Documentation and figures | Product guides move under `pramana/docs`; shared PLAN stays; checks/figure discovery cover both explicit locations |
| CI and caches | Pramāṇa commands and cache keys are product-scoped; Foundry retains its own CI/build roots |
| Foundry assignments | Operator updates affected product commands/working-directory mappings explicitly; no live ticket or policy rewrite is performed |

The migration adds path and wrapper regression cases to the model-free suite and
image/native verification to CI. Passing those checks does not establish corpus
fidelity, live provider conformance, operator cutover or Foundry repair closure.
Candidate-specific test results belong in the PR rather than being inferred here.

## Deliberate compatibility and remaining boundaries

Top-level old product guide links are forwarding bookmarks, not duplicated manuals.
Root MCP/Modal/tranche command wrappers remain for existing clients. There is no
root Mix wrapper, no root-to-project source symlink forest and no automatic move of
ignored corpora or caches. Old chapter-level source paths are a deliberate break;
use current indexes or immutable historical links. Shared active PLAN, formal
ROADMAP and existing Foundry files are preserved rather than mass-rewriting their
historical source references or ticket commands.

The [cutover guide](LAYOUT_MIGRATION.md) describes local caches, source manifests,
virtualenvs, paused worktrees and rollback. The previous review is recoverable at
[the pre-migration revision](https://github.com/lorecrafting/pramana/blob/8d4e8ee5513dc631538f638fdf53e0678c8dc370/docs/REPOSITORY_STRUCTURE.md).
Separate repositories remain a later packaging/access-control decision, not an
automatic consequence of this layout. No branding, package publication or provider
policy changes are bundled into the source move.
