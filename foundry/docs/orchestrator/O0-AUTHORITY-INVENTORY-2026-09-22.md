# O0 authority inventory: where workflow code crosses protected authority

**Date:** 2026-09-22. **Type:** inventory only. It **changes no behaviour**, proposes no
implementation beyond naming seams, and does not interrupt the active repair. **Taken at
commit `6bc015ed`** (`repair/fr08b-kernel`). Every `file:line` below is at that commit and
will drift; re-derive rather than trust a line number after any later edit.

This is step O0 of the [orchestrator boundary migration sequence](../ORCHESTRATOR-BOUNDARY.md):
inventory the workflow calls that cross protected authority, classify each as protected
fact, evidence or telemetry, and identify the software-specific decisions that need not be
protected. Class definitions are the boundary document's "Three classes of durable
information". "Core" and "Standard Controller" are its "Distribution shape" terms: Core owns
authority, evidence, acceptance, effects and budgets with no permanent PM/developer/reviewer
topology; the Standard Controller is the software workflow above it.

Paths are relative to `foundry/lib/pramana_foundry/` unless stated.

## 1. The structural fact that shapes everything below

At `6bc015ed` there are two workflow paths, and **neither is wired to the other**.

| Path | What it is | How it reaches protected authority |
|---|---|---|
| FR-08B kernel (`workflow/kernel.ex`, `workflow/kernel/event.ex`, `workflow/kernel/state.ex`) | Pure reducer: no I/O, no calls into `durable_store/`. **No production caller** — `grep` finds it referenced only by tests, `test/support/kernel_walk.ex`, and a comment at `durable_store/transition_plan.ex:10` | Only through event payload **slots** that `TransitionPlan.bind/3` fills with facts produced by protected operations inside `Gateway`'s atomic bundle (`durable_store/gateway.ex:1296-1331`). The candidate-side plan producer that comment names, `Workflow.Kernel.Plan`, **does not exist** at this commit, so no code path produces a kernel plan outside tests |
| Legacy coordinator (`coordinator.ex`, `coordinator/state.ex`, `coordinator/tick.ex`) | The live pre-repair path | **Never calls `Gateway`.** It appends to a JSONL log (`coordinator.ex:1636`, `effects/checkpoint.ex:27` → `event_log.ex:14-22`). Its "authority" is legacy in-memory state plus that log |

The only production callers of `Gateway` outside `durable_store/` are
`observations/gateway_source.ex:20,25` (read-only snapshot/query) and
`CompatibilityWriter.append/4` (`durable_store/compatibility_writer.ex:20`), reached only when
`EventLog.append/2` is given a `{:durable_store, ...}` target (`event_log.ex:7-8`).

A second consequence: the durable codec knows only the 14 "Family 1" lifecycle types
(`durable_store/record_codec.ex:34`). The kernel's 23 steering and evidence types
(`workflow/kernel/event.ex:38-50`) **cannot be committed durably yet**. Rows E1–E8 and S1–S5
below are therefore crossings the kernel is *designed* to make, not ones any durable
transaction makes today.

## 2. Crossing points

Columns: **class** is protected fact / evidence / telemetry / *uncertain*. **Decision** is
where the decision taken at that point belongs: **Core** (generic), **Controller**
(software-workflow topology, belongs in the Standard Controller), or **Split** (a generic
Core mechanism whose *transition target* encodes software topology; the split line is
stated).

### 2.1 Kernel: bound protected facts (FR-08B path)

The slot table is `durable_store/transition_plan.ex:63-81`; the producers are at `:48-52`.

