# Retired files

Documents, scripts and experiments removed from the working tree, with links to the last
revision that held them. Every link opens that **pinned revision**, not the current branch:
its commands, prices, results and proposed APIs are historical, not approved procedures.
Git history keeps everything; nothing here was purged.

[Documentation](README.md) · [Repository map](REPO_MAP.md)

## Retired 2026-09-24: the single-product cleanup

Foundry left on 2026-09-23. This pass removed the two-product layout machinery, finished
the local-data cutover, cut the plan to its open work and retired one-off records.

| Retired path | What it was | Now |
|---|---|---|
| [`docs/PLAN.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN.md) | Full plan before the 2026-09-24 cut | [Plan](PLAN.md) keeps the open work |
| [`docs/PLAN_INDEX.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/PLAN_INDEX.md) | Navigation for the long plan | [Plan](PLAN.md); no longer long enough to need an index |
| [`docs/REPOSITORY_STRUCTURE.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/REPOSITORY_STRUCTURE.md) | 2026-09-15 review proposing the two-product sibling layout | [Repository map](REPO_MAP.md); implemented, then Foundry moved out |
| [`docs/LAYOUT_MIGRATION.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/LAYOUT_MIGRATION.md) | Cutover and rollback guide for the sibling-layout migration | Completed 2026-09-24; local data now lives under `pramana/` |
| [`bin/check_local_layout.exs`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/bin/check_local_layout.exs) | Read-only preflight for legacy local-data paths | Retired with the completed cutover |
| [`test/local_layout_test.exs`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/test/local_layout_test.exs) | Tests for that preflight | Retired with it |
| [`bin/pramana-modal`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/bin/pramana-modal) | Root compatibility wrapper | Use `pramana/bin/pramana-modal` |
| [`bin/pramana-tranche`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/bin/pramana-tranche) | Root compatibility wrapper | Use `pramana/bin/pramana-tranche` |
| [`docs/TEST_AUDIT.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/TEST_AUDIT.md) | Behaviour-first test audit, 2026-09-15 | [Testing](TESTING.md) |
| [`docs/audits/2026-09-15/README.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/audits/2026-09-15/README.md) | Documentation audit, 2026-09-15 | [Maintaining docs](MAINTAINING_DOCS.md) |
| [`docs/audits/2026-09-15/INVENTORY.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/audits/2026-09-15/INVENTORY.md) | That audit's file inventory | Historical record |
| [`docs/audits/2026-09-15/inventory.json`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/audits/2026-09-15/inventory.json) | Machine-readable inventory | Historical record |
| [`docs/strategy/FOUNDRY.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/docs/strategy/FOUNDRY.md) | Foundry product strategy | Moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/PRODUCT.md) |
| [`pramana/docs/harness/04-10-parallel-track-the-self-improving-supervisor-foundry-s-own-met.md`](https://github.com/lorecrafting/pramana/blob/2ad8ed912a5ed1c30e8f4f1e97ce069fd1400c94/pramana/docs/harness/04-10-parallel-track-the-self-improving-supervisor-foundry-s-own-met.md) | Foundry's meta-harness chapter | Moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md) |

## Retired 2026-09-15: documentation audit cleanup

Pinned to `21f298bb`. The guide copies were archived during that audit after current
source-backed guides replaced their operating instructions; the experiments had no
tracked consumers.

### Superseded guide snapshots

Every link below opens the **pre-cleanup revision**, not the current branch. Old
commands, prices, results and proposed APIs are historical, not approved procedures.
For nested chapters, the linked parent index resolves them within that same revision.

| Retired path | Current owner / reason |
|---|---|
| [`docs/records/architecture-design.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/architecture-design.md) | [Architecture](ARCHITECTURE.md); superseded design snapshot |
| [`docs/records/cloud-pricing-2026-08-14.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/cloud-pricing-2026-08-14.md) | [Compute guidance](CLOUD.md); dated pricing snapshot |
| [`docs/records/deployment-notes.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/deployment-notes.md) | [Deployment](DEPLOY.md); superseded operating/security claims |
| [`docs/records/development-environment.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/development-environment.md) | [Setup](DEV_ENV.md); old tuning and incident notes retained in Git history |
| [`docs/records/embedding-measurements.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/embedding-measurements.md) | [Embeddings](EMBEDDING.md); old measurements retained in Git history |
| [`docs/records/gpu-runbook-measurements.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements.md) | [GPU runbook](GPU_RUNBOOK.md); retired run/measurement snapshot |
| [`docs/records/gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements/01-a-long-tranche-detach-it-and-supervise-it-by-asking-modal.md) | [GPU runbook](GPU_RUNBOOK.md); retired run/measurement snapshot |
| [`docs/records/gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements/02-index-build-cost-at-scale-measured-2026-08-27.md) | [GPU runbook](GPU_RUNBOOK.md); retired run/measurement snapshot |
| [`docs/records/gpu-runbook-measurements/03-4-verify.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/gpu-runbook-measurements/03-4-verify.md) | [GPU runbook](GPU_RUNBOOK.md); retired run/measurement snapshot |
| [`docs/records/language-and-runtime-design.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/language-and-runtime-design.md) | [Language boundaries](ELIXIR.md); superseded design assessment |
| [`docs/records/layer-design.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/layer-design.md) | [Layers](LAYERS.md); superseded layer design |
| [`docs/records/mcp-interface-notes.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes.md) | [MCP](MCP.md); superseded interface snapshot |
| [`docs/records/mcp-interface-notes/01-tools.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes/01-tools.md) | [MCP](MCP.md); superseded interface snapshot |
| [`docs/records/mcp-interface-notes/02-errors.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/mcp-interface-notes/02-errors.md) | [MCP](MCP.md); superseded interface snapshot |
| [`docs/records/observability-audit.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/observability-audit.md) | [Observability](OBSERVABILITY.md); superseded capability audit |
| [`docs/records/translation-design-and-experiments.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments.md) | [Translation](TRANSLATION.md); old design/experiments retained in Git history |
| [`docs/records/translation-design-and-experiments/01-the-reframe.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments/01-the-reframe.md) | [Translation](TRANSLATION.md); old design/experiments retained in Git history |
| [`docs/records/translation-design-and-experiments/02-the-promotion-pipeline.md`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/docs/records/translation-design-and-experiments/02-the-promotion-pipeline.md) | [Translation](TRANSLATION.md); old design/experiments retained in Git history |

### Experiments and scaffolding

| Retired path | Reason |
|---|---|
| [`bin/archive/arm_depth_probe.sh`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/bin/archive/arm_depth_probe.sh) | One-off retrieval-arm probe; no tracked filename consumers |
| [`bin/archive/depth_abba.sh`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/bin/archive/depth_abba.sh) | One-off depth experiment; no tracked filename consumers |
| [`bin/archive/ngram_fix_validate.sh`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/bin/archive/ngram_fix_validate.sh) | One-off n-gram validation wrapper; maintained evaluation tasks remain |
| [`evals/archive/build_query_translation_arms.py`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/build_query_translation_arms.py) | Archived generator with hardcoded operator paths and historical case assumptions |
| [`evals/archive/dense_vs_prose.exs`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/dense_vs_prose.exs) | Archived probe; incident lessons and regression protections remain |
| [`evals/archive/pali_miss_diagnosis.exs`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/pali_miss_diagnosis.exs) | Archived diagnostic for a dated corpus/gold set |
| [`evals/archive/query_translation_arm_a.jsonl`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/query_translation_arm_a.jsonl) | Archived query arm, not the active gold set |
| [`evals/archive/query_translation_arm_b.jsonl`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/query_translation_arm_b.jsonl) | Archived query arm, not the active gold set |
| [`evals/archive/sweep-20260827T191912/control.json`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/archive/sweep-20260827T191912/control.json) | Lone historical sweep control, not the active baseline |
| [`evals/depth200_experiment.json`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/depth200_experiment.json) | Unreferenced historical scorecard, not the active baseline |
| [`evals/per_tradition_experiment.json`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/evals/per_tradition_experiment.json) | Unreferenced historical scorecard, not the active baseline |
| [`apps/pramana_web/priv/static/images/logo.svg`](https://github.com/lorecrafting/pramana/blob/21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f/apps/pramana_web/priv/static/images/logo.svg) | Unused Phoenix scaffold asset; no tracked import/template/test references |

Retiring the unused logo removes the old `/images/logo.svg` static URL; it does not
remove the CSS/JS vendor assets, favicon, robots file or reader functionality.

## Retained deliberately

All existing Foundry files, roles, tests, migration/repair records, implementation
log and review evidence are unchanged (they moved to [lorecrafting/foundry](https://github.com/lorecrafting/foundry) on 2026-09-23). So are the active PLAN, formal ROADMAP,
new product strategy, source/translation manifests, lockfiles, gold cases, evaluation
baseline, native code and regression tests. History, proxy studies and stable rules
remain locally available. Small matching fixture/configuration files are not
assumed redundant merely because their bytes match.

The tracked-file census did not find checked-in runtime `.log` files, BEAM/Python
bytecode, crash dumps, ZIP/tar archives or dependency/build trees to delete. JSON and
JSONL often encode authoritative inputs or test evidence, not disposable logs.
This is not a secret scan, dependency vulnerability audit or proof that every dynamic
runtime reference has been discovered.

Ignored local data, provider credentials, databases, running worktrees and GitHub
Actions artifacts are outside this PR. A repository snapshot cannot establish their
local contents or safe retention. No local-state cleanup, history rewrite, branch
removal or Actions-artifact deletion was performed.

## Keep future cleanup conservative

Use dedicated ignored scratch/output directories. The cleanup added missing Foundry
coverage/ExDoc output ignores (removed with Foundry on 2026-09-23) and Python bytecode-cache ignores; it does not add a
blanket JSON, JSONL, log or experiment-file ban. A reproducible test fixture or
accepted evidence record is allowed to be tracked with an explicit owner.

Before retiring a file, check exact paths and basenames, imports/configuration,
globs, generated consumers and active work. No search hits alone do not prove dead
code. Preserve an immutable recovery link when a removed file carries historical
value; update every current incoming link in the same change. Do not change a
baseline, erase a failed experiment or discard repair evidence to make the tree
look cleaner. Retire superseded instructions, not the record of why a rule exists.

For offline recovery, a clone must contain the historical commit. A shallow clone
may need the relevant history fetched first; the web links require repository access.
Inspect the file without restoring it into a live checkout, for example:

```bash
git show 21f298bb0913fe8aa93e7dd71e18d4106c1ffe6f:evals/archive/dense_vs_prose.exs
```

Recovery is for inspection. Do not run retired scripts against live state without
rechecking their paths, dependencies, permissions and experimental assumptions.
Documentation checks validate current relative links; they do not fetch historical
URLs or reproduce retired experiments. The cleanup review separately checks the
retired targets and preserved anchors against the captured pre-cleanup tree.
