# FR-21 independent review — frozen candidate 85a7449

Date: 2026-09-13 (Pacific/Honolulu)

## Verdict

**FAIL — do not integrate or mark FR-21 complete yet.**

The candidate has a sound happy-path foundation: two independent clean detached checkouts passed all six stages and 426 tests, used collision-free build/dependency/tmp/runtime roots, did not launch a provider or live daemon, deleted the tracked Owl tree/prebuilt escript/Python diagnostic, retired Python parity fail-closed, enforced the seven-entry formatter-debt hash baseline, and fixed the RPC test's build-path assumption.

However, five release-gate defects remain. The first four directly defeat FR-21's portability/provenance/failure-evidence outcomes; the fifth means the stated dependency-source policy is descriptive rather than enforced.

1. **Blocker / high — the supposedly Elixir-only model-free job has an undeclared host Python `tiktoken` dependency and fails without it.**
2. **Blocker / high — dirty/untracked source is compiled into the artifact while the run still reports `passed`; the artifact's actual source bytes are not identified.**
3. **Blocker / high — setup failures do not always emit a manifest, and rescued setup manifests omit required provenance and command/exit receipts.**
4. **Blocker / medium — the runner claims exact toolchain policy success for OTP 29.0.1 although the policy/workflow pin is OTP 29.0.5.**
5. **Blocker / medium — “lockfile-only Hex sources” is recorded but not enforced; an unpinned path dependency passes `mix deps.get --check-locked` and is omitted from dependency provenance.**

FR-22/provider/activation work is not a blocker here. I did not run a provider, Herdr, a daemon, corpus services, or foreign-pane cleanup. The lack of a bounded live-provider test remains correctly routed to FR-22.

## Frozen identity and diff verification

Reviewed repository: `/private/tmp/pramana-fr21`

- candidate commit: `85a74492959e6db51f4a0f03c218990afb97b0c3` — exact match
- candidate tree: `cc730c6bf3cd7b62a66cc59b754176b16ad98521` — exact match
- sole parent/base: `5d3acf4ff9e925b7de3a355048acfa9d6c548331` — exact match
- candidate document SHA-256: `b3a6e5bb95afbc8032e98afddd44d302cfd41f664767c750dcf8767c94d6c7c2` — exact match
- binary diff SHA-256 (`git diff --binary BASE CANDIDATE`): `f54080e365b5ae93a26910cc6eeef6da2ca455f3b3bf0f0a16f02eb23c46ab61`
- name-status SHA-256: `2ae75ccfcef98370a329fa5bb64389905340cbcdae26bd303cc4058814defe4e`
- `git diff --check BASE CANDIDATE`: exit 0
- diff scope: 41 paths, 736 insertions, 5,652 deletions
- candidate worktree after review: no tracked or untracked changes (`git status --short --untracked-files=all` empty)

Commands:

```sh
git -C /private/tmp/pramana-fr21 rev-parse HEAD HEAD^{tree} HEAD^
git -C /private/tmp/pramana-fr21 diff --binary BASE CANDIDATE | shasum -a 256
git -C /private/tmp/pramana-fr21 diff --name-status BASE CANDIDATE | shasum -a 256
git -C /private/tmp/pramana-fr21 diff --check BASE CANDIDATE
shasum -a 256 /private/tmp/pramana-fr21/foundry/docs/fr-21/candidate.md
```

## Blocking findings and minimal reproductions

### B1. Undeclared `python3`/`tiktoken` makes the hosted job non-portable

`foundry/lib/pramana_foundry/projections/benchmark.ex:162-179` invokes `python3` and imports `tiktoken`. If that import fails, the code silently changes the token-count algorithm. `test/pramana_foundry/projections/benchmark_test.exs:12` compares against a saved `tiktoken` result, so the default test suite fails. The workflow installs only BEAM (`.github/workflows/foundry-ci.yml:36-40`); `foundry/mix.exs` declares only Owl; neither Python nor `tiktoken` is pinned, installed, or included in provenance.