| # | Crossing | Where | What crosses | Class | Decision |
|---|---|---|---|---|---|
| K1 | `launch_planned.authority` | `workflow/kernel.ex:445-456`; reads `authority.execution_id` at `:1139` | `launch_authority_v1` projected from `issue_claim`'s effect (`transition_plan.ex:208-228`). Kernel keeps only `execution_id` | Protected fact (effect claim/issuance) | Split — binding an execution to an issued effect is Core; "queued ticket launches a **developer** into `developing`" is Controller |
| K2 | `check_planned.authority` | `kernel.ex:671-681` | same shape | Protected fact | Core |
| K3 | `build_planned.authority` | `kernel.ex:1012-1017` | same shape | Protected fact | Core |
| K4 | `review_planned.authority` | `kernel.ex:729-751`; copies `execution_id` into `review` at `:746` | same shape; binds the reviewer execution to the frozen `candidate_id` | Protected fact | Split — review bound to exact candidate and execution is Core; "review follows checks" is Controller |
| K5 | `integration_planned.authority` | `kernel.ex:871-883` | same shape; the promotion effect | Protected fact | Split — promotion issuance is Core; `ready_to_integrate → integrating` is Controller |
| K6 | `pm_launch_planned.authority` | `kernel.ex:268-271` | same shape, **then discarded** (`{:ok, objective}`); no planning execution is recorded | Protected fact (received and dropped) | Split — see §4 |
| K7 | `launch_settled.settlement` | `kernel.ex:459-473`; ordinal `:1184-1185` | `nonstart_settlement_v1` from `settle_claim` (`protected_primitives.ex:189-240`, table `root_infrastructure_settlements`). Kernel ignores the settlement's own `ordinal` and increments its own | Protected fact | Split — closing a non-started execution is Core; `developing → queued`, reason `developer_launch_non_started` is Controller |
| K8 | `check_settled.settlement` | `kernel.ex:683-706` | same | Protected fact | Core |
| K9 | `build_settled.settlement` | `kernel.ex:1019-1029` | same | Protected fact | Core |
| K10 | `review_settled.settlement` | `kernel.ex:754-781` | same | Protected fact | Split — close execution is Core; `reviewing → awaiting_review` is Controller |
| K11 | `integration_settled.settlement` | `kernel.ex:886-904` | same | Protected fact | Split — as K10, target `ready_to_integrate` |
| K12 | `pm_launch_settled.settlement` | `kernel.ex:275-276` | same, but the event **names no execution** (`event.ex:75`) | Protected fact | Split — see §4 |
| K13 | Infrastructure-limit discriminator | `gateway.ex:1316-1352` → `protected_primitives.ex:371-389` (replay: `:330-353`) | Policy `infrastructure_attempt_limits[role]` compared with the authoritative settlement ordinal; selects one of the plan's alternatives | Protected fact | Split — "below/at the limit" is Core; *what happens to the work at the limit* (`ticket_parked`, `ticket_blocked`, `attempt_settled(exhausted)`) is Controller-authored alternatives |
| K14 | `control_changed.control` | `kernel.ex:995-1009`; producer `transition_plan.ex:50,230-242` | `control_id`, `control_revision` from `set_control`. `paused`, `draining`, `stop_status` travel **beside** the bound fact, unbound (`event.ex:76-78`) | Protected fact (identity/revision); flags *uncertain* (U2) | Core |
| K15 | `ticket_reset.generation` | `kernel.ex:373-406` | Slot declared (`transition_plan.ex:80`) but `reset_fact_v1` has **no producer** in `@producers`, so binding fails closed with `:unsupported_output_kind`. Kernel ignores the payload and increments its own generation (`:401`) | Protected fact (allowance generation) | Core |
| K16 | Kernel-held ordinals and generation | `workflow/kernel/state.ex:57-75,206-215`; written at `kernel.ex:401-405,1185` | A per-role counter mirroring `root_infrastructure_settlements.ordinal`. **No kernel guard reads it**; the at-limit decision is K13 | *Uncertain* (U1) | Core |

### 2.2 Kernel: evidence events (FR-08B path, not durably committable yet)

None of these payload values is produced by a protected operation; each is a plain field the
caller supplies.

