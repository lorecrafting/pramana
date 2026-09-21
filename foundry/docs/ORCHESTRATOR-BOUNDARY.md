# Orchestrator boundary — authority path, observation path, and controller adapters

**Date:** 2026-09-21. **Type:** post-repair architecture guidance. This document
does not change the active repair plan, accepted workflow contract, current launch policy,
provider entitlement, production authorization or FR-08 implementation scope.

[Foundry strategy](STRATEGY.md) · [Workflow contract](WORKFLOW-CONTRACT.md) ·
[Project workflow profiles](PROJECT-WORKFLOW-PROFILES.md) ·
[Observability](OBSERVABILITY.md) · [Ecosystem boundary](ECOSYSTEM-BOUNDARY.md) ·
[Cloudflare OS lessons](CLOUDFLARE-OS.md)

## Decision

Foundry should be the **authority/evidence/acceptance control plane** for model-directed
work, not the mandatory owner of every planning loop or orchestration runtime.

External orchestrators may decide how to plan, decompose, sequence, parallelize, wait,
retry, correct and coordinate agents. They interact with Foundry through a small versioned
machine protocol that exposes authoritative facts and accepts bounded proposals. Foundry
alone turns an accepted proposal plus required evidence into authoritative Foundry state.

> **Do not wrap the whole orchestrator; wrap its authority boundaries.**

A Cloudflare OS Gadget, Pi controller, AX reconciler, Claude Code/Codex harness, custom
planner or future workflow runtime may all drive the same Foundry-governed project without
becoming a source of Foundry grants, budgets, evidence binding, acceptance or promotion.

The CLI remains useful for operators and debugging, but it should be a client of the same
machine protocol rather than the primary integration interface.

## Why this boundary

Foundry's durable value is not that it can tell an agent what to do next. Models and
orchestration systems will continue to improve at that job.

The facts that must remain trustworthy even when the planner is wrong are different:

- what objective and policy revision were admitted;
- which principal/assignment received which capability;
- which budget/reservation authorized a request;
- whether a consequential external effect was claimed and issued;
- whether an unknown effect was reconciled before retry;
- which exact artifact/candidate an observation, check or review applies to;
- whether required review is actually independent;
- whether mandatory checks and acceptance predicates are satisfied;
- whether an exact artifact may be integrated, published, deployed or activated.

Those facts belong to Foundry. Planning and orchestration strategy do not.

## Topology

~~~text
                         human / steering
                               |
                               v
                    +---------------------+
                    |       FOUNDRY       |
                    |                     |
                    | admitted intent     |
                    | durable identities  |
                    | capability grants   |
                    | budgets/effects     |
                    | evidence binding    |
                    | acceptance          |
                    | promotion           |
                    +----------+----------+
                               |
                     facts + bounded grants
                               |
              +----------------+----------------+
              |                                 |
              v                                 v
      default Foundry                     external controller
      workflow kernel               Cloudflare / AX / Pi / ...
              |                                 |
              +----------------+----------------+
                               |
                         assignments
                               |
              +----------------+----------------+
              |                                 |
              v                                 v
       ExecutionBackend                  ResourceAdapter
   where/how work executes             what may be touched
              |                                 |
              v                                 v
        agents / tools                 GitHub / Loka / SaaS
~~~

The current workflow kernel remains a valid default orchestrator/controller. The protected
semantics must not require that one implementation forever.

One product may implement more than one replaceable seam, but the responsibilities remain
separate for authority and conformance. For example, Cloudflare OS may be a controller
while Dynamic Workers/Sandbox implement ExecutionBackend and Gatekeepers implement
ResourceAdapter. AX may act as controller while AX/Substrate also implements execution.
Using one vendor for several seams must not let controller state bypass the protected
boundary between them.

## Two paths: authority and observation

An orchestrator integration has two deliberately different paths.

### Authority path

The authority path is low-volume, synchronous at the protected decision boundary, durable
and idempotent. It is used when something would create or change a Foundry fact or permit a
consequential operation.

Examples:

~~~text
objective proposal/admission
assignment proposal/admission
capability issuance/revocation
budget reservation/settlement
execution issuance
candidate/artifact registration
effect claim/issue/settlement
review/check receipt registration
acceptance evaluation
integration/publication/deployment/activation
cancellation and reconciliation
~~~

The orchestrator sends a semantic command or proposal. Foundry validates authenticated
identity, expected revisions, scope, current policy, capability, budget and prerequisite
evidence, then returns a durable disposition such as accepted, rejected or blocked plus
canonical IDs/revisions.

