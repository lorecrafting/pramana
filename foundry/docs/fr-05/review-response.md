# FR-05 independent review response

Response to the independent **FAIL** artifact with SHA-256
`8324ecbe8c194b056d6b5a8ae5b8e7fafdab77ccc88640d8a771def46b369991`.
Only its two blocking findings were changed. FR-13 evidence verification, FR-14 ref
promotion and FR-17 activation remain unimplemented.

## R1 — resolved: every public legacy Pipeline operation is inert

`Integration.Pipeline` now identifies itself as a containment boundary. All six public
operations refuse with the same explicit FR-13/FR-14 restoration message before state,
runner, filesystem or Git effects:

- `acquire_owner/3` and `release_owner/2` cannot change ownership;
- `validate_readiness/3` cannot accept invented or missing Git/review/ticket facts;
- `run_gate_checks/3` cannot invoke either a supplied runner or `System.cmd`;
- `promote_candidate/3` cannot change an accepted revision; and
- `fail_integration/3` cannot mutate an assignment or owner.

The focused test calls all six boundaries with an invented candidate, an `auto_approve`
ticket and a nonexistent checkout. It byte-compares state, checks Coordinator state and
its event-log path, verifies the absent path remains absent, and proves no runner message
arrives. Historical owner tests now assert the suspension rather than exercising the
removed memory-only mechanism.

## R2 — resolved: direct ticket CLI parsing fails closed

`CLI.main/1` now parses ticket-create options against the fixed allowlist `--title`,
`--priority`, `--scope` and `--acceptance`. It rejects unknown and duplicate options,
missing values and empty required values before reading Coordinator state. Normalization
of case, hyphens, underscores and `--key=value` detects `auto_approve` requests and
returns the explicit independent-review requirement.

The direct CLI test covers true, false, hyphenated, uppercase, equals, missing-value and
duplicate auto-approve forms, plus an unrelated unknown acceptance control and a
duplicate allowed option. Every call leaves Coordinator state byte-identical and creates
no event log. The handoff and review commands already used exact argument shapes with
rejecting fallbacks; ticket status/integrate/list likewise do not discard extra options.
The read-only board/log commands are unrelated to acceptance and were not changed.

## Verification

Pinned Elixir 1.20.3 / OTP 29.0.5, fresh temporary roots, provider/tick variables unset,
and no real Herdr, credential, activation, accepted-ref or daemon operation:

- Reviewer six-file focused set, seed 506: **63 passed**, exit 0.
- Full model-free suite excluding integration, seed 506: **422 passed**, exit 0.
- Forced test compilation with warnings as errors: 77 files, exit 0.
- Production compilation plus `mix run --no-start`: six Pipeline refusals, nine direct
  CLI refusals, no runner invocation and no application start, exit 0.
- `git diff --check`: exit 0.

One preceding full-suite attempt selected Homebrew Python through an explicit PATH and
returned 421/422 because that unrelated environment lacked the suite's pre-existing
`tiktoken` package. Repeating with the original system Python and the same pinned
Elixir/Erlang binaries returned 422/422. No dependency was installed or changed.

## Final hashes

```text
8324ecbe8c194b056d6b5a8ae5b8e7fafdab77ccc88640d8a771def46b369991  foundry/docs/fr-05/review.md
45c2b19413cb4f4eb32469c35cf4a1c1bc0fd90e8e4f982cb58783c6a4386c5d  foundry/docs/fr-05/candidate.md
b967dea898c28f415cee391cd1aa4f1b55fe975d831c72588e9042cd50b8c67a  foundry/lib/pramana_foundry/cli.ex
a1660d6bc9a0e4ca086d810fd7a7fba64278520af61f6bddff59c4899ad80ee5  foundry/lib/pramana_foundry/integration/pipeline.ex
d1b827ea771136c95b4c5c3681f0c95b455e4877125696773ddd69c2ae4d02ea  foundry/test/pramana_foundry/fr05_containment_test.exs
9b1ae78c3d4b5458910f537424e2e436fb6dfd735f576aacbe650cf6f93b28b0  foundry/test/pramana_foundry/integration/integration_test.exs
6a1c087412a84e659ac6d2ac6d1bf707ce073bcb82b18e0c009086da0085d081  foundry/test/pramana_foundry/coordinator/engine_test.exs
456b3f6b86299d1e89a55fcd2e8bfaec09eff9b32ee16633cd03b66f9f44287a  foundry/test/pramana_foundry/coordinator/recovery_test.exs
```

This response file is excluded from its own non-self-referential hash list. The worktree
remains uncommitted.
