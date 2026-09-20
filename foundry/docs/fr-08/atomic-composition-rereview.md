# FR-08A atomic-composition corrected candidate — independent BLOCKER

Snapshot: 2026-09-20. Fresh independent reviewer
`/root/fr08a_atomic_bundle_rereview`, separate from implementer and first reviewer.
The corrected maintained hostile matrix passes, but two additional already-executed
variants demonstrate incomplete settlement outcome provenance and a non-total recovery
validator. **BLOCKER; no acceptance or integration recommendation.**

## Exact subject

| Item | Identity |
|---|---|
| Runtime/tests correction | `940ccfb3efbcfb533ebeec0f46d67c1f83d3681f` |
| Runtime/tests tree | `a62c1fdbe7f22a30acfc8affc5cff56c34576c8a` |
| Evidence-bound candidate | `154a9fb3df07554051cf6b20e68b27c838f8cc44` |
| Candidate tree | `3bcd03d29ba30d17235dc8d10afd6bc04fe6632d` |
| Branch | `codex/fr08a-atomic-bundle` |
| Worktree | `/Users/raymondluong/dev/pramana-fr08a-atomic` |
| Earlier BLOCKER | [First review](atomic-composition-review.md), commit `d1700a8` |

Read shared workflow, Foundry routing, applicable workflow atomic/R4a/R5 obligations,
FR-08A/B scope, first review and probes, correction diff and rebound evidence.
The diagnosis is absent from this branch; inspected its historical content with
`git show 87025bd:foundry/docs/fr-08/atomic-composition-diagnosis.md`.
Only this report, its [reproduction probes](atomic-composition-rereview-probes.exs)
and the README route are reviewer edits. No implementation was changed.

## Remaining blockers

### B3/B5 — Copied immutable settlement fact is not bound to the actual settlement

The new validator correctly derives the actual settlement table from receipts and checks
lineage. However `valid_protected_outcome_provenance/6` compares the protected outcome
after `without_settlement_carrier/1` removes `infrastructure_settlement`. No subsequent
check requires that removed value to equal the receipt-derived settlement row.

The independent variant commits a valid non-start, stops its disposable Gateway, changes
only `infrastructure_settlement.ordinal` to `900` in the atomic result and matching durable
operation result carrier, and reopens. The original command, receipt, effect and actual
settlement remain unchanged. Gateway reports **ready**, whereas the probe requires
recovery. This accepts a forged authority-bearing outcome even though the independently
derived actual settlement remains correct. The maintained altered-policy-outcome test
does not cover the specially excluded settlement field.

Minimal correction: require the complete settlement carrier, including required presence,
to equal the independently reconstructed settlement for the exact operation's
effect/claim/receipt. Apply that binding to committed and duplicate carriers and reject
settlement fields on operations that cannot produce them. Preserve root-result provenance.

### B5 — Nested scalar outcome crashes startup instead of entering recovery

The independent variant commits a valid policy bundle and replaces its result's
`operations` array with `[17]`. Cardinality is still correct. Reopening raises
`BadMapError` at `ProtectedPrimitives.valid_bundle_protected_row?/4`, line 4249,
when `Map.keys(operation_result)` receives the integer. The Gateway child fails startup;
it does not expose the explicit recovery state.

Minimal correction: validate every nested carrier's type before map access/destructuring,
including operation/result/facts and duplicate-settlement paths. A top-level map decoder
does not make nested values maps. Preserve explicit recovery errors for malformed input.
The corrected wrong-operation-kind test passes but does not establish total validation.

## B1–B7 disposition

| Finding | Rereview disposition |
|---|---|
| B1 identity/disposition | PASS for reviewed scope: reserved digest-derived operation IDs, public namespace rejection, stored disposition check and global domain/atomic identity refusal; original hostile controls pass |
| B2 early durable rejection | PASS for reviewed scope: full typed unexecuted/rolled-back outcomes, no provisional facts retained; early rejection and retry control passes |
| B3 receipt-derived settlement | BLOCKER remains for outcome carrier binding above; actual table derivation, missing-row refusal and lineage checks are credited |
| B4 exact v1/partial migration | PASS for reviewed scope: exact source-row singleton sets and exact supported table inventory; original forged/missing history and partial migration controls pass |
| B5 total provenance/recovery | BLOCKER: both additional variants above; cardinality and ordinary protected-result provenance corrections are credited |
| B6 complete prestate/staged dependencies | Original repeated-policy prestate control now passes; source compares protected prestate before writes and supplies staged reads from fixed operations. Full transitive staged-composition closure was not independently established; no broad PASS |
| B7 duplicate receipt | PASS for exercised original case: same immutable settlement retrieved once, typed duplicate result durably rejects new domain work; conflicting mixed-operation rejection remains covered |

