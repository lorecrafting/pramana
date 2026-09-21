# Foundry strategy brief

**Date:** 2026-09-19. **Type:** investment direction and design guidance, not an
implementation inventory or authorization to execute. Records the operator's
Foundry-first investment direction, the model-directed-work vision and the lessons from
FirstMate, Pi, OMP and no-mistakes. External capabilities below are source observations
at pinned revisions, not comparative performance measurements or certification on the
operator's machine.

[Documentation index](README.md) · [Repair plan](REPAIR-PLAN.md) ·
[Workflow contract](WORKFLOW-CONTRACT.md) ·
[Broader product strategy](../../docs/strategy/FOUNDRY.md)

## Working summary

Build a trusted execution and governance kernel for model-directed work, not another
comprehensive coding harness or a permanently hard-coded agent graph. Models may propose
task decomposition, roles, workflow shape, context, tools, checks and corrections.
Foundry owns admitted intent, identities, capability grants, durable acknowledged state,
budgets, external-effect control, evidence, acceptance, recovery and controlled
self-improvement. The resulting boundary should also make Foundry an experimentation
kernel: hold authority/evidence/acceptance invariants stable while comparing workflow
strategies, models, harnesses, context policies, tool configurations, review topologies
and concurrency by accepted-outcome correctness, effort, latency and resource cost.

Retain the standalone Elixir/OTP project. Beneath the current fail-closed launch gate,
the implemented execution path still targets OMP through Herdr; that is implementation
truth, not the desired permanent dependency.
Keep agent execution harness-neutral behind a small versioned execution/observation
contract. Pi remains the preferred first replacement **agent**, but the bridge is now a
substitution question: compare direct pinned Pi RPC with pinned Jido.Harness/ACP before
investing further in OMP-specific integration or writing a custom adapter. Herdr remains initial optional
presentation. A stronger model, different harness, accessible API or new backend may
improve planning without gaining spending, acceptance or deployment authority. Model
proposals and harness observations remain inputs to protected deterministic checks.

Software engineering is the first workload to prove, not the permanent ontology of the
system. Prove one useful complete lifecycle, including correction and interruption,
before generalizing roles or workflow definitions. **Compose before build:** Foundry
should own the contracts that distinguish trustworthy execution, not commodity
infrastructure that another system can satisfy under those contracts. Measure operator
effort per independently accepted outcome, including preparation, review, recovery and
Foundry maintenance. Safety without useful completion and apparent productivity without
valid evidence are both failures.

## Authority and document ownership

The [repair plan](REPAIR-PLAN.md) owns ticket status, ordering, dependencies and
acceptance obligations. The [workflow contract](WORKFLOW-CONTRACT.md) owns identities,
transitions, budgets, isolation, integration and activation. Their current containment
remains binding. This brief closes no ticket, changes no production policy and creates
no parallel backlog. Investigations may inform blocked work; production implementation
and activation still require the owning prerequisites and evidence.

This brief owns the Foundry-first investment rationale and cross-project lessons.
The [broader Foundry chapter](../../docs/strategy/FOUNDRY.md) retains post-repair product
initiatives and portfolio sequencing. Funding the repair foundations first does not
silently waive its post-repair evaluation gates. One operator, one machine and Pramāṇa
remain the present scope; a second repository requires separately approved scope.
Pramāṇa must continue to build and run without Foundry.

## Product thesis

Given a bounded authorized objective, Foundry should let capable models direct useful
work while preserving independently checked outcomes, interruption safety and a durable
account of what actually happened. The longer-term differentiator is a replaceable,
project-portable workflow kernel that can accept model-proposed plans without giving the
planner power to alter the protected rules judging its effects.

Better models should remove pressure to encode planning intelligence, fixed role
taxonomies or elaborate task graphs in the protected core. They do not remove the need
for durable identity, authority, budgets, exact artifact binding, attributable evidence,
independent acceptance and reconciliation of uncertain side effects. Enforcing those
boundaries does not prove arbitrary work correct; useful specifications, real checks,
independent review and evaluation remain necessary. Number of agents, generated pull
requests and test coverage percentages are not the product outcome.

## Architecture to preserve

| Responsibility | Foundry owns | Reuse rather than rebuild |
|---|---|---|
| Authority | Authenticated policy, capabilities, reservations, effect claims and acceptance predicates | OS security primitives and appropriate transactional storage libraries |
| Workflow | Admission, pure decision/replay, scheduling, correction, cancellation and reconciliation for versioned workflow definitions | OTP supervision and ordinary concurrency mechanisms |
| Agent execution | A small versioned and tested execution/observation contract | Current source: OMP; preferred first replacement agent: Pi; compare direct pinned Pi RPC with pinned Jido.Harness/ACP before selecting the bridge, subject to FR-09/15a conformance and explicit contract review |
| Project tools | Approved capability/evidence surfaces for the current assignment | Git/compiler tools for software; typed project APIs where appropriate |
| Presentation | Honest projections and outstanding operator decisions | Herdr initially; future backends only after conformance evidence |

These are responsibilities, not five new services. Keep the protected verifier small:
it checks whether an exact operation is authorized and supported by receipts. It must
not become a second planner, scheduler, context engine or general plugin host. Most
feature work should propose a new use of existing authority, not enlarge authority.

