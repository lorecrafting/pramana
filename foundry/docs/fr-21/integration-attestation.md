# FR-21 post-integration attestation

Date: 2026-09-13 (Pacific/Honolulu)

## Verdict

**PASS — actual integration preserves the reviewed FR-21 behavior.**

The integrated commit is the exact reviewed v3 implementation/test/workflow content, its
deletion set is exact, and its only differences from the frozen candidate are four
status/history/review documents. The supplied clean-run provenance and my independent full
run both bind clean pre/post source, the pinned toolchain, isolated locked Hex dependencies,
non-vacuous exclusions, all six command receipts, and a per-build escript hash. The v2 R1
filesystem boundary also passes directly on the integrated tree.

This verdict makes no provider, live-daemon, activation, deployment, corpus, or FR-22 claim.

## Identities and checkout

- checkout: `/private/tmp/pramana-fr21-attest`
- integrated commit: `a0c7a72c173d7d8e9929e6ee235d9ce138afa703`
- integrated tree: `0437785f9395f7ea261e0d1421cb4aef3fb03ee6`
- integration parent: `cde1a63aa59c5f95a24a203f8119d9d72758c2b0`
- reviewed candidate: `f76be70955452e378274e1784886b57bf618f033`
- reviewed candidate tree: `c49c7fc89f4aab6c561c61df4936192424100390`
- `git status --porcelain=v1 --untracked-files=all`: empty before checks and after the
  independent full run
- `git diff --check cde1a63..a0c7a72`: exit 0

I independently resolved the commit/tree in the detached checkout; they match the supplied
identities.

## Candidate-byte and integration-scope checks

`git diff --name-status f76be70..a0c7a72` contains only:

- `docs/PLAN.md`
- `foundry/docs/IMPLEMENTATION-LOG.md`
- `foundry/docs/REPAIR-PLAN.md`
- added `foundry/docs/fr-21/review-v3.md`

Those changes record review/integration status and other-ticket history; they change no
runner, workflow, runtime, test, dependency input, or exclusion behavior. The persisted v3
review SHA-256 is exactly
`de1cf2bbe9cefdf391850a005fc54cf6b75d673095fca7fa486a355c9ebc9b42`.

All reviewed candidate-owned workflow/code/test files match `f76be70` by Git blob ID. Their
integrated SHA-256 values are:

| Path | SHA-256 |
|---|---|
| `.github/workflows/foundry-ci.yml` | `e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6` |
| `foundry/ci/run.exs` | `c1cecbc224fc84030e7d0ba7f80ebeadc970c74912f6d0db6020d6c6d792bc7c` |
| `foundry/ci/toolchain.exs` | `06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1` |
| `foundry/ci/format_debt.exs` | `d38e709984c4e94ed103624dfb4d18206543c628488e0013ca4c3d957ac9500d` |
| `foundry/lib/pramana_foundry/ci.ex` | `b2cc9c67825588a38da8a22ae2141a3c90e59960a96fc86217b6a5744fcf08d1` |
| `foundry/lib/pramana_foundry/parity.ex` | `1ab5768b3024951a8381c4067c2a1e98c808bc735c1ff56766417c4641e7d399` |
| `foundry/test/pramana_foundry/ci_test.exs` | `284a9e4d7bc86087180ec7bab69d4e7e8bf58dc3c83fbcd4f56034c86528ff08` |
| `foundry/test/pramana_foundry/projections/benchmark_test.exs` | `9046278d515463ed9ea5e20d18c6d103091ef785c9296ed3cda2faaa63e8de2a` |
| `foundry/test/pramana_foundry/policy_test.exs` | `407d1d3f77892e8ffe7a224ce07f54434e995ac864fc1d3beac2b4b14df03f86` |
| `foundry/test/pramana_foundry/rpc_wrapper_test.exs` | `1217d74805d4bc6085a15327cff060ea654a312b4a48175d68eef8120d2a43d7` |

The integration deletion set exactly equals the candidate deletion set: 27 paths, comprising
25 tracked `foundry/deps/owl/**` paths, `foundry/pramana_diagnose.py`, and the tracked generated
`foundry/pramana_foundry` escript. `foundry/mix.exs` and `foundry/mix.lock` have the same blobs
at the assigned base, candidate, and integration (`0ed7ad2...` and `77c461f...`).

No Coordinator path entered the integration diff. `foundry/lib/pramana_foundry/cli.ex` has
the identical blob `4d280a4c8a5166ff9f12b6d5eed05c8a176d8385` in the integration parent, reviewed candidate,
and integrated commit. Thus the no-net intermediate CLI edit and the user's dirty/untracked
Coordinator or local artifacts did not enter the commit.

