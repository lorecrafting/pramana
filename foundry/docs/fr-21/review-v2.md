# FR-21 v2 fresh independent review

Date: 2026-09-13 (Pacific/Honolulu)

## Verdict

**FAIL — do not integrate or mark FR-21 complete.**

The frozen v2 candidate resolves the substance of v1 blockers B1, B2, B4 and B5, and
resolves the ordinary missing-project and missing-command cases of B3. A Python/tiktoken-free
clean detached run passed 431 tests with the one declared recomputation test excluded. Dirty
pre- and post-source fences, exact Elixir/OTP/ERTS checks, complete selected Mix dependency
inspection, lock/SCM/isolation enforcement, tracked-source/prebuilt rejection, and per-build
artifact provenance all survived independent adversarial probes.

One FR-21/F24 blocker remains in the failure-evidence contract: an output directory can be
created successfully while its `provenance.json` destination is unwritable. In that case the
runner emits no manifest (unavoidable), but returns ordinary setup exit **2**, repeats the
failed write, and does not identify the destination path. This contradicts both
`foundry/docs/CI.md` and `foundry/docs/fr-21/acceptance-v2.md`, which say the sole
no-manifest destination failure returns **70** and identifies the path/error. It is the same
failure-boundary family as v1 B3 and is FR-21 documentation/provenance truth, not FR-22.

No provider, paid model, Herdr backend/pane, installed live daemon, integration, activation,
deployment, database or corpus service was invoked. FR-22 and provider/live/activation work
remain out of scope and are not blockers in this verdict.

## Frozen identity and candidate state

Reviewed path: `/private/tmp/pramana-fr21`

- final candidate commit: `1bd381d96d6c58379d1a9586888fca56811bdc4f`
- final candidate tree: `b460f67a25ff19eb71f87234b4b160911b983598`
- implementation parent: `4e4acf784742381127bfd54fef49faf957d1c256`
- implementation tree: `4e95b891f23d8822122acb3d919605b793c64491`
- assigned base: `5d3acf4ff9e925b7de3a355048acfa9d6c548331`
- final binary diff SHA-256, base to candidate:
  `f53605513ab7eb845c277b18e06eb0ab3dc1971b7cdcacb3bc0caa9e967561af`
- final name-status SHA-256, base to candidate:
  `76bf72b21c38d7782ff1bca9edd6098a2869a61e64c6efd39603105cd1070897`
- scope: 47 paths, 1,799 insertions, 5,668 deletions
- `git diff --check BASE..CANDIDATE`: exit 0
- candidate status before review, after focused tests, and at final check: empty under
  `git status --porcelain=v1 --untracked-files=all`

Principal final-candidate path SHA-256 values:

| Path | SHA-256 |
|---|---|
| `.github/workflows/foundry-ci.yml` | `e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6` |
| `foundry/ci/run.exs` | `c1cecbc224fc84030e7d0ba7f80ebeadc970c74912f6d0db6020d6c6d792bc7c` |
| `foundry/ci/toolchain.exs` | `06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1` |
| `foundry/ci/format_debt.exs` | `d38e709984c4e94ed103624dfb4d18206543c628488e0013ca4c3d957ac9500d` |
| `foundry/lib/pramana_foundry/ci.ex` | `a60bda6a26f57efbe15ab5cab37592a79471739bb90d0e06fa3cf84a596d1f66` |
| `foundry/test/pramana_foundry/ci_test.exs` | `8da9254cde0e14715c097655d9b40cea50531d0d35b4ad043f3fe4d7a94798ef` |
| `foundry/test/pramana_foundry/projections/benchmark_test.exs` | `9046278d515463ed9ea5e20d18c6d103091ef785c9296ed3cda2faaa63e8de2a` |
| `foundry/docs/CI.md` | `744dda8ab04e5f859c8e614ad6c07c3b6f82cf29622b52e1f1518bc91d34731c` |
| `foundry/docs/fr-21/candidate-v2.md` | `c2df8bf68a739a453f50980b56e91302c99d4a0b8c04300d936acfdace7ca3a3` |
| `foundry/docs/fr-21/acceptance-v2.md` | `572412b6bc7805f3c1bb17c6d1b93079eff1c881d88c546ae739c1eecf76d69c` |
| `foundry/docs/fr-21/review.md` | `da11d18a4cfe7f7842ccb9309e63f6dbb8319b41967c5f0e30fb723c86eac36c` |
| `foundry/docs/fr-21/review-response.md` | `9798eaf6d4e0c3105ac25c5b4f61de0b9f26fe296cadf30269170558920f068e` |

