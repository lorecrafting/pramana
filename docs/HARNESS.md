# Harness Engineering — Planning

**Deferred until the event-sourcing rearchitecture lands.** This document captures what
the DAIR.AI Harness Engineering collection&#8203;<!-- footnotes -->[^1] and the surrounding
discourse reveal about Pramana's architecture, and what should be built once the
foundation supports event-sourced state.

> A harness is everything between the model weights and the world: the loop, the context
> it assembles, the tools and skills it can reach for, the sub-agents it can spawn, and
> lately the code of the harness itself. … the same weight file can score 30% or 95% on
> the same benchmark depending only on what surrounds it.

Pramana already embodies this. The model is a **swappable reader** that never touches the
database; the citation guard, provenance tracking, and retrieval pipeline **are the
harness**. This document names the gaps the collection exposes, and plans the work.

---

## 1. Verifiers as the Moat: a Feedback Loop from Guard Verdicts

### What exists

`Pramana.Guard` has five granular failure reasons (`diagnose/1`):

| reason | what it means |
|---|---|
| `:editorial_punctuation` | words match; CBETA's modern punctuation differs |
| `:orthographic_variant` | equivalent glyph under the corpus's variant classes |
| `:spans_line_boundary` | quote crosses a Taishō line break |
| `:wrong_address` | real text at the wrong URN |
| `:absent_from_corpus` | the fabrication case — appears nowhere in the bake |

Plus `verify_report` checks entire documents and re-executes retrievals. The guard is
deterministic, model-independent, and byte-comparison precise — exactly the verifier
infrastructure the Harness Engineering discourse calls undervalued.

### What is missing

**No feedback loop.** The guard diagnoses a failure; the result goes to the caller and
nothing more. No projection aggregates failures by translator, model arm, or canonical
source. No eval case is generated from a real-world verification failure. No alert fires
when a model arm's quotation failure rate crosses a threshold.

The guard's sophistication is consumed as a boolean (or a five-value verdict) and
discarded as a learning signal.

### Event-sourcing design

```
VerificationRequested(source, query, result_urn, quoted_text)
  → GuardVerdictEmitted(urn, quoted, verdict, reason, layer, provenance, translator_id)
```

**Projections (read models built from events):**

| projection | schema | use |
|---|---|---|
| `TranslatorReliability` | `translator_id → {total, failed, failure_rates_by_reason, trend}` | Model-arm monitoring — is MITRA getting worse? |
| `CanonicalFailureMap` | `canon → verdict_reason → count` | Which failure type dominates each tradition |
| `ChainBreakage` | `hop_count, last_verdict, chain_ids` | Multi-hop commentary traversal reliability |
| `UnverifiedClaimsIndex` | `quote_sha256, query, verdict, translator` | Feed for generating new eval cases |

**Commands (actions that produce events):**

| command | produces | when |
|---|---|---|
| `VerifyQuotation` | `GuardVerdictEmitted` | Every `verify_citation` or `verify_report` call |
| `BackgroundVerifyBatch` | `GuardVerdictEmitted×N` | Periodic re-verification of sampled renderings |
| `GenerateEvalCaseFromFailure` | `EvalCaseRegistered` | When a failure pattern repeats N times |
| `AlertOnDeterioration` | `AlertRaised` | When a translator's failure rate exceeds threshold |

### Migration path from current code

The guard's `check/2` is already instrumented — it emits `[:pramana, :guard, :check]`
telemetry. The event-sourced version replaces the telemetry span with an explicit event
write. `Guard.check/2` becomes an idempotent handler: read current bake, write verdict
event, return finding. No logic changes; the storage and aggregation change.

### What ships with this

- `mix pramana.guard.translator_reliability` — reports failure rates per translator
- `mix pramana.guard.generate_evals` — proposes new eval cases from real-world failures
- `GuardVerdictEmitted` integration with the eval gate — a sustained failure rate
  increase blocks deployment

---

## 2. Harness Self-Optimization (Meta-Harness&#8203;<!-- footnote -->[^2] Pattern)

