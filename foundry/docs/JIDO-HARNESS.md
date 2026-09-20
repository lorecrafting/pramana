# Jido / Jido.Harness evaluation for Foundry

**Checked:** 2026-09-20. **Status:** substitution research only. This document does
not adopt Jido, Jido.Harness, ACP, ExMCP, Jido.VFS, Jido.Workspace or any provider
adapter; it does not replace the active repair plan, workflow contract, FR-09/15a
isolation/billing requirements or the existing production fail-closed posture.

[Foundry strategy](STRATEGY.md) · [Pi harness design](PI-HARNESS.md) ·
[Observability](OBSERVABILITY.md) · [Research register](../../docs/strategy/RESEARCH.md)

## Decision summary

Jido core is useful primarily as an architectural reference. Its agent-as-data,
command/directive separation, process-state-versus-agent-state distinction and testing
style reinforce Foundry's existing direction, but Jido's AgentServer is not a replacement
for Foundry's authority/evidence kernel and BEAM process isolation is not Foundry's OS
security boundary.

Jido.Harness is materially more relevant. At the pinned source checked below it is a
supervised Elixir runtime that normalizes Amp, Claude Code, Codex, Gemini CLI, Grok,
Kimi Code, OpenCode, Pi and Z.AI behind stable run/session/process identities and a
provider-neutral API. It uses ACP through ExMCP for coding-agent messages, owns local
process lifecycle, replay journals, timeouts, process-group cancellation and normalized
capability/event/result types, and intentionally does not claim to be a durable job
system, provider router, workspace provisioner or retry engine.

Foundry should therefore compare **two Pi integration candidates** before writing a
production bridge:

1. direct pinned Pi RPC behind Foundry's harness-neutral contract; and
2. pinned Jido.Harness/ACP with Pi's ACP adapter behind the same Foundry contract.

The result should be chosen by conformance evidence, not by feature count. Jido.Harness
wins only if its portability and lifecycle implementation reduce Foundry maintenance
without weakening exact identity, lifecycle, billing, isolation, observability or
unknown-outcome semantics.

## Boundary map

A useful target composition is:

```text
models / coding agents
        |
        +-- Pi
        +-- Claude Code
        +-- Codex
        +-- Gemini / others
        |
   optional Jido.Harness
        |
   normalized ACP lifecycle
        |
        v
Foundry harness-neutral execution contract
        |
        +-- identity correlation
        +-- capability/billing admission
        +-- budget/effect ownership
        +-- evidence/acceptance/reconciliation
        |
        v
isolated execution / typed project services
```

Jido.Harness must remain below Foundry's authority boundary. A normalized
`RunResult.status == :completed` is an execution observation; it is not candidate
acceptance, reviewer independence, integration authorization or deployment permission.

## Findings worth adopting conceptually

### Agent state is data; effects are explicit

Jido's core model separates immutable agent state transitions from directives that the
runtime later executes. Foundry already needs the stronger form of the same pattern:

```text
transition(authoritative_state, authenticated_command)
  -> {new_state, admitted_effect_intents}
```

Consequential Foundry effects then pass through reservation/claim/issue/settlement or
reconciliation. This is stronger than a generic "directive means execute" contract, but
the explicit transition/effect split is worth preserving because it keeps protected
domain logic deterministic and easy to adversarially test.

### Process lifecycle is not semantic completion

Jido explicitly distinguishes process lifecycle from agent completion. Foundry should
retain the stronger hierarchy:

```text
worker alive
  != execution productive
  != assignment complete
  != candidate valid
  != candidate accepted
```

No terminal pane, child process, ACP terminal event or harness `:completed` value may
skip those semantic boundaries.

### Normalization should not fabricate parity

Jido.Harness's normalization rule is particularly compatible with Foundry: common
semantics receive stable types, provider-specific information remains provider-specific,
and unsupported capabilities are declared/rejected rather than silently invented.

Foundry should preserve the same rule for harness telemetry and capabilities. Missing
token counts, provider session IDs, cancellation guarantees, sandbox modes, cache values
or cost must remain explicitly unavailable/unknown. A common adapter type must not turn
weak provider evidence into strong evidence.

