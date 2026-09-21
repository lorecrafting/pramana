# Cloudflare OS lessons for Foundry

**Date:** 2026-09-21. **Type:** architecture research and design pressure, not dependency
adoption, repair-ticket reprioritization, production authorization or evidence that
Cloudflare OS satisfies Foundry conformance.

[Foundry strategy](STRATEGY.md) · [Ecosystem boundary](ECOSYSTEM-BOUNDARY.md) ·
[AX/Substrate backend](AX-SUBSTRATE.md) · [Workflow contract](WORKFLOW-CONTRACT.md) ·
[Broader research register](../../docs/strategy/RESEARCH.md)

## Source snapshot

This note was checked against Cloudflare OS at pinned revision
[baa4f7cc4ab628c5d157c68054b315695de02fa1](https://github.com/cloudflare/cloudflare-os/tree/baa4f7cc4ab628c5d157c68054b315695de02fa1),
including its README, Gatekeeper API, Gatekeeper action journal and usage contract,
observer/information-flow design, and repository agent/runtime guidance at that exact
revision.

The broader execution-ladder comparison also checked Cloudflare's
[Project Think](https://blog.cloudflare.com/project-think/) and
[Sandbox security model](https://developers.cloudflare.com/sandbox/concepts/security/) on
2026-09-21.

Cloudflare OS marks the current v2 repository **early access** and describes it as a complete
rewrite of v1. Its local wrangler/workerd path is explicitly not the recommended
production-server deployment, and the README still marks polished self-hosted workerd
deployment guidance as coming soon. Treat current implementation details as moving targets.

## Executive conclusion

Cloudflare OS is highly relevant to Foundry, but **not in the same architectural position as
AX/Agent Substrate**.

The useful split is:

~~~text
                         organizational/work platform
                                  |
                          Cloudflare OS
                        /               \
       capability/effect ideas           agent workspace/product ideas
                    \                   /
                     \                 /
                          Foundry
              authority / evidence / acceptance
                     /                 \
                    /                   \
        ExecutionBackend             ResourceAdapter
          "where/how"               "what may be touched"
            /   \                     /   |   \
           /     \                   /    |    \
 AX/Substrate   Cloudflare       GitHub  Google  Slack ...
  or local      primitives
~~~

Cloudflare OS itself already owns users, workspaces, sharing, approvals, observations,
credential mediation, side-effect journals and agent/application lifecycle. Putting the
whole product under Foundry would create overlapping control-plane authority and a
dual-truth problem.

However, three Cloudflare ideas are strong enough to refine Foundry's architecture:

1. **Gatekeeper-like resource capabilities:** external credentials stay behind a typed,
   resource-scoped broker rather than becoming ambient agent secrets.
2. **Observation provenance:** policy may depend not only on what an execution is allowed to
   do, but on what protected data it has actually observed.
3. **Execution ladder:** use the least-privileged compute environment capable of the task,
   escalating from data/workspace operations to isolates, browser automation or full OS
   sandboxes only when required.

The underlying Cloudflare execution primitives can also become a separate future
ExecutionBackend family, especially for lightweight or non-software work.

## Cloudflare OS is beside Foundry, not below it

Cloudflare OS describes its own architecture with an operating-system analogy:

| Normal OS | Cloudflare OS |
|---|---|
| kernel | workshop-backend |
| device drivers | Gatekeepers |
| shell | workshop frontend |
| processes | Gadgets |
| executables | Blueprints |
| users | users |
| ACLs | sharing permissions |

The kernel performs security, user/workspace coordination, application isolation,
resource binding, approval and observation enforcement. Those are not merely commodity
process-execution concerns.

Foundry already claims a narrower but overlapping control-plane responsibility:

- principals and delegation;
- CapabilityGrant and policy generation;
- durable reservations/effect semantics;
- evidence and provenance;
- approval/review requirements;
- acceptance and promotion.

Therefore this is undesirable:

~~~text
Foundry authority
      |
      v
Cloudflare OS authority
      |
      v
external effect
~~~

because an integration would then have two answers for questions such as:

- Which grant authorized the action?
- Which authority generation applies?
- Was the action approved?
- Was a provider effect known to land?
- Which observation history constrains disclosure?
- Which state is authoritative after reconnect/retry?
- Which system decides the output is acceptable?

The correct use of Cloudflare OS is as a **design comparator** and source of independently
developed mechanisms. Reuse lower-level Cloudflare primitives only through Foundry-owned
contracts.

## Two independent substitution axes

The AX/Substrate review focused on ExecutionBackend. Cloudflare OS demonstrates that
Foundry needs an equally explicit second seam.

### Axis A — ExecutionBackend

Answers:

> Where does admitted code run, how is it isolated, and how is lifecycle observed?

Candidate responsibilities include:

~~~text
prepare
launch
observe
signal
suspend/resume
cancel
collect
destroy
reconcile
~~~

Possible implementations:

- local controlled Linux worker;
- AX over Agent Substrate;
- Cloudflare Dynamic Worker;
- Cloudflare Sandbox;
- future durable runtimes.

### Axis B — ResourceAdapter / capability broker

Answers:

> How may this principal read or affect a particular external resource without receiving
> ambient credentials or broader authority?

Candidate responsibilities include:

~~~text
describe resource/capabilities
verify principal/resource scope
observe/read through typed interface
stage consequential action
bind authority generation
request/record approval when required
apply
return exact receipt or unknown outcome
reconcile
revoke
~~~

Possible implementations:

- a native Foundry adapter;
- a Gatekeeper-inspired broker;
- provider-specific services;
- future standard capability/effect protocols.

These axes compose:

~~~text
Foundry admitted execution
        |
        v
ExecutionBackend
        |
     agent/harness
        |
        v
ResourceAdapter
        |
        v
external provider
~~~

The process sandbox should not need the provider's root credential. The resource adapter
should not get to create Foundry grants or acceptance facts.

## Gatekeepers: strongest design lesson

Cloudflare OS Gatekeepers are provider-specific capability brokers. The current README says
they expose a clean RPC API over the provider, handle authorization such as OAuth, constrain
access to the intended resource, log actions, and mediate side effects through human
approval.

Cloudflare OS also makes the application/agent start with no ambient resource access.
Resources are introduced explicitly. Its Dynamic Worker gadget execution is described as
having internet access disabled and reaching designated resources through bindings.

That suggests a stronger Foundry target than merely:

~~~text
sandbox + GITHUB_TOKEN + network allowlist
~~~

Prefer:

~~~text
sandbox
   |
   +-- RepoReadCapability(repo=X)
   +-- IssueWriteCapability(repo=X)
   +-- ModelInvokeCapability(route=Y)
   |
   v
typed broker(s)
   |
credentials remain outside agent
~~~

Network isolation remains useful defense in depth, but typed capability mediation can
remove large classes of ambient authority before network policy has to catch them.

## ResourceCapability as a compiled projection

Foundry's existing CapabilityGrant should remain the authoritative policy object.

A Gatekeeper-like adapter should receive only a compiled, execution-specific projection:

~~~text
CapabilityGrant
  principal
  assignment
  generation
  resource scope
  operations
  budget/effect limits
        |
        v
ResourceCapability
  provider = github
  resource = repo:owner/name
  operations = [read_issue, create_pr]
  authority_generation = G17
        |
        v
GitHub ResourceAdapter
~~~

ResourceCapability is an integration representation, not a second grant ledger.

A provider reconnect, credential rotation, resource move or policy revision must be
reconciled back to Foundry's generation semantics before further consequential effects.

## Side-effect lifecycle convergence

Cloudflare's current Gatekeeper action journal independently converges on several Foundry
effect principles.

Its journal models:

~~~text
staged -> pending -> claimed -> applied
                    \
                     -> failed
~~~

and a failed record distinguishes a provider effect known to be absent from one whose
outcome is unknown. The source comments explicitly say an unknown provider effect may
already have committed, so it is not automatically replayed and is retained rather than
pruned like an ordinary known failure.

That is direct design pressure for Foundry's existing unknown-effect contract:

~~~text
claim before effect
attempt
exact receipt OR unknown
unknown -> reconcile before unsafe retry
~~~

The lesson is not to import Cloudflare's storage schema. It is that a production-oriented
agent system independently encountered the same failure class and chose not to flatten
unknown into failed.

## ActionFence and authority generation

The current Gatekeeper journal stores an opaque ActionFence with a generation for action
kinds that require authority fencing. Apply compares the staged fence with current authority
before handler dispatch.

This closely matches Foundry's existing rule that previously prepared work cannot execute
under silently changed authority.

~~~text
stage action under authority generation G17
              |
              v
          approval/wait
              |
              v
       apply under current G?
          /           \
        G17           other
         |              |
      dispatch        refuse
~~~

Cloudflare's implementation supports connection-scoped generation or an adapter-supplied
stable account identity. Foundry should retain its richer principal/assignment/grant
lineage and treat a resource adapter's fence as a projection of that authority.

## Approval after simulation

Cloudflare OS demonstrates a useful workflow technique: a Gatekeeper may stage a
consequential action, simulate the result so the agent can continue reasoning, then allow a
human to approve/reject later.

For Foundry, the important distinction is:

~~~text
simulated effect
    != provider effect
    != accepted outcome
~~~

Any future speculative/simulated action layer must keep those identities explicit.

A model may reason over projected/simulated state, but simulation cannot mint an
external-effect receipt; dependent actions must preserve dependency on the unresolved real
effect; rejection must unwind or invalidate staged dependents safely; approval must recheck
current authority/fence before dispatch; and an unknown real provider outcome must not be
overwritten by simulation.

The technique is interesting; the Foundry effect ledger remains the authority.

## Observation provenance: what did this execution see?

Cloudflare OS's strongest novel pressure on Foundry is its treatment of **observations**.

A Gatekeeper can record what protected resource/data a workspace actually observed. When
another user tries to observe/share the workspace, the producer's Gatekeeper can verify the
new observer against the relevant provider ACLs. For resource families whose children have
different ACLs, Gatekeepers can track the specific subsets actually read and exclude a
prospective observer who lacks access.

The current system also supports observation attributes such as containsRestrictedData.
Once restricted data is observed, the workspace can enter a restricted mode that blocks
actions and public web fetches. At the current pinned revision, an ownerInvitesOnly
observation can additionally latch stricter sharing behavior.

This suggests that Foundry's future policy model may need both:

~~~text
CapabilityGrant
  "what may this principal do?"
~~~

and:

~~~text
Observation provenance
  "what protected information has this execution/artifact consumed?"
~~~

Those are different facts.

### Current Cloudflare observation enforcement is useful, not complete

Do not overread the pattern as proof that Cloudflare OS already solves general
information-flow control. The pinned observer design explicitly keeps v1 enforcement
coarse (including no per-thread hiding) and records known fail-open windows. For example,
it documents a first-time observer-registration interval in which an observer id may be
known to Gatekeepers before the overseer's reverse record exists, and a retained binding
loopback case where stored graph state can say a resource left scope while a previously
minted capability can still reach it. Those are tracked as required fixes in Cloudflare's
own design.

That honesty is itself useful design pressure for Foundry:

- observation provenance and revocation must be tested against escaped capabilities, not only
  current graph/config state;
- "not present in the index" cannot automatically mean "not currently authorized/active";
- revocation must cover already-issued capabilities and live sessions;
- a provenance model is only as strong as every egress/effect path that consumes it;
- fail-open residuals must remain visible instead of being hidden behind a high-level
  "information-flow aware" label.

Any Foundry experiment should therefore reproduce these adversarial classes rather than
copy only Cloudflare's happy-path observation API.

## Candidate ObservationReceipt

Do **not** add this to the protected ontology during the current repair merely because the
idea is promising. But preserve a future seam capable of carrying something like:

~~~text
ObservationReceipt {
  execution_id
  adapter_id
  resource_identity
  resource_revision_or_scope
  classification
  observed_at
  evidence_ref
}
~~~

Then a policy decision may be a function of both grant and provenance:

~~~text
may_effect(
  principal,
  requested_operation,
  target_resource,
  CapabilityGrant,
  ObservationSet
)
~~~

Example:

~~~text
grant:
  public_website.publish

observed:
  confidential/customer-segment

policy:
  confidential data -> public publication requires declassification/review

result:
  blocked / approval required
~~~

This becomes increasingly important if Foundry governs marketing, community, research,
finance or other non-code workflows where disclosure risk depends on information consumed,
not only API permission.

## Derived-artifact provenance

Observation tracking is also useful without dynamic security policy.

~~~text
artifact A
  derived_from observation O1
  derived_from observation O2
  produced_by execution E
  accepted_under policy P
~~~

This can improve explainability, deletion/retention impact analysis, downstream sharing
decisions, confidential/public boundary checks and audit reconstruction.

The protected Foundry rule remains exact: provider/Gatekeeper observations are evidence
inputs until Foundry binds them to the exact execution/artifact identity.

## Execution ladder

Cloudflare's Project Think describes an explicit execution ladder:

| Tier | Environment | Approximate privilege/cost shape |
|---|---|---|
| 0 | durable Workspace | filesystem/data operations |
| 1 | Dynamic Worker | sandboxed generated JavaScript, no ambient network |
| 2 | Dynamic Worker + npm | isolate plus selected packages |
| 3 | browser | web automation |
| 4 | full Sandbox | Linux/git/compilers/test runners |

The valuable idea is not Cloudflare's exact tier numbering. It is:

> **Do not give every assignment a full general-purpose machine. Escalate execution power
> only when the admitted work needs it.**

A Foundry-neutral version might become:

~~~text
E0  pure/reflex/model decision
E1  typed ResourceAdapter calls, no arbitrary code
E2  restricted code isolate, capability bindings only
E3  browser/document automation
E4  full Linux sandbox
E5  exceptional privileged profile, separately governed
~~~

The planner may propose an execution profile. Foundry admission chooses or narrows it.

Measure smaller attack surface, credential exposure, startup/compute cost, cleanup burden,
tool-schema/context overhead and replay/observation quality. Keep this a replaceable
policy/profile mechanism, not a hard-coded Cloudflare ontology.

## Cloudflare runtime as an alternate ExecutionBackend family

Cloudflare OS itself is not the backend, but its underlying primitives may be useful
implementations.

### Dynamic Worker

Good candidate for short generated-code transformations, data processing, API composition
behind explicit bindings and lightweight non-software workflows. Its design advantage is
low ambient authority and fast isolate startup.

### Durable Object / fiber-oriented execution

Potentially useful for waiting/scheduled work, long-lived lightweight agents, durable
per-assignment state and real-time collaboration or control-plane adjuncts.

Do not duplicate Foundry's authority reducer inside a Durable Object. Durable Object state
would be backend/runtime state unless explicitly imported as evidence.

### Cloudflare Sandbox

Cloudflare's current Sandbox SDK documentation says each sandbox runs in its own VM with
filesystem, process and network isolation plus per-sandbox CPU/memory/disk quotas.

This makes it a plausible alternate full-OS backend for repository checkout,
compilers/test runners, shell-based coding agents and heavyweight toolchains.

The same warning applies as AX/Substrate: sandbox success is process-level evidence, never
task acceptance.

## Multi-backend architecture

Foundry should not prematurely choose one universal compute substrate.

~~~text
Foundry.ExecutionBackend
        |
        +-- LocalLinux
        |
        +-- AX
        |    \-- Agent Substrate
        |
        +-- CloudflareIsolate
        |
        +-- CloudflareSandbox
        |
        +-- future backends
~~~

and independently:

~~~text
Foundry.ResourceAdapter
        |
        +-- GitHub
        +-- Google
        +-- Slack
        +-- Browser
        +-- Model route
        +-- future capability brokers
~~~

A workflow profile may select a combination:

~~~text
marketing research:
  ExecutionBackend = CloudflareIsolate
  ResourceAdapters = CRM(read), analytics(read), website(stage-publish)

software build:
  ExecutionBackend = AX/Substrate
  ResourceAdapters = GitHub(repo scoped), CI, model route

small deterministic edit:
  ExecutionBackend = local restricted worker
  ResourceAdapters = none
~~~

This better supports Foundry's goal of serving different departments/work types without
turning one backend's primitives into the protected ontology.

## Cloudflare OS and Pi

The current Cloudflare OS repository uses pi-agent-core and credits Pi for model-provider
abstraction.

That is useful external validation of a pattern Foundry is already evaluating:

~~~text
small/reusable agent loop
       +
strong deterministic surrounding platform
~~~

It is **not** evidence that Pi automatically satisfies Foundry's subscription, provider,
isolation, lifecycle or evidence requirements. FR-09/15a conformance remains necessary.

## What to borrow versus what not to copy

Borrow as design pressure:

- capability-first resource access;
- credentials outside generated code;
- explicit observation recording;
- information-flow-aware sharing/action policy;
- staged/claimed/applied effect state;
- first-class unknown provider outcome;
- authority-generation fencing;
- deferred approval with simulation;
- least-privilege execution ladder;
- independently replaceable provider-specific adapters.

Do not copy by default:

- Cloudflare OS's workspace/user/product ontology;
- its approval queue as Foundry authority;
- its sharing graph as Foundry principal policy;
- Gatekeeper action records as Foundry's canonical effect ledger;
- provider connection generation as the complete Foundry grant identity;
- Dynamic Workers/DOs as required infrastructure;
- Cloudflare-specific RPC/type shapes in the protected domain;
- optimistic product claims as local security/conformance evidence.

## Conformance questions for a Gatekeeper-like ResourceAdapter

A future ResourceAdapter contract should be tested at least for:

1. the agent cannot access provider credentials directly;
2. resource scope is narrower than provider/account scope where requested;
3. an ungranted resource or operation is denied even if the underlying credential permits it;
4. reconnect/credential replacement cannot apply an action staged under stale authority;
5. consequential effects are claimed before dispatch;
6. timeout/lost response produces exact receipt or explicit unknown, never guessed failure;
7. unknown effect cannot be automatically retried unsafely;
8. rejection/cleanup cannot leak staging artifacts or grant future authority;
9. approval is bound to exact action payload/resource/authority generation;
10. observation records identify the actual protected data/resource scope read;
11. revocation or widened observation scope re-evaluates downstream disclosure/access as policy
    requires;
12. sensitive observation cannot leak through an unrelated adapter/public-web route;
13. adapter restart cannot replay an already-landed effect;
14. logs/errors do not expose provider credentials;
15. simulation is clearly distinguishable from real provider state;
16. provider-specific assertions are treated as evidence, not Foundry acceptance;
17. adapter upgrade fails pinned conformance until reviewed.

## Experiment sequence

This research creates no current repair dependency.

After FR-22 or separately authorized bounded research:

### C0 — Contract extraction

- define a vendor-neutral ResourceAdapter/capability-broker contract;
- map current Foundry effect adapters onto it without changing authority;
- decide whether ObservationReceipt remains telemetry/evidence-only or needs a later protected
  policy role;
- define execution-profile selection independently of any Cloudflare tier names.

### C1 — Capability-broker fixture

Build a provider-free fake adapter proving credentials never enter the agent environment,
narrow resource capability, staged action + approval, authority fence, unknown-effect
reconciliation and observation recording.

Compare complexity against direct shell/MCP/provider access.

### C2 — Cloudflare primitive experiment

If useful, test Dynamic Worker for restricted generated-code tasks, Sandbox for full
Linux/coding tasks, and Durable Object/fiber semantics for waiting work.

Run them through the same ExecutionBackend contract as local and AX paths.

### C3 — Information-flow experiment

Use a synthetic classified-resource fixture:

~~~text
read private resource -> produce artifact -> attempt public effect
~~~

Compare grant-only policy with grant + ObservationReceipt policy, including operator burden,
false blocks and provenance quality.

Do not promote observation-derived restrictions into default Foundry policy without this
evidence.

## Relationship to AX/Substrate

The two research tracks are complementary.

~~~text
AX/Substrate asks:
  how do we safely run and resume many stateful agent workloads?

Cloudflare OS asks:
  how do we safely let agents and generated apps touch organizational resources and data?

Foundry asks:
  under what admitted authority, budgets and evidence may work/effects occur,
  and what can become accepted?
~~~

AX/Substrate is therefore the stronger first candidate for distributed **heavy execution**.

Cloudflare's capability model is the stronger design reference for **external-resource
mediation and information-flow provenance**.

Cloudflare runtime primitives may still outperform AX for some lightweight workloads.
That should be measured by workload class rather than settled by architecture aesthetics.

## What this does not authorize

This note does not:

- add Cloudflare OS, Workers, Durable Objects, Sandbox or Project Think as production
  dependencies;
- adopt Cloudflare OS's product/kernel as Foundry's authority layer;
- create ObservationReceipt as a protected persisted record during the current repair;
- replace existing CapabilityGrant, effect, budget or acceptance semantics;
- allow resource adapters to mint Foundry permission;
- permit agent-authored extensions to self-grant capability;
- permit full-network access merely because code runs in a sandbox;
- replace AX/Substrate evaluation;
- claim Cloudflare's internal use proves Foundry's security or economics;
- change FR-06, FR-09, FR-15a, FR-18, FR-22 or current production authorization.

## Resulting architecture principle

The refined Foundry position is:

> **Separate authority from both compute and resources. Foundry decides what work and
> effects are admitted; ExecutionBackends decide how code runs; ResourceAdapters mediate
> narrowly scoped external resources; observation provenance can inform policy without
> becoming self-authenticating authority.**

That decomposition gives Foundry room to use AX/Substrate, Cloudflare primitives or future
systems where each is strongest without letting any one ecosystem become Foundry's product
ontology.