The two local passes accidentally inherited `tiktoken` 0.13.0 from the review host's user-site Python. Selecting a clean Homebrew Python without that package gives 425/426 tests and exit 2 in the CI runner. A targeted reproduction is:

```sh
cd CLEAN_CHECKOUT/foundry
PATH="PINNED_ELIXIR_BIN:PINNED_OTP_BIN:/opt/homebrew/bin:/usr/bin:/bin" \
  MIX_ENV=test MIX_BUILD_PATH=UNIQUE_BUILD MIX_DEPS_PATH=FETCHED_DEPS TMPDIR=UNIQUE_TMP \
  mix test test/pramana_foundry/projections/benchmark_test.exs --seed 0
```

Observed:

```text
ModuleNotFoundError: No module named 'tiktoken'
Assertion with == failed: assert first == saved_result()
Result: 0/1 passed
Failed: 1 test
```

This contradicts the project/runner claims that Foundry and this runner need nothing but Elixir plus locked Owl, and it leaves a material test input unidentified. The current Ubuntu 24 hosted-image inventory lists Python/pip but not `tiktoken`; more importantly, depending on ambient image packages would still violate the explicit provenance requirement.

Required correction: eliminate the Python runtime dependency from the default model-free gate (for example, isolate the already-recorded benchmark fixture from CI recomputation), or explicitly pin/install/hash/document Python and `tiktoken`. The latter expands Foundry's documented dependency boundary and needs an intentional design decision.

### B2. Dirty source passes and enters the escript without source identity

`source_provenance/1` records `git status` once (`ci.ex:274-280`) but does not reject dirtiness or hash dirty paths. Formatting enumerates only `git ls-files` (`ci.ex:228-247`). Mix compilation, however, compiles untracked `.ex` source.

In a disposable clone only, I added formatted `foundry/lib/pramana_foundry/dirty_probe.ex` with SHA-256 `f7ed947ef638cdcc2a1fda70d3c8ac026bbce3185c4ba02a4807b5aaa21c5a50`, then ran the exact CI runner. All six commands and all 426 tests passed. The resulting escript contains `Elixir.PramanaFoundry.DirtyProbe.beam`, but the manifest still identifies the frozen commit/tree and artifact only:

```json
{
  "result": "passed",
  "source": {
    "commit": "85a74492959e6db51f4a0f03c218990afb97b0c3",
    "tree": "cc730c6bf3cd7b62a66cc59b754176b16ad98521",
    "dirty_paths": ["?? foundry/lib/pramana_foundry/dirty_probe.ex"]
  },
  "artifact": {"sha256": "00c60950f6f0ecf5482f231f35bb2130e26b319032d64168237ebad1c1e95286"}
}
```

The probe's hash is absent; it also bypasses the format gate. Manifest SHA-256: `a946f8599f275109c867c356c2e9ddc8c8300de705e26d5d2650e124e4d7c5e4`.

Required correction: fail closed on a non-clean source checkout before executing work and re-check after execution, or fully hash and format every modified/untracked input and model deletions/mode changes. For this clean-checkout gate, rejecting dirtiness is simpler and less ambiguous.

### B3. Failure manifests are absent or materially incomplete

`main/1` does not create the output directory until after `project_root/0` and `create_run_root/0` succeed (`ci.ex:22-33`). Those `with` errors print to stderr and return 2 without writing a manifest. The rescue at `ci.ex:145-161` covers only exceptions inside `run/3`; it emits only `schema`, `result`, and `error`, then reraises. It contains no source/tree/dirty/toolchain/lock/isolation data and no command exit receipt.

Minimal reproduction, in a disposable exact-candidate clone:

```sh
rm foundry/mix.exs                  # disposable clone only
mkdir -p ARTIFACT_DIR
cd foundry
elixir ci/run.exs --output ARTIFACT_DIR
```

Observed exit 2 and:

```text
foundry CI setup failed: {:not_foundry_root, ".../foundry"}
```