## Supplied clean-run provenance

Manifest:
`/private/tmp/fr21-integrated-artifacts-clean/provenance.json`

- manifest SHA-256:
  `dd63583f406c31369563dee0ebccf6e917e246cc7bef585f3367a95d1cd9c047`
- result/exit/final stage: `passed` / `0` / `source_postflight`
- schema: `pramana-foundry-ci-provenance/v2`
- source and post-source both record exact commit `a0c7a72...`, tree `0437785...`, empty
  `dirty_paths`, and empty-status SHA-256 `e3b0c442...`
- source and post-source runner/workflow hashes equal the integrated bytes above
- exact actual and expected toolchain: Elixir `1.20.3`, OTP `29.0.5`, ERTS `17.0.5`;
  `matches_policy: true`
- isolation: distinct build/deps/tmp/operator roots; `COORDINATOR_TICK` and `HERDR_ENV`
  unset, provider launch disabled, foreign-pane cleanup not invoked
- dependency inventory: only Owl 0.13.1, `Hex.SCM`, Hex lock entry/checksums present,
  `lock_matches: true`, `destination_isolated: true`; no tracked dependency sources and no
  tracked prebuilt escript
- all seven pinned format-debt entries have matching expected/actual hashes
- all six receipts passed with exit 0: locked dependency fetch, warnings-as-errors compile,
  scoped format check, model-free tests, dependency inventory, escript build
- exclusions are non-vacuous and explicit: real-provider tags absent (0 matches), optional
  Python/tiktoken recomputation excluded (1 match), live daemon/activation absent, corpus and
  services not required
- artifact SHA-256 in the manifest is
  `bea5d7d4187fb15c9cb3a245112a51ba3a25c0468a3db162acf4cf27483b0110`; hashing the artifact
  file independently produced the same value, and its `source_commit` is the integrated commit

## Independent execution

Using explicit pinned Elixir/OTP paths and external isolated output/build/deps/tmp/operator
roots, I ran:

```sh
mix deps.get --check-locked
mix test test/pramana_foundry/ci_test.exs \
  test/pramana_foundry/projections/benchmark_test.exs \
  test/pramana_foundry/policy_test.exs \
  --exclude python_tiktoken_recompute --seed 0
elixir ci/run.exs --output /private/tmp/fr21-integration-independent-artifacts.7bCZyZ
```

Results:

- focused suite: **14 passed, 1 excluded**
- full gate: **432 passed, 1 excluded**, all six stages passed, exit 0
- independent manifest SHA-256:
  `63d6989f95aa0eac975aef57fbfa0530ea5934dc49749d550578cea170c86357`
- independent artifact SHA-256:
  `3f45a02d761049292cc3dc34ef71799445d331ae01e6eb68989c8e35a68917a3`
- independent manifest again records exact integrated source/tree, clean pre/post fences,
  pinned Elixir/OTP/ERTS, explicit exclusions, and six passing receipts
- checkout remained clean

For R1, I pre-created an unreplaceable
`/private/tmp/fr21-integration-r1.WHuAfD/artifacts/provenance.json/` directory and invoked the
integrated runner. It returned **70**, wrote exactly one stderr line containing the exact
destination and `:eisdir`, did not retry, and left only the requested artifact directory plus
the deliberately pre-existing `provenance.json/` directory. No artifact, JSON file, or temp
file was created; source remained clean.

## Limits and exclusions

- The shell's ambient Elixir was 1.19.5 with ERTS 17.0.1 and failed an initial dependency
  attempt before tests. The actual focused and full attestations used the explicit project
  pins, and the runner itself rejects nonmatching versions. This is not passing evidence from
  the ambient toolchain.
- The supplied and independent escript hashes differ. This remains the reviewed, honest
  non-reproducible-byte limitation. FR-21 requires exact per-build source/dependency/artifact
  provenance, which both manifests provide; it does not require identical escript bytes.
- Test logs exercise fake runners and in-process supervised components. No real provider,
  paid model, credential, external Herdr backend, installed/live daemon, activation,
  deployment, database, or corpus service was invoked. The Coordinator application started
  only in test mode with ticking disabled.
- Ordinary failure-manifest behavior was not separately re-probed post-integration because
  the runner and its tests are byte-identical to the reviewed v3 candidate; the full CI file
  and focused suite passed. R1, the only v3 residual, was directly re-probed.
