# Sibling-project migration: cutover and rollback

**Scope:** tracked-source migration from cleanup candidate
`8d4e8ee5513dc631538f638fdf53e0678c8dc370` (PR #3). The migration PR is stacked on
that cleanup until it merges. This is not an instruction to merge or activate it.
[Current map](REPO_MAP.md) · [Original structure review](REPOSITORY_STRUCTURE.md) ·
[Testing](TESTING.md).

**Superseded for Foundry 2026-09-23:** Foundry moved to
[lorecrafting/foundry](https://github.com/lorecrafting/foundry); `foundry/` rows below describe the pre-split layout.
The Pramāṇa cutover and rollback guidance still applies.

## What changes

| Before, relative to Git root | After |
|---|---|
| `mix.exs`, `mix.lock`, `config/`, `rel/`, `apps/` | Same layout inside `pramana/` |
| `native/`, `priv/`, `sources/`, `evals/`, `sources.lock.json` | Inside `pramana/`; source/dependency lockfile contents unchanged |
| Pramāṇa `.credo.exs`, `.formatter.exs`, `.iex.exs`, Docker files | Inside `pramana/`; root formatter now covers shared scripts/tests only |
| Product `bin/pramana-*` implementations | `pramana/bin/`; old root paths forward without duplicating logic |
| Pramāṇa topic docs and their chapters | `pramana/docs/`; internal links updated to the new owners |
| Shared documentation tests in the domain app | `test/docs/`; standalone checker remains `bin/check_docs.exs` |
| Foundry source, runtime configuration and repair records | Same `foundry/` location and contents; new scoped agent router only |

The shared `docs/PLAN.md` and `docs/ROADMAP.md` stay byte-identical. Their old
backticked Pramāṇa project paths and commands are interpreted from `pramana/` now;
Foundry instructions still belong to `foundry/`. They retain their owning repair
status, phase numbers and decisions. Shared strategy/audit links are rebased where
needed without re-accepting their historical claims.

## Four roots with different meanings

**Git root:** the directory containing this repository's working tree. In a linked
worktree `.git` is a file, not necessarily a directory. Git commands can run in
Pramāṇa or Foundry and still refer to this same repository.

**Project root:** `pramana/` for its Mix umbrella, source manifests, evaluation files,
native/model helpers and relative CLI arguments; `foundry/` for its independent
Mix project. All three Pramāṇa children keep their `../../` build/config/lock paths.
No new common Mix parent or merged dependency lock is introduced.
The Pramāṇa umbrella now prepares its test database before recursive application
startup; the previous child-only alias could fail on a fresh database.

**Documentation roots:** `pramana/docs/` for research-product references;
`foundry/docs/` for execution contracts; root `docs/` for shared concerns and the
still-active plan. Figure generation explicitly scans both the Pramāṇa and shared
document roots so it continues to find STATUS and PLAN blocks. No figures are
remeasured by this move.

**Runtime/data roots:** operator-controlled locations. Foundry's existing fixed or
explicitly configured operator runtime root is unchanged. Databases, accepted
builds, provider credentials, worktrees, raw corpora, model weights and virtualenvs
are not relocated, deleted, activated or rebuilt by source renames.

## Before switching an existing checkout

Coordinate a quiet cutover with the active repair session. Finish or checkpoint its
work through the existing workflow; do not close unrelated panes, edit live ticket
state or assume a source merge changes a running release. Record branch, commit,
worktree paths, configured project commands and runtime locations. Keep a recoverable
backup of operator data under its existing policy.

Use a clean, separate checkout/worktree to review the migration first. Build outputs
and dependencies should be rebuilt under each product, not copied from the old
`_build/` tree with embedded absolute paths. Existing accepted Foundry releases are
separate operational artifacts and must not be casually rebuilt or replaced.

The source commit does not migrate your ignored files. Before acquiring anything,
changing the database or enabling inference, run at the Git root:

```bash
mise exec -- elixir bin/check_local_layout.exs
```

This read-only, bounded inventory reports legacy `raw/`, `bake/out`, model weights,
virtualenvs, PLTs and local-source text/raw directories. Exit 2 means review is needed;
exit 0 is not a full disk, secret, worktree or runtime-health audit. Nothing is moved.

For raw data already at `CHECKOUT/raw`, an **explicit operator-created local bridge**
can keep the existing bytes in place. From the Git root, after confirming the target:

```bash
# Optional bridge, not part of the PR and not an automatic migration step.
test -d raw && test ! -e pramana/raw && test ! -L pramana/raw && ln -s ../raw pramana/raw
```

New raw downloads otherwise live under `pramana/raw/`. Do not let two independent
raw trees grow by accident. Choose either a reviewed bridge or a separate deliberate
data move; never merge them blindly. A direct link is recognized by the preflight.
Root and project ignore patterns protect both locations, including symlink entries.

Treat `priv/models`, local `sources/local/<id>/text` or `raw`, and other operator
artifacts the same way, with each path inspected explicitly. Preserve relative
source paths and hashes. Do not blanket-link old `priv/` or `sources/`: these contain
tracked files now owned by the new project. Recreate the Python virtualenv under
`pramana/priv/embed/.venv` from the approved requirements rather than assuming its
absolute shebang paths are relocatable. Do not delete the old environment first.

Keep DATABASE_URL and database names unchanged unless a separate operation explicitly
changes them. Compare source manifests and representative resolved source paths before
running any bake. Run corpus verification only in its authorized real environment;
model-free CI cannot establish equivalence of an operator's ignored data.

## Commands, editors and Foundry assignments

Pramāṇa commands now run from `pramana/`. At the Git root,
`bin/pramana-mix test` is an explicit convenience, not a shared umbrella. A bare
`mix test` at the Git root is no longer a product test command. Shared formatting
and `elixir bin/check_docs.exs` remain available there without project dependencies.

Root `.mcp.json` still uses the compatible `bin/pramana-mcp` path. A project-local
`.mcp.json` supports opening `pramana/` directly. Editor configurations outside Git
may have absolute paths; inspect/update those separately. Both wrappers keep compiler
output out of the JSON-RPC stdout stream and preserve failure exit status.

Modal/tranche wrappers now use the Pramāṇa project context. Supply absolute paths for
external inputs/outputs; project-relative module paths resolve under `pramana/`.
A shell prompt, credential or valid tool binary is not authorization to run a GPU job.

Foundry's own directory, CLI and accepted runtime root remain unchanged. At admission
of new **Pramāṇa** work, project/check commands must enter the task checkout's
`pramana/`, while Git operations and owned-file paths remain repository-relative
(`pramana/apps/...`). Old in-flight path ownership/review evidence must be reconciled
through the existing workflow; do not rewrite its artifacts or substitute a different
candidate. Existing stale `cd workflow` fallback strings remain the repair owner's
issue, not a newly authorized command or a hidden repair in this migration.

## Validation and remaining acceptance

The migration separates a pure path-move commit from explicit fixes. Validation must
cover a fresh checkout and a linked worktree, both project builds/tests, root-only
document checks, source/dependency lockfile preservation, native manifests, assets,
release assembly and the product-local Docker context. Build cache keys deliberately
change; an old root cache is not proof of the new layout.

Pramāṇa CI keeps the quality checks. Migration-relevant tests/release steps should
still run after an unrelated quality failure when compilation succeeded; the job
must stay red for that failure. Foundry's existing isolated model-free runner remains
independent. Read actual PR check results, not this checklist, for executed evidence.

Live operator cutover, corpus fidelity, real-provider conformance, recovery with
existing task worktrees and activation/rollback of accepted releases require their
own existing acceptance procedures. This PR does not certify those outcomes.

## Rollback

Keep old ignored data in place until the new workflow is verified. To review or return
to the old source layout, prefer a separate worktree at the recorded pre-migration
commit. Rebuild that revision's development dependencies there as needed. Do not
force-reset a checkout containing another agent's work, or run `git clean -fdx`.

For a merged-code rollback, revert the migration commits together in reverse order
on a reviewed branch, resolving intervening work explicitly. Do not revert the
Foundry repair commits or cleanup PR merely to undo this layout. Undo only the local
bridges/editor settings you intentionally added; inspect each symlink before removal.
No database rollback is implied, since the source migration changes no schema or data.
Live Foundry rollback still uses its governing deployment protocol and accepted build.