| # | Crossing | Where | What crosses | Class | Decision |
|---|---|---|---|---|---|
| E1 | `artifact_frozen` | `kernel.ex:477-495` | `candidate_id`, `sealed_generation` — the exact candidate identity | Evidence (candidate registration) | Split — registration is Core; `developing → awaiting_review` is Controller |
| E2 | `check_recorded` | `kernel.ex:710-726` | check `status`, `reason_code` | Evidence (check receipt) | Core |
| E3 | `review_recorded` | `kernel.ex:785-799`; binding guard `:1403-1411` | `candidate_id`, `verdict` against the exact frozen candidate | Evidence (review receipt) | Core |
| E4 | `integration_recorded` | `kernel.ex:908-962` | `ref_receipt_id`, `outcome` — the promotion receipt. `terminal_settlement_v1` is declared (`transition_plan.ex:42`) but has no producer | Evidence (Git/ref proof) | Core |
| E5 | `attempt_settled` | `kernel.ex:965-992`; guards `:1546-1561`, `:1587-1667` | `disposition`, including `integrated` — the doc's "accepted candidate / promoted ref" — written by an unbound domain event gated only on E4 | *Uncertain* (U3) | Split — the acceptance decision is Core; `needs_correction → queued`, `blocked`, `superseded_base` targets are Controller |
| E6 | Execution lifecycle: `execution_observed`, `stream_sealed`, `developer_closed`, `worker_closed`, `reviewer_closed` | `kernel.ex:568-653,810-868` | lifecycle, sealed sequence, closure. `worker_closed` records closure rather than verifying it (`:623-628`); verification is FR-10's protected reconciliation | Evidence | Split — execution closure is Core; `developer_closed`/`reviewer_closed` as distinct types and `reviewer_closed`'s approved → `ready_to_integrate` branch are Controller |
| E7 | `submission_rejected` | `kernel.ex:554-566` | a rejected-submission count; the charge against R5 is not written here | Evidence | Core |
| E8 | `integration_issued?/1` | `kernel.ex:1716-1720` (reasoning `:1672-1714`) | Infers R1 issuance from execution lifecycle; the comment calls it "the kernel's proxy" | *Uncertain* (U4) | Core |

### 2.3 Kernel: admission and steering

| # | Crossing | Where | What crosses | Class | Decision |
|---|---|---|---|---|---|
| S1 | `objective_created` | `kernel.ex:242-252` | objective and `planning_owner_id`; no allocation bound | Protected fact (admitted intent) | Core |
| S2 | `ticket_admitted` | `kernel.ex:279-306` | admission to `queued`/`blocked`. R4.02.o1 requires validated assignment/policy/budget allocation; the event deliberately carries none (`event.ex:35-37`) and no slot binds `reserve`/`delegate_allocation` | Protected fact, unbound | Core |
| S3 | `pm_proposal_recorded` | `kernel.ex:255-265` | proposal id and operation; admits nothing (R4.01.o2) | Evidence | Controller |
| S4 | `ticket_amended`, `ticket_parked`, `ticket_blocked`, `ticket_unblocked` | `kernel.ex:309-371` | spec revision, block reason, resume phase | Protected fact (steering decision) | Split — block/resume is Core; the resume-phase vocabulary is Controller |
| S5 | `cancellation_requested`, `cancellation_finalized` | `kernel.ex:411-443` | cancel control; finalisation needs every execution closed | Protected fact | Core |

### 2.4 Legacy coordinator (live path)

