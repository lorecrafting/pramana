# FR-08B subcommit 2: the developer `decide/3`

**Date:** 2026-09-23. **Type:** design proposal, **not approved**. No production code or
tests change. Taken at `e608a2b0` (`repair/fr08b-kernel`). Line numbers are at that commit.
Paths are relative to `foundry/`.

## What this is

Subcommit 2 is "`decide/3` returning closed transition plans for the developer role only,
with its full R4/R4a control and allocation product"
(`docs/fr-08/fr08b-kernel-correction-design.md:231-232`). It also has to reconcile
`expected_revisions` with `domain_reads` (`:244-249`). Its first commit has landed: the
reducer refuses to plan under pause, drain and pending cancel (`kernel/control.ex:33-44`,
`kernel/executions.ex:33-35`). The rest is outstanding (`docs/REPAIR-PLAN.md:454`).
Subcommit 3 extends the same function to the reviewer
(`FR08B-SUBCOMMIT3-DESIGN-2026-09-23.md:136-139`), and its approved D1 says that "control
gates every successor launch in `decide/3`" (`:151`).

The producer is the module that `durable_store/transition_plan.ex:9-11` names and that does
not exist yet: `PramanaFoundry.Workflow.Kernel.Plan`. It is candidate-side code. Gateway never
calls it (`plan-binding-specification.md:46-53`).

## Two findings that shape the design

1. **The durable codec cannot carry most developer plans.** `RecordCodec` admits 14
   lifecycle types (`durable_store/record_codec.ex:34`, checked at `:118`), without
   `ticket_blocked`, `attempt_settled` or `cancellation_finalized`, and `bind/3` normalizes
   through it (`transition_plan.ex:149`). So the at-limit, exhaustion and cancel plans cannot
   commit today. The end-to-end non-start test sidesteps this with a `"blocked"` projection
   value on `launch_settled` (`test/.../atomic_bundle_test.exs:1255-1257`), not the kernel's
   event (`kernel/tickets.ex:80-92`). This is the recorded, undone vocabulary extension
   (`fr08b-subcommit2-control-inventory.md:74-75`); `record_codec.ex` is attestation-pinned
   (`fr08a-protected-report.txt:18`).
2. **A launch cannot be a plan.** Issuing needs `reserve`, `create_effect`, `claim_effect`,
   `issue_claim` (`atomic_bundle_test.exs:800-843`). `claim_effect` is protected
   (`protected_primitives.ex:7`) but absent from `TransitionPlan.@operation_types`
   (`transition_plan.ex:41`), and a plan must declare every staged operation
   (`gateway.ex:1391-1401`).

Both need protected maintenance under R3. See commit 0 and O1 below.

## Signature and return shape

```elixir
# PramanaFoundry.Workflow.Kernel
@spec decide(State.t(), command :: map(), facts :: map()) ::
        {:ok, %{"command" => map(), "plan" => map()}}
        | {:reject, reason :: atom()}
        | {:error, reason :: atom()}
```

- **`state`**: the prestate. It must pass `State.well_formed?/1`, as `apply/2` requires
  (`kernel.ex:129-130`).
- **`command`**: a `RecordCodec` command (`record_codec.ex:18`). Its `expected_revisions`
  are ignored on input. `decide/3` returns the command with them filled in (see Reads).
- **`facts`**: protected facts that the adapter read through `Gateway.protected_query/3`
  (`gateway.ex:98`). Each is one existing query type (`protected_primitives.ex:571-620`),
  returned together with its revision. `policy` and `control` carry the root policy and root
  control. `allocation` is the ledger generation for this role's start dimension. The adapter
  also supplies `writer_epoch` and `predecessor_effect_id`. `decide/3` never queries
  anything itself. It is pure, like `apply/2` (`kernel.ex:5-7`).
- **`{:ok, ...}`** is always an `accepted` plan. `decide/3` never emits the codec's
  `rejected`/`blocked` dispositions (`transition_plan.ex:43-44`): `bind/3` refuses them
  (`:141`), so Gateway would record a rejected bundle, not "no transition".
- **`{:reject, reason}`** is R4a's pre-intent denial. It "creates no execution, claim or
  reservation" (`WORKFLOW-CONTRACT.md:400-401`), so it produces no event
  (`fr08b-event-vocabulary-enumeration.md:176-182`) and nothing is sent to Gateway.
- **`{:error, reason}`**: malformed input (state, command or fact shape); a caller bug.

