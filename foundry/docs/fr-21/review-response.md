# FR-21 response to independent review

Date: 2026-09-13

Reviewed v1: `85a74492959e6db51f4a0f03c218990afb97b0c3`

The exact independent FAIL is preserved in `review.md` with SHA-256
`da11d18a4cfe7f7842ccb9309e63f6dbb8319b41967c5f0e30fb723c86eac36c`.
This response changes only the five reported blockers and the two documentation notes.

## B1 — ambient Python/tiktoken

Resolved without adding a dependency. The default model-free test reads and asserts the
recorded benchmark fixture entirely in Elixir. Recomputing that historical measurement is
now a separately tagged `:python_tiktoken_recompute` test excluded from default CI. The
manifest reports that exactly one declared test matches that exclusion. Provider tags each
match zero tests and are reported as absent, not as skipped evidence.

The external recomputation code remains available for deliberately refreshing the dated
measurement, but a green default CI run no longer depends on ambient `tiktoken`. Clean-run
acceptance uses a Python installation without `tiktoken` to prove this distinction.

## B2 — dirty source could pass

Resolved by two fail-closed checks. Before dependency restoration or compilation, the runner
requires an available Git identity and an empty tracked/untracked porcelain status. After all
commands and removal of the generated checkout-local escript, it re-reads the status and
requires the same commit/tree plus no dirty paths. A dirty source failure records its status
digest and paths, runs zero commands, emits no artifact, and exits nonzero.

## B3 — missing/incomplete failure provenance

Resolved with provenance schema v2. The runner derives and creates the requested output first,
then atomically writes a skeletal manifest before project, cleanliness, toolchain, dependency
or isolation checks. The skeleton already contains every available commit/tree/dirty,
runner/workflow, exact toolchain, lockfile/package and exclusion identity. Each stage and
command atomically replaces the manifest. Nonzero commands and command spawn exceptions have
explicit argv, status, exit/error, duration, empty-or-real output digest and isolated
environment receipts. Setup failures preserve the skeleton and append their failing stage.

The sole physical exception is an output directory that cannot be created or written: no
program can place evidence at an unavailable destination, so the runner exits 70 and reports
the path/error to stderr.

## B4 — major-only OTP comparison

Resolved with `ci/toolchain.exs` as the Foundry CI policy: Elixir 1.20.3, OTP 29.0.5 and ERTS
17.0.5. The runner reads the installed OTP patch from the runtime's `OTP_VERSION`, reads the
ERTS version from the emulator, and requires all three exact values. Workflow regression tests
bind setup-beam's necessarily duplicated inputs to the canonical policy file.

## B5 — dependency policy was descriptive

Resolved by executable preflight and resolved-source gates. Tracked `deps/` content or a
tracked `pramana_foundry` escript fails before work. After locked restoration and before
compile, the runner loads the complete selected Mix dependency graph and requires every entry
to use `Hex.SCM`, carry the exact committed Hex lock entry, and resolve beneath the unique
`MIX_DEPS_PATH`. Path, Git, unlocked, lock-mismatched and nonisolated inputs fail. The manifest
records each resolved dependency's name, requirement, SCM, status, lock kind/match and source
destination. Regression tests cover every rejected class.

## Documentation corrections

The retired Parity documentation now says its only successful response is an explicit retired
metadata query, never a comparison. `docs/CI.md` describes the v2 failure, exact-toolchain,
dependency enforcement and measured exclusion-count behavior.

## Evidence and limits

Focused checks, adversarial failure probes and two clean detached full runs are recorded in the
v2 candidate artifact and reported to the coordinator after freeze. The same exclusions remain:
no provider/paid/Herdr conformance, live daemon, activation, Git integration or FR-22 lifecycle
claim. The optional historical tokenizer recomputation is not evidence run by default CI.