Keep one transactional authority store and one domain reducer for live operation and
replay. Session transcripts, diagnostics, context caches and boards are evidence or
projections, never competing sources of acceptance or budgets. A working process is
not progress; progress is not completion; completion is not acceptance.

## Intelligence boundary: models direct, the kernel governs

Treat workflow intelligence as replaceable and increasingly model-driven. A model may
propose how to decompose an objective, which temporary roles are useful, which permitted
execution profile to use, what context or tools it needs, which checks to run, and how a
correction or sub-workflow should proceed. It may also propose a workflow amendment when
new evidence changes the plan. Those are planning decisions, not authority.

The protected system owns the facts that must not depend on the planner believing its
own story: principal and assignment identity, admitted capabilities, durable revisions,
budget reservations, effect claims and idempotency, unknown-outcome reconciliation,
exact artifact identity, check/review receipts, independence constraints, acceptance
predicates and promotion/activation. A model saying that a test passed, a retry is safe,
or its work is complete is not the corresponding receipt.

A model-generated workflow is therefore an untrusted proposal. Before execution, Foundry
validates it against the current operator/project policy, available capabilities and
budgets, then pins the admitted definition and its revision/digest. Protected policy may
inject or require gates that a proposed workflow omitted; a project or model cannot
weaken mandatory review, acceptance, publication or activation predicates. A mid-run
change is a new admitted decision, not a silent mutation of history. Project
configuration may request authority but cannot mint it.

Do not bake today's PM/developer/reviewer names or one software lifecycle into protected
storage and authority semantics. Preserve generic identities such as project, workflow,
workflow revision, role, assignment, principal, capability set, artifact/evidence type,
acceptance profile and execution profile. Independence is checked from durable
principal/authority lineage and candidate ownership; changing a role label, session or
model does not create an independent reviewer. Current repairs may continue using the
fixed software workflow until it is actually proven; this direction is a post-repair
generalization constraint, not authorization to replace the active contract.

The same project should eventually be able to register materially different workflows
with materially different tool surfaces. A software-engineering workflow may receive an
isolated worktree, Git, shell and compiler tools; a content-authoring workflow may receive
only a typed Builder API, simulation and certification operations. Reusing the same
model in both cases does not imply equal authority. Child work and sub-workflows inherit
bounded parent scope/budget ceilings unless protected policy grants less; composition
cannot expand authority. Avoid a Turing-complete workflow DSL or a second orchestrator:
start with small composable lifecycle primitives and introduce generalization only after
real portability evidence.

### Project-declared roles and capability surfaces

The post-repair generalization should be **role-agnostic in the kernel and role-specific
at the project boundary**. See [Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md).

A versioned ProjectProfile may declare RoleSpecs, tool/API surfaces, context policy,
evidence adapters, acceptance profiles and workflow templates. Foundry admits an exact
CapabilityGrant that is no broader than protected operator/project policy.

This is stronger than merely mapping role names to model profiles. The current code still
contains software-specific assumptions—for example `LaunchEligibility` accepts only
`developer | reviewer | pm`, the queue path launches a developer, and handoff/review
lifecycle code is specialized around software candidates. Those assumptions are acceptable
inside the active repair workflow; they are **not** the target protected ontology.

Loka supplies a concrete portability test:

- a MUD/world builder can operate only through Loka's typed Builder API over L3–L6
  authoring surfaces;
- the builder can have enormous semantic authoring power without shell or engine-source
  write access;
- a missing semantic primitive produces a capability proposal/escalation;
- a separately admitted engine-capability developer may work at L2 under stronger
  isolation/checks;
- a semantic reviewer may inspect/simulate the exact content candidate without mutation;
- a release role may stage only an exact certified artifact.

Changing the model, role label or session does not create reviewer independence or enlarge
authority. Escalation creates a new protected decision/assignment; the originating role
cannot amend its own grant.

## Compose before build: own contracts, substitute infrastructure

Foundry is not valuable because it owns an agent loop, container runner, durable workflow
engine, policy language or model router. Those layers are increasingly available from
specialized projects and will continue to improve. Before substantial post-repair work
on any such layer, perform a bounded substitution evaluation against the best available
candidate. If a candidate satisfies the required contract with lower operator,
maintenance and security burden, use it and delete or avoid overlapping Foundry code.

Evaluate one responsibility at a time rather than adopting a new stack wholesale:

| Responsibility | Candidate class to benchmark | Foundry-specific conformance question |
|---|---|---|
| Software-factory orchestration | Warp Factories or comparable systems | Can it preserve Foundry's exact authority, evidence, budget and acceptance semantics, or should Foundry sit above/beside it? |
| Agent/workflow runtime | LangGraph or comparable agent runtimes | Does it add useful persistence/control without becoming a competing source of workflow authority? |
| Coding-agent harness normalization | Direct Pi RPC versus Jido.Harness/ACP or comparable harnesses | Does normalization remove lifecycle/provider-specific maintenance while preserving exact identities, capabilities, billing/usage evidence, cancellation and restart/reconciliation semantics? |
| Durable execution | Restate, Temporal, DBOS or comparable runtimes | Can it represent effect claims, unknown outcomes and replay without weakening the protected store/receipt contract? |
| Tool execution/isolation | Dagger, containers, micro-VMs and OS primitives | Can candidate-controlled tools be isolated from model credentials, protected state and unauthorized network paths while still completing real work? |
| Authorization policy | OPA, Cedar or comparable policy engines | Can it safely replace a bounded stateless policy slice without becoming the durable budget/effect/acceptance ledger? |
| Fast semantic decisions | Jev/System One or comparable typed decision models | Does it improve routing, triage or supervision on held-out cases while remaining advisory and confidence-gated? |

