# FR-18A B5a–B5d correction independent rereview — PASS with one recorded gap

Narrow independent rereview, 2026-09-20. **PASS for B5a–B5d at the exact subject
below.** All four blockers recorded in [the B5 review](b5-review.md) are corrected, and
each correction holds under independently authored hostile and healthy-store probes.
One coverage gap in new protected read code is recorded below; it is not a reproduced
defect and does not block integration of this correction, but it must close before
FR-18A is marked complete.

Reviewer: Claude Opus 5, fresh session, no implementation context, separate from the
implementer. Recorded here as the evidence identity actually used. This is a narrow
re-review scoped to the reproduced B5a–B5d defects and their adjacent contracts, in the
tier the repair plan reserves for a bounded critical re-review; it is not a fresh
whole-surface critical review of FR-18A, and it does not revisit the blockers already
settled by [the correction rereview](correction-rereview.md) and
[the final B1 rereview](final-b1-rereview.md).

## Exact subject and evidence

| Layer | Commit | Tree |
|---|---|---|
| B5a–B5d correction implementation and tests | `98b6ef9fe4236d4741d54888845f64049d8ba738` | `92607c146bd3bfca6d27ed498710e77390ddb40e` |
| Corrected revision-bound FR-08A evidence | `aa173780365d732e1b6fe8ea07b86ca9348c863e` | `94fa3654e46bee4eb888e7cb5a7b9664126199f6` |
| Frozen candidate reviewed | `f3f038809262963e5f26e1b2dd127bc89c6bd3c9` | `490cb434b3110b2eee987b7e3bbf57c6eb8d0c9e` |
| Integrated base compared against | `057f2902580235d844679c43ece571056b60b8a5` | — |

Branch `repair/fr18a-honest-observations`, worktree `/private/tmp/pramana-fr18a.8plkoi`,
clean at review start and at review end apart from this report and its probes. Read the
shared workflow, the Foundry route, the repair plan's FR-18A criteria and shared
completion requirements, the workflow contract's R3/R4a/R5 and observation obligations,
the B5 review, the bounded-effect-query design and candidate records, and the complete
implementation diff with its surrounding read, validation and recovery paths. This review
changed no implementation, runtime, Gateway, Coordinator, daemon, provider, activation
or ticket status.

## Verdict per blocker

### B5a — bounded control and execution summaries: corrected

`read_target/5` no longer reaches the legacy unbounded `control` and `inbox`
materializers. `bounded_effect_control/2` and `bounded_effect_execution/2` select only
scalar prefixes and ordered aggregate sequences inside the existing query transaction;
neither the control state blob nor any inbox item payload crosses the SQLite boundary.

Budget accounting is correct and was verified rather than assumed. The new summaries are
built into `context` before `initial_effect_observation_state/2`, and
`effect_observation_size/3` sizes the complete response including them, so the base cost
is charged up front rather than discovered after section reads. The added post-build
`:erlang.external_size(response) <= context.max_bytes` guard is therefore a redundant
backstop, not the primary bound.

The closed `~w(active cancel_requested)` vocabulary was tested for over-strictness rather
than accepted from the diff. It matches the pre-existing `@control_statuses` and is
enforced at the write boundary: a `set_control` carrying no `status`, or a status outside
that pair, is refused `invalid_control_state` before it can reach a durable row. A healthy
store therefore cannot present a control value that this reader calls corrupt. Extra
unrelated keys alongside a valid status remain canonical.

The `bounded_effect_control/2` treatment of an absent control row as corruption, against
`bounded_effect_execution/2` treating an absent inbox as `"absent"`, is a deliberate and
correct asymmetry: an effect cannot be created without its control, while an execution
inbox is legitimately absent before first append.

### B5b — valid non-start reconciliation: corrected

`valid_settlement_current_status?/3` distinguishes the immutable non-start settlement
from current reconciliatory status, and admits `reconciliation_required` only when a
durably quarantined, committed `settle_claim` bundle carries a conflicting non-`non_started`
attempted receipt for the same effect and claim. The reviewed `failed` conflict now
reports `ok/canonical` with `unknown/reconciliation_required` and its historical ordinal.

The single reviewed conflict case was extended rather than re-run. A `succeeded` conflict
behaves identically. A second conflicting receipt is refused at the write boundary and
leaves the page canonical. The hypothesis that a *duplicate non-start* conflict would be
misclassified — the guard requires the attempted receipt's outcome to differ from
`non_started` — does not hold: that bundle is rejected before any reconciliation
transition, so no healthy store reaches the excluded state. Verified backup continues to
succeed in every conflict case.

### B5c — settlement field binding: corrected

Every emitted singleton scalar is now bound three ways: to the settlement row, to bounded
authoritative effect/receipt scalars, and to the accepted operation record via
`settlement_matches_required?/2`, with `validate_bounded_settlement_lineage/2` checking
ordinal succession and predecessor agreement. The six single-column mutations from the
original review are now corruption.

