# Durable event vocabulary extension — design, revision 2

Date: 2026-09-20

Status: **design note; no implementation, no acceptance, no accepted vocabulary**

Author: Claude Opus 5. Revision 1 was reviewed and returned **BLOCKER**; this revision
replaces its mechanism outright. The prior mechanism is described below under "what
revision 1 got wrong" rather than deleted, because the mistake is instructive.

This is subcommit 0 of the [FR-08A plan-binding correction](plan-binding-specification.md).

## Exact base

`main` at `4a2f7748ba80b73b1aa9e3fef25c5e0a5bdd2e70`.

## What revision 1 got wrong

Revision 1 proposed versioning the durable event record: keep `schema_version` 1 for the
legacy vocabulary, admit 2 for the lifecycle vocabulary, and dispatch validation on the
record's declared version.

That mechanism is unimplementable without a relational migration the note never mentioned.
Independent review established, and this author re-verified:

- `database.ex:248` declares `schema_version INTEGER NOT NULL CHECK (schema_version = 1)`
  on the `events` table, which is `STRICT`. SQLite cannot alter a CHECK in place; changing
  it requires a full table rebuild.
- `gateway.ex:1481` writes `VALUES (?, ?, 1, ?, ?, ?, ?)` — the version is a literal in the
  SQL text, not bound from the event.
- The review further identified that relaxing the CHECK without fixing the literal would
  write column `1` beside a blob declaring `2`, committing successfully and then failing
  `:relational_binding_mismatch` on the next read, because `authority.ex` cross-checks the
  column against the blob. That is a new way to manufacture exactly the partial-version
  state this repair exists to eliminate.

The underlying error was reasoning from `RecordCodec` without reading the table beneath it.

## The correction: the constrained column was never the one that needed to change

`schema_version` is CHECK-constrained. **`event_type` is not.**

```
event_type TEXT NOT NULL,
```

The event-type vocabulary is enforced in exactly one place in the entire system —
`record_codec.ex:81`, `map["type"] in @event_types` — and nowhere in the relational schema.
The database will store any event type string today.

So extending the vocabulary requires **no schema change, no migration, no table rebuild and
no version dispatch**. It requires adding names to one closed list in one module.

## Mechanism: one flat vocabulary of globally unique names

Extend `@event_types` with the lifecycle vocabulary. Do not introduce record versioning.

The two vocabularies must be **fully disjoint**, so an event type name alone identifies
exactly one event contract. The legacy and lifecycle sets currently collide on one name,
`ticket_resumed`. The lifecycle event takes a distinct name instead. Which name is FR-08B's
call; this note requires only that it not reuse a legacy one.

Why a flat disjoint namespace is better here than versioning, beyond being implementable:

- **Nothing can go out of sync.** A version column can disagree with its payload; a name
  cannot disagree with itself. The failure mode review found in revision 1 has no analogue.
- **Existing read paths need no change.** `gateway.ex:1917`'s `query_recent_events/2`
  selects `event_type` without `schema_version`. Under revision 1 that surface was
  ambiguous and needed widening. Under disjoint names it is already correct.
- **Later extension stays cheap.** Adding a name is additive. This matters for the
  ownership split below: FR-08B can add lifecycle events later without a "v3" migration.
- **Redefinition is forbidden rather than versioned.** A name's contract never changes; a
  changed contract takes a new name. This is the ordinary event-sourcing discipline and it
  is what makes replay of old records safe indefinitely.

The cost is that the namespace is permanently global: a name, once persisted, is spent.
That is an acceptable and explicit trade.

## Ownership split, stated honestly this time

Revision 1 claimed to own only "the mechanism" while shipping a concrete vocabulary, and
review correctly identified that as a content decision wearing mechanism's clothes.

Under a flat additive namespace the split is real rather than rhetorical: adding a name
later costs nothing, so seeding the list does not freeze FR-08B's options the way shipping
a numbered schema version would have. FR-08B may add, and must not redefine or reuse.