The complete changed-path/deletion inventory appears at the end of this review.

## Blocking finding

### R1 — unwritable manifest destination violates the documented failure contract

Severity: medium. Scope: **FR-21 / F24 and the remaining edge of v1 B3**.

The bootstrap distinguishes only `File.mkdir_p/1` failure as infrastructure exit 70
(`ci.ex:18-24`). If the directory exists but the initial atomic write/rename fails,
`atomic_manifest/2` returns `{:error, reason}` (`ci.ex:654-665`); the broad `with` else
routes that to `fail_manifest(..., 2)` (`ci.ex:168,201-202`). `fail_manifest/5` then tries
the same impossible write a second time, ignores that result and returns 2
(`ci.ex:630-640`).

Exact reproduction against the clean detached final candidate:

```sh
mkdir -p /private/tmp/fr21-v2-review.9oIg7D/unwritable-artifacts/provenance.json
cd /private/tmp/fr21-v2-review.9oIg7D/source/foundry
env PATH=PINNED_ELIXIR_BIN:PINNED_OTP_BIN:/opt/homebrew/bin:/usr/bin:/bin \
  elixir ci/run.exs \
  --output /private/tmp/fr21-v2-review.9oIg7D/unwritable-artifacts
```

Observed exit: **2**. Observed stderr:

```text
cannot write provenance manifest: :eisdir
cannot write provenance manifest: :eisdir
Foundry CI failed at setup: :eisdir
```

`find` showed only the deliberately pre-existing `provenance.json/` directory; no manifest
or artifact existed. The stderr did not contain the destination path.

This directly contradicts:

- `foundry/docs/CI.md:57-61`: an uncreatable/unwritable requested destination returns 70;
- `foundry/docs/fr-21/acceptance-v2.md:106-107`: it returns 70 and identifies path/error.

Minimum correction: treat failure of the initial `atomic_manifest/2` as an output-transport
failure, report the exact destination path plus reason once, and return 70 without trying to
write the failure manifest to the same impossible destination. Alternatively narrow the docs
to the actual nonzero contract, but preserve a distinct infrastructure outcome if callers use
2 for policy/setup rejection. Add an executable regression for the case where `mkdir_p`
succeeds and `provenance.json` cannot be replaced.

## V1 blockers challenged against the final candidate

### B1 — resolved: default CI no longer depends on ambient `tiktoken`

The selected `/opt/homebrew/bin/python3` fails `import tiktoken` with
`ModuleNotFoundError`. Nevertheless the focused suite passed **13 tests, 1 excluded**, and
the clean detached full runner passed **431 tests, 1 excluded**. The default test reads the
saved JSON fixture in Elixir. The recomputation is a real, separately tagged test, not a
vacuous declaration: running `benchmark_test.exs` without the exclusion in the same
Python environment produced **1/2 passed**, with the tagged recomputation failing against
the saved tiktoken result. Thus the manifest's `declared_test_matches: 1` is material.

This resolves the CI portability defect without claiming the historical recomputation ran.
The production `benchmark-projections` command can still invoke Python/tiktoken and fall back
when unavailable; that command is outside the default FR-21 gate and is now honestly excluded,
not evidence that tokenizer recomputation is portable.

### B2 — resolved: both dirty-source fences fail closed

Preflight probe in a disposable final-candidate clone added one tracked edit and one untracked
`.ex` file. Result: exit 2 at `source_preflight`; both exact porcelain entries and their
status digest were recorded, `commands` was empty, and the artifact was `not-built`.
Manifest SHA-256:
`40673e44bf5954d5cced60690c9a2de001801315e2b1ab0d843fd5ed23ec15e0`.

