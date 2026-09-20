# FR-08A atomic-composition independent review — BLOCKER

Snapshot: 2026-09-20. Reviewer: fresh independent Astra-high, separate from
`/root/fr08a_atomic_bundle_impl`. **BLOCKER for the frozen candidate.** The eight
maintained atomic tests pass, but independent variations reproduce accepted domain
work after a rejected protected operation, incomplete rejection persistence, and
unverified authority/history after reopening. Rebinding the historical evidence
cannot correct these runtime failures.

## Exact subject and boundary

| Subject | Identity |
|---|---|
| Candidate commit | `9a8a4912bcc86d1f58b50a65f9cc148982ac3915` |
| Candidate tree | `325652033c56f582ea3102650770dd5a73b3c0bb` |
| Base | `d0059b03757a73085f430895304244afaec79ce2` |
| Branch | `codex/fr08a-atomic-bundle` |
| Worktree | `/Users/raymondluong/dev/pramana-fr08a-atomic` |
| Diagnosis examined | `foundry/docs/fr-08/atomic-composition-diagnosis.md` at `87025bd` |

Read the repository/shared workflow and Elixir conventions, Foundry index, R2/R3
authority and command/bundle protocol, R4/R4a/R5, FR-08A/B acceptance and the accepted
FR-08A/FR-19A combined review. Inspected all four changed implementation files and
the changed atomic tests, with relevant inherited verifier/replay and operational
storage paths. Historical PASS statements were treated as revision-bound evidence.

Only this report, the [review probes](atomic-composition-review-probes.exs), and a
README route are review edits. No implementation, maintained tests, frozen evidence,
repair-plan status, provider settings, deployment, push or integration changed.
The tests use disposable stores and isolated model-free application state. Raw SQLite
edits are negative recovery fixtures after stopping their Gateway; they make no claim
about administrator-resistant cryptography or actual host isolation.

## Blocking findings

### B1 — A cached rejected operation can commit an accepted bundle

`Gateway.stage_atomic_operations/3` treats `:idempotent` exactly like `:accepted`.
`ProtectedPrimitives.execute_in_transaction/4` returns that status for any previously
stored result, including a rejection. The operation ID is the public string
`<bundle-command-id>/protected/<ordinal>` and has no exclusive bundle ownership.

The public probe first submits `cached-rejection/protected/0` with an incomplete
policy read set and retains its rejected result. Submitting the corresponding atomic
bundle then returns **accepted/committed**, records a queued domain projection, and
contains that same **rejected** protected outcome. The policy was never created.
This is executable acceptance of a transaction whose prerequisite was rejected.

A separate public probe commits a valid atomic bundle, then submits its command through
`Gateway.transact/4`. The domain-only route returns `:idempotent` with the v1 domain
component instead of rejecting the changed semantic envelope. Global identity is thus
not uniformly bound to the complete atomic request across ingress routes.

Correction: namespace and bind every operation identity to its owning envelope; reject
cross-owner reuse, enforce stored disposition when recovering an operation, and resolve
global command identity consistently across v1/v2 routes. Do not infer success from a
cache-hit status.

### B2 — An early semantic rejection cannot persist its durable result

The operation reducer halts at the first rejected operation and persists only the
executed prefix. `validate_bundle_operations/4` nevertheless requires exactly
`length(envelope.operations) + 1` rows. A two-operation bundle whose first operation
has an incomplete read set returns `storage_unavailable / protected_corrupt /
atomic_bundles`, rather than a durable semantic rejection. Its rejection transaction
rolls back. The maintained rejection test fails only on its last operation and misses
this case.

Correction: represent the entire ordered operation history, including explicit
unexecuted outcomes, or define and validate a typed rejected-prefix schema. Retain the
original semantic rejection without treating it as storage corruption. Rolled-back
provisional facts must remain clearly noncommitted outcomes.

### B3 — Settlement facts are not reconstructed from attributable receipts

`validate_infrastructure_settlements/1` checks only column/state-byte equality. It does
not derive the role, owner, generation, predecessor, failure class or ordinal from the
accepted effect/claim/receipt, nor require a settlement for each applicable v2 non-start.

After a valid non-start, changing only the settlement row and its state to role `pm`,
owner `invented-owner`, generation `99`, ordinal `900` reopens **ready**. Deleting the
settlement entirely also reopens **ready**, despite retained accepted bundle evidence
containing it. These fixtures preserve original authenticated commands and receipts.

Correction: derive the immutable settlement exactly once from typed accepted history
and attributable receipt; enforce a bijection with required settlement rows and validate
the owner/generation/predecessor ordinal chain. Matching copied carriers is insufficient.
The new count/predecessor reads also need explicit protected read-set coverage.

### B4 — Typed history and partial migration are not fail-closed