### Conversation continuity is not workflow authority

Jido.Harness provides stable run/session/turn identities and provider session IDs.
Foundry should correlate those to an already admitted execution identity, never derive
the latter from the former. Session replay, continuation, compaction or provider resume
cannot rewind budgets, effects, candidate identity or accepted evidence.

### Thread/history and working memory should remain different classes of data

Jido's ecosystem distinguishes append-oriented history from mutable working memory.
Foundry should keep the same conceptual separation:

- authoritative/evidentiary history: commands, effects, receipts, candidate/review
  identities and accepted protected facts;
- derived working state: context summaries, retrieval results, learned hints,
  optimization hypotheses and model/session state.

The second class may be recomputed, compacted or discarded without rewriting the first.

### Standard Erlang telemetry is a good runtime seam

Jido emits ordinary Erlang `:telemetry` events and can bridge them to
OpenTelemetry-style tracing/metrics. Foundry should similarly make a single normalized
runtime observation emitter the fan-out point for durable local analytics and optional
OpenTelemetry export. Observability remains evidence/diagnostics, not authority.

## Jido.Harness capabilities relevant to Foundry

At commit `07870f722cbb6aa19a556b232f34528a821b98e8`, the Jido.Harness README
documents:

- caller-independent supervised runs and sessions;
- stable run/session/turn/process IDs;
- blocking and detached execution;
- streaming, bounded replay journals, reattachment and pruning;
- multi-turn ACP sessions;
- executable/argv process ownership, stdin/PTY/timeouts;
- process-group cancellation and retained output;
- explicit provider capabilities and readiness checks;
- normalized events, results, errors and usage;
- reusable deterministic/live integration contracts.

Runs survive caller and stream-consumer death but intentionally do **not** survive a BEAM
or host restart. This is acceptable only if Foundry owns durable execution intent and
reconciliation above the harness.

Jido.Harness currently uses ACP through ExMCP for all coding-agent messages. Native ACP
CLIs and ACP adapter programs share the Harness lifecycle path. Harness retains its own
run/turn IDs, replay journals, retention, process groups, signal escalation, output
streaming and cleanup while ExMCP owns ACP parsing/validation and JSON-RPC request
correlation.

For Pi this introduces an additional adapter/protocol boundary compared with direct
`pi --mode rpc`. Portability is therefore a hypothesis to measure against added
dependency/protocol/supply-chain complexity.

## Reasons not to adopt it blindly

### The current release line is still moving

The checked Jido.Harness README says the version 3 candidate is installed from Git and
is not yet published on Hex; the planned first Hex release is `3.0.0-rc.1`. Pin an exact
commit for any experiment and treat upgrades as conformance events.

### The extra protocol path can lose provider-native information

The ACP/ExMCP boundary intentionally normalizes messages. For adapter-backed providers,
Harness can only retain what the adapter maps into ACP. Foundry must prove that
provider-native fields required for billing, usage, tool identity, cancellation or
reconciliation are available with adequate source/quality labels. Do not assume
`Event.raw` is the original provider-native event.

### Harness durability is deliberately process-local

A BEAM/host restart destroys Harness runs/sessions. Foundry therefore still needs durable
start intent, execution identity, provider/effect claims and reconciliation. The harness
cannot become the workflow ledger.

### Process supervision is not sandboxing

Jido.Harness can own process groups and cleanup, which is useful lifecycle machinery, but
BEAM/process ownership is not filesystem, credential, network, syscall or host isolation.
FR-09/15a remains responsible for proving the entire executable route.

### Generic retries are not Foundry effect semantics

Jido and general agent frameworks may offer ordinary retry/backoff patterns. Foundry must
not apply generic retry to consequential external effects when a timeout can mean either
"failed" or "succeeded but acknowledgment was lost." Such effects remain
reservation/claim/issue/reconcile operations under the protected kernel.

## Direct Pi RPC versus Jido.Harness/ACP evaluation

Both candidates should implement the same small Foundry-facing interface:

- start;
- observe/stream/replay;
- prompt/follow-up;
- interrupt/cancel;
- reconcile;
- close;
- source-qualified usage/capabilities.