`ARTIFACT_DIR/provenance.json` was absent. This makes workflow `upload-artifact` with `if: always()` fail to provide the promised evidence on a source/setup failure. Separately reproduced wrong-toolchain and missing-`mix` exceptions; their manifests were only:

```json
{"schema":"pramana-foundry-ci-provenance/v1","result":"setup_failed","error":"..."}
```

SHA-256 values: wrong toolchain `467872181cefdd3d7da40b315ff40d7bbdf9a78cdefe7be4407201e921a5c1d9`; missing executable `4822ea1b240897057f6f3fb137bdb140cfd899e42538f7fa8134cfa4061733d7`.

Required correction: establish the output directory and a skeletal evidence object before every fallible setup stage, then atomically write a final manifest on every exit path. Represent spawn/setup failures as command/stage receipts with explicit exit/error fields and preserve all provenance available at failure time.

### B4. Exact OTP 29.0.5 pin is reduced to major version 29

The workflow correctly asks setup-beam for OTP `29.0.5`, but the runner policy constant is only `"29"`, obtained from `System.otp_release/0` (`ci.ex:12-13,284-296`). I ran the candidate with Elixir 1.20.3 on OTP 29.0.1 / ERTS 17.0.1. Its manifest says:

```json
{
  "otp_release": "29",
  "expected_otp_release": "29",
  "emulator": "Erlang/OTP 29 [erts-17.0.1] ...",
  "matches_policy": true
}
```

Manifest SHA-256: `254be4f0aef98d80fdfaf32246ec2080b76beefe6c23569b5d9d05acb929d0c0`. That run later failed for B1, but the toolchain gate itself explicitly accepted the wrong patch version.

Required correction: derive and compare an exact OTP/ERTS version against the single canonical pin (or provide a tested canonical mapping), rather than labeling the major-only value as an exact policy match.

### B5. Lockfile-only dependency-source policy is not enforced

`dependency_provenance/1` asserts that lock entries have Hex shape, but merely records `tracked_dependency_sources` and `prebuilt_escript_tracked` (`ci.ex:299-326`). It does not reject either flag and does not inspect declared/resolved dependencies that have no lock entry. `mix deps.get --check-locked` permits path dependencies.

In a disposable clone, I added an external absolute path dependency to `mix.exs`, leaving `mix.lock` unchanged. Then:

```sh
MIX_DEPS_PATH=UNIQUE_DEPS mix deps.get --check-locked
MIX_DEPS_PATH=UNIQUE_DEPS mix deps
```

The first command exited 0; the second listed both Owl from Hex and the unpinned external path dependency. Its source bytes would not appear in `locked_packages` or any source hash. Thus the manifest's policy string, “Hex sources resolved from the committed lockfile,” is not a gate.

Required correction: validate the complete resolved Mix dependency set/SCM against the committed lock and reject path/git/unlocked sources; also fail if tracked dependency sources or a tracked prebuilt escript are found. Add negative tests for each prohibited source.

## Independent clean-checkout runs

Review root: `/private/tmp/fr21-independent-review.kS5OJB`

I used two separate `git clone --no-local --no-checkout` repositories, detached each at the frozen commit, and verified before execution that each checkout was clean and lacked `foundry/deps/` and `foundry/pramana_foundry`. Artifacts were written outside both clones. The command in each `foundry/` directory was:

```sh
PATH=".../elixir/1.20.3-otp-29/bin:.../erlang/29.0.5/bin:$PATH" \
  elixir ci/run.exs --output EXTERNAL_ARTIFACT_DIR
```

| Evidence | Run 1 | Run 2 |
|---|---|---|
| result | passed | passed |
| tests | 426/426 | 426/426 |
| six command exits | all 0 | all 0 |
| manifest SHA-256 | `c13cc324f6b1c0e45d67f52e123fd20f79ea7fbb4172cd3488c8c9327bc5141f` | `11e61eb4506ae8c641fca51ef78fa0f8452905ac7247f0caf8e7baa612c403e5` |
| escript SHA-256 | `3f535dc38177f6134166b81dc4c6d1ef8ec5a83a34fb879f7f56df638e4b8ff3` | `a2f543bc0464b6877890aaa347edda998907ece397844decb6c7580ee5e3eec6` |
| run root suffix | `9cwMxYDiCAkcR0_UoXsDSLca` | `sNCbqq9LzpsHWXMOBnpLJefl` |

