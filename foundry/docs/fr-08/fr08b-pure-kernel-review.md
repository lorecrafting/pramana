# FR-08B pure domain kernel independent review — BLOCKER

Date: 2026-09-20

Reviewer: `/root/fr08b_pure_kernel_review`, independent of implementation

Verdict: **BLOCKER.** The candidate is deterministic on its maintained happy paths and
contains no direct I/O, clock, RNG, process, Git, configuration or provider calls. It is
not a total or guarded replay kernel, and its R4/R4a model loses required custody and
terminal evidence. A safe Gateway adapter would have to duplicate lifecycle validation,
reinterpret arbitrary state snapshots and predict protected post-operation facts. That is
a redesign of the claimed pure contract, not the deferred mechanical adapter slice.

## Exact subject and scope

| Item | Identity |
|---|---|
| Candidate commit | `a00deccbf4717ed6c3e4835bbdefed457dd6d637` |
| Candidate tree | `21ec8b3c1cc64c490b325506682754bfa2cd7db5` |
| Parent/main | `057f2902580235d844679c43ece571056b60b8a5` |
| Branch/worktree | `repair/fr08b-pure-kernel` / `/private/tmp/pramana-fr08b-kernel.bYbL8q` |
| Changed implementation | `workflow/kernel.ex`, `workflow/kernel/state.ex` |
| Changed maintained test | `workflow/kernel_test.exs` |

I read the repository/shared workflow, Foundry route and strategy summary, Elixir
conventions, workflow-contract command protocol and R2/R4/R4a/R5, FR-08B repair-plan
acceptance, the command-ingress inventory, the integrated FR-08A atomic-bundle boundary,
and all three changed files. This review changes no implementation, runtime, Gateway,
Coordinator, daemon, provider, deployment or ticket status.

The [review probes](fr08b-pure-kernel-review-probes.exs) deliberately assert the observed
bad behavior. Their green result means all eleven counterexamples reproduced.

## Blockers

### B1 — `apply/2` is an unrestricted snapshot installer, not a guarded event reducer

`apply/2` accepts any nonempty event type and delegates every event to generic `changes`
(`kernel.ex`, lines 78–89 and 1260–1299). A ticket change needs only a matching ID and one
listed phase. There is no closed event vocabulary, event-to-entity/change relationship,
source-state guard, command/actor/policy binding, sequence/revision check, duplicate guard
or nested ticket/attempt/execution schema. The event can therefore create an `integrated`
ticket from empty state. Applying an older snapshot after a newer event silently moves a
ticket backwards.

`State.valid?/1` validates only the outer containers and four control fields
(`state.ex`, lines 14–39). It accepts extra top-level protected-looking data and arbitrary
nested values. A state with integer ticket value passes `valid?/1`, then `decide/3` raises
while evaluating a source guard. Thus the public decision function is not total over the
state its own validator declares valid.

The maintained protected-fact test rejects only a blacklisted key. It does not test the
authority-significant state transition itself: the probe's unknown event creates an
integrated projection without any candidate, checks, review, claim or ref receipt. R3
still prevents that label from moving the protected accepted ref, but R4 replay and the
domain projection are false, and a fixed verifier cannot safely validate this generic
snapshot language without becoming a second lifecycle reducer.

### B2 — review/check/correction custody violates R4 rows 7, 11, 15–17 and 26

`developer_closed/3` emits an event containing the unchanged ticket; it records no closed
execution or durable closure fact (`kernel.ex`, lines 1104–1115). `start_checks/3` does
not require developer closure and changes the attempt to `checking` without creating a
check execution (`kernel.ex`, lines 523–537). After that transition, the check
`request_effect` guard requires `candidate_frozen`, so the documented row-11 route has no
schedulable check path (`kernel.ex`, lines 1158–1163). The maintained complete-lifecycle
test skips developer closure and check launch, masking both defects.