Passing a feature checklist is insufficient. Compare actual failure semantics, operator
effort, upgrade/rollback cost, licensing, local/offline requirements, privacy, observability
and the cost of preserving Foundry's evidence. A promising external system is a dependency
candidate, not evidence that a repair ticket is complete. Conversely, "we already wrote
it" is not a reason to retain a worse implementation.

This substitution gate also defines a stop condition for Foundry itself. If an external
system eventually satisfies the whole useful contract—including protected authority,
durable effect accounting, exact evidence binding, independent acceptance and recovery—
use that system rather than maintaining Foundry as a duplicate. The product thesis is
the contract and outcome, not ownership of a particular codebase.

## Current execution baseline: host-bound path, automatic launch fail-closed

The current source should not be described simply as "agents run unsandboxed" because
production automatic dispatch is intentionally blocked earlier. `AgentServer.init/1`
first resolves an admitted launch profile and requires the Herdr adapter to prove the
selected route is subscription-only. The production Herdr System runner currently
reports that proof as unsupported, so a normal automatic launch stops before pane
creation. FR-09 and FR-15a own the evidence needed to restore live automatic execution.

The implemented execution path beneath that gate is nevertheless host-bound rather than
containerized. `AgentServer.do_launch/1` asks Herdr to split a terminal pane whose
working directory is the assignment checkout, then starts `omp` in that pane.
`Herdr.Runner.System` invokes the configured Herdr executable directly as an OS child
with `Port.open/2`. Foundry records pane/process identities and process groups so it can
refuse stale cleanup and signal the correct descendants, but it does not create a
container, micro-VM or separate OS security principal in this path.

Git worktrees, terminal panes and process groups solve different problems from a sandbox:
they provide checkout separation, presentation/session identity and safer lifecycle
cleanup. They do **not** by themselves restrict what a shell-capable model process may
read, execute, contact or modify under the host principal. If this host path were enabled
under an ordinary user account, candidate-controlled tools could exercise whatever
filesystem, network, process and installed-tool authority that principal and the host OS
grant them. A worktree prevents neither reads outside the checkout nor arbitrary outbound
network access. Process-group ownership helps terminate descendants after the fact; it
does not constrain those descendants while they are running.

That is why the repair contract requires a stronger harness/tool separation before
automatic execution is restored: reusable provider credentials remain in a protected
authentication path, while candidate-controlled file/shell/build/test work runs in a
credential-free restricted principal/environment with explicit network and filesystem
bounds. Sandboxing must also preserve positive usefulness: an isolated worker that cannot
build or test real work is not an acceptable solution.

## Dagger versus Docker

Docker is primarily a container platform/runtime interface: images describe packaged
environments and containers are isolated processes managed by a container runtime.
Dagger sits **above** an OCI-compatible runtime such as Docker, Podman or nerdctl. Dagger
provides a programmable, typed DAG/execution API for creating containers, injecting
explicit files/directories/services, running commands, caching intermediate work and
returning artifacts consistently across local development and CI. When Docker is the
runtime, the Dagger Engine itself runs as a container and asks that runtime to execute
the workflow's containers.

For Foundry, Docker or another OCI runtime could be used directly. Dagger is interesting
because it may remove custom plumbing around "construct environment → copy exact inputs
→ run bounded commands/services → capture outputs/artifacts → cache/reuse → clean up."
It is therefore an execution abstraction and reproducibility layer, **not a stronger
security boundary merely because it uses containers**. Foundry would still specify and
test mounts, network paths, credentials, host services, privileges, resource ceilings
and cleanup. A poorly configured Dagger workflow can expose host resources just as a
poorly configured Docker invocation can.

The adoption question is therefore not "Dagger or Docker." It is closer to:

```text
Foundry authority/control
        |
        +-- direct OCI/container adapter --------> Docker/Podman/etc.
        |
        +-- Dagger execution adapter ------------> Dagger Engine
                                                     |
                                                     v
                                               OCI runtime
```

Evaluate Dagger if its typed composition, caching, portability and observability reduce
Foundry maintenance while still satisfying the same isolation conformance suite.
Otherwise a smaller direct container/micro-VM adapter may be preferable.

### Dagger integration posture: pin the engine, keep the bridge tiny

Dagger is Apache-2.0 open source, can run locally against an OCI-compatible runtime, and
is therefore compatible with the sovereignty policy: mirror the exact source/release,
pin the engine/artifact digest and retain the legal/technical ability to build or fork
it. That does **not** imply Foundry should vendor or fork the whole engine by default;
the engine is a substantial active project whose upstream security and runtime work are
valuable.

Upstream is moving quickly enough that a broad compile-time coupling would create
maintenance pressure. Engine releases advanced from v0.21.0 on 2026-05-26 through
v0.21.9 on 2026-08-26, with several intervening patch releases. Current documentation
also describes the 1.0 workspace/module configuration migration, while the Elixir SDK
is explicitly still beta, uses the previous beta SDK interface, needs an update for the
current module/client commands and currently supports checks but not generators or
`up` services. Treat that as meaningful interface churn, not a reason to reject Dagger.