**Identifiers are derived from `command_id`** (e.g. `"#{command_id}/e0"`), so a retry
rebuilds the same plan and digest for the same-ID lookup (`gateway.ex:576-578`); this is the
"explicit clock/ID inputs" requirement (`REPAIR-PLAN.md:871`).

**Projections are computed by the reducer.** Each alternative is dry-run through `apply/2`
on the prestate; a reducer refusal becomes `{:reject, _}`, so no plan the reducer would refuse
is emitted and no guard is written twice. Each written entity's post-state is the projection
`value`; markers are checked with `Event.validate(event, template: true)` (`kernel/event.ex:178-195`).

## Module layout, mirroring the reducer split

- `Kernel.decide/3` dispatches on `command["type"]` through a `@deciders` table, like
  `@families` (`kernel.ex:77-93`).
- `Kernel.Plan`: role-generic builders (`launch`, `nonstart`, `close_attempt`, `block`), the
  namespace table, id derivation, `expected_revisions/2`, the dry run. It names no role.
- `Kernel.Software.Developer.decide/3`: command types, `launch_planned`/`launch_settled`,
  dimension `starts.developer`, reason `developer_launch_infrastructure`, retained-attempt rule.
- `Kernel.Cancellation.decide/3`: `finalize_cancellation`, generic (`kernel.ex:80`).

Subcommit 3 adds `Software.Review.decide/3` on top of the same builders, with
`review_planned`, `review_settled`, `awaiting_review` and `reviewer_launch_infrastructure`.
Nothing in `Plan` changes for it. This follows O1: the kernel is the Standard Controller's
layer, and role vocabulary stays out of Core (`O1-SEQUENCING-PROPOSAL-2026-09-23.md:28-31,
41-43`).

**Executions are read only through accessors.** Examples are `Executions.open_executions/1`
(`kernel/executions.ex:244-249`) and a new `Executions.open_role?/2`, which would lift the
test from `require_no_open_developer/1` (`:288-295`). `decide/3` never reads
`execution["field"]` directly. The concurrent conversion to an execution struct (D3,
`FR08B-SUBCOMMIT3-DESIGN-2026-09-23.md:153, 228-231`) then changes only the accessors.

## Commands, per R4/R4a row

| Command | Rows | Protected operations | Bindings → slot | Discriminator | Alternatives |
|---|---|---|---|---|---|
| `launch_developer`, launch branch | R4.04.f1–f3, o1–o3 (`WORKFLOW-CONTRACT.md:467`); R4a.01.o7 retry (`:430`) | `reserve`, `create_effect`, `claim_effect`, `issue_claim` | `launch_authority_v1` from `issue_claim` (`transition_plan.ex:55`) → `launch_planned.authority` (`:77`) | `unconditional_v1` | `unconditional`: `launch_planned` |
| `launch_developer`, drain branch | R4a drain sentence (`WORKFLOW-CONTRACT.md:438-439`) | none | none | `unconditional_v1` | `unconditional`: `ticket_blocked(draining, resume_phase: developing)` |
| `launch_developer`, exhaustion branch | R4a.01.o9 (`:430`) | `close_attempt` | `terminal_settlement_v1` (`transition_plan.ex:57`) → `attempt_settled.settlement` (`:94`) | `unconditional_v1` | `unconditional`: `attempt_settled(exhausted)` |
| `settle_developer_nonstart` | R4a.01.f1–f2, o1, o3, o7, o8 (`WORKFLOW-CONTRACT.md:430`) | `settle_claim` | `nonstart_settlement_v1` (`transition_plan.ex:53`) → `launch_settled.settlement` (`:84`) | `infrastructure_limit_v1`, required (`:382-384`) | `below_infrastructure_limit`: `launch_settled`. `infrastructure_limit_reached`: `launch_settled`, `ticket_blocked(developer_launch_infrastructure, resume_phase: developing)` |
| `finalize_cancellation` | R4.28 (`WORKFLOW-CONTRACT.md:491`); R4a cancel sentence (`:436-437`) | `close_attempt` | `terminal_settlement_v1` → `attempt_settled.settlement` | `unconditional_v1` | `unconditional`: `attempt_settled(cancelled)`, `cancellation_finalized` |

Notes on the table:

- Discriminator values are the protected layer's (`protected_primitives.ex:346-348`);
  settlement-to-execution identity is checked at bind (`transition_plan.ex:705-718`).
- **One command runs the developer successor**, because under the approved Q1 reading, "the
  successor is the next issue, not the settle"
  (`FR08B-B3-CONTRACT-READINGS-PROPOSAL-2026-09-22.md:83-90, 399-401`). The settle is
  therefore unconditional with respect to control. It always commits either `queued` or the
  limit block. Everything that R4a orders "before queuing its successor"
  (`WORKFLOW-CONTRACT.md:435`) is evaluated on the next `launch_developer`.
