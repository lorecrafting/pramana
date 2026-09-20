# FR-08A atomic-composition settlement-presence correction — narrow PASS

Snapshot: 2026-09-20. Independent reviewer
`/root/fr08a_atomic_bundle_rereview`, separate from implementation.
**PASS for the final narrow correction and the previously identified B3/B5 blockers.**
The [previous BLOCKER](atomic-composition-final-rereview.md) remains historical evidence
for its exact candidate; this report supersedes its settlement-presence finding only
for the subject below. It is not permission to activate execution or an exhaustive
review of every FR-08B lifecycle composition.

## Exact subject

| Item | Identity |
|---|---|
| Runtime/tests | `67a2b923ef58f98290457f4640561bc5d44f9db8` |
| Runtime/tests tree | `687172583725ff5f4f2a4ff47cc868380b43b4de` |
| Evidence-bound candidate | `721a9e86ed51b776785a7260890b39f894fc1c5a` |
| Final candidate tree | `2d33301fc50ebd04102e6874c0423e094574c9c2` |
| Worktree / branch | `/Users/raymondluong/dev/pramana-fr08a-atomic` / `codex/fr08a-atomic-bundle` |

Inspected the exact correction diff and rebound evidence. Ran only the two existing
maintained/review matrices; no new fault, corruption or mutation variants were created.
This commit changes only review documentation and navigation.

## Why the blocker is closed

`valid_committed_settlement_carrier/4` now separately computes whether the field exists
using `Map.has_key?/2`, and whether a `settle_claim` result's authoritative receipt says
`non_started`. That outcome requires both a present key and a map value, then executes
the existing authoritative binding validator. Missing and explicit null carriers
therefore return false and enter recovery. New maintained tests exercise both cases.

The exact binding validator remains unchanged: complete typed settlement shape,
role/owner/generation/predecessor/failure/identity agreement with root effect/claim/receipt,
positive ordinal, and byte equality with the authoritative settlement row. The independent
table/lineage validator remains. The duplicate path retains its map/schema requirements,
operation claim/receipt/failure binding and exact stored settlement bytes. The previous
ordinal-forgery probe still passes.

For outcomes that do not require a settlement, any presence of the settlement key now
returns false, including explicit null or an injected map. Only true absence is accepted.
The new ordinary-policy positive control survives reopen with that key absent. Rejection
of injected/null keys on ordinary operations is established by source inspection here;
no new injection variant was run.

The previous nested scalar outcome fix is unchanged, and its existing probe passes.
The map/type guards reviewed in the previous report remain. This is bounded source and
test evidence, not a proof over all possible malformed histories.

B1/B2/B4/B7 behavior and the original B6 repeated-policy prestate control remain green
in the existing matrix. The prior qualification about exhaustive transitive staged
composition coverage under B6 remains; this small correction does not expand that scope.
There is no diff to Gateway, Database or the operational-storage fixture from the
previously reviewed candidate. The single outer transaction and fixed typed operation
boundary remain, with no SQL/callback/arbitrary-root-update/candidate-code API added.

FR-19A fixture hardening is unchanged: autocheckpoint is disabled only on the owned test
connection; positive uncheckpointed NOOP frames are required before physical filesystem
fill; error/recovery/WAL/reopen checks remain. Production WAL settings are unchanged.

## Checks and provenance

Successful reruns used `login: false`, separate fresh `mktemp -d` roots and separate
`MIX_BUILD_PATH` values. `MIX_ENV=test`; the absolute Mix executable was
`/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin/mix`.
PATH began with that Elixir bin and
`/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin`.

| Check from `foundry/` | Result |
|---|---|
| `mix run --no-start docs/fr-08/atomic-composition-review-probes.exs`, seed 92022 | Exit 0; 40 passed |
| `mix run --no-start docs/fr-08/atomic-composition-rereview-probes.exs`, seed 92032 | Exit 0; 15 passed |
| Rebound evidence source SHA-256 inventory | All listed hashes match |
| Staged documentation check / whitespace check | Exit 0; 80 passed / passed |

The suites inherit maintained atomic tests, so their counts overlap. Logs:
`/private/tmp/fr08a-presence-existing-matrix-isolated.log` and
`/private/tmp/fr08a-presence-existing-rereview-isolated.log`.
Initial parallel invocations reused the worktree build directory and both exited 1
on telemetry BEAM rename collisions before executing tests. The sequential isolated
reruns above resolved that harness error without modifying implementation or tests.

Independently inspected and checked
`/private/tmp/fr08a-presence-pinned-ci.b4OzkU/provenance.json`: exact clean
`721a9e8` / `2d33301`, identical pre/post source objects, pinned Elixir 1.20.3 / OTP 29.0.5,
all dependency/compile/format/test/inventory/escript phases passed with exit 0.
The coordinator reports 625 passed, 13 skipped and one optional exclusion. The JSON
independently establishes the successful test phase and one declared optional exclusion;
it stores an output hash rather than passed/skipped counts, so those counts are attributed
to the coordinator. Source bindings were independently checked. Loaded BEAM binding is
credited through canonical CI, not presented as an independently inspected live release.

## Limits

This review closes the identified settlement carrier and nested-outcome defects for the
exact subject. It does not replace the earlier broad review history or certify all
migration/reopen/backup/staged-composition permutations. FR-08B role transitions,
pause/drain/cancel/exhaustion and every-ingress migration remain deferred, as do FR-18A
observations, actual isolation, provider execution, activation and FR-22 acceptance.
No new physical fault or power-loss guarantee is inferred. No runtime change, push,
integration or deployment was performed.
