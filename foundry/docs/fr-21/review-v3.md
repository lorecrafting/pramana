# FR-21 v3 renewed focused independent review

Date: 2026-09-13 (Pacific/Honolulu)

## Verdict

**PASS — R1 is resolved for the exact frozen v3 candidate.**

The pre-existing-directory/unreplaceable-initial-manifest boundary now returns infrastructure
exit 70, prints the exact destination and `:eisdir` once, does not retry, and produces no
artifact or false manifest. The regression test genuinely creates and exercises that
filesystem condition. The five-path delta introduces no new FR-21 blocker and does not weaken
the previously accepted B1, B2, B4 or B5 behavior or ordinary attributable failure manifests.

This is an FR-21-focused pass only. It is not provider, live-daemon, activation, integration,
deployment, corpus, or FR-22 lifecycle evidence.

## Frozen identity and scope

Reviewed checkout: `/private/tmp/pramana-fr21`

- candidate commit: `f76be70955452e378274e1784886b57bf618f033`
- candidate tree: `c49c7fc89f4aab6c561c61df4936192424100390`
- candidate parent: `0d4aa2cf625893e77009f01f525dd36357a58044`
- implementation commit: `0d4aa2cf625893e77009f01f525dd36357a58044`
- implementation tree: `6e4044d2413d266018da91af091907adb3b27b59`
- failed v2 candidate: `1bd381d96d6c58379d1a9586888fca56811bdc4f`
- v2-to-v3 binary diff SHA-256:
  `9e356caebbf15e5f32a97523bbb0c145bd6c024ef00ed38060ebee74819e934a`
- v2-to-v3 name-status SHA-256:
  `ffeec6465e6d497101822bbfa2fbfdca8fe5534856940e1ab8ec0ed8bb21b831`
- delta: 5 files, 453 insertions, 6 deletions; the large insertion count is the preserved
  v2 review/response evidence
- `git diff --check 1bd381d..f76be70`: exit 0
- candidate worktree status before and after review: empty under
  `git status --porcelain=v1 --untracked-files=all`

Exact changed-path SHA-256 values:

| Path | SHA-256 |
|---|---|
| `foundry/lib/pramana_foundry/ci.ex` | `b2cc9c67825588a38da8a22ae2141a3c90e59960a96fc86217b6a5744fcf08d1` |
| `foundry/test/pramana_foundry/ci_test.exs` | `284a9e4d7bc86087180ec7bab69d4e7e8bf58dc3c83fbcd4f56034c86528ff08` |
| `foundry/docs/fr-21/review-v2.md` | `f9477b3497dc925eabd97a05b5af4806c523c071ef5f1f071fe10f87a124c64f` |
| `foundry/docs/fr-21/review-response-v2.md` | `80ce25b575cd8e9566dc92d42a657c78cc21ea87869b28daa3c8b6344a5234e5` |
| `foundry/docs/fr-21/candidate-v3.md` | `1bf41f65e6736aebc3e811059bc97b69e5120d154322bb7281d95dd48966d33e` |

The preserved review hash exactly matches `/tmp/fr21-v2-review.md`.

## R1 code and regression review

The behavior delta is appropriately narrow:

1. The first manifest write now goes through `initial_manifest/2`. An atomic-write failure
   becomes `{:manifest_transport_error, reason}` rather than falling into ordinary setup
   failure handling.
2. `execute/3` routes that tagged result directly to `manifest_transport_failure/2`.
3. `atomic_manifest/2` no longer prints independently. This prevents the prior duplicate
   diagnostic.
4. `manifest_transport_failure/2` prints the exact
   `<output>/provenance.json` path and inspected reason, then returns 70.
5. `fail_manifest/5` still returns the requested ordinary failure exit when the failure
   manifest is written. If that write itself becomes unavailable, it now converts the result
   to the same path-bearing exit-70 transport failure.

The new test is not a synthetic helper-only assertion. It creates the output directory and
then creates a directory at its `provenance.json` destination, calls `CI.main/1`, captures
real stderr, and asserts exit 70, exact path, `:eisdir`, one diagnostic occurrence, and the
unchanged destination directory. That is the precise branch the v2 review reproduced.

Although the test does not separately spell `refute File.exists?(artifact)`, execution returns
from the initial manifest boundary before isolation or commands. The independent filesystem
probe below confirms no artifact or temporary file appears.