| # | Crossing | Where | What crosses | Class | Decision |
|---|---|---|---|---|---|
| C1 | Subscription-route enforcement | `coordinator/tick.ex:66` | billing/launch policy | Protected fact (read) | Core |
| C2 | Launch eligibility | `tick.ex:67-74`; `coordinator.ex:1526-1538`; roles `launch_eligibility.ex:14` | profile grant, allowed model, quota, cooldown for a role | Protected fact (grant/budget read) | Split — eligibility is Core; "the queue launches `:developer`" and "a handoff launches `:reviewer`" are Controller |
| C3 | Assignment admission | `tick.ex:75-87` → `coordinator/state.ex:141-178` (`auto_approve` refusal `:148-149`) | assignment admitted, written to **JSONL**, not the protected store | Protected fact (legacy store) | Split — admission and the mandatory-review refusal are Core; dispatch order is Controller |
| C4 | Launch retry/park | `tick.ex:130-189,214-237` | coordinator constant `max_launch_retries = 3` | *Uncertain* (U5) | Controller |
| C5 | Handoff → candidate | `coordinator.ex:407-491` → `state.ex:181-256` (`candidate_commit` `:204`) | handoff commit becomes the candidate | Evidence (candidate registration) | Split — registration is Core; handoff retry budget (`:213-252`) is Controller |
| C6 | Automatic reviewer launch and reviewer identity | `coordinator.ex:415-470,1450-1494`; `reviewer_run_id` stored at `:457,1494` | a controller-minted random run id later required by review validation | *Uncertain* (U6) | Split — reviewer independence is Core; spawning a reviewer after handoff is Controller |
| C7 | Review receipt | `coordinator.ex:493-562` → `state.ex:258-347` → `reviews/artifact.ex:31-39` | review `run_id` and `commit` checked against `reviewer_run_id` and `candidate_commit` | Evidence (review bound to exact candidate) | Split — binding is Core; correction limit (`assignments/correction.ex:6`, `@default_max_corrections 2`) and review retry budget (`state.ex:309-340`) are Controller |
| C8 | Integration | `coordinator.ex:564-570`; `state.ex:350-356` | **nothing** — suspended under FR-05 containment | — (no crossing; not counted) | — |
| C9 | PM proposals applied | `coordinator.ex:572-593` → `pm/proposal.ex:67-110` | a PM `create`/`split` proposal **directly queues** an assignment — the proposal acts as admission, contrary to R4.01.o2 | Protected fact (admission) | Split — admission is Core; PM decomposition is Controller |
| C10 | PM attempt-cap reset | `coordinator.ex:595-600` → `state.ex:359-375` → `pm/attempt_cap.ex:130-164` | human-authority reset of the PM allowance; this handler does not persist it | Protected fact (allowance reset) | Split — allowance reset is Core; the PM cap as a concept is Controller |
| C11 | Pause, resume, stop | `coordinator.ex:312-322` → `state.ex:40-58` | control flags, in memory; this handler does not persist them | Protected fact (control) | Core |
| C12 | Ticket enqueue | `coordinator.ex:371-394` | ticket admission, persisted as `ticket_enqueued` | Protected fact (admission) | Core |
| C13 | Manual unblock | `coordinator.ex:324-369` | resumes a parked ticket and **zeroes `launch_retries`** | *Uncertain* (U7) | Split — explicit resume is Core; the retry counter is Controller |
| C14 | Cleanup records | `coordinator.ex:621-676` | cleanup pending/result, resource registration | Evidence (reconciliation) | Core |
| C15 | Telemetry emission | `coordinator.ex:1614-1640` | lifecycle telemetry records | Telemetry | Core |
| C16 | Runtime lease | `coordinator.ex:854,1365` (`RuntimeLease`) | clean-release inhibition for the runtime owner | *Uncertain* (U8) | Core |

### 2.5 Counts

44 crossing points (C8 excluded: it crosses nothing).

| Class | Count | Rows |
|---|---|---|
| Protected fact | 26 | K1–K15, S1, S2, S4, S5, C1, C2, C3, C9, C10, C11, C12 |
| Evidence | 10 | E1–E4, E6, E7, S3, C5, C7, C14 |
| Telemetry | 1 | C15 |
| Uncertain | 7 | K16, E5, E8, C4, C6, C13, C16 |