### What exists

The Foundry improver classifies agent failures into 14 categories and proposes hardening
PM tickets. It reads failed traces and mutates prompts from what it saw — the Reflexion
pattern made systematic.

The retrieval pipeline has several tunable parameters:

| parameter | set where | last measured |
|---|---|---|
| RRF k (fusion constant) | `Hybrid` | installation default |
| RRF ranks per retriever | `Hybrid` | installation default |
| reranker candidate window | `Rerank` | installation default |
| hybrid lexical/semantic weight | `Hybrid` (equal) | installation default |
| `limit` (result window) | caller | varied per experiment |
| `@min_coverage` | `Chunk.Vectors` | 0.5, unmeasured impact |
| embedding cap | `Embed` | 320 tokens, measured 2026-09-04 |
| chunk size | `Segment` | ~300 chars, measured 2026-09-04 |

### What is missing

**No systematic search over retrieval parameters.** Every parameter was set once and never
re-derived. The DSPy and GEPA papers show that prompt and pipeline parameters should be
optimised against a held-out eval set, not guessed.

**No A/B framework.** A parameter change is a commit and a full `mix pramana.evals` run.
There is no shadow-deployment, no online A/B, no automatic rollback.

**The prompt is hand-authored.** The system prompt, function descriptions, and MCP tool
descriptions are written by a person and never evolved against usage data.

### Event-sourcing design

```
ParameterChangeProposed(parameter, current_value, proposed_value, rationale)
  → ParameterTrialStarted(trial_id, parameter, A_value, B_value, eval_seed)
    → TrialCompleted(trial_id, winner, delta, effect_size)
      → ParameterChanged(parameter, old_value, new_value, trial_id)
        → EvalGatePassed  (or)  EvalGateFailed → RollbackRequested
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `OptimalParameters` | `query_type → {parameter: value}` | Per-task retrieval config |
| `TrialHistory` | `trial_id → {parameter, A, B, delta, p_value}` | Audit trail for every parameter change |
| `DriftDetector` | `parameter → {baseline, current_value, weeks_since_last_trial}` | Flag parameters that have never been re-derived |

**The key design question:** should parameters be **per-query-type** (a Chinese-root
retrieval needs different fusion weights than a Tibetan commentary retrieval) or global?
The `OptimalParameters` projection supports the per-task model; the initial
implementation should start global and add the breakdown once there is data to steer on.

### Migration path

1. Instrument every parameter with a snapshot function (`Pramana.Retrieval.snapshot/0`)
   that returns all current parameter values as a map. This exists already in scattered
   form (`config()` functions, module attributes); consolidate them.
2. The eval harness records the parameter snapshot with each run.
3. `mix pramana.retrieval.tune` runs a grid or Bayesian search over a bounded space,
   scoring each arm against `evals/`. Output: a `TrialCompleted` record (event-sourced
   or JSONL) naming the winning config and the delta.
4. The event-sourcing rearchitecture makes this a first-class event stream.

### Acceptance

- A parameter change is reversible by replaying events (not by git revert).
- The eval gate can refuse a parameter change that degrades recall.
- `mix pramana.retrieval.tune --budget 10` explores 10 configs and reports the winner.

---

## 3. Task-Length Measurement

### What exists

The eval harness measures **single-turn** scores:

| case type | what it measures | unit |
|---|---|---|
| `retrieval` | Does the passage appear at rank ≤k? | one search |
| `topical` | Does the right tradition appear? | one search |
| `quote_verify` | Does the guard confirm this quote? | one check |
| `gloss` | Does `get_glosses` return the right commentary? | one lookup |

The Kwa paper (*Measuring AI Ability to Complete Long Software Tasks*&#8203;<!-- footnote -->[^3])
argues that harness progress is visible as **task length**, not single-turn accuracy. The
trend line the talk opens on: static-harness systems handle short tasks; self-improving
systems handle longer ones.

### What is missing

No eval case type measures multi-step capability. The corpus *has* multi-step structures:

```
passage → get_quotations → verify_citation (2 steps)
passage → get_commentaries → get_glosses → verify_citation (3 steps)
search → get_passage → get_parallels → compare_versions (3 steps)
get_person → get_works_by_person → get_passage → verify_citation (4 steps)
```

Each step can fail: the search misses the right passage, the quotation graph has no entry,
the guard rejects the quote. **The number of consecutive successful steps** is a
harness-quality measure that the current evals cannot see.

### Event-sourcing design

```
AgentTaskStarted(task_id, task_type, initial_urn)
  → AgentStepStarted(task_id, step_number, tool, arguments)
    → AgentStepCompleted(task_id, step_number, result, duration)
      → AgentTaskFailed(task_id, step_number, failure_reason)
        (or)
      → AgentTaskCompleted(task_id, total_steps, max_continuous_success)
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `TaskLengthDistribution` | `task_type → {p50, p90, p99, max} of completed_steps` | What is this harness capable of? |
| `StepFailureRate` | `task_type, step_number, tool → failure_rate` | Which tool is the bottleneck |
| `ChainSurvival` | `canon_start → canon_end → survival_probability` | Cross-canon traversal reliability |

