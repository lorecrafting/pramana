# Harness Engineering — Planning — chapter 3

> Design/research note. Proposed commands and guarantees are not shipped capabilities unless current source and acceptance evidence establish them.
> [Contents](../HARNESS.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

### Acceptance

- `mix pramana.retrieval.plan --plan bhumi --query "what happens on the seventh bhūmi"`
  runs the multi-tool plan and returns the combined result
- Plans are cached by plan template + query hash
- `verify_report` can re-execute a plan (not just individual tools)

---

## 8. Implementation Order After Event Sourcing

| # | Work | Depends on | What it produces |
|---|---|---|---|
| H1 | Guard feedback loop | Event sourcing (events) | `GuardVerdictEmitted`, `TranslatorReliability` |
| H2 | Eval coverage & auto-generation | H1 (guard failures as input) | `EvalCoverage`, `mix pramana.evals.generate` |
| H3 | Task-length chain evals | Event sourcing (agent events) | `chain_*.jsonl`, chain survival score |
| H4 | Translators citation reliability | H1 | `TranslatorCitationReliability` projection |
| H5 | Retrieval parameter optimisation | Event sourcing (parameter events) | `mix pramana.retrieval.tune`, `OptimalParameters` |
| H6 | Retrieval plans | None (JSON templates) | `Pramana.Retrieval.Plan`, plan runner |
| H7 | Multi-agent routing | H6 + Event sourcing | Router, Fuser, per-canon sub-agents |
| H8 | Meta-harness self-optimisation | H5 | Six tiers from parameter search to meta-meta |
| **H9** | L2 — prompt & tool-description evolution | H1 guard verdicts | GEPA-style trace reader for `pramana://guide` |
| **H10** | L3 — skill composition | H6 plan runner | Auto-discovery of tool sequences from MCP tools |
| **H11** | L4 — architectural search | H1–H3, release_id | Coding agent rewrites retrieval pipeline |
| **H12** | L5 — continual online adaptation | L4 stable | Per-query bounded parameter adaptation |
| **H13** | L6 — meta-meta-harness | L5 + eval set stable | Archive-based evolution of the meta-harness itself |

**H6 can start before event sourcing** — it is stateless JSON processing. Everything else
benefits from events but could be prototyped with telemetry (H1, H4) or `mix` tasks (H2,
H3, H5).

---

## 9. Beyond Minimal: the Meta-Harness Progression

The quote: *"you got to start with a minimal one first."*

A meta-harness is a harness whose job is producing, optimizing, or rewriting other
harnesses. The progression from minimal to full covers six tiers — each expands the
search space from tunable parameters all the way to the architecture itself.

```
  L1  Parameter search              (H5 in this plan)
  L2  Prompt & tool-description evolution
  L3  Skill & retrieval-plan composition
  L4  Architectural search — the retrieval pipeline rewrites itself
  L5  Continual adaptation — online learning without batch experiments
  L6  Meta-meta — the meta-harness improves itself
```

Every tier after L1 builds on the one before it. Each is described below with: the
search space, what changes, event schema, trigger, risk, and the specific form it
takes for Pramana.

---

### Tier L1 — Parameter Search (minimal meta-harness)

**This is H5 in the implementation plan above.** Already planned, included here for
completeness.

| property | value |
|---|---|
| **Search space** | Existing tunable parameters — RRF k, reranker window, fusion weights, `@min_coverage`, `limit`, embedding cap, chunk size, and any later additions |
| **What changes** | Parameter values only. The pipeline shape is fixed. |
| **Trigger** | Explicit — `mix pramana.retrieval.tune --budget N` |
| **Who owns output** | A human reviews delta before `--accept`. The meta-harness proposes; a person accepts. |
| **Event** | `TrialCompleted(trial_id, parameter, A, B, delta, effect_size)` |
| **Risk** | Overfitting to the eval set. Mitigation: held-out golden set not seen during search, statistical significance test, effect-size threshold before change is candidate |

---

### Tier L2 — Prompt & Tool-Description Evolution

The next thing to search over. The system prompt, MCP tool descriptions, function
signatures, and `pramana://guide` resource are hand-authored and have never changed
since they were written. The GEPA paper (paper 15) shows that reading failed traces and
mutating the prompt that produced them beats reinforcement learning at a fraction of the
rollouts.

| property | value |
|---|---|
| **Search space** | Tool descriptions, function parameter names, system prompt, `pramana://guide` content, error messages |
| **What changes** | The text a model reads. The tool's behaviour (what it calls, what it returns) is unchanged — only how it is *described* to the model. |
| **Trigger** | When a tool's failure rate (from H1's `TranslatorReliability` projection) crosses a threshold, or when a model arm's evaluation shows systematic misinterpretation of a tool |
| **Mutation strategy** | GEPA-style: collect the N worst traces, present them to a frontier model with the current description, and ask for a revision. Scored against held-out evals. |
| **Who owns output** | Human reviews before replacement. Auto-deploy is too risky: an evolved description that passes evals but causes a model to misinterpret the tool in production would be undetected until the next `verify_report` failure. |
| **Event** | `PromptMutated(tool_id, old_text, new_text, rationale, eval_delta)` |
| **Risk** | Prompt drift: successive mutations drift the description from what the tool actually does. Mitigation: integration tests assert the tool does what the description says — a mutation that passes evals but fails integration is refused. |

