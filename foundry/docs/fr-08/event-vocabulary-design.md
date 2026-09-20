# Durable event vocabulary extension — design

Date: 2026-09-20

Status: **design note; no implementation, no acceptance, no accepted vocabulary**

Author: Claude Opus 5.

This is subcommit 0 of the [FR-08A plan-binding correction](plan-binding-specification.md),
whose prerequisite section records the blocking finding. It is written as a separate
design note because it changes a contract shared with FR-08B and must be reviewed on its
own terms before any code is written.

## Exact base

`main` at `9dd30c3fd1624ef74bf697bc78eb0fc4d10154ba`.

## The finding, restated

The prerequisite section recorded that `RecordCodec` accepts nine event types while the
FR-08B kernel declares twenty-seven, intersecting in exactly one name. Further inspection
shows something more specific and more consequential.

Eight of the nine accepted event types map one-to-one onto the **legacy command
vocabulary** in the same module:

| Accepted event type | Legacy command |
|---|---|
| `legacy_event` | `legacy_event_append` |
| `ticket_enqueued` | `enqueue` |
| `ticket_steered` | `steer` |
| `ticket_paused` | `pause` |
| `ticket_resumed` | `resume` |
| `ticket_cancelled` | `cancel` |
| `effect_requested` | `request_effect` |
| `receipt_recorded` | `record_receipt` |

(`ticket_created` is the ninth, with no direct command counterpart.)

So the durable store's event vocabulary is the **pre-repair legacy lifecycle**. It was
never migrated to the v2 lifecycle that [R4](../WORKFLOW-CONTRACT.md#r4) defines. The
mismatch with the FR-08B kernel is therefore not the kernel inventing an idiosyncratic
vocabulary; it is the durable codec still speaking the vocabulary the repair replaced.

This matters for how the change is framed. It is a deliberate migration of a durable
contract toward R4, not an accommodation of one unreviewed candidate.

## Ownership split

- **This subcommit (FR-08A) owns the mechanism**: how the durable codec admits a second,
  explicitly versioned lifecycle vocabulary while preserving the legacy one exactly.
- **FR-08B owns the vocabulary's content**: which lifecycle events exist, their payload
  key sets and their correspondence to R4 rows. FR-08B's acceptance obligations are
  unchanged and none is waived here.

The mechanism is implementable and reviewable without settling every event name, which is
why it is separated. A seed vocabulary derived from R4 is proposed below so the mechanism
has a concrete first population, explicitly subject to FR-08B revision.

## Mechanism: version the event record, not the call path

`RecordCodec.normalize(:event, _)` requires `schema_version == 1` and membership in a
single closed list. Two options were considered.

**Rejected — thread a vocabulary parameter through the call path.**
`normalize_candidate/1` is shared by the v1 `transact` path (`gateway.ex` lines 518, 550)
and the v2 atomic path (line 598), so the accepted vocabulary would depend on which
function called it. The persisted record would then not describe itself: replay, reopen
and backup validation would have to know the writing path to know which vocabulary
applies. That is precisely the ambiguity the repair is removing elsewhere.

**Chosen — a versioned event record.** A durable event declares `schema_version`. Version
1 keeps exactly today's nine legacy types, byte-for-byte unchanged. Version 2 admits the
R4 lifecycle vocabulary. Validation dispatches on the record's own declared version.

Consequences, all of which are properties the repair wants:

- The persisted bytes are self-describing. Replay and backup validation read the version
  from the record and need no knowledge of the writing path.
- Version 1 records are untouched, so existing histories keep validating unchanged.
- An unsupported version fails closed, as `supported_version/1` already does for bundles.
- **A bundle mixing event versions is rejected.** Partial version states are exactly what
  the diagnosis requires failing closed on, and a bundle whose events disagree about which
  lifecycle they describe has no coherent reading.

## Seed vocabulary proposed from R4

Derived from the [R4 transition table](../WORKFLOW-CONTRACT.md#r4) rather than from the
preserved kernel work in progress, which is unreviewed and mid-correction. Each entry
must trace to a row or entity state; entries that cannot are omitted rather than guessed.

Admission and specification: `objective_created`, `ticket_admitted`, `ticket_amended`,
`ticket_parked`.

Developer lifecycle: `launch_planned`, `launch_settled`, `artifact_frozen`,
`artifact_blocked`, `freeze_failed`, `submission_rejected`, `developer_closed`.

Checks: `checks_started`, `check_planned`, `check_recorded`.

Review: `review_planned`, `review_recorded`, `reviewer_closed`.

Integration: `integration_planned`, `integration_settled`.

Controls and recovery: `control_changed`, `ticket_resumed`, `ticket_reset`,
`cancellation_requested`, `cancellation_finalized`.

Observation: `execution_observed`.

PM: `pm_proposal_recorded`, `pm_launch_planned`, `pm_launch_settled`.

Two deliberate differences from the preserved kernel vocabulary, both traceable to R4:

- **`submission_rejected` is added.** The row "any open submission phase; malformed
  result" requires a durable rejected submission that charges one validation action. The
  preserved kernel has no event for it, so that row could not be reduced.
- **`ticket_resumed` is retained as a shared name.** It is the one name already in the
  legacy vocabulary. Under versioned records this is not a collision: a v1
  `ticket_resumed` and a v2 `ticket_resumed` are distinct records with distinct payload
  contracts, and nothing has to disambiguate them by name alone.

Attempt terminal dispositions are deliberately **not** separate event types here. R4 sets
a disposition once on an attempt as part of the transition that terminates it, so a
separate event would create two carriers for one fact. If FR-08B's reduction shows this
is wrong, that is its call to make.

## What this design does not decide

Payload key sets per event type, the event-to-projection correspondence for each type,
and whether any transition needs an ordered multi-event group all belong to FR-08B. The
mechanism admits a vocabulary; it does not define the semantics of its members.

## Acceptance for the implementing subcommit

- Version 1 events validate exactly as today, proven against unchanged existing fixtures.
- Version 2 events validate against the seed vocabulary; unknown names in either version
  reject.
- A bundle mixing event versions rejects with a distinct reason.
- An unsupported event version fails closed.
- Existing v1 and v2 bundle histories continue to validate on reopen, replay and backup
  validation.
- No legacy accepted type is removed, renamed or re-pointed.

## Limits

This note changes no runtime and enables no execution. It does not establish FR-08B
progress, does not unblock the FR-08A Gateway wiring on its own, and claims no lifecycle
behavior. The plan-binding correction's subcommit 4 remains additionally bound by its
recorded structural-provenance requirement.
