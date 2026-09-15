# FR-21 candidate v2 acceptance

Date: 2026-09-13

This record belongs to FR-21 only. It records the corrected implementation commit
`4e4acf784742381127bfd54fef49faf957d1c256` (tree
`4e95b891f23d8822122acb3d919605b793c64491`) and the commands used to challenge it. The final
candidate commit adds only this record and the candidate pointer; the review request and each
clean-run provenance manifest carry that final immutable commit/tree.

## Focused checks

From a clean Foundry checkout with Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5:

```bash
mix test test/pramana_foundry/ci_test.exs \
  test/pramana_foundry/projections/benchmark_test.exs \
  test/pramana_foundry/policy_test.exs \
  --exclude python_tiktoken_recompute --seed 0
```

Result: exit 0; 13 tests passed and the single tagged Python/tiktoken recomputation test was
excluded. The CI unit file alone passed 9 tests. `mix compile --warnings-as-errors` and the
formatter check over all FR-21-owned Elixir files both exited 0.

The clean-run environment deliberately contains `python3` without `tiktoken`:

```bash
python3 -c 'import tiktoken'
```

Result: exit 1, `ModuleNotFoundError`. Default CI nevertheless passes because it validates the
recorded fixture in Elixir; it does not invoke the optional recomputation.

## Clean detached run

The implementation commit was checked out detached with an independent artifact root and no
corpus service, provider variables or inherited build/dependency/runtime directory:

```bash
cd foundry
env -u HERDR_ENV -u COORDINATOR_TICK -u PRAMANA_FOUNDRY_RUNTIME_DIR \
  PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin \
  elixir ci/run.exs --output /private/tmp/fr21-v2-final-artifacts-1
```

Result: exit 0; 431 passed, 1 excluded. Manifest:

- SHA-256: `9e59a6fe301268e663d352248a75de0c862c33d1d852f5bfae4073e8ca80c335`
- source commit/tree: the corrected implementation values above before and after work;
- dependency: OWL 0.13.1, `Hex.SCM`, lock matched, isolated destination;
- exact runtime: Elixir 1.20.3, OTP 29.0.5, ERTS 17.0.5;
- commands: locked restore, warnings-as-errors compile, bounded format gate, model-free suite,
  dependency inventory and escript build all exited 0; and
- artifact SHA-256: `066bc28fa260998d1d60d29e4dfcff8f09a16fd319b0ff510a11a6b5b13b3142`.

Two clean detached runs of the final evidence-bearing candidate, with different checkout,
artifact and generated isolation roots, are supplied with the review request. Their manifests
are the authoritative exact-candidate receipts.

## Adversarial failure probes

Each probe used a committed, clean disposable checkout except the dirty-source probe, whose
deliberate tracked and untracked changes are the subject of the check.

| Probe | Observed result |
|---|---|
| dirty tracked plus untracked `.ex` | exit 2 at `source`; zero commands and no artifact; dirty paths/digest recorded |
| missing `mix.exs` | exit 2 at `project`; source/tool/lock/isolation identities retained |
| OTP 29.0.1 / ERTS 17.0.1 | exit 2 at `toolchain`; exact actual and expected patch versions recorded |
| committed path dependency | locked restore exits 0, then resolved-policy gate exits 2 before compile; `Path.SCM`, unlocked source and destination recorded |
| missing `mix` executable | exit 70 at `command:locked dependencies`; command argv, `:enoent`, null exit code and empty-output digest recorded |

The final missing-executable manifest for implementation commit `4e4acf7` is
`/private/tmp/fr21-v2-final-spawn-failure/provenance.json`; disposable local paths are reported
for reproducibility and are not repository inputs. The other probes ran against v2 correction
draft `dba5635`; the changes through `4e4acf7` only strengthened a missing-lock comparison and
normalized null/error/stage provenance. Unit regressions bind every rejected dependency class,
dirty preflight, exact toolchain mismatch and spawn receipt in the final implementation.

## Candidate path identity

The principal behavior inputs at the corrected implementation commit have these SHA-256 values:

| Path | SHA-256 |
|---|---|
| `.github/workflows/foundry-ci.yml` | `e57f7c46527958c501a3338fdadcb11981eca605a77fca83c92576af61fab0a6` |
| `foundry/ci/run.exs` | `c1cecbc224fc84030e7d0ba7f80ebeadc970c74912f6d0db6020d6c6d792bc7c` |
| `foundry/ci/toolchain.exs` | `06d9fbb6ea92206dff68d705b2cae885b44a08b21495c1c5db620b456aecacc1` |
| `foundry/ci/format_debt.exs` | `d38e709984c4e94ed103624dfb4d18206543c628488e0013ca4c3d957ac9500d` |
| `foundry/lib/pramana_foundry/ci.ex` | `a60bda6a26f57efbe15ab5cab37592a79471739bb90d0e06fa3cf84a596d1f66` |
| `foundry/test/pramana_foundry/ci_test.exs` | `8da9254cde0e14715c097655d9b40cea50531d0d35b4ad043f3fe4d7a94798ef` |
| `foundry/test/pramana_foundry/projections/benchmark_test.exs` | `9046278d515463ed9ea5e20d18c6d103091ef785c9296ed3cda2faaa63e8de2a` |
| `foundry/docs/fr-21/review.md` | `da11d18a4cfe7f7842ccb9309e63f6dbb8319b41967c5f0e30fb723c86eac36c` |

The v1 candidate removed the exact tracked `foundry/deps/owl/**` tree, generated
`foundry/pramana_foundry`, and stale `foundry/pramana_diagnose.py`; the candidate diff is the
authoritative exhaustive deletion inventory. `mix.exs` and `mix.lock` are unchanged from the
assigned base.

## Exclusions and limits

The provider tags match zero tests and are reported as absent, not skipped coverage. One
optional Python/tiktoken recomputation test is declared and excluded. No provider/paid/Herdr
conformance, live daemon, activation, Git integration, corpus service or FR-22 lifecycle claim
is made. The runner cannot create a manifest only when the requested output destination itself
cannot be created or written; it returns exit 70 and identifies the path/error on stderr.
