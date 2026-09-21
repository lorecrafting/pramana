# FR-08B subcommit 1 — correction design

Date: 2026-09-20

Answers [the independent review](fr08b-subcommit1-review-findings.md), which returned
BLOCK on `be1e19c`. Base for the corrections: `f42219c` on `repair/fr08b-kernel`.

## Diagnosis: two abstraction defects, then guards

The repair plan requires diagnosing the abstraction once rather than accumulating patches
against an interface already shown wrong. Sorting the nineteen findings gives two
structural defects and a set of discrete guard omissions. The structural pair must land
first, because six of the guard corrections cannot be expressed until they do.

### Defect A — executions are addressed through the active-attempt pointer

`active_attempt/1` and `update_active_attempt/2` (`kernel.ex:889-892`) read
`ticket["attempts"][ticket["active_attempt_id"]]`, and every execution helper is built on
them: `require_execution/2`, `require_sealed/2`, `require_not_closed/2`,
`require_worker_role/2`, `require_reviewer_execution/2` and `close_execution/2`. So an
execution is reachable only while its attempt is the active one.

`attempt_settled` sets `active_attempt_id` to `nil`. Every execution the attempt owned
becomes permanently unreachable at that instant — while R4 orders closure *after*
settlement in four rows: "close developer, then queue fresh", "queue fresh developer after
all check workers close", "close/seal reviewer, then queued fresh developer", "bounded
new check-run reservation after cleanup". R4a's restart sentence requires reconstructing
"no live execution", and today every integrated ticket permanently reports one.

This is one defect with six symptoms, not six defects. The correction is to address an
execution by the attempt that **owns** it: helpers take an `attempt_id`, and closure
events require that the attempt exists and owns the execution rather than that it is
active. `require_active_attempt` stays where R4 genuinely means the active attempt —
launch, freeze, check and review *transitions* — and leaves the closure paths.

Two guards fall out of the same correction. `developer_closed` requires
`candidate_frozen` (`kernel.ex:489`), which makes rows 8 and 9 — developer close after a
blocked or partial result, and after a sealed stream with no candidate — unexpressible;
the phase guard goes, and the sealed-stream guard stays, because that is what R4 actually
conditions closure on. And `refuse_terminal_ticket` (`:194`) must narrow from *all* events
to *transitions*: recording a closure on an integrated ticket preserves terminal facts, it
does not overwrite them, which is what R4's terminal row actually says.

### Defect B — the infrastructure ordinal is per ticket, not per role and owner

