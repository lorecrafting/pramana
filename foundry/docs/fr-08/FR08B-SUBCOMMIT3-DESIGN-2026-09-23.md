# FR-08B subcommit 3: reviewer and PM roles — scope, prerequisites, two decisions

**Date:** 2026-09-23. **Type:** design proposal. **Status: D1–D4 APPROVED by the
operator 2026-09-23, as recommended.** P1 (subcommit 2's developer `decide/3`) is still unmet
and comes first. No production code changes. Taken at `7514c930` (`repair/fr08b-kernel`); line
numbers are at that commit.

## What subcommit 3 is

The subcommit plan defines it as "Reviewer and PM roles against the same contract"
(`fr08b-kernel-correction-design.md:233`). Subcommit 2 is "`decide/3` returning closed
transition plans for the developer role only" (`:231-232`). Subcommit 4 covers the check,
freeze, build and integration workers (`:234`). Subcommits 3 and 4 are reviewed as one batch:
"FR-08B's roles and workers (3 and 4) qualify" (`REPAIR-PLAN.md:269-271`).

The reducer transitions for both roles already exist from subcommit 1
(`kernel/software/review.ex:31-171`, `kernel/software/planning.ex:10-44`). **What subcommit 3
adds is `decide/3` for these roles**: closed transition plans that bind protected facts,
reject pre-intent denial without creating an event (`fr08b-event-vocabulary-enumeration.md:176-182`),
and apply the R4a control and allocation product that subcommit 2 builds for the developer.

## Deliverable

| Area | R4 / R4a rows (`WORKFLOW-CONTRACT.md`) | Events and slots | Guard / plan work |
|---|---|---|---|
| Reviewer launch | R4.15 (`:478`) | `review_planned`, slot `review_planned.authority` ← `launch_authority_v1` (`transition_plan.ex:79`) | Rejections for reviewer capacity and eligibility. Control product: `review_planned` checks only pending cancel (`review.ex:38`), while `launch_planned` checks pause, drain and cancel (`executions.ex:33-35`) — **Q1** below |
| Reviewer non-start | R4a.02 (`:431`); the uncited clauses o2, o5–o8, o10 (`r4_coverage_test.exs:297-303`) | `review_settled` ← `nonstart_settlement_v1` (`transition_plan.ex:86`), already bound to its execution (`:640`, B3 item 4); `ticket_blocked(reviewer_launch_infrastructure | reviewer_budget)` | Below the limit, back to the reviewer queue. At the limit, blocked with `resume_phase: awaiting_review`. Missing allocation gives blocked or exhausted without approving the candidate |
| Verdicts | R4.16–R4.18 (`:479-481`) | `review_recorded`, `stream_sealed`, `reviewer_closed`, `attempt_settled(needs_correction | rejected)` | `attempt_settled.settlement` ← `terminal_settlement_v1`, which does not exist yet (P2). R4.17's "queued fresh developer or blocked(drain)/exhausted" |
| Reviewer crash | R4.19 (`:482`) | `reviewer_closed` no-verdict branch (`review.ex:158-165`); `attempt_settled(exhausted)` | A bounded new reviewer execution, or exhaust. The developer ledger is untouched |
| PM | R4.01 (`:464`), R4a.03 (`:432`); o3–o5 uncited (`r4_coverage_test.exs:304-307`); R4a.03.f2 `:unguarded` | `pm_launch_planned`, `pm_launch_settled` (`event.ex:74-75`) | **Blocked, see Q2.** `pm_launch_planned` records nothing (`planning.ex:36-38`). `pm_launch_settled` has no `execution_id` and no guard (`planning.ex:43-44`) |

The acceptance trace this discharges is "reviewer non-start returns the same frozen candidate
to awaiting_review; PM retains its planning owner" (`REPAIR-PLAN.md:876-881`).

## Prerequisites at `7514c930`

| # | Prerequisite | Met? | Evidence |
|---|---|---|---|
| P1 | Subcommit 2: developer `decide/3`, including the control and allocation product and the `expected_revisions`/`domain_reads` reconciliation | **No** | Nothing under `lib/` defines `decide`. The FR-08B row says "the rest of subcommit 2 … outstanding" (`REPAIR-PLAN.md:452`). Subcommit 3 extends a function that does not exist yet. Subcommit 2 also gets its own review (`:266-268`) |
| P2 | `terminal_settlement_v1` producer and slot `attempt_settled.settlement` (`close_attempt`) | **In progress** (another session) | `transition_plan.ex:52-56` has four producers, and `:76-92` has no `attempt_settled` slot. Spec: item 1 of `FR08B-PROTECTED-ITEMS-SPEC-2026-09-23.md:17-68`. Required before subcommit 3 (`fr08b-event-vocabulary-enumeration.md:212-221`) |
| P3 | `reset_fact_v1` producer | Yes | `transition_plan.ex:56, :92`; kernel side at `4ceca7f4` |
| P4 | Settlement binds the execution it settles (B3 item 4) | Yes | `7631641e`; `transition_plan.ex:640` `:settlement_execution_mismatch` |
| P5 | Non-start settles after a policy revision (B3 item 5) | Yes | `3db4ac1d` |
| P6 | Kernel split by family along the generic/software line | Yes | `cd762052`, `c702c877`; `O1-SEQUENCING-PROPOSAL-2026-09-23.md:69-73` |
| P7 | EV-2 clause IDs, required before subcommit 3 (`REPAIR-PLAN.md:345`) | Yes | `fr08b-evidence-reduction-tickets.md` order table, EV-2 "Landed" |
| P8 | Stop hand-writing R4 twice: the prober reads the row table, and preconditions are found by search (`REPAIR-PLAN.md:144-157`) | No | `KernelWalk.candidates/1` is still hand-written (`test/support/kernel_walk.ex:264`). Not a hard gate, but every reviewer scenario written before it is a third encoding to migrate later |
| P9 | No independent review outstanding on the current state shape, because the collapse question depends on it (`REPAIR-PLAN.md:213-214`) | Unknown | Operator to confirm |

**Constraint from O1:** Core stays role-agnostic. Subcommit 3 adds no role-named protected
vocabulary (`O1-SEQUENCING-PROPOSAL-2026-09-23.md:41-43, 57-59`). The kernel is the
Standard Controller layer, and its role-named events may stay (`:28-31`). Every protected
fact that subcommit 3 binds already exists or is keyed on identity: `launch_authority_v1`,
`nonstart_settlement_v1`, and `terminal_settlement_v1` (keyed on `(scope, attempt_id)` with
no role, spec `:54-55`).

## Q1: does pause or drain gate a reviewer launch?

R4.15's from-cell (`WORKFLOW-CONTRACT.md:478`) does not mention control. R4a orders control
"after recording non-start and before queuing its successor", and that applies to every role.
R4.17 and R4.13 name `blocked(drain)` explicitly. **Proposal:** `decide/3` evaluates control
before it plans any successor launch, reviewer included. The reducer guard stays as it is,
because the reducer records decisions and does not make them. The operator should confirm
this reading, since it changes behaviour for a ticket that is paused while it waits for
review.

## Q2: take PM out of subcommit 3

Two recorded gaps block PM:

1. **Vocabulary.** A PM execution has no success-path close, and `pm_launch_settled` cannot
   name its execution. The R4a.03.f2 candidate was blocked on these two findings
   (`fr08b-r4a03f2-review-2026-09-22.md`, findings 1–2), which are "a vocabulary change, not a guard".
2. **Core.** An objective-scoped effect is inadmissible (O0 U9, settled 2026-09-23,
   `O0-AUTHORITY-INVENTORY-2026-09-22.md:247`). No PM plan can reach Gateway until a Core
   schema change lands, and that change "stays with the deferred PM lifecycle".

**Proposal:** subcommit 3 covers the reviewer only. The PM rows stay `:unguarded` or uncited,
recorded as deferred to the PM lifecycle (FR-15), and not built on a kernel surface the
standing direction says not to grow.

## The checks/review collapse question (`REPAIR-PLAN.md:197-214`)

**Recommendation: do not collapse. Bind each check run and review to its execution instead,
and do it before the reviewer's `decide/3`.**

Evidence for the problem the plan describes (two places holding facts about one thing, kept in
step by hand), measured and not just argued:

- **A check record does not name its execution.** `check_planned` adds a check and an
  execution with no link between them (`checks.ex:43-52`). `check_settled` checks the
  `check_id` and the `execution_id` independently (`checks.ex:57-77`). Probe (below): with
  C1/K1 and C2/K2 planned, `check_settled{check_id: C2, execution_id: K1}` is **accepted**.
  Result: checks `["C1"]`, executions `K1 closed, K2 pending`. C1's run is closed as a
  non-start, and C2's record is deleted while its worker is still live. B3 item 4 fixed this
  shape at the protected layer (settlement to execution), but the protected layer cannot
  see `check_id`. The gap has already been noted as deferred to subcommit 4
  (`executions.ex:126-128`).
- The review side already has the pointer (`review.execution_id`), and guards exist only to
  keep it in step: `require_reviewer_execution` (`review.ex:234-239`),
  `require_reviewer_stream_sealed` (`:184-191`) and `require_reviewer_open` (`:225-232`). The
  last one is documented as unreachable (`:218-224`).

Why binding and not collapsing:

1. **The contract keeps them as separate entities.** "Check/review | check_run_id or
   review_id → exact candidate, policy and **independent execution/receipt**"
   (`WORKFLOW-CONTRACT.md:236`). "Check run" has its own state machine, "pending, running,
   passed, failed, timed_out, unknown, cancelled; bound to candidate/tree/check definition"
   (`:392`), and it is separate from "Execution lifecycle" (`:389`). Collapsing would hide a
   contract entity inside an execution field.
2. **A check is not one execution.** A `check_id` names a mandated check that survives its
   runs: a timed-out or infrastructure-failed run is re-planned under the same id
   (`checks.ex:152-166`, `retryable_check?`). Both "all mandatory receipts passed" and the
   policy-empty set are read over check ids, not runs (`checks.ex:128-136`).
3. **O1's generic/software split.** `Execution` is in the generic module
   (`executions.ex:1-5`). Putting a verdict or a check status on it adds software-workflow
   vocabulary to the generic entity, which decision 3 says not to do
   (`O1-SEQUENCING-PROPOSAL-2026-09-23.md:69-73`).

**Proposed fix (commit 1 below):** give the check record `execution_id` (the review record
already has one). `check_settled`, `check_recorded` and `worker_closed` for a check each
require that the named execution is the one bound to the check. A re-plan rebinds it. Add a
refusal atom and use the probe as its red control. After this, one rule (`close_execution/4`
plus the binding) replaces the hand-kept pairs, which is the outcome the plan wanted from the
collapse.

## Proposed commit sequence

This starts after P1 (subcommit 2, reviewed) lands. P2 must land before commit 5.

1. `fix(foundry): a check run binds the execution it plans`: the binding above, with the
   probe as the red control. It can go in before subcommit 3 as its own candidate.
2. *(Only if D3 is approved)* `refactor(foundry): the execution entity as a struct`, which is
   mechanical. It adapts `test/support/kernel_walk.ex` and about 29 test-side `"executions"`
   sites. See the measurement below.
3. `feat(foundry): decide/3 plans reviewer launch (R4.15)`: pre-intent rejections, the
   control product per Q1, and `review_planned.authority`.
4. `feat(foundry): decide/3 settles reviewer non-start (R4a.02)`: below the limit, at the
   limit, and the budget block. This cites o2, o5–o8 and o10.
5. `feat(foundry): reviewer verdicts terminalise through terminal_settlement_v1
   (R4.16-R4.19)`. This needs P2.
6. `test(foundry): reviewer scenarios by searched precondition` (P8 item 2 for the new rows),
   moving the cited clauses out of `@uncited`.
7. PM: either the deferral record (Q2) or, if the operator reverses Q2, the vocabulary change,
   which counts as protected maintenance.

Then comes one batch review with subcommit 4 (`REPAIR-PLAN.md:269-272`), plus the contract-row walk.

## Decisions requested

- **D1 (Q1):** control gates every successor launch in `decide/3`, the reviewer's included.
- **D2 (Q2):** take PM out of subcommit 3 and defer it to the PM lifecycle.
- **D3:** convert the execution entity to a struct in commit 2, or do not. The measurement
  follows.
- **D4:** bind rather than collapse checks and review. Commit 1 can land now.

## Measurement: what Elixir 1.20's checker sees on an `%Execution{}` struct

Environment: Elixir 1.20.3 / OTP 29, base `7514c930`. The spike ran on the throwaway local
branch `spike/execution-struct-aad81` (commit `099f417f`, not pushed). It changed 7 files,
+78/−61: `execution["f"]` became `execution.f`; every enumeration binds
`{_id, %Execution{} = execution}`; writes became `update_in(a, ["executions", id], &%{&1 | f: v})`;
`add_execution` builds `%Execution{}` with `@enforce_keys` on all five fields; and
`State.valid_execution?/1` matches `%Execution{}`. Production code on this branch is unchanged.

**Conversion.** `mix compile --force` produced **0 warnings** both before and after the
conversion. The conversion found no latent defect. The kernel stays green in a
`Kernel.apply/2` probe that exercises every write site (launch through `check_recorded`,
ending at `awaiting_review`). The existing workflow suite goes red (187/207, 36 invalid). In
every sampled failure, the cause is test code reading executions through `Access`
(`UndefinedFunctionError … Execution.fetch/2`, 23 occurrences), not the kernel.

**Seeded defects.** For each defect: apply it, run `mix compile --force`, run the runtime
probe, then revert. The map baseline seeds the equivalent defect into the original code.
"Runtime" means `Kernel.apply/2` refuses at the first event that runs the site.

| Defect (seed) | Struct: compile | Struct: runtime | Map: compile | Map: runtime |
|---|---|---|---|---|
| Misspelled field on update, typed site: `%{e \| lifecyle: …}` in `execution_observed` | **warning** | `:kernel_raised` | none | `:malformed_post_state` |
| Misspelled field on update, untyped site: `&%{&1 \| lifecyle: "closed"}` in `close_execution` (the value came through `update_in`) | **none** | `:kernel_raised` | none | `:malformed_post_state` |
| Field written with the wrong shape: `lifecycle: :closed` (an atom) | none | `:malformed_post_state` | none | `:malformed_post_state` |
| Missing required field: `sealed_sequence` omitted in `add_execution` | **compile error** (`@enforce_keys`) | n/a | none | `:malformed_post_state` at `launch_planned` |
| Misspelled read: `execution.lifecyle` in `require_no_open_developer` | **warning** | KeyError if the site is reached. The probe did not reach it | none (`execution["lifecyle"]` is `nil`) | **silent**: probe accepted. The suite fails several tests only because `nil != "closed"` makes every developer look open |
| Stale string-key read on a struct: `execution["lifecycle"]` | **none** | raises if the site is reached. The probe did not reach it | n/a | n/a |

Raw warning for the typed-site update misspelling (trimmed):

```
warning: expected a map with key :lifecyle in map update syntax:
    %{e | lifecyle: payload["lifecycle"]}
but got type:
    dynamic(%PramanaFoundry.Workflow.Kernel.Execution{execution_id: term(), role: term(),
      lifecycle: term(), result: term(), sealed_sequence: term()})
where "e" was given the type: dynamic(%...Execution{})  # from executions.ex:72:86
└─ lib/pramana_foundry/workflow/kernel/executions.ex:73:12: ...Executions.do_transition/4
```

Raw warning for the misspelled read (trimmed):

```
warning: unknown key .lifecyle in expression:
    execution.lifecyle
the given type does not have the given key:
    dynamic(%...Execution{execution_id: term(), role: binary(), lifecycle: term(), ...})
where "execution" was given the types: dynamic(%...Execution{}) = execution  # executions.ex:289:91
└─ lib/pramana_foundry/workflow/kernel/executions.ex:290:53: ...require_no_open_developer/1
```

The missing-field seed failed the build with `** (ArgumentError) the following keys must also be given
when building struct PramanaFoundry.Workflow.Kernel.Execution: [:sealed_sequence]` at
`executions.ex:196`.

**What this shows:**

1. On the write side, the struct adds little. Kernel property 6 (`:malformed_post_state`)
   already catches misspelled keys, wrong shapes and missing keys at the first transition
   that runs the site, and it also catches wrong *values*, which the checker never does
   (struct fields are typed `term()`).
2. **Reads are where the struct helps.** The misspelled read is the one seed the map kernel
   accepts silently. Only a behaviour test notices it. With the struct it is a compile warning
   at a typed site, and the gate's `--warnings-as-errors` turns that into a build failure. At
   an untyped site the misspelled read becomes a raise instead of a silent `nil`.
3. **The checker sees only what is pattern-matched or constructed.** A value fetched from the
   string-keyed parent map is `dynamic()`, so the `update_in … &1` misspelling and the stale
   `["lifecycle"]` read are invisible to it. The value depends on a convention (bind
   `%Execution{} = e` at every site) that nothing enforces.

**Recommendation for D3:** a modest yes, for the execution entity only, as commit 2. Two
conditions: the convention in point 3 is adopted, and the one-time test churn is accepted.
Do not extend the struct to attempt or ticket until that commit has run through one review;
the gain on reads is real but narrow.

### Reproduce

The probe (`Kernel.apply/2` over `ticket_admitted → launch_planned → execution_observed →
artifact_frozen → stream_sealed → developer_closed → checks_started → check_planned →
check_recorded`) prints the first refusal. For the check-binding probe, apply the same
builders up to `check_planned` twice (C1/K1, C2/K2), then
`check_settled{check_id: "C2", execution_id: "K1", settlement: %{"schema_version" => 1}}`, and
inspect `attempts["A1"]`. The observed output was
`{["C1"], %{"K1" => "closed", "K2" => "pending", "X1" => "closed"}}`. Commands:
`mix compile --force` and `TMPDIR=/private/tmp mix test <probe>`. The spike branch holds the
struct conversion. The probe files were scratch and are not committed. Commit 1 turns the
check-binding probe into a regression test.
