# The mechanism / lifecycle-definition seam

Date: 2026-09-20

Status: **analysis, not a commitment.** No ticket, no scheduled work. Recorded so the
reasoning is not re-derived when a second workflow arrives.

Foundry today runs exactly one workflow: the software-development lifecycle R4 defines.
The question this note answers is what it would take to run others — a different domain
would want different phases, different roles and a different transition table — and when
that work should happen.

## What is coupled today, and how badly

R4 is a markdown table in [the contract](../WORKFLOW-CONTRACT.md). It is implemented twice,
by hand, on purpose:

1. `Workflow.Kernel.do_transition/4` — one clause per event type, guards written from the
   rows.
2. `test/support/kernel_walk.ex`'s `candidates/1` — "every event R4 makes conceivable from
   this state", written to be independent of the kernel so it can find rows the kernel
   cannot reach.

The independence of the second from the first is the only mechanism connecting the
implementation to the contract. It is also fragile in a specific way: two hand-maintained
encodings of one table drift **toward** each other under pressure, because whoever is
tuning them wants the suite green. That is not hypothetical — the subcommit 1 review
confirmed it on `ticket_parked`, where the prober proposed a resume target derived from the
ticket's current phase and the kernel's guard was widened to accept it, the two agreeing on
a state R4 forbids.

## What is already data, and what is not

Data: the closed event-type list, `Event.@payloads`' exact key sets, `State`'s phase,
disposition, lifecycle, result, status, verdict and role vocabularies, and
`TransitionPlan.@slots` mapping a slot to `{event, field, output_kind}`.

Not data: the guards, which are the interesting half. `"integrating; successful ref receipt
and prior role/check workers closed"` is three predicates over evidence, hand-written as
`require_execution`, `require_workers_closed` and `require_receipt_for_integration`.

## Where the seam actually falls

Varies by domain: the phase vocabulary, the role vocabulary, the transition table, and what
counts as evidence — a ref receipt means nothing outside software integration.

Does not vary: event sourcing with revision and sequence ordering and duplicate-identity
idempotence; the protected-authority boundary of R2/R3, which decides who may *derive* a
fact rather than merely assert one; claims, receipts, reservations and the R5 ledger; and
the *structure* of R4a non-start recovery — "an issued launch with attributable proof that
nothing started closes its execution, refunds the start unit and consumes a role-scoped
allowance" is domain-independent. Only the role list is domain-specific, which is why the
per-role ordinal correction split `@ticket_roles` from `@objective_roles` rather than
hard-coding five counters.

So the split is **mechanism** (durable, protected, generic) against **lifecycle
definition** (per-domain data). Foundry is already partly on the right side of that line,
by construction rather than by intent.

## Why not now

The repair's goal is a supervised dogfood alpha, and the remaining path is FR-08B, then
FR-10/11/12, then Batch D. A definition layer is a new subsystem, not a repair, and the
plan's own rules forbid coding against an interface no second consumer has frozen.

The stronger argument is evidence. Independent review found nineteen defects in the
hand-written implementation of this one contract, including terminal states reachable
without their lifecycle and a coverage claim that measurement showed to be false. A
definition language extracted now would be extracted from a specification we cannot yet
demonstrate we implement correctly, and it would harden today's misreadings into syntax.
Extraction is cheap with two instances and expensive with one plus imagination.

A naive state-machine DSL would also not survive contact with R4. It handles
`from-phase + input -> to-phase` and cannot express write-once sealed results, "unknown
stream completeness blocks reconciliation; it is not a failed attempt", "exit notifications
cannot overwrite this", or "a check failure uses its controller exit/receipt reason_code,
not an agent's assertion". Those are predicates over evidence *provenance*, so the
definition language would need a vocabulary of facts and of who may derive them — which is
R2/R3, the hardest part of the contract to get right.

## The one step worth taking inside FR-08B

Make R4's rows executable data and drive `candidates/1` from that table instead of from a
second hand-written encoding.

This is justified on today's merits alone, independent of any future workflow. It is what
the repair plan already asks for — "prefer executable coverage assertions over prose: a
test that enumerates the contract's rows and fails when one has no destination is durable,
while a reviewer's row-by-row read is not" — and it is the direct structural fix for the
circularity finding, because two encodings that cannot drift cannot be tuned against each
other. That it would also be the natural seed of a workflow definition format is a
consequence, not the motivation.

Scope it to FR-08B's remaining subcommits. Do not open a ticket for the definition layer
itself; open it when a second workflow exists and the variation surface can be observed
rather than guessed.