For the first Foundry experiment, avoid making the beta Elixir SDK a foundational
dependency. Prefer a narrow process/API adapter such as:

```text
Foundry.Execution.Dagger
  -> exact pinned dagger executable
  -> fixed Foundry-owned Dagger module/core API calls
  -> `dagger api call ... --json`
  -> strict versioned JSON result parser
```

The Dagger CLI exposes JSON output and the engine exposes a language-independent GraphQL
API. This keeps Dagger-specific generated types out of Foundry's durable domain and makes
an engine upgrade an explicit adapter/conformance event rather than an application-wide
SDK migration. Pin the module's `engineVersion`, module references and engine artifact;
upgrade only after regenerating any Dagger-side bindings, reviewing the diff and rerunning
the full Foundry execution/isolation suite.

If a later stable Elixir SDK materially reduces bridge code without increasing coupling,
re-evaluate it. The target is not "never update the bridge"; it is a bridge small enough
that upstream churn is localized to one adapter and upgrades are optional rather than
forced.

## In-house sandbox direction: own policy and launcher, not kernel isolation

A secure execution boundary is required for unattended roles that can run arbitrary
candidate-controlled code (shell, build hooks, tests, generated scripts or similar).
It is not automatically required for every Foundry role: a Lokacore author restricted
to a narrow typed Builder API can rely on that API/capability boundary instead of being
given a general-purpose shell sandbox.

Do not write a new sandboxing mechanism from first principles. Linux already supplies
the enforcement primitives; Foundry should own a small versioned **worker-launch
contract and sandbox policy** that composes them. The useful in-house asset is the exact
policy, conformance suite, launch protocol and receipts—not our own namespace, syscall
filter or container implementation.

A minimum software-worker profile should fail closed unless it can establish all of
these properties:

- run under a dedicated unprivileged execution identity, with no supplementary host
  groups or reusable provider credentials;
- clear inherited environment variables and file descriptors, set `no_new_privs`,
  drop Linux capabilities and expose no host SSH agent, keychain, Docker socket, system
  bus, operator home or provider-auth socket;
- provide an immutable/read-only base environment plus writable ephemeral `HOME`,
  `/tmp` and the exact assignment workspace only; dependency caches, if shared, are
  read-only or mediated and cannot become an authority channel;
- isolate PID, mount, IPC and network views; hide the host process tree and devices;
- default network to denied, adding only explicitly authorized egress through a
  controlled fetch/proxy path when a build genuinely needs it;
- enforce CPU, memory, PID, wall-time and storage ceilings and kill the whole owned
  execution hierarchy on cancellation/timeout;
- use seccomp to reduce syscall attack surface and Landlock (where available) as a
  stackable filesystem/network restriction in addition to namespaces and ordinary Unix
  permissions;
- never mount the host filesystem broadly or expose privileged runtime sockets;
- emit attributable receipts containing sandbox-policy revision, rootfs/image digest,
  input/workspace digest, exact argv, exit status, output/artifact digests, resource
  observations and any policy denial;
- prove both denial and usefulness: synthetic credential/escape/egress attempts must
  fail, while representative Elixir/Phoenix builds and tests must still complete.

Linux kernel documentation explicitly treats Landlock as an additional restriction layer
and notes that namespaces alone are not fine-grained access control. Seccomp filters and
`no_new_privs` propagate restrictions across child execution when configured correctly.
A mature helper such as bubblewrap can implement namespace/mount construction, but its
own security documentation stresses that it is a toolkit, not a complete policy, and
recent security advisories demonstrate why an internally mirrored helper must still
receive reviewed security updates rather than being frozen forever.

For the current macOS host, prefer a Linux worker boundary rather than inventing a
macOS-specific sandbox contract first. Apple Virtualization.framework can run a Linux VM.
A pragmatic sovereign design is therefore:

```text
macOS operator host
  └─ Foundry Elixir control plane
       └─ protected auth/model gateway
       └─ Linux worker VM (no operator credentials)
            └─ per-execution restricted worker
                 ├─ namespaces / UID
                 ├─ cgroups
                 ├─ seccomp
                 ├─ Landlock
                 ├─ controlled workspace
                 └─ default-deny network
```

The outer VM keeps the operator's Mac, keychain and normal home outside the tool-worker
security boundary; the inner per-execution sandbox prevents concurrent assignments from
sharing unrestricted authority inside the worker VM. The VM may be long-lived if
cleanup/reconciliation is proved, or disposable/snapshotted if stronger reset semantics
are worth the cost.

If we want the launcher implementation itself in-house, keep it deliberately small:
Foundry sends a fixed, versioned sandbox manifest to a root-owned/restricted launcher
(or an unprivileged launcher where the chosen kernel mechanisms permit it); the launcher
validates that manifest against a closed schema and invokes pinned kernel/runtime
mechanisms. A small Rust/C helper is a reasonable implementation shape for the Linux
syscalls, while Elixir remains the authority/control plane. Avoid a general shell-based
"policy" launcher whose caller can smuggle extra mounts, sockets, environment or flags.