For postflight, a disposable PATH wrapper created an untracked source path only after the
escript-build command. (The test command was short-circuited in this focused fence probe;
the actual full suite had already passed independently.) All six receipts were present, then
the runner exited 2 at `source_postflight`, recorded the exact dirty path, and published no
artifact. Manifest SHA-256:
`8500599f9143c4204b2bcbc56c4fd3bbadd61b75812f3dadcf3be378ee42045c`.

The artifact cannot pass while attributable source is dirty. The usual unavoidable
pre/post time-of-check race remains, but clean detached CI has no concurrent source writer and
FR-21 does not require a hostile build sandbox.

### B3 — mostly resolved, but R1 prevents closure

Two original reproductions now work:

- Missing `foundry/mix.exs`: exit 2 at `project`; manifest retained final-candidate
  commit/tree, dirty deletion, exact toolchain, lock/package inventory, exclusions, zero
  commands and no artifact. SHA-256:
  `474200430a15dbe012dc6895607645e303a056961f7d22902f6458c35173496c`.
- Missing `mix` executable while invoking absolute pinned `elixir`: exit 70 at
  `command:locked dependencies`; the receipt includes argv, `exit_code: null`,
  `error: "Erlang error: :enoent"`, duration, empty-output SHA-256 and all isolated
  environment paths. SHA-256:
  `dd9286ee0c6bbe3cafcc4e8c9c390399bc42b7d1a836cda2d14b51487fc1eb7c`.

Those are attributable and complete for their stage. R1 is the remaining false branch of
the candidate's explicit no-manifest exception contract.

### B4 — resolved: exact patch versions are enforced

The workflow and `ci/toolchain.exs` agree with `mise.toml`: Elixir 1.20.3 distribution
`1.20.3-otp-29`, OTP 29.0.5 and ERTS 17.0.5. Running the clean final candidate under
Elixir 1.20.3 with OTP 29.0.1 / ERTS 17.0.1 exited 2 at `toolchain`, reported both exact
actual and expected versions, `matches_policy: false`, and ran zero commands. Manifest
SHA-256:
`d9fb649f8231f465ddb397bebf7cf3296861005122ea102bf3bdcb3211bdd7c1`.

### B5 — resolved: complete selected Mix SCM/lock/isolation policy is enforced

The successful manifest contains the only selected dependency, Owl 0.13.1, with
`Hex.SCM`, exact Hex lock match, requirement, status and a destination beneath the unique
run dependency root. The lockfile SHA-256 is
`63191c494ab822546ef17d95030691bff62c44c382ecdaaf9f483308c655eab5`;
both Hex checksums are recorded.

An actual committed clean path-dependency mutation let `mix deps.get --check-locked` exit 0,
then failed at `resolved_dependency_policy` before compile. Its complete resolved entry
reported `Mix.SCM.Path`, `unlocked`, lock mismatch, external destination and
`destination_isolated: false`. Manifest SHA-256:
`fa5a6d931a7466c5890c92d39f7dc0c5ca9f429d831c4878a3f970c1abbe65d3`.

Committed ignored dependency source plus a committed prebuilt escript failed preflight with
both identities recorded; after removing only the dependency source, the prebuilt escript
alone failed preflight. Manifest SHA-256 values:
`85d551920492a7975d281a56b5fb07846dc86628934c0f6247af2f065f7bf63f`
and
`f89c8f4cdef0bd02915f15ac6da2c16546977e5bc9cd9a36aac98b7d92255ab1`.
Unit regressions separately cover Git SCM, unlocked, lock mismatch and nonisolated entries.

## Clean detached CI and artifact binding

Independent clone/root: `/private/tmp/fr21-v2-review.9oIg7D/source`, detached at the exact
final candidate. The checkout was empty under porcelain before and after the run. Command:

```sh
cd /private/tmp/fr21-v2-review.9oIg7D/source/foundry
env -u HERDR_ENV -u COORDINATOR_TICK -u PRAMANA_FOUNDRY_RUNTIME_DIR \
  PATH=PINNED_ELIXIR_BIN:PINNED_OTP_BIN:/opt/homebrew/bin:/usr/bin:/bin \
  elixir ci/run.exs --output /private/tmp/fr21-v2-review.9oIg7D/artifacts
```