An orchestrator never calls a generic advance operation. It proposes meaning:

~~~text
propose_assignment(...)
register_candidate(...)
request_effect(...)
submit_review(...)
record_check(...)
request_acceptance(...)
request_promotion(...)
~~~

Foundry determines whether that proposal is a legal authoritative transition.

### Observation path

The observation path is high-volume, asynchronous where possible and non-authoritative. It
captures what the orchestrator, harness, model, tools and runtime actually did. Losing an
observation must never create authority or false success, but required local
retention/quality rules still matter for diagnosis, cost accounting and self-improvement;
"non-authoritative" does not mean "disposable".

Examples:

~~~text
model request started/completed
token/cache/cost observations
tool invocation
tool-result size/truncation
context composition
orchestrator wake/sleep
child/job lifecycle
sandbox/runtime metrics
queue delay
human steering/review time
diagnostic logs
provider latency
~~~

Observation records support diagnosis, comparison, self-improvement and evidence
collection, but telemetry cannot itself mint authority.

A trace saying a test process exited zero is not automatically a mandatory check receipt.
A controller event saying completed is not automatically an accepted outcome.
A model saying done is not automatically a candidate.

## Three classes of durable information

Keep three classes distinct even when they share correlation IDs.

| Class | Examples | Authority |
|---|---|---|
| **Protected facts** | grant, reservation, effect state, accepted candidate, promoted ref | authoritative |
| **Evidence** | exact review receipt, approved check receipt, Git/artifact proof, reconciliation receipt | can satisfy a protected predicate when its verifier accepts it |
| **Telemetry** | tokens, latency, tool events, traces, controller wakes, process metrics | never authoritative by itself |

The observation pipeline may retain or reference evidence artifacts, but it must not
silently reinterpret telemetry as a protected receipt. A raw artifact or controller event
can arrive through the observation transport; it becomes Foundry evidence only after the
applicable protected binding/validation records what exact candidate, execution and policy
it supports.

## Machine protocol, not CLI coupling

The primary integration surface should be a small versioned machine API.

For the current local architecture this should remain compatible with the accepted
workflow contract's authenticated local boundary: a protected endpoint such as the
Unix-domain-socket protocol, with transport/capability-derived identity and no arbitrary
BEAM eval.

~~~text
Foundry daemon
   |
   +-- machine protocol  <---- orchestrator adapters
   |
   +-- CLI               <---- human/operator
   |
   +-- status/UI         <---- projections
~~~

The CLI should call the same semantic operations. It is useful for steering, manual
dogfood, inspection, incident recovery, conformance fixtures and scripting. It should not
become the long-term way a remote controller invokes every transition by repeatedly
shelling out to a subprocess.

A future remote gateway may expose the same semantics over an authenticated transport.
That is a transport substitution, not permission to broaden the protected API.

## OrchestratorAdapter contract

A thin **OrchestratorAdapter** translates one controller's concepts into Foundry's stable
semantic commands and observations.

Responsibilities:

~~~text
connect / authenticate controller principal
read canonical facts and requirements
subscribe to relevant state changes
propose bounded assignments/workflow amendments
request issued execution grants
map controller jobs/sessions to Foundry execution IDs
emit source-qualified observations
register produced artifacts/evidence
request consequential effects through Foundry
map cancellation and unknown outcomes
reconcile controller/runtime state after restart
~~~

It must not:

~~~text
mint CapabilityGrant
settle Foundry budgets from its own counters
turn controller success into acceptance
declare reviewer independence
retry an unknown consequential effect
promote/publish merely because its workflow says to
rewrite prior acknowledged Foundry history
~~~

The adapter should be small enough that conformance can test the semantic mapping without
requiring Foundry to understand the controller's internal graph/session model.

## Facts and eligibility; controller chooses strategy

Foundry should expose canonical facts and protected requirements, not commands such as
"spawn reviewer model X now".

Useful query surfaces include:

~~~text
get_objective(...)
get_assignment(...)
get_candidate(...)
get_requirements(...)
get_eligible_work(...)
get_outstanding_decisions(...)
get_effect_status(...)
subscribe(...)
~~~

Example:

~~~text
Foundry facts:
  candidate cand_51 exists
  semantic review missing
  certification passed
  release not eligible

Cloudflare strategy:
  spawn semantic_reviewer

AX strategy:
  reconcile a reviewer task

