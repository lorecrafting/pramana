# FR-21 candidate

Date: 2026-09-13

## Scope and decisions

This candidate adds the independent Foundry CI job and an Elixir CI/provenance runner.
The job runs from `foundry/` with exclusive dependency, build, temporary and runtime
roots. It starts no corpus service, database, daemon, provider session or Herdr pane.
Every check exit is recorded and a fresh escript is built from source rather than read
from the checkout.

The committed `mix.lock` and its Hex checksums are the only third-party source authority.
The duplicate tracked OWL directory and generated escript are deleted and ignored; a fresh
`mix deps.get --check-locked` already restored OWL 0.13.1 after those deletions. The stale
Python diagnostic is deleted. The absent Python-migration parity implementation now fails
closed, while its sanitized fixtures remain explicitly dated import-compatibility inputs.

Seven unrelated pre-existing formatter failures are pinned by path and byte hash. CI checks
all other formatter-owned files and refuses changes to a debt file until the ticket changing
it formats the file and removes the baseline entry.

The GitHub actions were resolved from their official repositories on 2026-09-13 and pinned
to these immutable revisions:

- `actions/checkout`: `11d5960a326750d5838078e36cf38b85af677262`
- `erlef/setup-beam`: `54075bcc5e249e4758d363f27d099f55d843f124`
- `actions/upload-artifact`: `ea165f8d65b6e75b540449e92b4886f43607fa02`

## Candidate boundary

The exact reviewed candidate is the Git revision supplied with this document. Each clean
run writes `provenance.json`, which independently binds that commit and tree, dirty-path
inventory, runner/workflow hashes, lock entries, toolchain, command receipts, exclusions
and generated escript hash. Review must match those recorded identities and the candidate
path hashes; a later behavior change requires renewed evidence.

Owned paths are `.github/workflows/foundry-ci.yml`, `.gitignore`, the new `foundry/ci/`
files, `PramanaFoundry.CI`, FR-21 tests/docs, narrow migration/README truth corrections,
the retired `Parity` implementation and test, and the exact deleted dependency/executable/
diagnostic artifacts. The existing RPC wrapper test now derives its compiled ebin from
`Mix.Project.build_path/0` instead of assuming `_build/test`, which makes its actual wrapper
probe valid under an isolated build root. `mix.exs`, `mix.lock`, Coordinator, CLI, startup,
durable storage and live state are unchanged.

## Local evidence before freeze

Using the pinned Elixir 1.20.3 / OTP 29.0.5 installations:

- `mix deps.get --check-locked` restored OWL from Hex after the vendored directory deletion;
- forced warnings-as-errors compilation passed after retiring the vacuous parity return;
- focused formatting passed; and
- `mix test test/pramana_foundry/ci_test.exs test/pramana_foundry/policy_test.exs --seed 0`
  passed 7 tests.

The first clean full-run attempt failed 2 of 426 tests because the pre-existing RPC wrapper
fixture hard-coded `_build/test`. That is retained as diagnosis evidence rather than counted
as a pass. After the fixture used `Mix.Project.build_path/0`, its focused eight-test suite
passed under a non-default build path. The candidate was then re-frozen for two clean runs.

The final acceptance runs occur twice from clean detached checkouts after this candidate is
committed. Their external artifact directories and SHA-256 values are reported to the
coordinator and independent reviewer; they are not retroactively written into this frozen
candidate.

## Explicit exclusions

- No real provider, paid model, credential or Herdr conformance evidence.
- No live daemon replacement, reconfiguration or activation.
- No Git integration or full restart-lifecycle proof; FR-17/FR-22 own those gates.
- No claim that the seven baseline formatting files are formatted.
- No vulnerability assessment of OWL, BEAM, GitHub Actions or provider tooling.
