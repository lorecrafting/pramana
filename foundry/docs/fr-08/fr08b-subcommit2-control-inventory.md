# Subcommit 2 read-only inventory: the R4a control and allocation product (B3)

Read-only against `a798579`. No source edits. Subcommit 2's deliverable is `decide/3` for
the developer role **with its full R4/R4a control and allocation product**, which is
blocker B3 — the one blocker of the pure-kernel review that no attempt has touched.

## What the kernel holds, and what reads it

`State.new/0` carries a control entity: `paused`, `draining`, `stop_status`, `generation`,
`control_id`, `control_revision` (`state.ex:78-87`).

**Nothing reads any of it.** Every occurrence in the reducer is `control_changed` writing
the flags (`kernel.ex:928-936`) or the validator checking their shape. No transition guard
consults `paused`, `draining` or `stop_status`.

That is correct for subcommit 1, whose scope is the state and event contract — control
gating is a decision, and decisions are `decide/3`'s. It is worth recording plainly
anyway, because a stored value nothing reads is the shape this codebase has shipped three
times already, and the subcommit that starts reading it is the one that finds out whether
the shape is right.

## The ordering requirement has no implementation at all

R4a is explicit:

> Control state is evaluated **after** recording non-start and **before** queuing its
> successor.

Nothing in the kernel implements an ordering between recording and queuing, because the
kernel does not queue — `decide/3` does. So this is not a gap to fix in subcommit 1; it is
the first thing subcommit 2 must get right, and it is testable the moment `decide/3` exists:
a non-start recorded under a drain must not produce a successor, and the *recording* must
survive.

## The product, stated as a matrix

Five control crossings, each with a per-role answer. The previous candidate collapsed two
of them, which is why B3 is still open.

| Crossing | Developer | Reviewer | PM | Check/build/integration |
|---|---|---|---|---|
| Pause | retain recoverable phase, forbid issue | same | same | same |
| Drain | forbid replacement launch; `blocked(draining)` with same resume phase **and ordinal** | already-admitted retries remain eligible | forbidden, like developer | mandatory checks remain eligible |
| Cancel | settle non-start, finalize when no other issued work remains; never retry | same | same | same |
| Policy revocation / generation change | preserve role phase and owner; block or exhaust; old-generation refund settles its own generation | same | same | same |
| **Infrastructure limit** | `blocked(developer_launch_infrastructure)`, attempt **still active and resumable** | `blocked(reviewer_launch_infrastructure)`, candidate retained | `pm_launch_infrastructure` | that phase's own block row |
| **Allocation exhaustion** | attempt terminal **`exhausted`**, ticket `exhausted` | `blocked(reviewer_budget)` or `exhausted` | `pm_budget` | per phase |

The last two rows are different outcomes from different causes, and the reviewed candidate
treated reviewer exhaustion as only `blocked(reviewer_budget)` and ignored PM allocation
entirely. Subcommit 1 now expresses the infrastructure-limit row through `ticket_blocked`
and the exhaustion row through `attempt_settled(exhausted)`; what it cannot do is **decide
between them**, because that turns on allocation.

## What subcommit 2 needs that the kernel does not have

1. **The limits themselves.** `launch_non_start_limit` is protected policy, per role and
   work owner. The consumed side exists — per-role ordinals landed in subcommit 1 — so
   `decide/3` can evaluate "at the limit" once the limit is supplied as a protected fact.
   Confirm it is supplied rather than inferred.
2. **Allocation state.** The kernel holds none, and must not: the R5 ledger is protected.
   So allocation exhaustion must arrive as a protected fact too. Until it does, every
   "or exhausted" alternative stays undecidable — which is exactly why four clauses are
   recorded `@partial` in the coverage suite rather than driven.
3. **Settlement identity binding.** The reviewed candidate compared `settlement == outcome`
   and nothing else. R4a requires the settlement bound to the execution it settles: claim,
   receipt, role, work owner, effect, predecessor and infrastructure generation. A
   caller-supplied identifier set does not satisfy this, and the adapter must not be left to
   invent the check. This is the same class as FR-08A's binding correction, and that
   correction took five subcommits and two blocked reviews — budget accordingly.

## Prerequisites already recorded elsewhere

- The durable vocabulary extension, now **23** types, gated on nothing further since the
  `ticket_resumed` collision was resolved by renaming to `ticket_unblocked`.
- `expected_revisions` versus `domain_reads`, in
  [its own inventory](fr08b-subcommit2-reads-inventory.md) — four mismatches, one of which
  means a plan's declared domain reads have no defined translation into anything the
  gateway checks.
- `terminal_settlement_v1` and `reset_fact_v1` producers, required before subcommit 3.