Pi strategy:
  invoke reviewer subagent

human:
  perform review manually
~~~

All four operate on the same protected facts.

## Push + pull, not model polling

Controller integration should support both pull/query and push/subscription.

Do not repeatedly invoke an LLM merely to ask whether workers are done. A deterministic
adapter/controller can wait on:

~~~text
review_completed
candidate_registered
effect_settled
deadline_reached
operator_decision
capability_revoked
execution_terminated
~~~

and invoke a model only when the event creates actionable work.

The observation path should record orchestrator wake reason and whether a wake caused an
actionable state change so idle-polling cost remains measurable.

## Execution authority

Foundry does not need to own an orchestrator's internal event loop, but it should control
the authority to begin an admitted execution.

~~~text
Foundry
  |
  | issue ExecutionGrant
  v
OrchestratorAdapter
  |
  | compile into controller/runtime config
  v
Cloudflare / AX / Pi / Claude / Codex
  |
  v
agent execution
~~~

An **ExecutionGrant** is an integration representation of an already admitted assignment,
not a second authority system. It should bind enough protected identity to prevent the
controller from broadening the execution:

~~~text
objective / workflow revision
assignment / principal
capability generation
execution profile
project/resource scope
budget/reservation owner
evidence obligations
expiry/revocation generation
~~~

The controller may narrow the grant further. It cannot enlarge it.

## Internal subagents versus durable handoffs

Not every child agent, tool call or parallel helper requires a new Foundry assignment.

A controller may spawn internal helpers **inside one admitted execution** when the parent
retains durable responsibility and every helper stays inside the same effective capability,
budget, isolation and evidence ceiling. Their activity is execution/observation state.

A new Foundry assignment is required when the workflow creates a new durable responsibility
or authority boundary, for example:

- capability or writable/readable scope differs materially;
- a new budget/reservation owner is needed;
- reviewer/checker independence must be established;
- the child may produce a separately accepted candidate or consequential effect;
- responsibility survives or transfers beyond the parent execution;
- the work is an escalation that the parent's grant cannot cover.

This preserves cheap subagent-as-tool patterns without letting a controller manufacture
independence or broaden authority merely by spawning another model/session.

## Resource authority

External resources are independent of where the agent runs.

~~~text
ExecutionGrant
      |
      v
agent / tool
      |
      | scoped resource capability
      v
ResourceAdapter
      |
      v
GitHub / Loka Builder API / Google / Slack / ...
~~~

Provider credentials remain outside the untrusted execution. A Gatekeeper-like adapter can
stage or simulate provider actions, but any action that matters to Foundry must map to the
canonical Foundry effect identity and authority generation.

A Cloudflare action journal is therefore staging/resource-local delivery state, not a
second Foundry effect ledger.

## Consequential effect protocol

The controller may decide that an effect is useful. It cannot unilaterally authorize it.

~~~text
controller proposes
      |
      v
prepare_effect(execution, operation, resource, payload_digest)
      |
      v
Foundry verifies grant / policy / budget / prerequisites / duplicates
      |
      v
claim + issue exact bounded operation
      |
      v
ResourceAdapter dispatch
      |
      +--> exact receipt
      +--> known non-start/failure
      +--> outcome unknown
~~~

Unknown remains unknown until reconciliation evidence resolves it. A timeout is not
permission for the orchestrator to invent another effect ID and retry the same semantic
operation.

## Candidate and completion semantics

Controller completion and Foundry completion are intentionally different.

~~~text
agent says "done"
        !=
controller job exited successfully
        !=
candidate registered
        !=
required evidence complete
        !=
candidate accepted
        !=
candidate promoted
~~~

A controller should register an exact artifact/candidate with immutable source identity.
Foundry then evaluates the applicable acceptance profile against exact check/review
receipts and protected policy.

## Observability and correlation

All adapters should emit into one canonical observation vocabulary while preserving the
source system's native identity and uncertainty.

The durable correlation chain should support:

~~~text
project
  -> workflow revision
  -> objective
  -> ticket/work item
  -> attempt
  -> assignment
  -> execution
  -> request/tool/effect
  -> candidate
  -> review/check
  -> accepted outcome
~~~

Not every workload needs every node, but adapters must not collapse identities that have
different lifetimes or authority.

A common observation envelope should carry, where applicable:

~~~text
schema_version
source_kind
source_version
quality
recorded_at
project_id
workflow_revision_id
objective_id
ticket/work_item_id
attempt_id
assignment_id
execution_id