| Decision | Count |
|---|---|
| Core (generic) | 21 — K2, K3, K8, K9, K14, K15, K16, E2, E3, E4, E7, E8, S1, S2, S5, C1, C11, C12, C14, C15, C16 |
| Controller (software-specific) | 2 — S3, C4 |
| Split (Core mechanism, Controller target) | 21 — K1, K4–K7, K10–K13, E1, E5, E6, S4, C2, C3, C5, C6, C7, C9, C10, C13 |

Only two points are purely Controller. Most of the software topology is **inside** Core
transitions as their target phase, not in separate calls, so moving it above Core means
separating each Split row's target from its mechanism.

**Promotion today:** no live crossing. The coordinator's integration is suspended (C8); the
kernel's route (K5, K11, E4, E5) has no durable path.

## 3. Software topology encoded below the Controller line

### 3.1 In the kernel (`workflow/`)

**Event types that name a role or a software phase** (`workflow/kernel/event.ex:25-50`):
`launch_planned`/`launch_settled` (developer, implicitly), `review_planned`/`review_settled`,
`integration_planned`/`integration_settled`, `pm_launch_planned`/`pm_launch_settled`,
`pm_proposal_recorded`, `developer_closed`, `reviewer_closed`, `artifact_frozen` (developer
result → review), `checks_started` (requires the developer closed), `review_recorded`,
`integration_recorded` (Git outcomes `ref_created`/`no_ref_change`/`infrastructure_failed`),
and `objective_created` (a `planning_owner_id`).
Closer to generic: `check_*`, `build_*`, `worker_closed`, `execution_observed`,
`stream_sealed`, `control_changed`, `cancellation_*`, `attempt_settled` (though its
dispositions are not generic). `ticket_*` treats "ticket" as the work-item noun, which is
software vocabulary for the doc's "ticket/work item".

**Payload fields:** `planning_owner_id`, `candidate_id`, `verdict`, `ref_receipt_id`,
`outcome`, `sealed_generation`, `policy_empty`.

**State fields and vocabularies** (`workflow/kernel/state.ex`):

- ticket phases `:44-45` — `developing awaiting_review reviewing ready_to_integrate integrating integrated`;
- attempt phases `:46-47` — `candidate_frozen checking awaiting_review reviewing ready_to_integrate integrating`;
- dispositions `:48-49` — `integrated needs_correction superseded_base rejected`;
- verdicts `:54` — `approved correction rejected`;
- roles `:55`, `@ticket_roles :63`, `@objective_roles :64` — `developer reviewer pm check build integration`;
- objective keys `:69-70` — `planning_owner_id proposals`;
- attempt keys `:76-78` — `candidate_id ref_receipt_id review checks policy_empty_checks`;
- the phase/attempt pairing `@legal_pairs :388-394`.

**In `kernel.ex`:** `@terminal_ticket_phases :63`, `@blockable_phases :67-68`, reason literals
`"developer_launch_non_started"` (`:470`) and `"integration_failure"` (`:953`), and the
role-named guards `require_developer_closed`, `require_running_developer`,
`require_no_open_developer`, `require_developer_result`, `require_developer_stream_sealed`,
`seal_developer_result`, `require_reviewer_open`, `require_reviewer_execution`,
`require_reviewer_stream_sealed`.

### 3.2 In the protected layer itself (`durable_store/`)

The request was scoped to the kernel, but O0 cannot say Core is topology-free without
recording that it is not:

