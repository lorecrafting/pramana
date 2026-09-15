# FR-06 R4a correction response — version 3

2026-09-12. This responds only to R4a in
[independent review v2](../FR-06-DESIGN-REVIEW-V2.md). **Correction proposed; focused
independent verification pending.** FR-07 remains blocked on that verification and FR-03.
No production implementation, test, runtime probe or architecture redesign occurred.

## Input boundary

Before editing, the v2 manifest SHA-256 was
`42817763eda93bacaa0598eda3c63cb957bce20306cfae73857f5d2c3fef075b`.
Eleven unaffected inputs matched their recorded hashes. Only `REPAIR-PLAN.md` and
`docs/PLAN.md` differed: their current hashes were respectively
`2a0e464baa081e79aca382f05c4532eb58a48ecaf642a86062ce5d450ae4c8b2` and
`a6e500f3f065c38f0d7f1640361e37c95bd84ad020271ff1ccb27072535c1b84`.
The independent review records that it verified all 13 v2 inputs first and then changed
only its status passages in those files. Inspection found precisely those documented
review-status additions. No unexplained input drift was found.

Both independent reviews and [response v2](review-response-v2.md) remain byte-unchanged.
The refreshed manifest identifies the new active contract, plan passages, this response
and verification record while retaining the historical evidence inputs.

## R4a disposition

R4a is accepted. The review's trace was valid: R1 could prove a reviewer launch never
started and R5 could release its reservation while R4 left the ticket in `reviewing` with
no legal successor. The revised [R4a contract](../WORKFLOW-CONTRACT.md#r4a)
adds one shared classification and role-specific transitions.

The three launch outcomes are now disjoint:

- Pre-intent capacity, dependency, resource, profile or eligibility denial creates no
  execution, claim or reservation, stays in the scheduling phase and does not count as
  an infrastructure failure.
- An attributable, quiescence-backed `non_started` receipt closes the execution, releases
  its start reservation once, increments one durable infrastructure ordinal and applies
  the role-specific domain transition atomically.
- An unknown possible start retains its hold, slot and conflicting leases and cannot be
  replaced until R1 reconciliation establishes a terminal outcome.

Developer non-start retains the same nonterminal attempt and immutable lineage. The ticket
returns to `queued` with `resume_phase: developing`; safe launch resources are released,
and a released checkout lease must be reacquired and revalidated before retry. At the
finite infrastructure limit it blocks while remaining resumable. Only lack of protected
developer allocation makes that attempt/ticket exhausted.

Reviewer non-start closes only the reviewer execution. The same attempt, frozen candidate,
checks and reviewer ownership return to `awaiting_review`; no developer retry, correction
or approval is inferred. At the infrastructure limit it blocks with the candidate intact.
PM keeps its objective/spec-planning owner and admits no ticket. Check, freeze/import,
build, integration and activation workers preserve their existing domain inputs/phases
and use their phase-specific infrastructure block/retry outcome.

A protected finite `launch_non_start_limit` per role/work owner bounds retries independently
of process-start units. A proved non-start still refunds the R5 start reservation because
no process started; its durable infrastructure ordinal prevents that refund from enabling
an endless failure loop. New effects reference the settled R1 predecessor and require
issuer/channel quiescence plus one-time R5 settlement. Duplicate and late receipts cannot
release or increment twice. Restart after settlement and before redispatch reconstructs
one owner, one ordinal, no live execution and no replay of the old effect.

Cancel never retries. Pause retains the recovery phase without issuing. Drain blocks
developer and PM replacement launches while allowing reviewer, mandatory-check and
already-admitted finalization retries under the existing rule. A generation change cannot
turn an old refund into new allowance; retry reserves from the current permitted generation.

## Routing and preserved decisions

Acceptance traces were added only to FR-08, FR-10, FR-11 and FR-12:

- FR-08 owns deterministic role transitions and restart reconstruction.
- FR-10 owns predecessor/quiescence, unknown starts, atomic effect/settlement and
  duplicate/late receipts.
- FR-11 owns developer-attempt retention, reviewer candidate/role preservation, finite
  retry/block/exhaustion outcomes and absence of synthetic crash/timeout/result events.
- FR-12 owns pre-intent waiting, redispatch eligibility, controls and resource
  reacquisition/custody.

No dependency edge changed. Existing ticket acceptance paragraphs and every F01–F24
obligation remain. The accepted R1 claim ordering, R2 authentication boundary, R3
autonomous-kernel boundary and R5 conservation equations are unchanged; R4a uses their
existing predecessor, quiescence and reservation semantics. No contradiction requiring
those decisions to reopen was found.

## Evidence and limitations

The correction supplies a normative state transition; there is no proposed kernel whose
runtime behavior could answer that design question. No new probe was run. Verification
checks document preservation, dependency reachability, acceptance retention, links,
whitespace and refreshed hashes. These checks do not establish implementation behavior.

FR-08/10/11/12 must still implement and exercise the traces with deterministic fake
backends. Actual OMP non-start observability remains FR-09, OS/effect enforcement remains
FR-15a, and full lifecycle recovery remains FR-22. A backend that cannot prove non-start
must produce `unknown`; it cannot take the new retry transition.

An independent reviewer should verify the refreshed manifest, inspect only the revised
R4a passages and routed acceptance traces, and record whether this closes the residual
design gap. This response does not certify its own correction.