**Pramana-specific opportunities:** The seventeen tool descriptions in `pramana://guide`
are the most valuable target. `search_translations` returns `match: :any_term` when
individual words match but no single line contains all — if models consistently misread
this as "no match", the description needs to say it louder. `get_passage` returns
`alternatives` (withheld renderings) — if models consistently claim the list is
exhaustive when it is truncated, the description needs an edit.

---

### Tier L3 — Skill & Retrieval-Plan Composition

The retrieval plans (H6) define multi-tool protocols as JSON templates. L3 searches over
*which plans exist and how they compose* — not parameter values of a fixed sequence, but
the sequence itself.

| property | value |
|---|---|
| **Search space** | Tool sequences, branching conditions, output-joins between steps, plan templates |
| **What changes** | `priv/retrieval_plans/` — added, removed, or re-sequenced plans. Individual tool implementations are unchanged. |
| **Trigger** | When the `PlanEffectiveness` projection (H6) shows low success rate. Or: automatic discovery — combinatorial search over 2–4 step tool sequences not yet defined as plans, scored against chain evals (H3). |
| **Search strategy** | Initial candidates: all 2-step combinations of the 19 MCP tools (342 pairs), pruned by feasibility (tools that require a URN output from a prior step). Score each against chain gold sets. |
| **Who owns output** | Reviewed against gold chains before promotion. Auto-promote if delta exceeds a threshold. |
| **Event** | `SkillComposed(plan_id, tool_sequence, score, outperformed_prior)` |
| **Risk** | Novel sequences that pass evals but damage the caller (e.g., `search → survey_corpus` produces unbounded results). Mitigation: each plan has a bounded output budget, hard-coded. |

---

### Tier L4 — Architectural Search (full meta-harness)

**This is the "meta-harness" the paper names.** The retrieval pipeline code itself is the
thing being searched over. A coding agent receives the full search history, source
traces, eval scores, and current architecture, and rewrites the retrieval, memory, or
prompt-assembly code.

The Meta-Harness paper (paper 17) achieved SOTA on Terminal-Bench 2 by doing exactly
this — without touching the weights.

| property | value |
|---|---|
| **Search space** | Pipeline architecture: which retrievers exist, fusion strategy, chunking strategy, embedding model selection, reranker architecture, result window post-processing, cache strategy |
| **What changes** | Source code in `apps/pramana/lib/pramana/retrieval/`. New modules, different query plans, different index structures. |
| **Trigger** | Periodic (every N weeks) or performance-triggered (sustained eval plateau, new model arm that changes the search space) |
| **Search strategy** | A coding agent is given: current retrieval architecture, last N eval runs, recent guard failure diagnoses, recent query patterns. It proposes a concrete architectural change (add per-canon indices, replace RRF with learned fusion, change chunk boundary strategy). Scored by running `mix pramana.evals` in a checkout. |
| **Who owns output** | PR review. **The changed code must pass the same invariant checks the current code does** — the meta-harness does not get to skip invariants #1–#8. |
| **Event** | `ArchitectureProposed → ArchitectureReviewed → ArchitectureDeployed` or `ArchitectureRejected` |
| **Safety** | The citation guard and `verify --all` are architecture-independent — they check the corpus, not the retrieval code. A meta-harness change that breaks retrieval may reduce recall; one that breaks citation verification cannot exist because the guard does not depend on retrieval code. This is the strongest safety property Pramana has for meta-harness work. |

**Pramana-specific architectures for L4 to discover:**

- Per-canon vector indices (Tibetan embeddings in their own HNSW graph with different
  `ef_search` and `m` parameters — Tibetan has 97.3% truncation and needs different
  geometry)
- Sentence-window indexing for Tibetan (prototype proved 16 → 0 unreachable cases)
- Learned fusion weights per query type instead of global RRF
- A classifier that detects "no relevant passage" and returns earlier (the gap statistic
  was measured and rejected at L1; an architectural approach might work differently)

---

### Tier L5 — Continual Adaptation (Online Learning)

Batch experiments propose a change, score it against evals, promote if it wins. L5 does
not wait for batch — the harness adapts online, from every query it serves.

The *Continual Harness* paper (paper 18) keeps history, memory, skills, prompts, and
sub-agent specs across trajectories and mutates them while the agent runs, then updates
weights DAgger-style.

| property | value |
|---|---|
| **Search space** | Everything from L1–L4, but continuously rather than in batch |
| **What changes** | Parameters, prompts, skills, and (at the far end) the reader model's weights |
| **Trigger** | Every query. A failed `verify_citation` adjusts the per-translator reliability projection immediately. A repeated failure pattern across queries triggers a prompt mutation without waiting for the next batch. |
| **Search strategy** | Small set of cheap mutations: adjust RRF per-query fusion weights based on which retriever won for similar queries; adjust candidate window based on query length; reranker on/off based on whether the previous reranker helped. |
| **Who owns output** | No human review per mutation. Safety is structural: bounded max delta per query, auto-rollback if the next query's score drops below a moving baseline. Human owns the safety bounds; meta-harness owns the adaptation. |
| **Event** | `OnlineAdaptation(query_id, adapted_parameter, old, new, delta_to_next)` |
| **Risk** | Catastrophic forgetting: converges to optimise the most frequent query type and degrades rare ones. Mitigation: stratified eval monitoring — per-query-type performance is the loss function, not aggregate. A rare-type drop triggers a batch re-optimisation. |