The one Gateway-owned outer transaction and fixed noncommitting operation dispatch remain.
The envelope does not accept callbacks, SQL, arbitrary root updates or candidate functions.
Historical before/after write controls and current hostile tests provide bounded rollback
evidence. They do not certify every operation combination or every physical failure.
No newly discovered public command path for manufacturing the two corrupted rows is claimed;
these findings concern the explicit typed recovery contract.

## Checks and provenance

These executions were started before the coordinator restricted further fault/corruption
experiments. No additional such experiment was started after that instruction.

| Check | Result |
|---|---|
| Existing hostile matrix, seed 92022 | Exit 0, 35 passed |
| New variants plus inherited atomic fixture, seed 92032 | Exit 2, 8/10 passed; both new variants fail as described |
| Durable-store + repair + legacy containment, seed 92031 | Exit 2, 174/176 passed; failures below |
| Rebound report source SHA-256 inventory | Every listed source hash matches current files |
| Coordinator canonical CI provenance | Exact clean candidate/tree preflight and postflight equal; result passed, exit 0 |
| Staged review documentation check | Exit 0, 80 passed; staged whitespace check passed |

Local invocations accidentally selected Homebrew Elixir **1.20.4**, whereas canonical CI
uses pinned **1.20.3 / OTP 29.0.5**. This is explicitly not an independently repeated
pinned full acceptance run. Both new failures have direct source explanations, but a
pinned rerun of those probes was not performed after the stop instruction.

The affected suite's failures were fixture collisions: the maintained 57-case nested
matrix encountered `already_initialized` stores, and operational storage setup encountered
an existing `/private/tmp/fr19a-storage-4514` directory. They are not presented as product
regressions or as a passing affected-suite run. Further reruns would require fresh isolated
temporary roots and the pinned toolchain; they were not run.

Logs: `/private/tmp/fr08a-rereview-hostile.log`,
`/private/tmp/fr08a-rereview-variants.log`, `/private/tmp/fr08a-rereview-affected.log`.
Commands, from `foundry/`, were:

```sh
TMPDIR=/private/tmp MIX_ENV=test mix run --no-start docs/fr-08/atomic-composition-review-probes.exs
TMPDIR=/private/tmp MIX_ENV=test mix run --no-start docs/fr-08/atomic-composition-rereview-probes.exs
TMPDIR=/private/tmp COORDINATOR_TICK=0 PRAMANA_RUNTIME_ROOT_FRESH=1 PRAMANA_OPERATOR_RUNTIME_ROOT=/private/tmp/fr08a-rereview-operator mix test test/pramana_foundry/durable_store test/pramana_foundry/repair test/pramana_foundry/legacy_persistence_containment_test.exs --seed 92031
```

Inspected canonical `/private/tmp/fr08a-corrected-ci.mX2sOJ/provenance.json`: clean
`154a9fb` / `3bcd03d`, matching pre/post source objects, pinned toolchain, isolated
dependency/build/runtime roots, and passed command phases. The report binds `940ccfb`
and source/BEAM identities; the later evidence commit changes report/binding constants
and corresponding tests. Source hashes were independently checked. Loaded BEAM binding
is credited through the recorded canonical CI, not claimed as independently reverified
under the accidental local toolchain. CI passing does not cover the two new variants.

## FR-19A and deferred scope

The ENOSPC change is confined to the owned checkpoint test connection: it disables
autocheckpoint there, then requires `wal_checkpoint(NOOP)` to report positive log frames
and zero checkpointed frames before filling the disposable filesystem. The existing
physical full-filesystem error, recovery fencing, retained WAL and reopen checks remain.
Production WAL settings are unchanged in the correction diff. This strengthens the
checkpoint precondition instead of treating WAL file length as proof of pending writes.
The canonical CI passed; this reviewer did not separately rerun that physical test after
the stop instruction or inspect every canonical raw test output. No power-loss or
unavailable host/device guarantee is inferred.

Actual role-specific scheduling phases, pause/drain/cancel/exhaustion and every-ingress
migration remain FR-08B; minimal presentation/observation work remains FR-18A. They cannot
repair these FR-08A recovery defects. Actual isolation, providers, daemon activation,
deployment, and FR-22 acceptance are outside this review. Full migration/reopen/backup
composition permutations and total malformed-carrier coverage remain unproven. No push,
integration, provider launch or deployment was performed.