This should remain backend-neutral. The same `Foundry.ExecutionSandbox` conformance
suite should be runnable against an in-house Linux launcher, Dagger, direct OCI
containers or a future micro-VM backend. The in-house implementation wins only if it is
simpler to audit and maintain while passing the same cases.

## Control plane versus security/execution plane

Keep Elixir/OTP where it is strong: long-lived coordination, supervision, pure workflow
decisions/replay, typed domain boundaries, concurrent assignment lifecycle and honest
recovery. Do not treat BEAM process isolation as the security boundary for hostile or
model-controlled tools.

Use operating-system or proven sandbox primitives for hard resource and security
boundaries. On Linux, candidate mechanisms include namespaces for resource views,
cgroups for accounting/limits, seccomp for syscall restriction and Landlock for
additional filesystem/network access control. Containers or micro-VMs may compose these
mechanisms. On non-Linux hosts, require an equivalently tested boundary or keep the
capability disabled; do not emulate kernel security in Elixir.

Dagger is a candidate execution abstraction because it exposes typed containers,
directories, files and secrets and has an Elixir SDK, but the current Elixir SDK is
still beta and its presence does not prove Foundry's credential/network/isolation
contract. Its secret type is not permission to inject reusable model/provider
credentials into candidate-controlled execution; the protected authentication gateway
boundary remains until a separately reviewed design proves an equivalent or stronger
separation. Evaluate Dagger with the same synthetic-credential, egress, process-cleanup
and positive-delivery cases required of any other execution backend.

The intended split is therefore **Elixir/OTP control plane; OS/sandbox security and tool
execution plane**. Elixir is the current implementation choice and a strong fit for the
accepted single-machine control problem, not a product moat or a substitute for kernel
security. Keep those interfaces replaceable so Foundry can adopt better Linux, container,
micro-VM, remote-execution or durable-runtime mechanisms without changing workflow
authority. Do not rewrite the accepted OTP core merely for architectural fashion; require
the same substitution evidence before replacing it.

## Jev positioning: an optional reflex/assessor layer

Jev's System One design is unusually aligned with Foundry's intelligence boundary:
TypeSafe recommends keeping control flow, deterministic rules and side effects in code
while asking narrow typed questions and composing probabilities/confidence in software.
Use that shape where a fuzzy judgment is useful but authority is not required.

Potential post-evaluation consumers include context relevance, duplicate-finding
triage, stuck/progress classification, infrastructure-versus-assertion failure hints,
risk signals and execution-profile recommendations. Ask many narrow questions over a
bounded state, preserve the individual answers, and let deterministic policy choose
what confidence ranges may trigger an automatic low-risk action, verification or
escalation.

Jev is not the planner, scheduler, verifier or acceptance authority. It must not decide
entitlement, budget truth, Git ancestry, reviewer independence, whether an unknown
effect is safe to repeat, or whether an exact artifact may be promoted. Stage A remains
optional with deterministic fallback. Because Jev is currently early access, live use
requires fresh contract/terms/privacy/cost/conformance review and must remain replaceable.

## Lessons to adopt selectively

### FirstMate: operational clarity without another orchestrator

Provide one operator-facing interface that answers what was requested, what is
progressing, what is waiting, which decision belongs to the operator, and what was
accepted.

For the **first software-engineering lifecycle**, keep the operating structure shallow:
planner, bounded developers, independent reviewers and optional diagnostic help. This is
a proving workflow, not the permanent protected role taxonomy.

FirstMate's [current-state reader][fm-state] distinguishes append-only status events
from attributable current execution evidence. Apply that distinction in Foundry's
canonical projections: execution liveness, meaningful progress, workflow wait reason
and accepted outcome are separate facts. A failed observation is unknown, not proof
of death. Pane motion or a worker's last message cannot authorize retries or success.

Its [supervision design][fm-supervision] separates deterministic event filtering from
model-assisted attention. Implement ordinary classification, deadlines, capacity and
deduplication in Elixir. An optional diagnostic model may investigate ambiguity and
propose recovery, but cannot decide that an unknown effect is safe to repeat or that
a mandatory check may be ignored. Model-free idle supervision should consume no model
requests. Persist operator decisions until explicitly resolved; displaying a question
or compacting a conversation does not resolve it.

Do not embed FirstMate as a second owner of Foundry dispatch, retries, cleanup or
completion. Borrow mechanisms and failure scenarios, not a competing authority store.

### Pi: explicit session contracts and replaceable execution

The concrete [Pi harness design](PI-HARNESS.md) turns this strategy into a bounded
feature disposition, bridge threat model, P0/P1/P2 scope and conformance matrix. It is
a design candidate, not adoption or permission to bypass the governing repair gates.

Pi's [RPC contract][pi-rpc] is a useful example of structured headless integration.
A successful prompt response means accepted/queued/handled, not task completion.
Correlation IDs alone do not establish durable deduplication. Its documented abort
behavior also requires attention to queued work. Test lost acknowledgments, duplicate
submission, queued cancellation, session replacement and uncertain outcomes against
the actual harness, not a permissive mock.

Use Foundry's existing start/observe/prompt/interrupt/reconcile/close boundary. Keep
conversation continuity separate from workflow authority. The current contract chooses
a fresh developer after correction, not re-prompting the old developer; useful context
can transfer without reviving old execution authority.

