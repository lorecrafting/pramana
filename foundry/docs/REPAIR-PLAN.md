# Foundry repair plan

Created 2026-09-12 from [the audit](AUDIT-2026-09-12.md) and the operator's agreed
contract. This is an external Markdown backlog; it does not depend on Foundry's
admission, state tracking, or agents. No repairs are marked complete by creating it.

## How to execute this plan

Use one implementation session per ticket. Keep this file as the authoritative
backlog and the audit as dated evidence. Record decisions in versioned design notes,
not only in chat. Read the relevant audit findings and current source before starting:
audit line references and reproductions may become stale as repairs land.

Start with FR-01. Then finish the other ready containment tickets and FR-06 before
starting the dependent workflow redesign. A ticket's dependencies are necessary,
not evidence that its design has already been decided. Rows marked **blocked** need
their dependencies completed and their interface assumptions revalidated. Split a
ticket further if its investigation exposes independently reviewable changes; keep
the original ID as the parent and preserve its acceptance obligations.

Do not dispatch this whole backlog to simultaneous agents. The early work overlaps
in Coordinator, CLI, startup and state contracts. Keep one implementation owner for
those files. Independent work can run concurrently after contracts stabilize, with
explicit file/interface ownership; this plan does not itself launch agents.

### Product and authority contract

- One operator, one machine, Pramāṇa. Retain a standalone OTP application.
- Implement supervisor repairs, transport, persistence, orchestration, validation and
  fixtures in Elixir wherever technically possible. A non-Elixir process is acceptable
  only when the contract inherently crosses that boundary (for example Git, OS process
  acceptance, or the existing Herdr provider CLI), and its necessity must be recorded.
- Lean autonomous execution, including Foundry merge and activation once the
  acceptance and deployment protocols are proved. Temporary containment must name
  the capability it suspends and the ticket that safely restores it.
- Steering owns durable intent, priorities and authority. PM elaborates broad or
  ambiguous objectives; already specified work can go directly to admission.
- Foundry cannot broaden spending, enable paid fallbacks, weaken mandatory gates,
  or increase its authority without explicit operator steering.
- Automatic execution uses explicitly permitted subscription profiles only.
  OpenRouter/DeepSeek paid use remains manual. No eligible profile means affected
  work waits with a reason, rather than consuming another billing channel.
- OMP remains the harness and Herdr the initial presentation backend. A pane is
  optional presentation; its lifetime cannot establish workflow success or failure.
- Ticket, attempt, execution/session, pane, artifact, review, integration and
  deployment identities have separate lifetimes and explicit relationships.
- Acknowledged decisions survive restart. Uncertain external outcomes reconcile
  before retry. Agent assertions do not establish acceptance.

### Shared completion requirements

Each implementation must include its relevant executable acceptance evidence,
updated operator/developer documentation, and a status entry here and in
[`docs/PLAN.md`](../../docs/PLAN.md). Record the candidate revision, test commands,
results and remaining limitations. Required review evaluates the exact candidate.
Changing it after review requires renewed validation appropriate to the change.

The [audit probes](audit-2026-09-12/probes.exs) assert **broken behavior**. Use them
to understand a defect, then add regression tests for the required behavior to the
normal suite. Do not preserve a bug just to keep a characterization probe passing.
Keep the original audit as a dated record; link new evidence from ticket completion.

Use isolated temporary state, Git repositories and owned processes. Tests must not
truncate shared logs, broadly close panes, or launch billed fallback profiles.
Model-free tests should cover deterministic contracts. A bounded real subscription
smoke is needed where mocks cannot establish harness behavior; record provider,
profile, limits and observed usage, including unknown values. Existing authorization
permits isolated testing, but does not expand spending or governing policy.

No ticket may claim that the entire repair is complete based on component tests.
FR-22 owns final lifecycle acceptance, while earlier tickets supply the tests it uses.

### Model and context strategy