That said, **the names below are a proposal, and FR-08B owns them.** This note does not
require that subcommit 0 land the full seed. A defensible alternative is to land the
mechanism with only the event types the FR-08A binding actually needs, and let FR-08B add
the rest as its reduction is written. The implementing subcommit should choose explicitly
and record why.

## Seed vocabulary proposed from R4

Derived from the [R4 transition table](../WORKFLOW-CONTRACT.md#r4), not from the preserved
kernel work in progress, which is unreviewed and mid-correction.

Admission: `objective_created`, `ticket_admitted`, `ticket_amended`, `ticket_parked`.
Developer: `launch_planned`, `launch_settled`, `artifact_frozen`, `artifact_blocked`,
`freeze_failed`, `submission_rejected`, `developer_closed`.
Checks: `checks_started`, `check_planned`, `check_recorded`.
Review: `review_planned`, `review_recorded`, `reviewer_closed`.
Integration: `integration_planned`, `integration_settled`.
Controls and recovery: `control_changed`, `ticket_reset`, `cancellation_requested`,
`cancellation_finalized`, plus a lifecycle resume event under a name not already spent.
Observation: `execution_observed`.
PM: `pm_proposal_recorded`, `pm_launch_planned`, `pm_launch_settled`.

Two differences from the preserved kernel vocabulary, both traceable to R4 and both
sustained by review:

- **`submission_rejected` is added.** R4's "any open submission phase; malformed result"
  row requires a durable rejected submission charging one validation action. The preserved
  kernel has no event for it, so that row could not be reduced.
- **Attempt terminal dispositions get no separate event type.** R4 sets a disposition once,
  in the same row that moves the attempt to terminal. Review checked all nine dispositions
  against their rows and found no counterexample.

## Corrected framing of the original finding

Revision 1 concluded the durable store "still speaks the pre-repair legacy lifecycle."
Review showed that overreaches, and this revision withdraws it.

The 8-of-9 name correspondence between `@event_types` and `@command_types` is real, but
nothing cross-checks a command's type against an event's type — the correspondence is a
naming coincidence between two independently maintained closed lists. `@command_types`
also contains `reset`, `propose`, `submit_artifact` and `submit_review`, which have zero
uses anywhere in `lib/` outside the list literal. So the accurate statement is narrower:
**the codec carries two stale closed lists, one of which already contains dead R4-flavoured
names.** The dead names are routed to [FR-23](../REPAIR-PLAN.md), not removed here.

## Acceptance for the implementing subcommit

Revision 1's criteria were all at `RecordCodec` level and could have been satisfied in full
while leaving the actual prerequisite untouched. These require the real path:

- A bundle carrying a lifecycle event **commits through the real `Gateway` path** and is
  read back with its event type intact. Codec-level validation alone is insufficient
  evidence.
- That committed bundle **replays to identical state**, and survives **reopen and verified
  backup validation**, since those are the paths the diagnosis requires to revalidate.
- The legacy vocabulary continues to validate and replay byte-identically; no legacy name is
  removed, renamed or re-pointed, proven against unchanged existing fixtures.
- An unknown event type still rejects, with the same reason as today.
- No name appears in both vocabularies, enforced by an assertion over the two lists rather
  than by inspection.
- No relational schema change is introduced. If implementation discovers one is
  unavoidable, that is a design failure and returns here rather than proceeding.
- `transition_plan_test.exs`'s pinned prerequisite case, which currently asserts
  `{:error, :invalid_event}`, becomes the end-to-end binding assertion.

## Limits

This note changes no runtime and enables no execution. It does not establish FR-08B
progress and does not by itself unblock the FR-08A Gateway wiring, which remains
additionally bound by its recorded structural-provenance requirement. It makes no claim
about FR-08B's reduction logic or payload semantics, which do not exist yet.
