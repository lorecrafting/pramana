# FR-08B kernel correction — design

Date: 2026-09-20

Status: **design note; no implementation, no acceptance**

Author: Claude Opus 5.

> **Current status route (2026-09-20):** this document is preserved as the accepted design
> evidence for FR-08B, so its dated dependency sentences are **not** rewritten. Several are
> now out of date and a reviewer should not act on them:
>
> - "Subcommits 4 and 5, Gateway wiring and replay revalidation — **not written**" is
>   **superseded**. Both landed and were independently reviewed; `9f1115d`/`b9bfc85` and
>   `b5d19e9`/`e491e41`. **FR-08A is complete**, so the B4 section below is discharged.
> - The three codec coverage gaps it lists — a `launch_authority_v1` producer, a
>   `review_settled` slot and a check-worker settlement slot — are **all closed**, by
>   `71e558b` and `43ee08e`.
> - Two gaps of the same class remain open and are **not** in this document:
>   `terminal_settlement_v1` and `reset_fact_v1` have no producer. They are prerequisites
>   for subcommit 3, recorded in
>   [the event vocabulary enumeration](fr08b-event-vocabulary-enumeration.md).
> - The subcommit plan's item 1 is **implemented and frozen** at `be1e19c`; see
>   [its review briefing](fr08b-subcommit1-review-briefing.md). Items 2–5 are outstanding.
>
> Current ticket status lives only in [the repair plan](../REPAIR-PLAN.md).

