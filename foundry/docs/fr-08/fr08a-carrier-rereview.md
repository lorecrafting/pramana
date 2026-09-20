# FR-08A T3 typed carrier cardinality rereview — PASS

Independent narrow critical rereview, 2026-09-19 (Hawaii). **PASS for T3 on the
exact candidate below.** No residual cardinality or ordering blocker was reproduced.
This is not the combined FR-19A integration review, which still requires its separate
Astra-high gate.

## Exact subject

- Core `f9e35b42d2eb768f4407543ac0f84e2758409ab4`, tree
  `d7123e6a4e4ccaac75a66522b1b049f3693a39da`.
- Gate/report `3ccbbc3639ae31cbb76daa08254523ecefe63aa7`, tree
  `0cbd15e29f1018bceba5c7751ab4aa2f369168d0`.
- Evidence/catalog `f2e4a9110d46bee19f3438e74e467335c60e677f`, tree
  `72c8eb49c1ce8c8f3a76a3f6eb22965c9d711765`.

Verified all three trees directly in `/private/tmp/pramana-fr08a`. Read shared
workflow, Foundry orientation/strategy summary, FR-08A acceptance and R1/R5 contract,
the [residual review](fr08a-typed-replay-review.md) at
`cb1382ddf1b4e627390ea79128726d45c0f5e1d2`, correction source and probe fixtures.

## Findings

`protected_primitives.ex:4792` declares the operation-specific carrier kind and
cardinality. At `:4878`, validation runs before snapshot collection. A present singular
field must be one direct map with exactly the declared schema-v1 keys; null, scalar,
array, nested map/list, duplicate, wrong kind, extra/missing field and wrong schema
fail closed. Absence is permitted by this shape validator. Plurals require flat lists
of the declared kind and exact shape, with unique semantic identities (ledger identity
includes generation). Both conflicting orders and identical duplicates fence before
revision-based collection. Collection at `:4977` handles only the validated singular
map or flat declared list, with no recursive generic traversal.

The immutable old review now fences all four old/current, reversed and nested T3
fixtures. Its sole failure is the deliberately obsolete expectation that an identical
singular list restarts ready: actual result is `invalid_singular_transition_carrier`.
The maintained 57-case matrix correctly expects rejection and passes.

Fresh [bounded probes](fr08a-carrier-rereview-probes.exs) reuse 22 public-fixture
baseline controls and add 76 cases: direct/absent and malformed singular shapes for
ledger/reservation/claim/effect, plural ledger/reservation permutations and two distinct
reservation identities in both orders. Valid direct carriers and both distinct-list
orders restart ready. Maintained opaque diagnostic/artifact/receipt controls and prior
public shape-like receipt payload controls also pass. Unknown nested diagnostic maps
and lists are not traversed; the existing direct-extra-carrier conflict guard remains.

Absence is a carrier-shape allowance, not permission to delete required provenance:
removing the latest effect/claim or ledger snapshot may fail independent current-row
consistency; removing the original claim result fails claim-command provenance. Initial
fresh runs over-assumed readiness for these deletions (93/96, then 97/98). Final fixtures
remove superseded effect evidence for a positive absence control and explicitly assert
the claim provenance rejection. Empty ledger-list removal likewise fences for missing
current consistency, whereas empty reservation lists pass. No hostile rejection was
weakened into acceptance and no implementation changed.

## Executed checks

Fresh isolated build/runtime root `/private/tmp/fr08a-carrier-rereview.dPOllW`, pinned
Elixir 1.20.3 / OTP 29.0.5, dependency sources reused only. Commands ran from `foundry/`
through `sh /private/tmp/fr08a-carrier-rereview.dPOllW/run.sh`.

| Command | Actual result |
|---|---|
| `mix compile --warnings-as-errors` | exit 0; 108 project files |
| `mix run --no-start --no-compile docs/fr-08/fr08a-typed-replay-correction-probes.exs` | exit 0; 57 passed |
| `mix run --no-start --no-compile docs/fr-08/fr08a-transition-review-probes.exs` | exit 0; 39 passed |
| `mix run --no-start --no-compile docs/fr-08/fr08a-carrier-rereview-probes.exs` | exit 0; 98 passed |
| `mix run --no-start --no-compile docs/fr-08/fr08a-typed-replay-review-probes.exs` | exit 2; 45/46, sole obsolete identical-list expectation |
| `mix test --no-start --no-compile test/pramana_foundry/durable_store/protected_primitives_test.exs test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs test/pramana_foundry/repair/fr08a_protected_boundary_test.exs --seed 19411` | exit 0; 13 passed |
| Root `elixir bin/check_docs.exs`, evidence explicitly staged | exit 0; 80 passed |
| `git diff --cached --check` | exit 0 |

| Artifact in isolated root | SHA-256 |
|---|---|
| `run.sh` | `39604b9d3ca2ecf84d16b8baf2ad18fb696e9f43a8bf1d6bb4cb1a76049a35d9` |
| `compile.log` | `cb18f39c1909dbf9a136c5cdc9a3bee40445f9cbb0c463fb030daf6cd9488bc2` |
| `maintained57.log` | `16f93defcb2ea507decd17e11da90dc963d361994ba9f6e020ceef63ca2437c1` |
| `prior39.log` | `3aa3a13022a374240034849b1eb81ba440c4c74130400664893b8568d5540c13` |
| `focused.log` | `b402984ec6c3aea96c9718c6e40c4b521e2ed0702659b3de30c1a660cc3ff661` |
| `fresh98-final.log` | `d38afb86ef4db04e95eb4d62cfead6560193ebf4a7445d60d090289de87e5a07` |
| `historical46.log` | `e7d3bc9c6ccc1cd0f11e88711015b17b6b702895be5b0df805b6ecee3632cba7` |

Only review evidence and catalog navigation changed. No implementation, shared repair
plan/log, provider, daemon, push or integration changed. Full CI was not rerun; physical
media recovery, live providers, nonempty migration/rollback, FR-08B domain replay,
combined FR-19A integration and activation are not certified by this narrow result.
