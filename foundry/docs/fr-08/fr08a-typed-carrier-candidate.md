# FR-08A typed result-carrier correction candidate

Frozen correction evidence, 2026-09-19 (Hawaii). This candidate addresses only T3 from
the [focused typed-replay review](fr08a-typed-replay-review.md). It still requires a very
narrow independent rereview and does not authorize integration or FR-08B.

## Exact subject

- Core correction: `f9e35b42d2eb768f4407543ac0f84e2758409ab4`, tree
  `d7123e6a4e4ccaac75a66522b1b049f3693a39da`.
- Revision-bound gate/report: `3ccbbc3639ae31cbb76daa08254523ecefe63aa7`, tree
  `0cbd15e29f1018bceba5c7751ab4aa2f369168d0`.
- Branch/worktree: `repair/fr08a-protected-primitives`, `/private/tmp/pramana-fr08a`.

Known singular result fields now accept only one direct, schema-v1 map of their declared
ledger, reservation, claim or effect kind, or an absent field. Lists, nested lists,
duplicates, scalars, wrong carrier kinds, missing/extra fields and wrong schema versions
fence recovery before snapshot collection. Explicit plural fields accept only flat lists
of the declared kind with unique semantic identities; duplicate and conflicting identities
fence independently of order. Singular collection has no list recursion. Unknown
diagnostic/artifact fields and receipt payloads remain opaque.

The maintained matrix preserves the independent 46 cases with the corrected singular
cardinality expectation and adds eleven shape permutations, for 57 passing cases. The
historical review script itself remains immutable: it reports 45/46 because its former
identical-list control expected readiness, which the requested stricter contract now
correctly rejects.

## Verification

All successful commands used `TMPDIR=/private/tmp`. Full CI used the pinned Elixir 1.20.3,
OTP 29.0.5 and ERTS 17.0.5 binaries.

| Check | Result |
|---|---|
| `mix compile --force --warnings-as-errors` | exit 0; 108 project files |
| Corrected typed-carrier matrix | exit 0; 57 passed |
| Prior typed-transition matrix | exit 0; 39 passed |
| Maintained matrix plus revision-bound gate | exit 0; 7 passed subprocess tests |
| Focused protected-primitives/correction tests | exit 0; 9 passed |
| Full model-free CI at `3ccbbc3` | exit 0; 574 passed, 1 external Python/tiktoken test excluded; dependency inventory, escript and clean-source postflight passed |
| CI provenance | `/private/tmp/fr08a-ci-3ccbbc3-pinned/provenance.json`; SHA-256 `b911810a634b0fe2acff75d368d14f9222601c09b4855508de444b7286a6d97b` |
| Root documentation check | exit 0; 80 passed |

No shared repair plan/log, provider, credential, daemon, deployment or integration path
was changed. FR-08B, combined FR-19A integration and activation remain outside this result.