For v1 owners, `valid_durable_operation?/5` accepts any binary request/result without
binding it to the original command, type or outcome. Updating the singleton type to
`grant_ledger` and replacing both blobs with `invented` reopens **ready**. Deleting all
singleton rows also reopens **ready**.

A partial-migration fixture leaves `durable_operations` present with forged blobs,
removes the other v2 tables/marker and sets the protected schema marker to v1.
`Gateway.migrate/1` returns **`:ok`**, retaining the forged singleton rows through
`ON CONFLICT DO NOTHING`. This is not a supported complete v1 prestate.

Correction: validate supported exact migration states before applying DDL, require one
byte-identical singleton for every v1 command/result, reject missing/orphan/extra history,
and refuse partially installed or mismatched rows. Preserve original command bytes,
IDs and results while adding independently checked history.

### B5 — V2 outcomes can be truncated or substituted; malformed rows crash recovery

`validate_bundle_operations/4` zips envelope operations, result operations and stored
rows without requiring equal result-array length. Replacing only a valid bundle's
`result.operations` with `[]` reopens **ready**. A second fixture changes the copied
policy revision to `999` in the bundle result and its durable-operation row while
leaving the real protected command result and policy untouched; it also reopens
**ready**. The copied v2 outcome is not bound to its actual root operation outcome.

Changing a protected durable row's `operation_kind` to the otherwise valid `domain`
value raises a `MatchError` in the validator's function body. Gateway startup crashes
instead of returning its explicit recovery state.

Correction: validate array cardinality, operation IDs/types/ordinals, unique owner
binding and exact protected outcome provenance before trusting v2 results. Reject all
malformed carriers through total validators; do not destructure untrusted rows with
raising matches. Apply these checks to lookup, reopen, replay and backup.

### B6 — The API does not implement the required complete prestate read set

The bundle has per-operation expected revisions, and each operation compares them
against the state already mutated by preceding operations. There is no complete
bundle-prestate verification or declared staged-dependency representation.

The probe writes the same initially absent policy twice in a declared order, with
both operations referencing its absent prestate. It is durably rejected as stale:
the second operation is required to invent revision `0` from the staged first write.
This demonstrates the current staged-state convention, rather than the required
single complete prestate contract. New settlement count/predecessor dependencies are
not added to `required_reads/2` either.

Correction: specify and implement one complete prestate read/absence set, validate it
before protected mutations, and separately validate references to earlier staged outputs.
Include transitive protected dependencies, including settlement lineage. Add positive
reserve/admit/settle compositions and absence-race cases against that contract.

### B7 — Repeated attributable receipt cannot recover its immutable settlement

After a successful non-start, a new command carrying the same receipt and current
complete reads is accepted by the underlying settlement operation as an existing
receipt. The additional settlement writer then tries to create a new ordinal and fails
with `invalid_nonstart_infrastructure_settlement`. The atomic bundle is rejected.
The maintained test explicitly expects this rejection; it does not prove the contract's
receipt-identity idempotence or successful retrieval of the original settlement fact.

Correction: look up the existing settlement by attributable effect/claim/receipt identity,
verify exact equality, and return it without incrementing or releasing again. Independently
validate any new domain proposal; duplicate receipt identity cannot authorize unrelated
domain work. Conflicting evidence must retain the quarantine path.

## Credited behavior and evidence limits

The source has one Gateway-owned outer transaction and fixed noncommitting protected
dispatch. The public bundle does not accept SQL, callbacks, arbitrary root updates or
candidate decide/apply functions. Complete normalized actor/inputs/ordered operations/
domain proposal participate in the atomic digest, and normal same-envelope retry occurs
before CAS. Cross-route and operation-ownership exceptions are B1.

Ten independent SQLite `RAISE(ABORT)` controls, installed only in disposable stores,
passed at `root_policy_history`, `root_policies`, `root_commands`, `inputs`, `commands`,
`events`, `projections`, `command_results`, `durable_operations` and `atomic_bundles`.
Every tested failure left no accepted command or policy after reopen. The maintained
after-protected, after-domain, before-commit and postcommit-lost-reply cases also passed.
These are logical fault controls, not physical power-loss evidence or coverage of every
write performed by every supported operation.

Independent controls passed for stale-read rejection and exact retry after reopen,
unknown-start hold retention, non-start settlement after cancellation, and a mixed
productive-policy/conflicting-receipt bundle committing neither productive policy nor
domain changes. The mixed bundle also rolls its quarantine back; its durable rejection
is preserved. The unknown control asserts retained effect/reservation/ledger state;
despite its probe title, it does not submit a replacement launch.

