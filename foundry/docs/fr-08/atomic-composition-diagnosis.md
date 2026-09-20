# FR-08A atomic-composition handoff diagnosis

Date: 2026-09-20

Reviewer: fresh independent Astra-high, read-only

Inspected revision: `d0059b03757a73085f430895304244afaec79ce2`

Verdict: **CONTRADICTION — bounded prerequisite correction required**

## Finding

The accepted interface cannot atomically compose the protected and domain changes
required by FR-08B. `Gateway.transact/4` supplies no protected operations;
`Gateway.protected_command/4` executes exactly one `ProtectedPrimitives` operation in its
own transaction; and the legacy combined route is deliberately retired once root
authority exists. The existing claim settlement can atomically settle protected claim,
receipt, effect, reservation and lease facts, but cannot include the role's domain
transition or an explicit once-per-non-start infrastructure settlement fact.

This directly conflicts with the workflow contract's atomic bundle and R4a obligations.
Separate successful calls would expose crash states in which protected settlement and
domain ownership disagree, so FR-08B correctly stopped before implementation.

## Required bounded correction

Add a versioned bundle route through the existing authoritative Gateway and one outer
database transaction. The Gateway must authenticate and hash the complete semantic
envelope, resolve global command identity before current-revision checks, verify one
complete prestate read set, execute only fixed typed non-committing protected operations,
validate the versioned domain proposal, and commit protected history and domain
events/projections/intents together.

Ordered protected operations need typed persistence and outcomes. Old v1 command rows
must decode as singleton operation histories without changing their bytes, IDs or
results; unsupported or partial migration fails closed. Candidate reducers remain
outside protected authority, and the bundle accepts no callbacks, SQL, arbitrary root
updates or generic JSON traversal.

R4a additionally needs an immutable protected settlement fact identifying role, work
owner, infrastructure generation, predecessor effect, failure class and infrastructure
attempt ordinal. It is derived and incremented once from an accepted attributable
receipt and committed with settlement and the domain transition.

FR-08A owns this composition protocol, persistence/replay support and protected fact.
FR-08B continues to own role-specific transitions, pause/drain/cancel and generation
dispositions, plus migration of every command ingress.

## Acceptance focus

- Developer, reviewer and PM proved non-start bundles survive reopen with one owner, one
  ordinal, settled reservation and no redispatch.
- Failure at every protected/domain write boundary leaves no partial accepted bundle;
  a lost reply after commit returns the same complete result after restart.
- Duplicate and conflicting receipts cannot refund or increment twice; unknown starts
  retain holds and are not blindly retried.
- Ledger admission, reserve-and-intent, supported transfers, recursive close/reset and
  their domain effects conserve balances atomically across generations.
- Missing or stale transitive reads, absence races, reordered or unknown operations,
  forged facts/results and malformed carriers reject.
- Live/replay, reopen and backup equality cover migrated v1 and new versioned history.

## Limitations

This was a source and contract diagnosis. It made no changes and ran no runtime tests.
The historical FR-08A review remains evidence for its exact immutable candidate, but it
did not review this newly required composition surface. The correction therefore needs
a fresh Astra-high authority, persistence and replay review before integration.