Also separate **admitted capability** from **model-visible presentation**. Foundry may
authorize a broad bounded set while Pi presents only the few tool contracts/skills needed
for the current turn or exposes controller-approved discovery. This is a context-efficiency
optimization, never the enforcement boundary. Prefer progressive skills and deferred tool
metadata when controlled experiments show lower harness tax without worse accepted
outcomes. Execution-local notebook/code composition may similarly reduce model turns, but
its state is disposable and every nested effect/request remains individually governed.

The current source's implemented execution path still targets OMP, while production
automatic execution remains blocked.
The investment direction is now to evaluate Pi first as the replacement candidate before
deepening OMP-specific FR-09 work. Prefer a pinned `pi --mode rpc` subprocess with
strict JSONL framing over embedding a TypeScript SDK in the Elixir control plane. Keep the
bridge deliberately small: start, observe, prompt, interrupt, reconcile, close and
source-qualified usage observations. This is a preferred evaluation order, **not**
adoption: the existing FR-06 contract remains governing until a Pi candidate passes the
required tests and any OMP-specific contract text is explicitly revised and re-reviewed.

Pi itself runs with broad host authority by default. Its containerization guidance also
warns that extensions run wherever the Pi process runs; routing built-in tools into
Gondolin does not automatically sandbox unrelated extension tools. A production candidate
therefore needs pinned code/configuration; no unadmitted extension or
execution-changing configuration may be loaded; and an inventory must prove every
model-directed executable tool crosses the FR-15a isolation boundary. Do not turn Pi
extensions into a second authority or a bypass around Foundry's capability grants.

Pi RPC supplies useful diagnostic surfaces such as session token/cost/context statistics
and explicit compaction usage. Consume those through Foundry's observation contract with
source/quality labels. A prompt acknowledgement still means accepted/queued/handled, not
completion, and session statistics do not become budget, acceptance or retry authority.
Do not fund multiple equally elaborate production adapters before one works. Do not
rewrite Foundry as a collection of Pi extensions.

### Jido.Harness/ACP: benchmark the bridge before building it

The [Jido / Jido.Harness evaluation](JIDO-HARNESS.md) records a second implementation
candidate for the same harness-neutral boundary. At the pinned revision checked
2026-09-20, Jido.Harness normalizes Pi, Claude Code, Codex, Gemini and other coding-agent
CLIs into supervised Elixir runs/sessions/processes with stable IDs, replay journals,
process-group cancellation, explicit capabilities, usage/events and reusable contract
tests. Its current v3 path uses ACP through ExMCP; Pi therefore reaches Harness through an
ACP adapter rather than direct Pi JSONL RPC.

This is potentially valuable because Foundry should not maintain provider-specific
lifecycle machinery if a smaller external layer satisfies the contract better. It is
also an additional dependency/protocol/supply-chain boundary, and the checked Harness
version intentionally loses run/session state on BEAM/host restart. Foundry must therefore
remain the durable owner of execution intent, authority, budgets, effects and
reconciliation.

Do not choose between direct Pi RPC and Jido.Harness/ACP by API elegance. Run the same
pinned lifecycle, cancellation, lost-acknowledgement, restart, billing, isolation,
usage/provenance and useful-completion conformance cases against both. Verify explicitly
that ACP normalization does not discard provider-native information required by Foundry.
Choose one production bridge after that bounded comparison; do not maintain both merely
for optionality.

Jido core also reinforces useful design principles without becoming Foundry's control
plane: keep agent/workflow state as data where possible, separate pure decisions from
effects, distinguish process lifecycle from semantic completion, and test returned effect
intent independently from execution. BEAM process supervision is fault isolation, not
Foundry's filesystem/network/credential security boundary, and generic retry/backoff must
not replace effect claims plus unknown-outcome reconciliation.

### Isolation: reuse mechanisms, prove the whole boundary

The [Pi Gondolin example][pi-gondolin] demonstrates routing built-in tools into a
micro-VM while mounting the workspace read/write. This is an integration candidate,
not proof of Foundry's credential, network, request-budget or activation guarantees.
A different host/isolation topology also requires explicit review of the existing
account and provisioning contract; it cannot be silently substituted.

FR-15a/09 feasibility must inventory all candidate-controlled execution paths: shell,
file/custom tools, extensions, build hooks, language services, subprocesses, inherited
environment, network and shared writable state. Sandboxing one shell tool is insufficient
if another tool executes in a credential-bearing principal. Worktrees are not credential
or OS isolation; protected Git custody must not share candidate-writable authority.

First prove with synthetic credentials and controlled endpoints, then perform the
required bounded real-provider conformance under explicit authorization. Verify that
useful work can finish while tools cannot read reusable credentials, modify protected
state, or create model requests outside the claimed route. Missing proof keeps the
relevant capability disabled. A required upstream harness change should be narrowly
specified before downstream feature investment assumes compatibility.

### no-mistakes: review is an evidence subsystem

Its [agent interface][nm-agent] distinguishes structured-output rejection from provider
and process errors, preserves observed usage on failures, and exposes instruction
neutralization as a tested capability. Foundry reviewers need protected review rules
and trusted relevant project conventions; candidate-modified instructions are material
to inspect, not newly governing policy. Instruction suppression complements, rather
than replaces, credential, capability and filesystem separation.