- `kernel.ex:52-53` says the at-limit branch emits `ticket_parked`; the kernel blocks with
  `ticket_blocked` (`kernel/tickets.ex:72-92`). Stale comment, fixed in commit 3.

## How `launch_developer` decides, in order

1. **Pending cancel**: `{:reject, :cancel_pending}`. Cancel "never retries"
   (`WORKFLOW-CONTRACT.md:437`), and cancellation is finalized by its own command.
2. **Pause**: `{:reject, :control_paused}`. Pause "retains the recoverable phase but forbids
   issue" (`:437-438`), so the phase is untouched and no event is written.
3. **Drain.** If R4a retained an attempt (the ticket is `queued` with `resume_phase:
   developing`, which `launch_settled` stores at `kernel/executions.ex:53-55`), return the
   drain-branch plan. The contract says replacement launches "become `blocked(draining)`
   with the same resume phase and ordinal" (`WORKFLOW-CONTRACT.md:438-439`). The reason is
   spelled `draining` per Q3 (`FR08B-B3-CONTRACT-READINGS-PROPOSAL-2026-09-22.md:403`). A
   fresh launch under drain returns `{:reject, :control_draining}` and stays `queued`.
4. **Allocation.** If `facts["allocation"]["available"]` is below the start units, return
   the exhaustion plan when an attempt is retained (R4a.01.o9). Otherwise return
   `{:reject, :allocation_unavailable}`, which is R4.04.o3's pre-intent denial. This is
   question O3.
5. **Otherwise** return the launch plan. It reuses the retained `attempt_id` (R4.04.o1,
   enforced by `open_attempt/2` at `kernel/executions.ex:155-161`) and passes
   `predecessor_effect_id` through to `create_effect`.

Anything the reducer itself refuses, such as `developer_already_running` while an `unknown`
start still holds its execution, comes out of the dry run as `{:reject, _}`. That covers the
"unknown possible start" leg of the acceptance trace (`REPAIR-PLAN.md:878-881`).

**Where each fact comes from, and what restates nothing:**

- **Pause and drain** exist only in the reducer's control entity
  (`FR08B-B3-CONTRACT-READINGS-PROPOSAL-2026-09-22.md:28-32`). `decide/3` reads
  `state["control"]` and declares the control singleton in `domain_reads`, so a control change
  before commit fails CAS: "an ordinary prestate read under CAS"
  (`fr08b-kernel-correction-design.md:131-136`). Needed because Gateway never runs the
  reducer (`gateway.ex:1289-1293`).
- **Pending cancel** is the ticket's `cancel_requested`, covered by the ticket's own read.
- **Root control, policy and allocation** are protected. `decide/3` copies identity and
  revision into operation inputs and `expected_revisions` (`control/`, `policy/`, `ledger/`;
  `record_codec.ex:350-357`) and uses `available` only to pick a plan. Enforcement stays
  protected: `reserve` refuses excess units (`protected_primitives.ex:1004-1007`), and
  `issue_claim` refuses stale revisions and inactive control (`:1406-1411`).
- **The infrastructure limit** is never read by `decide/3`. The protected discriminator
  derives it inside the transaction (`gateway.ex:1314-1326`, `protected_primitives.ex:332-352`).
- **Policy revocation and generation change (G)** stay NOT-KERNEL
  (`FR08B-B3-GAP-INVENTORY-2026-09-22.md:112`). The protected claim refuses the retry (Q5,
  `FR08B-PROTECTED-ITEMS-SPEC-2026-09-23.md:129-143`). `decide/3` only binds the revision.

**This supersedes the correction design's allocation discriminator**, required because
allocation "after settlement differs from the prestate the kernel saw"
(`fr08b-kernel-correction-design.md:137-142`). Under Q1 Reading A the successor is chosen
on the next command, after the refund committed, so the ledger is ordinary prestate under
`ledger/<id>` CAS. The readings left it open (`FR08B-B3-CONTRACT-READINGS-PROPOSAL-2026-09-22.md:447-451`); see O2.

## `domain_reads` vs `expected_revisions`: the four mismatches

These are the mismatches in `fr08b-subcommit2-reads-inventory.md:29-44`.