A reviewer request creates a `pending` execution, but an approval is accepted immediately
without a launch receipt, review receipt binding or sealed-stream fact. `reviewer_closed`
then trusts an ordinary observation string and advances to `ready_to_integrate` while the
reviewer execution remains `pending` (`kernel.ex`, lines 613–685). Exact candidate ID
equality alone is not verified close or exact check/review custody.

`changes_requested` queues developer work before reviewer close or cleanup and terminalizes
the current attempt (`kernel.ex`, lines 639–654). The next developer admission replaces
that attempt without appending it to `prior_attempts` (`kernel.ex`, lines 395–413). The
reviewer execution, candidate and terminal correction evidence disappear. The same loss
occurs after check failure, no-result failure and superseded-base paths. Reusing an
execution/attempt ID can similarly overwrite map entries rather than preserve immutable
identity history.

Finally, `steer:block` accepts every nonterminal source, requires no protected control fact
and terminalizes an integrating attempt (`kernel.ex`, lines 960–979). That is not the
public blocked/partial developer-result row and contradicts the rule that unlisted
source-state transitions reject without mutation.

### B3 — R4a dispositions do not cross current controls, allocation or generations

The developer/reviewer non-start decision receives only the ticket, attempt and supplied
ordinal/limit/allocation. It never sees global pause/drain state and does not act on the
ticket's cancel control (`kernel.ex`, lines 744–773 and 840–881). A developer launch that
settles `non_started` after drain commits returns the ticket to `queued`, whereas R4a
requires `blocked(draining)` with the retained owner and ordinal. Cancellation finalization
and ledger-generation eligibility are likewise absent from this ordering point.

PM non-start ignores allocation entirely and queues below the infrastructure limit even
when the supplied current allocation says `exhausted` (`kernel.ex`, lines 884–923). It
also does not cross pause, drain, cancel or generation change. Reviewer budget exhaustion
is collapsed to `blocked(reviewer_budget)` without representing the protected-policy
choice between blocked and exhausted.

The kernel compares only `settlement == outcome`; it does not bind the claim, receipt,
role, work owner, effect, predecessor or infrastructure generation to the execution it is
settling. The retained `settlement_binding` is a selected set of caller-supplied IDs. A
future adapter would have to implement those semantic identity checks itself, contrary to
this slice owning role-specific transitions and distinct identities.

### B4 — the contract cannot be mechanically composed with the integrated atomic API

The integrated `RecordCodec` command contains `expected_revisions`. The pure kernel's
exact command validator omits that required field and rejects the canonical command as an
extra key (`kernel.ex`, lines 1233–1244). Its events use
`{schema_version,event_id,type,recorded_at,changes}` with unrestricted types; the Gateway
accepts the versioned event/projection carrier shape and closed codec vocabulary. This is
not merely a missing call site: the adapter would have to invent semantic event types,
projection revisions and transition guards from full-state snapshots.

There is also a timing mismatch for R4a. `decide/3` requires the protected settlement
outcome and root-generated infrastructure ordinal before it can produce the domain event
(`kernel.ex`, lines 690–773). `Gateway.atomic_bundle/4` receives the proposal and protected
operations together, then derives and persists that ordinal while staging the protected
operation inside its transaction. It does not call a reducer after staging. Predicting the
fact in an adapter, or accepting an unbound caller copy, loses the protected/domain
binding that FR-08A was added to guarantee.

The pure contract must define facts available before decision or a versioned root-bound
decision carrier that the existing atomic boundary can validate. The adapter cannot safely
solve this by stripping canonical fields and translating arbitrary snapshots.

### B5 — the maintained matrix evidence is declarative, not exhaustive

`guard_matrix/0` is a list of 28 labels. The test proves that the integers 1–28 occur,
not that each row's guard and disposition is implemented. The unlisted-state mutation test
varies only five commands. The role/control tests omit the R4a cross product of pause,
drain, cancel, allocation exhaustion, infrastructure exhaustion, policy revocation,
generation change and restart. This allowed the counterexamples above while all 17
maintained tests passed.