Make the dependency chain explicit: specification/policy → frozen candidate → required
check receipts → independent review → integration → build → activation. Evidence names
its inputs. A changed candidate or base follows the workflow contract's renewed checks
and review, not an optimistic reuse of old approval. A fresh conversation or different
model alone does not establish independence.

Classify assertion failure, infrastructure failure, invalid artifact and unknown external
outcome separately. Correction, bounded infrastructure handling, validation and
reconciliation are different transitions; generic retry is not a safe default.

### OMP and context: improve feedback before adding more reasoning

Use the existing harness's useful editing and development tools before reimplementing
them in Foundry. Evaluate stale-edit refusal, language-aware diagnostics and bounded
structured results on real Elixir/Phoenix work. Edit anchors are not cryptographic
acceptance evidence or semantic correctness. A custom tool needs an observed recurring
failure and a measurable advantage over the existing toolchain.

FirstMate's [stable supervision prompt][fm-prefix] keeps changing event data out of its
stable prefix. Apply that discipline: trusted role instructions and conventions first;
versioned task/spec/candidate material next; changing observations last. Required context
must never be dropped to meet an arbitrary token limit. Policy changes invalidate stale
assumptions regardless of cache efficiency.

Retain required raw evidence. Summaries are attributed replaceable projections; lessons
are hypotheses until reviewed and tested for a named scope. A lesson cannot weaken a
mandatory gate. Start with task-specific context selection, not unlimited memory.

The bounded Stage-A implementation for issue #26 is documented in
[Assessor Stage A](ASSESSOR.md). It is an advisory experiment with deterministic fallback,
not a production provider route or an acceptance authority. Its longer-term purpose is
a replaceable fast semantic/reflex layer only if held-out evaluation shows net benefit.

### Efficiency observability: optimize accepted outcomes, not token count

Treat measurement as part of the execution contract, not optional dashboard polish. The
implementation inventory and target are maintained in [Observability](OBSERVABILITY.md).
Every useful harness should let Foundry attribute observed resource use along the durable
lineage from objective and ticket through attempt, execution, request/tool/effect,
candidate, review and accepted outcome. Telemetry remains diagnostic evidence: it cannot
mint authority, and missing usage stays unknown rather than becoming zero.

For model work, preserve source-qualified input, cache-read, cache-write, output,
reasoning/other-provider token classes where exposed, total usage, context-window
utilization, latency, retries/compactions and provider-reported cost. Keep provider
reported cost distinct from subscription capacity, local infrastructure cost and human
effort. For context optimization, record attributed **counts/digests**, not prompt bodies,
for mandatory policy, role instructions, task/spec, source files, retrieved docs/tool
results, conversation history and correction history. Estimated attribution must remain
labelled estimated even when the provider's total is exact.

Record tool execution separately: tool/capability identity, duration, raw and
model-visible result size, truncation/error and the amount subsequently admitted to model
context. Also separate deterministic controller waiting from model wakeups and record
whether a wake had an actionable event, deadline or operator decision. Idle child polling
should not consume model requests merely to rediscover that nothing changed. Link
developer, reviewer, PM/assessor and correction consumption to the exact attempt/candidate
so failed work and rework are not hidden by a successful final run. Retention/compaction
must preserve numeric usage totals and provenance needed for longitudinal comparison.

The primary optimization target is trustworthy accepted delivery with low operator burden,
not minimum tokens. Compare like task classes using measures such as accepted outcomes per
operator hour, tokens/cost per accepted outcome, first-pass acceptance, correction and
failed-work tax, cache effectiveness, context/tool-result tax and wall-clock latency.
Cheaper runs that create more rework, miss defects or require more operator attention are
not improvements. Require a baseline, fixed evaluation and rollback/stop decision before
an efficiency proposal changes production behavior.

## Investment milestones within the repair plan

| Milestone | Owning repair work | Evidence before expanding investment |
|---|---|---|
| Feasibility and durable foundation | FR-07/08; bounded investigations informing FR-15a/09 | Actual binding/store/replay proof and executable evidence for a viable harness/tool separation |
| One useful complete task | FR-09–13, FR-15a/15 and their prerequisites | Authorized execution, frozen candidate, real checks, independent review and bounded correction |
| Recovery and controlled integration | FR-10–14, FR-16 and their prerequisites | Interrupted effects reconcile; stale work cannot advance; budgets and ownership survive restart |
| Controlled self-update | FR-17, FR-20/21 and their prerequisites | A real kernel repair activates under unchanged protected authority; rollback preserves acknowledged work |
| Operational acceptance | FR-18/19/22 and all remaining obligations | Useful delivery, honest status, bounded maintenance, real-host/provider evidence and explicit unsupported cases |

These group evidence, not a substitute dependency order or permission to close a parent
ticket early. Demonstrate a correction cycle plus interruption before concurrency. Give
checks, reviewers and admitted finalization capacity ahead of new developers. A cosmetic
board update is not proof of autonomous kernel repair. Do not restore an old snapshot
over newer acknowledged commands to claim successful rollback.

## Resource allocation and evaluation

Assign one architecture/integration owner, explicit durable-state/workflow ownership,
execution/isolation ownership, and genuinely independent verification. These are
responsibilities, not a mandatory headcount. Additional capacity should first improve
real execution environments and independent falsification, not multiply conflicting
edits to shared authority code. Preserve ongoing ticket ownership and unpublished work.