1. **Container.** `expected_revisions` is derived *from* `domain_reads`. Callers do not supply
   both. `Plan.expected_revisions(plan, facts)` maps each domain read to one key, then adds
   the protected-fact keys. Gateway checks that every declared read appears in the command's
   `expected_revisions` with the translated value, and refuses otherwise with
   `:domain_read_not_checked`. The check sits in `normalize_atomic_envelope/2`
   (`gateway.ex:589-616`), which is the one place where the command and the plan are both in
   hand. After that, `check_expected_revisions/4` CAS-checks every key (`:1874-1893`), so a
   declared read is always a checked read.
2. **Kind to namespace.** Each kind gets one fixed namespace: `ticket` →
   `foundry.ticket.v1`, `objective` → `foundry.objective.v1`, and `state` →
   `foundry.state.v1` with the entity id `control`. `state` is the kernel's global singleton,
   whose id is fixed (`kernel.ex:141-146`), which closes the missing `control` kind
   (`FR08B-B3-GAP-INVENTORY-2026-09-22.md:43-44`) without growing the vocabulary. `pm` stays
   unused until the PM lifecycle. The table exists twice, once in `Kernel.Plan` and once in
   `TransitionPlan`, which is the intended two-copy arrangement
   (`plan-binding-specification.md:50-53`). A test asserts that the two copies are equal. The
   names avoid `kernel-v1`, which crash fixtures already use
   (`test/support/durable_store_crash_fixture.exs:23`). The same table also lets replay
   rebuild a kernel envelope (`kernel/event.ex:54`) from a durable event: `entity_kind` comes
   from the namespace, and `entity_id` and `entity_revision` come from the projection.
3. **Encoding and revision numbering.** The key is `projection/` or `dependency/`, then
   base64url(namespace), then `/`, then base64url(entity_id). `projection/` is used when a
   projection in the plan writes the entity, and `dependency/` when the entity is only read
   (`gateway.ex:1947-1951`; the two resolve identically at `durable_store/authority.ex:105-109`).
   Revisions are stated in durable terms. A kernel entity at revision *r* ≥ 1 corresponds to
   projection revision *r* − 1. Kernel revision 0 (absent, or the untouched control in
   `State.new/0`, `kernel/state.ex:103-111`) corresponds to `"absent"`. This follows from
   `commit/4` setting the kernel revision to `entity_revision + 1` (`kernel.ex:222`) and the
   first projection write going from `-1` to `0` (`record_codec.ex:133-134`). It also gives
   event `entity_revision` = projection `revision`.
4. **The scalar.** `expected_domain_revision` is the kernel revision of the command's target
   entity, and the target is `domain_reads[0]`. Gateway requires it to equal that read's
   durable revision + 1 (absent counts as 0), or 0 when `domain_reads` is empty, which keeps
   the existing plan tests valid (`atomic_bundle_test.exs:1231-1232`). This makes the field
   redundant but checked. A field that is validated and never consulted is the defect
   recorded at `plan-replay-revalidation-design.md:77-85`, and deleting it would change stored
   plan digests.

Read sets per command:

| Command | Domain reads | Protected expected revisions |
|---|---|---|
| `launch_developer` | ticket (written), state (read only) | `policy/`, `control/`, `ledger/` |
| `settle_developer_nonstart` | ticket | none. `settle_claim` carries its own per-operation reads (`atomic_bundle_test.exs:851-861`) |
| `finalize_cancellation` | ticket | none |

## Testing

- **Row-driven.** A table keyed by clause ID, one row per outcome: R4.04.f3 ×3 (one refusal
  atom each), R4.04.o1–o3, R4a.01.o1/o3/o7/o8/o9, the drain, pause and cancel sentences
  quoted verbatim, R4.28.o1. Each row: prestate (via `test/support/kernel_harness.ex`, per
  `r4_no_direct_apply_test.exs:31-37`), command, facts, and `{:reject, atom}` or a plan shape.
  Clauses leave `@uncited`/`@partial` (`test/.../r4_coverage_test.exs:46-57, 237-295`),
  whose citation check verifies the quotes.
- **Oracle.** Every plan passes `TransitionPlan.validate/1`, in tests only; `Kernel.Plan`
  does not call it.
- **Substitution law** (`fr08b-kernel-correction-design.md:221-222`). For every
  alternative, bind against staged results and translate the bound durable events to kernel
  envelopes. Applying them to the prestate must equal that alternative's projections.
