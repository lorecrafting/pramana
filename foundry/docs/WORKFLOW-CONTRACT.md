# Foundry workflow contract — FR-06

Revision **4 (R3 observability boundary added; independent re-review outstanding)**,
2026-09-20. Revision 3's R4a correction remains independently verified: the
[focused review](fr-06/r4a-focused-review.md) returned **PASS** against the exact
revision-3 manifest, and revision 4 changes no R1, R2, R4, R4a or R5 decision. The added
R3 paragraph has **not** been independently reviewed, and no candidate may cite it as
verified contract text until it has. This is the
interface contract for the [repair backlog](REPAIR-PLAN.md), subordinate to its agreed
operator contract. The [audit](AUDIT-2026-09-12.md), [independent review v1](FR-06-DESIGN-REVIEW.md),
[response v2](fr-06/review-response-v2.md) and [independent review v2](FR-06-DESIGN-REVIEW-V2.md)
remain historical evidence. [Response v3](fr-06/review-response-v3.md) addresses only
R4a. FR-07 remains blocked on FR-03; its FR-06 design prerequisite is complete.
No production code, running daemon, credentials or host permissions changed here.

> **Current status route (2026-09-19):** This revision-3 document is preserved as the
> accepted FR-06 design evidence, so dated sentences below saying FR-07 waits for FR-03
> are not rewritten. Current ticket status and sequencing live only in the
> [repair plan](REPAIR-PLAN.md): FR-07 is complete for its accepted v9 foundation; H0
> inventories that public boundary; FR-08A supplies missing protected lifecycle
> primitives and substantive revision-bound handoff proof; FR-08B then migrates all
> command ingress and replay. See the independent read-only
> [alignment audit](ALIGNMENT-AUDIT-2026-09-19.md) and the historical
> [FR-08 investigation](fr-08/investigation.md). This route changes no R1–R5 decision,
> runtime, policy, provider or activation permission.
>
> **Enforcement matrix (2026-09-23):** the [enforcement matrix](#enforcement-matrix) was added
> on operator approval. It records where each guarantee is enforced and changes no R1–R5
> decision, so the revision number is unchanged.

## Decisions and evidence

Retain one standalone OTP project. Use one pure decision/replay kernel, SQLite for
transactional authority, owned asynchronous workers for effects, OMP for execution and
Herdr for optional presentation. Introduce a small protected local controller for policy,
capability issuance, durable write/claim verification, accepted-ref promotion and activation.
The workflow kernel is an autonomously updatable isolated process; the protected verifier
and activation root remain outside its authority. Both are built from this standalone
project. Root upgrades require operator maintenance; ordinary kernel repairs do not.
See R3 below for the exact boundary. No new service framework or multi-user product.

Focused source checks found `Application.start/2` starts effectful children for ordinary
CLI invocations; `EventLog.append/2` synchronizes individual records without a transaction
across decisions; `Effects.Launch` persists pane-based launch identities; and `mix.exs`
has no transactional store dependency. These support replacing the authority connections,
not deleting useful scheduling, validation or process primitives. See those modules and
F02/F08/F14 for the pre-repair behavior. Source baseline is the audit's HEAD plus existing
working-tree changes; source was not changed by FR-06.

The [storage spike](fr-06/storage_spike.py) and [machine output](fr-06/storage-results.json)
compare the same command/result/event/state/intent bundle in SQLite WAL and a checksummed,
locked, fsynced journal. Run `python3 foundry/docs/fr-06/storage_spike.py` from repo root.
It uses fresh temporary files and subprocess exits, no Foundry startup or model calls.
Python is experiment tooling only; production storage stays in the standalone Elixir app.

| Failure question | SQLite prototype | Repaired journal prototype |
|---|---|---|
| Exit before durable commit / after commit before reply | No transaction / complete transaction; retry same key deduplicates | Same at tested boundaries; one bundle per record |
| Two OS writers | Second child fails while lock held; succeeds after release | Second child fails while flock held; succeeds after release |
| Capacity failure | Actual SQLite `max_page_count` error preserves prior transactions | Untested; no equivalent journal/filesystem capacity fault injected |
| Torn bytes / corruption | SQLite page/WAL corruption not injected | Short append refuses recovery; earlier bytes preserved; interior checksum mismatch refuses |
| Snapshot / migration | Backup row count checked; user_version rollback checked; unknown application body version refused | Unpublished partial snapshot ignored; atomic publication and version migration not implemented |
| Compaction, sync I/O errors, hardware power loss | Untested | Untested |

Selection: **SQLite WAL, synchronous FULL**, one writer connection, foreign keys enabled,
short transactions; indexed projections and command/effect lookups. SQLite supplies
transaction and backup machinery the journal would require us to maintain. Neither
prototype implements the full kernel, nor establishes production throughput or crash
safety on this filesystem. No speed comparison is claimed. SQLite documents WAL FULL's
commit sync and the filesystem assumptions that limit durability: [PRAGMA synchronous](https://www.sqlite.org/pragma.html#pragma_synchronous),
[atomic commit assumptions](https://www.sqlite.org/atomiccommit.html).
FR-07 must pin and exercise an in-process Elixir SQLite binding on the pinned OTP/macOS
build; no Python database sidecar and no Postgres dependency. Binding failure is an
explicit design exception to resolve, not permission to silently revert to JSONL.

## Authority and deployment boundary — R2 and R3

Threat model: fallible local coding agents and candidate kernel/runtime code capable of
arbitrary shell, including build hooks, tests, extensions and subprocesses. Trust only
operator-installed verifier/launcher/authentication components and their pinned inputs.
No protection against an operator using administrator authority or a kernel exploit is
claimed. Identity labels alone do not establish OS/process/filesystem/network isolation.

<a id="r3"></a>

### R3: autonomously repairable kernel, protected verifier

Replace v1's permanent exclusion of kernel repairs. A new scheduler, lifecycle reducer,
replay implementation or recovery planner can be independently reviewed, checked and
autonomously activated under unchanged governing policy. The root does not execute that
candidate in its own BEAM, load its plugins or give it a SQL/OS credential. The kernel
runs under a separate restricted account and proposes bounded transaction bundles over a
versioned local protocol. The sole SQLite writer remains behind the protected verifier.

| Component | Owns | Upgrade authority |
|---|---|---|
| Protected verifier/store gateway | Authenticated steering provenance; policy; command deduplication and revision CAS; append-only sequence; budget ledger; effect claims; receipt provenance; acceptance predicates | Operator maintenance |
| Protected launcher/auth gateway/activation controller | Fixed privilege operations, isolated identities, provider credential custody, owned process evidence, accepted refs and immutable release switch | Operator maintenance |
| Workflow kernel | Pure decide/apply, ticket/attempt lifecycle, scheduling plans, recovery proposals, domain projections and queries | Autonomous exact-candidate repair under root gates |
| Planning/presentation/workers | PM, developer/reviewer execution, tools, board, runtime behavior | Autonomous exact-candidate repair under root gates |

The verifier checks safety predicates rather than implementing a second scheduler or full
workflow reducer. A bundle may append a supported domain event and CAS its projection;
it cannot update protected tables directly. Root-derived fields (claims, budget balances,
accepted/integrated/deployed pointers, policy and review/check receipt validity) cannot be
supplied by kernel events. Kernel projection labels never serve as acceptance evidence.
Authenticated original commands and raw receipts are durably retained before kernel
interpretation; the candidate cannot rewrite/drop them or acknowledge an uncommitted
command. Bad lifecycle proposals can block progress, but cannot manufacture authority.

**Observability is not authority.** An observation, telemetry record or diagnostic log is
evidence *about* the system, never a fact the system may decide on. No observation may
establish a lifecycle disposition, a closed execution, a check or review outcome, or any
protected fact. The R4 rows already say this one case at a time — a closed execution
requires verified process/session termination or proved non-start, a check failure uses
its controller's own `reason_code` rather than an agent's assertion, a review verdict is
read only from a sealed stream, and pane closure alone cannot assert completion — and
stating it once here makes it reviewable as a boundary instead of re-derived per row. A
projection, board or analytics surface computed from observations is likewise a view, not
a source. This holds whichever surface an observation reaches: the canonical observation
envelope, a JSONL diagnostic file, or an exported trace. It is also why the observability
work may change what is measured, how it is retained and where it is exported without
ever changing what is decided.

Recorded at revision 4 on implementation evidence rather than from first principles. The
FR-08B kernel enforced this rule three separate times in one subcommit — `execution_observed`
may not close an execution, a verdict string is not a disposition, and a review verdict
needs a sealed stream — and each was re-derived from individual R4 row text because the
rule was written nowhere. A rule stated only inside FR-18B would also become ownerless when
that ticket closes, while the boundary must outlive it.

For every effect claim the verifier independently checks: authentic admitted assignment,
current control/policy revision, allowed role/profile/operation/scope, sufficient ledger
reservation, ownership/conflict guards, and any prerequisite raw evidence. Acceptance
requires root-verified actual Git ancestry/full diff, independent exact-candidate review
and mandatory root-owned checks. Activation requires that acceptance, build provenance,
compatible write set and external health gates. General SQL, arbitrary event injection,
command evaluation, arbitrary privileged shell and candidate-selected gate programs are
not verifier APIs. Unknown command/event/write versions fail closed. The initial API
schema and these predicates are part of FR-07/08/15a's shared protected contract.

Enforceability argument: even a kernel that emits `integrated` for a nonexistent SHA or
sets its projection's remaining budget to infinity cannot obtain a ref update or provider
request: those effects consult the root's repository/receipts/ledger, not its projection.
A proposed build containing changed verifier code may be accepted as source, but routine
activation selects only declared kernel/runtime artifacts; root binaries, mandatory gate
programs, policy and their configuration are excluded from its writable/install scope.
A kernel replay fix is therefore deployable without replacing the invariant checks that
constrain it. FR-17/20/22 must demonstrate this specific repair, not only a board change.

This preserves the agreed autonomous Foundry capability while protecting the governing
policy boundary already required by that contract. It does not claim a verifier can prove
arbitrary new code correct. If implementing the API would require moving the entire
lifecycle reducer back into the operator-only root, reopen R3: the concrete choices are
(a) further factor the safety API and retain autonomous kernel repair, or (b) ask the
operator to approve an explicit permanent exclusion listing the affected repairs. V2
selects (a); (b) is not authorized or silently adopted. No new operator product decision
is required by the selected design; actual enforcement remains to be proved.

<a id="enforcement-matrix"></a>

### Enforcement matrix — what Core re-checks and what rests on the controller

**Status:** added 2026-09-23 on operator approval, from the Fable strategy review. It records
where each guarantee is enforced at `c3b65161`; it changes no R1–R5 decision. Sources:
review C3 in the [subcommit 2 `decide/3` design](fr-08/FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md)
and the [protected items spec](fr-08/FR08B-PROTECTED-ITEMS-SPEC-2026-09-23.md). Paths are
under `foundry/lib/pramana_foundry/`; tests under `foundry/test/pramana_foundry/`.

**Rule:** every new protected operation or plan slot adds a row here in the same commit.

Core rows hold against any controller, including the kernel, because the protected layer
re-checks them at commit.

| Guarantee | Owner | Enforcement point | Evidence |
|---|---|---|---|
| CAS on every read revision | Core | `durable_store/gateway.ex` `check_expected_revisions/4` (`revision_conflict`); protected read sets in `durable_store/protected_primitives.ex` `complete_read_set/3` (`stale_read_set`) | `durable_store/review_corrections_test.exs` "read preconditions are authoritative and rejected decisions cannot mutate" |
| Control status is `active` for effect, claim and issue | Core | `protected_primitives.ex` `allowed_effect?/3` in `create_effect`, and `control_active?/1` in `claim_effect`, `issue_claim` and `reclaim_claim` (`control_not_active`) | `durable_store/fr08a_critical_corrections_test.exs` "control cancellation revokes claimed descendants and preserves no implicit credit" (issue refused); `durable_store/create_effect_refusal_test.exs` "create_effect is refused under an inactive control, and admitted once active" (Core's only inactive state is `cancel_requested`; `paused` is refused as `invalid_control_state`) |
| Allocation at `reserve`: open ledger, units within `available` | Core | `protected_primitives.ex` `apply_operation(%{"type" => "reserve"})` (`reservation_not_permitted`); units are debited at activation, re-checked by `activate_reservations/2` in `create_effect` (`reservation_activation_not_permitted`) | `durable_store/protected_primitives_test.exs` "parent-funded ledger, claims, leases and settlement conserve authority"; `create_effect_refusal_test.exs` "a reservation or an effect over the ledger's available units is refused" |
| Predecessor currency: successor names the latest terminal effect in its lineage | Core | `protected_primitives.ex` `predecessor_guard/5` in `create_effect`; `predecessor_current?/2` in `claim_effect` and `issue_claim` (`predecessor_not_terminal`, `predecessor_identity_mismatch`) | `durable_store/atomic_bundle_test.exs` "the retry a below-limit non-start selects is admitted by create_effect"; `create_effect_refusal_test.exs` "a successor naming a superseded predecessor is refused, and one naming the latest admitted" |
| Non-start allowance, per role from `infrastructure_attempt_limits` | Core | `protected_primitives.ex` `nonstart_allowance/3` in `create_effect` (`nonstart_allowance_exhausted`) | `atomic_bundle_test.exs` "the retry a below-limit non-start selects is admitted by create_effect"; `create_effect_refusal_test.exs` "a retry past the role's non-start allowance is refused, and admitted one step inside it" |
| Attempt closure; no effect under a closed attempt | Core | `protected_primitives.ex` `apply_operation(%{"type" => "close_attempt"})` (`attempt_not_settled`); `attempt_open/3` in `create_effect` (`attempt_closed`) | `protected_primitives_test.exs` "an attempt closes only when settled, and a closed attempt takes no new effect"; "an unsettled effect with no reservations still keeps its attempt open" |
| Infrastructure-limit branch is derived, not chosen | Core | `gateway.ex` `protected_discriminator/3` → `ProtectedPrimitives.infrastructure_discriminator_at_revision/3`, reading the effect's own policy revision | `atomic_bundle_test.exs` "a policy revised after the effect was created still decides from the effect's revision"; "a non-start still settles after a policy revision drops the role's limit" |
| A non-start binding requires `infrastructure_limit_v1` | Core | `durable_store/transition_plan.ex` `validate_binding_discriminator/1` (`nonstart_requires_infrastructure_discriminator`) | `durable_store/transition_plan_test.exs` "a non-start settlement cannot be bound by an unconditional plan" |
| Settlement closes the execution it settled | Core | `transition_plan.ex` `closes_named_execution?/4` via `bound_carriers_agree/4` (`settlement_execution_mismatch`) | `transition_plan_test.exs` "a settlement offered to a different execution's event is refused"; `atomic_bundle_test.exs` "a settlement cannot close an execution other than the one it settled" |
| A quarantined claim is not settled by an ordinary receipt | Core | `protected_primitives.ex` `settle_with_receipts/6` (`reconciliation_required` → `quarantine_conflicting_receipt/5`) | `durable_store/quarantine_exit_probe_test.exs` "fresh receipts of every outcome re-quarantine and leave the claim quarantined" |
| Reset facts: list-slot elements from distinct operations, each a well-formed `reset_fact_v1` | Core | `transition_plan.ex` `validate_binding_discriminator/1` (`list_slot_operation_repeated`); `valid_output?("reset_fact_v1", _)` | `transition_plan_test.exs` "two list-slot bindings from one operation are refused"; `atomic_bundle_test.exs` "an unconditional plan commits a ticket reset bound to its new ledger generation" |

Controller rows rest on `decide/3` alone, under the approved Q1/D1 and O2 readings. The
reference kernel enforces them; **an adversarial controller can violate them, and Core does
not claim them.** A controller that skips one can plan work the contract forbids, but it
still cannot pass a Core row above.

| Guarantee | Owner | Enforcement point | Evidence |
|---|---|---|---|
| No launch under pause | Controller | `workflow/kernel/control.ex` `require_not_paused/1`, called from `workflow/kernel/executions.ex` `do_transition("launch_planned", …)` | `workflow/kernel_test.exs` "launch_planned under pause refuses with control_paused" |
| No launch under drain | Controller | `kernel/control.ex` `require_not_draining/1`, same call site | `kernel_test.exs` "launch_planned under drain refuses with control_draining" |
| No launch under a pending cancel | Controller | `kernel/control.ex` `require_no_pending_cancel/1`, same call site | `kernel_test.exs` "#{type} under a pending cancel refuses with cancel_pending" |
| A retained attempt is reused, not replaced | Controller | `kernel/executions.ex` `open_attempt/2` (`retained_attempt_must_be_reused`) | `workflow/r4_guard_reachability_test.exs` "the forged-reference guards are exercised" |
| Phase guards on every transition | Controller | `workflow/kernel/shared.ex` `require_phase/2`, `require_attempt_phase/2` (`wrong_source_phase`) | `kernel_test.exs`, e.g. "a reset is refused unless the ticket is exhausted" |
| Exhaustion choice (which terminal disposition) | Controller | `workflow/kernel/software/dispositions.ex` `do_transition("attempt_settled", …)`; Core's `attempt_settlement` fact carries no disposition | `workflow/kernel_plan_test.exs` "close_attempt, attempt_settled, then cancellation_finalized" (plan shape only) |

<a id="r2"></a>

### R2: authenticated harness separated from arbitrary tools

Use separate principals for the root, authentication gateway, trusted OMP harness and
untrusted tool workers. Provision an exclusive non-admin worker account per concurrent
slot; no slot shares a writable home/process authority with the harness or other slots.
Only a fixed, operator-installed launcher can assign those accounts. Before slot reuse,
prove owned processes ended and revoke its capabilities; uncertainty prevents reuse.
FR-15a owns OS isolation/provisioning proof, FR-09 installed OMP conformance, FR-15 later
steering. Host provisioning requires explicit authority outside this design session.

Automatic executions use only explicitly authorized subscription profiles. Available
credentials or a model/provider name do not establish entitlement. No eligible profile
means affected work waits with a reason; quota observations retain freshness/uncertainty.
OpenRouter/DeepSeek paid use remains explicitly manual and outside automatic routing.

Reusable subscription authentication lives only in the protected authentication gateway,
never in a tool worker, candidate runtime, terminal shell, assignment, transcript or
model-visible file. The gateway uses the configured provider adapter; it is not a general
HTTP CONNECT proxy. It verifies a root-issued execution capability and durably claimed
request ID, then fixes provider/account/billing class/profile/model/reasoning and allowed
endpoint/operation from that execution's immutable assignment. It refuses arbitrary
URLs, auth-header forwarding, profile changes, hidden retries and new sessions. It strips
credentials from responses/logs. Each actual model request requires a reservation as
specified in R5. Provider retries are new claimed requests unless provider idempotency is
proved; an unknown prior outcome is reconciled or blocks further requests for that owner.

Trusted OMP runs pinned code/config with no candidate-loaded plugins, startup hooks,
auto-discovered executable project configuration or tools in its credential/network
principal. Its model calls go through the gateway; its execution capability is private
to the harness process. All model-directed shell/file/build/test tools execute through a
fixed bridge in the separate untrusted slot, with inert argv and validated paths. The
bridge gives no arbitrary code execution in the harness account. OMP may retain its
session there, but tool output is data and cannot select an endpoint or load a plugin.
Credential-free candidates and tools have OS-enforced denial of direct provider egress,
operator homes/keychains, harness process memory/IPC, auth socket and general forwarding
proxies. Any needed network acquisition uses a separately scoped, allowlisted fetch
service; inheriting the operator's unrestricted network/proxy environment is forbidden.

A second `omp` or `curl` launched by a tool thus has neither reusable authentication nor
access to the gateway capability/network path. Attempts to request extra model work from
the authorized harness still traverse per-request root claims and budgets. Authentication
refresh is gateway-internal maintenance with no model-execution permission. Herdr remains
operator-side optional presentation of sanitized output; attachment cannot yield the
operator's shell, harness capability or reusable credentials to the model.

This is a required adapter contract, **not a claim that installed OMP supports it**.
FR-09 must prove fixed gateway routing and remote tool execution with candidate extension
loading disabled under FR-15a isolation. If installed OMP cannot support the separation,
automatic execution stays blocked while a bounded OMP integration change is specified.
Do not replace OMP, copy credentials into tool slots, or enable paid fallback as a workaround.
No credentials, provider endpoints or model executions were inspected in this revision.

### Local command and inspection boundary

Use a Unix-domain socket with transport-derived peer/capability authentication, no exposed
BEAM distribution/eval. Tokens bind actor/role/execution, allowed operations, scope,
revocation generation and expiry; persist only digests. Operator steering credentials are
absent from all candidate/harness/tool contexts. Read-only status exposes canonical root
facts plus versioned domain projections, their freshness, last durable sequence, writer
identity and unknown/corrupt states. Inspect actual listeners; redact ordinary telemetry
and crash/status output; raw artifacts use controlled access. FR-02's inert RPC transport
is temporary containment, replaced by FR-15a's scoped protocol, not an authority credential.

## Identities and persisted records

Opaque random IDs are allocated once as explicit decision inputs; never infer identity
from ticket name, PID, pane or clock. Store installation UUID and repository/object-format
identity. An attempt owns work lineage, not a single reservation: each execution, check or
validation action owns its own reservation. The immutable relationships are:

| Entity | Binding |
|---|---|
| Objective/spec | objective_id → spec revisions with full assignment digests |
| Policy/control | policy_revision_id/control_id → authenticated operator command and prior revision |
| Ticket/attempt | ticket_id → objective/allocation/spec/scope/dependencies; attempt_id → ticket, ordinal, base, spec/policy snapshot |
| Execution/session | execution_id → attempt or PM objective, role, fixed profile, deadline generation; backend session/version/owned root → execution |
| Presentation | presentation_id → execution and separately verified pane/terminal/session identity |
| Artifact/candidate | raw artifact digest; candidate_id → repository/base/commit/tree/spec/attempt |
| Check/review | check_run_id or review_id → exact candidate, policy and independent execution/receipt |
| Reservation | reservation_id → ledger generation, dimension, units, exact execution/request/validation/effect owner |
| Effect/claim | effect_id → exact request digest and resources; claim_id → effect, writer epoch, policy/control revisions, reservations |
| Integration/deployment | integration_id → old/new refs/evidence; deployment_id → accepted source/build and compatibility/write set |

SQLite schema v1 contains metadata, authenticated input inbox, commands/results, ordered
events, projections, effects/claims/receipts, leases, ledger generations/reservations,
policy/control revisions and artifact references. Unique keys cover command ID, event seq,
effect ID, single active claim, request ID and receipt identity; foreign keys bind owners.
Separate protected rows from kernel domain projections. All mutations still use the same
transaction gateway; the protected and domain records do not form two independent stores.
Event, reducer/projection, protocol and SQL schema versions are distinct.

<a id="interfaces"></a>

### Command encoding and transaction protocol

Command envelope: `{schema_version, command_id, expected_revisions, type, target_ids,
payload}` with actor identity from transport. V1 semantic values are null, booleans,
signed 64-bit integers, Unicode scalar strings, arrays and objects with unique ASCII
schema keys; reject floats, duplicate keys, invalid UTF-8/surrogates and unknown fields.
Canonical bytes are UTF-8 JSON, no whitespace, keys sorted by ASCII byte order, shortest
base-10 integers, literal Unicode with no normalization; escape quote/backslash, encode
controls U+0000–001F as lowercase `\u00xx`, never escape slash. Hash a schema/domain-tagged
object containing actor ID and the complete semantic request, excluding bearer secrets.
Omitted and null differ unless that command schema explicitly normalizes them. Artifact
hashes instead cover original raw bytes. FR-08 supplies cross-client encoding vectors.

Authenticate access, compute digest, then look up existing command ID **before** checking
current revisions or dispatch policy. Same actor/ID/digest returns the original durable
result even after later state changes; changed actor/payload returns idempotency conflict.
A revoked submit token cannot mutate; its actor can retrieve an old result through an
independently authorized read capability. A lost reply is retried with the same ID.

For a new command, `expected_revisions` is the complete map of read/write entities,
including policy/control, parent ledgers, dependencies/resources and accepted ref when
relevant. The gateway compares every member and rejects incomplete/stale read sets.
IDs that must not exist use an explicit absent precondition. The verifier adds protected
reads the caller cannot omit. New semantic rejection is a durable command result but has
no domain mutation; malformed command envelopes or unauthenticated traffic are rejected
outside domain history. An authenticated valid submission envelope containing an invalid
artifact is a charged validation action, with a durable rejection under R5.

Input time, IDs, observations and deadlines are explicit immutable inputs to pure
`decide(state, command, inputs)`; `apply(state, event)` is the only domain reducer both
live and on replay. Replay reads no clock, Git, backend or current configuration. Kernel
upgrades replay in a versioned projection namespace; authoritative input/events remain.
The gateway verifies the bundle, then atomically commits command result, ordered events,
projections, ledger/lease changes and pending intents. Publish cache, dispatch and reply
only after checked commit. Cache failure reconstructs; store error fences effects and
returns unavailable/outcome_unknown, never success. Existing corrupt/unsupported stores
enter explicit recovery mode; missing store initialization is exclusive and explicit.

Event envelope: `{schema_version, seq, event_id, command_id, actor_id, entity_ids,
policy_revision_id, recorded_at, type, payload}` including decision inputs and disposition.
Result envelope: `{schema_version, command_id, disposition, reason_code, entity_revisions,
committed_seq, effect_ids, control}`. `accepted/rejected/blocked` describes a durable
decision, not external completion. For a control command, `control` contains control_id,
status, effective_policy_revision and outstanding_claim_ids as of committed_seq; otherwise
it is null. Cancellation/revocation pending is a control status, not a fourth command
disposition. Requery returns current status; idempotent replay returns the original result.
Authoritative success pointers are root-derived receipts.

<a id="r1"></a>

## Durable claims and recovery — R1

There is one ordering point: a short protected gateway transaction. Cancellation,
policy/control changes, epoch takeover, reservations and claim transitions serialize there.
An intent alone confers no execution authority. The operation protocol is:

| Effect state | Legal next state and condition |
|---|---|
| pending | claimed only after verifier checks current authority, exact request, prerequisite evidence, resources and reservations; or cancelled without issuance |
| claimed | issued by CAS of that claim under current epoch/control; or cancelled/revoked before issuance |
| issued | succeeded, failed or non_started on attributable receipt; unknown if outcome cannot be established |
| unknown | succeeded/failed/non_started only on reconciliation evidence; never redispatched by timeout |
| succeeded/failed/non_started/cancelled | Immutable outcome; duplicate delivery returns recorded state, no second action |

The `issued` commit is the irrevocable authorization boundary for **one exact bounded
external operation**, immediately before broker delivery. It records claim/request ID,
owner process incarnation, epoch, policy/control versions, prerequisites and reservations.
The broker may deliver it once; mark issued before delivery. Duplicate queue messages
return claim status. No generic bearer permit is handed to untrusted code. A trusted
worker receives a single fixed operation over its owned channel and cannot ask for a
second operation without another gateway claim. Crash after issued but before delivery is
ambiguous, not permission to resend. Steps of integration/deployment and individual model
requests have separate claims; authorization for one never covers its successors.
The root also enforces a semantic operation key (owner/role/phase generation/operation
ordinal), not just random effect IDs: a second ID cannot duplicate an outstanding launch,
prompt or ref update. A retry has a new ordinal referencing the terminal predecessor and
requires its non-start/failure/quiescence evidence. Cancellation scopes include descendant
attempts/executions/effects, so allocating new IDs cannot evade a cancelled ticket/objective.

| Ordering / interleaving | Required outcome |
|---|---|
| Cancel/revoke commits before claim or issue | pending/claimed productive effects cancelled; later claim/issue rejected; refund proved unissued holds |
| Issue commits before cancel/revoke | That fixed operation may finish after control acknowledgment; record it in the command's outstanding-claims result |
| Cancel while worker stalled before Git CAS | If issued, cancel is pending and CAS may complete; if only claimed, no CAS allowed |
| Duplicate dispatch/claim | Unique effect/claim and issued CAS admit at most one delivery; request mismatch rejected |
| Takeover before issue | Old claim cannot issue under new epoch; reclaim only after old owner/channel quiescence is proved |
| Takeover after issue | Retain old issued claim and leases; old action may settle; successor may observe it but cannot replace it blindly |

A cancel/revocation acknowledgment means **no subsequent productive issuance is allowed**,
not that previously issued work has ceased. Return durable control ID, committed sequence,
outstanding issued claim IDs and cancel_requested/revocation_pending control status. The
operator can query until settled; never return completed cancellation while an issued
operation could still run. Finalization accounts for sessions, prompts, check/build tools,
Git operations, release stop/switch/start and cleanup, not just panes. If an issued ref
update succeeds, preserve integrated fact, report cancelled-after-integration and inhibit
subsequent deployment. Revocation blocks later requests in an existing harness session;
interrupt/cleanup or rollback actions use the root's pre-existing safety-recovery authority.
They cannot broaden productive authority. A permission check without an issued record is
insufficient, and observing expiry alone proves neither termination nor non-start.

The broker owns the continuous OS fence and epoch. Old kernel connections cannot mint
claims after successor registration; old issued workers have only their fixed operation.
Before retrying an apparently absent Git/process effect, prove the old worker and delivery
channel cannot still perform it, then inspect the external outcome. Old ref equality or
missing pane alone is insufficient. A successor may retire an unissued claim and create
a new claim for the same intent after this proof, with existing holds; an issued effect
requires terminal non-start evidence or completion, not a new epoch as retry permission.
Unknown effects keep their leases. Unrelated work may proceed if its resources/policy do
not conflict. Root loss stops new issuance; it does not pretend issued work disappeared. Provider
requests already issued may have remote outcomes beyond process termination; killing a
local issuer alone cannot prove non-delivery or refund their holds.

Boot: fence → schema/input/replay validation → new epoch → reconcile outstanding claims,
owned sessions and observers → eligible scheduling. SQLite locking does not fence external
processes. All slow operations run in monitored, deadline-bounded owned workers outside
GenServer callbacks. Queries and controls stay responsive while cancellation is pending.
No exactly-once external execution is claimed; issued-to-receipt crashes can require
explicit reconciliation or operator recovery evidence. Unknown never implies safe retry.

Backend operations remain start/observe/prompt/interrupt/reconcile/close with effect and
execution IDs. Unsupported OMP delivery/reconnect yields unknown. Herdr presentation
identity is independent. Recycled IDs/missing ownership never authorize cleanup. Receipts
carry observation ID and claim ID; late old-epoch receipts can settle that claim and its
original ledger, but cannot advance a newer execution or create new authority.

<a id="r4"></a>

## Legal lifecycle and controls — R4

The following vocabularies and guarded rows define v2. Unlisted public transitions are
rejected with no domain mutation; stale/duplicate observations are retained/deduplicated
and do not mutate a newer owner. Resource waits carry `resume_phase` and reason. Domain
reducer ordering is durable event sequence, with raw receipt provenance checked by root.

| Entity | States / terminal boundary |
|---|---|
| Ticket phase | draft, queued, developing, awaiting_review, reviewing, ready_to_integrate, integrating, integrated, blocked, exhausted, rejected, cancelled |
| Attempt phase | active, candidate_frozen, checking, awaiting_review, reviewing, ready_to_integrate, integrating, terminal |
| Attempt disposition | Set once on terminal: integrated, needs_correction, failed, timed_out, blocked, exhausted, rejected, cancelled, superseded_base |
| Execution lifecycle | pending, starting, running, closing, closed, unknown; closed requires verified process/session termination or proved non-start |
| Execution result | Separate write-once sealed result: valid, blocked, partial, invalid, none; exit status/timeout/cancel are separate observations |
| Control | Orthogonal pause/drain flags; stop_requested → stop_completed (or pending with reason); per-target cancel_requested → cancel_finalized and revocation_pending → revocation_finalized with actual outcomes; not ticket phases |
| Check run | pending, running, passed, failed, timed_out, unknown, cancelled; bound to candidate/tree/check definition |

<a id="r4a"></a>

### Launch non-start recovery — R4a

Launch admission has three mutually exclusive outcomes. Capacity, dependency, resource,
profile or eligibility denial **before an intent** creates no execution, claim or
reservation: the ticket, review, PM plan or other work item stays in its scheduling phase,
and ordinary waiting does not increment an infrastructure-failure counter. An issued
launch with attributable proof that no process, backend session or model request started
settles the R1 effect as `non_started`, closes that execution as `closed`, and settles its
R5 start reservation exactly once as `released`. An issued launch whose start cannot be
disproved becomes `unknown`; it retains its reservation hold, execution slot and
conflicting leases and permits no replacement launch until R1 reconciliation proves
non-start or records the actual start/outcome.

Every proved non-start atomically records `(role, work_owner, predecessor_effect_id,
failure_class, infrastructure_attempt_ordinal)`, closes the execution, releases only its
execution/launcher/session resources, settles the original reservation and applies the
domain row below. A duplicate or late receipt is idempotent by claim/receipt identity and
cannot increment the ordinal or release twice. A retry is a new execution/effect with a
new reservation and semantic operation ordinal, referencing that terminal predecessor.
It is eligible only after the issuer/delivery channel is proved quiescent under R1 and the
predecessor reservation has reached its one-time R5 terminal settlement.

Protected policy sets a finite `launch_non_start_limit` per role and work owner. The
durable infrastructure ordinal consumes that allowance even though a proved non-start
refunds the process-start unit; this prevents an unlimited launch-failure loop without
pretending a process started. The allowance is neither fungible budget nor capacity
waiting. Changing it requires operator policy. A policy reset may create a new
infrastructure generation with an explicit finite allowance; it never erases predecessor
records. Restart, new execution IDs, profile changes, attempt resumption and duplicate
receipts do not reset the ordinal.

| Domain owner when launch settles `non_started` | Atomic transition and retained resources |
|---|---|
| Developer {R4a.01.f1}, active attempt before any valid result {R4a.01.f2} | Keep the **same nonterminal attempt** {R4a.01.o1} and immutable base/spec/policy lineage {R4a.01.o2}; return ticket `developing → queued` with `resume_phase: developing` and reason `developer_launch_non_started` {R4a.01.o3}. Release launch resources. {R4a.01.o4} Release its checkout/conflict lease only after proving the checkout was never exposed or mutated, then reacquire/revalidate it before retry {R4a.01.o5}; otherwise retain the lease and block affected work. {R4a.01.o6} Below the infrastructure limit, queue a bounded developer retry {R4a.01.o7}. At the limit, ticket becomes `blocked(developer_launch_infrastructure)` while the attempt remains active and resumable {R4a.01.o8}. Exhaustion of current developer allocation instead makes the attempt terminal `exhausted` and ticket `exhausted` {R4a.01.o9} |
| Reviewer {R4a.02.f1}, frozen candidate awaiting review {R4a.02.f2} | Keep attempt and ticket `awaiting_review` {R4a.02.o1}, immutable candidate/check receipts and reviewer ownership {R4a.02.o2}. Close only the failed reviewer execution {R4a.02.o3}; never enter developer retry or correction {R4a.02.o4}. Release reviewer launch resources {R4a.02.o5}; retain candidate custody and candidate/check leases. {R4a.02.o6} Below the limit, return to the durable reviewer queue. {R4a.02.o7} At the limit, ticket becomes `blocked(reviewer_launch_infrastructure)` with `resume_phase: awaiting_review` {R4a.02.o8}; the same attempt/candidate remain resumable {R4a.02.o9}. Missing current reviewer allocation yields `blocked(reviewer_budget)` or `exhausted` under protected policy, without discarding or approving the candidate {R4a.02.o10} |
| PM {R4a.03.f1} planning execution {R4a.03.f2} | Keep the same objective/spec-planning owner {R4a.03.o1}; infer no proposal {R4a.03.o2}. Release launch-only resources. {R4a.03.o3} Below the PM limit, return to its PM queue {R4a.03.o4}; at the limit or without current allocation, block as `pm_launch_infrastructure` or `pm_budget`. {R4a.03.o5} Admit no ticket and create no objective allocation {R4a.03.o6} |
| Check, freeze/import, build, integration or activation worker {R4a.04.f1} | Preserve its candidate/deployment phase and verified inputs {R4a.04.o1}; apply that phase's existing infrastructure retry/block row. {R4a.04.o2} Release only proved-unused launch resources. {R4a.04.o3} A retry references the predecessor and {R4a.04.o4} consumes its finite role-specific infrastructure allowance {R4a.04.o5}; infer no successful check/build/ref/release receipt {R4a.04.o6} |

Control state is evaluated after recording non-start and before queuing its successor.
Cancel settles the proved non-start/refund and finalizes cancellation when no other issued
work remains; it never retries. Pause retains the recoverable phase but forbids issue until
resume. Drain forbids developer and PM replacement launches, so their work becomes
`blocked(draining)` with the same resume phase and ordinal; reviewer, mandatory-check and
already-admitted finalization retries remain eligible under the existing drain rule. If
policy revocation or a budget-generation change makes a retry ineligible, preserve the
role-specific phase/owner and block or exhaust it; every retry reserves from the current
permitted generation. An old-generation refund settles that generation under R5 and
cannot finance the new retry implicitly.

Non-start settlement, domain transition, infrastructure ordinal and reservation settlement
commit together. Restart after settlement but before redispatch therefore reconstructs
exactly one queued/review/blocked owner and no live execution. Recovery neither replays
the settled launch nor increments its ordinal again. The scheduler may create only the
next effect referencing the recorded predecessor and only when current controls,
allocation, resources and the finite infrastructure allowance permit it.

A successful submission first enters the authenticated durable inbox with execution ID
and sequence; validation/freeze is an asynchronous effect. On exit, the broker seals that
execution's input stream with its last accepted sequence. It processes all inbox artifacts
through that sequence before deciding no valid result exists. Unknown stream completeness
blocks reconciliation; it is not a failed attempt. Messages arriving after sealing are
late evidence, never silently attached to a new attempt. Freeze copies immutable Git
objects into controller custody, verifies digest/full diff from that copy, and does not
run candidate hooks in the root. Mutable source paths are not frozen artifacts.

| From-state / input / guard | Domain outcome and owned actions |
|---|---|
| Objective without admitted spec {R4.01.f1}; broad steering {R4.01.f2} | Durable objective and bounded PM reservation {R4.01.o1}; PM proposal is evidence, not authority {R4.01.o2} |
| draft {R4.02.f1}; specific spec or valid PM create {R4.02.f2} | Common admission validates full assignment/policy/budget allocation {R4.02.o1}; queued or blocked with reason {R4.02.o2}; malformed spec rejected {R4.02.o3} |
| queued/blocked {R4.03.f1}; PM amend/park {R4.03.f2} | New future spec revision or explicit blocked state {R4.03.o1}; active assignments never edited {R4.03.o2}; amendment does not reset budgets {R4.03.o3} |
| queued {R4.04.f1}; dependencies/resources/profile/reservation eligible {R4.04.f2}; no pause/drain/cancel {R4.04.f3} | Create a fresh attempt unless R4a retained a resumable developer attempt {R4.04.o1}; create its launch intent and enter developing {R4.04.o2}. Pre-intent denial remains queued and consumes no start unit or infrastructure ordinal {R4.04.o3} |
| developing {R4.05.f1}; success artifact validates and freezes {R4.05.f2} | Attempt candidate_frozen {R4.05.o1}; ticket awaiting_review {R4.05.o2}; seal productive capability/deadline generation {R4.05.o3}; kernel requests developer close through broker immediately {R4.05.o4} |
| developing {R4.06.f1}; freeze/import infrastructure failure before valid candidate {R4.06.f2} | Retain submitted bytes {R4.06.o1}; bounded starts.check retry after owned worker closure {R4.06.o2}; blocked(freeze_failure) when unavailable {R4.06.o3}; unknown preserves lease. {R4.06.o4} Git/scope validation failure is invalid submission {R4.06.o5}, never a frozen result {R4.06.o6} |
| candidate_frozen {R4.07.f1}; developer exit/timeout/abnormal exit {R4.07.f2} | Cleanup observation only {R4.07.o1}; preserve frozen candidate {R4.07.o2}. No new developer and no attempt failure {R4.07.o3} |
| developing {R4.08.f1}; sealed stream has no valid candidate {R4.08.f2}, verified exit/timeout {R4.08.f3} | Attempt terminal failed/timed_out {R4.08.o1}; after cleanup queue fresh bounded attempt or exhaust {R4.08.o2}; normal exit alone is not success {R4.08.o3} |
| developing {R4.09.f1}; valid blocked/partial result {R4.09.f2} | Terminal blocked attempt, blocked ticket {R4.09.o1}; close developer {R4.09.o2}, no review {R4.09.o3}. Resume/rescope requires explicit command and fresh attempt {R4.09.o4} |
| any open submission phase {R4.10.f1}; malformed result {R4.10.f2} | Durable rejected submission, charge one validation action {R4.10.o1}; further submission allowed only while stream open {R4.10.o2} and budget remains {R4.10.o3}; exhaustion closes execution and exhausts ticket {R4.10.o4} |
| candidate_frozen {R4.11.f1}; developer closed {R4.11.f2}, check capacity eligible {R4.11.f3} | checking attempt, awaiting_review ticket {R4.11.o1}; schedule root-mandated check workers before reviewer {R4.11.o2}, retaining immutable candidate {R4.11.o3} |
| checking {R4.12.f1}; all mandatory check receipts passed {R4.12.f2} | awaiting_review attempt {R4.12.o1}; queue independent reviewer {R4.12.o2}; checks with explicit policy-empty set follow same guarded transition {R4.12.o3} |
| checking {R4.13.f1}; actual check assertion fails {R4.13.f2} | Terminal needs_correction attempt {R4.13.o1}; queue fresh developer after all check workers close {R4.13.o2}, or blocked(drain)/exhausted; failed candidate never goes to approval {R4.13.o3} |
| checking {R4.14.f1}; tool/infrastructure failure or timeout {R4.14.f2} | Preserve candidate, bounded new check-run reservation after cleanup {R4.14.o1}; pending same phase {R4.14.o2}, or blocked(check_infrastructure)/exhausted {R4.14.o3}. Unknown check retains lease and blocks retry {R4.14.o4} |
| awaiting_review {R4.15.f1}; check receipts valid {R4.15.f2} and reviewer capacity available {R4.15.f3} | reviewing attempt/ticket, independent reviewer launch with its own reservation {R4.15.o1}; R4a returns a proved non-start to this same candidate/role queue {R4.15.o2} |
| reviewing {R4.16.f1}; valid approved exact-candidate verdict {R4.16.f2} | Close/seal reviewer {R4.16.o1}; after verified close ready_to_integrate {R4.16.o2}; no Git success inferred {R4.16.o3} |
| reviewing {R4.17.f1}; correction verdict {R4.17.f2} | Terminal needs_correction attempt {R4.17.o1}; close/seal reviewer, then queued fresh developer {R4.17.o2} or blocked(drain)/exhausted; never re-prompt old developer {R4.17.o3} |
| reviewing {R4.18.f1}; rejected verdict {R4.18.f2} | Terminal rejected attempt/ticket {R4.18.o1}; cleanup pending separately {R4.18.o2}; later work needs explicitly admitted revision {R4.18.o3} |
| reviewing {R4.19.f1}; sealed stream no valid verdict {R4.19.f2} and reviewer crash/timeout {R4.19.f3} | Preserve candidate, close reviewer then bounded new reviewer execution {R4.19.o1}; developer ledger untouched {R4.19.o2}; exhaust if unavailable {R4.19.o3} |
| ready_to_integrate {R4.20.f1}; current base/evidence/policy valid {R4.20.f2} | integrating ticket/attempt {R4.20.o1}; root integration intent, then R1 claim/issue {R4.20.o2} |
| ready_to_integrate/integrating {R4.21.f1}; accepted base moved before issuance {R4.21.f2} | Terminal superseded_base attempt {R4.21.o1}; fresh bounded rebase developer plus renewed checks/review {R4.21.o2}; blocked under drain or budget exhaustion {R4.21.o3} |
| integrating {R4.22.f1}; successful ref receipt {R4.22.f2} and prior role/check workers closed {R4.22.f3} | integrated ticket {R4.22.o1}; terminal integrated attempt {R4.22.o2}; deployment is separate. {R4.22.o3} Exit notifications cannot overwrite this {R4.22.o4} |
| integrating {R4.23.f1}; proved no ref change {R4.23.f2}, command infrastructure failed {R4.23.f3} | Same phase with bounded integration-effect retry after old issuer termination {R4.23.o1}; or blocked(integration_failure) {R4.23.o2}. Conflict uses moved-base row {R4.23.o3}; unknown blocks reconciliation {R4.23.o4} |
| blocked {R4.24.f1}; explicit resume or recorded dependency/resource recovery {R4.24.f2} | Revalidate spec/control/policy and existing allocation {R4.24.o1}; return to stored resume_phase {R4.24.o2}; fresh attempt only if prior attempt terminal. {R4.24.o3} Partial/rescope and explicit operator blocks require steering, not automatic unblocking {R4.24.o4} |
| exhausted {R4.25.f1}; authenticated reset grants eligible units {R4.25.f2} and explicitly resumes {R4.25.f3} | Keep old attempt terminal {R4.25.o1}; queue a fresh developer attempt using retained evidence as context {R4.25.o2}, with newly bound checks/review {R4.25.o3}; block if that role lacks allocation {R4.25.o4}; never reset prior consumption {R4.25.o5} |
| integrated/rejected/cancelled {R4.26.f1}; ordinary launch/result/completion command {R4.26.f2} | Reject transition {R4.26.o1}; preserve terminal facts {R4.26.o2}. New work requires explicit admission linked to predecessor, with parent-funded allocation {R4.26.o3} |
| nonterminal ticket {R4.27.f1}; cancel requested {R4.27.f2} | Set orthogonal control, cancel pending/unissued effects, request owned interrupts {R4.27.o1}; hold phase/evidence while issued effects reconcile {R4.27.o2} |
| cancel_requested {R4.28.f1}; every owned session AND non-session claim terminal {R4.28.f2}, cleanup reconciled {R4.28.f3} | If no integration occurred: cancelled ticket and active attempt terminal cancelled {R4.28.o1}; already terminal dispositions retained. {R4.28.o2} If integration occurred: integrated and cancel_finalized(after_integration) {R4.28.o3}; suppress deployment {R4.28.o4} |

Exhaustion seals the current attempt with exhausted disposition. A resumable resource or
infrastructure block retains its attempt phase unless a row explicitly terminates it.
Reset never reopens a terminal attempt or reattributes its candidate/review to a new ID.

A valid frozen developer candidate or validated review result takes precedence over later
execution exit status. Until that result validates, sealed inbox processing precedes exit
failure. The close effect is independent of a review notification; successful developers
do not remain alive waiting for review. Invalidate productive timers atomically when the
result is accepted; cleanup deadlines cannot change the work verdict. Execution closure
releases CPU slots, not necessarily the candidate/resource leases needed by checks/review.
If cleanup is unknown, block affected work and retain capacity. A check failure uses its
controller exit/receipt reason_code (assertion_failed, infrastructure_failed or timed_out),
not an agent's assertion of infrastructure error.

Controls: pause blocks new productive issuance, allowing receipt processing/cleanup.
Drain blocks new tickets, PM and developer issuance but permits already admitted checks,
reviews and integration to settle; no new deployment starts. Corrections/rebases during
drain become blocked with resume_phase=queued and reason=draining; stop does not wait for
a forbidden fresh developer. Stop completes only after all issued effects/owned processes
and necessary cleanup settle, storing queued/blocked/correction work for restart. Unknown
work reports stop-blocked; no unconditional shutdown success. A force shutdown may be an
explicit operator recovery action and retains unknown records. Clearing drain/resuming
revalidates admission/budget, never grants new allowance. Cancellation also covers
check/build/import/ref/activation effects using R1: before switch abort staging; after
issued switch, root recovery finishes safe start/health or compatible rollback and records
actual deployment outcome. It never deletes accepted source or newer acknowledged work.

Schedule checks and reviewers ahead of new developers once ready, and finite already
admitted finalization work ahead of admission. All productive roles and check/build
workers consume configured process capacity. With capacity one, developer closes, checks
run and close, then reviewer runs and closes. Resource conflicts still block; waiting or
unknown ownership is visible, not charged as a launch failure. Priority/autonomy changes
are durable steering, applied at claim/issue, not only in the scheduler's in-memory queue.

<a id="r5"></a>

## Budget ledger — R5

Limits are supplied by protected operator policy, not chosen numerically here. V2 uses
integer dimensions: `starts.pm`, `starts.developer`, `starts.reviewer`, `starts.check`,
`starts.build`, `operations.integration`, `operations.activation`, `model_requests`, and
`validations` (one schema/artifact validation action, distinct from mandatory check runs).
Retry ceilings may be narrower per-role/attempt but cannot enlarge these ledgers. No
conversion between units. Each model execution additionally has a gateway-enforced request
cap and broker-enforced elapsed deadline; token/currency usage is diagnostic unless a
provider can enforce an explicit upper bound. Unknown usage is never zero or a token-budget
proof. Subscription starts/requests are bounded even if token usage is unavailable.

At steering, root creates objective ledger generations with explicit authorized units.
PM consumes that objective's PM and model-request units. Tickets receive child allocations
by atomic transfer from the parent's **available** units; no new allowance on ticket/spec
creation. Child model-request/start/check/validation dimensions come from the same objective.
A ticket cannot move unused reviewer units into developer units. PM proposes allocation;
root checks permitted envelope, parent balance and scope. Correction, rebase, crash retry,
profile switch and amendment retain the same objective/ticket allocations; new execution
or effect means a new reservation charged to the appropriate existing dimension.

For each dimension/generation use nonnegative integer balances:
`authorized = available + held + consumed + delegated + retired`.
Parent-to-child transfer moves parent available→delegated and creates equal child
authorized/available in one transaction. Returning unused child available reduces child
authorized and parent delegated, increasing parent available; consumed/held cannot return.
Across the tree, root authorized equals the sum of available+held+consumed+retired over
all nodes (exclude delegated to avoid double counting). An objective cannot be duplicated
to escape its envelope: only authenticated steering creates a new root grant. PM splitting,
cloning or amending work never grants credits. Per-policy global/account caps may further
restrict the root grants and every issuance.

Reservation key: random reservation_id with immutable `(ledger_id, generation, dimension,
units, owner_kind, owner_id)`. Launch/start reservations belong to execution/check-run/build
IDs; model-request reservations belong to `(execution_id, request_id)`; integration and
activation step reservations to effect IDs; validation to authenticated submission/action
ID. An attempt groups these reservations but owns no fungible refill. Each concrete
productive external step consumes its declared units; rollback/cleanup use a separately
bounded root recovery pool, inaccessible to candidate productive work. If recovery capacity
is exhausted, report recovery_required, not an unlimited retry or a successful stop.

| Reservation transition | Ledger movement / guard |
|---|---|
| absent → reserved | available→held, atomically with intent; reject insufficient balance; no units for scheduler denial |
| reserved → issued_unknown | Hold unchanged at R1 issued commit; includes possible start/delivery; unavailable for reuse |
| reserved → released | held→available only for proved unissued cancellation/non-start |
| issued_unknown → consumed | held→consumed on confirmed process start/request delivery/operation execution, regardless of later success or failure |
| issued_unknown → released | held→available only on proven non-start/non-delivery after old issuer/channel quiescence |
| reserved → consumed for validation | Charge once in the same protected action/result transaction; lost reply or same command ID does not recharge |
| consumed/released → same terminal state | Duplicate receipts idempotent; conflicting receipts quarantine the owner for reconciliation, never mint credit |

Unknown is **held**, not prematurely settled consumed; this replaces v1's ambiguous
consume-on-uncertainty phrasing. A confirmed start stays consumed even if execution later
fails or is cancelled. Reviewer retries each charge reviewer start and their model calls,
not another developer start. Each freeze/import/mandatory-check worker charges starts.check;
its trusted classification/required operation mapping is fixed in the root policy. A proved non-start may release its start unit, while a new
validation or confirmed backend request remains charged in its own dimension. Invalid
unauthenticated traffic has separate transport rate limits and cannot debit a ticket.
Authenticated valid submission commands with malformed artifacts consume validation units;
their exact duplicates
do not. Check infrastructure retry charges a new check start; assertion failure charges
subsequent developer work only if a correction actually starts. Scheduler/slot denial
before intent reservation debits nothing; failure after reservation follows this table.
R4a's durable infrastructure ordinal separately bounds repeated proved non-starts. It is
incremented once per terminal launch effect and is not paid from the released start unit.

Reset is an authenticated, idempotent **generation change with an explicit grant**, not
zeroing counters. Close old generation to new reservations; revoke unissued productive
claims, preserve outstanding issued holds/consumption and mark unused availability retired.
Apply this recursively to its delegated subtree; old delegated balances remain accounted
for by their descendants. New generation receives only explicitly operator-granted units
subject to parent allocation/global caps, or an explicit atomic transfer of old unspent
units. Such transfer decreases old authorized/retired and increases new authorized; it
never includes held/consumed units. A child reset alone cannot create a parent grant.

Receipts always settle their original generation. A late non-start in a closed generation
moves held→retired, not into the new available balance; a late start moves held→consumed.
Old holds remain outstanding against global/account limits alongside any new grant. When
policy demands a total ceiling, new grants are refused unless the ceiling includes old
holds and consumption. Only explicit operator steering can change that ceiling. Keep all
old reservations/receipts and reset provenance; restart rebuilds their conservation
invariants. No implicit credits from a new profile, attempt, ticket or projection version.

<a id="integration"></a>

## Integration, activation and compatibility

Fast-forward accepted ref only if candidate base equals current accepted ref and actual
ancestry/scope/full diff pass. Freeze/import Git objects in a hook-disabled isolated
worker, verify content in controller custody, then generate controller check receipts and
independent review of that exact tree/spec/policy. Untrusted concurrent writers cannot
replace imported objects or build outputs; copy into root-owned staging and verify digest
there before atomic publication. Any changed candidate/base requires fresh bounded rebase
work, checks and review, not an unreviewed merge tree.

Integration uses R1's durable issued claim before fixed `git update-ref old→new`. After
crash, new ref with matching verified objects settles success; third ref is conflict;
old ref permits retry only after proving the old issuer/channel cannot act and settling
non-start/failure under R1. Kernel cannot write accepted refs. Keep slow checks/Git outside
gateway callbacks; cancelled/unknown integration reports actual refs and outstanding claims.

Build accepted source from pinned dependency/toolchain/config/role inputs in an isolated
worker. Controller verifies immutable outputs and manifest before private publication.
Separate accepted source, selected deployment and healthy build pointers. A manifest lists
kernel/runtime artifacts and root ABI but cannot authorize overwriting root binaries,
gates or policy. Root deploys kernel/runtime as restricted principals, not as itself.

Deployment: requested→built→draining→stopped→switched→starting→healthy; failures go to
failed→rolling_back→recovered or recovery_required. Each productive step has its own R1
claim and R5 operation/start reservation. Build failure retains running old service. Root
stays alive while kernel stops; correct release stop/start plus observed process exit and
readiness replaces sleeps/watcher rebuilds. A cancellation before issue blocks that step;
after issue, settle it then use the bounded recovery pool for safe start or rollback.
External health verifies loaded manifest/process identity, protocol behavior, replay of
acknowledged commands and receipt reconciliation. Candidate-reported health is insufficient.

Compatibility is a verified **write-set inclusion**, not overlap of declared ranges:
every SQL/event/protocol version the candidate can cause to be committed must be readable
and semantically handled by the rollback build and supported by the fixed verifier. Root
rejects writes outside that activation's allowlist. Validate on retained authoritative
history and new-version command scenarios. Kernel projection caches can be regenerated;
never restore an old snapshot over newer committed inputs/events/receipts. Routine kernel
repairs within the permitted write set activate autonomously. Root/unsupported schema
changes require operator maintenance with drain, checked backup and transactional
migration; failed compatibility leaves effects fenced in explicit recovery mode.

SQLite remains provisional on the recorded maintenance/conformance grounds; v2 adds no
storage measurement. FR-07 repeats the shared cases using the actual Elixir binding and
separate SQL rows, including sync/write errors, torn/oversize import, constraints, replay
and migration rerun. FR-19 owns physical capacity/WAL/checkpoint/compaction interruptions,
verified archival and offline relocation. Backup uses SQLite backup facility, not a bare
copy of a WAL DB; verify full content/replay, not just row count. Retain original JSONL
and a digest/range/error import manifest, never skip authority silently or fabricate legacy
receipts. Diagnostic retention cannot erase authoritative work.

## Review and implementation gates

R1–R5 are resolved at design level. See the
[v2 response](fr-06/review-response-v2.md) for precise passages, arguments and deferred
evidence, and [verification](fr-06/verification.md) for input provenance and limits.
The [focused R4a review](fr-06/r4a-focused-review.md) verified the exact revision-3
inputs and returned **PASS** without reopening R1/R2/R3/R5. FR-07 still waits for its
FR-03 prerequisite. No implementation behavior, account provisioning, storage fault
conformance, provider behavior, or activation is certified by this design disposition.
