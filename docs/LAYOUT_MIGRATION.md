# Sibling-layout migration and operator cutover

**Scope:** tracked-source migration from the cleanup baseline
`8d4e8ee5513dc631538f638fdf53e0678c8dc370`. This guide does not execute the cutover.
[Structure](REPOSITORY_STRUCTURE.md) · [Repository map](REPO_MAP.md) · [Testing](TESTING.md)

## What changes, and what does not

Pramāṇa's source, Mix files, internal apps/config, native/model companions, manifests,
evaluation inputs, scripts and product guides live under `pramana/`. Foundry remains
at `foundry/`. Shared strategy, PLAN, formal ROADMAP, workflow and review records
stay in repository `docs/`. Product-specific guides formerly at `docs/*.md` have
small forwarding pages with their principal bookmarks intact.

Nothing in this PR moves or deletes an ignored directory, corpus, database, credential,
model, virtualenv, accepted build, transcript or running worktree. Source renames do
not imply a runtime migration. Existing Foundry repair evidence and policy remain
unchanged; the new router is not acceptance of any repair capability.

## Coordinate before changing an active checkout

Finish or checkpoint the other session's owned work before switching the checkout
it is using. Review `git status` and `git worktree list`; do not force-reset, clean,
move or rebase a running task's directory. Review the stacked cleanup and migration
PRs independently. A separate worktree is suitable for source review and isolated
checks; it must not inherit production-state write authority.

Record the previous commit, environment values, database selection, client commands
and Foundry project/check mappings. Keep any required backups under the existing
operator retention policy. There is no automatic Git branch switch or data-copy script.

## Working-directory switch

Run product commands from the repository root explicitly:

```bash
bin/pramana mix deps.get
bin/pramana mix compile
# Or enter the project first: cd pramana
```

Foundry commands continue inside `foundry/`; its separate `foundry/bin/pramana`
operator CLI is not the root `bin/pramana` project dispatcher. Update only affected
Pramāṇa assignment/check commands under the governing workflow. In a Git worktree,
Git operations still apply to the entire repository; product commands use that
worktree's `pramana/` directory. A Git root is not a product root.

The root no longer has `mix.exs`. Do not make a new root umbrella, merge lockfiles,
or use `apps/foundry` to restore an old command. Old root `bin/pramana-mcp`,
`bin/pramana-modal` and `bin/pramana-tranche` forward to their product counterparts.
The root MCP configuration uses `./pramana/bin/pramana-mcp` directly.

## Select existing data explicitly

For an existing checkout whose ignored `raw/`, `priv/models/`, Python virtualenv
or local source text stays at repository root, set an **absolute** data root in the
specific operator shell/client environment:

```bash
# Run from the repository root containing pramana/ and foundry/:
export PRAMANA_DATA_ROOT="$PWD"
```

A fresh checkout with no legacy data defaults to `pramana/` for product-local data.
To deliberately use a separate new product-local dataset despite old data being
present, explicitly choose `PRAMANA_DATA_ROOT="$PWD/pramana"` from repository root.
Do not choose that path accidentally and re-download or recreate an expensive corpus.
Relative and empty values are rejected. The guard checks known legacy directories;
it is not a discovery or backup tool for every possible external location.

| Item | Location after source migration |
|---|---|
| Tracked `sources.lock.json` | `pramana/sources.lock.json`; original bytes preserved |
| Default acquired source roots | `$PRAMANA_DATA_ROOT/raw/...` or the new project's `raw/...` |
| Fine-tuned model weights | `$PRAMANA_DATA_ROOT/priv/models/...` |
| Tracked local manifests | `pramana/sources/local/<id>/...` |
| Ignored text for those manifests | `$PRAMANA_DATA_ROOT/sources/local/<id>/text/` |
| A caller-supplied manifest outside the project | Its adjacent `text/`, unchanged |
| Modal virtualenv | `$PRAMANA_DATA_ROOT/priv/embed/.venv`, or absolute `PRAMANA_MODAL_VENV` |
| Python source and native source | `pramana/priv/embed/` and the product's native directories |
| Database | Existing server/database environment settings; no database move or migration runs automatically |
| Foundry runtime root | Existing operator-owned fixed root, unchanged |

Absolute source paths already stored in the database remain usable. Relative
`raw/...` provenance is resolved through the selected data root, and new default
raw provenance retains that logical shape. Non-raw externally supplied source paths
are recorded absolutely. Path records that were already malformed or split on
spaces are not retroactively repaired by a directory migration.

Explicit task `--root`/`--out` values still follow that task's documented CLI
semantics. `PRAMANA_DATA_ROOT` changes defaults, not arbitrary shell operands. Commands
such as `git clone ... raw/...` must use the intended absolute data destination when
it differs from the new project root. Generated evaluation/export scratch files
are not silently searched in old locations; specify them explicitly.

## Caches and private environments

Do not move `_build`, `deps`, native `target`, PLTs or virtualenvs just because source
moved. Absolute paths may be embedded in build products. Restore dependencies and
rebuild in the new product directory; leave old caches untouched until the new setup
has been checked and a separate cleanup is approved. Both old and new generated
paths remain ignored. New lockfiles are not generated by the migration.

An existing virtualenv stays at its old absolute path, preserving its shebangs;
`PRAMANA_MODAL_VENV` can select another existing environment. The Modal wrapper
preserves caller CWD, quoted arguments and exit status. Its only source alias maps
a missing legacy `priv/embed/*.py` operand to the moved product script. It does not
authenticate, install packages or launch jobs merely to verify a path.

## Validation before operator adoption

From a clean source checkout, run the root `elixir bin/check_docs.exs` suite. It
checks full documentation reachability, links, root boundaries, actual wrapper argv/
stdout behavior, data-root isolation and figure discovery without providers or a DB.
Then run the independent product checks in [TESTING](TESTING.md), including:

- Pramāṇa dependency restore, compilation, formatting, static checks and tests in
  `pramana/`; native and asset/release builds, plus `docker build ./pramana`.
- Foundry's existing isolated `elixir ci/run.exs` from `foundry/`; never use the live
  daemon/state as a test fixture. Review any changed assignment/check working directory.
- The intended read-only corpus checks in the actual permitted environment after
  explicitly selecting data/database roots. No automatic re-bake is necessary merely
  for a source move; verify recorded identity before considering data writes.

`MIX_ENV=test` config pins data to each fixture's project root and ignores the
operator `PRAMANA_DATA_ROOT`; acquisition tests must not write into a live corpus.
Corpus-tagged tests only see product-local fixtures under this test policy. This is
separate from intentionally running the operator's corpus verification commands.

CI's image smoke checks release assets, the native Unicode boundary and packaged
folio metadata without starting the application against a database. A successful
image build is not proof of live data access or public-deployment permissions.
Failures from external dependencies and unavailable corpus/provider checks must be
reported, not converted into a migration acceptance claim.

## Rollback

Stop only processes you own under the existing operating procedure; do not broadly
kill panes or other sessions. Use the recorded pre-migration commit in a clean
checkout/worktree, restore its client and assignment command mappings, and use its
matching build artifacts or rebuild there. Do not apply a blanket reset to another
session's work. This PR leaves old data and database state in place, so it supplies
no reverse data migration. Old source ignores the new data-root environment and
expects its old path semantics; restore the recorded environment as well.

A source revert cannot undo unrelated database writes, new corpus acquisitions,
provider charges or changes made after cutover. Those require their own backups,
receipts and recovery procedures. Merge readiness and operator deployment readiness
are different decisions; this PR performs neither automatically.