| Where | What is software-specific |
|---|---|
| `protected_primitives.ex:6`, `:3373-3382` | budget dimensions `starts.pm starts.developer starts.reviewer …`, with `required_dimension/2` mapping role to dimension |
| `protected_primitives.ex:201` | the non-start settlement's role whitelist `developer reviewer pm check freeze build integration activation` |
| `protected_primitives.ex:1240-1249`, `:3116`, `:3296-3297` | every effect requires `ticket_id` and `attempt_id`, scope must equal `"ticket:" <> ticket_id`, and the work owner is `ticket:attempt:role` |
| `protected_primitives.ex:3134-3155` | the non-start allowance is counted per ticket/attempt/operation/role |
| `transition_plan.ex:59`, `:63-81`, `:423` | slots named after software event types; `launch_authority_v1` requires `ticket_id` and `attempt_id` |
| `record_codec.ex:34`, `:46` | lifecycle event and intent vocabularies (`launch prompt check freeze build integrate activate cleanup git_update`) |

This conflicts with the boundary doc's "Do not preemptively build … controller-specific state
into the protected schema" and STRATEGY's "Do not bake today's PM/developer/reviewer names
… into protected storage". Recorded, not acted on: the doc's own sequencing puts factoring
after the repair.

## 4. Is PM planning lifecycle a Core or Controller concern?

**Input:** the [R4a.03.f2 review](../fr-08/fr08b-r4a03f2-review-2026-09-22.md) blocked a
candidate because a PM execution has no success-path close. The only objective-execution
closer is `pm_launch_settled`, which is R4a's proved-non-start row, and it cannot name the
execution it settles.

**Answer: split. The lifecycle mechanics are Core; the PM role and its completion meaning are
Controller.** The gap belongs to Core.

- **Core:** issuing, closing and settling an admitted execution exactly once, with its
  non-start ordinal, budget reservation and control checks. That covers what the doc lists
  under "EXECUTIONS issue / start / terminate / reconcile" and "budget reservation/settlement"
  on the authority path, and the R4a guarantee that "a duplicate or late receipt … cannot
  increment the ordinal", which is generic. The protected layer already treats PM like any
  other role (K6/K12 slots, `starts.pm`, the role whitelist at `:201`). The missing success
  close is a hole in that generic lifecycle. It surfaced on PM because PM is the one role
  whose execution the kernel does not record (K6 discards the authority).
- **Controller:** the fact that the role is "PM"; what a planning result is; whether
  `pm_proposal_recorded` or something else *ends* the planning assignment; and when to plan
  again. [Project workflow profiles](../PROJECT-WORKFLOW-PROFILES.md) §8 makes the result
  kind (a "planning/decomposition proposal") an `AssignmentResult` declared by the admitted
  WorkflowPlan, not a role callback. [Planning strategies](../PLANNING-STRATEGIES.md) §4
  says "PM/Shaper proposes the plan"; the contract's R4.01.o2 says "PM proposal is evidence,
  not authority". The boundary doc's Core "owns no permanent PM/developer/reviewer topology".

**Consequence for the seam:** the Core fix is a role-agnostic close for an execution whose
work owner is an objective rather than a ticket. It is not a `pm_closed` event, which would
add one more role-named type below the line. The review's alternative, "`pm_proposal_recorded`
defined as closing the open planning execution", is a Controller reading. It would tie a
Core lifecycle fact to a PM-specific result. This agrees with the review's own decision not
to widen the kernel's vocabulary until the boundary exists.

**Complication (uncertain, U9):** the kernel counts PM ordinals per **objective**
(`state.ex:64`, `kernel.ex:276`). The protected layer requires every effect, PM included, to
carry a `ticket_id` and `attempt_id`, with work owner `ticket:attempt:pm` and scope
`ticket:<id>` (§3.2). So a PM launch cannot currently be issued under an objective-scoped
work owner at all. The two layers disagree about what owns a planning execution.

## 5. Uncertain classifications and what would settle each