Both manifests record:

- exact candidate commit/tree
- runner SHA-256 `739b25f37a4b3766244a30c2f87d0c925109ba7aee218dd740e862f26e70ef46`
- workflow SHA-256 `e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6`
- Elixir 1.20.3, OTP 29, ERTS 17.0.5
- lockfile SHA-256 `63191c494ab822546ef17d95030691bff62c44c382ecdaaf9f483308c655eab5`
- Owl 0.13.1 and both Hex checksums
- no tracked dependency sources and no tracked escript
- unique per-run `MIX_BUILD_PATH`, `MIX_DEPS_PATH`, `TMPDIR`, and operator runtime root beneath the random run root
- `COORDINATOR_TICK` and `HERDR_ENV` unset, provider launch disabled, foreign-pane cleanup not invoked
- all seven formatter-debt entries matched their pinned SHA-256 values

After each run, each source checkout remained clean and the generated source-tree escript had been removed. The two run roots were distinct; there was no collision or shared build/dependency/tmp/runtime path. No corpus/database/service was accessed.

The differing escript bytes are not an express FR-21 failure because the manifest identifies each built artifact, but they show that artifact-byte reproducibility is not established.

## Requirements assessment

### Satisfied in the frozen tree / happy path

- Foundry has its own path-filtered workflow and local runner.
- Action provenance is immutable and authentic: all three full SHAs resolve in the official upstream repositories:
  - `actions/checkout@11d5960a326750d5838078e36cf38b85af677262` = v4.4.0
  - `erlef/setup-beam@54075bcc5e249e4758d363f27d099f55d843f124` = v1.24.1
  - `actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02` = v4.6.2
- Setup-beam input names are valid and the workflow values match `mise.toml`: OTP 29.0.5 and Elixir 1.20.3-otp-29.
- Current frozen dependencies are actually lock-resolved Owl only; tracked vendored Owl and the tracked escript are deleted and ignored.
- The stale `foundry/pramana_diagnose.py` is deleted.
- Python parity is fail-closed: production calls return `{:error, :retired_python_migration_parity}`; only explicit retired metadata is returned. The corresponding policy tests pass.
- RPC wrapper tests use `Mix.Project.build_path/0`; both clean isolated builds passed.
- Formatter debt is isolated to seven exact hashes. An independent full `mix format --check-formatted` identified exactly those seven paths and no additional debt.
- Default CI avoids real providers and live lifecycle activation. Runtime inspection confirms tests use fakes/unsupported production capability rather than Herdr launches.
- Candidate documentation clearly routes live provider/lifecycle/activation acceptance to FR-22.

### Not satisfied

- Clean-machine portability is not demonstrated because of B1.
- Every artifact's complete source/dependency identity is not demonstrated because of B2 and B5.
- “Failure artifact always emitted” and useful failure receipts are not satisfied because of B3.
- Exact local toolchain-policy validation is not satisfied because of B4.

### Later work, not FR-21 blockers

- Real-provider authorization/profile and bounded smoke evidence: FR-22.
- Installed daemon, activation, restart, reboot/persistence, and real lifecycle acceptance: FR-17/FR-22.
- Broad remaining docs truth pass: FR-22, except statements introduced by FR-21 itself must already be accurate.

## Non-blocking limitations / observations

- This review ran locally on macOS; I did not execute GitHub's hosted Ubuntu job. B1 is a deterministic dependency-boundary failure, not a claim based only on guessing the hosted image.
- No test currently carries `@tag :live_provider` or `@tag :real_provider`. The CLI includes both `--exclude` switches, but they presently skip zero tagged tests. The manifest's static category declarations are accurate about absent evidence, yet they do not report a matched/skipped-test inventory. Adding the real bounded suite remains FR-22; reporting actual match counts would make FR-21 evidence stronger.
- The complete suite emits pre-existing test-source and unmatched support-pattern warnings despite compile-with-warnings-as-errors passing. These were not introduced as FR-21 production compiler regressions.
- `PramanaFoundry.Parity`'s module documentation still describes “effect-free shadow inspection” even though the path is retired. That is a minor documentation mismatch; runtime behavior is safely fail-closed.