### Migration path

1. Define canonical multi-step chains (see the four examples above) as gold sequences in
   `evals/gold/chain_*.jsonl`. Each record: starting URN, tool sequence, expected
   final tool response.
2. `mix pramana.evals --chains` runs each chain and scores by `max_continuous_success`.
3. The event-sourcing rearchitecture captures chain events as the agent walks through
   tools.

### What ships with this

- `evals/gold/chain_retrieval.jsonl` — 20+ multi-step chains across canons
- A `chain_survival` score in the gate output
- Documented the Kwa task-length framing in `docs/ARCHITECTURE.md`

---

## 4. Multi-Agent Retrieval Pipeline

### What exists

One query → one hybrid search → rerank → return. All canons are searched simultaneously
through the same vector space and the same lexical index.

### What is missing

The corpus has three structurally different canons:

| canon | English coverage | anchor width | embedding cap issues | primary retrieval mode |
|---|---|---|---|---|
| Pāli (SuttaCentral) | 210,756 human | 1.00 seg (fine) | none | rendering search |
| Chinese (CBETA) | 28,571 generated + 3,354 human | 2.01 segs | none | source + rendering |
| Tibetan (84000) | 30,653 human | 6.94 segs (coarse) | ~97% truncated | rendering search only |

A single hybrid search with one parameter set cannot optimise for all three. The DAIR.AI
collection (paper 10, *Multi-Agent Collaboration*&#8203;<!-- footnote -->[^4]) and paper 13
(*Recursive Language Models*&#8203;<!-- footnote -->[^5]) suggest: spawn per-canon retrieval
specialists and fuse their results.

### Event-sourcing design

```
QueryReceived(query_id, text, detected_language, detected_domain)
  → QueryRouted(query_id, sub_queries: [{canon, retriever_config, priority}])
    → SubSearchStarted(sub_id, canon, config)
      → SubSearchCompleted(sub_id, results, confidence, duration)
        → ResultsFused(query_id, fused_order, confidence_scores)
          → VerificationCheckStarted(fused_result)
            → VerificationCompleted(verdict)
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `RouterAccuracy` | `query_domain → {routed_to, was_correct}` | Does the router work? |
| `SubRetrieverLatency` | `canon, retriever_type → p50/p90/p99 latency` | Performance by sub-agent |
| `FusionQuality` | `fusion_strategy → ndcg@10` | Which fusion method wins |
| `VerificationRate` | `canon → {total, failed, failure_reasons}` | Per-canon guard performance |

### Migration path

**Not a shim over `Hybrid`.** Per-canon retrieval means separate vector indices,
separate lexical indices, and separate reranker passes. The current code shares one
`Hybrid` module that queries all chunks. The event-sourced version:

1. Accepts a query
2. Router agent decides which canons to search and with which priority
3. Each canon agent runs its own `Hybrid` with canon-specific parameters
4. Fuser merges results (weighted by canon priority, not equal RRF)
5. Verifier re-checks top results before returning

### What ships with this

- `Pramana.Retrieval.Router` — dispatches by query language and domain keywords
- `Pramana.Retrieval.Fuser` — weighted fusion by canon priority
- `mix pramana.retrieval.route <query>` — test the router
- Eval gold cases that require cross-canon answers (e.g. "what do Tibetan and Chinese
  commentaries say about the same bhūmi")

---

## 5. Eval Harness Maturity

### What exists

`evals/` is mature: 1,472 gold cases across 8 types, a baseline gate, per-case detail
in JSON, and `mix pramana.evals --gate --accept`. The gate checks coverage, per-tradition
rates, case substitution, and noise.

### What is missing

**No eval generation from real verification failures.** `verify_report` encounters
failures daily. None is automatically surfaced as a candidate eval case. The guard
diagnoses five failure reasons; the eval harness tests three (`quote_verify`,
`quote_reject`, `absence`).

**No coverage analysis of eval cases against the corpus.** Which retrieval failure modes
are untested? Which guards have no eval case? Which translators appear in zero cases?
Unknown.

**No regression sensitivity analysis.** When a case moves, which parameter change caused
it? The current gate reports *that* a case moved, not *why*.

**The human-ceiling confound** (item 13 in PLAN.md: the "human" reference arm scores
itself via identity match) has no structural guard. Rule 84 describes it; no test detects
it automatically.

### Event-sourcing design

```
GoldCaseProposed(source, query, expected_urns, failure_reason, provenance)
  → GoldCaseReviewed(reviewer, accepted/declined, note)
    → GoldCaseRegistered(case_id, type, query, expect_urns, tags)

EvalRunStarted(baseline_id, config_snapshot)
  → CaseScored(case_id, outcome, rank, details)
    → CaseMovementDetected(case_id, old_outcome, new_outcome, delta_type)
      → (if baseline changed) CaseAccepted(case_id)  or  CaseInvestigationOpened(case_id)

RetrievalParameterSnapshot(case_id, parameters)
  → SensitivityAnalysisCompleted(case_id, causal_parameter, effect_size)
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `EvalCoverage` | `failure_mode → {has_case, case_ids, last_verified}` | Which guard verdicts are untested |
| `TranslatorEvalCoverage` | `translator_id → {in_eval_cases, verdict_distribution}` | Is every translator evaluated? |
| `BaselineDrift` | `case_id → {current_outcome, trend, first_seen_at}` | Gradual degradation detection |
| `HumanCeilingCheck` | `eval_type → {has_identity_confound, measured_delta, warning}` | Rule 84 automated |

### Migration path

1. `mix pramana.evals.generate --from-guard-failures` scans recent guard failures
   and proposes eval cases. Output: JSONL ready for review. **Does not write gold cases
   without human review** — auto-generated cases would measure the system's own blind
   spots against themselves.

2. `mix pramana.evals.coverage` reports which failure modes have no gold case. The gate
   warns when coverage drops below a threshold.

3. `mix pramana.evals.sensitivity` runs each case twice with one parameter varied,
   reporting delta per case. Initial focus: `k`, RRF weight, reranker on/off.

### What ships with this

- A `failure_mode_coverage` metric in the gate output
- `mix pramana.evals.generate` — proposes candidate cases from guard logs
- Automated `HumanCeilingCheck` — flags any eval case where query and index share a
  translator identity (rule 84)

---

## 6. Cross-Canon Citation Reputation

### What exists

Every retrieved span carries `tier` (`t0` human, `t1` generated), `method` (`human`,
`llm`), and `review_state`. The MCP response includes `reranked.tiers` so a caller knows
whether generated text influenced the order. Invariant #8 prevents generated text from
being citable as source.

### What is missing

**No cross-referencing of citation reliability by translator and canon.** A human
translator whose renderings consistently fail the guard (wrong addresses, editorial
punctuation mismatches) is indistinguishable from one who passes every time. A generated
layer that produces 90% verifiable quotations is not labelled any differently from one
that produces 10%.

**No reputation surface.** Neither the reader nor the MCP tools expose "this translator's
citations verify at N% against this corpus" — a number that would directly affect how a
model or scholar trusts a claim.

### Event-sourcing design

The data already exists in the guard telemetry. The event-sourcing version:

```
GuardVerdictEmitted(translator_id, canon, verdict)
  → TranslatorReliabilityUpdated(translator_id, trailing_window, verdict_counts)
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `TranslatorCitationReliability` | `translator_id → {rate, trailing_n, by_canon}` | Per-translator trust score |
| `LayerCitationReliability` | `{method, tier} → rate` | Generated vs human aggregate |
| `CanonCitationHealth` | `canon → top_translators, bottom_translators` | Which canon's English is weakest |
| `VerificationTrend` | `translator_id → {week_over_week, month_over_month}` | Deterioration detection |

### Migration path

1. `mix pramana.guard.translator_reliability` reads telemetry and produces the table.
   Requires only the already-instrumented telemetry — no event sourcing needed.
2. Surface on `get_person` as `citation_reliability`, and on `get_passage` beside each
   rendering.
3. The event-sourcing rearchitecture makes the projection incremental and live.

### Acceptance

- A model can ask "which translation of this passage should I cite?" and receive the
  translator with the highest verification rate, not just the first rank.
- The eval gate warns when a translator's verification rate drops below a threshold.

---

## 7. Agentic Retrieval: Orchestrating the Tool Surface

### What exists

Nineteen MCP tools, each callable independently. A model decides the order and
combination. `verify_report` can re-execute tool calls from a report.

### What is missing

**No orchestrated retrieval pattern.** The collection's papers show that co-ordinated
tool use beats independent calls: a search then a verification then a secondary search if
verification fails. Pramana has the tools; it does not have the orchestration layer.

**No retrieval plan expressed as data.** A "bhūmi investigation" should be: search →
get_commentaries for each canon → get_glosses → get_parallels → verify_citation. This is
a mini-program, not one call.

### Event-sourcing design

```
RetrievalPlanCreated(plan_id, steps: [{tool, arguments}, ...])
  → PlanStepExecuted(plan_id, step_number, tool, result_summary)
    → PlanBranchTaken(plan_id, step_number, branch_condition, next_step)
      → PlanCompleted(plan_id, final_response, total_duration, steps_succeeded)
```

**Projections:**

| projection | schema | use |
|---|---|---|
| `PlanEffectiveness` | `plan_template → {success_rate, avg_duration, p50_steps}` | Which patterns work |
| `BranchUtility` | `plan_template, branch_condition → {taken_rate, improves_outcome}` | Is branching worth it |
| `ToolSequenceFreq` | `[tool_list] → frequency, avg_success` | Common usage patterns |

### Migration path

**Do not build a planner agent.** The plan is expressed as JSON, not as an LLM decision.
A `retrieval_plan.json` file defines:

```json
[
  {"tool": "search", "arguments": {"query": "{{Q}}"}, "output": "passages"},
  {"tool": "get_passage", "arguments": {"urn": "$passages[0].urn"}, "output": "detail"},
  {"tool": "verify_citation", "arguments": {"urn": "$detail.urn", "quote": "$detail.text"}}
]
```

Templates live in `priv/retrieval_plans/`. The runner is `Pramana.Retrieval.Plan` —
synchronous, deterministic, no LLM involved. Variable interpolation from `{{Q}}` and
`$step.output.path`. Branching on `$step.verdict == "failed"`.

After event sourcing: plans emit lifecycle events and the projections above become active.

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

## 10. Parallel Track: the Self-Improving Supervisor (Foundry's Own Meta-Harness)

The six tiers above are for the **product** — the retrieval pipeline that users and models
query. There is a second, parallel meta-harness for the **build process**: the Foundry
supervisor that writes code, runs experiments, and maintains Pramana itself.

The Foundry already has foundations the product meta-harness is still waiting for:

| What | Foundry | Umbrella (product) |
|---|---|---|
| Event sourcing | ✅ Coordinator emits checkpoint events before state mutations | ❌ Not yet — planned rearchitecture |
| Event schema | ✅ `event-v1.json` — validated JSONL | ❌ Not yet |
| Event log | ✅ `foundry/local/state/current/events.jsonl` | ❌ Not yet |
| Self-healing loop | ✅ Improver — 14 classifiers, 5-min cycle | ❌ Not yet — H1 planned |
| Hardening PM | ✅ Dedicated GenServer for IMPRV-* tickets | ❌ Not yet |
| Agent lifecycle | ✅ DynamicSupervisor + GenServer per agent | ❌ Not yet — Foundry-only |

**The Foundry IS a domain-specific harness for software engineering over Pramana.** Its
meta-harness progression is about improving the Foundry's own orchestration — not the
retrieval pipeline it manages, but the system that manages the pipeline.

### FL0 — Current state

Everything hand-authored:

- **14 improver classifiers** — static pattern matches with hardcoded thresholds
  (`@crash_threshold 3`, `@launch_failure_rate 0.3`, `@stuck_queue_ms 120000`)
- **Coordinator state machine** — fixed GenServer pattern with hand-coded transitions
- **Agent dispatch** — fixed DynamicSupervisor + GenServer per agent, serial launches
- **Roles** — developer, reviewer, pm — each a static markdown file
- **PM cycle** — fixed 10-minute timer for hardening review
- **Scheduler** — fixed polling interval (15s), fixed ticket queue management

### FL1 — Orchestration parameter search

Search over the Foundry's own tunable parameters:

| parameter | current value | module |
|---|---|---|
| `@crash_threshold` | 3 | Improver |
| `@launch_failure_rate` | 0.3 | Improver |
| `@stuck_queue_ms` | 120000 | Improver |
| `@default_interval_ms` | 300000 (5 min) | Improver |
| `@hardening_interval_ms` | 600000 (10 min) | HardeningPM |
| `poll_ms` (coordinator tick) | 15000 | Coordinator |
| `max_launch_retries` | 3 | Coordinator |
| agent timeout | defaults | AgentServer |
| Herdr timeout | 30000 | Coordinator |

**What changes:** Parameter values only. The orchestration shape is fixed.

**Trigger:** When the Foundry's own efficacy metrics cross a threshold — e.g., ticket
throughput per cycle, agent success rate, proposal acceptance rate.

**Produces:** `mix pramana_foundry.health --diagnose` that recommends parameter changes
based on observed cycle efficiency.

**Risk:** Overfitting to current workload patterns. If the corpus is stable and tickets
are few, the improver may converge to parameters that work well for 3 tickets/week and
break under load. Mitigation: parameters revert to defaults when ticket volume changes
by more than 2×.

### FL2 — Classifier evolution

The 14 classifiers are the improver's core intelligence. When a failure trace does not
match any classifier, the improver currently drops it as noise. FL2 evolves the
classifier set.

**What changes:** The pattern-matching logic in the improver's `classify/1` function. New
classifiers added, existing ones refined, dead ones removed.

**Trigger:** When `UnclassifiedTracesRate` — the share of failure traces matching no
classifier — exceeds a threshold (e.g., 10% of traces in a cycle). Or when a classifier
has consistently produced proposals that were rejected (over-classifying).

**Mutation strategy:** GEPA-style: collect the N unclassified traces, present them with
the current classifier set to a frontier model, and ask for new classifier patterns that
would have caught them. Scored against a held-out trace set: precision (does the new
classifier fire on things it shouldn't?) and recall (does it fire on the traces it was
created for?).

**Who owns output:** The new classifier pattern is reviewed before addition. A classifier
that fires on nothing after N cycles is auto-removed.

**Event:** `ClassifierProposed(fingerprint, pattern, traces_caught, false_positive_rate)`
→ `ClassifierAccepted` or `ClassifierRejected`

**Risk:** Classifier proliferation — adding classifiers for one-off failures degrades the
system's signal/noise ratio. Mitigation: a classifier must catch at least N distinct
traces (not repeats of the same failure) before it is promoted out of probation.

### FL3 — Agent dispatch strategy search

Currently every agent launch creates a GenServer under the DynamicSupervisor with fixed
timeout, retry, and routing. FL3 searches over how agents are dispatched.

**What changes:** The agent launch strategy in `AgentServer.start_link/1` and
`Herdr.Adapter`. Not the agent's behaviour — how agents are launched and managed.

**Search space:**

| strategy | when to try | risk |
|---|---|---|
| Eager launch (spawn all tickets now) | Low load, fast agents | Resource contention |
| Lazy launch (spawn when coordinator tick) | Normal operation | Latency |
| Pooled agents (pre-spawn N agents, assign tickets) | Predictable ticket types | Wasted agents |
| Serial launches (one agent at a time) | Corpus bake — exclusive resource | Throughput floor |
| Priority queuing (high-priority tickets skip queue) | Urgent fixes | Starvation of low priority |

**Trigger:** When ticket throughput drops (more tickets queued than completed per cycle)
or when agent failure rate rises.

**Produces:** `Coordinator.dispatch_strategy()` — the active strategy, which can be
switched at runtime without restarting agents.

### FL4 — Workflow architecture search

The Foundry's own coordination code — the coordinator state machine, the handoff flow,
the integration pipeline. A coding agent rewrites the Foundry's orchestration.

**What changes:** Source code in `foundry/lib/pramana_foundry/coordinator.ex`,
`improver.ex`, `hardening_pm.ex`, `agent_server.ex`. Not the agent behaviour — how the
Foundry manages itself.

**Trigger:** When FL1–FL3 improvements plateau (ticket throughput flat for N cycles
despite active parameter/classifier/dispatch search).

**Search strategy:** A coding agent is given: the current Foundry architecture, the last N
cycle metrics (throughput, proposal acceptance rate, agent success rate, cycle duration),
and the event log. It proposes a concrete architectural change — e.g., "merge the improver
and hardening PM into one cycle to reduce latency between finding and acting", or "replace
the GenServer-based coordinator with a pure Ecto-based projection that doesn't need VM
state".

**Who owns output:** PR review, same as any code change. The changed code must pass the
same tests the current Foundry does. The key safety property: the event log is the source
of truth — a new coordinator that reads from the same log produces the same state, even
if it gets there by a different path.

**Risk:** The coding agent produces a coordinator that works differently and passes tests
but has worse performance under the real workload. Mitigation: the event log supports
replay — the new coordinator is tested against a replay of the last N cycles of live
events before it is deployed. If it processes the replay slower than the current
coordinator, it is rejected.

### FL5 — Online self-healing

The Foundry learns from its own cycles in real-time, adjusting dispatch, classifiers, and
priorities per-cycle without waiting for batch FL2/FL3 experiments.

**What changes:** Runtime adaptation of improver thresholds, dispatch strategy, agent
timeouts, classifier firing order. All within the bounds set by FL1's parameters — FL5
adjusts within the envelope; FL1 adjusts the envelope.

**Trigger:** Every cycle. If the last cycle's agent failure rate was high, the next cycle's
agent timeout is extended. If the last cycle's proposal acceptance rate was low, the next
cycle's classifier confidence threshold is raised.

**Safety:** Bounded adaptation only. Max parameter delta per cycle (e.g., timeout can
increase by at most 20% per cycle). Automatic rollback if the adjustment makes things
worse (measured as proposal acceptance rate dropping after an adjustment).

**Event:** `FoundryOnlineAdaptation(cycle_id, parameter, old, new, delta)` — emitted for
every adjustment, enabling offline analysis of whether the online loop is converging.

**Pramana-specific opportunity:** The improver runs every 5 minutes but the cycle can
complete in under 30 seconds for a small ticket queue. The remaining 4.5 minutes are idle.
An online loop could use that idle time to run low-priority meta-experiments — e.g., test
a new classifier against archived traces without affecting the live cycle.

### FL6 — Meta-Foundry

The improver's improvement logic improves itself. If the improver's proposals have been
declining in acceptance rate (the PM or reviewer rejects more of them), the meta loop
adjusts how the improver formulates proposals — more evidence per finding? shorter
summaries? different severity labels? different role assignment for the proposal review?

**What changes:** The code of the improver's `do_analyze/1` — the loop that reads records,
classifies traces, derives observations, computes forecasts, and creates proposals. The
meta loop rewrites the analysis function itself, not just its parameters.

**Search space:** Analysis strategy, classifier ordering, observation derivation method,
forecast algorithm, proposal formulation template.

**Trigger:** When the improver's own proposal acceptance rate drops below a threshold for
N consecutive cycles. Or when the Foundry's ticket queue has been empty for N cycles
(everything is running smoothly and the improver has nothing to propose — at which point
it should be looking for latent improvements rather than waiting for failures).

**Who owns output:** Human veto power over meta-Foundry changes, because a broken
improver that stops noticing failures is the system's blind spot. The meta loop proposes
a new improver; a human accepts or rejects it. The old improver is retained in the
archive and can be reinstated with one command.

### Relationship to the Product Meta-Harness

The two meta-harness progressions operate on different timescales and feed each other:

| | Product meta-harness (L1–L6) | Foundry meta-harness (FL0–FL6) |
|---|---|---|
| **What it optimises** | Retrieval pipeline — parameters, prompts, architecture | Orchestration — dispatch, classifiers, coordination |
| **Timescale** | Hours per trial (evals run ~30 min) | Minutes per cycle (improver runs every 5 min) |
| **Eval signal** | Gold-set evals, recall@k, chain survival | Cycle metrics: throughput, proposal acceptance, agent success |
| **Event stream** | Umbrella event store (planned) | Foundry `events.jsonl` (exists) |
| **Auto-deploy risk** | Low — guard is architecture-independent | High — a broken coordinator stops all work |
| **First step** | `mix pramana.retrieval.tune` (H5) | `mix pramana_foundry.health --diagnose` (FL1) |

The two converge at L4/FL4 (architectural search): a coding agent that proposes changes
to both the retrieval pipeline AND the orchestration, because a change to one may require
a change to the other (e.g., per-canon retrieval requires the coordinator to dispatch
canon-specific agent types).

## References

[^1]: DAIR.AI Academy, "Harness Engineering Paper Collection."
    https://academy.dair.ai/papers/collections/harness-engineering

[^2]: Yoonho Lee et al., "Meta-Harness: End-to-End Optimization of Model Harnesses"
    (2026). arXiv:2603.28052

[^3]: Thomas Kwa et al., "Measuring AI Ability to Complete Long Software Tasks"
    (2025). arXiv:2503.14499

[^4]: Yashar Talebirad, Amirhossein Nadiri, "Multi-Agent Collaboration: Harnessing the
    Power of Intelligent LLM Agents" (2023). arXiv:2306.03314

[^5]: Alex L. Zhang, Tim Kraska, Omar Khattab, "Recursive Language Models" (2025).
    arXiv:2512.24601

[^6]: Seth Karten et al., "Prime Agent" (2026). arXiv:2608.23552

[^7]: Jon Saad-Falcon et al., "OpenJarvis: Personal AI, On Personal Devices" (2026).
    arXiv:2605.17172

[^8]: Lakshya A Agrawal et al., "GEPA: Reflective Prompt Evolution Can Outperform
    Reinforcement Learning" (2025). arXiv:2507.19457

[^9]: Jenny Zhang et al., "Darwin Godel Machine: Open-Ended Evolution of
    Self-Improving Agents" (2025). arXiv:2505.22954

[^10]: Seth Karten et al., "Continual Harness: Online Adaptation for Self-Improving
    Foundation Agents" (2026). arXiv:2605.09998