# FR-08B kernel event vocabulary — enumeration

Date: 2026-09-20

Status: **specification; first deliverable of subcommit 1. No implementation, no acceptance.**

Author: Claude Opus 5.

The [kernel correction design](fr08b-kernel-correction-design.md) makes this enumeration
subcommit 1's first deliverable rather than a later discovery, and names this document's
owner as the party that decides the vocabulary. It starts from the preserved work in
progress at `059546b` (`kernel/event.ex`, 27 types), reconciles it against
[R4 and R4a](../WORKFLOW-CONTRACT.md#r4) row by row, and pairs each name with a
destination slot where a protected fact must bind.

Base `main` at `a319b39`, with FR-08A complete.

## What the durable codec accepts today

`RecordCodec` accepts fourteen lifecycle event types, seeded by FR-08A subcommit 0 as
"exactly the ten event types the transition-plan destination slots require" and extended
to fourteen by the R4a coverage correction. Every one of the fourteen has a destination
slot in `TransitionPlan.@slots`. That is not a coincidence: subcommit 0 deliberately
justified each name by a concrete binding and left the remainder to this ticket.

The consequence is that **the durable vocabulary today contains only events that carry a
protected fact.** Every event expressing sealed domain evidence — a frozen candidate, a
check receipt, a review verdict, a closed execution — has no name yet. That is the gap
this enumeration closes.

## The three families

Reconciling against R4 produces three families with genuinely different rules, and the
preserved work in progress did not separate them.

**Family 1, admission authority and R4a settlement.** A protected fact derived inside the
transaction binds into a declared slot. All fourteen exist.

**Family 2, admission and steering.** Durable operator or PM decisions. They carry no
protected derivation; their allocation and reservation effects live in the R5 ledger and
the protected tables, not in the event payload.

**Family 3, sealed domain evidence.** Facts established by sealed streams, receipts and
verified closure. They carry no protected derivation either, and the kernel must never
infer one from them.

## Family 1 — admission authority and R4a settlement (14, all existing)

| Event | Justifying R4/R4a row or entity state | Destination slot |
|---|---|---|
| `launch_planned` | queued; dependencies/resources/profile/reservation eligible | `launch_planned.authority` |
| `launch_settled` | R4a domain owner: developer, active attempt before any valid result | `launch_settled.settlement` |
| `check_planned` | candidate_frozen; developer closed, check capacity eligible | `check_planned.authority` |
| `check_settled` | R4a domain owner: check worker | `check_settled.settlement` |
| `build_planned` | R5 `starts.build` is a distinct dimension; R4a build worker | `build_planned.authority` |
| `build_settled` | R4a domain owner: build worker | `build_settled.settlement` |
| `review_planned` | awaiting_review; check receipts valid and reviewer capacity available | `review_planned.authority` |
| `review_settled` | R4a domain owner: reviewer, frozen candidate awaiting review | `review_settled.settlement` |
| `integration_planned` | ready_to_integrate; current base/evidence/policy valid | `integration_planned.authority` |
| `integration_settled` | R4a domain owner: integration worker | `integration_settled.settlement` |
| `pm_launch_planned` | Objective without admitted spec; broad steering | `pm_launch_planned.authority` |
| `pm_launch_settled` | R4a domain owner: PM planning execution | `pm_launch_settled.settlement` |
| `control_changed` | R4 Control entity; R4a control crossing after non-start | `control_changed.control` |
| `ticket_reset` | exhausted; authenticated reset grants eligible units and explicitly resumes | `ticket_reset.generation` — **unbindable, see prerequisites** |

### Correction, 2026-09-20: every settlement names its execution

`check_settled`, `build_settled`, `review_settled` and `integration_settled` originally
carried no `execution_id`, while `launch_settled` did. That asymmetry had no justification
and made R4a unsatisfiable: a proved non-start must "close the execution", and a settlement
that cannot name one leaves an execution open that no later event can close. Because
`reviewer_closed` requires the `reviewing` phase, a settled reviewer execution was
unclosable **forever**, so R4's "prior role/check workers closed" could never hold and the
integration row was unreachable.

Found by the reachability walk, not by re-reading this table. All five settlements now
carry `execution_id`.

## Family 2 — admission and steering (8 new)

| Event | Justifying R4 row | Payload key set | Slot |
|---|---|---|---|
| `objective_created` | Objective without admitted spec; broad steering | `objective_id planning_owner_id` | none |
| `ticket_admitted` | draft; specific spec or valid PM create | `ticket_id objective_id spec_revision_id spec phase reason` | none |
| `ticket_amended` | queued/blocked; PM amend/park — new future spec revision | `ticket_id spec_revision_id spec` | none |
| `ticket_parked` | queued/blocked; PM amend/park — explicit blocked state | `ticket_id reason resume_phase` | none |
| `ticket_resumed` | blocked; explicit resume or recorded dependency/resource recovery | `ticket_id phase` | none |
| `cancellation_requested` | nonterminal ticket; cancel requested | `ticket_id` | none |
| `cancellation_finalized` | cancel_requested; every owned session and non-session claim terminal | `ticket_id disposition` | none |
| `pm_proposal_recorded` | PM proposal is evidence, not authority | `proposal_id objective_id operation` | none |

`ticket_admitted` carries `phase` and `reason` because the row admits to **queued or
blocked with reason**, and both are the admitted outcome rather than a later transition.
It does not carry an allocation: R4's row says common admission validates full
assignment/policy/budget allocation, and that validation's authoritative record is the R5
ledger, not a number copied into an event.

## Family 3 — sealed domain evidence (14 new)

| Event | Justifying R4 row | Payload key set | Slot |
|---|---|---|---|
| `artifact_frozen` | developing; success artifact validates and freezes | `ticket_id attempt_id candidate_id observation_id sealed_generation` | none |
| `artifact_blocked` | developing; valid blocked/partial result | `ticket_id attempt_id observation_id result reason` | none |
| `freeze_failed` | developing; freeze/import infrastructure failure before valid candidate | `ticket_id attempt_id disposition reason` | none |
| `submission_rejected` | any open submission phase; malformed result | `ticket_id attempt_id observation_id reason` | none |
| `execution_observed` | candidate_frozen; developer exit/timeout/abnormal exit — cleanup observation only | `ticket_id attempt_id execution_id observation lifecycle` | none |
| `stream_sealed` | On exit, the broker seals that execution's input stream with its last accepted sequence | `ticket_id attempt_id execution_id last_accepted_sequence` | none |
| `developer_closed` | developing; kernel requests developer close through broker immediately | `ticket_id attempt_id execution_id` | none |
| `worker_closed` | queue fresh developer after all check workers close; prior role/check workers closed | `ticket_id attempt_id execution_id` | none |
| `checks_started` | candidate_frozen; developer closed, check capacity eligible | `ticket_id attempt_id policy_empty` | none |
| `check_recorded` | checking; receipts passed / assertion fails / tool failure or timeout | `ticket_id attempt_id check_id status reason_code` | none |
| `review_recorded` | reviewing; approved exact-candidate / correction / rejected verdict | `ticket_id attempt_id candidate_id verdict` | none |
| `reviewer_closed` | reviewing; close/seal reviewer, then after verified close ready_to_integrate | `ticket_id attempt_id execution_id` | none |
| `integration_recorded` | integrating; successful ref receipt / proved no ref change | `ticket_id attempt_id execution_id outcome ref_receipt_id` | none |
| `attempt_settled` | R4 entity state: attempt disposition is set once on terminal | `ticket_id attempt_id disposition reason_code settlement` | **`attempt_settled.settlement` — does not exist, see prerequisites** |

### Five decisions inside family 3, each answering a named blocker

**`stream_sealed` is its own event, not a field of an observation.** B2's specific defect
was that `reviewer_closed` "trusts an ordinary observation string." Sealing is a once-only
fact carrying the last accepted sequence, and R4 makes it load-bearing: the broker
"processes all inbox artifacts through that sequence before deciding no valid result
exists," and "unknown stream completeness blocks reconciliation; it is not a failed
attempt." A field inside a repeatable observation cannot carry a once-only fact, and the
preserved work in progress put `stream_status` inside `execution_observed`, which is why
its approval path accepted an unsealed stream.

**`submission_rejected` is new and was absent from the preserved work in progress.** R4's
malformed-result row requires a durable rejected submission that charges one validation
action, permits further submission only while the stream is open and budget remains, and
exhausts the ticket when the budget runs out. Without the event there is no durable record
to charge against, so the row is unimplementable.

**`integration_recorded` is separate from `integration_settled`.** They are different
facts: `integration_settled` is the R4a **non-start** settlement for the integration
worker, while this is the actual ref receipt or the proved no-ref-change outcome. The
preserved work in progress had only `integration_settled` and would have had to express a
successful integration through the non-start vocabulary.

**One `attempt_settled` rather than nine terminalizing events.** R4 states the attempt
disposition is "set once on terminal" over a closed nine-value set. Concentrating it in one
event makes set-once enforceable in one guard instead of nine, and gives the R5 one-time
terminal settlement a single destination instead of nine. Evidence events therefore never
terminalize: a failing `check_recorded` records the failed receipt, and the
`attempt_settled(needs_correction)` in the same bundle terminalizes. That separation is
also what B2 asks for, since it stops a verdict string from being both the evidence and
the disposition.

**`worker_closed` exists because the first four decisions missed it.** The enumeration
named a closure event for the developer and one for the reviewer and none for the check,
build or integration workers, even though R4 requires their closure in three separate rows:
"queue fresh developer after all check workers close", "bounded new check-run reservation
after cleanup", and "successful ref receipt and prior role/check workers closed". The gap
was not found by re-reading the table. It was found by implementing
`require_workers_closed/1`, which made R4's integration row unreachable — the same failure
mode as the codec's missing `launch_authority_v1` producer, one level up, and found the
same way: by asking whether a mechanism can express a contract row rather than whether it
is internally consistent.

The rule it generalises is recorded with it. R4 states that an execution lifecycle of
`closed` "requires verified process/session termination or proved non-start", so
`execution_observed` may move an execution through every lifecycle **except** `closed`.
Closure has its own guarded events. That is B2's finding — `reviewer_closed` trusted an
ordinary observation string — stated as a property of the vocabulary rather than as a fix
to one path.

The kernel *records* worker closure rather than verifying it, and says so: verified
termination is a protected reconciliation fact owned by FR-10, and the link from a check
execution to its receipt that would let the kernel demand a recorded status first belongs
with subcommit 4's check/build/integration workers.

## Events deliberately not created

**Pre-intent denial gets no event.** R4a is explicit that capacity, dependency, resource,
profile or eligibility denial before an intent "creates no execution, claim or
reservation," the work item stays in its scheduling phase, and ordinary waiting does not
increment an infrastructure-failure counter. The repair plan's R4a acceptance trace still
requires table-testing it, so it must be an explicit `decide/3` **rejection** with a
reason, not an event. An event would be a durable record of a transition that R4a says
did not happen.

**Terminal-state command rejection gets no event.** R4's integrated/rejected/cancelled row
rejects the transition and preserves terminal facts; a rejection that mutates nothing is
returned, not recorded.

**Ticket and attempt phase get no event of their own.** Phase is derived by the reducer
from the events above under their source-state guards. This is the direct answer to B1: an
event that carried a phase would be a snapshot to install, which is the defect. The one
exception is `ticket_admitted`, whose `phase` is the admission outcome the row itself
names, and `ticket_resumed`, whose `phase` is the stored `resume_phase` being returned to.

## Prerequisites this enumeration establishes

Two destination slots the vocabulary needs do not exist or cannot bind. Both are gaps in
the FR-08A codec rather than in the kernel, and both are the **same class** as the two the
broad design review found — a name that is declarable but not derivable — with one
difference: these two are already recorded as such in the codec's own test, at
`transition_plan_test.exs:637`, which states that "terminal_settlement_v1 and reset_fact_v1
remain declarable but unproducible." They were known and left, correctly, until a ticket
needed them. FR-08B is that ticket.

1. **`reset_fact_v1` has no producer.** `ticket_reset.generation` is a declared slot whose
   output kind is absent from `@producers`, so `derive_output/2` returns
   `:unsupported_output_kind` and the slot fails closed. R4's reset row — exhausted,
   authenticated reset grants eligible units and explicitly resumes — is therefore
   unreachable through the binding, exactly as R4's ordinary admission row was before
   `launch_authority_v1` gained `{"issue_claim", "effect"}`. The `reset_generation`
   protected operation already exists in `@operation_types`; what is missing is the
   specification of which of its result facts is authoritative.
2. **`terminal_settlement_v1` has no producer and no slot.** R5 requires every reservation
   to reach exactly one terminal settlement, and `attempt_settled` is where that fact must
   bind for the nine terminal dispositions. The output kind is declared and validated in
   `valid_output?/2` but nothing produces it and no slot receives it.

Both are **required before subcommit 3**, not before subcommit 2: subcommit 2 covers the
developer role, whose R4a non-start settlement binds through the existing
`launch_settled.settlement`. The first terminal disposition and the first reset appear as
soon as the developer role's terminal rows are implemented, so the margin is one subcommit,
not several.

This is the third time a coverage gap in that codec has been found by asking whether it
can express a contract row, and the first time it has been found before the dependent work
started rather than during it. The maintained coverage assertions added after the second
occasion enumerate settlement slots for the six R4a domain owners; they do not yet assert
that every declared slot has a producer. Adding that assertion is part of prerequisite 1,
so the next missing producer fails a test rather than waiting for a reviewer.

### Correction, 2026-09-20: two payloads the subcommit 1 review forced

`checks_started` gained `policy_empty`. R4's row — "checks with explicit policy-empty set
follow same guarded transition" — was unreachable without it, because an attempt that has
not planned its checks yet and one whose policy set is genuinely empty are the same state.
Emptiness is protected policy, so it is carried rather than inferred from an empty map.

`integration_recorded` gained a third `outcome` value, `infrastructure_failed`, for the
second half of R4's row "Same phase with bounded integration-effect retry after old issuer
termination; **or blocked(integration_failure)**". It is carried on the row's own event the
way `freeze_failed` carries its blocked alternative, rather than borrowing `ticket_parked`,
whose row is the PM park and whose sources R4 limits to queued and blocked.

Both were found the same way as `worker_closed` and the settlement `execution_id`
asymmetry: by executing the rows, not by re-reading the table. The count of new types is
unchanged at 22; these are payload corrections within it.

### Recorded prerequisite: a name collision with the legacy codec vocabulary

`ticket_resumed` is already a member of `RecordCodec.@legacy_event_types`, and the codec
raises a `CompileError` when the legacy and lifecycle vocabularies share a name — by
design: "a reused name would silently give one stored type two contracts, which is the
single failure this design must prevent." Legacy members are explicitly immutable, so the
resolution belongs on the kernel side. It is the only collision among the 22 and it blocks
subcommit 2's codec extension.

Still unproduced, and now with one addition: `terminal_settlement_v1` has neither a
producer nor a slot; `reset_fact_v1` has a slot and no producer; and the execution result
value `invalid` has no event that produces it, since R4 attributes it to "Git/scope
validation failure is invalid submission", a distinction `freeze_failed` does not yet draw.
The other four result values are produced by `artifact_frozen`, `artifact_blocked` and the
sealed-no-candidate settlement.

## Reconciliation with the preserved work in progress

The preserved `kernel/event.ex` at `059546b` enumerated 27 types. This enumeration keeps
**all 27** and adds 9, for a total of 36. Nothing is renamed and nothing is dropped: every
preserved name maps to an R4 row, which is the evidence that the preserved work had read
the contract carefully even though its code does not compile.

The 9 additions fall into two groups.

- **Four already exist in the durable codec and were simply absent from the preserved
  file**, which predates the R4a coverage correction: `check_settled`, `review_settled`,
  `build_planned` and `build_settled`. Their absence is not an oversight by that author.
  At the time it was written the codec had no such slots, so `check_recorded` was the only
  place a check non-start could go, and it was carrying both the receipt and the
  settlement. The coverage correction split them, and this enumeration inherits the split.
- **Five are new here**: `stream_sealed`, `submission_rejected`, `integration_recorded`,
  `attempt_settled` and `worker_closed`, each for the reason given above. The last was
  added during implementation, not during enumeration; that is recorded rather than
  smoothed over, because it is evidence about how these gaps are actually found.

Counted against the durable codec rather than against the preserved file, the extension is
22 new types on top of the existing 14.

The preserved file's structural devices are adopted: a closed type list, an exact payload
key set per type, exact outer-envelope keys, and a `template?` mode that admits a
`%{"binding" => name}` marker in place of a value so an unresolved plan can be validated
with the same validator as a bound event. That last device is what lets the substitution
law — binding a planned projection must equal applying its concretely bound event to the
same prestate — be checked with one validator rather than two.

## What the reachability prober changed about this document

This enumeration was written to stop contract rows being unreachable, and it still missed
things that only became visible when the rows were executed. `worker_closed` was absent
entirely. Four of the five settlements could not name the execution they settle. Both were
found by walking the state machine rather than by reading R4 again.

That is the same lesson the FR-08A codec taught twice, and it is worth stating plainly:
**careful reading is not a mechanism.** An enumeration is a claim about coverage, and a
claim about coverage has to be executable before it is worth anything. The prober and its
`@known_unreached` ratchet are where that claim now lives; this document is its rationale,
not its evidence.

## What subcommit 1 still owes

This document is the vocabulary. The rest of subcommit 1 is the pure state and event
contract in code: `State.valid?/1` totality, source-state guards per event, durable
sequence ordering, duplicate identity idempotence, and no entity creation by projection.
No plan production, and no `decide/3` role coverage, which begin at subcommit 2.