| # | Row | Why unsure | What would settle it |
|---|---|---|---|
| U1 | K16 kernel ordinals | The ordinal is a protected fact (`root_infrastructure_settlements`). The kernel's copy is incremented, never read, and ignores the settlement's own `ordinal`. `state.ex:5-7` says the kernel "may not restate" ledger truth. It could be a restated protected fact (a defect) or a replay-visible projection (telemetry-grade) | A contract reading of R4a's "reconstructs" clause saying whether replay must see the ordinal in domain state. If not, the field is deletable; if so, the kernel should take the bound `ordinal` rather than count |
| U2 | K14 control flags | `paused`/`draining`/`stop_status` travel beside the bound `control_fact_v1` unbound. The protected layer checks control `status == "active"` itself (`protected_primitives.ex:3158-3159`) | Compare the `root_controls` value schema with the kernel flags. If the flags are in the protected value they should be bound, not caller-copied |
| U3 | E5 `attempt_settled(integrated)` | This is the doc's protected fact (accepted/promoted), yet it is written by an unbound domain event gated on E4's caller-supplied `ref_receipt_id` | The FR-13/FR-14 promotion design: whether acceptance/integration gets a protected producer (`terminal_settlement_v1` is declared, not derivable) |
| U4 | E8 `integration_issued?` | A kernel inference of R1 issuance from execution lifecycle; the source comment calls it a proxy | Binding issuance as a protected fact, or a contract ruling that the lifecycle proxy suffices |
| U5 | C4 launch retry limit | It plays R4a's infrastructure-allowance role (protected policy under the contract) but is a coordinator constant | Whether FR-08B wiring retires the legacy retry path in favour of K13. If it does, C4 is dead code, not a classification |
| U6 | C6 `reviewer_run_id` | Independence is a Core predicate over principal lineage. Here it is a random id the controller mints and later checks, which is conformance item 7's "relabelling" risk | Whether the legacy review path is in scope for independence at all, or wholly superseded by K4/E3 plus a principal-lineage check |
| U7 | C13 unblock zeroes `launch_retries` | R4a says restart and resumption "do not reset the ordinal". If `launch_retries` is the legacy ordinal this is a reset without policy; if it is controller retry state it is fine | Same as U5 |
| U8 | C16 runtime lease | Writer/owner fencing is Core in spirit (conformance item 4) but is neither a fact, evidence nor telemetry in the doc's taxonomy | A fourth category for fencing/ownership, or a ruling that it is a protected fact |
| U9 | §4 PM work owner | Objective-scoped in the kernel, ticket-scoped in the protected layer | Construct a PM `create_effect` against the protected layer and see whether an objective-scoped PM effect is admissible. This inventory ran no code — **Settled 2026-09-23: not admissible.** `allowed_effect?` requires `scope == "ticket:" <> ticket_id` even when policy lists the objective scope, and `root_effects.ticket_id` is `NOT NULL`. Pinned by `protected_primitives_test.exs` "an effect cannot be scoped to an objective, only to a ticket" (red control: removing the scope check makes it fail). An objective-owned execution needs a Core schema change; it stays with the deferred PM lifecycle, not the FR-08B protected items |
| — | C10, C11 persistence | These handlers do not persist; `grep` found no in-lib caller of `Coordinator.pause/0` or `reset_pm_attempts/1`, so they may be persisted, or unused, via a CLI path not traced here | Trace the CLI callers |

## 6. Seams, named only

No implementation is proposed. These are where a Core/Controller split would cut:

1. **Slot binding** (`transition_plan.ex:48-81`) is already the protected boundary. The
   split is slots keyed by generic execution kind rather than by role-named event types.
2. **The discriminator** (`gateway.ex:1316-1352`): Core decides the limit and the controller
   authors the alternatives. This is the cleanest existing instance of the doc's "facts and
   eligibility; controller chooses strategy".
3. **Evidence binding:** E1–E4 have no protected producer. This is the doc's "register
   candidate / register review / register check" surface.
4. **Admission binding:** S1, S2 and C9 are unbound to `reserve`/`delegate_allocation`.
5. **Coordinator → Gateway:** absent. O1's local reference adapter has nothing to wrap until
   the live path reaches the protected store.
