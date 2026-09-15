# Harness Engineering — Planning — chapter 2

> Design/research note. Proposed commands and guarantees are not shipped capabilities unless current source and acceptance evidence establish them.
> [Contents](../HARNESS.md) · [Documentation](../README.md) · [Current architecture](../ARCHITECTURE.md)

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