## Changed-path SHA-256 inventory

Hashes for present candidate paths are candidate bytes. `DELETED` entries give the base bytes' SHA-256.

```text
e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6  .github/workflows/foundry-ci.yml
b7fb01c04d9c4c507a3c7a3d2e9671e1c7b49de1135b601591b7a79b5a75b88b  .gitignore
926b569c6f8cc937c2f5ba9ddb02296250c7e8d5a89712c71558d6e798468d89  foundry/README.md
d38e709984c4e94ed103624dfb4d18206543c628488e0013ca4c3d957ac9500d  foundry/ci/format_debt.exs
c1cecbc224fc84030e7d0ba7f80ebeadc970c74912f6d0db6020d6c6d792bc7c  foundry/ci/run.exs
DELETED a46ecd2cb12fd54c0cf0928c72fb10bef329b3f72b49df9bef621c3370734bc5  foundry/deps/owl/.formatter.exs
DELETED 77f6ea610d00379023ca000538019084de3f8c5c81e8bd9be6d06d79e5e951e4  foundry/deps/owl/.hex
DELETED c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4  foundry/deps/owl/LICENSE.txt
DELETED 9e1bbc227e0ee0f4da760e35ea94434e3fb4ce58c97b5aaac94b68ef65004d7d  foundry/deps/owl/README.md
DELETED c703a31dd2a4a329b45accd0e78742d3effd37f90c3805de00f8ac43b4b4be2e  foundry/deps/owl/hex_metadata.config
DELETED 4879f37b69c41329b1742ced66ed64a9fbf027df612c90928ec63b2cc096b0b2  foundry/deps/owl/lib/owl.ex
DELETED b7843314652ba82c90c6c2f99e2c53c008f8c8ff141c55b640c7d56b73d12260  foundry/deps/owl/lib/owl/application.ex
DELETED 86345b1c3690f10adb231b9d3b1a0245383f302412b2301e6e79e38e26ac6545  foundry/deps/owl/lib/owl/border_style.ex
DELETED 3b759c16d61ebc2c06cf7ff67b6ff09559605e67b6b26bafc4b38ae1b25db66b  foundry/deps/owl/lib/owl/box.ex
DELETED 4e98905d520cb973ec4faa38b4652ec9b12d92ad550654f93774d7e91ec348fe  foundry/deps/owl/lib/owl/daemon.ex
DELETED 48b859e3e17abc4043e006f81319c7ad3ef8c9febf609c72059477446f5dfbd1  foundry/deps/owl/lib/owl/data.ex
DELETED 3c5270c84555ec02887ba2d27d0a037e4581a815eab2e59dc09a3995cdf6080e  foundry/deps/owl/lib/owl/data/sequence.ex
DELETED 4f16a63a6221a6a9ba96f4d2fc100c8725a8a6bede0390a9af0097d491d5a2eb  foundry/deps/owl/lib/owl/io.ex
DELETED 2dfd307b9cfcaa4b22781a7ebffe589dcd2d19e10cb60e4cadac7b584c02c785  foundry/deps/owl/lib/owl/lines.ex
DELETED 04dc86c5a7d875dc7d546fbb9a2bd350c6eb11add13e6a7fddcd261c5ae96f9b  foundry/deps/owl/lib/owl/live_screen.ex
DELETED d2a518ee37e0c3075387af977af43d8108eeb5dd5659888aedabaeff023cc160  foundry/deps/owl/lib/owl/palette.ex
DELETED d064a3ddc473f6c4a7a0f42f44f29740d491a61ff6ff7b756cdf8cf26dd2918c  foundry/deps/owl/lib/owl/progress_bar.ex
DELETED d0756c4c93d5617f6b4d5d5874c4c92c96a726b903bae169e42ce1d2f3a03030  foundry/deps/owl/lib/owl/spinner.ex
DELETED a5f4b7963875d9edb54027f2ca17a62452ef4db271e8948bf6d1fc346749372c  foundry/deps/owl/lib/owl/system.ex
DELETED 0a4c267ebd760a76e94d55523d43c1fbac08b5787d96c7fa7343608687157bcb  foundry/deps/owl/lib/owl/system/helpers.ex
DELETED 17319347e31891634e5c7c90d12ba51e094cc5b77c6db8730ca0f45adcde642f  foundry/deps/owl/lib/owl/table.ex
DELETED d55e018f96c19be3438cfc41b3c1966b2e23a361f0ec892edfcc7c814cac51e0  foundry/deps/owl/lib/owl/tag.ex
DELETED 090e25126f493953dcb84f0729f3f868f10002519fe932e6ac2bf19cb9998b97  foundry/deps/owl/lib/owl/task.ex
DELETED 04a38b2cd656666bf231d77be6ddb630228ca20a8bd7d267fc87d0d2bafd8295  foundry/deps/owl/lib/owl/true_color.ex
DELETED beec7ef6cc06754755d3e1850606f4e47022c25b766f228a2dff1d62999c7ddb  foundry/deps/owl/mix.exs
6f416d2e4874ad1521cefd0d275969d1e95b46afaaa9b8d3090488a3c3922505  foundry/docs/CI.md
2fd5e18e89af3a2f51588df8867fd9522a65a6d121a2eea9aa9ae96ad3708835  foundry/docs/MIGRATION-TICKETS.md
372695ca46ab4a80616fa0bd9d43a6218d425c5c519946425b264e5509c91877  foundry/docs/MIGRATION.md
b3a6e5bb95afbc8032e98afddd44d302cfd41f664767c750dcf8767c94d6c7c2  foundry/docs/fr-21/candidate.md
739b25f37a4b3766244a30c2f87d0c925109ba7aee218dd740e862f26e70ef46  foundry/lib/pramana_foundry/ci.ex
b714c02f7bbb013b4a6f4a00ac015063b284635d0bd9ed2f67458787119d933b  foundry/lib/pramana_foundry/parity.ex
DELETED c8423089ead8d872d4928c9a5e337bd54295a1f4db64b2b25b1f4b88f3a57eac  foundry/pramana_diagnose.py
DELETED 52c5152bc059b1bd85564671924e92c17e2e8b7294b641390898b799e66c4618  foundry/pramana_foundry
467c81e8194722ebf1fd472e8c9d9c9a4eca4f2bda4d8ac26ad7b5e788aa1143  foundry/test/pramana_foundry/ci_test.exs
407d1d3f77892e8ffe7a224ce07f54434e995ac864fc1d3beac2b4b14df03f86  foundry/test/pramana_foundry/policy_test.exs
1217d74805d4bc6085a15327cff060ea654a312b4a48175d68eef8120d2a43d7  foundry/test/pramana_foundry/rpc_wrapper_test.exs
```

## Review scope and limitations

I read the complete applicable requirements in `foundry/docs/REPAIR-PLAN.md` (FR-21), `foundry/docs/REPAIR-AUDIT-2026-09-12.md` (F23/F24), `AGENTS.md`, and `docs/CODE_CONVENTIONS.md`, plus all changed candidate docs/source/tests/workflow and the relevant benchmark, runner, CLI/parity, Herdr, cleanup, and RPC code. I did not mutate the frozen candidate. Fault injections were confined to explicitly disposable independent clones under `/private/tmp/fr21-independent-review.kS5OJB`.

I did not use a provider or live daemon, did not touch corpus state, did not invoke Herdr, and did not run foreign cleanup. Network use was limited to fetching the Hex dependency in fresh isolated roots and read-only provenance checks of official GitHub action repositories/hosted-image documentation.