Prioritize state-machine/replay tests, crash-boundary tests, adversarial authority tests
and positive delivery controls. Deliberately break selected protections and require tests
to detect those mutations. A test that derives its expectation from the same broken
implementation is weak evidence. Refusing everything must fail useful-delivery acceptance.

Track both safety and usefulness: operator effort per accepted change, correction and
recovery burden, queue versus execution time, unresolved outcomes, stale-evidence rejection,
budget conservation, and observed versus unknown usage. No assumed model savings or
unmeasured throughput claims. Self-improvement proposals need a baseline, fixed evaluation,
regression checks, effort cap and rollback decision outside the candidate's control.

Postpone multi-machine fleets, deep agent hierarchies, broad plugin marketplaces,
automatic policy learning, custom terminals/harnesses, generalized memory platforms and
custom replacements for mature external infrastructure that has not failed a Foundry
conformance evaluation.
The [broader strategy](../../docs/strategy/FOUNDRY.md) owns later repository portability,
context/tool experiments and Superlogical evaluation. Do not put an unverified future
presentation backend on the repair critical path.

## How to use this brief on a task

Read the working summary once when entering Foundry work. For design, new dependencies,
provider/backend changes or investment decisions, read the relevant section as well.
Then work from the current repair ticket, governing contract, source and exact evidence.
State which responsibility a proposed change belongs to, which failure it addresses,
and how both safe refusal and useful completion will be tested. Do not preload every
linked source or append an unrelated initiative to the repair queue.

## Source observations

The following pinned sources informed the 2026-09-17 comparison. Their capability claims
are not installed-backend conformance, privacy/billing authorization or benchmark evidence.
Recheck current licensing and integration terms before copying code or adding dependencies.

[fm-state]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/bin/fm-crew-state.sh
[fm-supervision]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/docs/pi-supervision-branch.md
[fm-prefix]: https://github.com/kunchenguid/firstmate/blob/f5d7f5f2484564dd855b76e7e40ef8c40dc7ab2b/bin/fm-branch-prompt.sh
[pi-rpc]: https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/docs/rpc.md
[pi-gondolin]: https://github.com/earendil-works/pi/blob/46c9de402bddf46b03c3b9f46487b777aaa41861/packages/coding-agent/examples/extensions/gondolin/index.ts
[nm-agent]: https://github.com/kunchenguid/no-mistakes/blob/71cd9110543eeac67fd76180f2bdabd355395ec2/internal/agent/agent.go
[jido-harness]: https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/README.md
[jido-normalization]: https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/guides/normalization_and_data_model.md
[jido-acp]: https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/docs/decisions/exmcp-acp-boundary.md


### Additional substitution-source observations — checked 2026-09-18

These sources motivate evaluation, not adoption. Recheck versions, licensing and
interfaces when an experiment is actually authorized.

- [Warp documentation](https://docs.warp.dev/) describes Factories (Early Access) as
  repeatable software-development workflows in which agents triage, spec, implement,
  review and verify work, with multi-model support. Treat it as a serious benchmark for
  Foundry's software-factory value, not proof of generalized non-software authority.
- [TypeSafe's System One design guide](https://docs.typesafe.ai/concepts/how-to-build-with-system-one)
  explicitly keeps control flow, deterministic rules and side effects in code and uses
  narrow typed model decisions; [Jev's launch note](https://typesafe.ai/blog/introducing-system-one-models-and-jev)
  says Jev is early access. This supports the assessor/reflex positioning, not authority.
- [Dagger's Elixir SDK](https://docs.dagger.io/reference/sdks/elixir/) exposes typed
  container/file/directory/secret APIs but is currently beta with documented feature
  limitations. Evaluate it as execution plumbing rather than assuming isolation parity.
- [OPA](https://www.openpolicyagent.org/docs) and
  [Cedar](https://docs.cedarpolicy.com/) are mature policy-engine candidates for bounded
  authorization decisions; neither by itself supplies Foundry's durable claims, budgets,
  evidence binding or reconciliation.
- [Restate](https://restate.dev/), [Temporal](https://docs.temporal.io/),
  [DBOS](https://docs.dbos.dev/) and [LangGraph](https://www.langchain.com/langgraph)
  overlap with durable execution/orchestration. Their existence is a reason to benchmark
  before extending Foundry's runtime, not a reason to migrate without contract evidence.
- [Jido.Harness][jido-harness] and its [normalization model][jido-normalization] provide
  a concrete Elixir harness-normalization candidate; its [ACP boundary][jido-acp] also
  adds protocol/dependency surface. Benchmark it against direct Pi RPC instead of assuming
  either a custom adapter or a generic harness is automatically simpler.
- Linux already supplies hard-isolation primitives including
  [namespaces](https://man7.org/linux/man-pages/man7/namespaces.7.html),
  [cgroups](https://man7.org/linux/man-pages/man7/cgroups.7.html),
  [seccomp](https://man7.org/linux/man-pages/man2/seccomp.2.html) and
  [Landlock](https://cdn.kernel.org/doc/html/latest/userspace-api/landlock.html).
  Foundry should compose proven OS enforcement rather than recreate it in application code.
