# Foundry Pi harness design

**Status:** design candidate, 2026-09-19. This document does **not** adopt Pi, replace
OMP, enable automatic model execution, approve a provider/billing route, or weaken any
repair gate. The active [repair plan](REPAIR-PLAN.md) and
[workflow contract](WORKFLOW-CONTRACT.md) remain governing until their owning requirements
are explicitly revised and re-reviewed.

[Foundry strategy](STRATEGY.md#pi-explicit-session-contracts-and-replaceable-execution) ·
[Observability](OBSERVABILITY.md) ·
[Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md) ·
[Research sources](../../docs/strategy/RESEARCH.md)

### Use this document by task

| Task | Section |
|---|---|
| Understand the architecture/ownership split | [Decision summary](#1-decision-summary), [ownership](#4-ownership-boundary), [topology](#6-recommended-governed-topology) |
| Implement the adapter | [Execution contract](#5-harness-neutral-execution-contract), [loadout](#7-deterministic-loadout-and-configuration), then the P0/P1/P2 scope below |
| Add Claude-like ergonomics | [Feature disposition](#8-claude-like-feature-disposition) |
| Review security/isolation | [Threat model](#10-bridge-threat-model), [provider/billing](#11-provider-and-billing-boundary), [conformance](#14-conformance-matrix) |
| Review observability/efficiency | [Observability](#12-observability-integration), then the context/compaction feature disposition |
| Decide adoption | [Rollout gates](#15-rollout-and-adoption-gates), [upgrade policy](#17-upgrade-policy) |

## 1. Decision summary

Use Pi as the preferred **replacement harness candidate**, not as a new Foundry control
plane. The target is "Claude-quality coding ergonomics under Foundry-quality authority":

- Pi owns the model/session loop, streaming, context plumbing, compaction hooks and
  optional interactive UI.
- Foundry owns admitted intent, assignment/execution identity, capability grants,
  provider/billing authorization, budgets, child-work admission, effect execution,
  evidence, acceptance, recovery and activation.
- A small pinned Foundry bridge may translate Pi tool/lifecycle events into Foundry
  requests and observations. It must not become a scheduler, authority store, retry
  engine or second workflow runtime.
- Governed runs load an explicit pinned Pi build, bridge and approved resources. They do
  not inherit arbitrary user-level or project-local extensions, agents, prompts, skills,
  MCP servers or configuration.
- Model-directed access to project/host resources—reads, writes, processes, network,
  language services and other executable effects—crosses Foundry's admitted capability
  gateway and the FR-15a isolation boundary (or an equivalently proven OS restriction).
  Merely hiding Pi tools is not an authority boundary.
- Pi-local task lists, direct Pi subagent spawning and ambient agent teams are not
  authoritative workflow mechanisms. Delegation requests go to Foundry, which may admit
  bounded child/sibling assignments.
- Session branches and checkpoints are context conveniences. They never rewind budgets,
  grants, accepted artifacts, effect history or other durable authority.
- Source-qualified Pi token/cache/cost/context and compaction observations feed
  Foundry's versioned observation contract. Unknown usage stays unknown.
- Pi does not graduate from candidate to production harness until the same lifecycle,
  billing, isolation, recovery and useful-completion requirements governing the current
  OMP route pass against an exact pinned candidate.

This design deliberately preserves Pi's minimalism. We should add the conveniences that
remove recurring operator/model friction, not recreate every Claude Code feature.

## 2. Why this composition

Claude Code is a mature coding product with useful batteries included: permission modes,
plan mode, isolated subagents, hooks, skills, code intelligence, checkpoints, background
work and external-tool integration. Pi intentionally exposes a smaller core plus extension,
skill, prompt, session and RPC surfaces. Pi's upstream examples already demonstrate plan
mode, permission interception, protected paths, subagents, Git checkpoints, status UI and
sandbox/tool-routing patterns.

Those examples are **implementation references**, not automatically trusted Foundry
components. In particular, an upstream example that directly launches child Pi processes
or executes a tool on the Pi host would bypass Foundry if copied literally.

The architectural opportunity is therefore to keep the useful Pi primitives while moving
the consequential semantics one layer up:

    model experience
        Pi modes / skills / sessions / UI
                    |
                    v
        small Foundry Pi bridge
                    |
                    v
    admitted Foundry execution contract
        identity / grants / budget / evidence
                    |
                    v
      isolated effects and typed services

This avoids two failure modes:

1. **Claude clone drift:** Pi slowly accumulates its own task system, permissions,
   orchestrator, memory, sandbox policy and agent hierarchy until Foundry merely wraps a
   second control plane.
2. **Thin-wrapper theater:** Pi is declared "minimal" while direct shell, extensions or
   project configuration still have ambient host/provider authority that Foundry cannot
   observe or constrain.

## 3. Non-goals

This design does not:

- make Pi a security boundary;
- implement or endorse an unofficial provider-authentication or billing bypass;
- assume a Claude Code subscription is usable from Pi;
- recreate Claude Code Agent Teams inside Pi;
- make session state authoritative workflow state;
- add a second durable task database;
- permit project-controlled code to install controller-side extensions;
- make every MCP server or local tool visible to every assignment;
- treat a Plan-mode UI toggle as authorization;
- make a model's "done", "[DONE:n]" or equivalent marker acceptance evidence;
- make compaction summaries durable truth;
- give child work broader scope or budget than policy allows;
- fund multiple production harness adapters before one candidate proves the contract.

## 4. Ownership boundary

| Concern | Pi | Foundry | Project profile / worker |
|---|---|---|---|
| model turn loop and streaming | owns | observes | — |
| conversation/session tree | owns | correlates | — |
| context rendering/compaction plumbing | owns | constrains mandatory inputs, observes | may supply admitted context |
| interactive commands/status | owns presentation | supplies authoritative facts | — |
| assignment/workflow identity | display only | **owns** | requests only |
| permissions/capabilities | may hide/shape tools | **owns and enforces** | requests subset |
| provider/model/billing authorization | executes admitted route | **owns admission and evidence** | no authority |
| project/host read access | presents bounded context/tools | **owns/mediates readable scope** | constrained worker/service |
| executable tools | presents tool schemas | **owns gateway/authorization** | isolated implementation |
| shell/filesystem/network isolation | no security claim | **owns required contract** | constrained worker |
| child/subagent creation | presents request/result | **owns admission/lifecycle/budget** | child receives bounded grant |
| evidence/check receipts | renders | **owns validation/custody** | produces untrusted outputs/receipts |
| review independence | no authority | **owns lineage predicate** | role label is contextual |
| acceptance/promotion/deployment | no authority | **owns** | cannot self-promote |
| usage/context observations | emits source data | correlates/retains quality | — |
| learned skills/policy | can load pinned content | approves governing changes | may propose |

A Pi extension may make the user experience richer without acquiring the right-hand
column's authority.

## 5. Harness-neutral execution contract

The durable Foundry boundary remains deliberately smaller than Pi's full API:

- `start`
- `observe`
- `prompt`
- `interrupt`
- `reconcile`
- `close`
- `usage`

The Elixir control plane should depend on this contract, not directly on Pi concepts such
as a TUI widget, extension event or session-file layout.

### 5.1 Start

Input conceptually includes:

- assignment/execution identity;
- exact checkout/workspace;
- admitted execution profile;
- exact model/provider/billing selection already authorized by Foundry;
- exact Pi build and bridge/resource manifest;
- context/bootstrap references;
- isolation profile;
- deadlines/resource ceilings.

Output must include a fresh, opaque execution/session identity sufficient to distinguish a
new incarnation from stale observations.

Starting a Pi process is an external effect. Foundry must durably record intent/issue and
reconcile uncertain outcomes according to the governing workflow contract.

### 5.2 Observe

Observation must distinguish at least:

- process/session exists;
- model is idle/busy;
- a request was acknowledged;
- a turn/tool call is active;
- queued input exists where the pinned Pi protocol exposes it;
- last observable activity;
- context/usage statistics and their source quality;
- termination/abort/error state.

None of these facts alone means workflow progress, completion or acceptance.

### 5.3 Prompt

A prompt response that means accepted/queued/handled is not completion. The adapter must
correlate:

    assignment -> attempt -> execution -> model request/turn

Foundry's existing checkpointed prompt-delivery semantics must be re-evaluated against the
pinned Pi RPC protocol. Lost acknowledgements, duplicate delivery and ambiguous restart
must never be converted into blind re-prompting.

### 5.4 Interrupt

Interruption must have tested semantics for:

- an active model request;
- an active tool request;
- queued/follow-up input;
- already-terminated execution;
- process loss during abort;
- child/background work owned by the assignment.

"Ctrl+C was sent" is an issued effect, not proof that execution stopped.

### 5.5 Reconcile

After controller or Pi restart, Foundry must be able to decide one of:

- same verified execution can be reattached/observed;
- execution is definitely gone;
- execution identity changed and must not be controlled as the old assignment;
- outcome remains unknown and blocks retry pending bounded reconciliation.

Conversation continuity is optional evidence. It cannot recreate expired execution
authority.

### 5.6 Close

Close must be idempotent from the workflow perspective and must preserve resources whose
ownership/incarnation cannot be verified. Presentation cleanup, Pi process cleanup,
sandbox cleanup and child-job cleanup are separate facts.

### 5.7 Usage

The adapter should preserve source-qualified values when Pi exposes them:

- input tokens;
- output tokens;
- cache reads;
- cache writes;
- reasoning/other token classes if exposed;
- total/context utilization;
- provider-reported cost;
- compaction usage and before/after estimates;
- model identity;
- turn/request counts.

Missing fields are `unknown`, not zero. Provider-reported cost is diagnostic and does
not replace Foundry's budget ledger or subscription-capacity accounting.

## 6. Recommended governed topology

The preferred first experiment separates both **model requests** and **project/host
effects** from ambient authority. Post-hoc usage observation is not a budget boundary.

    protected Foundry controller
        |
        +-- provider/request gateway
        |      |
        |   reservation / exact admitted route
        |      |
        |   reusable provider authentication
        |      |
        |      v
        |   model provider
        |
        +-- launches pinned Pi RPC process
        |      |
        |      +-- execution-scoped provider route
        |      +-- pinned Foundry bridge only
        |      X-- no reusable provider credential where avoidable
        |      X-- no ambient executable extensions
        |      X-- no direct host filesystem/process/network tools
        |
        +-- per-execution authenticated control channel
               |
               v
          effect gateway
               |
        CapabilityGrant check
               |
      isolated workspace/tool worker
               |
        filesystem/shell/build/test

The bridge should receive an execution-scoped handle, not a reusable operator/provider
credential. That handle stays in the protected Pi/bridge principal: it is not copied into
model context, worker environment, tool output, child input or diagnostic logs. The Pi
process should start from a controller-owned **neutral control working directory**, not
the candidate checkout, unless a later conformance result proves an equally strong
configuration-discovery boundary. The candidate workspace is an explicit gateway resource, not ambient process CWD. In
this topology, model-visible filesystem read/search, mutation, shell, language-service and
network operations are mediated through the gateway or another
equivalently proven restricted principal; a "read-only" Pi builtin must not retain ambient
access to the operator home or provider secrets. A concrete resource/effect request
carries an invocation identity and is checked against the durable assignment/grant.

Example conceptual request:

    execution_id
    invocation_id
    operation = workspace.edit
    resource = lib/example.ex
    payload_digest / bounded payload
    expected workspace/candidate generation

Foundry derives the maximum allowed project, workspace, operation and scope from the
authenticated execution. It does not trust model-supplied role/project/scope strings as
authorization.

### 6.1 Why not "Pi plus sandboxed Bash"

Because extensions run where Pi runs, and read authority matters too. Sandboxing only a
built-in Bash tool is insufficient if another active extension/tool can spawn a host
process, or if a built-in read/search/file-inclusion path can inspect provider credentials,
operator-home files or another workspace.

The governed loadout therefore needs a complete **resource and executable path**
inventory—not a tool-name allowlist alone—including file references/attachments,
read/search helpers, language servers, build hooks, extensions, subprocesses and network
clients that can be influenced by model or candidate input.

### 6.2 Provider request authority

Every provider request—including the first prompt, tool-loop continuation, retry,
compaction/summarization call and child request—must cross a budget/accounting boundary
**before** issue. Foundry needs a durable reservation/claim before a request can consume
subscription capacity or money; a crash after possible issue retains an unknown hold
until reconciliation.

The preferred mechanism is a Foundry-owned local request broker/proxy that fixes the
admitted provider/model/account route and keeps reusable provider authentication out of
Pi. If the selected subscription mechanism cannot operate through such a broker, an
alternative pinned trusted provider adapter must prove an equivalent pre-request
reservation handshake and must be unable to issue when Foundry refuses it.

If neither mechanism is compatible with the intended official subscription route, Pi is
not yet a conforming production replacement. Do not weaken durable request budgets into
post-hoc token accounting to make the harness fit.

### 6.3 Alternative whole-Pi sandbox

Running all of Pi inside the worker may eventually be attractive, but only if provider
authentication/request authority is separately brokered so model-directed code cannot
read reusable credentials or issue unreserved requests. That topology is a later
experiment, not the initial assumption.

## 7. Deterministic loadout and configuration

A governed run must be reproducible from a controller-owned manifest that binds at least:

- exact Pi version/revision and executable digest;
- exact bridge revision/digest;
- exact approved extension list;
- exact active tool schemas;
- exact approved skills/prompts/context resources and digests;
- governing instruction/router bundle and base revision/digest;
- provider/model/profile selection and provider-request gateway/adapter identity;
- model-request reservation/receipt protocol revision;
- isolated session-storage root, retention/redaction policy and resume policy;
- isolation profile;
- project/workflow/role/context-policy revision;
- relevant environment allowlist;
- protocol version.

For governed runs, ambient discovery is fail-closed:

- user-level Pi extensions are not inherited;
- project-local extensions are not auto-loaded;
- project-local agents are not auto-executable;
- user/project prompt libraries are not implicitly authoritative;
- arbitrary prior Pi sessions are not selectable/resumable across assignment boundaries;
- arbitrary MCP servers are not auto-discovered;
- unknown execution-changing settings refuse rather than silently apply.

A candidate checkout may contain a **proposal** to change a project profile, skill,
extension or repository instruction file, but it cannot modify the active manifest or
governing instruction bundle for its own execution. Candidate-modified `AGENTS.md`,
skills or prompts are inspectable candidate data until separately reviewed/admitted;
they are not silently reloaded as higher-priority instructions mid-assignment.

Governed session persistence uses an assignment/execution-scoped storage root with
controller-chosen permissions and retention. A Pi "resume" or session tree cannot select
a transcript from another assignment merely because the same host user can see it.
Session transcripts may contain source/tool/model data and require the same privacy and
diagnostic-boundary treatment as other retained context.

Interactive human Pi usage may have a more permissive convenience profile, but that
profile is not evidence for autonomous Foundry conformance.

## 8. Claude-like feature disposition

### 8.1 Permission modes — P0

**Adopt the ergonomics, not the trust model.**

Pi may expose recognizable modes such as inspect/plan/work/review, but the active tool
surface is a projection of an admitted CapabilityGrant.

Example:

| Mode | Typical visible capabilities | Enforced meaning |
|---|---|---|
| inspect | read, search, symbols, diagnostics | no mutation/effect grant |
| plan | inspect + clarification + workflow proposal | still no candidate mutation |
| work | scoped write, approved shell/checks, delegation request | exact admitted grant |
| review | candidate/evidence read, review checks, finding submit | no candidate mutation |

If the UI accidentally exposes `write` during review, the gateway still refuses it. If
the UI hides `write` during work, the assignment merely loses convenience; authority is
not inferred from visibility.

There is no governed equivalent of an unrestricted "bypass permissions" mode.

### 8.2 Plan mode — P0/P1 UX

Pi upstream's plan-mode example is a useful interaction pattern: read-only exploration,
plan extraction and later execution. Foundry should adapt the pattern so that the result
is a `PlanningProposal`, not a local authoritative todo list.

Flow:

    enter plan projection
      -> inspect/read only
      -> model proposes numbered/structured plan
      -> Foundry validates requested operations/roles/checks/budget
      -> admitted workflow revision
      -> execution capabilities become available

A "[DONE:n]" marker may update UI progress but cannot satisfy a protected workflow
predicate.

`PlanningProposal` is the post-repair target shape, not permission to generalize the
current live repair workflow early. A P0 software trial may map planning into the existing
admitted software-assignment contract until the owning role/workflow-generalization work
is complete.

### 8.3 Skills and prompt templates — P0/P1

Use Pi's progressive skill loading aggressively to keep always-loaded context small.

Initial governed skills should be few and durable, for example:

- Foundry assignment/handoff;
- Foundry review;
- Foundry adversarial review;
- Elixir/Phoenix development routing where relevant;
- project-specific typed-workflow guidance when admitted.

Governed runs should initially load only controller-approved, digest-pinned skills.
Project-controlled candidate text can be supplied as attributed context, but it is not
new governing policy merely because Pi calls it a skill.

The root `AGENTS.md` remains the provider-neutral repository router. A Pi adapter must
explicitly supply it when Pi does not natively apply that repository convention.

### 8.4 Delegation/subagents — P1

Pi's upstream subagent example proves useful UX patterns: isolated child contexts,
parallel/chain execution, streamed status, cancellation and per-child usage. Do **not**
copy its direct child-process authority into governed Foundry.

Pi should instead expose a request such as:

    delegate_work(
      purpose,
      requested_role,
      task,
      context_refs,
      desired_parallelism
    )

Foundry then decides whether to:

- refuse;
- satisfy with the current assignment;
- admit bounded child work under the parent ceiling;
- create a separately authorized sibling/root escalation when broader authority is
  actually required;
- require operator decision.

The child receives its own execution identity, budget reservation, workspace and
CapabilityGrant. Parent/child usage and evidence remain separately attributable.

A child cannot gain authority by naming itself "developer", "reviewer" or
"engine-capability-developer". Review independence is checked from principal/candidate/
authority lineage.

### 8.5 Agent teams/task lists — do not implement as authority

Do not create a Pi-owned shared task database or team coordinator beside Foundry.
Convenience commands such as `/tasks`, `/children`, `/steer` and `/cancel` may
project or request changes against Foundry state.

If Pi maintains temporary UI todos, they are disposable session metadata.

### 8.6 Hooks — P0/P1

Use Pi lifecycle/tool hooks for bounded translation concerns:

- tool-call interception;
- context injection/attribution;
- session/execution observation;
- compaction shaping;
- usage capture;
- status UI;
- redaction of diagnostic presentation where appropriate.

Hooks must not decide acceptance, authorize retries, weaken mandatory gates, mint child
authority or mutate durable workflow truth.

### 8.7 Code intelligence/LSP — P1

Add read-oriented semantic code tools because they materially improve coding-agent
ergonomics without requiring broad write authority:

- definition;
- references;
- symbols;
- hover/type information;
- diagnostics.

For Elixir, Expert is a candidate language server to pin and evaluate, not an assumed
production dependency. The LSP process belongs in the admitted worker/workspace boundary.

Refactor/rename operations should initially return a proposed edit set. Applying that edit
must cross the normal candidate-write gateway.

### 8.8 Checkpoint, rewind and session branching — P1

Separate three concepts:

1. **Pi conversation branch/session tree** — context/navigation only.
2. **candidate workspace checkpoint** — exact Git/worktree/artifact identity.
3. **Foundry workflow state** — authority/effects/budgets/evidence.

A user-facing rewind may offer conversation-only, candidate-only or both, but Foundry must
create/validate any candidate restoration as an explicit operation. Conversation rewind
never revives a revoked grant, refunds spent budget, erases an acknowledged effect or
changes accepted/deployed pointers.

### 8.9 Context HUD and visibility — P0/P1

Provide a high-value status projection without making UI text authoritative.

Useful fields:

- assignment / role / execution identity;
- active mode/grant summary;
- model/profile;
- context used / available where known;
- input/output/cache usage;
- subscription/budget capacity as distinct concepts;
- active/blocked child work;
- current candidate/check/review stage;
- isolation/network summary;
- outstanding operator decision.

A `/context` view should show bounded attribution categories rather than raw sensitive
prompt bodies:

- mandatory policy;
- role instructions;
- task/spec;
- relevant source;
- retrieved documentation;
- tool results admitted to context;
- conversation history;
- correction history.

Exact provider totals may coexist with estimated per-category attribution; quality must be
labeled.

### 8.10 Foundry-aware compaction — P1

Before compaction, preserve a structured projection sufficient to continue useful work:

- assignment/workflow identity references;
- current objective/spec revision;
- exact candidate/workspace identity;
- material decisions;
- files/areas changed;
- checks and observed outcomes;
- review findings/corrections;
- unresolved questions/risks;
- child-work references/results;
- important exact identifiers;
- current capability limitations.

Mandatory policy/spec/evidence context is selected outside the compaction model and cannot
be dropped merely to save tokens.

The compacted summary remains an attributed projection. Raw evidence and authoritative
state stay elsewhere.

### 8.11 Background jobs — P1

Do not expose unrestricted host `bash --background` as the governed primitive.

Use a Foundry operation such as:

    start_job(command_or_registered_check, execution_profile, expected_outputs)

which returns a durable execution/job identity. Status/log/cancel commands then operate on
that identity.

"Terminal/process exists", "job alive", "meaningful progress", "job completed" and
"workflow accepted" remain distinct observations.

### 8.12 MCP/external services — P2

External tools are useful but should enter through registered capability surfaces, for
example:

    github.issue.read(repo = X)
    docs.search(collection = Y)

An MCP server may implement such a surface, but the governed Pi worker should not inherit
whatever MCP servers happen to be installed on the host. Server/tool identity, scope and
network authority are admitted explicitly.

### 8.13 Automatic memory — defer

Do not initially implement mutable model-written long-term memory for governed execution.

The safer loop is:

    session observation/lesson
      -> attributable improvement proposal
      -> evidence/review
      -> approved skill / instructions / project-profile change

A lesson cannot silently become policy or weaken a mandatory gate.

## 9. Tool gateway sketch

The exact protocol is an implementation decision, but the bridge should expose a small
typed vocabulary rather than arbitrary local execution.

Candidate families:

### Read/context

- `workspace.read`
- `workspace.search`
- `code.definition`
- `code.references`
- `code.symbols`
- `code.diagnostics`

### Candidate mutation

- `workspace.edit`
- `workspace.write`
- `candidate.diff`
- `candidate.checkpoint`

### Execution/checks

- `shell.exec` with admitted environment/profile;
- `check.run` for registered check specifications;
- `job.start/status/logs/cancel`.

### Workflow requests

- `clarification.request`
- `workflow.propose`
- `delegation.request`
- `escalation.request`
- `handoff.submit`
- `review.submit`

A tool result is not automatically an acceptance receipt. The owning evidence adapter
decides which controller-observed facts can satisfy a protected predicate.

### 9.1 Workspace and Git custody

A Git worktree is not sufficient isolation. Its `.git` indirection may lead to a shared
common repository whose refs, hooks, remotes or worktree metadata have broader authority
than the candidate file scope. A shell-capable worker must not receive protected
integration credentials or unrestricted control of the controller's Git common directory.

The implementation may use a disposable clone/object view, mediated Git operations or
another proved arrangement, but the conformance requirement is invariant:

- candidate file authority does not imply protected-ref/integration authority;
- path scope is enforced after safe resolution, not by string-prefix comparison;
- traversal, symlink/hardlink/reparse-style escape and swap races are refused or contained;
- candidate checks/builds cannot install hooks or mutate controller-custodied Git state;
- commits/diffs used as evidence are rebound to exact controller-observed artifact identity.

## 10. Bridge threat model

The bridge runs close to provider/session authority and therefore has to be treated as a
small trusted component.

### Assets to protect

- provider/subscription credentials and account route;
- Foundry authentication root and durable store;
- protected policy/project profiles;
- other assignments/workspaces;
- Git integration/publication credentials;
- operator home/private files;
- Pi session transcripts and context caches from other assignments;
- protected Git refs/common metadata/integration credentials;
- network destinations outside the grant;
- budget/effect/acceptance state.

### Threats

1. candidate repository adds or modifies a Pi extension and obtains host execution;
2. user-level Pi config silently changes tools/provider/network behavior;
3. a candidate modifies `AGENTS.md`/skills/prompts and turns its own proposed policy into
   governing instructions mid-run;
4. a direct read/search/file-inclusion path exposes host secrets or out-of-scope data;
5. a custom extension bypasses sandboxed built-ins;
6. hostile model/candidate tool arguments exploit bridge parsing, shell interpolation,
   path handling or oversized/ambiguous protocol inputs;
7. model calls a generic gateway while lying about project/role/path scope;
8. path traversal, symlink swap or shared Git metadata escapes the admitted workspace;
9. a prior/foreign Pi session is resumed under a new assignment;
10. child Pi process inherits a broader environment or credential;
11. stale session controls a successor execution;
12. prompt/abort acknowledgement is mistaken for completed effect;
13. direct Pi subagent spawning bypasses child budget/grant admission;
14. LSP/build hooks execute candidate-controlled code outside the worker boundary;
15. background process survives assignment cancellation;
16. tool output or telemetry copies secrets/raw prompts into diagnostics;
17. session rewind resurrects stale policy assumptions;
18. MCP/plugin supply-chain change silently enlarges capabilities;
19. Pi/provider fallback spends through a route not admitted by Foundry;
20. Pi-internal retry, tool-loop continuation or compaction issues a model request without
    a durable request reservation.

### Required mitigations

- exact-version/digest pinning;
- explicit governed loadout and protected instruction bundle;
- no ambient executable extension/session discovery;
- complete resource/executable-path inventory, including non-tool file ingestion;
- strict versioned/bounded bridge and RPC schemas; reject duplicate/ambiguous fields,
  invalid encoding, NUL/control abuse and oversized records rather than interpolating
  untrusted data into shell/code;
- authenticated execution-scoped gateway;
- pre-request model reservation/claim with exact route fixed outside model/candidate
  control;
- provider-request gateway configuration, route selection and reusable credentials kept
  in protected controller custody where technically feasible, never in the effect worker;
- server-side scope derivation from CapabilityGrant;
- credential-free model-directed worker;
- restricted network/filesystem/process authority with canonical path/resource checks;
- protected Git custody separated from candidate shell/file authority;
- assignment-scoped session storage/resume and bounded retention;
- child grants/budgets no broader than parent ceilings unless separately admitted;
- incarnation/session matching before control/cleanup;
- durable effect intent/issue/reconciliation;
- bounded diagnostic schemas/redaction;
- fail-closed unknown provider/billing/quota state;
- conformance rerun on Pi/bridge/security-sensitive dependency upgrade.

## 11. Provider and billing boundary

Pi replacement is blocked until the selected provider/account route is actually proven.

For each governed execution profile, Foundry must verify:

- exact provider and model selection;
- intended account/profile;
- every model request is preceded by the required durable reservation/claim and followed
  by an attributable receipt/reconciliation outcome;
- subscription-versus-paid billing class;
- behavior when subscription quota/capacity is unavailable;
- absence of an automatic paid/extra-credit fallback unless separately authorized;
- observable usage/quota signals and their uncertainty;
- child/delegated work uses only its admitted provider/budget route;
- retries, tool-loop continuations and compaction cannot create unreserved requests;
- crash/timeout after possible provider issue retains an unknown hold until reconciled.

Possession of an Anthropic/OpenAI/other credential is not proof of subscription
entitlement. A future authentication bridge intended to use an official subscription
route is a security- and billing-sensitive dependency that needs its own review and
conformance evidence; this design does not authorize reverse-engineering or bypassing
provider controls.

## 12. Observability integration

Every meaningful Pi observation should join the same Foundry correlation chain:

    ticket
      -> attempt
        -> assignment/principal
          -> execution/session
            -> model request/turn
              -> tool/job/child execution
                -> candidate/evidence/review outcome

Minimum useful event families:

- execution start/stop/reconcile;
- request/turn start/end/error/abort;
- tool request/result/denial;
- job/child request and lifecycle;
- compaction/context observation;
- usage/cost observation;
- correction/review transitions;
- operator intervention.

Record bounded metadata rather than raw prompts/responses by default. Tool observation
should include invocation identity, admitted capability, duration, result size,
truncation/error status and bounded context admission.

Failed, retried, corrected and reviewed work stays in the denominator. A "cheaper"
execution that produces more correction/review/operator effort is not a proven
optimization.

## 13. P0 / P1 / P2 implementation scope

This is a design decomposition, **not a parallel Foundry backlog**. Every implementation
change must be routed to the repair/workflow requirement that owns its authority and
prerequisites; these labels cannot be used to jump blocked FR dependencies or mark an FR
complete. P0/P1/P2 only describe the minimum Pi-candidate scope and sequencing once the
owning work is admissible.

### P0 — prove Pi is a governable replacement candidate

1. Define a harness-neutral Elixir behaviour around start/observe/prompt/interrupt/
   reconcile/close/usage.
2. Build a strict pinned Pi RPC adapter with JSONL framing and protocol validation.
3. Define a controller-owned governed loadout/instruction/session manifest and refuse
   ambient executable configuration or foreign-session resume.
4. Implement the minimal trusted bridge and gateway path needed for a useful coding task
   without ambient model-visible host filesystem/process/network access.
5. Prove provider/model/billing selection, per-request durable reservation/receipt and
   fail-closed no-paid-fallback behavior for the intended real route.
6. Prove credential/filesystem/network/process isolation with synthetic secrets and
   controlled endpoints.
7. Connect Pi usage/context/compaction observations to FR-18's versioned telemetry path.
8. Provide inspect/plan/work/review tool projections backed by actual grants.
9. Supply the repository router/context explicitly and prove mandatory context survives
   compaction.
10. Pass lifecycle/restart/cancellation/reconciliation conformance and one bounded useful
    developer/reviewer flow.

P0 does not require polishing the interactive TUI or matching every Claude Code feature.

### P1 — remove the main reasons to reach back for Claude Code

- Foundry-admitted plan workflow UX;
- progressive approved skills/prompts;
- Foundry-backed delegation/subagents;
- read-oriented LSP/code intelligence;
- context/budget/capability status HUD;
- Foundry-aware compaction;
- conversation/candidate checkpoint and rewind UX;
- supervised background jobs;
- ergonomic task/child projections.

### P2 — optional ecosystem conveniences

- registered MCP/external-service adapters;
- richer interactive-human profile;
- additional language servers;
- curated reusable Pi package/distribution;
- broader UI/presentation integration;
- reviewed learning-to-skill promotion helpers.

Each P2 item still needs an observed need and must not expand the protected kernel merely
for parity.

## 14. Conformance matrix

A Pi candidate is not ready because it can edit files and answer prompts. The following
cases must be executable against the exact candidate.

### Protocol/lifecycle

- fresh start returns unique execution/session identity;
- malformed/oversized/noncanonical JSONL, duplicate keys and invalid/ambiguous fields
  fail closed before dispatch;
- hostile strings/newlines/NUL/path-like payloads remain inert data across the bridge;
- prompt acknowledgement is distinguished from turn completion;
- lost prompt acknowledgement is reconciled without blind duplicate delivery;
- duplicate prompt/request identity does not create duplicate acknowledged effects;
- abort during model response;
- abort during model-directed tool call;
- queued/follow-up input behavior is tested;
- Pi process crash before/after request acknowledgement;
- controller crash/restart with live Pi;
- stale session identity cannot control a successor;
- close/cancel is bounded and preserves unknown foreign resources;
- no pane/process/UI liveness is accepted as workflow completion.

### Configuration/supply chain

- malicious project-local extension is ignored/refused in governed mode;
- malicious user-level extension/config is ignored/refused;
- candidate-modified `AGENTS.md`/skill/prompt is visible as candidate data but cannot
  replace the pinned governing instruction bundle for that execution;
- foreign/prior Pi session cannot be selected as the current assignment session;
- candidate `.pi`/ancestor configuration cannot affect governed behavior merely by
  becoming the Pi process working directory;
- changed bridge/Pi digest refuses until manifest is updated through protected process;
- unknown execution-changing setting fails closed;
- candidate cannot rewrite the active skill/project profile governing itself.

### Capabilities/isolation

- review role cannot write candidate even if UI/tool exposure is wrong;
- out-of-scope path write/read is denied after safe path resolution;
- `../`, absolute-path, symlink/hardlink and swap-race escape cases cannot reach outside
  the admitted workspace;
- read/search/file-inclusion paths cannot read reusable provider/controller credentials;
- shell/process paths cannot read reusable provider/controller credentials;
- unauthorized outbound network is denied;
- another assignment/workspace and its Pi session/context store are inaccessible;
- candidate shell cannot mutate protected Git refs/common worktree metadata or use
  integration/push credentials;
- build/LSP hook cannot escape the worker boundary or install a protected-host hook;
- denied capability is visible evidence, not translated into success;
- worker cleanup does not kill foreign resources.

### Provider/billing

- exact configured provider/model/profile is observed and cannot be changed by model/UI
  command outside a newly admitted decision;
- intended subscription route is positively evidenced;
- first request, tool-loop continuation, retry and compaction each have a corresponding
  pre-issue reservation/claim and attributable receipt or unknown hold;
- controller/Pi crash after possible provider issue does not release capacity as unused;
- subscription exhaustion does not silently use paid/extra-credit route;
- unavailable/unknown quota blocks or follows FR-16 policy;
- child work cannot choose a broader/premium route;
- usage unknowns remain unknown.

### Delegation

- child receives separate execution identity and reservation;
- child grant is no broader than admitted ceiling;
- child cannot claim a role string to enlarge scope;
- cancellation propagates/reconciles;
- child usage/evidence remains attributable;
- escalation requiring broader authority creates separately admitted work, not privilege
  growth;
- renamed model/session does not create independent review lineage.

### Context/session/compaction

- required policy/spec/evidence context is retained or reloaded deterministically;
- governing instruction bundle is pinned independently of candidate-modified instructions;
- assignment-scoped session storage cannot resume/read a foreign assignment transcript;
- optional source/tool context can be ranked/dropped without dropping mandatory context;
- compaction summary is attributed and not accepted as raw evidence;
- context/usage observation values preserve quality/source;
- sensitive prompt/tool content is not copied wholesale to telemetry;
- resumed session with stale policy is revalidated against current grant/policy.

### Checkpoint/rewind

- conversation-only rewind does not mutate workspace;
- candidate restore is an explicit admitted operation;
- rewind does not refund budget or erase effect history;
- revoked/narrowed grant remains revoked after session branch;
- accepted/deployed pointers do not move from a local rewind.

### Useful completion

At least one representative software task must complete with:

- real scoped edits;
- real checks;
- a frozen candidate;
- correction request;
- corrected candidate;
- independent review;
- exact usage/effect evidence;
- clean cancellation/cleanup paths.

Mocks establish exhaustive failure semantics; a bounded authorized real-provider smoke is
still required for harness/provider/billing claims.

## 15. Rollout and adoption gates

### Stage A — protocol fixture

Implement the generic harness boundary and Pi JSONL parser against captured/pinned
fixtures. No real provider or automatic execution.

### Stage B — pinned local candidate

Run exact Pi/bridge builds in an isolated test environment with protocol fixtures or an
otherwise controlled provider test route plus the effect gateway. Exercise configuration,
lifecycle, denial and cleanup cases.

### Stage C — bounded provider/isolation smoke

Under explicit existing authorization, prove the intended real subscription route plus
synthetic-secret, network and filesystem denial. Record actual usage signals and unknowns.

### Stage D — software workflow trial

Run one bounded developer/check/reviewer/correction flow without autonomous merge or
activation. Compare evidence/operator effort with the current reference path where a
valid reference exists.

### Stage E — substitution decision

Evaluate:

- useful completion;
- failure/recovery semantics;
- operator effort;
- token/context usage;
- billing predictability;
- isolation/security burden;
- upgrade/rollback burden;
- dependency churn;
- evidence quality.

Only then propose explicit governing-text changes for OMP-specific FR-06/09/15a language.

### Stage F — controlled adoption

Pin the accepted candidate, update contracts/fixtures/runbooks, repeat independent review,
and preserve a reversible rollback path. Production enablement remains owned by the repair
plan and later full lifecycle acceptance.

## 16. Candidate repository layout

Do not create these paths until implementation scope is admitted, but prefer a separation
like:

    foundry/lib/pramana_foundry/harness.ex
    foundry/lib/pramana_foundry/harness/pi/
      process.ex
      rpc.ex
      protocol.ex
      observation.ex

    foundry/pi/bridge/
      index.ts
      tools/
      hooks/

    foundry/pi/skills/
      assignment/
      review/
      adversarial-review/

    foundry/test/pramana_foundry/harness/
      contract_test.exs
      pi_protocol_test.exs
      pi_conformance_test.exs

The TypeScript bridge should remain thin. Do **not** add bridge-side
`workflow_engine.ts`, `scheduler.ts`, `budget_manager.ts` or `acceptance.ts`.

## 17. Upgrade policy

Pi's small surface is valuable only if upgrades stay reviewable.

For every Pi/bridge security- or execution-sensitive upgrade:

1. pin exact candidate revision/digest;
2. inspect upstream RPC/extension/tool/config changes relevant to our manifest;
3. regenerate/validate protocol fixtures;
4. rerun the conformance matrix appropriate to the change;
5. compare newly reachable executable paths;
6. verify provider/billing behavior where affected;
7. retain rollback to the prior accepted build.

A green unit suite after an upstream harness upgrade does not establish billing or
isolation parity.

## 18. Sources and implementation references

Primary references checked for this design:

- Pi RPC:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/rpc.md
- Pi extensions:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/extensions.md
- Pi upstream extension examples, including plan mode/subagents/permissions:
  https://github.com/earendil-works/pi/tree/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/examples/extensions
- Pi subagent example:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/examples/extensions/subagent/README.md
- Pi skills:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/skills.md
- Pi sessions:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/sessions.md
- Pi containerization/security guidance:
  https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/containerization.md
- Claude Code feature overview:
  https://code.claude.com/docs/en/features-overview
- Claude Code permissions:
  https://code.claude.com/docs/en/permissions
- Claude Code subagents:
  https://code.claude.com/docs/en/sub-agents
- Claude Code hooks:
  https://code.claude.com/docs/en/hooks
- Claude Code checkpointing:
  https://code.claude.com/docs/en/checkpointing

The repository's source-quality summary for Pi is
[research entry E30](../../docs/strategy/RESEARCH.md). External examples establish
available mechanisms and design inspiration, not Foundry acceptance evidence.

## 19. Open decisions intentionally deferred

The design leaves these decisions for measured implementation work:

- exact local IPC transport for the Pi bridge and provider-request broker/adapter;
- which Pi-internal pure/session/UI tools can remain direct after the resource-path
  inventory proves they cannot access project/host resources;
- exact sandbox/runtime implementation;
- exact Pi version/revision selected for Stage B;
- exact language-server package/version;
- whether an official supported provider route can meet the subscription-only contract;
- which context categories can be exact versus estimated;
- whether interactive-human and governed profiles share one bridge package;
- exact assignment-scoped Pi session persistence/retention mechanism after privacy tests;
- exact protected-Git/workspace topology after isolation tests;
- whether Superlogical eventually presents Pi sessions or replaces Herdr independently.

None of those unknowns requires weakening the core boundary: Pi remains replaceable,
Foundry remains authoritative, and useful conveniences graduate only after they preserve
that separation.