Responds to the independent BLOCKER review of the first pure-kernel candidate
(`a8ecf36`, candidate `a00decc`, branch `repair/fr08b-pure-kernel`) and to the
[FR-08B acceptance paragraph](../REPAIR-PLAN.md). Governing lifecycle is
[R4 and R4a](../WORKFLOW-CONTRACT.md#r4).

## Exact base and dependency

Base `main` at `5d025bd`. This correction requires **three** things from FR-08A, not one:

- **Subcommit 0**, the lifecycle event vocabulary — integrated at `5d025bd`.
- **Subcommits 4 and 5**, Gateway wiring and replay revalidation — **not written**. Until
  they land, no bound proposal commits, so nothing here is reachable.
- **Codec coverage gaps** — a `launch_authority_v1` producer and the two missing R4a
  settlement slots, enumerated below.

Revision 1 named only subcommit 0 and was returned BLOCKER for that understatement.

## Disposition of the preserved work in progress

The previous implementer's uncommitted correction is preserved at `059546b`, with a
mechanical syntax repair at `88c905d` that still does not compile.

**It is not resumable by patching, and this correction will not try.** After repairing 49
keyword-spacing errors and two misplaced `rescue` clauses it still fails on semantic
errors that require reconstructing the author's intent. It is 1,168 lines in a compressed
one-line style with 26 lines over 200 characters, abandoned mid-rewrite.

It is valuable as a **design reference** and is consulted as one throughout: it shows the
intended closed event and plan vocabularies, the control crossings that answer B3, and the
acceptance of `expected_revisions` and removal of generic snapshots that answer B4. Those
intentions are adopted where they match R4; the code is rewritten.

## B4 is partly answered, and the remainder is undischarged FR-08A work

Revision 1 of this note claimed B4 "is already answered by the integrated binding."
Independent broad review returned **BLOCKER** on that claim and it is withdrawn. The
corrected position, verified against source at `5d025bd`:

**What the binding does answer.** For an output kind that has a producer, the kernel can
emit a closed plan with finite alternatives, never see the infrastructure ordinal, and
have Gateway substitute the authoritative fact. `nonstart_settlement_v1` and
`control_fact_v1` have producers, so the developer and PM non-start settlements are
expressible today.

**What it does not answer, and the design must not imply otherwise.**

1. **No Gateway wiring exists.** `grep -rn "TransitionPlan" lib` returns nothing outside
   the codec itself. `commit_accepted_atomic_bundle/6` still binds
   `proposal = envelope["proposal"]` and commits it unchanged. FR-08A subcommits 4
   (Gateway wiring) and 5 (replay and idempotency revalidation) do not exist as
   candidates. **Nothing this design describes can commit until they land**, so they are
   dependencies of this correction, not adjacent work.
2. **Admission authority cannot bind at all.** `launch_authority_v1` is the output kind
   for all five `.authority` slots — `launch_planned`, `check_planned`, `review_planned`,
   `integration_planned`, `pm_launch_planned` — and it has **no producer**. `derive_output/2`
   returns `:unsupported_output_kind`, and the codec's own test asserts that fail-closed
   behavior. R4's ordinary admission row is therefore unreachable through this binding,
   not merely unwired.
3. **Two of R4a's four domain-owner rows have no destination slot.** `@slots` defines
   settlement slots for `launch_settled`, `integration_settled` and `pm_launch_settled`
   only. There is **no `review_settled` and no check-worker settlement slot**, while R4a's
   reviewer row and its check/freeze/build/integration/activation row both require one,
   and the repair plan's R4a acceptance trace explicitly requires the reviewer
   non-start to return the same frozen candidate to `awaiting_review`.

Items 2 and 3 are gaps in the FR-08A codec, not in the kernel. They are recorded here
because this design cannot be implemented without them, and because the FR-08A reviews
that passed that codec examined its mechanism — authority, slot enforcement, fail-closed
derivation — rather than its coverage of R4a. **Required before FR-08B subcommit 2:** a
producer for `launch_authority_v1`, a `review_settled` settlement slot, and a check-worker
settlement slot, each with the same three-way authoritative binding the existing settlement
producer uses.

The kernel's output type still changes from events to plans; that decision survives the
review. What changes is the honesty of the dependency statement.

## Event vocabulary beyond subcommit 0

Subcommit 0 seeded exactly the ten event types the existing `@slots` require. This
design's own B2 section requires `developer_closed`, `checks_started` and a durable frozen
candidate fact, **none of which exist in the codec**. The preserved work in progress
enumerates 26 lifecycle types against the durable codec's 9, and the plan-binding
specification records that extending beyond subcommit 0 was left "blocked pending
agreement with the FR-08B kernel owner on the exact vocabulary."

**This document is that owner, and defers no longer.** The vocabulary extension is an
undischarged dependency that gates subcommit 2 onward. Its enumeration starts from the
preserved `kernel/event.ex` at `059546b`, reconciled against the R4 table row by row, with
each name justified by a row or entity state and each paired with a destination slot where
a protected fact must bind. That enumeration is the first deliverable of subcommit 1, not
a later discovery.

## Control and allocation: prestate reads versus protected discriminators

Review correctly identified this as a load-bearing question the previous revision dressed
as resolved. Only one protected discriminator exists —
`infrastructure_discriminator/3`, a single binary over a settled ordinal and a static
policy limit — while R4a requires the developer row to distinguish an infrastructure-limit
block from allocation-exhaustion terminal, and the PM row to distinguish
`pm_launch_infrastructure` from `pm_budget`. Two axes, one mechanism.

**The decision, made here:**

- **Control state is an ordinary prestate read under CAS.** Pause, drain, cancel and
  policy generation are not changed by settling a non-start. The kernel reads them at plan
  time and names them in `domain_reads`; concurrent modification fails the prestate check
  and the command retries. No discriminator is needed, and R4a's ordering requirement is
  still met because the read set is validated against transaction prestate before any
  mutation.
- **Post-refund allocation is a protected discriminator.** Settling a proved non-start
  releases its start reservation, so allocation *after* settlement differs from the
  prestate the kernel saw. Whether a retry is affordable is therefore derived inside the
  transaction, exactly like the infrastructure ordinal. It requires a second discriminator
  primitive, which does not exist and must be specified with its own closed vocabulary
  before subcommit 2.

This is the architectural answer the previous revision owed. If implementation shows
control can in fact change between prestate validation and settlement, that invalidates
the first half and returns here rather than proceeding.

## B1 — a guarded reducer, not a snapshot installer

`apply/2` must stop accepting any event type and delegating to a generic `changes` merge.
Required properties:

- **Closed vocabulary.** Only lifecycle event types the durable codec accepts.
- **Total over its own validator.** If `State.valid?/1` accepts a state, `apply/2` and
  `decide/3` must not raise on it. The candidate accepted states that later raised while
  evaluating a source guard; that is the specific defect.
- **Source-state guards.** Every event names the phase it may apply to. An event that does
  not match its source state rejects rather than installing.
- **No entity creation by projection.** The candidate could create an `integrated` ticket
  from empty state with no candidate, checks, review, claim or ref receipt. Terminal
  states must be reachable only through their lifecycle.
- **Ordering and duplicates.** Replay applies events in durable sequence; an older event
  after a newer one rejects rather than moving a ticket backwards. Duplicate event
  identity is idempotent.

## B2 — custody per the R4 rows

The candidate's closure and check paths violate R4 rows 7, 11, 15–17 and 26. Required:

- `developer_closed` records a durable closure fact and closed execution, not an event
  carrying the unchanged ticket.
- `checks_started` requires developer closure first and creates a check execution; without
  it the row-11 check route is unschedulable because the request guard requires
  `candidate_frozen`.
- A reviewer approval requires a launch receipt, review receipt binding and sealed-stream
  fact before it is accepted. The candidate accepted approval immediately.
- Candidate and check custody survive every closure path: a frozen candidate is preserved
  across developer exit, timeout and abnormal exit, and a failed candidate never reaches
  approval.

## B3 — R4a control crossing at the specified ordering point

R4a is explicit about when controls are evaluated:

> Control state is evaluated **after** recording non-start and **before** queuing its
> successor.

The kernel must implement exactly that order, and cross every role with the full control
and allocation product:

- **Pause** retains the recoverable phase and forbids issue until resume.
- **Drain** forbids developer and PM replacement launches — their work becomes
  `blocked(draining)` with the same resume phase and ordinal — while reviewer, mandatory
  check and already-admitted finalization retries remain eligible.
- **Cancel** settles the proved non-start and finalizes cancellation when no other issued
  work remains; it never retries.
- **Policy revocation or generation change** preserves the role-specific phase and owner
  and blocks or exhausts; an old-generation refund settles its own generation and cannot
  implicitly finance the new retry.
- **Allocation exhaustion** is distinct from the infrastructure limit. For a developer,
  the limit yields `blocked(developer_launch_infrastructure)` with the attempt still
  active and resumable, while allocation exhaustion makes the attempt terminal
  `exhausted`. The candidate collapsed reviewer exhaustion to `blocked(reviewer_budget)`
  and ignored PM allocation entirely.

**Settlement identity binding.** The candidate compared only `settlement == outcome`. The
kernel must bind the settlement to the execution it settles: claim, receipt, role, work
owner, effect, predecessor and infrastructure generation. Caller-supplied identifier sets
do not satisfy this, and the adapter must not be left to invent the check.

## Acceptance, per the FR-08B paragraph

Table-driven sequences over every supported command and verdict, comparing live state with
reconstruction. The R4a trace is required per role from its exact scheduling phase through
pre-intent denial, proved non-start and unknown possible start, asserting that a developer
non-start retains one active attempt and returns the ticket to queued, a reviewer non-start
returns the same frozen candidate to `awaiting_review`, and PM retains its planning owner.
Restart after atomic non-start settlement but before redispatch must reconstruct one owner,
one infrastructure ordinal, no live execution and no replay of the settled launch.

The substitution law is a kernel obligation: binding a planned projection must equal
applying its concretely bound event to the same prestate.

## Subcommit plan

Batch C requires one lifecycle branch with attributable subcommits reviewed as a unit.
Within FR-08B:

1. Pure state and event contract: closed vocabulary, `State.valid?/1` totality, source
   guards, ordering and duplicate rules. No plan production.
2. `decide/3` returning closed transition plans for the developer role only, with its full
   R4/R4a control and allocation product.
3. Reviewer and PM roles against the same contract.
4. Check, freeze, build and integration workers.
5. Every remaining command ingress from the inventory. **Split along the inventory's own
   four ownership boundaries**, not landed as one subcommit: Coordinator/scheduler,
   agent/inbox/cleanup, PM/correction/quota, and public-ingress adapters. The inventory
   assigns those separately to avoid unreviewable concurrent edits to Coordinator,
   AgentServer, Cleanup, PM, Improver and quota modules, and the plan's coordination
   discipline requires one active writer per shared subsystem. Revision 1 reunited them
   into one subcommit, which recreates the unreviewable change the two-level strategy
   exists to prevent.

Additionally, `expected_revisions` and `domain_reads` are **different shapes** — the
command's map is keyed by projection-style strings while the plan carries a typed list
plus a scalar `expected_domain_revision`. The root-fact diagnosis warned against confusing
their key formats. Their correspondence is unreconciled and nothing exercises it, because
Gateway never calls both paths together. Reconciling them explicitly is part of subcommit
2, not an implementation detail.

**Scope of this document:** FR-08B internals only. Batch C additionally requires FR-10,
FR-11 and FR-12 on one lifecycle branch reviewed as a unit. Their composition is not
planned here and needs its own note; the five items above are not the whole of Batch C.

## Explicit non-goals

No external effects inside the reducer. FR-08A's protected verifier is not a second domain
reducer. Legacy JSONL may remain only as checked import/export or diagnostic compatibility
once it stops deciding live workflow truth; its retirement is FR-08B scope but not this
design note's.
