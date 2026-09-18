# FR-08 read-only investigation

Prepared 2026-09-13 by `/root/fr08_investigate` against main commit
`6613810895934cffd2f70b63f543b0f292f1b40f`. This is dependency preparation, not
implementation or review. The investigator changed no repository file, live process,
provider or Git ref. The full working note had SHA-256
`0124e166dff0e7374c21c7f6e72adee8136e6e31e5b143a645077dfdd0fe9a7f`.

## Conclusion

FR-08 is not an extension of the legacy `Transition` module. It requires one pure
`decide(state, command, inputs)` function and one `apply(state, event)` reducer, with
the same reducer used after live commit and during reconstruction. The current system
instead has live mutation in Coordinator, Coordinator.State, Tick, PM, correction,
cleanup and agent callbacks; separate replay in Transition; direct time/ID generation;
and unpersisted controls and reset paths.

The protected/domain split must be structural. Kernel events may advance domain
projections but cannot directly update protected claims, balances, accepted refs,
policy or receipt validity. FR-08 must adapt every mutation ingress to FR-07's gateway,
not add another compatibility reducer.

## Confirmed migration traps

- Pause, resume, stop, reset, public admission and several block/retry paths mutate only
  memory. They need durable idempotent commands.
- PM replay records only `last_proposal`; it loses the actual create, split, amend,
  reprioritize and park mutations.
- `launch_intent`, `launch_completed` and `prompt_delivered` are written by effect helpers
  but are not all accepted by strict Transition replay.
- CLI `handoff block` constructs `{outcome, summary, task_id}`, not the actual blocked
  artifact schema. Public end-to-end acceptance must catch this.
- Wall-clock reads and generated IDs occur throughout Coordinator.State, PM, correction,
  Transition, Coordinator, Tick and CLI. FR-08 must sweep them into explicit inputs.
- Existing duplicate-record projection and `Checkpoint.matching/5` are not command
  idempotency. Same actor/ID/digest must return the original durable result; any actor or
  payload conflict must fail.
- Current retry/correction counters do not represent R5 generations, allocations,
  reservations, holds, consumption, refunds or late settlement.
- Exit/result ordering currently depends on direct process messages and inferred status.
  Durable inbox sequence/seal facts are required before adapter migration.
- Existing dirty root `ticket unblock` edits ignore append failure and conflict with this
  architecture. They are uncommitted user work, not a baseline or approved FR-08 path.

## Required FR-07 handoff capabilities

Before FR-08 begins, verify that FR-07 provides:

- actor + command ID + canonical digest lookup before revision checks;
- complete entity/policy/control/allocation read-set CAS with explicit absent values;
- atomic command result, ordered events, projections, effect/claim/receipt, lease and
  ledger/reservation rows;
- indexed revisions and authenticated inbox sequence/seal facts;
- structural rejection of kernel attempts to forge protected fields;
- explicit recovery/error outcomes with no effects before checked commit;
- immutable original legacy import and explicit unsupported-record reporting.

Do not infer these capabilities from generic JSON payload columns or table names.

## Proposed implementation sequence

1. Land canonical encoding vectors, command/read-set schemas and pure kernel tests.
2. Add gateway equivalence/idempotency tests against the exact FR-07 API.
3. Sequentially route controls, admission, scheduling, submissions, observations,
   PM proposals, corrections, cleanup and recovery through the common command path.
4. Retire legacy live/replay authorities only after equivalent public and replay tests
   exist; keep containment tests until then.

Completion requires every supported command/verdict/control to cover live, replay,
duplicate and applicable stale/conflict cases. R4a traces must distinguish pre-intent
denial, proved non-start and unknown start for every role, including restart before
redispatch. R5 tests must cover conservation, multi-ticket allocation, recursive
delegation, duplicate/conflicting receipts, bounded infrastructure retries, resets and
late settlement against the original generation. Replay must never invoke Git, backend,
clock, random generation, configuration or provider effects.


## Executable handoff-gate plan — 2026-09-17

This investigation will be paired with a small executable conformance gate before FR-08
implementation begins. The gate is preparation only: it must not modify or substitute for
the active FR-07 store implementation, and a missing FR-07 public boundary must report
**blocked/not yet available**, never a false pass.

The first gate will encode the handoff capabilities listed above as named probes against a
small provider-neutral adapter. It will distinguish **passed**, **failed** and
**unavailable** capabilities, produce deterministic machine-readable output, and require
all mandatory capabilities before declaring FR-08 ready. Fixture adapters will prove the
gate catches missing, failing and contradictory capabilities without relying on the live
FR-07 worktree. Once FR-07 lands, one thin adapter may bind these probes to the accepted
public API; that binding is the only dependency-specific layer.

In parallel, the Pramāṇa CheckRun cancellation regression will be made synchronization-
based so it proves worker death precedes completion without depending on ExUnit's implicit
100 ms receive timeout. These two changes are intentionally grouped as repair-readiness
work: one removes CI timing noise, the other shortens the FR-07 → FR-08 handoff.
