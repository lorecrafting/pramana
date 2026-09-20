# FR-08A atomic-composition final narrow rereview — BLOCKER

Snapshot: 2026-09-20. Independent reviewer
`/root/fr08a_atomic_bundle_rereview`, separate from implementation. This is a narrow
review of the correction to the [previous rereview](atomic-composition-rereview.md).
Both exact previous reproductions now pass. **A source-confirmed B3 settlement-carrier
presence defect remains; this candidate does not receive PASS.**

## Exact subject and scope

| Item | Identity |
|---|---|
| Implementation/tests | `0cadb1f1c936304240c0b053503c45156c53f4e4` |
| Implementation/tests tree | `302248012d0d16760b9779c487740d955d5058ba` |
| Evidence-bound final candidate | `ede7f429a2a269b2e575c2be254a84c35541df91` |
| Final candidate tree | `4e8d226097d2281d13cfa2241f9cf6a1f0af15da` |
| Worktree / branch | `/Users/raymondluong/dev/pramana-fr08a-atomic` / `codex/fr08a-atomic-bundle` |

Inspected the exact implementation/test diff, complete affected validator chain and
evidence binding. No new fault, corruption or mutation variants were authored or run.
Only the two existing probe suites were rerun as requested, against disposable fixtures.
Only review documents and navigation are changed by this review commit.

## Remaining B3 blocker: absent settlement carrier is accepted

`valid_committed_settlement_carrier/4`, at
`lib/pramana_foundry/durable_store/protected_primitives.ex:4446`, matches:

```elixir
case {operation["type"], operation["outcome"], settlement} do
  {"settle_claim", "non_started", settlement} when is_map(settlement) ->
    valid_authoritative_settlement(conn, operation, root_facts, settlement)

  {_type, _outcome, nil} ->
    true
```

The second clause also matches an accepted `settle_claim/non_started` outcome whose
copied `infrastructure_settlement` is missing or explicitly null. This bypasses the
new mandatory shape/equality validation. The preceding provenance comparison deliberately
removes that field with `without_settlement_carrier/1`; removing the carrier therefore
still leaves the exact original root outcome. The later required-settlement inventory
uses `operation_result.facts.effect.effect_id`, not the copied settlement field, so an
unchanged correct settlement table satisfies that independent check.

Consequently, a missing/null copied settlement in both the bundle result and matching
durable operation carrier satisfies this validator chain for an otherwise valid accepted
non-start. It loses a required part of the complete durable outcome instead of entering
recovery. This is a static, directly traced finding; no new corruption experiment was
performed. The existing ordinal-forgery test tests a present map, which correctly takes
the new strict branch and does not exercise this missing/null branch.

Minimal correction: for an accepted non-start root outcome, require the field to exist
and be a valid map before the generic no-settlement case. Preserve the distinct treatment
of quarantined/rejected outcomes that do not create a settlement. For operations that
cannot carry settlement facts, require actual field absence if their result schema
forbids that field, rather than treating explicit null as absence. Rebind evidence after
the runtime correction and independently check the resulting exact candidate.

## Credited correction and B1–B7 disposition

The present settlement-map branch now checks exact schema/shape, positive ordinal,
nonnegative generation, all copied role/owner/generation/predecessor/failure/identity
fields against root effect/claim/receipt facts, then byte equality with the authoritative
settlement row. The independent table/lineage validation remains. The duplicate branch
requires a map, exact field set, matching operation claim/receipt/failure and exact stored
settlement bytes. These close the previously reproduced ordinal substitution.

The previous scalar operation-outcome startup crash is corrected by map guards before
map access. Inspected committed, duplicate, rolled-back and unexecuted paths now guard
the relevant nested result/facts/settlement maps. The existing scalar and wrong-kind
recovery controls pass. This is bounded source/test evidence, not an exhaustive proof
over every malformed JSON value or every historical protected primitive.

| Finding | Disposition at this candidate |
|---|---|
| B1 identity/disposition | Prior reviewed behavior preserved; existing controls pass |
| B2 early rejection | Prior reviewed behavior preserved; existing controls pass |
| B3 settlement binding | BLOCKER for required presence; exact present-map provenance correction credited |
| B4 v1 history/migration | Prior reviewed behavior preserved; existing controls pass |
| B5 total nested recovery | Previous exact crash fixed; existing recovery controls pass and changed nested guards inspected |
| B6 prestate/staged dependencies | Existing 37-case matrix passes, including prior prestate control; previous limitation on full transitive-composition coverage remains |
| B7 duplicate receipt | Existing recovery/no-unrelated-domain-work case passes; stronger duplicate carrier binding credited |

B6 did not receive an unqualified PASS in the previous report. Passing the same matrix
does not turn that explicitly unexamined scope into verified coverage.

Gateway, Database and the ENOSPC fixture have no diff from the previously reviewed
`154a9fb` candidate. One outer transaction, fixed typed operations, and the no-SQL,
no-callback, no-arbitrary-root-update and no-candidate-code authority boundary remain.
The owned ENOSPC fixture still disables autocheckpoint only on its test connection,
asserts positive uncheckpointed NOOP frames before filling the filesystem, and retains
the physical full-filesystem/recovery/reopen checks. Production WAL settings are unchanged.

## Executed checks and exact provenance

Both executions used `login: false`, fresh `mktemp -d` temporary roots, and explicit
toolchain paths:

```text
/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin/mix
PATH begins with that Elixir bin and
/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin
MIX_ENV=test
```

| Check, from `foundry/` | Result |
|---|---|
| `mix run --no-start docs/fr-08/atomic-composition-review-probes.exs`, seed 92022 | Exit 0; 37 passed |
| `mix run --no-start docs/fr-08/atomic-composition-rereview-probes.exs`, seed 92032 | Exit 0; 12 passed |
| Rebound report source-hash inventory | All source SHA-256 values match |
| Staged documentation check / whitespace check | Exit 0; 80 passed / passed |

Logs: `/private/tmp/fr08a-final-existing-matrix.log` and
`/private/tmp/fr08a-final-existing-rereview.log`. Both suites inherit the maintained
atomic tests; their counts overlap and must not be added as independent coverage.

Inspected `/private/tmp/fr08a-rereview-pinned-ci.CBJlkw/provenance.json`: exact clean
`ede7f42` / `4e8d226`, identical pre/post source objects, pinned Elixir 1.20.3 / OTP 29.0.5,
established isolated roots, all command phases passed, overall exit 0. The optional
exclusion has one declared test. The coordinator reports 622 passed and 13 skipped;
the provenance stores the test command exit status and output hash, not those counts.
Its artifact directory contains only provenance and escript, so this reviewer did not
independently verify those two raw-output counts. Loaded binding is credited through
canonical CI; source hashes were independently checked, not a newly loaded deployment.

FR-08B role transitions, exhaustive staged combinations and every-ingress migration,
FR-18A observations, actual isolation, provider execution, deployment and FR-22 remain
outside this bounded review. No new physical failure or power-loss guarantee is claimed.
No runtime modification, push, integration or deployment was performed.