The eight maintained tests substantiate bounded positive transactions, role-labelled
settlement rows, backup equality, coarse rollback, identity variation and a synthetic
v1-shaped migration. Their developer/reviewer/PM cases all use the same generic queued
projection fixture; they do not establish the three actual role lifecycle transitions,
owner reconstruction or no-redispatch behavior. Pause/drain role transitions, scheduling,
exhaustion and every-ingress migration remain FR-08B. The rejected direct `paused` and
`draining` control spellings observed during probe authoring were removed from the final
suite; they are not presented as new composition blockers.

Reserve+intent, parent admission, close/reset/transfer conservation and late-generation
behavior retain inherited affected-suite coverage, but this review did not independently
exercise every combination through the new v2 route. Nor does it claim full transitive
absence-race coverage, old-build rollback compatibility, provider execution, actual
principal/channel isolation, loaded deployment or FR-22 acceptance. Review finalization
was requested after the reproduced blockers; further fault experimentation stopped.

## Executed checks

Pinned toolchain: Elixir `1.20.3`, OTP `29.0.5`; `TMPDIR=/private/tmp`.

| Check | Result |
|---|---|
| Maintained `atomic_bundle_test.exs`, seed 92021 | Exit 0; 8 passed |
| Final independent probe, seed 92022 | Exit 2; 22/35 passed, 13 failures grouped B1–B7 |
| Durable-store and repair directories plus legacy containment, seed 92023 | Exit 2; 173/176 passed; two stale bindings and ENOSPC fixture |
| Base `d0059b0` ENOSPC checkpoint fixture, seed 92024 | Exit 0; 1 passed, 15 excluded |
| Candidate same ENOSPC fixture, seed 92024 | Exit 2; 0/1 passed, 15 excluded; zero-frame success |
| Coordinator canonical CI, independently inspected provenance | Exit 2; reported 617/620 passed, 13 skipped and one optional exclusion; exact clean candidate/tree |
| Staged review documentation check | Exit 0; 80 passed; staged diff whitespace check passed |

The coordinator's canonical provenance is at
`/private/tmp/fr08a-atomic-ci-9a8a491/provenance.json`; its compile and formatting phases
passed. It identifies the exact clean candidate and isolated dependency/build/runtime
roots. The two FR-08A report failures are expected stale source/BEAM bindings and require
rebound evidence after a corrected freeze; they are not themselves runtime blockers.

The third failure is `operational_storage_test.exs:515`: the candidate checkpoint returns
success with `checkpointed_frames=0` and `log_frames=0` on the filled filesystem. The
same isolated fixture passed on the exact base in a detached worktree. Therefore this
review **does not verify the claim that the failure is pre-existing/environmental**.
Zero frames explain why that call need not require a failing write, but WAL byte length
alone does not prove pending frames. The fixture's actual checkpoint precondition and
candidate/base difference remain unresolved acceptance evidence, not a demonstrated
loss of committed authority. No additional experiment was run after finalization.

An initial affected-suite invocation incorrectly used `--no-start` for tests requiring
the test application; it produced setup/fixture failures and was terminated. The table
reports the completed rerun with the isolated test application, coordinator ticking off,
and fresh runtime root. Initial probe mistakes in an unknown proof spelling and a SQL
table name were corrected before the final 35-test run and are not implementation findings.

Reproduce from `foundry/`, with the pinned toolchain on PATH:

```sh
TMPDIR=/private/tmp MIX_ENV=test mix run --no-start docs/fr-08/atomic-composition-review-probes.exs
TMPDIR=/private/tmp mix test --no-start test/pramana_foundry/durable_store/atomic_bundle_test.exs --seed 92021
TMPDIR=/private/tmp COORDINATOR_TICK=0 PRAMANA_RUNTIME_ROOT_FRESH=1 PRAMANA_OPERATOR_RUNTIME_ROOT=/private/tmp/fr08a-atomic-independent-operator mix test test/pramana_foundry/durable_store test/pramana_foundry/repair test/pramana_foundry/legacy_persistence_containment_test.exs --seed 92023
```

The probe reuses the frozen maintained fixture and appends independent assertions;
those assertions intentionally fail on the named candidate. Complete local logs are
`/private/tmp/fr08a-atomic-independent-probes.log`,
`/private/tmp/fr08a-atomic-independent-affected-corrected.log`,
`/private/tmp/fr08a-atomic-independent-base-enospc.log` and
`/private/tmp/fr08a-atomic-independent-candidate-enospc.log`.

Probe SHA-256: `58bac9f89d3c391addd90025fe4e86cf43a8ca12b3e9a99736d2ca103cd435e1`.
Final probe-log SHA-256:
`1793caba989f864ba84e52dd5e9011f602998c4032c05247e16435a601089a5e`.

Keep the correction bounded to the existing protected gateway, typed persistence,
prestate/dependency protocol and immutable settlement derivation. Then refreeze, rerun
the hostile cases and full affected checks, regenerate revision-bound evidence, and
obtain a fresh independent critical review. FR-08B scheduling work cannot compensate
for these protected-boundary defects.