**Pramana-specific online opportunities:**

- Per-query-type RRF weights: if the past 5 Chinese-root queries fused at
  `{lexical: 0.3, semantic: 0.7}` and all retrieved the right work, shift toward those
  weights for the next Chinese query.
- Reranker on/off: if the last 10 queries had `reranked.tiers == ["t0"]` (only human
  English) and the reranker produced no promotions, turn it off for the next 10.
- Guard verdict → immediate translator reliability update. If a translator reaches 5
  failures in the last 100 checks, the `get_passage` response labels that rendering with
  a confidence warning.

---

### Tier L6 — Meta-Meta-Harness

The Darwin Gödel Machine (paper 16): agents sample from an archive of their own
ancestors, rewrite their own scaffolding, get scored, and go back into the archive.
The meta-harness improves *itself* — the code that searches over parameters, the
mutation strategy for prompts, the discovery algorithm for skills, the bounds for online
adaptation.

| property | value |
|---|---|
| **Search space** | The meta-harness code: search strategy (grid vs Bayesian vs evolutionary), parameter space definitions, mutation operators, trigger thresholds, safety bounds, eval sampling strategy |
| **What changes** | The code in the Foundry's improver and classifier, or a dedicated harness module. The meta-harness rewrites its own search loop, not just the retrieval pipeline. |
| **Trigger** | When the meta-harness's own improvement rate plateaus — eval trend flat for N weeks despite active search. Or when a new capability (a new model arm, a new canon, a new eval type) arrives that the current strategy was not designed to optimise over. |
| **Search strategy** | Archive-based evolution. The meta-harness maintains an archive of its own past configurations. When it detects stagnation, it samples a variant, mutates it, scores it by running N meta-harness cycles, and promotes it if it outperforms the current strategy. |
| **Who owns output** | The archive is human-readable. A human can inspect why a new strategy was chosen. A human can veto. But the design intent is mostly autonomous — human involvement when the archive itself needs redesign (a change to what *counts* as improvement). |
| **Event** | `MetaStrategyEvolved(strategy_id, ancestor_id, mutation_type, delta, epochs)` |
| **Risk** | Meta-overfit: converges on a search strategy that works for the current eval set but cannot discover novel architectures. Mitigation: the eval set itself is under human review (H2). A second meta-meta loop monitors diversity of proposals — if all are small parameter adjustments and none are architectural, a reset is needed. |

---

## The Progression Table

| Tier | Searches over | What produces the change | Human involvement | Runs how often | Depends on |
|---|---|---|---|---|---|
| **L1** - Parameter | Parameter values | `mix pramana.retrieval.tune` | Review delta before accept | On demand | Evals, H3 chain gold sets |
| **L2** - Prompt | Tool descriptions, system prompt | GEPA-style trace reader | Review each proposal | Per tool failure threshold | H1 guard verdicts, L1 eval baseline |
| **L3** - Skill | Tool sequences, plan templates | Combinatorial search over MCP tools | Auto-promote at high delta | Weekly or on new tool | H6 plan runner, H3 chain evals |
| **L4** - Architecture | Pipeline code, index structure, fusion | Coding agent with sandbox | PR review, same as any code change | Monthly or performance plateau | L1–L3, `release_id`, event store |
| **L5** - Online | Everything, per query | Bounded online adaptation loop | Structural bounds only | Per query | L4 architecture stable, drift detector |
| **L6** - Meta-meta | Meta-harness code itself | Archive-based evolution | Veto power, not design per change | When meta-harness plateaus | L5 mature, eval set stable |

---

## The Event Sourcing Architecture's Role at Each Tier

The event sourcing rearchitecture determines how events flow between tiers:

| Tier | Events produced | Events consumed | Must be in same event store? |
|---|---|---|---|
| L1 | `TrialCompleted` | `EvalRunStarted`, `CaseScored` | Yes |
| L2 | `PromptMutated` | `GuardVerdictEmitted` | Yes |
| L3 | `SkillComposed` | `PlanEffectiveness` | Yes |
| L4 | `ArchitectureProposed`, `ArchitectureDeployed` | Everything from L1–L3 | Yes |
| L5 | `OnlineAdaptation` | Everything, continuously | Needs low-latency stream |
| L6 | `MetaStrategyEvolved` | All of the above | Needs archive of meta-harness states |

**Recommendation:** Design the event store so that a consumer can read events from any
tier at any latency. L1–L3 events are write-and-read-later (seconds to minutes). L4
events include code changes and a sandbox build (minutes to hours). L5 events are
sub-second. A single event store with partitioned consumer groups works for all; a
separate low-latency stream for L5 is a future optimisation.

---
