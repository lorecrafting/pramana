# Project workflow profiles — post-repair design direction

**Status:** strategy/design guidance for the post-repair Foundry direction. It does not
change the active repair plan, workflow contract, launch policy, provider entitlement,
or current runtime behavior.

[Foundry strategy](STRATEGY.md) · [Workflow contract](WORKFLOW-CONTRACT.md) ·
[Validation](../../docs/strategy/VALIDATION.md)

## 1. Purpose

Foundry should be **workflow- and role-agnostic without being authority-agnostic**.

The protected kernel should not permanently encode "software developer → reviewer" as
the only shape of useful work. A project should be able to describe materially different
roles and workflows, while the kernel continues to enforce the same durable properties:

- authenticated/admitted intent;
- bounded capability grants;
- exact project/workflow/assignment identity;
- budget and external-effect accounting;
- isolation requirements appropriate to the granted tools;
- immutable candidate/evidence identity;
- review-independence rules;
- mandatory checks and acceptance predicates;
- idempotency/reconciliation for uncertain effects;
- integration/publication/activation authority;
- recovery and replay.

A project definition may **request** power. It never mints power.

## 2. Separate role meaning from authority

A role name is descriptive workflow vocabulary, not a security principal by itself.

Examples:

- `developer`;
- `reviewer`;
- `researcher`;
- `translator`;
- `mud_world_builder`;
- `quest_builder`;
- `engine_capability_developer`;
- `semantic_reviewer`;
- `release_operator`.

Foundry should care about the admitted contract behind the name:

```text
RoleSpec
  identity / purpose
  allowed workflow phases
  context policy
  capability requests
  writable scope
  readable scope
  execution profile request
  evidence obligations
  handoff/result schema
  escalation targets
  independence requirements
```

A RoleSpec may request an independence requirement; it cannot assert that the requirement
has been satisfied. Protected policy evaluates durable principal/authority/candidate
lineage (and any additional configured separation requirements).

Two assignments with different labels but the same principal/candidate lineage are not
automatically independent. Conversely, the same underlying model may be usable in
different roles when policy permits, but it receives the exact capabilities of each
assignment rather than ambient model-wide authority.

## 3. ProjectProfile

A versioned **ProjectProfile** tells Foundry how a project exposes safe work.

Conceptual shape:

```yaml
project: loka
revision: 7

surfaces:
  builder_api:
    kind: typed_api
  cartridge_lab:
    kind: typed_api
  engine_checkout:
    kind: isolated_workspace
  git:
    kind: protected_integration

roles:
  world_builder: ...
  engine_capability_developer: ...
  semantic_reviewer: ...

acceptance_profiles:
  story_cartridge: ...
  engine_change: ...
```

A ProjectProfile may define:

- project/source identity and routing;
- available typed APIs/tool surfaces;
- allowed execution profiles;
- role specifications;
- workflow templates/combinators;
- check/evidence adapters;
- acceptance profiles;
- protected publication/integration routes;
- context-routing rules;
- escalation classes.

It is itself versioned, reviewed policy input. The active ProjectProfile/policy revision
must be controller/protected-policy-custodied (or equivalently authenticated) and pinned
into admitted assignment identity. A candidate-controlled checkout may contain a proposed
profile change, but cannot silently rewrite the active ProjectProfile governing its own
assignment.

## 4. Capability grants, not ambient toolboxes

### Registered tool surfaces, not project-installed controller code

A ProjectProfile may reference/request tool or API surfaces that the protected system knows
how to admit. It does not get to install arbitrary executable code into the controller/
verifier simply by declaring a new tool kind.

A new controller-side adapter/plugin requires its own reviewed Foundry change and
conformance. A project-specific executable tool may instead run as an isolated worker or
external typed service under an admitted interface, but its outputs remain untrusted until
the governing receipt/evidence contract verifies them.

This keeps "project-configurable tools" from becoming a plugin-shaped authority escape
hatch.



A RoleSpec requests specific capabilities. Foundry admits an exact
**CapabilityGrant** that is a subset of project/operator policy.

Examples:

```text
builder.workspace.read
builder.content.write(kind = [room,npc,quest,scene])
builder.lab.run
builder.certification.read

git.diff.read
git.commit.candidate

shell.exec(approved_environment)
network.fetch(allowlisted)
provider.model_request(profile = ...)
```

A capability grant should bind, where relevant:

- project/workflow/assignment/principal;
- exact workspace/resource namespace;
- exact ProjectProfile, RoleSpec, WorkflowPlan and protected-policy revision/digest;
- operation family;
- read/write classification;
- object/path/content-kind scope;
- data classification/redaction constraints for readable context/results;
- exact API/schema version;
- resource/time/budget ceiling;
- execution/sandbox profile;
- expiry/generation;
- evidence/receipt requirements.

"Has shell" or "is developer" is too coarse to be the long-term authority model.

## 5. Typed-API roles versus arbitrary-code roles

Not every productive agent needs the same sandbox.

A role limited to a narrow, validated typed API can receive high semantic power without
receiving a shell or repository write access.

A role that can execute candidate-controlled code, build hooks, compilers or arbitrary
shell commands requires the stronger worker isolation contract described in
[STRATEGY](STRATEGY.md).

This distinction is central to the Loka example:

```text
MUD/world builder
  -> Loka Builder API
  -> Cartridge Lab
  -> content workspace only
  X  no engine source write
  X  no arbitrary shell
  X  no publication authority

engine capability developer
  -> isolated engine checkout
  -> approved shell/build/test tools
  -> L2 capability implementation scope
  X  no self-review acceptance
  X  no release authority
```

The world builder may be *more expressive inside the game-authoring domain* than a
generic source-code developer while still having dramatically less host authority.



## 5.1 Enforcement is outside the role prompt

Role instructions are useful context, but they are not an authority boundary.

A role is actually constrained only when every effectful operation crosses an enforcement
point that verifies the admitted CapabilityGrant.

Therefore:

- hiding a tool from the model UI is not sufficient if another reachable tool can perform
  the same operation;
- telling a builder "do not edit engine code" is not sufficient if its OS principal can
  write the engine checkout;
- a typed API must authenticate/identify the assignment and enforce operation/object scope
  server-side;
- a shell-capable role must run under the admitted sandbox/workspace/filesystem/network
  policy rather than relying on path conventions;
- publication/integration credentials remain outside ordinary candidate-controlled
  execution;
- capability denial is logged as evidence and cannot be converted into success by a
  model response.

The protected verifier's existing **role/profile/operation/scope** check is the substrate
to generalize; ProjectProfile/RoleSpec should compile into requests checked by that
authority rather than create a second authorization system.

### Gateway scope comes from the admitted assignment, not caller claims

A typed project API must not trust a caller-supplied role name, path prefix, project ID,
or "requested scope" as authorization.

The gateway derives the maximum permitted operation/resource scope from the authenticated
assignment/principal and pinned CapabilityGrant, then validates the concrete request
inside that scope.

This prevents confused-deputy shapes such as:

- builder calls a generic `content.write` operation while naming an engine path;
- child/subagent reuses a parent API credential but supplies a broader role string;
- an engine-capable service is asked to operate on another project/workspace ID;
- caller chooses a stale/broader ProjectProfile revision in the request.

Where practical, model-controlled workers should receive mediated handles rather than
reusable bearer credentials for broad project APIs.

### Grant revision, revocation and policy change

A later ProjectProfile or operator-policy revision does not silently enlarge an already
admitted assignment.

Rules:

- broadening policy requires a new admission/grant before the assignment can use the new
  authority;
- narrowing/revocation uses a protected generation/revocation mechanism checked at the
  effect gateway;
- already-issued external effects/holds are reconciled under the governing workflow
  contract rather than forgotten;
- stale grants fail closed for new effects once revoked;
- replay/audit retains the policy/grant revision that governed each acknowledged action.

A project cannot "update its profile" in candidate content and thereby upgrade a running
agent.

### Deny by capability, not by omission

The long-term design should prefer positive grants:

~~~text
allowed:
  builder.content.write quest/*
  builder.lab.run cartridge/*
  builder.capability.read *

everything else:
  denied
~~~

over giant negative lists such as "can do everything except engine, release, credentials,
database, network...".

The exact representation may differ, but absence of a grant must fail closed.

## 6. Loka's layered world model as a portability test

Loka's proposed world architecture provides a useful materially-different workflow test:

```text
L6  cartridges/campaigns/deployments
L5  quests/scenes/world-event orchestration
L4  domain composites
L3  composition grammar
L2  engine semantic capabilities
L1  world-model contracts
L0  authority/transaction substrate
```

Possible project roles:

### `world_builder`

Normal write authority: **L3–L6** through the typed Builder API.

May:

- create/update authored world content;
- configure registered capabilities;
- create ActionRecipes/ReactionRules/Behaviors;
- build quests/scenes/population/commerce/service compositions;
- run Lab simulations and certification preflights;
- inspect diagnostics and exact diffs.

May not:

- modify L0–L2 implementation;
- call arbitrary persistence;
- add engine bindings;
- weaken certification;
- publish a release.

### `quest_builder`

Narrower L3–L6 role.

May mutate quest/dialogue/scene/storyline/fact/reaction content plus referenced
world-authoring surfaces explicitly granted to the assignment.

It does not gain general world or engine write access merely because a quest needs a new
mechanic.

### `engine_capability_developer`

May change approved L2 capability implementation/schema/tests in an isolated software
workspace under ordinary source-code evidence gates.

Any L0/L1 architecture change requires a separately admitted higher-risk scope.

### `semantic_reviewer`

Read/simulate/evaluate only.

Receives exact candidate artifact, traces, branch comparisons, diagnostics, relevant
source context and rubric. Cannot mutate candidate or certify its own changes.

### `release_agent`

May stage/promote only the exact artifact/hash for which all protected certificate
predicates already hold. It cannot author content or waive a failed gate.

These names are project vocabulary, not new Foundry kernel primitives.

## 7. Escalation instead of privilege growth

A role encountering missing semantics should return a typed **EscalationRequest** or
domain-specific proposal rather than acquiring new power.

Example:

```text
world_builder
  requests "NPC can forge an item only during a lunar eclipse"

Builder API
  -> expressible from existing schedule/policy/service primitives?
       yes -> continue inside current grant
       no  -> MISSING_CAPABILITY

world_builder
  -> CapabilityProposal(
       requested semantics,
       evidence/examples,
       nearest primitives,
       portability need,
       candidate invariants/tests
     )

Foundry
  -> protected workflow decides whether to admit separate
     engine_capability_developer work
```

The original builder assignment remains bounded.

An escalation can therefore:

- propose a new task;
- request a new separately admitted role assignment;
- request operator decision;
- request additional context;
- request a narrower approved capability.

It cannot amend its own CapabilityGrant.

## 8. Assignment results are typed, not role-name callbacks

Long-term protected workflow state should not need branches such as:

~~~text
if role == developer -> receive_handoff
if role == reviewer  -> receive_review
~~~

A generic **AssignmentResult** envelope can carry a schema-declared result kind such as:

- candidate artifact/proposal;
- finding/review set;
- evidence/check result;
- planning/decomposition proposal;
- escalation request;
- operator-decision request;
- no-change/blocked/unsupported result.

Conceptually:

~~~text
AssignmentResult
  assignment_id
  principal_id
  role_spec_revision
  workflow_revision
  result_kind
  subject/candidate identity
  payload/artifact reference + digest
  evidence references
  outcome classification
~~~

The admitted WorkflowPlan declares which result kinds are valid at each node and what
protected transition may consume them.

A result never changes durable workflow state merely because its role/model says
"approved", "done", or "publish". The protected reducer verifies schema, identity,
candidate/evidence binding, capability/policy revision and transition predicate first.

Review independence is similarly a predicate over principal/authority/candidate lineage,
not an implication of `result_kind = review`.

The current `handoff` and `review` commands may remain adapters for the proven
software workflow. Post-repair generalization should translate them into the generic
assignment/result model rather than preserve developer/reviewer callbacks as the kernel
ontology.

## 9. WorkflowPlan should be declarative and small

Models may propose workflow topology, but the durable admitted plan should use a small
composable vocabulary rather than arbitrary orchestration code.

Candidate primitives:

- assignment;
- dependency;
- fork/join;
- check;
- review;
- correction;
- escalation;
- operator decision;
- integration/publication;
- rollback/recovery.

A project may supply templates such as:

```text
software_change:
  developer -> checks -> independent_reviewer -> integration

loka_content:
  world_builder -> static_checks -> simulations
  -> semantic_reviewer -> certification -> exact-hash release

missing_loka_capability:
  world_builder escalation
  -> engine_capability_developer
  -> engine checks/review
  -> capability release
  -> resume/rebase content candidate
  -> content certification
```

The protected kernel admits/pins the actual WorkflowPlan and may inject mandatory gates.
The planner cannot remove a required reviewer, certification profile or operator decision.

## 10. Context is part of the role contract

### Read authority and sensitive context

Read access is authority too.

A RoleSpec/CapabilityGrant must not expose protected credentials, provider tokens, signing
keys, unrelated private data, operator home contents, or another project's data merely
because the assignment is "read only."

Context/tool-result construction should:

- derive readable resources from the admitted grant;
- apply project/operator redaction/classification policy outside candidate control;
- keep reusable credentials in protected gateways rather than model context;
- prevent a typed API role from asking a generic read endpoint for another workspace;
- record provenance for sensitive evidence surfaced to reviewers;
- treat attempted secret access as a denied capability/evidence event.

A reviewer may need broader **read** access than an author to falsify claims, but that
broader read grant is explicit and still does not imply mutation/publication authority.



A role should receive the **minimum sufficient authoritative context**, not a giant
repository dump and not a context window chosen only for token savings.

Examples:

### Loka world builder context

- Builder API schema and permitted operations;
- relevant capability docs/examples;
- cartridge neighborhood and incoming/outgoing refs;
- current workspace diff;
- failing Lab/certification traces;
- L3–L6 composition guidance.

Normally omit engine source.

### Engine capability developer context

- capability semantic contract;
- exact affected engine modules/tests;
- compatibility constraints;
- generated-schema consequences;
- adversarial failure fixtures;
- relevant L0–L2 architecture rules.

### Reviewer context

- exact frozen candidate/hash;
- assignment contract and exclusions;
- mandatory check receipts;
- raw evidence needed for falsification;
- project conventions relevant to the changed surface.

A model/assessor may help rank optional context. Mandatory policy/spec/evidence context is
selected outside that model and cannot be dropped by it.

## 11. Evidence and acceptance are project-configurable, authority is not

Different workflows need different evidence:

Software might require:

- compile;
- formatter/lint;
- unit/property/integration tests;
- dependency/security checks;
- exact diff/source provenance;
- independent review.

Loka content might require:

- schema/reference validation;
- quest/path reachability;
- deterministic simulation;
- branch comparison;
- cross-host conformance;
- population/economy invariants;
- scene/recovery tests;
- semantic review;
- physical-device smoke;
- exact artifact certificate.

Foundry should consume versioned **EvidenceAdapters / AcceptanceProfiles** while keeping
the protected meaning of acceptance fixed: every mandatory predicate must be satisfied
by evidence bound to the exact candidate and governing policy revision.

A project-supplied check cannot report itself mandatory-pass by merely returning a string
"pass"; Foundry verifies the check runner/receipt according to its admitted evidence
contract.

Project-defined evidence adapters/check specifications are also authority-sensitive input:

- their exact definition/revision/digest is pinned into the admitted acceptance profile;
- candidate-controlled changes to a check definition do not alter the currently governing
  gate until separately reviewed/admitted;
- executable project checks run in the appropriate isolated check worker and receive only
  their required inputs/capabilities;
- controller-observed command/result/artifact identity becomes the receipt; candidate
  prose or exit-status-only self-report is insufficient;
- a changed mandatory check implementation invalidates evidence according to protected
  policy rather than silently reusing old receipts.

This prevents a candidate from "fixing the test" by replacing the checker with one that
always passes.

## 12. Jev and other semantic decision models

A fast typed decision model such as Jev may be useful for:

- choosing among already-authorized RoleSpecs;
- context relevance ranking;
- diagnostic triage;
- duplicate-finding classification;
- test/simulation prioritization;
- risk classification;
- deciding which stronger reviewer path should inspect an anomaly.

It should not decide:

- whether a capability is authorized;
- whether an assignment may expand scope;
- whether a reviewer is independent;
- whether an unknown effect is safe to repeat;
- whether mandatory evidence passed;
- whether an artifact is accepted/published.

The model outputs probabilistic advisory evidence. Protected code applies thresholds and
fallback/escalation policy.

## 13. Required portability proof

Do not generalize the live implementation from this document before the current repair
workflow is accepted.

Post-repair, a role/workflow generalization should prove at least two materially
different workloads:

1. a normal software change using isolated source-code developer/reviewer roles;
2. a typed-content workflow such as Loka where a world/quest builder has no engine-code
   write surface and missing semantics escalate to a separately authorized capability
   developer.

The proof should demonstrate:

- no hard-coded developer/reviewer lifecycle assumption in protected generic state;
- exact per-role capability grants;
- fail-closed denied operations;
- context routing by RoleSpec;
- mandatory project gates cannot be removed by the model/project plan;
- review independence survives renamed roles/models/sessions;
- child workflows cannot expand parent scope/budget;
- escalation does not alter the originating role's grant;
- interruption/replay/recovery remains correct;
- positive useful completion for both workflows.

Only then is "role-agnostic Foundry" an evidenced property rather than a strategy claim.