Result: exit 0; **431 passed, 1 excluded**; six command receipts exit 0. Manifest SHA-256:
`e420c83692d2823b2b8ce1fd89d4472597dd6c6c1a022f52ccb915e66b588b3b`.
Artifact SHA-256:
`89e4e768ccfbb2518ee40f69fc7c01d4c4833b45060b2ec7184608e5fa0869e3`.

The manifest binds final commit/tree before and after, empty dirty-status hashes, runner and
workflow hashes, exact runtime policy/actual versions, complete lock and selected dependency,
unique build/dependency/tmp/operator roots, every command receipt and the copied escript hash.
The generated checkout-local escript was removed before source postflight.

The two supplied exact-final-candidate clean receipts were also independently inspected:

| Receipt | Manifest SHA-256 | Escript SHA-256 | Source/tree | Result |
|---|---|---|---|---|
| final A | `f9cfc6da6b95962c60bd721dba42daf88f94e560e158679bd4cf1f6f3aa9d51e` | `dbec977adade506ffd6b3269675db90eebe1b6f882204baa3258d30afb523b68` | exact final, clean pre/post | 431/1, all six exits 0 |
| final B | `890c0ba7e7d8a327eee48850cc226f4fe71929b264eaef9e92d29e5c04e845a8` | `896e811828f12a6eaa1b758398c2d0240fff7dc0599410b5f2385ddb8a10bf87` | exact final, clean pre/post | 431/1, all six exits 0 |

Their run roots and every derived build/dependency/tmp/runtime path are distinct.

The three escript hashes differ despite the same recorded source, lock and toolchain. Therefore
**byte-reproducible escripts are not established**. FR-21 requires exact per-build provenance
and local reproduction of the job, not identical artifact bytes: each build records the exact
artifact hash and source/dependency/tool inputs. This limitation is not an FR-21 blocker and
must not be upgraded into a reproducible-build claim. A later reproducible-build requirement
would need deterministic BEAM/archive inputs and its own acceptance test.

## Deletion, retirement and documentation scope

The candidate deletes all 24 tracked `foundry/deps/owl/**` paths from the assigned base, the
tracked generated `foundry/pramana_foundry`, and stale `foundry/pramana_diagnose.py`. None is
present in the final tree. `.gitignore` covers the generated dependency tree, escript and CI
artifact directory. `mix.exs` and `mix.lock` are unchanged from the assigned base.

The former Python `Parity` implementation no longer imports or invokes Python. Normal shadow
and fixture comparison calls fail closed or return explicit `retired` metadata; README and
migration documents date the historical claims. This meets FR-21's retirement/provenance
scope without claiming current parity. The still-existing CLI tombstone is safe, but its
module doc at `foundry/lib/pramana_foundry/cli.ex:2` still says “effect-free shadow
inspection”; correcting that stale phrase is a non-blocking documentation cleanup because
the operator README and actual route both clearly fail closed.

## Exclusions and later-ticket boundary

The manifest reports provider tags as **absent with zero declarations**, not skipped tests.
It reports one real Python/tiktoken recomputation declaration as **excluded**. Live daemon /
activation is absent, and corpus/services are not required. This is nonvacuous and matches
the command argv.

The full suite does start isolated test supervision and test fixture OS processes; names such
as `daemon` and pane IDs in output are fixture vocabulary. `COORDINATOR_TICK` and `HERDR_ENV`
are unset, the real System runner has a direct fail-closed test, AgentServer paths use fake
runners, and runtime roots are beneath the unique run root. No external Herdr/provider or
installed live daemon was started and no foreign pane was inspected or closed.

Deferred, correctly non-blocking here:

- real OMP/account/subscription-route and bounded provider smoke (FR-09/FR-15a/FR-22);
- real daemon/restart lifecycle, Git integration, immutable activation and rollback
  (FR-13/FR-14/FR-17/FR-22);
- scenario-level replacement of F23's vacuous historical lifecycle evidence (FR-22).

## Commands, secondary observations and limitations

- Focused final-candidate command from `foundry/`:
  `mix test test/pramana_foundry/ci_test.exs test/pramana_foundry/projections/benchmark_test.exs test/pramana_foundry/policy_test.exs --exclude python_tiktoken_recompute --seed 0`;
  exit 0, 13 passed, 1 excluded.
