# Harness Engineering — Planning — chapter 1

> Design/research note. Proposed commands and guarantees are not shipped capabilities unless current source and acceptance evidence establish them.
> [Contents](../HARNESS.md) · [Documentation](../README.md) · [Current architecture](../../pramana/docs/ARCHITECTURE.md)

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
