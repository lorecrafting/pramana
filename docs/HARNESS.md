# Harness Engineering — Planning

Design and research material, not an execution queue. Foundry's own meta-harness (chapter 10) moved to lorecrafting/foundry.

[Documentation](README.md) · [Current architecture](ARCHITECTURE.md) · [Testing](TESTING.md)

## Chapters

- [1. Verifiers as the Moat: a Feedback Loop from Guard Verdicts](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md)
- [What is missing](harness/02-what-is-missing.md)
- [Acceptance](harness/03-acceptance.md)
- [10. Parallel Track: the Self-Improving Supervisor (Foundry's Own Meta-Harness), now in lorecrafting/foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md)
- [References](harness/05-references.md)

## Original topic links

These anchors preserve existing bookmarks. Follow the link to read the topic.

| Topic |
|---|
| <a id="harness-engineering--planning"></a>[Harness Engineering — Planning](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#harness-engineering--planning) |
| <a id="1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts"></a>[1. Verifiers as the Moat: a Feedback Loop from Guard Verdicts](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts) |
| <a id="what-exists"></a>[What exists](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-exists) |
| <a id="what-is-missing"></a>[What is missing](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-is-missing) |
| <a id="event-sourcing-design"></a>[Event-sourcing design](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#event-sourcing-design) |
| <a id="migration-path-from-current-code"></a>[Migration path from current code](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#migration-path-from-current-code) |
| <a id="what-ships-with-this"></a>[What ships with this](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-ships-with-this) |
| <a id="2-harness-self-optimization-meta-harness82032-pattern"></a>[2. Harness Self-Optimization (Meta-Harness&#8203;<!-- footnote -->^2 Pattern)](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#2-harness-self-optimization-meta-harness82032-pattern) |
| <a id="what-exists-1"></a>[What exists](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-exists-1) |
| <a id="what-is-missing-1"></a>[What is missing](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-is-missing-1) |
| <a id="event-sourcing-design-1"></a>[Event-sourcing design](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#event-sourcing-design-1) |
| <a id="migration-path"></a>[Migration path](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#migration-path) |
| <a id="acceptance"></a>[Acceptance](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#acceptance) |
| <a id="3-task-length-measurement"></a>[3. Task-Length Measurement](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#3-task-length-measurement) |
| <a id="what-exists-2"></a>[What exists](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-exists-2) |
| <a id="what-is-missing-2"></a>[What is missing](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-is-missing-2) |
| <a id="event-sourcing-design-2"></a>[Event-sourcing design](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#event-sourcing-design-2) |
| <a id="migration-path-1"></a>[Migration path](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#migration-path-1) |
| <a id="what-ships-with-this-1"></a>[What ships with this](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-ships-with-this-1) |
| <a id="4-multi-agent-retrieval-pipeline"></a>[4. Multi-Agent Retrieval Pipeline](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#4-multi-agent-retrieval-pipeline) |
| <a id="what-exists-3"></a>[What exists](harness/01-1-verifiers-as-the-moat-a-feedback-loop-from-guard-verdicts.md#what-exists-3) |
| <a id="what-is-missing-3"></a>[What is missing](harness/02-what-is-missing.md#what-is-missing) |
| <a id="event-sourcing-design-3"></a>[Event-sourcing design](harness/02-what-is-missing.md#event-sourcing-design) |
| <a id="migration-path-2"></a>[Migration path](harness/02-what-is-missing.md#migration-path) |
| <a id="what-ships-with-this-2"></a>[What ships with this](harness/02-what-is-missing.md#what-ships-with-this) |
| <a id="5-eval-harness-maturity"></a>[5. Eval Harness Maturity](harness/02-what-is-missing.md#5-eval-harness-maturity) |
| <a id="what-exists-4"></a>[What exists](harness/02-what-is-missing.md#what-exists) |
| <a id="what-is-missing-4"></a>[What is missing](harness/02-what-is-missing.md#what-is-missing-1) |
| <a id="event-sourcing-design-4"></a>[Event-sourcing design](harness/02-what-is-missing.md#event-sourcing-design-1) |
| <a id="migration-path-3"></a>[Migration path](harness/02-what-is-missing.md#migration-path-1) |
| <a id="what-ships-with-this-3"></a>[What ships with this](harness/02-what-is-missing.md#what-ships-with-this-1) |
| <a id="6-cross-canon-citation-reputation"></a>[6. Cross-Canon Citation Reputation](harness/02-what-is-missing.md#6-cross-canon-citation-reputation) |
| <a id="what-exists-5"></a>[What exists](harness/02-what-is-missing.md#what-exists-1) |
| <a id="what-is-missing-5"></a>[What is missing](harness/02-what-is-missing.md#what-is-missing-2) |
| <a id="event-sourcing-design-5"></a>[Event-sourcing design](harness/02-what-is-missing.md#event-sourcing-design-2) |
| <a id="migration-path-4"></a>[Migration path](harness/02-what-is-missing.md#migration-path-2) |
| <a id="acceptance-1"></a>[Acceptance](harness/02-what-is-missing.md#acceptance) |
| <a id="7-agentic-retrieval-orchestrating-the-tool-surface"></a>[7. Agentic Retrieval: Orchestrating the Tool Surface](harness/02-what-is-missing.md#7-agentic-retrieval-orchestrating-the-tool-surface) |
| <a id="what-exists-6"></a>[What exists](harness/02-what-is-missing.md#what-exists-2) |
| <a id="what-is-missing-6"></a>[What is missing](harness/02-what-is-missing.md#what-is-missing-3) |
| <a id="event-sourcing-design-6"></a>[Event-sourcing design](harness/02-what-is-missing.md#event-sourcing-design-3) |
| <a id="migration-path-5"></a>[Migration path](harness/02-what-is-missing.md#migration-path-3) |
| <a id="acceptance-2"></a>[Acceptance](harness/03-acceptance.md#acceptance) |
| <a id="8-implementation-order-after-event-sourcing"></a>[8. Implementation Order After Event Sourcing](harness/03-acceptance.md#8-implementation-order-after-event-sourcing) |
| <a id="9-beyond-minimal-the-meta-harness-progression"></a>[9. Beyond Minimal: the Meta-Harness Progression](harness/03-acceptance.md#9-beyond-minimal-the-meta-harness-progression) |
| <a id="tier-l1--parameter-search-minimal-meta-harness"></a>[Tier L1 — Parameter Search (minimal meta-harness)](harness/03-acceptance.md#tier-l1--parameter-search-minimal-meta-harness) |
| <a id="tier-l2--prompt--tool-description-evolution"></a>[Tier L2 — Prompt & Tool-Description Evolution](harness/03-acceptance.md#tier-l2--prompt--tool-description-evolution) |
| <a id="tier-l3--skill--retrieval-plan-composition"></a>[Tier L3 — Skill & Retrieval-Plan Composition](harness/03-acceptance.md#tier-l3--skill--retrieval-plan-composition) |
| <a id="tier-l4--architectural-search-full-meta-harness"></a>[Tier L4 — Architectural Search (full meta-harness)](harness/03-acceptance.md#tier-l4--architectural-search-full-meta-harness) |
| <a id="tier-l5--continual-adaptation-online-learning"></a>[Tier L5 — Continual Adaptation (Online Learning)](harness/03-acceptance.md#tier-l5--continual-adaptation-online-learning) |
| <a id="tier-l6--meta-meta-harness"></a>[Tier L6 — Meta-Meta-Harness](harness/03-acceptance.md#tier-l6--meta-meta-harness) |
| <a id="the-progression-table"></a>[The Progression Table](harness/03-acceptance.md#the-progression-table) |
| <a id="the-event-sourcing-architectures-role-at-each-tier"></a>[The Event Sourcing Architecture's Role at Each Tier](harness/03-acceptance.md#the-event-sourcing-architectures-role-at-each-tier) |
| <a id="10-parallel-track-the-self-improving-supervisor-foundrys-own-meta-harness"></a>[10. Parallel Track: the Self-Improving Supervisor (Foundry's Own Meta-Harness)](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#10-parallel-track-the-self-improving-supervisor-foundrys-own-meta-harness) |
| <a id="fl0--current-state"></a>[FL0 — Current state](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl0--current-state) |
| <a id="fl1--orchestration-parameter-search"></a>[FL1 — Orchestration parameter search](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl1--orchestration-parameter-search) |
| <a id="fl2--classifier-evolution"></a>[FL2 — Classifier evolution](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl2--classifier-evolution) |
| <a id="fl3--agent-dispatch-strategy-search"></a>[FL3 — Agent dispatch strategy search](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl3--agent-dispatch-strategy-search) |
| <a id="fl4--workflow-architecture-search"></a>[FL4 — Workflow architecture search](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl4--workflow-architecture-search) |
| <a id="fl5--online-self-healing"></a>[FL5 — Online self-healing](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl5--online-self-healing) |
| <a id="fl6--meta-foundry"></a>[FL6 — Meta-Foundry](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#fl6--meta-foundry) |
| <a id="relationship-to-the-product-meta-harness"></a>[Relationship to the Product Meta-Harness](https://github.com/lorecrafting/foundry/blob/main/docs/strategy/META-HARNESS.md#relationship-to-the-product-meta-harness) |
| <a id="references"></a>[References](harness/05-references.md#references) |