`@infrastructure_keys ~w(ordinal generation)` sits on the ticket (`state.ex:40`), and five
settlement rows bump the same counter. R4a sets `launch_non_start_limit` "per role and
work owner" and records `(role, work_owner, predecessor_effect_id, failure_class,
infrastructure_attempt_ordinal)` on every proved non-start. The check-worker row says a
retry "consumes its finite **role-specific** infrastructure allowance".

So today a reviewer non-start consumes the developer's allowance. Objectives carry no
infrastructure at all, so the PM limit R4a names cannot be evaluated from this state.

Ordinals become a per-role map on the work owner: the ticket holds one per role, the
objective holds the PM ordinal. Generation stays per owner, since R4a's reset creates a
new generation for the owner rather than for one role.

This matters beyond bookkeeping: `decide/3` in subcommit 2 must evaluate "below the
infrastructure limit" per role. Subcommit 2 was gated on a state shape that cannot answer
its central question.

## Guard corrections

Each is discrete once A and B land.

| Finding | Correction |
|---|---|
| 1 | `attempt_settled` gets a source-state guard per disposition: `rejected` requires a rejected verdict, `cancelled` requires `cancel_requested`, `integrated` keeps its ref-receipt guard, and the reviewer crash/timeout row must not terminalise at all |
| 2 | `cancellation_finalized(after_integration)` requires a prior attempt holding a ref receipt |
| 4 | `check_recorded` becomes write-once on terminal statuses, mirroring the verdict rule |
| 5 | `check_settled` preserves the attempt in `checking` per R4 row 13's "pending same phase" rather than poisoning it |
| 7 | An attempt holding a ref receipt may only settle `integrated`; the row commits atomically |
| 8 | `require_workers_closed` accepts `closed` only; `unknown` blocks, per R4a |
| 9 | `require_resume_phase` excludes `blocked` and terminal phases; parking an already-blocked ticket keeps its stored target |
| 10 | `review_settled` gets `require_reviewer_execution`, as `reviewer_closed` has |
| 11 | `integrating` gains its bounded-retry and `blocked(integration_failure)` exits |
| 13 | `artifact_frozen`, `artifact_blocked`, `submission_rejected` and sealed-no-candidate each seal an execution `result` |
| 14 | A policy-empty check set finishes checks rather than stranding the attempt |
| 15 | `ticket_parked` rejects `developing`; R4's park row is "queued/blocked" |
| 16 | `cancellation_finalized` requires every owned execution closed — expressible only after defect A |

Corrections 4 and 10 are the same principle the reviewer identified as applied to one
sibling and not the other. Both are therefore applied as rules over the vocabulary rather
than as fixes to two events.

## Prober corrections

The prober's defects are why six blockers were invisible, so they are part of this
subcommit rather than deferred.

- **Admit a replacement ticket.** Every deep walk currently dies with its single ticket —
  twenty of twenty-five end `cancelled`, five `rejected` — and then idles hundreds of steps
  on background events. Without this the step budget buys nothing after the first death.
- **Make the reachability ratchet variant-level**, matching the prober's own labelling.
  Findings 2 and 8 both live in the gap between a type-level ratchet and a variant-level
  coverage model. Variants never proposed and therefore never counted include
  `cancellation_finalized:after_integration`, `execution_observed:{starting,closing,unknown}`,
  `freeze_failed:{retry,unknown}` and `check_recorded:{pending,running,unknown,cancelled}`.
- **Propose the missing variants**, including a `ticket_admitted` carrying an objective.
- **Fix the `ticket_parked` proposal** to derive `resume_phase` from R4 rather than from
  the ticket's current phase — the confirmed circularity.
- **Re-derive `@known_unreached` from scratch** once the kernel corrections land. The
  present entry is not a ratchet; it is a false claim.

Properties 18 names as mislabelled are restated to assert what their names claim: the
restart property must assert R4a's "exactly one queued/review/blocked owner and no live
execution", and the sequence property must test the kernel rather than the walker's
counter.

## Resolved during the corrections: a vocabulary collision

Found by read-only inventory during the review. **Correction to an earlier claim in this
document: it was not unrecorded.** [The vocabulary design](event-vocabulary-design.md)
called it at FR-08A subcommit 0 — "The legacy and lifecycle sets currently collide on one
name, `ticket_resumed`. The lifecycle event takes a distinct name instead. Which name is
FR-08B's call" — and the FR-08B enumeration lost it. The mechanism was already decided; only
the name was outstanding.

`RecordCodec` holds fourteen lifecycle types (`record_codec.ex:34`); the kernel declares
thirty-six; the extension is exactly the twenty-two the enumeration names. But
`ticket_resumed` is already a member of `@legacy_event_types` (`:28`), and `:40-46` raises
a `CompileError` when the two vocabularies share a name — deliberately: "a reused name
would silently give one stored type two contracts, which is the single failure this design
must prevent."

Legacy members are explicitly immutable, so the resolution belongs on the kernel side, as
the vocabulary design already required.

**Resolved: the lifecycle event is `ticket_unblocked`.** R4 calls the input "explicit
resume", but that row also ends "explicit operator blocks require steering, not automatic
**unblocking**", so `unblocked` is the contract's own word. It is also the more accurate
one: the source phase is always `blocked` however the ticket got there — a PM park,
`blocked(check_infrastructure)`, `blocked(draining)` — so a name pairing it with
`ticket_parked` would claim it only undoes a park. The asymmetry with `ticket_parked` is
the state machine's: parking is one of several ways into `blocked`, and this is the only
way out.

Verified mechanically rather than by inspection: extending the codec's lifecycle vocabulary
by the kernel's remaining 22 types now yields no shared name, so the extension satisfies the
codec's compile-time rule. Two maintained assertions were added so the next such collision
fails a test rather than breaking a later build — one that no kernel type reuses a legacy
name, and its converse, that no durable lifecycle type is missing from the kernel.

Both subcommit-3 prerequisites stand unchanged: `reset_fact_v1` has a slot and no producer,
`terminal_settlement_v1` has neither.