optional:
request_id
tool_call_id
effect_id
candidate_id
review_id
check_id
trace/span context
~~~

Provider-native controller/session/job IDs remain attributes or evidence, not replacement
Foundry IDs.

## OpenTelemetry position

OpenTelemetry is an appropriate interoperability and analysis sink for traces, metrics and
logs from heterogeneous orchestrators.

It is not the authority ledger.

~~~text
Cloudflare observations --+
AX observations ----------+
Pi observations ----------+--> canonical Foundry observation seam
Claude/Codex observations-+                |
tool/model/runtime data ---+                +--> durable local analytics
                                            +--> OpenTelemetry export
                                            +--> dashboards / analysis
~~~

Foundry should preserve a local durable provenance-qualified dataset even when an external
OTel backend samples or expires traces.

## Controller-neutral measurements

This architecture makes Foundry a neutral evaluator of orchestration strategies.

Hold protected policy and task class constant, then compare:

~~~text
accepted outcomes / operator hour
tokens / accepted outcome
cash/subscription/infrastructure cost / accepted outcome
first-pass acceptance
correction/review tax
wall-clock / accepted outcome
idle orchestration wakeups
context/tool-result tax
unknown-effect/recovery burden
human steering/recovery effort
defect escape rate under the same acceptance profile
~~~

A controller with lower token use but more rejected candidates or operator recovery is not
better. The benchmark unit is trustworthy accepted delivery, not task count, agent count
or raw controller throughput.

## Cloudflare OS mapping

Cloudflare OS is a strong candidate external controller/product shell because it already
provides agent spawning, callable agents, Gadgets/Blueprints, durable workspace state,
scheduling/hooks, Gatekeepers, scoped bindings and multiple execution classes.

~~~text
Foundry authoritative facts
        |
        v
Cloudflare OrchestratorAdapter
        |
        +-- spawn PM/builder/reviewer agents
        +-- select Dynamic Worker/Sandbox class
        +-- install only issued resource bindings
        +-- wait on events/schedules
        +-- stream observations
        |
        v
Cloudflare OS
~~~

Cloudflare may decide workflow topology. Foundry still owns assignment/grant,
budget/effect authority, exact candidate/evidence identity, independence, acceptance and
promotion.

Do not require every internal Gadget/agent action to call Foundry. Require Foundry at the
boundaries where authoritative facts or consequential effects change.

## Loka mapping

Loka is a strong portability test because its Builder API already creates a natural
capability boundary.

~~~text
Foundry RoleSpec: world_builder
        |
        | admitted CapabilityGrant
        v
Cloudflare spawner environment
        |
        +-- LOKA_BUILDER(workspace=X, L3-L6)
        +-- CARTRIDGE_LAB(workspace=X)
        X  engine source
        X  arbitrary shell
        X  publish
~~~

If the builder discovers a missing L2 semantic capability, the controller can propose a
new work item or assignment. Foundry decides whether a separate
engine_capability_developer assignment is admitted. The builder cannot upgrade its own
grant.

A semantic reviewer receives the exact candidate plus read/simulation/certification
surfaces and no candidate mutation capability. Release receives only the exact certified,
accepted artifact and protected promotion route.

## Default Foundry workflow kernel remains useful

Making orchestrators replaceable does not require deleting the current workflow kernel.

~~~text
Foundry protected authority
          |
          +-- default Foundry workflow kernel
          +-- Cloudflare controller adapter
          +-- AX controller adapter
          +-- future experimental controllers
~~~

The default kernel provides a dependable reference workflow and local fallback. External
controllers can be compared against it using the same authority/evidence/acceptance
semantics.

Over time, if an external controller consistently provides better planning/orchestration,
Foundry can delete overlapping planning machinery without giving up the protected contract.

## Failure and restart behavior

An adapter/controller restart must not force Foundry to guess.

At reconnect, reconcile:

~~~text
known controller jobs/sessions
known Foundry executions
issued but unsettled effects
candidate/artifact outputs
outstanding callbacks/subscriptions
controller-side cancellations
~~~

Rules:

- Foundry durable facts remain canonical.
- Controller jobs absent after restart are not automatically failed if outcome is unknown.
- Controller-reported success is evidence until the corresponding Foundry fact is verified.
- Stale controller generations cannot continue to issue new work after revocation/takeover.
- Duplicate delivery uses stable command/effect identities and returns prior durable results.
- Unknown consequential effects are reconciled before unsafe retry.

