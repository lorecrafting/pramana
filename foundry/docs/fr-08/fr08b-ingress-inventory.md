# FR-08B command-ingress and transition inventory

Date: 2026-09-20

Baseline: `079473065ea1124620132ce712c2b19acca0b5e6` (`main`)

Scope: read-only source and test inventory for FR-08B. No provider, daemon, runtime
mutation, deployment or live acceptance was run. This document is implementation
planning evidence, not ticket completion, execution authority or a replacement for the
[workflow contract](../WORKFLOW-CONTRACT.md) or [repair plan](../REPAIR-PLAN.md).

## Evidence convention and conclusion

- **Direct evidence** identifies behavior present in the named baseline and cites exact
  source lines.
- **Required migration** is an inference from the workflow contract's command protocol,
  R4/R4a lifecycle and R5 ledger rules. It is not a claim that the inferred command or
  transition exists.

**Direct evidence:** FR-08B cannot safely begin on this revision. The current authority
has two separate transaction surfaces: domain `Gateway.transact/4` and single-operation
`Gateway.protected_command/4`. Neither can atomically combine an R4/R4a domain transition
with protected claim, reservation, lease, receipt or ledger settlement
(`lib/pramana_foundry/durable_store/gateway.ex`, lines 75–90;
`lib/pramana_foundry/durable_store/protected_primitives.ex`, lines 10–44). The focused
[atomic-composition diagnosis](atomic-composition-diagnosis.md#finding) reaches the same
conclusion.

**Direct evidence:** no production Coordinator path uses the SQLite Gateway. Coordinator
still recovers and writes `events.jsonl`, while live mutation remains divided among
Coordinator, State, Tick, PM, Cleanup and AgentServer callbacks
(`lib/pramana_foundry/coordinator.ex`, lines 121–137, 158–171 and 1245–1275).

**Required migration:** after the independently accepted FR-08A atomic-bundle correction
integrates, FR-08B should route every mutation through one command service invoking a pure
`decide(state, command, inputs)` and the same `apply(state, event)` for live projection and
replay. The current `Transition` is a legacy event projector, not that kernel.

## Existing command and authority surfaces

The durable codec currently admits exactly these command types:
`legacy_event_append`, `enqueue`, `steer`, `pause`, `resume`, `cancel`, `reset`, `propose`,
`submit_artifact`, `submit_review`, `request_effect` and `record_receipt`
(`lib/pramana_foundry/durable_store/record_codec.ex`, lines 17–23).

The Gateway validates command and bundle shape but accepts a caller-supplied proposal; it
does not bind each command type to a trusted domain decision function
(`lib/pramana_foundry/durable_store/gateway.ex`, lines 471–560). Existing result
dispositions are `accepted`, `rejected` and `blocked`; rejected or blocked proposals may
not contain domain mutations (`lib/pramana_foundry/durable_store/kernel.ex`, lines 9–24).

Protected operations currently comprise `set_policy`, `set_control`, `append_inbox`,
`seal_inbox`, `grant_ledger`, `delegate_allocation`, `return_allocation`, `reserve`,
`release_reservation`, `close_generation`, `reset_generation`, `create_effect`,
`claim_effect`, `reclaim_claim`, `issue_claim`, `cancel_effect` and `settle_claim`
(`lib/pramana_foundry/durable_store/protected_primitives.ex`, lines 6–8). Claim-settlement
outcomes are `succeeded`, `failed`, `non_started` and `unknown`, with fixed proof pairings
(`lib/pramana_foundry/durable_store/protected_primitives.ex`, lines 1139–1175 and
3288–3291).

`Coordinator.transition/1` is only a non-persisting planner for `:admit` and `:prompt`, not
a canonical command executor (`lib/pramana_foundry/coordinator.ex`, lines 282–286;
`lib/pramana_foundry/transition.ex`, lines 76–140). `Coordinator.replace_projection/1` is
exposed but has no matching handler (`lib/pramana_foundry/coordinator.ex`, line 31).

## Mutation-ingress inventory

Each row distinguishes the current mutation destination from the required canonical
command, protected operations and persisted domain decision.

| Ingress and callers | Direct evidence: current destination | Required migration: command, inputs, protected/domain outcome | Missing migration and acceptance |
|---|---|---|---|
| CLI/RPC ticket creation | RPC admits `ticket create`; CLI generates a task ID from OS time plus random bytes and calls `Coordinator.enqueue_ticket/1` (`cli/rpc.ex`, lines 136–152; `cli.ex`, lines 356–390). Coordinator appends legacy `ticket_enqueued`, then installs separately reduced memory (`coordinator.ex`, lines 371–394). | `enqueue`: actor/command ID, recorded time, ticket/objective/spec/allocation IDs, absent-ticket precondition and policy/control/ledger revisions. Atomically bind protected allocation, using `delegate_allocation` where needed, and persist ticket-created/enqueued events, queued projection and result. | Route RPC to canonical envelopes; inject IDs/time; same-ID, lost-reply, restart and stale-read cases; one common admission path for direct and PM-created tickets. |
| CLI handoff submit and block | Submit may route through AgentServer or directly to Coordinator (`cli.ex`, lines 162–221). Public block constructs `{outcome, summary, task_id}`, while the blocked validator requires schema version, task/run IDs, `status`, reason and diagnostic evidence (`cli.ex`, lines 244–268; `assignments/handoff.ex`, lines 7–49). The advertised block therefore cannot reach blocked. | `submit_artifact`: execution ID, inbox sequence/item ID, raw digest or bytes reference, recorded time and candidate/check IDs. `append_inbox`; consume a validation reservation; request freeze/check effect if valid. Completed advances toward candidate/checking; blocked/partial is explicit terminal blocked; malformed is a durable charged rejection. | Fix public block semantics; table-test completed, blocked, partial/invalid and malformed; end-to-end public block must reach its intended state. |
| CLI review submit and AgentServer reviewer callback | Both call `Coordinator.receive_review/3` (`cli.ex`, lines 276–327; `agent_server.ex`, lines 329–360). State validates and mutates memory; Coordinator appends `review_received`; correction can message the old developer (`coordinator/state.ex`, lines 258–345; `coordinator.ex`, lines 493–560). | `submit_review`: review inbox item/sequence, review/execution/candidate/check/policy IDs, verdict, raw digest and recorded time. `append_inbox`, validation charge and possibly `seal_inbox`; approved advances only after reviewer close, correction terminalizes the attempt and queues fresh developer work, rejected terminalizes rejected. | Approved/rejected/changes-requested, malformed retry/exhaustion, exact-candidate guards, sealed result-before-exit and no re-prompt of an old developer. |
| Coordinator public controls | `pause`, `resume`, `request_stop`, full `reset`, PM reset and unblock mutate memory; only unblock appends a legacy event (`coordinator.ex`, lines 289–367 and 595–599). Drain and ticket cancellation are absent. RPC exposes none of these and rejects CLI `ticket unblock` because no accepted RPC shape names it (`cli/rpc.ex`, lines 127–164). | `pause`, `resume`, `steer`, `cancel`, `reset`, plus explicit drain/clear-drain/stop/resume-ticket semantics. Inputs: authenticated operator, control ID/revision, target/scope, recorded time, policy revision, complete outstanding-claim reads and explicit reset grants. Atomically apply `set_control`, `cancel_effect`, `close_generation`/`reset_generation` and domain control events. | Restart persistence; pending/finalized status and outstanding claim IDs; drain and stop-blocked rules; cancellation before/after issue; terminal guards; authenticated public routes. Remove destructive memory reset. |
| Coordinator direct admission | `Coordinator.admit_assignment/5` calls State and updates memory without an event; State reads wall time (`coordinator.ex`, lines 400–405; `coordinator/state.ex`, lines 139–175). | Internal `request_effect`/schedule-launch command, never an unrestricted public state edit. Inputs: attempt/execution/effect/reservation IDs, exact policy/control/resource/dependency/ledger revisions, recorded time/deadline, role and profile. Atomically `reserve` plus `create_effect` with queued→developing/reviewing/PM-planning. | Remove or privatize the bypass and prove all callers use the command service. |
| Scheduler/Tick developer admission | Tick generates a run ID, reads clock/environment/profile, calls State, appends `assignment_admitted`, then starts a child (`coordinator/tick.ex`, lines 20–122). Prelaunch denial directly blocks memory; supervisor failure uses legacy retry/parking (`coordinator/tick.ex`, lines 124–196). | Scheduler remains pure selection. `request_effect` distinguishes pre-intent denial from admitted launch intent. Supply IDs, time and eligibility/resource observations explicitly. Commit `reserve` plus `create_effect`; dispatcher later claims/issues. Pre-intent denial creates no execution, reservation or ordinal. | Capacity/dependency/resource/profile/pause/drain/cancel matrix; priority; multi-ticket allocation; crash between commit/dispatch; no debit on denial. |
| Reviewer scheduling | A successful handoff generates a reviewer ID and launches before durable reviewer ownership, then stores reviewer run ID only in memory; ineligibility directly blocks memory (`coordinator.ex`, lines 415–467 and 1540–1547). Reviewer retry repeats this (`coordinator.ex`, lines 1450–1523). | `request_effect` for reviewer from exact `awaiting_review`, retaining immutable candidate/check receipts and assigning new execution/effect/reservation IDs. Protected reserve/effect/claim/issue lifecycle. | Reviewer capacity and R4a tests; frozen-candidate retention; no developer-ledger debit; restart before dispatch. |
| Agent launch callbacks | AgentServer sends launch success/failure messages (`agent_server.ex`, lines 136–212). Success changes `dispatched_at` with current wall time and no durable event; failure appends legacy retry/park and directly changes counters/state (`coordinator.ex`, lines 863–1043). | `record_receipt`: receipt/request/claim IDs, exact outcome, proof and recorded time. Atomic `settle_claim`, role-specific domain transition and corrected FR-08A infrastructure-ordinal fact. | Developer/reviewer/PM R4a rows; duplicate/conflicting/late receipts; unknown hold; same ID; reopen before redispatch. |
| Result, exit, timeout and crash callbacks | AgentServer sends timeout, completion and crash messages (`agent_server.ex`, lines 216–263 and 430–460). Coordinator appends `task_completed`/`task_crashed` but independently infers live state and retry counters (`coordinator.ex`, lines 1045–1199). | `append_inbox` for result/exit observation, `seal_inbox(last_sequence)`, then an execution-decision command. Inputs include observation ID/time, deadline generation and verified termination evidence. Valid result precedes later exit; sealed no-result controls failure/timeout. | Every result-versus-exit mailbox order, stale deadline generation, late evidence, unknown stream completeness and terminal overwrite denial. |
| Correction lifecycle | `Assignments.Correction.handle_review/2` reads time and mutates counters/history; Coordinator prompts the existing developer (`assignments/correction.ex`, lines 16–63; `coordinator.ex`, lines 516–524; `agent_server.ex`, lines 268–297). This conflicts with R4's fresh developer attempt. | Review correction event terminalizes the current attempt `needs_correction`; a fresh attempt is queued only after cleanup and current allocation/control validation. Recorded time and new attempt/execution/effect/reservation IDs are inputs. | Remove old-agent correction prompt; correction/rebase allocation, drain and exhaustion cases. |
| PM proposals and planning | Improver and HardeningPM call `Coordinator.apply_pm_proposals/2` (`improver.ex`, lines 456–466; `hardening_pm.ex`, lines 115–133). Create/split/amend/reprioritize/park mutate state and create wall-clock timestamps (`pm/proposal.ex`, lines 67–218). Replay records only `pm.last_proposal`, losing the actual mutations (`transition.ex`, lines 705–715). | `propose` with operation-specific payload and explicit proposal/spec IDs, recorded time and objective/policy/control/parent-ledger reads. Root performs common admission; ticket creation uses `delegate_allocation`. PM disposition and PM non-start are separate receipt-driven decisions. | Live/replay equality for all five proposal operations and all-or-none batches; PM owner, budget, non-start, pause/drain and reset cases. |
| PM attempt/reset counters | AttemptCap mutates timestamps and reset state in memory; reset deletes counters rather than changing an R5 generation (`pm/attempt_cap.ex`, lines 22–73 and 129–185). | Durable PM disposition events plus protected PM-start/model-request reservations. Reset is an authenticated generation change with explicit grant, not deletion. | Restart/exhaustion persistence; repeated-reason cap; old-generation late receipt and no implicit refill. |
| Cleanup and resource ownership | AgentServer synchronously invokes `record_cleanup`; Coordinator uses `Cleanup.register_resource`, `apply_pending` or `apply_result` then legacy appends (`agent_server.ex`, lines 91–94; `coordinator.ex`, lines 621–673; `cleanup.ex`, lines 18–132). | Receipt/cleanup observation carrying resource/lease/effect/claim/receipt IDs, verified identity and termination proof. Atomically settle claim/lease and update cleanup projection. | Duplicate/stale/sibling identity; unresolved cleanup; capacity retention; cancellation; SQLite restart/replay. |
| Startup recovery | Coordinator rebuilds using legacy Transition and contains outstanding legacy states; dormant stale re-enqueue code appends an event and mutates separately (`coordinator.ex`, lines 137–260 and 1551–1610). | Reopen validates protected/domain histories and reconstructs projections only. New recovery observations are explicit commands; status alone never synthesizes a relaunch or requeue. | Restart at every commit boundary; unknown-claim recovery; settled launch not redispatched; projection rebuild equality. |
| Legacy effect helpers | Launch and prompt helpers append `launch_intent`, `launch_completed`, `prompt_intent` and `prompt_delivered` directly (`effects/launch.ex`, lines 23–127; `effects/prompt_delivery.ex`, lines 14–85). Strict Transition lacks most of these cases and rejects unknown events (`transition.ex`, lines 717–722). | Effects originate only as committed intents; dispatch claims/issues; observations return as receipt commands. | Remove authority use of `Checkpoint.matching/5`; reconcile by protected claim/receipt identity. |
| Quota/cooldown/fallback | Public pure APIs alter cooldown/fallback maps and generate IDs/time, but no production caller exists outside the quota facade (`quota/cooldown.ex`, lines 9–22; `quota/fallback.ex`, lines 94–190; `quota/quota.ex`, lines 6–24). | If retained, use a durable steering/observation command with explicit time/new execution ID and existing allocation. A profile switch cannot refill authority. | Decide whether supported; otherwise remove from authoritative state. If supported, test replay and no implicit credit. |
| Budgets and ledgers | Real R5 state exists only behind protected APIs; Coordinator lifecycle uses ad hoc retry counters. Protected ledger operations are implemented separately (`protected_primitives.ex`, lines 506–847 and 1139–1188). | Every productive transition uses the corrected atomic bundle. Each operation names ledger/reservation generation and immutable owner. Receipt settlement and domain transition share one commit. | Domain+ledger conservation; multi-ticket delegation; validation charges; late closed-generation settlement; recursive reset and no refill. |

## Known live/replay divergence

Direct source evidence establishes additional migration traps:

- Pause, resume, stop, reset, direct admission and PM reset are not durable commands.
- `CoordState.new/1`, State admission/handoff/review, PM proposal/counter code,
  correction, Coordinator, Tick and CLI read clocks or allocate IDs internally
  (`coordinator/state.ex`, lines 11–36; `transition.ex`, lines 185 and 256;
  `cli.ex`, lines 367–368).
- Transition's review reducer derives reduced correction records and does not reproduce
  the full live correction artifact (`transition.ex`, lines 465–549).
- `Checkpoint.matching/5` is record matching, not actor/command-ID/digest idempotency
  (`effects/checkpoint.ex`, lines 41–50).
- Existing retry/correction counters do not encode R5 generations, allocation, holds,
  consumption, refunds or late settlement.
- Exit/result ordering depends on process messages rather than authenticated inbox
  sequence and seal facts.

These findings agree with the earlier [FR-08 investigation](investigation.md#confirmed-migration-traps),
but the source citations above bind this inventory to the stated baseline.

## Table-driven acceptance matrices

The common harness should execute each sequence live, reopen the store, reconstruct into a
fresh projection namespace and compare the full domain projection with bounded protected
snapshots/facts. A test of only one side is insufficient.

### Command protocol and verdict matrix

| Coverage | Required rows and assertions |
|---|---|
| Canonical types | Each of the twelve codec command types: `legacy_event_append`, `enqueue`, `steer`, `pause`, `resume`, `cancel`, `reset`, `propose`, `submit_artifact`, `submit_review`, `request_effect`, `record_receipt`. |
| Command result | `accepted`, `rejected`, `blocked`; malformed or unauthenticated traffic outside history; incomplete/stale read set as durable rejection. |
| Idempotency | Same actor+ID+digest returns the original result before current CAS; changed actor or semantic payload conflicts; lost reply followed by same-ID retry, restart and retry. |
| Submission result | Developer `valid`, `blocked`, `partial`, `invalid`, `none`; completed/blocked handoff; malformed validation charged once. |
| Review verdict | `approved`, `changes_requested`, `rejected`, plus malformed review and no valid verdict before sealed exit. |
| Receipt verdict | `succeeded`, `failed`, `non_started`, `unknown`; valid and invalid proof pairing; duplicate and conflicting observations. |
| Explicit inputs | Missing required actor, command/event/effect/claim/reservation/receipt ID, recorded time, observation or deadline rejects. Fixed inputs produce byte-for-byte equivalent decisions. |

### R4 source-state guard matrix

Every unlisted source-state transition must reject without domain mutation.

| Row | Source/guard | Expected outcome |
|---:|---|---|
| 1 | Objective without spec; broad steering | Durable objective and bounded PM reservation; proposal is evidence only. |
| 2 | Draft plus specific spec or valid PM create | Common admission: queued/blocked; malformed rejected. |
| 3 | Queued/blocked plus PM amend or park | Future spec revision or explicit block; no active edit/refill. |
| 4 | Queued and launch eligible | Fresh or retained R4a attempt, intent and developing; pre-intent denial remains queued and uncharged. |
| 5 | Developing plus valid frozen candidate | Candidate frozen, ticket awaiting review, productive capability sealed and developer close requested. |
| 6 | Freeze/import infrastructure failure | Retain bytes; bounded check retry/block; unknown retains lease. |
| 7 | Candidate frozen plus developer exit/timeout | Cleanup only; preserve candidate. |
| 8 | Developing, sealed stream, no valid candidate, verified exit/timeout | Attempt failed/timed-out; bounded fresh attempt or exhausted. |
| 9 | Developing plus valid blocked/partial result | Terminal blocked attempt/ticket; no review. |
| 10 | Open submission plus malformed result | Durable charged rejection; continue only while open and funded. |
| 11 | Candidate frozen, developer closed, check eligible | Checking attempt and mandatory root checks scheduled. |
| 12 | Checking plus all mandatory receipts passed or explicit empty set | Awaiting review and reviewer queue. |
| 13 | Checking plus assertion failure | Needs-correction attempt; fresh developer or drain/exhaustion block. |
| 14 | Checking plus infrastructure failure/timeout/unknown | Preserve candidate; bounded retry, block or hold unknown. |
| 15 | Awaiting review plus valid checks/capacity | Reviewing with independent reviewer intent/reservation. |
| 16 | Reviewing plus approved exact-candidate verdict | Close reviewer; ready to integrate only after verified close. |
| 17 | Reviewing plus correction verdict | Needs correction; fresh developer or drain/exhaustion; never old developer. |
| 18 | Reviewing plus rejected verdict | Terminal rejected; cleanup independent. |
| 19 | Reviewing, sealed with no verdict, reviewer crash/timeout | Preserve candidate; bounded new reviewer or exhaust. |
| 20 | Ready to integrate plus current base/evidence/policy | Integrating and protected integration intent. |
| 21 | Ready/integrating plus moved base before issue | Superseded-base attempt; bounded rebase plus new checks/review. |
| 22 | Integrating plus successful ref receipt and closed prior workers | Integrated ticket and attempt; exit cannot overwrite. |
| 23 | Integrating plus proved no ref change/infrastructure failure | Same-phase retry/block; conflict uses moved-base; unknown reconciles. |
| 24 | Blocked plus explicit resume or recorded dependency/resource recovery | Revalidate all authority and return to resume phase. |
| 25 | Exhausted plus authenticated reset and explicit resume | Old attempt stays terminal; fresh developer under new grant. |
| 26 | Integrated/rejected/cancelled plus ordinary lifecycle command | Reject and preserve terminal facts. |
| 27 | Nonterminal plus cancel request | Orthogonal cancel control; cancel pending work and interrupt issued work. |
| 28 | Cancel requested plus all owned work/cleanup terminal | Cancelled unless integration occurred; otherwise integrated and finalized after integration. |

### R4a role and control matrix

For developer, reviewer and PM independently, test all three launch-admission outcomes:

| Outcome | Common assertion | Role-specific assertion |
|---|---|---|
| Pre-intent denial | No execution, claim, reservation or infrastructure ordinal; scheduling owner remains. | Developer remains queued; reviewer retains awaiting-review candidate; PM retains planning owner. |
| Proved `non_started` | In one commit: settle effect/claim/reservation/leases, record failure class/predecessor/infrastructure generation and increment one ordinal. Duplicate receipt changes nothing. | Developer retains the same active attempt and queues/blocks/exhausts correctly. Reviewer retains candidate/check custody and reviewer queue/block. PM retains planning owner, admits no ticket and queues/blocks under PM allowance. |
| Unknown possible start | Reservation and lease remain held; execution/claim becomes unknown; no replacement launch. | Each role retains its exact owner and phase pending reconciliation. |

Cross each role/outcome with pause, drain, cancel, allocation exhaustion,
infrastructure-limit exhaustion, policy revocation, ledger-generation change and restart
after settlement but before redispatch. Restart must reconstruct one owner, one ordinal, no
live execution and no replay of the settled effect.

### R5 transfer, settlement and reset matrix

Test root grant; parent-to-multiple-child delegation; partial return; reserve; issue
unknown; confirmed start consumption; proved non-start release; direct validation
consumption; duplicate terminal settlement; conflicting-receipt quarantine; recursive
close; root and child generation reset; explicit transfer of old unused authority; late
old-generation non-start to retired; late start to consumed; old holds constraining new
grant; and refusal to convert dimensions.

Correction, rebase, crash retry, profile switch, ticket/spec amendment and projection
version changes must not refill a ledger. Across every row assert
`authorized = available + held + consumed + delegated + retired` and the corresponding
tree-wide conservation rule before commit, after live commit and after replay.

### Public, restart and purity matrix

- Exercise every exposed mutation through the real inert RPC wrapper. In particular,
  `handoff block` must reach blocked, controls must reach their intended durable states,
  unknown shapes must reject inertly and read-only commands must start no coordinator or
  effect.
- Restart must preserve pause/stop, all PM proposal operations, exhausted retry state and
  terminal dispositions. Completion/exit cannot overwrite accepted review state.
- Stale deadline generations and late receipts are evidence but cannot mutate a newer
  owner. A settled launch is never redispatched.
- A kernel projection change cannot forge policy, control, claims, receipts, accepted refs
  or ledger facts.
- Run decisions with clock, RNG, Git, backend and current-configuration calls replaced by
  fail-on-call fakes. Replay must use only retained inputs/events.
- Compare migrated v1 history and new bundle history across live, reopen, replay and
  verified backup.

## Ownership and implementation slicing

Do not begin implementation from this baseline. Rebase onto the independently accepted
atomic-composition correction and rerun its authority/replay gate first.

The correction is expected to own these high-conflict files:

- `lib/pramana_foundry/durable_store/gateway.ex`
- `lib/pramana_foundry/durable_store/protected_primitives.ex`
- `lib/pramana_foundry/durable_store/database.ex`
- `lib/pramana_foundry/durable_store/record_codec.ex`
- `lib/pramana_foundry/durable_store/authority.ex`
- FR-08A durable-store tests and repair-gate evidence
- shared repair-plan and implementation-log status records

After integration, use disjoint slices:

1. **Pure domain kernel and matrix fixtures:** new kernel modules and tests owning R4
   states, commands, events and `decide/apply`; no Gateway or Coordinator edits.
2. **Gateway command-service adapter:** one owner wires the pure kernel to the corrected
   atomic bundle and removes caller-supplied arbitrary domain proposals. This owner alone
   edits the Gateway-facing codec and application wiring.
3. **Public ingress adapter:** `cli.ex`, `cli/rpc.ex`, validators and RPC tests construct
   authenticated canonical envelopes and repair public block; no reducer logic.
4. **Coordinator/scheduler adapter:** one owner edits Coordinator, State, Tick, Scheduler
   and their tests, reducing Coordinator to cache/dispatch and removing direct mutation.
5. **Agent/inbox/cleanup adapter:** AgentServer, Cleanup, effect helpers and related tests;
   callbacks become inbox or receipt commands.
6. **PM/correction/quota adapter:** PM, correction, Improver/HardeningPM and quota modules;
   proposals and counters become commands and old-developer correction is removed.
7. **Acceptance/replay suite:** new FR-08B table modules and fixtures only, independently
   exercising every matrix above.
8. **Documentation/evidence:** a single reconciler after code integration, avoiding
   concurrent repair-plan or implementation-log edits.

The unavoidable hotspots are Coordinator, RecordCodec, application supervision and the
corrected Gateway surface. Assign one owner to each. Other slices should expose adapters
or new modules rather than editing those files concurrently.

## Inspection limitations

This inventory inspected source and existing test names at the pinned revision. It did
not execute the suite and does not claim that an existing test passed. Existing focused
tests cover legacy Transition/Coordinator behavior and protected FR-08A primitives, but
there is no maintained FR-08B all-ingress table suite that covers all matrices above.
No external effect, paid provider, daemon, deployment or live listener was exercised.