- `git diff --check BASE..CANDIDATE`; exit 0.
- `git fsck --no-dangling --no-progress`; exit 0.
- One instrumented postflight attempt that still ran the whole suite hit a five-second
  timeout waiting for a killed fixture port in `RuntimeStartupBoundaryTest` (430/431). The
  exact focused test immediately passed 1/1, the independent clean run passed 431/431, and
  the two supplied clean runs passed 431/431. I do not attribute that one timing failure to
  FR-21, but it is retained here rather than silently omitted.
- Review host: macOS arm64, not GitHub's Ubuntu runner. Network activity was limited to
  restoring locked Owl from Hex in fresh roots. GitHub-hosted execution itself was not run.
- Candidate source was never edited. Every mutation probe was confined to disposable clones
  under `/private/tmp`.

## Complete changed-path SHA-256 inventory

Present entries hash final-candidate bytes. `DELETED` entries hash bytes from assigned base
`5d3acf4ff9e925b7de3a355048acfa9d6c548331`.

```text
e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6  .github/workflows/foundry-ci.yml
b7fb01c04d9c4c507a3c7a3d2e9671e1c7b49de1135b601591b7a79b5a75b88b  .gitignore
926b569c6f8cc937c2f5ba9ddb02296250c7e8d5a89712c71558d6e798468d89  foundry/README.md
d38e709984c4e94ed103624dfb4d18206543c628488e0013ca4c3d957ac9500d  foundry/ci/format_debt.exs
c1cecbc224fc84030e7d0ba7f80ebeadc970c74912f6d0db6020d6c6d792bc7c  foundry/ci/run.exs
06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1  foundry/ci/toolchain.exs
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
744dda8ab04e5f859c8e614ad6c07c3b6f82cf29622b52e1f1518bc91d34731c  foundry/docs/CI.md
2fd5e18e89af3a2f51588df8867fd9522a65a6d121a2eea9aa9ae96ad3708835  foundry/docs/MIGRATION-TICKETS.md
372695ca46ab4a80616fa0bd9d43a6218d425c5c519946425b264e5509c91877  foundry/docs/MIGRATION.md
572412b6bc7805f3c1bb17c6d1b93079eff1c881d88c546ae739c1eecf76d69c  foundry/docs/fr-21/acceptance-v2.md
c2df8bf68a739a453f50980b56e91302c99d4a0b8c04300d936acfdace7ca3a3  foundry/docs/fr-21/candidate-v2.md
b3a6e5bb95afbc8032e98afddd44d302cfd41f664767c750dcf8767c94d6c7c2  foundry/docs/fr-21/candidate.md
9798eaf6d4e0c3105ac25c5b4f61de0b9f26fe296cadf30269170558920f068e  foundry/docs/fr-21/review-response.md
da11d18a4cfe7f7842ccb9309e63f6dbb8319b41967c5f0e30fb723c86eac36c  foundry/docs/fr-21/review.md
a60bda6a26f57efbe15ab5cab37592a79471739bb90d0e06fa3cf84a596d1f66  foundry/lib/pramana_foundry/ci.ex
1ab5768b3024951a8381c4067c2a1e98c808bc735c1ff56766417c4641e7d399  foundry/lib/pramana_foundry/parity.ex
DELETED c8423089ead8d872d4928c9a5e337bd54295a1f4db64b2b25b1f4b88f3a57eac  foundry/pramana_diagnose.py
DELETED 52c5152bc059b1bd85564671924e92c17e2e8b7294b641390898b799e66c4618  foundry/pramana_foundry
8da9254cde0e14715c097655d9b40cea50531d0d35b4ad043f3fe4d7a94798ef  foundry/test/pramana_foundry/ci_test.exs
407d1d3f77892e8ffe7a224ce07f54434e995ac864fc1d3beac2b4b14df03f86  foundry/test/pramana_foundry/policy_test.exs
9046278d515463ed9ea5e20d18c6d103091ef785c9296ed3cda2faaa63e8de2a  foundry/test/pramana_foundry/projections/benchmark_test.exs
1217d74805d4bc6085a15327cff060ea654a312b4a48175d68eef8120d2a43d7  foundry/test/pramana_foundry/rpc_wrapper_test.exs
```