## Minimal correction required

1. Replace generic snapshot `changes` with a closed, versioned semantic event vocabulary.
   Validate the exact payload and nested state shape for each event, enforce its legal
   source/owner/revision, and reject duplicate or out-of-order replay. `decide/3` and
   `apply/2` must return errors rather than raise for every malformed term.
2. Model durable execution result/stream/closure facts and exact candidate/check/review
   custody. Checks require verified developer closure; review advancement requires the
   matching reviewer settlement and verified close. A correction/rebase/failure keeps the
   terminal predecessor append-only and admits a distinct fresh attempt only after required
   workers close.
3. Evaluate R4a settlement against current pause/drain/cancel, allocation, policy and ledger
   generation facts for developer, reviewer and PM. Bind the complete protected settlement
   identity to the stored execution and preserve unknown holds. Apply role-specific block,
   exhaust, resume and cancellation dispositions before any replacement is eligible.
4. Publish an adapter-safe versioned boundary: accept the canonical command including
   `expected_revisions`; make event/projection conversion a documented bijection; and use
   only protected facts that can be root-bound in the same atomic transaction. Do not make
   the adapter predict post-operation ordinals or duplicate lifecycle guards.
5. Replace label/count tests with executable rows for all 28 R4 guards, all three R4a roles
   and their control/generation cross product, terminal/unlisted mutations, malformed-state
   totality and replay permutations.

## Deferred parent-ticket work, not blockers by itself

The candidate was intentionally only the pure-kernel slice. Gateway persistence wiring,
every CLI/RPC/Coordinator/agent/PM ingress migration, public RPC repair, full protected R5
arithmetic, restart/reopen integration and removal of legacy mutation paths remain later
FR-08B slices. No blocker above is based merely on those files being absent. The blockers
are that the pure state/decision/event contract cannot preserve the required facts or be
safely adapted later without changing its core shapes and semantics.

## Positive findings

- Repeating `decide/3` with the same maintained valid inputs is deterministic, and no
  changed production file calls I/O, clock, RNG, configuration, process, Git, Gateway or
  provider APIs.
- `supported_commands/0` lists all twelve codec command names, and each reaches an explicit
  result in the maintained smoke table.
- Normal decisions retain opaque authority identifiers rather than ledger balances.
- Accepted/rejected/blocked are separate decision dispositions, and rejected/blocked
  maintained paths emit no domain event.

These positives do not establish the guarded lifecycle or replay contract.

## Reproducible checks

All successful commands used Elixir 1.20.3 / OTP 29.0.5, `MIX_ENV=test`, an isolated
`MIX_BUILD_PATH`, existing local dependencies and `TMPDIR=/private/tmp`.

| Check from `foundry/` | Outcome |
|---|---|
| `mix test --no-start test/pramana_foundry/workflow/kernel_test.exs --seed 92040` | Exit 0; 17 passed |
| `mix test --no-start test/pramana_foundry/durable_store/atomic_bundle_test.exs test/pramana_foundry/workflow/kernel_test.exs --seed 92042` | Exit 0; 30 passed |
| `mix run --no-start docs/fr-08/fr08b-pure-kernel-review-probes.exs` | Exit 0; 11 counterexamples reproduced, fixed seed 92041 |
| `mix compile --warnings-as-errors` | Exit 0 |
| Candidate-file `mix format --check-formatted` and `git diff --check` | Exit 0 |
| Repository `elixir bin/check_docs.exs` | Exit 0; 80 passed |
| Static forbidden-call scan of the two production files | No matches |

An exploratory unscoped full suite with `--no-start` was stopped after unrelated tests
that require the application failed with missing Coordinator/Supervisor processes. It is
not reported as candidate evidence. No live provider, daemon, listener, external effect,
deployment, activation or runtime mutation was performed.