The binding was additionally tested from the authoritative side, which the original review
did not do. Mutating only the effect's own `$.role` — leaving settlement row and accepted
operation coherent with each other — is corruption. Mutating the settlement row *and* the
effect coherently, leaving only the accepted operation record disagreeing, is also
corruption. The binding is genuinely three-way rather than settlement-row-local.

The case analysis in `bounded_infrastructure_settlement/2` is complete: a settlement row
with no accepted operation requiring it, and multiple settlement rows for one effect, both
reach the catch-all corruption clause.

### B5d — bounded response source and version validation: corrected

`canonical_effect/2` validates the response and source schema, correlates
installation/repository/frontier to the surrounding snapshot and effect revision to the
header, and checks nested schema versions, relation count, encoded page size and
continuation shape before assigning canonical quality. The six adapter variations from the
original review — missing source, another repository, wrong protected frontier, wrong
effect revision, effect schema 999 and relation schema 999 — are all corruption, and
whole-envelope redaction still follows correlation.

## Recorded gap — untested enumerated execution-summary branches

`bounded_execution_summary/1` enumerates four statuses. Against a real store, `result` is
covered by the maintained materialization test and `absent` by this review's probes.
**`exit` and `sealed_without_result_or_exit` have no executable coverage anywhere in the
suite**; `sealed_without_result_or_exit` does not appear in `test/` at all. Those branches
carry real validation (`result`/`exit` must lie in `1..sealed_sequence`, and `sealed`
must not exceed `last_sequence`), and an error there would misreport terminal execution
state — the precise property FR-18A exists to make honest.

This is a coverage gap, not a reproduced defect: no probe in this review produced a wrong
answer from those branches, and the `atomic_bundle_test` fixtures cannot reach them
because they expose no `append_inbox`/`seal_inbox` helper. Required follow-up: add
real-store regression cases for both branches, including the sequence-range validation,
before FR-18A is marked complete. This does not block integrating the B5a–B5d correction.

## Executed checks

Isolated dependency and build roots outside the worktree, repository-pinned
Elixir 1.20.3 / OTP 29.0.5, `TMPDIR=/private/tmp`, `MIX_ENV=test`, `COORDINATOR_TICK=0`.

| Check | Result |
|---|---|
| Independent [rereview probes](b5-correction-rereview-probes.exs), seed 20926 | Exit 0; 23 passed (13 inherited atomic cases, 10 authored here) |
| Implementer-maintained observations, protected primitives, atomic bundle and FR-08A boundary suites, seed 20927 | Exit 0; 42 passed |
| Corrected [B5 review probes](b5-review-probes.exs), seed 18055 | Exit 0; 26 passed |
| Canonical CI at the frozen candidate, clean worktree | Exit 0; six stages passed, `dirty_paths` empty |

Canonical CI provenance binds source commit `f3f038809262963e5f26e1b2dd127bc89c6bd3c9`,
tree `490cb434b3110b2eee987b7e3bbf57c6eb8d0c9e`, clean before and after, with locked
dependencies, warnings-as-errors compilation, formatting, the model-free suite, dependency
inventory and escript build all passing.

The implementer's in-place rewrite of the reviewer-owned `b5-review-probes.exs` — flipping
its `REPRODUCED` assertions to assert required behavior — is correct practice under the
repair plan's standing instruction not to preserve a bug to keep a characterization probe
passing, and maintained regressions were added alongside in `atomic_bundle_test.exs` and
`observations_test.exs`. The original reproducing assertions remain recoverable in history
at `2d17717a24c1f5fac691574f503322d6780bb0cd`.

## Note on the canonical gate's temp-directory sensitivity

`PramanaFoundry.CI.create_run_root/1` derives its run root from `System.tmp_dir!()`, which
honors the invoking shell's `TMPDIR`. On macOS the default per-user `TMPDIR` is a symlink,
and `Gateway.initialize/1` correctly refuses a symlinked parent with
`:database_parent_symlink_not_allowed`, so the gate fails 74 DurableStore tests purely from
where it was invoked. Every CI result in this review was produced with `TMPDIR=/private/tmp`.
This is an FR-21 runner observation recorded for its owner, not an FR-18A finding, and no
change was made to the runner here.

## Disposition and limits

B5a–B5d are corrected. FR-18A's remaining obligation before completion is the recorded
execution-summary coverage gap. Integration of this correction releases the
`ProtectedPrimitives` ownership that the FR-08A protected-result/domain-plan binding
correction is waiting on.

This PASS binds only the exact revisions named above. It does not establish FR-18A
completion, FR-18B producer/board/usage wiring, FR-09/15a harness or OS isolation, FR-17
pointer production or activation, FR-19B maintenance expansion, or FR-22 lifecycle
acceptance. No provider, live daemon, global toolchain mutation, push, integration,
activation or deployment was performed. Fixture SQL writes and accepted fixture commands
affected only owned disposable stores.