- **End to end through `Gateway.atomic_bundle/4`: yes, one test per plan shape.** The shapes
  are launch, settle below the limit, settle at the limit, drain block, exhaustion and
  cancel finalization. The seeding helpers from `atomic_bundle_test.exs:764-844` move to
  `test/support`. Each test then rebuilds kernel state from the committed durable events and
  compares it with the live post-state. The one after settle is the "restart after
  settlement but before redispatch" trace (`REPAIR-PLAN.md:881-883`): one owner, one
  ordinal, no live execution.
- **Red controls (EVIDENCE-TOOLS rule 1).** Each step check is spelled `require_*` for
  `bin/guard_mutation_sweep.exs` (`kernel.ex:135-137`) with a test that fails when it is
  neutralised. Plus: `control_changed(paused)` committed between `decide/3` and submit must
  yield `revision_conflict` (`gateway.ex:1885`); dropping one `expected_revisions` key must
  yield `:domain_read_not_checked`.

## Out of scope

- Developer result rows R4.05–R4.10: freeze, failure, blocked and malformed submissions.
  Their inputs are sealed results from the freeze and import worker (subcommit 4,
  `fr08b-kernel-correction-design.md:234`). See O4.
- Pre-intent denial for capacity, resources, profile or dependencies. That is FR-12
  (`REPAIR-PLAN.md:1014-1017`). The `{:reject, _}` shape already allows for it.
- Control and cancel *ingress* (`control_changed`, `cancellation_requested`), which is
  subcommit 5 (`fr08b-kernel-correction-design.md:235-242`). Tests commit
  `control_changed` through an existing slot (`transition_plan.ex:92`).
- The reviewer, which is subcommit 3, and PM, which is deferred (D2).
- The adapter that assembles envelopes and probes per-operation reads. That is O1, after
  FR-08B.
- Deleting the codec's terminal dispositions, and checking that a plan operation's `input`
  equals the staged operation (`gateway.ex:1391-1401` compares types only).

## Commit sequence

0. *(protected, needs O1)* `fix(foundry): the durable codec admits the kernel's lifecycle
   vocabulary`. Every `Kernel.Event.types/0` name goes into `@lifecycle_event_types`, with a
   test that the kernel set is a subset. `claim_effect` goes into
   `TransitionPlan.@operation_types`. Re-attest.
1. *(protected, needs O1)* `feat(foundry): gateway checks every domain read a plan declares`.
   This adds the namespace table, `:domain_read_not_checked`, the `expected_domain_revision`
   rule and a red control for each. Re-attest.
2. `feat(foundry): Kernel.Plan builds closed plans and derives expected revisions`. This adds
   the builders, id derivation, the dry run and the table-equality test. There is no
   command yet.
3. `feat(foundry): decide/3 settles a developer non-start (R4a.01)`. This adds both
   alternatives end to end, the restart trace, and the `kernel.ex:52` comment fix.
4. `feat(foundry): decide/3 plans the developer successor (R4.04, R4a controls)`. This adds
   the five ordered steps, the CAS race control, and end-to-end tests for launch, drain and
   exhaustion.
5. `feat(foundry): decide/3 finalizes a cancelled ticket (R4.28)`. This is generic, and
   subcommit 3 reuses it.
6. `test(foundry): cite the developer R4a clauses`. This moves clauses from
   `@uncited`/`@partial`.

Then comes subcommit 2's own review (`REPAIR-PLAN.md:268`).

## Open questions for the operator

- **O1.** Authorize commits 0 and 1 as protected maintenance on `record_codec.ex`,
  `transition_plan.ex` and `gateway.ex`. Without commit 0, only the below-limit settle and
  nothing else can commit.
- **O2.** Confirm that Q1 Reading A retires the "second discriminator primitive" of
  `fr08b-kernel-correction-design.md:137-142`, with allocation handled as a CAS-bound prestate
  read at the next launch.
- **O3.** When allocation is short, is it `exhausted` only for an attempt retained after a
  non-start (R4a.01.o9), and pre-intent denial that stays `queued` for a fresh launch
  (R4.04.o3)? The recommendation is yes.
- **O4.** Do developer rows R4.05–R4.10 belong to subcommit 4, as proposed, or to
  subcommit 2?
- **O5.** The contract names the per-role limit `launch_non_start_limit`
  (`WORKFLOW-CONTRACT.md:419`), and `create_effect` enforces it by that key with a default of
  0 (`protected_primitives.ex:1257, 3189-3190`). The discriminator reads
  `infrastructure_attempt_limits[role]` instead (`:343`). If they disagree, a retry that the
  discriminator ruled below the limit is refused at `create_effect`. Which key is
  authoritative? Fixing this is protected maintenance, and `decide/3` depends on the answer
  only through its end-to-end tests.
