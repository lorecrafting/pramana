# Foundry continuous integration

Foundry has a standalone, model-free CI gate. It runs from `foundry/` without the
umbrella, corpus, Postgres, Rust or Python model sidecar:

```bash
cd foundry
elixir ci/run.exs --output /absolute/path/to/artifacts
```

Use the Elixir 1.20.3 / OTP 29.0.5 toolchain pinned by the repository. The GitHub job
installs those exact versions and pins each action to a full commit SHA. The Elixir runner
creates exclusive random dependency, build, temporary and runtime roots for every
invocation. It unsets the runtime override, tick and Herdr-provider switches before
running these checks. It rejects any tracked or untracked source change before work and
rechecks the exact clean commit/tree afterward.

1. restore the exact committed `mix.lock` with `mix deps.get --check-locked`;
2. inspect the complete selected Mix dependency graph and reject non-Hex, unlocked,
   lock-mismatched or nonisolated sources;
3. force-compile with warnings as errors;
4. check every formatter-owned file except the explicitly pinned baseline debt;
5. run the model-free suite while excluding explicitly inventoried external tests;
6. inventory the resolved dependency tree; and
7. build a fresh escript from the checked source.

The output directory contains `provenance.json` and, after a successful run, the generated
`pramana_foundry` escript. The JSON binds the source commit/tree and dirty paths, runner and
workflow hashes, exact lock entries and checksums, BEAM versions, isolation paths, command
argv/exit/duration/output hashes, excluded coverage, and escript hash. It is build evidence,
not acceptance or activation authority. FR-17 owns immutable activation; FR-22 owns final
lifecycle conformance.

## Dependency and executable policy

Hex plus the committed lockfile is authoritative for third-party source. CI resolves OWL
0.13.1 into a fresh untracked directory and records both Hex checksums. The previously
tracked `foundry/deps/owl/` copy was removed because it duplicated that authority without a
verification step. Restore dependencies with the runner or `mix deps.get --check-locked`.

Generated executables are never source inputs. The previously tracked escript was removed;
`foundry/pramana_foundry` and `foundry/ci-artifacts/` are ignored and reproduced by the
runner. A consumer must match an artifact's recorded SHA-256 and source commit rather than
assuming a file named `pramana_foundry` represents the checkout.

The policy is enforced, not descriptive: tracked dependency sources or a tracked escript fail
preflight. After restore, every resolved dependency must be `Hex.SCM`, match its committed lock
entry exactly and reside beneath the run's unique dependency directory. Path, Git and unlocked
dependencies are rejected before compile.

## Failure evidence and exact toolchain

`ci/toolchain.exs` is the canonical Foundry CI policy for Elixir, OTP and ERTS. The runner
compares Elixir 1.20.3, the installed runtime's exact OTP 29.0.5 `OTP_VERSION`, and ERTS 17.0.5.
The workflow's setup-beam inputs are regression-checked against that policy.

Provenance schema v2 is written atomically before fallible project/tool/dependency/isolation
work. Setup failures retain all identities available at that point and name the failed stage.
Each command records argv and either an exit code or spawn error. A manifest cannot be written
only when its requested output destination itself cannot be created or written; that condition
returns exit 70 on stderr.

## Formatting policy

Seven pre-existing files were unformatted when FR-21 established CI on 2026-09-13. Their
paths and SHA-256 values are isolated in `ci/format_debt.exs`; all other formatter-owned
files must pass immediately. A debt file cannot change unnoticed: CI fails if its bytes no
longer match the baseline. The ticket that next changes one must format it and remove its
entry. This records debt without reformatting unrelated source inside FR-21.

## Explicitly absent evidence

This job starts no daemon, Herdr pane, provider session, database or corpus service. It does
not authorize paid credentials, inspect provider conformance, integrate Git candidates,
activate releases or establish restart lifecycle acceptance. Real-provider evidence stays
bounded and separately reported under FR-09/FR-15a/FR-22. The job never closes a pane, so it
cannot close a foreign pane.

The default suite checks the saved tokenizer benchmark in Elixir. One separately tagged test
can deliberately recompute that dated measurement using external Python/tiktoken inputs; CI
excludes and counts that one test. No current test has a live-provider tag, which the manifest
reports as zero/absent rather than implying provider coverage was skipped.

The Python-migration parity harness and `pramana_diagnose.py` were retired on 2026-09-13.
Their former inputs did not describe the current store, fence or runtime. Sanitized Python
fixtures remain only as dated import-compatibility tests; they are not current parity proof.