## Conformance suite for an OrchestratorAdapter

A controller is not integrated merely because it can launch an agent. A reusable
conformance suite should prove at least:

1. it cannot mint or broaden a CapabilityGrant;
2. it cannot start protected execution after grant revocation;
3. duplicate command delivery does not create duplicate assignments/effects;
4. a stale controller generation cannot commit after takeover;
5. controller completed does not mint Foundry acceptance;
6. candidate identity is exact and immutable across review/check binding;
7. reviewer independence cannot be asserted by relabeling the same authority lineage;
8. cancellation blocks new descendant productive effects after the protected cutoff;
9. issued unknown effects are not silently retried;
10. restart/reconnect reconciles controller jobs without false success/failure;
11. observations preserve source/version/quality and unknown values;
12. telemetry cannot satisfy a protected receipt predicate by itself;
13. subscriptions wake on meaningful state changes without requiring model busy-polling;
14. controller-native IDs remain mapped to, not substituted for, Foundry identities;
15. adapter upgrades are pinned and must re-pass conformance before protected use.

## Candidate semantic API vocabulary

Do not freeze an exact RPC schema here; the accepted workflow contract owns current
implementation semantics. For post-repair controller portability, keep the protected
vocabulary small and semantic.

~~~text
OBJECTIVES
  propose / revise / cancel / inspect

ASSIGNMENTS
  propose / admit / claim / settle / escalate / inspect

EXECUTIONS
  issue / start / terminate / reconcile / inspect

ARTIFACTS
  register / derive / inspect

EVIDENCE
  register review / register check / register provenance / inspect

EFFECTS
  prepare / claim / issue / settle / reconcile / inspect

ACCEPTANCE
  evaluate / inspect

PROMOTION
  integrate / publish / deploy / activate / rollback

QUERY / EVENT
  facts / requirements / eligible_work / outstanding_decisions / subscribe

OBSERVATION
  emit batch / checkpoint source cursor
~~~

Some commands above may collapse into the existing transaction protocol; some may be
queries or controller conveniences rather than protected mutations. The design constraint
is more important than endpoint count: no controller-specific workflow graph belongs in
the verifier API.

## Migration sequence

Do not interrupt the active repair to implement this abstraction.

### O0 — extract semantics

- inventory current workflow-kernel calls that actually cross protected authority;
- classify each as protected fact, evidence or telemetry;
- identify software-specific orchestration decisions that need not be protected;
- preserve current behavior.

### O1 — local reference adapter

- implement an OrchestratorAdapter for the default Foundry workflow kernel;
- make the CLI use the same semantic client library where practical;
- prove no authority changed.

### O2 — observation convergence

- complete the canonical observation seam described in OBSERVABILITY;
- add adapter/source identity and event-driven wait/wake observations;
- preserve durable local analytics plus optional OpenTelemetry export.

### O3 — second controller experiment

Use a bounded materially different controller, preferably a small Cloudflare OS or Loka
workflow:

~~~text
objective
 -> world_builder
 -> semantic_reviewer
 -> certification
~~~

Keep acceptance/promotion in Foundry and compare against the reference controller.

### O4 — delete duplicate orchestration

Only after conformance and useful workload evidence should Foundry remove planning,
scheduling or coordination code that an external controller can satisfy better.

## Non-goals

This direction does not authorize:

- rewriting the accepted FR-06/FR-08 authority contract during the current repair;
- exposing the protected store directly to controllers;
- replacing idempotent semantic commands with a generic advance operation;
- treating OpenTelemetry as authority;
- treating controller completion as task acceptance;
- giving controller workers reusable root credentials;
- making Cloudflare OS, AX, Pi or any other controller mandatory infrastructure;
- creating a Turing-complete protected workflow DSL;
- giving repository-controlled workflow configuration permission to grant itself power;
- requiring Foundry to proxy every read, model token or local computation synchronously.

## Resulting principle

> **Foundry is the authority/evidence/acceptance plane. Orchestrators are replaceable
> controllers over its canonical facts. Foundry synchronously governs authority-changing
> transitions and consequential effects, while high-volume execution activity flows through
> a separate non-authoritative observation path. The CLI, default workflow kernel,
> Cloudflare OS, AX, Pi and future controllers should all consume the same protected
> semantics rather than becoming competing sources of truth.**

This makes Foundry both a dependable governance kernel and a neutral laboratory for
comparing orchestration strategies without moving the goalposts that define trustworthy
completion.