Evaluate at an exact pinned revision using the same scenarios:

| Dimension | Direct Pi RPC | Jido.Harness/ACP question |
|---|---|---|
| Protocol surface | Pi JSONL directly | Does ACP normalization preserve every required semantic? |
| Provider portability | Pi only | Is multi-provider support actually useful without weakening policy? |
| Lifecycle | Foundry must implement bridge details | Do Harness IDs/journals/cancellation remove custom code safely? |
| Crash/restart | Foundry-owned | Can Foundry reconcile cleanly after Harness state disappears? |
| Cancellation | Pi-specific behavior | Do queued input, session cancel and process-group cleanup match required semantics? |
| Usage | Pi session statistics | Are token/cache/cost/context values preserved with source/quality? |
| Billing | Must prove admitted route | Does the adapter/ACP path add any unobserved provider/auth route? |
| Isolation | Must inventory Pi/extensions/tools | Does Harness introduce executable helpers/config/environment outside the admitted boundary? |
| Supply chain | Pi + bridge | Jido.Harness + ExMCP + ACP adapter + Pi; is the maintenance trade worth it? |
| Upgrades | Pin Pi/protocol | Pin every involved revision and rerun conformance |

Do not fund two long-lived production adapters. Run the bounded comparison, choose one,
and keep the Foundry-facing contract harness-neutral.

## Conformance suite lesson

Jido.Harness's testing taxonomy is worth copying even if the dependency is rejected.
Foundry's execution-backend conformance should include at least:

1. deterministic fake/protocol fixture;
2. non-billable readiness and exact-version check;
3. lifecycle and event-order contract;
4. terminal uniqueness and duplicate delivery;
5. caller/consumer death;
6. cancellation, escalation and complete descendant cleanup;
7. replay cursor gaps/truncation;
8. lost acknowledgement and reconnect/reconcile;
9. queued follow-up/session replacement;
10. usage/source-quality settlement;
11. provider/billing-route proof;
12. isolation/credential/egress proof;
13. long deterministic soak;
14. bounded authorized live-provider smoke.

The same suite should be reusable for direct Pi, Jido.Harness and future harness
candidates where the capability applies.

## Other Jido ecosystem components

- **Jido.Agent/AgentServer:** useful architecture/testing reference; do not make it the
  Foundry authority coordinator.
- **Jido Signals / CloudEvents-style envelopes:** potentially useful for external
  integration transport, but a received signal is never itself an authoritative Foundry
  command/fact.
- **Jido.VFS / Jido.Workspace:** worth benchmarking as convenience abstractions, never as
  a sandbox or protected Git custody boundary.
- **Jido Runic/DAG/workflow machinery:** avoid as a competing protected workflow
  authority unless a future bounded substitution evaluation proves a specific missing
  capability.
- **Jido AI reasoning layers:** optional intelligence components only; they cannot mint
  authority or acceptance.

## Adoption gate

No Jido component enters the production authority path because this document exists.
A Jido.Harness candidate may advance only after:

1. exact dependency revisions and licenses are recorded;
2. the direct-Pi and Jido.Harness paths run against the same Foundry conformance fixture;
3. ACP/provider capability loss is explicitly inventoried;
4. provider/billing and executable-route inventory passes FR-09/15a requirements;
5. cancellation/restart/reconciliation behavior is proven;
6. usage/observability mapping preserves unknowns and provenance;
7. maintenance/operator benefit is measured;
8. the owning workflow-contract text is revised and independently reviewed if the
   selected implementation changes any governing assumption.

## Checked sources

- Jido.Harness README at
  https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/README.md
- Jido.Harness normalization/data model at
  https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/guides/normalization_and_data_model.md
- Jido.Harness testing guide at
  https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/guides/testing.md
- Jido.Harness ExMCP/ACP decision at
  https://github.com/agentjido/jido_harness/blob/07870f722cbb6aa19a556b232f34528a821b98e8/docs/decisions/exmcp-acp-boundary.md
- Agent Client Protocol overview at https://agentclientprotocol.com/
- Jido documentation at https://jido.run/