## Independent adversarial reproduction

Fresh detached clone:
`/private/tmp/fr21-v3-review.aE3eMt/source`, checked out at the exact candidate and clean.
The output root was external to the source checkout.

```sh
mkdir -p /private/tmp/fr21-v3-review.aE3eMt/artifacts/provenance.json
cd /private/tmp/fr21-v3-review.aE3eMt/source/foundry
env PATH=PINNED_ELIXIR_BIN:PINNED_OTP_BIN:/opt/homebrew/bin:/usr/bin:/bin \
  elixir ci/run.exs \
  --output /private/tmp/fr21-v3-review.aE3eMt/artifacts
```

Observed output, exactly once:

```text
cannot write provenance manifest /private/tmp/fr21-v3-review.aE3eMt/artifacts/provenance.json: :eisdir
```

Observed exit: **70**.

`find .../artifacts -maxdepth 2` returned only the artifact directory and the deliberately
pre-existing `provenance.json/` directory. There was no JSON file, escript, or `.tmp-*` remnant.
The detached source checkout remained clean. This closes the exact v2 R1 reproducer.

## Focused checks and non-regression evidence

Using Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 with isolated build, dependency and temporary
paths:

```sh
mix deps.get --check-locked
mix test test/pramana_foundry/ci_test.exs \
  test/pramana_foundry/projections/benchmark_test.exs \
  test/pramana_foundry/policy_test.exs \
  --exclude python_tiktoken_recompute --seed 0
mix test test/pramana_foundry/ci_test.exs --seed 0
mix compile --force --warnings-as-errors
mix format --check-formatted \
  lib/pramana_foundry/ci.ex test/pramana_foundry/ci_test.exs
```

Results:

- locked dependency restore: exit 0;
- focused three-file suite: exit 0, **14 passed, 1 excluded**;
- CI unit file alone: exit 0, **10 passed**;
- forced warnings-as-errors compile: exit 0, 78 files compiled;
- touched-file format check: exit 0.

Ordinary failure probes against the exact detached candidate:

- invalid invocation: exit 2 at `arguments`; clean candidate commit/tree, zero commands,
  `not-built` artifact and failed stage persisted. Manifest SHA-256:
  `8a85e2539899ef7aa3d4e84e73804c4efa061caba3ecf14add7833204dea6a51`;
- untracked source: exit 2 at `source_preflight`; exact dirty path, zero commands and
  `not-built` artifact persisted. Manifest SHA-256:
  `4038a88adfed770d614d53ef1cdccbcb5174e4f2e50dd05a4ffa2952d2922db0`;
- missing `mix` executable while invoking absolute pinned `elixir`: exit 70 at
  `command:locked dependencies`; the manifest retained exact source/tree and an attributable
  receipt with argv, `exit_code: null`, `Erlang error: :enoent`, duration, empty-output hash,
  and isolated paths. Manifest SHA-256:
  `fd679031023895cd27d42d0d9dacc0e3a6ab9053ac6538b3eacb5157489c732b`.

B1, B2, B4 and B5 policy functions and command construction are byte-unchanged by the delta.
Their focused regressions all pass. The actual dirty-source probe above additionally exercises
the modified `fail_manifest/5` success path, while invalid invocation exercises another
ordinary exit-2 manifest and the spawn probe exercises the unchanged command-receipt exit-70
path. No accepted v2 behavior regressed.

## Limits and exclusions

- No full 431-test CI rerun was needed for this five-path focused correction. The exact v2
  candidate's full clean runs and accepted B1/B2/B4/B5 evidence remain preserved; v3's touched
  implementation force-compiles and all relevant focused tests pass.
- Escript byte reproducibility remains unproved and unclaimed. FR-21 requires exact
  per-build source/dependency/artifact provenance, not identical escript bytes.
- No real provider, paid model, credential, Herdr backend or pane was invoked. No installed
  live daemon, integration, activation, deployment, database or corpus activity occurred.
- The stale CLI module-doc phrase recorded as non-blocking in v2 remains unchanged and outside
  this narrow correction.
- Real-provider conformance and end-to-end lifecycle/restart/activation evidence remain
  FR-09/FR-15a/FR-17/FR-22 work and are not implied by this PASS.