Recommended working default: **Sol, medium** for bounded ticket implementation,
test writing, documentation and elaborating downstream tickets against settled
contracts. This is an engineering recommendation, not a Foundry model benchmark.
The [official Sol reference](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
documents medium reasoning support; it does not prove a success rate for this repo.

Use Sol-high for routine independent review and Astra-medium for the first review of
authority, durable storage, recovery, budgets, Git integration and activation work.
Reserve Astra-high for FR-22's final lifecycle gate, a concrete cross-cutting design
contradiction, or a candidate that repeatedly fails in materially different ways. Narrow
rechecks after a reviewer has isolated one defect may use Sol-medium. Escalate when a
ticket reveals an unresolved contract or repeatedly fails meaningful tests; do not keep
retrying the same implementation or make every documentation edit an expensive review.
Model selection does not replace deterministic gates or independent review.

Save this plan and decisions before clearing context. A fresh implementation session
needs project instructions, the assigned ticket, shared contracts, relevant findings,
dependency completion evidence, and current source—not the entire audit conversation.
Read more when an interface crosses the assigned scope. Switching models alone is
not a reason to discard useful context.

Suggested fresh-session instruction:

> Implement FR-01 from foundry/docs/REPAIR-PLAN.md. Read project instructions and
> the plan's shared contract, then its referenced audit findings and current source.
> Confirm dependencies and preserve unrelated working-tree changes. Implement only
> this ticket and its necessary tests/docs. Report evidence and limitations, update
> the backlog, and stop before starting another ticket. If the agreed architecture
> proves inadequate, document the concrete decision needed instead of silently
> changing governing policy.

Substitute the next ready ID. Before ending each session, leave a short completion
or continuation entry under that ticket with files, decisions, tests and exact next
step. FR-06's R4a correction and exact revision-3 inputs passed
[focused independent verification](fr-06/r4a-focused-review.md). This closes the
design gate only; every routed implementation obligation remains open.

## Dependency inventory

**Ready** means specified enough to begin investigation and implementation; it does
not mean a repair has been made. **Blocked** means wait for listed dependencies.

| ID | Deliverable | Depends on | Status | Findings |
|---|---|---|---|---|
| FR-01 | Remove automatic paid execution paths | — | **Complete: reviewed static containment** | F01 |
| FR-02 | Transport CLI arguments as inert data | — | **Complete: reviewed inert transport** | F06 |
| FR-03 | Fence startup and fail closed on legacy persistence errors | — | **Complete: reviewed containment** | F14, F02 |
| FR-04 | Restrict cleanup to verified owned resources | — | **Complete: reviewed containment** | F05, F23 |
| FR-05 | Contain acceptance and mutable-source activation bypasses | — | **Complete: reviewed containment** | F03, F04, F12, F13, F22 |
| FR-06 | Decide durable workflow and authority contracts | — | **Complete: focused R4a design verification passed** | F02, F07–F09, F13, F22 |
| FR-07 | Implement durable store and compatibility boundary | FR-03, FR-06 | **Reviewing corrected candidate `b88918d`** | F02, F20, F21 |
| FR-08 | Unify command transitions and replay | FR-07 | Blocked | F07, F16 |
| FR-09 | Prove OMP execution and presentation contract | FR-01, FR-04, FR-06, FR-15a | Blocked | F08–F10 |
| FR-10 | Persist owned effects and reconcile executions | FR-08, FR-09 | Blocked | F08, F09 |
| FR-11 | Close correction, timeout and review lifecycles | FR-10 | Blocked | F09, F10, F16 |
| FR-12 | Wire admission, resource scheduling and review capacity | FR-08, FR-10, FR-11 | Blocked | F04, F11, F15 |
| FR-13 | Verify artifacts, candidate scope and check receipts | FR-02, FR-05, FR-10, FR-12, FR-15a, FR-15 | Blocked | F03, F04, F16 |
| FR-14 | Perform serialized recoverable Git integration | FR-13 | Blocked | F12 |
| FR-15a | Prove protected verifier and execution isolation | FR-02, FR-03, FR-05, FR-06, FR-07, FR-08 | Blocked | F01, F04, F06, F13, F14, F22 |
| FR-15 | Implement durable steering and optional PM planning | FR-08, FR-12, FR-15a | Blocked | F15, F22 |
| FR-16 | Implement bounded subscription switching | FR-01, FR-09, FR-12, FR-15 | Blocked | F01, F11 |
| FR-17 | Activate immutable accepted builds and recover failures | FR-05, FR-07, FR-14, FR-15, FR-21 | Blocked | F13, F22 |
| FR-18 | Make status, board and telemetry reflect real state | FR-08, FR-10, FR-11 | Blocked | F17, F18 |
| FR-19 | Bound storage and make offline maintenance safe | FR-07, FR-18 | Blocked | F20, F21 |
| FR-20 | Reconnect constrained improvement proposals | FR-15, FR-18 | Blocked | F19 |
| FR-21 | Establish independent Foundry CI and build provenance | FR-01, FR-04, FR-05 | **Reviewing frozen candidate `85a7449`** | F23, F24 |
| FR-22 | Prove full lifecycle and reconcile operating docs | FR-11–FR-21 | Blocked | F01–F24 |

## FR-06 sequencing and supersession

The [workflow contract](WORKFLOW-CONTRACT.md) governs dependent tickets. Original
acceptance paragraphs below remain obligations; these decisions refine mechanisms,
never waive a failing case. No containment is claimed installed by this plan.

| Work class | Tickets / disposition |
|---|---|
| Immediate containment | FR-01 authorized profiles; FR-02 inert transport; FR-03 exclusive startup plus checked legacy persistence; FR-04 owned cleanup; FR-05 disable unsupported acceptance/integration and source watcher activation |
| Superseded interim mechanisms | FR-02 general RPC replaced by FR-15a scoped protocol; FR-03 legacy append patches replaced by FR-07/08 atomic kernel; FR-05 integration/activation suspension restored only by FR-13/14/17 evidence |
| Do not build | A second production journal backend; parallel live/replay reducers; pane-driven recovery; both correction resume and relaunch; synthetic acceptance; raw-source rebuild watcher; custom compaction before choosing storage |
| Durable foundation | FR-06 independent review → FR-07/08 store/kernel. FR-15a uses FR-07/08 store/verifier contracts to establish isolated execution before the later PM loop |
| Dependent execution | FR-09 under isolation → FR-10 recovery → FR-11 lifecycle → FR-12 scheduling → FR-15 durable steering; FR-16 bounded subscription switching |
| Dependent delivery | FR-13 verified evidence → FR-14 protected ref promotion → FR-17 immutable runtime activation; FR-21 supplies build provenance before activation |
| Operational closure | FR-18 projections; FR-19 retention/offline relocation; FR-20 constrained improvement; FR-22 scenario acceptance and documentation |

FR-15a is a child of the existing FR-15 authority work, not an additional audit finding.
V2 adds FR-07/08 dependencies because its real protected claim/ledger tests need their
store and transaction contracts. Initial operator policy, reset/cancel primitives and
claim predicates are FR-08 interfaces exercised under FR-15a isolation; the optional
PM loop and full steering UX remain FR-15. FR-09 can use bounded preconfigured assignments
and reservations without waiting for FR-12 scheduling/FR-16 switching; live orchestration
still cannot bypass those later gates. Host provisioning and installed OMP compatibility
are explicit FR-15a/09 prerequisites, not implied available because the graph is acyclic.

V2 supersedes the **design** of an operator-only workflow kernel: FR-17 restores autonomous
kernel repairs behind the fixed verifier/activation root. No runtime-only demonstration
may stand in for that capability in FR-20/22. FR-05 remains temporary containment until
the restored paths pass their original and v2 acceptance obligations.
FR-07 can build the store contract in isolated tests before controller provisioning;
production authority and execution remain gated by FR-15a. FR-21's early CI need not wait
for the entire lifecycle; expand it as dependent implementation lands.

### Audit acceptance obligations retained

This matrix is a routing checksum, not a replacement audit. Each referenced finding's
full repair/acceptance obligation and the ticket acceptance text remain binding.

| Finding | Owners | Required evidence retained |
|---|---|---|
| F01 | FR-01, FR-09, FR-15a, FR-16 | Every autonomous role, explicit subscription eligibility, quota/unknown/cooldown/restart; no paid fallback |
| F02 | FR-03, FR-07 | Failed writes cannot acknowledge or launch; corrupt/torn/oversize/versioned history never resets; atomic recovery |
| F03 | FR-02, FR-05, FR-13 | Real wrapper preserves raw identity; stale/wrong-role/candidate and fabricated checks rejected |
| F04 | FR-05, FR-12, FR-13, FR-15a | Common admission, protected mandatory gates, actual ancestry/full diff, isolated independent reviewer |
| F05 | FR-04, FR-10 | Foreign/recycled/unknown identities preserved, verified owned cleanup |
| F06 | FR-02, FR-15a | Literal actual-wrapper transport; no general evaluation authority for agents |
| F07 | FR-08, FR-11, FR-17 | All controls/verdicts/PM mutations replay identically; artifacts/budgets retained; stale completion harmless |
| F08 | FR-09, FR-10 | Reconcile before retry; adopt owned surviving work and reviewer continuation; unknown blocks |
| F09 | FR-10, FR-11 | Role/execution IDs, monitors, stale/duplicate/late timers, hard-kill recovery |
| F10 | FR-09, FR-11 | Distinct timeout, single correction strategy, CLI/auto cleanup, role retry accounting |
| F11 | FR-12, FR-16 | Actual scheduler, capacity/review progress, persistent resources, assignment environment, no capacity retry charge |
| F12 | FR-05, FR-14 | Actual refs/trees, responsive async gates, changed base/conflict/concurrent/crash reconciliation |
| F13 | FR-05, FR-15a, FR-17, FR-20, FR-22 | Watcher disabled, immutable accepted build, real start/stop/health and compatible rollback |
| F14 | FR-03, FR-10, FR-15a | Two OS owners, effect-free inspection, stale PID and old-owner effects fenced |
| F15 | FR-12, FR-15 | Durable steering, conditional PM, full admitted spec, no invented authority |
| F16 | FR-08, FR-11, FR-13 | Public blocked/partial schema and lifecycle, explicit partial rescope; no accidental retry |
| F17 | FR-18 | Board/status canonical projection; unavailable/corrupt is not empty healthy |
| F18 | FR-18 | Real producers validate and correlate; resource/usage unknowns explicit |
| F19 | FR-20 | Classifiers consume emitted schemas; deduplication/admission retry/resolution survives restart |
| F20 | FR-07, FR-18, FR-19 | Bounded queries, capacity health, serialized retention/backup/compaction; diagnostics distinct from authority |
| F21 | FR-07, FR-19 | Offline explicit maintenance, strict paths/journal, unknown space/digest/live handles block, verify copy before removal, collision-safe rollback |
| F22 | FR-15a, FR-15, FR-17, FR-18 | Enforced OS/capability boundary, policy provenance, listener inspection, telemetry/crash redaction |
| F23 | FR-04, FR-21, FR-22 | Owned isolated non-vacuous tests, independent CI, real lifecycle/restarts and bounded provider smoke |
| F24 | FR-21, FR-22 | Explicit dependency/executable provenance; retired diagnostic/parity paths resolved; docs match reality |

FR-22 reconciles every row with actual revisions/evidence and remaining gaps. The
storage spike supplies design evidence only; it closes none of these findings.

## Tickets

### FR-01 — Remove automatic paid execution paths

**Outcome:** Every autonomous developer, reviewer and PM launch must use an explicitly
configured subscription profile; missing or exhausted eligibility yields no launch.

**Scope:** Trace AgentServer defaults, Tick, reviewer launch, configuration and all
fallback callers. Add a common launch eligibility check and explicit blocked reason.
Do not guess subscription entitlement from a model name. Keep manually selected paid
execution distinct from automatic routing. Record how temporary configuration feeds
the later protected policy contract.

**Acceptance:** Exercise every autonomous role with absent configuration, an allowed
subscription profile, a paid profile and a quota failure. Assert captured launch argv
and billing/profile selection, and zero launches for disallowed cases. No hidden
OpenRouter default survives. Existing manual paths require explicit invocation.

**Excludes:** Dynamic switching and benchmarking; FR-16 owns switching.

### FR-02 — Transport CLI arguments as inert data

**Outcome:** User text reaches the daemon literally, without becoming Elixir source.

**Scope:** Replace wrapper interpolation with a fixed RPC entry point and an inert,
validated payload transport. Enumerate command types and reject unknown shapes.
Audit the other executable entry points for equivalent interpolation.

**Acceptance:** Run the actual wrapper boundary with quotes, backslashes, newlines,
Unicode, `#{1+1}`, and malformed payloads. Assert exact round-trip values, explicit
errors, and no expression evaluation. Preserve useful command exit statuses.

**Excludes:** A new remote API or distributed control protocol.

### FR-03 — Fence startup and fail closed on legacy persistence errors

**Outcome:** One runtime owns a state directory; inspection cannot start orchestration.

**Scope:** Wire fencing into actual startup before any mutation. Separate daemon,
read-only CLI/board and offline maintenance startup. Define stale-owner recovery
without deleting a live owner's lock. Check that effectful children remain off in
inspection paths even when tick scheduling is disabled.

**Acceptance:** Two OS processes contend for the same isolated state directory; only
one writes or launches. Read-only commands cannot start Coordinator/Improver effects.
Kill the owner and prove defined recovery, including a misleading stale PID case.

**Containment addition (FR-06):** Check every authoritative legacy append before success
or effects; persistence/load/unsupported-version errors enter explicit recovery mode.
Do not translate unreadable history to `[]`. If a legacy multi-write path cannot provide
an honest acknowledgment, disable that path until FR-07/FR-08. Test failing append and
load through public commands as well as startup; assert no acknowledged mutation or
launch after failure. This closes the immediate F02 gap without repairing two reducers.

**Excludes:** Storage format redesign, delivered by FR-07. The legacy append patch is
superseded by SQLite transactions, but writer fencing and effect-free clients remain.

### FR-04 — Restrict cleanup to verified owned resources

**Outcome:** Recovery and test scripts can close only resources they created or whose
persisted ownership has been positively verified.

**Scope:** Remove CWD-based ownership inference and hard-coded pane exceptions from
destructive paths. Require backend identity checks; uncertainty leaves a visible
unresolved resource. Replace broad recovery-test cleanup with isolated test ownership.

**Acceptance:** Foreign panes in the same temporary directory survive cleanup;
recycled pane/process identifiers are not killed; missing identity causes no deletion;
owned resources close successfully. Test cleanup also preserves unrelated state logs.

**Excludes:** Full restart reconciliation, delivered by FR-10.

### FR-05 — Contain acceptance and mutable-source activation bypasses

**Outcome:** Unverified submissions cannot be promoted, and editing source cannot
activate a new Foundry runtime.

**Scope:** Reject incomplete artifact identities rather than synthesize current ones;
remove synthetic review and permissive production Git-check bypasses. Prevent the
existing memory-only integration path from reporting successful acceptance. Disable
raw-source watcher activation until FR-17 supplies the accepted-build protocol. Make
these temporary restrictions visible in commands and docs with restoration ticket IDs.

**Acceptance:** Stale/incomplete artifacts and auto-approve requests fail explicitly;
missing Git evidence cannot advance accepted state; editing a watched source file
cannot rebuild/restart the runtime. Read-only inspection remains usable. Tests prove
restrictions through real public command paths, not only validator calls.

**Excludes:** Complete evidence validation, real integration and safe autonomous
activation: FR-13, FR-14 and FR-17 restore these capabilities.

### FR-06 — Decide durable workflow and authority contracts

**Outcome:** Versioned design notes settle the interfaces needed by downstream tickets.

**Scope:** Specify entity IDs, command/event/result schemas, legal transitions,
idempotency, commit/ack boundaries, unknown outcomes, budget ownership and deterministic
replay. Define operator policy provenance and the enforcement boundary outside candidate
control. Explicitly address agents running as the operator's OS user: repository
conventions alone cannot protect governing files or an unrestricted RPC channel.

Run a small storage conformance spike comparing a transactional local store with a
repaired journal against the audit's required failure cases. Select the smallest
adequate option; event sourcing does not require JSONL. Define schema migration and
rollback compatibility. Record the evidence and tradeoffs; do not build both backends.

**Acceptance:** Transition table includes rejection, blocking, corrections, exhaustion,
cancel/drain and PM proposals. Effect protocol identifies each ambiguous crash boundary.
Storage decision records tested and untested failure cases. Authority design states
what a candidate can and cannot mutate and how enforcement is achieved. Downstream
interface changes are reflected in this plan. Focused independent design review finds
no unresolved contradiction in these contracts before FR-07 starts.

**Decision/evidence — 2026-09-12:** [Workflow contract](WORKFLOW-CONTRACT.md) selects
SQLite WAL with checked transactional decisions/projections/intents, one pure kernel,
fresh-attempt corrections, explicit unknown effects, fast-forward exact-candidate
integration, and a protected controller outside candidate execution authority. The
[storage experiment](fr-06/storage_spike.py) and [results](fr-06/storage-results.json)
record observed crash/deduplication/writer/capacity cases and untested durability limits.
No runtime implementation or provider invocation occurred.

**Independent review — 2026-09-12, v1 (historical):**
[FR-06 design review](FR-06-DESIGN-REVIEW.md) recorded verdict **not ready**, R1–R5.
The original manifest matched before the documented plan-status edits. The review and
its reviewed hashes remain unchanged; the current manifest now identifies revision v2.

**Revision v2 — 2026-09-12:** [Response and dispositions](fr-06/review-response-v2.md)
revises claim/issue ordering, isolated authentication, autonomous kernel activation,
legal lifecycle/cleanup and conserved budget generations. It also settles encoding,
revision read sets, lost-reply lookup order, projection authority and routing. The agreed
product/authority contract above is unchanged. Protocol arguments are design evidence;
OS/OMP/fault/activation proof remains in implementation acceptance. R1–R5 are addressed
for independent re-review, not certified closed. FR-07 stays blocked. Verify the current
[manifest](fr-06/manifest.json) and [verification record](fr-06/verification.md).

**Independent v2 re-review — 2026-09-12:** [Review v2](FR-06-DESIGN-REVIEW-V2.md)
verified the supplied manifest digest and all 13 input hashes. Verdict: **ready after
specified corrections**. R1/R2/R3/R5 are resolved at design level; R4a remains: map
proved developer/reviewer launch non-start into explicit domain retry/block/attempt
transitions, distinct from capacity denial, crash/timeout and unknown start. Preserve
review candidates and role accounting, and add the corresponding acceptance traces.
Check that focused correction and refreshed input hashes before opening the design gate.
FR-07 remains blocked on R4a and FR-03; implementation acceptance is still deferred.
The v2 manifest is retained unchanged; this status edit intentionally changes this
file's hash. Neither the proposal nor historical review was silently repaired.

**Revision v3 — R4a correction proposed, 2026-09-12:**
[Response v3](fr-06/review-response-v3.md) adds only launch-non-start domain recovery.
Developer non-start retains its active attempt for bounded retry; reviewer non-start
retains the frozen candidate and reviewer ownership. Pre-intent waiting, proved non-start
and unknown possible start have separate outcomes. Retries require the R1 predecessor and
quiescence proof, one-time R5 settlement and a finite infrastructure allowance independent
of refunded process-start units. PM and other launch roles follow the same rule, with
pause/drain/cancel/generation/restart behavior explicit. R1/R2/R3/R5 are unchanged.
FR-07 remains blocked pending focused independent verification and FR-03.

**Focused independent verification — 2026-09-12:**
[R4a review](fr-06/r4a-focused-review.md) verified the revision-3 manifest digest
`27e8315697ad84db96dfbcf985f2055014b3065c91561c5c6cba7067d307dd38`
and every entry, then returned **PASS**. R4a is resolved at design level without
reopening R1/R2/R3/R5. Review SHA-256:
`51b40e94e097ceb9de581901ca7187d1ace8593907718f924b6a0d910861f32f`.
This closes FR-06's design gate, not any implementation finding. FR-07 remains
blocked on FR-03.

**Excludes:** Multi-user services, generic adapters, implementation of the full kernel.

### FR-07 — Implement durable store and compatibility boundary

**Outcome:** Accepted decisions and effect intents are durable; corrupt authority cannot
silently become an empty workflow.

**Scope:** Implement the [FR-06 contract](WORKFLOW-CONTRACT.md): SQLite WAL/FULL via a
pinned in-process Elixir binding, separate command/event/projection/intent tables,
writer integration, checked commits,
version validation and explicit recovery mode. Provide an offline import of current
history that preserves originals, reports invalid records and cannot silently drop
acknowledged work. Keep diagnostics separate from authoritative history.

**Acceptance:** Crash before/after commit and before reply; retry the same command;
inject write/full-disk errors, torn input and unknown versions; import history larger
than the current reader limit. Assert the documented durable outcome and fail-closed
behavior. Prove transactional state/event/intent consistency and migration rerun safety.

**V2 review acceptance refinement:** Implement the protected SQLite write gateway separately from the isolated, updatable
kernel. Prove atomic command/event/projection/claim/ledger rows, foreign-key and uniqueness
failures; no candidate SQL access. Retain every untested storage case from review v1,
including real binding/write/sync/import faults, not only the one-row spike.

**Excludes:** Optimizing log retention; FR-19 handles measured operational limits.

### FR-08 — Unify command transitions and replay

**Outcome:** One deterministic transition contract produces equivalent live and
reconstructed state.

**Scope:** Route all mutations through the kernel/store, including steering controls,
PM proposals, reviews, budgets and resets. Distinguish commands, persisted decisions
and projections. Remove parallel mutation paths; use recorded time rather than replay
wall-clock time. Model blocked/partial/rejected outcomes explicitly or reject them
consistently at admission with documented alternatives.

**Acceptance:** Table-driven sequences cover every supported command/verdict and compare
live state with reconstruction. Pause/stop and all PM proposals survive restart;
exhausted retries stay exhausted; completion cannot overwrite accepted review state;
duplicate commands are idempotent. The public block command reaches its intended state.

**V2 review acceptance refinement:** Implement v2 canonical encoding/read-set CAS, same-ID lookup before current revision
checks, and explicit clock/ID inputs. Persist root controls, claim predicates and R5
ledgers as the early interface for FR-15a, independently of PM. Table-driven tests must
cover all R4 source-state guards, sealed result-versus-exit ordering, terminal dispositions
and all R5 transfers/settlements/reset generations. A kernel cannot forge protected facts
by changing a domain projection; live/replay equivalence applies to both authoritative
facts and the domain reducer. Test multi-ticket allocation and no implicit refill.

**R4a acceptance trace:** Table-test each role from its exact scheduling phase through
pre-intent capacity/eligibility denial, proved launch non-start and unknown possible start.
Assert developer non-start retains one active attempt and returns the ticket to queued;
reviewer non-start returns the same frozen candidate to awaiting_review; PM retains its
planning owner. Restart after atomic non-start settlement but before redispatch must
reconstruct one owner, one infrastructure ordinal, no live execution and no replay of the
settled launch. Pause/drain/cancel/exhaustion and generation changes reproduce the v3 rows.

**Excludes:** Running external effects inside the reducer.

### FR-09 — Prove OMP execution and presentation contract

**Outcome:** A narrow execution interface has measured capabilities and honest limits.

**Scope:** Conform to the FR-06 identity/effect contract under FR-15a isolation. Define
start, observe, prompt, interrupt, reconcile and close operations with
execution/session identity. Put Herdr attach/inspect/close behind presentation operations.
Exercise installed OMP structured modes, session persistence and quota observations.
Keep Herdr as the initial backend; do not replace it speculatively.

**Acceptance:** A bounded allowed-subscription execution produces a result without a
pane where supported; disconnect/reconnect, cancellation and exit observation have
recorded outcomes. Pane closure alone cannot assert ticket completion. Unsupported
capabilities produce a documented explicit outcome, not an invented liveness signal.
Record exact executable versions and observed usage/entitlement signal limitations.

**V2 review acceptance refinement:** Prove the installed OMP harness can use the credential gateway and remote isolated
tool bridge with candidate plugin/startup-code loading disabled. Reusable auth must never
reach arbitrary tool execution. Test a second harness/direct request/profile override
from the same slot, forged request identity, proxy/credential access and unauthorized
extra model calls; they fail or traverse new authorized reservations. Verify hidden
backend retries cannot evade per-request accounting. If unsupported, report execution
blocked with the required adapter change; do not copy credentials or replace OMP silently.

**Excludes:** Model ranking, generic multi-provider plugin infrastructure.

### FR-10 — Persist owned effects and reconcile executions

**Outcome:** Restart reconciles prior work before deciding whether another launch is safe.

**Scope:** Persist effect IDs/intents/receipts and separate developer, reviewer and PM
execution IDs under attempts. Wire checked launch/prompt/process operations into actual
orchestration. Monitor execution workers and reconnect or terminate verified ownership
after Coordinator loss. Define explicit unknown outcomes where backend idempotency is
unavailable; do not promise exactly-once external execution.

**Acceptance:** Restart between intent, launch, receipt and completion; hard-kill a worker
and Coordinator separately; deliver late/duplicate messages from old attempts. Assert
no blind relaunch, no stale transition, recovery of reviewer work and explicit uncertain
states. The runtime registry rebuilds from durable identities rather than pane guesses.

**V2 review acceptance refinement:** Implement pending/claimed/issued/unknown/terminal states under the protected gateway.
Inject claim→cancel→issue, issue→cancel→external action, duplicate delivery and old-writer
takeover. Assert exact outstanding claim IDs, no second delivery and no retry from an old
ref/missing process alone. Include non-session effects in reconciliation, issuer/channel
quiescence proof and late receipts settling only their original reservations. R1's issued
boundary is authorization for one operation, not an assertion that it has finished.

**R4a acceptance trace:** Prove launch non-start only after the named issuer/delivery
channel is quiescent. Atomically close the execution, settle its one reservation and emit
the role-specific domain transition. Duplicate and late receipts must neither release
twice nor advance the infrastructure ordinal twice. An unknown possible start retains
holds/leases and cannot be replaced. A new launch effect must reference the terminal
predecessor; restart between settlement and new claim cannot redispatch the old effect.

**Excludes:** Scheduler prioritization and deployment effects.

### FR-11 — Close correction, timeout and review lifecycles

**Outcome:** Every attempt has one explainable terminal disposition and bounded retries.

**Scope:** Separate timeout from successful completion, cancel/invalidate old timers,
use the FR-06 fresh-attempt correction strategy (close/reconcile old execution before
new launch; no simultaneous re-prompt), and make CLI and automatic review use the same
transition/cleanup path. Persist developer/reviewer retry budgets separately as designed.
Release execution capacity while awaiting review without losing resumable session state.

**Acceptance:** One correction cannot both re-prompt and relaunch the developer;
old deadlines cannot end a newer execution; reviewer crashes consume the intended budget;
blocked and exhausted work remain correctly classified across restart. Check all owned
executions and panes after success, reject, cancel, timeout and failed reviewer launch.

**V2 review acceptance refinement:** Test valid frozen result then abnormal exit, exit with a prior durable inbox result,
missing/incomplete stream, successful developer close before capacity-one review, and
reviewer-result cleanup through CLI and automatic paths. Test check assertion versus
infrastructure failure/timeout, malformed validation exhaustion, and cancellation after
an attempt already has a terminal disposition. No exit or timer can overwrite a valid
result. Retries obey role reservations, closed generations and exact-once settlement.

**R4a acceptance trace:** A proved developer non-start closes only that execution and
retains the same nonterminal attempt until bounded infrastructure exhaustion or budget
exhaustion; no crash/timeout/result is synthesized. A proved reviewer non-start preserves
candidate, checks and reviewer ownership and never enters developer retry. Exercise below-
limit retry, infrastructure block, explicit resumption, developer budget exhaustion and
reviewer budget block/exhaustion, including restart and stale receipts from the failed
launch. Process-start units are refunded only on proof and are not charged to bound the
separate durable infrastructure allowance.

**Excludes:** Evidence acceptance itself, delivered by FR-13.

### FR-12 — Wire admission, resource scheduling and review capacity

**Outcome:** The actual launch path enforces policy, specification requirements,
dependencies, resource conflicts and bounded capacity while allowing reviews to progress.

**Scope:** Route Tick through the real scheduler and common admission; validate usable
checkout/base/spec references and environment propagation. Reserve or otherwise guarantee
review progress under developer saturation. Scheduling denial is not an execution retry.

**Acceptance:** Exercise competing tickets, unresolved dependencies, resource conflicts,
priority changes, unusable checkouts and full worker capacity through live orchestration
with a fake execution backend. No denied work launches or burns attempt budget. A queued
review progresses under the configured maximum concurrency. Agent launch receives the
admitted environment and assignment, with secrets omitted from diagnostic output.

**V2 review acceptance refinement:** Schedule mandatory check/build workers as well as model roles. Test capacity one:
developer close→checks close→review close. Under drain, correction/rebase becomes blocked
queued work and stop may complete after issued claims/cleanup settle; unknown work blocks
stop visibly. PM decomposition transfers existing objective allocations to tickets;
capacity/dependency/profile denial neither reserves nor consumes a start unit.

**R4a acceptance trace:** Pre-intent capacity/resource/profile/eligibility denial stays
in the current scheduling phase, creates no execution/claim/reservation and does not
increment launch infrastructure attempts. After proved non-start, schedule only a new
effect referencing the predecessor and only when current policy, controls, resource
revalidation, budget generation and finite role allowance permit. Under pause, retain but
do not issue; under drain, block developer/PM retries while reviewer/check/finalization
retries remain eligible; cancel never retries. Verify released checkout resources are
reacquired/revalidated and immutable reviewer candidate custody is retained.

**Excludes:** Dynamic profile switching and PM-generated specifications.

### FR-13 — Verify artifacts, candidate scope and check receipts

**Outcome:** An independent review and required checks approve an exact attributable
candidate, with controller-verified scope and ancestry.

**Scope:** Carry explicit ticket/attempt/execution/base/spec/policy identity end to end.
Validate real Git ancestry and diff against admitted scope. Run required checks in an
owned worker and store controller-generated receipts bound to tree, command, environment
and result. Reviewer execution identity cannot be substituted with the developer's.

**Acceptance:** Actual wrapper-to-controller tests reject stale artifacts, wrong role,
nonexistent checkout, unrelated one-commit history, hidden out-of-scope changes, altered
candidate after review, and fabricated check assertions. A legitimate real candidate
and independent review pass. Empty checks are allowed only if governing policy explicitly
permits them, not because a field was missing.

**V2 review acceptance refinement:** Prove freezing/import uses controller-custodied immutable objects despite concurrent
untrusted writer changes; forbid candidate hooks/paths from executing in the root. Gate
receipts and accepted facts cannot be forged through kernel domain events. Cover all
v2 blocked/partial/invalid/check-result transitions at actual submission boundaries.

**Excludes:** Updating the accepted Git ref; FR-14 owns integration.

### FR-14 — Perform serialized recoverable Git integration

**Outcome:** Acceptance corresponds to an actual verified Git tree/ref transition.

**Scope:** Use durable integration intents and owned asynchronous workers. Apply
FR-06's fast-forward-only accepted-ref compare-and-swap. A moved base requires a fresh
rebase attempt, renewed checks and independent exact-candidate review; no unreviewed
merge tree. The protected controller owns the accepted repository. Reconcile interrupted ref updates; serialize competing integrations. Keep pause,
cancel and status responsive while Git/check commands are running.

**Acceptance:** Real Git tests cover successful integration, conflict, changed base,
failed checks, stale review, concurrent acceptance and crash before/after ref update.
Assert both durable records and actual refs/trees. No nonexistent SHA advances state;
an interrupted effect cannot be reported successful without checking its outcome.

**V2 review acceptance refinement:** Exercise an issued Git worker stalled before CAS while cancel or epoch takeover
commits. Cancel returns pending with that claim; settling actual ref wins over guessed
cancellation. Old ref alone cannot justify another issuer until the original process and
channel are quiescent. Non-issued cancellation prevents CAS; changed base renews checks
and review, charging the existing allocation for actual new work.

**Excludes:** Building or activating the running release.

### FR-15a — Prove protected verifier and execution isolation

**Outcome:** Candidates cannot exercise operator/controller authority or impersonate a
reviewer. This is the early infrastructure portion of FR-15, separated to avoid making
FR-09 depend on a steering loop that itself depends on execution.

**Scope:** Implement the account/worker isolation and narrow local capability protocol
in [FR-06](WORKFLOW-CONTRACT.md), using FR-07/08 durable gateway and ledger contracts.
Protect verifier/launcher/auth gateway/activation-root code, state, policy, accepted refs,
release store and activation credentials. Keep untrusted build/test/runtime code outside
that principal. Separate role/slot access; Herdr attachment must not inherit steering
credentials. Pin the initial operator-installed controller and immutable deny-by-default
policy. Full durable policy changes/PM remain in FR-15.

**Acceptance:** From actual isolated developer, reviewer, PM, build and runtime processes,
try controller file writes, other-role token/checkout reads and writes, general release
RPC, unauthorized policy changes and forged/replayed capability calls. Assert denial;
valid scoped submission/query works. Inspect actual listeners and crash/status redaction.
Reused execution slots cannot retain prior tokens/processes. Verify old writer epochs
cannot authorize new effects. Test accounts and resources must be explicitly owned.
If the host cannot enforce the chosen isolation, keep the affected capabilities disabled
and record the failed requirement; a same-user directory convention is not a substitute.

**V2 review acceptance refinement:** Prove the selected root/kernel/auth-harness/tool principal separation, including
same-slot reusable-auth/direct-provider bypass, network/proxy/IPC/process-memory denial,
launcher input validation and no candidate-loaded code in trusted harness/root contexts.
Use deterministic local fake provider endpoints for exhaustive denial/accounting tests;
FR-09 separately owns actual installed-harness subscription conformance. Root write gateway
must reject forged budget/acceptance events from an isolated candidate kernel. Its safety
predicates and initial policy must work without the later PM loop.

**Excludes:** Installing privileged host accounts in an ordinary ticket without necessary
operator provisioning authority; full steering/PM behavior or autonomous protected-root
upgrade. The workflow kernel is not part of that exclusion; FR-17 activates its repairs.
FR-15a completion must provide a reproducible isolated test setup and host setup procedure.

### FR-15 — Implement durable steering and optional PM planning

**Outcome:** Operator direction becomes durable policy and bounded admitted work.

**Scope:** Use the FR-15a authority boundary and FR-06 actor/commit contract for durable
pause/drain/cancel/priority/autonomy changes, and an optional PM path that creates a
versioned spec. Forward the full admitted assignment and artifact contract to the
developer. Directly admit already specified work without a redundant planning call.

**Acceptance:** Change authority mid-run and prove its effect on new actions and the
declared handling of active work, including restart. A PM/candidate cannot enable paid
fallback, weaken required gates or broaden authority through files or exposed commands.
Broad direction yields a spec and admitted ticket; a specific request skips PM; an
ambiguous proposal yields an explicit unresolved decision instead of invented authority.

**V2 review acceptance refinement:** Use existing gateway cancel/revoke/reset primitives; do not create a competing
steering transition path. Test cancellation acknowledgments naming issued work, revocation
between claim and issue, reset with old unknown reservations, and controls surviving
kernel replacement. Root grants require authenticated operator commands; PM amendments,
new tickets and profile changes cannot replenish a ledger or select weaker gates.

**Excludes:** A polished conversational UI; a working steering command boundary is
sufficient if its durable records can support the later conversation surface.

### FR-16 — Implement bounded subscription switching

**Outcome:** Quota problems switch only within explicit per-role permitted profiles,
without duplicate execution or hidden paid use.

**Scope:** Persist profile ordering, exhaustion/cooldown evidence and bounded retry
decisions under protected policy. Label quota observations with freshness/uncertainty.
Reconcile possibly running work before switching. Stop admitting affected work when
no eligible profile remains; expose the reason and an operator recovery command.

**Acceptance:** Deterministic cases cover low/unknown quota, quota rejection after
launch, all profiles exhausted, stale signals, restart and manual recovery. Verify the
chosen profile and billing path at the backend boundary; no automatic paid fallback.
Real smoke proves only the signals actually exposed by installed subscription tooling.

**V2 review acceptance refinement:** Exercise role-start plus model-request reservations through profile switching,
unknown deliveries, duplicate and late receipts, reset generations and parent/child
allocation limits. The gateway fixes billing/profile fields from the claim; available
credentials never imply permission. Unknown holds remain charged against available
capacity until reconciliation, never converted into zero usage or new-generation credit.

**Excludes:** Inventing a capability ranking before benchmarks exist.

### FR-17 — Activate immutable accepted builds and recover failures

**Outcome:** Foundry can autonomously deploy accepted code with identifiable running
builds and compatible rollback.

**Scope:** Build from accepted immutable input, record source/build/policy/schema
versions, drain or reconcile active effects, and use the real release start/stop
interfaces. Keep the activation controller and mandatory health/gate policy outside
candidate control as specified by FR-06. Define rollback when state migration prevents
loading an older executable; do not silently discard acknowledged post-upgrade work.

**Acceptance:** Activate a real isolated build and verify its loaded revision. Inject
build, stop, start, health and compatibility failures and crashes at activation boundaries.
Recover a usable compatible runtime with preserved evidence. A candidate modifying its
own health checks cannot bypass mandatory external criteria. Merge success and deployment
success remain distinguishable. Restore automatic activation only through this protocol.

**V2 review acceptance refinement:** Activate an actual kernel lifecycle/replay repair autonomously while the verifier,
policy/gates/auth root and their hashes remain fixed. Attempted root replacement or
forged acceptance/health/ledger requests from that kernel must fail. Verify every version
the new kernel can write is supported by the rollback build and root allowlist; mere
range overlap is insufficient. Test cancellation at each issued build/stop/switch/start
boundary, safe copy under concurrent writes, and rollback preserving newer acknowledged
work. Protected-root upgrades remain explicit operator maintenance, not all kernel repairs.

**Excludes:** Fleet deployment or distributed release orchestration.

### FR-18 — Make status, board and telemetry reflect real state

**Outcome:** The operator can see what runs, why it waits, and what evidence is missing.

**Scope:** Consume one versioned query/projection contract; fix board envelope handling
and distinguish unavailable/corrupt data from empty success. Align actual telemetry
producers with validators and consumers; correlate ticket/attempt/execution/effect IDs.
Report worker ownership, unknown outcomes, retry budgets and accepted/running revisions.
Review diagnostic redaction and local inspection exposure against FR-06's boundary.

**Acceptance:** Drive launch/correction/review/block/crash/restart events through real
producers and assert board/status/log agreement with authoritative state. Telemetry
records validate; invalid records are surfaced. Representative secret-bearing commands
are redacted. A corrupt/unreachable store cannot show a healthy empty board.

**V2 review acceptance refinement:** Show separate ticket/attempt/execution/control facts, pending cancellation claim IDs,
check/cleanup/stop blocks, old-generation holds, unknown usage and root-derived accepted/
deployed pointers. A candidate domain projection cannot manufacture healthy acceptance.

**Excludes:** Building a new dashboard framework.

### FR-19 — Bound storage and make offline maintenance safe

**Outcome:** Diagnostic growth and maintenance failures cannot erase authoritative work.

**Scope:** Add measured retention/rotation and bounded query behavior for diagnostic
logs. Apply FR-07's snapshot/compaction protocol where needed. Repair or retire relocation
commands explicitly: validate paths, space and digests, check journals and avoid dynamic
atoms; cross-device moves verify the destination before source removal. Preserve evidence
when maintenance fails.

**Acceptance:** Exercise large logs, malformed diagnostic records, interrupted rotation,
compaction and migration, full disk and cross-device copy failures. Verify acknowledged
state, originals and unrelated paths survive. Record measured data sizes, resource costs
and limits; make no unmeasured performance claim. Disabled historical tools must fail
clearly and have a documented supported replacement where required.

**V2 review acceptance refinement:** Retain full filesystem ENOSPC/sync/WAL/checkpoint/compaction and SQLite corruption
recovery obligations; verify backup content and replay, not just row count. Old ledger
and claim evidence must survive retention and offline maintenance. The small comparison
is not completion of the full storage failure-conformance set.

**Excludes:** Retaining unsafe Python compatibility just for historical parity.

### FR-20 — Reconnect constrained improvement proposals

**Outcome:** Operational findings can yield attributable, deduplicated improvement
work through the same admission and acceptance gates as other changes.

**Scope:** Align classifiers with emitted schemas and actual states; persist finding,
proposal and admission outcomes separately. Replace fixed ticket IDs and stale paths;
do not suppress a finding merely because proposal generation/admission failed. Route
repair work through current specs, checkout allocation and policy. Complete autonomous
integration/activation uses FR-14/FR-17, never a privileged shortcut.

**Acceptance:** Real emitted failures produce appropriate proposals without crashing;
legitimate states do not trigger known false classifications. Failed admission retries
within budget; restart neither loses pending work nor duplicates admitted repairs.
Completed repair tickets remain complete. An improvement cannot broaden governing policy.

**V2 review acceptance refinement:** Include ordinary kernel defects in the repair path. Generate a scoped proposal,
consume existing allocation, independently review and autonomously activate via FR-17;
no root privilege shortcut or operator-only kernel exclusion. Proposal plumbing may be
implemented before FR-17, but kernel repair activation is not complete until FR-17 passes.

**Excludes:** Open-ended recurring PM calls or self-generating management hierarchies.

### FR-21 — Establish independent Foundry CI and build provenance

**Outcome:** Foundry checks run independently of the corpus stack and test artifacts
have identifiable source/dependency inputs.

**Scope:** Add a Foundry CI job with fresh isolated state/TMPDIR, explicit exclusions
and appropriate compile/format checks. Resolve tracked deps/escript provenance with an
explicit build/vendoring policy. Replace vacuous lifecycle tests with meaningful assertions
as repaired paths become available. Date or retire absent Python parity claims/tools.
Handle existing formatting debt separately from functional changes.

**Acceptance:** Reproduce the job locally from a clean checkout without corpus services;
run it twice without stale temporary-path collisions. Build provenance identifies inputs.
No CI test closes foreign panes or launches paid agents; real-provider tests are explicit,
bounded and separately reported. Publish excluded coverage rather than implying it ran.

**Excludes:** Waiting for the whole repair before adding CI; extend this job in each
subsequent ticket as new lifecycle tests land.

### FR-22 — Prove full lifecycle and reconcile operating docs

**Outcome:** Demonstrate the agreed autonomous engineering workflow end to end, including
recovery, and state exactly what remains unsupported.

**Scope:** Assemble prior tests into scenario-level conformance. Reconcile README,
EVENT_SOURCING, migration docs, roles, commands and AGENTS references with exercised
behavior. Retain the dated audit; add a closure matrix linking each F01–F24 finding to
implementation revisions and evidence or an explicitly unresolved gap.

**Acceptance:** Steer an objective, optionally plan, admit, launch, submit a real commit,
request a correction, independently review, integrate and activate a Foundry change.
Repeat with restarts at decision/effect boundaries and variants for blocked work, quota
exhaustion, full capacity, stale artifacts, partial persistence, lost observers and failed
activation. Assert actual Git/build/state outcomes and owned resource cleanup, while
foreign resources survive. Use deterministic fake backends for exhaustive fault cases
and a bounded real subscription smoke for harness integration. Report limitations of
each; mocks alone cannot establish real-provider behavior.

**V2 review acceptance refinement:** Add scenario variants for every R1–R5 interleaving/invariant and one real autonomous
kernel repair under unchanged root policy. Verify both kernel update success and attempted
root/credential/budget bypass denial. Runtime-only activation cannot close this capability.
Retain the complete original F01–F24 matrix and publish unresolved implementation limits.

**Excludes:** Declaring unknowns safe because all existing component tests pass.

## Completion log

2026-09-12, FR-06: design and isolated storage evidence recorded in
[WORKFLOW-CONTRACT.md](WORKFLOW-CONTRACT.md). No production repair implemented.
Independent design review was pending when that proposal was recorded.

2026-09-12, FR-06 independent review v1: [review](FR-06-DESIGN-REVIEW.md) completed;
verdict **not ready**, R1–R5 unresolved. Manifest matched before review-status edits;
the isolated storage rerun exactly reproduced the recorded JSON. No proposal or runtime
repair performed. Next: resolve the review findings, record revised input hashes and
review their disposition. Continue FR-01–FR-05 containment independently. FR-07 stays
blocked; stop this session after the review.

2026-09-12, FR-06 revision v2: [response](fr-06/review-response-v2.md) records R1–R5
protocol dispositions and smaller clarifications. Original manifest inputs verified;
reversing only the documented review-status edits reproduces both original plan hashes.
Historical review preserved. Current manifest identifies the revised input set. No
production repair or model invocation. **FR-07 remains blocked pending independent
re-review; no self-certification.** Next at that revision: verify v2 hashes, review protocols/dispositions
and implementation routing, record a new independent verdict. Stop after this design revision.

2026-09-12, FR-06 independent re-review v2: [review](FR-06-DESIGN-REVIEW-V2.md)
records **ready after specified corrections**. Manifest digest and all inputs matched;
dependency and F01–F24 routing checks passed. R1/R2/R3/R5 resolved at design level;
R4a retains the missing role-specific launch-non-start recovery transitions. Next:
make that bounded design correction and check its passages, acceptance traces and new
hashes. FR-07 stays blocked on R4a and FR-03. No implementation, provisioning or model
invocation occurred; the workflow proposal and historical review remain unchanged.

2026-09-12, FR-06 revision v3: [response](fr-06/review-response-v3.md) proposes the
bounded R4a correction and routes its acceptance traces to FR-08/10/11/12. Both independent
reviews and response v2 remain historical evidence. No production code, tests, daemon,
credentials or model execution changed. **FR-07 remains blocked pending focused independent
verification of the refreshed manifest, plus FR-03.** This entry does not certify R4a.

2026-09-12, FR-06 focused independent verification:
[review](fr-06/r4a-focused-review.md) returned **PASS** against the exact v3 manifest
and resolved R4a at design level. FR-06's design gate is complete. No production
implementation finding closed; FR-07 still waits for FR-03 completion evidence.

2026-09-12, FR-01: candidate v5 received an independent Astra-high
[PASS](fr-01/review-v5.md) for static containment. Every current automatic developer
and reviewer path requires the common validated policy plus an enforced subscription
route capability; the production System runner deliberately reports that capability as
unsupported, so no real automatic model launch is currently possible. PM eligibility is
covered although no PM model caller exists. Model-free focused, supporting, adversarial
and full-suite acceptance passed; the final isolated full run reported 323 passed and 2
integration-tag exclusions. Real OMP subscription/account/billing conformance and safe
re-enablement remain FR-09/15a, dynamic switching remains FR-16, and full lifecycle
acceptance remains FR-22. Candidate hashes and the review chain are retained in
[IMPLEMENTATION-LOG.md](IMPLEMENTATION-LOG.md).

2026-09-12, FR-02: Elixir-only candidate v2 received an independent
[PASS](fr-02/review-v2.md). `bin/pramana` now transports user argv as a bounded,
versioned JSON envelope inside canonical URL-safe base64 to one fixed RPC expression;
the daemon-side decoder rejects duplicate keys, malformed/oversized/noncanonical data,
NUL and unknown command shapes before dispatch. Actual-wrapper tests preserve literal
quotes, backslashes, newlines, Unicode, empty/interpolation-looking data, stdout/stderr
and exit status. General release eval authority remains FR-15a; equivalent historical
interpolation in `tickets_from_review.sh` and `test_daemon_recovery.sh` remains routed
to FR-03/04/05. No live daemon/provider was used.

2026-09-12, FR-03: candidate `69ede99128b14134cec9bddd728883e56f8cf62c`
received an independent [PASS](fr-03/review-v2.md) for immediate F02/F14 containment
after the original [review](fr-03/review.md) reproduced four blockers and the
[response](fr-03/review-response.md) corrected them. Startup now admits one fenced
runtime whose owner contains the effectful subtree; clean release follows subtree
quiescence, while abrupt/uncertain loss leaves an unclean marker and refuses automatic
takeover. Unterminated or invalid authoritative history is preserved and enters visible
recovery through the single strict replay path. Checked legacy writes cannot acknowledge
or launch after failure. Unsafe automatic startup reconciliation, multi-item tick work
and legacy Git integration are suspended for FR-07/08 and FR-05 rather than represented
as atomic. The new fixtures are Elixir; the existing Fence bridge remains the external
POSIX-lock boundary. This is integrated containment, not deployment or FR-22 lifecycle
acceptance. FR-07 is now ready because both FR-03 and FR-06 have completion evidence.

2026-09-13, FR-04: candidate `cd77de43475b1fbb4ef600384817b3f2434c6b4d`
received independent [PASS](fr-04/review-v9.md) after an adversarial review chain retained
in `docs/fr-04/`. Destructive cleanup now requires exact pane, terminal, native-session,
shell-generation and foreground-generation evidence; split ownership is durably recorded
before agent start, unverified/unknown resources are preserved, and developer/reviewer
resources remain distinct in a bounded role/execution inventory. Cleanup pending/results
use FR-03's checked gateway. Outstanding cleanup blocks admission and clean fence release;
all owned resources must have matching terminal evidence. CWD inference, hard-coded pane
exceptions, default-adapter close and the destructive fixed-root recovery fixture are gone.
This is immediate F05/F23 containment, not FR-10 reconciliation or atomic backend
compare-and-close; no live backend/provider or deployment was exercised.

2026-09-13, FR-05: candidate `5bc8c1ca81bfe65dff2b40a164ea8e12e2424f80`
received independent [PASS](fr-05/review-v2.md) after its original
[review](fr-05/review.md) found and the [response](fr-05/review-response.md) closed
two direct-boundary bypasses. CLI submissions no longer synthesize artifact, revision,
check or reviewer identity; automatic approval and production Git-check bypasses fail
closed. Every public legacy Pipeline/integration operation refuses before runner, state,
filesystem, Git ref or cleanup effects. Replayed legacy integration success is retained
only as an unverified historical claim and cannot advance the authoritative accepted
revision. The mutable-source watcher invokes no child and exits 78. This is containment,
not FR-13 artifact custody, FR-14 integration or FR-17 immutable activation; none is
deployed or re-enabled.
