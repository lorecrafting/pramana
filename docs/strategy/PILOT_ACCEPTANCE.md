# Chinese pilot acceptance and rehearsal contract

**Status:** frozen pre-execution contract; no pilot execution or provider use is authorized.
**Decision date:** 2026-09-17
**Pilot:** `chinese-commentary-v1`
**Machine-readable companion:** [`pilot_acceptance.json`](pilot_acceptance.json)

[Pilot charter](PILOT_CHARTER.md) · [pilot preflight](PILOT_PREFLIGHT.md) ·
[validation](VALIDATION.md) · [rights/data flow](CHINESE_PILOT_RIGHTS.md)

This contract freezes the Chinese-first pilot's **execution ceilings, evaluation rubric,
critical-failure taxonomy and rehearsal contract before implementation**. The numbers are
preregistered feasibility/safety choices, not claims that the current code already enforces
them or that they are empirically optimal.

It deliberately does **not** freeze the exact live pilot corpus. The `pilot_scope` gate
still requires a release-bound materialization of seed IDs, relation traversal, expanded
works, alignment coverage and denominators. It also does not select a model/provider,
authorize cash spend, identify evaluators or claim a rehearsal has run.

## What "frozen" means

The machine-readable companion is the exact v1 value set. Prose below explains it.

Before the first participant task, changing a bound, scoring rule, critical-failure
definition or rehearsal pass condition requires:

1. a new contract revision;
2. an explicit reason;
3. re-running every baseline/rehearsal result affected by the change; and
4. updating the preflight evidence.

After the first participant task begins, changing an acceptance threshold or critical
definition makes that pilot version inconclusive for its preregistered decision. Continue
only under a new declared pilot revision; do not move the goalposts inside the same result.

A frozen contract is **not runtime enforcement**. Later implementation must prove every
bound is enforced at the admission/execution boundary. A log that merely reports a larger
value after the fact does not satisfy a hard ceiling.

## Repository observations used to set the initial ceilings

These are context, not authority:

- current Hybrid retrieval defaults to 20 returned results and caps public result/depth
  limits at 200;
- with a 20-result request, current measured Hybrid defaults inspect 60 lexical and
  120 semantic candidates and rerank at most 100;
- the existing deterministic `Retrieval.Terms` helper already caps matched English
  headwords at three;
- the historical translation glossary helper caps terminology pins at 12, although that
  helper is **not** a pilot-safe provenance interface;
- current evaluation code treats timeouts/errors separately from misses rather than
  silently publishing them as retrieval failures.

The pilot preserves the useful bounded shapes without claiming the historical
English-index/translation workflow is authorized or suitable as the new implementation.

# 1. Per-task execution bounds

A **task attempt** begins when one user question is admitted against one declared pilot
scope/release and ends in success, explicit refusal, timeout or failure. A manual retry is a
new attempt with a new receipt.

## 1.1 Query planning

| Bound | v1 ceiling | Rule |
|---|---:|---|
| extracted concepts | 3 | Additional concepts are reported as unexpanded rather than silently broadened |
| deterministic Chinese candidates retained in the plan | 12 distinct | Deduplicate normalized-identical candidates before counting |
| deterministic Chinese candidates allowed to trigger retrieval | 8 distinct | Rank by relation class/scope evidence; the remaining planned candidates stay inspectable but do not execute |
| `related` candidates allowed to trigger retrieval | 3 of the 8 | Related concepts can improve recall but cannot numerically swamp equivalence-bearing candidates |
| `model_proposed` candidates | 4 distinct | Recall-only, visibly unverified, never promoted by retrieval success |
| model calls for optional query proposal | 1 | Zero unless an inference route is separately authorized |

Candidate precedence is:

`explicit_equivalent` / `attested_gloss` / in-scope `historical_rendering` →
`transliteration` / `orthographic_variant` → reviewed `broader_narrower` →
`related` → `model_proposed`.

This is execution priority, not a claim that every item inside one class is equally valid.

A normalized identical retrieval query executes once even if several glossaries or
concepts produced it. All provenance records still survive in the plan.

## 1.2 Retrieval and fusion

The pilot may use the four intended independent arms, but each arm stays bounded.

| Bound | v1 ceiling |
|---|---:|
| lexical results returned per Chinese query | 20 |
| semantic results returned per Chinese query | 20 |
| lexical candidate depth per query | 60 |
| semantic candidate depth per query | 120 |
| Chinese lexical query executions across the task | 12 |
| Chinese semantic query executions across the task | 12 |
| original-English multilingual semantic queries | 1 |
| existing-English-index queries | 1 |
| all retrieval query executions across the task | 26 |
| fused results retained before evidence selection | 20 |
| weak-expansion fusion contributions per passage | 1 |

The lexical 60 / semantic 120 ceilings match the current 20-result Hybrid shape rather than
raising the existing retriever's 200 ceiling merely because it exists.

A future implementation may issue fewer searches. It may not convert unused allowance in
one class into extra `related` or `model_proposed` searches. The 26-execution ceiling is
the sum of at most 12 Chinese lexical queries, 12 Chinese semantic queries, one
original-English multilingual query and one existing-English-index query; a candidate
cannot be fanned out into undeclared extra scopes/queries to escape these totals.

`related` and `model_proposed` candidates share **one weak fusion contribution bucket per
passage**. Several weak expansions retrieving the same passage may improve recall but cannot
accumulate multiple votes/evidence weight against one attested candidate. Their individual
receipts remain visible even though their fusion contribution is capped.

Every executed query must retain:

- exact query text;
- query-candidate id;
- provenance/relation class;
- glossary/work scope where applicable;
- retrieval arm;
- rank before fusion;
- rank after fusion; and
- source release/index identity.

A timeout/error is **not** a miss, an absence claim or an empty successful arm.

## 1.3 Exegetical expansion and selected evidence

| Bound | v1 ceiling |
|---|---:|
| accepted relation traversal | 2 hops |
| unique related works admitted per task | 8 |
| passages supplied to answer synthesis | 8 |
| unique source passages sent for generated reading translation | 6 |

Only accepted `comments_on` / `subcommentary_of` edges from the frozen pilot scope may
create the exegetical path. Topic similarity cannot consume an exegetical slot by pretending
to be a relation.

The eventual scope materialization may be **narrower** than two hops. The task executor
must obey the smaller of the scope allowance and this execution ceiling.

Users may navigate additional local source context in the reader without automatically
putting those bytes into model context. Opening a passage is not consent to synthesize or
send it externally.

## 1.4 Reading-translation payload

For one task attempt:

| Bound | v1 ceiling |
|---|---:|
| Chinese/source characters per generated translation unit | 1,200 |
| UTF-8 source bytes per generated translation unit | 4,800 |
| Chinese/source characters translated across the task | 6,000 |
| UTF-8 source bytes translated across the task | 24,000 |
| terminology pins supplied to one translation | 12 |
| UTF-8 glossary/terminology bytes per translation unit | 4,000 |
| UTF-8 glossary/terminology bytes across the task | 12,000 |
| unique source hashes translated | 6 |

Both character and byte ceilings apply; the smaller effective allowance wins. Source bytes
and glossary/terminology bytes have separate ceilings so a richer terminology packet cannot
become an unbounded prompt or data-transfer side channel. Whitespace, markup and all
source/glossary material placed in model context must be counted according to the eventual
provider-interface specification rather than hidden outside the budget.

Provider/model-specific input/output token counts must also be recorded when an inference
route is selected. Because no tokenizer/provider is authorized today, the exact UTF-8
source-byte ceilings are the provider-neutral hard bounds; provider token limits may make a
future route narrower, never wider.

A source hash already translated successfully in the same task must reuse that result.
A failed duplicate must refuse/retry explicitly; it must not issue an invisible second call.

## 1.5 Model calls, retries, time and spend

| Bound | v1 ceiling |
|---|---:|
| all model calls per task attempt | 8 |
| optional query-proposal calls | 1 |
| reading-translation calls | 6 |
| final synthesis calls | 1 |
| automatic retries | **0** |
| timeout per model call | 60 seconds |
| total automated task-attempt timeout | 300 seconds |
| authorized cash spend | **US$0.00** |

The eight-call maximum is a ceiling, not a target. Batching may reduce call count, but does
not raise source-byte or evidence limits.

**No hidden retries.** A timeout, provider failure, parse failure or refusal ends that stage
for this attempt unless a user/operator explicitly starts a new attempt. The new attempt
gets a new receipt and fresh bounds; previously successful source-hash translations should
still be reused where policy allows.

The present spend ceiling is zero because the charter grants no provider/billing
authority. **External-provider calls and external-provider capacity are both unauthorized
in v1**, including free tiers, trial credits, prepaid/included subscription capacity and
already-funded accounts. Zero marginal cash does not create authority.

If the operator later authorizes any external route, this contract must be revised to name
the permitted route and both its cash and non-cash/metered-capacity bounds before the
`inference_authority` gate can become ready. Provider availability, an API key or an
existing subscription is never permission to execute or consume capacity.

Local-model inference is still subject to the same candidate, passage, byte, call, retry
and timeout ceilings. "Local" changes billing/data-transfer questions, not epistemic or
resource bounds.

## 1.6 Bound-exceeded behavior

Crossing a ceiling produces a typed **`bound_exceeded` refusal for that stage**.

The system must not:

- silently truncate and then report a complete/exhaustive result;
- replace a blocked source/model with an undeclared alternative;
- drop provenance to fit a prompt;
- relabel a timeout as "no evidence exists"; or
- exceed the bound and merely log a warning afterward.

A partial deterministic result may still be shown when its incompleteness is explicit and
no critical trust rule is violated. It cannot support an exhaustiveness/absence claim.

# 2. Frozen evaluation protocol

Evaluation has different units because retrieval, lexical equivalence, translation and
claim support are different claims. One aggregate "quality" score is prohibited.

Ground-truth/evaluator judgments for held-out cases must be recorded **before inspecting
the candidate system's output** wherever feasible. Legitimate multiple passages,
translations and interpretations may be accepted; the benchmark must not force one
proof-text when scholarship permits several.

## 2.1 Retrieval

For each eligible held-out retrieval case, report:

- evaluator-approved evidence recall@1, recall@5 and **recall@10**;
- reciprocal rank of the first acceptable passage where one exists;
- every independent arm and the fused result separately;
- task class;
- text role;
- supported-in-scope vs genuinely out-of-scope status;
- executed query-candidate provenance;
- timeout/error/refusal separately from miss.

The primary retrieval metric is **evaluator-approved evidence recall@10**. Recall@10 asks
whether useful evidence became inspectable, not whether one preselected sentence ranked
first.

Before participant execution, the held-out supported-case baseline must contain at least
**30 evaluator-confirmed in-scope questions**, including at least **8 commentary-eligible
questions**. The frozen v1 floor is:

- **overall supported-case recall@10 ≥ 80%**; and
- **commentary-eligible supported-case recall@10 ≥ 75%**.

These are preregistered feasibility floors, not claimed industry benchmarks. They may reveal
that the proposed pilot is not ready; they may not be lowered after seeing the baseline
while retaining the same contract revision. Timeout/error cases are reported separately
rather than removed until the denominator looks better.

A natural question that is genuinely outside the frozen scope is an
`unsupported_out_of_scope` case, not a retrieval miss. A question supported by the scope
but not found is a miss. The distinction requires a qualified evaluator/corpus check; the
system cannot self-certify absence from its own failed search.

No fused improvement may hide an arm-specific collapse. Report cases rescued and harmed by
each arm.

## 2.2 Query expansion

Every reviewed candidate is classified by its declared relation:

- `explicit_equivalent`;
- `attested_gloss`;
- `historical_rendering`;
- `orthographic_variant`;
- `transliteration`;
- `broader_narrower`;
- `related`; or
- `model_proposed`.

The evaluator records one outcome:

- **correct as declared**;
- **correct only with narrower work/translator scope**;
- **related but relation overstated**;
- **wrong concept**;
- **fabricated/unattested**; or
- **insufficient evidence**.

Report precision/error counts by declared relation class. Do not collapse
`historical_rendering` and `related` into generic "correct terms."

**Verified-equivalence surface threshold: 100%.** Anything the system presents as a
verified equivalence/attestation must be judged either **correct as declared** or **correct
only with narrower work/translator scope**, with that narrower scope preserved in the
product and downstream plan. One overstated/wrong/fabricated verified-equivalence case is
CF06 and fails acceptance; it cannot be averaged away.

`related` and `model_proposed` are excluded from that equivalence denominator precisely
because they are not equivalence claims. They may contribute recall only while retaining
their weaker relation labels.

A `model_proposed` candidate can be useful retrieval input without becoming an
equivalence. Retrieval success never upgrades its provenance.

## 2.3 Generated reading translation

Each sampled generated reading is evaluated against the exact Chinese passage by a
qualified Buddhist-Chinese evaluator on six dimensions:

| Dimension | 2 | 1 | 0 |
|---|---|---|---|
| propositional fidelity | source claim preserved | minor imprecision without material meaning change | material claim changed/invented |
| omission / addition | no material omission/addition | minor non-material loss/addition | material source content omitted or invented |
| negation / modality | polarity, condition and force preserved | minor nuance loss | reversal/negation/obligation materially changed |
| technical terms | doctrinal terms adequate and scoped | understandable but improvable/inconsistent | materially misleading doctrinal rendering |
| names / referents | actors, titles, pronouns and references preserved | minor ambiguity recoverable from context | wrong actor/text/referent |
| readability | clear natural English | understandable with awkwardness | materially difficult/misleading to read |

A reading translation passes for pilot reader evidence only when:

- **no dimension scores 0**;
- total score is **at least 9/12**;
- no critical failure below applies; and
- its generated/unreviewed status remains visible unless that exact rendering received the
  required human review.

Report translation results separately for `root`, `treatise`, `commentary` and
`subcommentary`. A strong root-text average cannot mask failing commentary.

Automatic glossary/back-translation/model agreement may diagnose. None can substitute for
the qualified evaluator in this pilot.

Before `rehearsal_trust` may become ready for participant execution, the **actual
separately authorized inference route** (local or external) must also produce at least
**8 source-bound reading translations**, with at least **2 samples for each text role
present in the frozen pilot scope**, up to the eight-sample minimum. Every sample must pass
the 9/12, no-zero-dimension translation rule and no critical failure may remain. If the
scope contains more roles than eight samples can cover at two each, the sample grows to
cover them; eight is a minimum, not a cap.

The provider-free deterministic rehearsal can therefore prove control-flow mechanics, but
it cannot by itself prove the configured inference route's translation quality.

## 2.4 Claim support

Every substantive generated-answer claim receives one support class:

1. `direct_source_support`;
2. `independent_treatise_support`;
3. `commentarial_interpretation`;
4. `synthesis_across_sources`;
5. `unresolved_or_insufficient`.

For classes 1–4, the evaluator checks that the cited passages actually support the
classification and that source role/tradition/scope are not overstated. Class 5 must remain
visibly unresolved rather than being rewritten into a confident answer.

A genuine quotation with an unsupported interpretation fails claim support even when byte
verification passes.

## 2.5 Evidence reuse and ordinary-user comprehension

The charter's existing user-level floors remain controlling:

- ≥75% eligible task success overall and ≥60% per user stratum;
- ≥80% source/rendering/commentary/synthesis comprehension;
- ≥80% traceable evidence-packet reuse among successful tasks;
- median ≤3 minutes and p90 ≤8 minutes to useful inspectable evidence;
- the declared 14-day repeat-use signal.

This contract does not change those floors.

Evidence-packet traceability means an independent reviewer can recover the same permitted
source passage(s), source identity, roles, rendering status, scope and limitations from the
packet. Correctly copying generated prose is not source traceability.

# 3. Critical-failure taxonomy

A known critical failure is a **stop/fix condition regardless of average scores**. It may
not be offset by more successful tasks.

| ID | Critical failure | Concrete trigger | Required response |
|---|---|---|---|
| CF01 | false verification | fabricated/altered quotation or nonexistent citation shown as source-verified | stop affected acceptance run; repair guard/claim surface |
| CF02 | wrong source identity | wrong work, witness, edition or address presented as the evidence retrieved | stop; repair identity/provenance path |
| CF03 | rendering/source conflation | generated or human English shown/cited as the authoritative Chinese witness, or generated shown as human | stop; repair layer labeling/selection |
| CF04 | wrong text role | commentary/treatise/root/subcommentary role materially misrepresented | stop; repair role/provenance path |
| CF05 | fabricated exegetical relation | topical similarity or unsupported inference presented as `comments_on` / `subcommentary_of` | stop; remove relation-producing path |
| CF06 | query-equivalence overclaim | related, scope-limited or model-proposed term presented as a verified universal equivalent/synonym | stop affected expansion path; correct provenance/relation |
| CF07 | material translation distortion | score-0 propositional/omission/negation/term/referent error that materially changes the source | block that rendering from reader evidence; investigate systematic cause |
| CF08 | unsupported claim as supported | answer asserts source/treatise/commentary support the cited passage does not provide | stop answer-acceptance path; repair claim/evidence contract |
| CF09 | rights/data-boundary violation | source/glossary/rendering bytes cross a boundary not cleared by the rights matrix/provider terms | stop processing immediately; contain/delete as required and review incident |
| CF10 | evidence-export violation | packet redistributes text beyond the cleared excerpt/export rule | stop export; repair packet policy |
| CF11 | privacy/retention violation | participant/private evaluation data retained, exposed or reused outside consented procedure | stop pilot processing; follow deletion/incident procedure |
| CF12 | execution/spend-bound violation | hidden retry, call/byte/time/candidate ceiling breach, or unapproved spend/provider route | stop execution; boundary must be enforced before resuming |
| CF13 | false absence/exhaustiveness claim | retrieval failure, timeout, partial arm or bounded scope stated as proof no relevant text exists | stop affected answer/refusal path; expose scope/search limitation |
| CF14 | provenance/traceability loss | evidence cannot be traced to the same source release/address/hash and role after presentation/export | stop acceptance/export path; restore provenance |
| CF15 | source-data/control injection | source, commentary or glossary bytes are interpreted as instructions that change provider, tool, budget, policy, authority or control flow | stop processing; enforce structured data/control separation before resuming |

For CF07, an individual bad rendering is blocked immediately. It becomes a pilot-level
critical failure when the bad rendering was or would have been presented as accepted reader
evidence, used to support synthesis without the required safeguard, or reveals a systematic
path that cannot yet be bounded.

All critical findings require a durable case/evidence record, disposition and rerun after
correction. "Could not reproduce" is not closure unless the original condition and
candidate revision are accounted for.

# 4. Rehearsal contract

Rehearsal tests the **apparatus**, not user value. It runs before participant recruitment.

The exact work IDs/URNs must be instantiated only after `pilot_scope` is frozen so the
cases cannot accidentally point outside the release they claim to test.

## Required rehearsal slots

| ID | Required property | What the rehearsal must prove |
|---|---|---|
| R01 | exact attested technical term | precise deterministic expansion/retrieval survives with provenance |
| R02 | translator/text-scoped historical rendering | work scope survives planning and cannot become universal |
| R03 | related-but-not-equivalent trap | useful related candidate is never displayed/promoted as synonym |
| R04 | root passage with passage-aligned commentary | root/commentary distinction and exact alignment survive answer/evidence flow |
| R05 | treatise → commentary → subcommentary | two-hop typed lineage works without treating treatise as scripture |
| R06 | passage with no cleared human English | generated-reading layer remains distinct from Chinese evidence and synthesis |
| R07 | genuinely unsupported/out-of-scope question | explicit unsupported result without false absence claim |
| R08 | multiple legitimate source passages | evaluator accepts plural evidence; fusion does not force one proof-text |
| R09 | injected false/altered verification | CF01 is detected before acceptance |
| R10 | injected generated/human/source conflation | CF03 is detected before acceptance |
| R11 | injected topical/fabricated relation | CF05 is detected before acceptance |
| R12 | rights/export-sensitive payload | prohibited/provider/export path refuses before bytes cross the boundary |
| R13 | duplicate source hash plus failed call/retry request | successful result is reused; hidden retry cannot occur |
| R14 | candidate explosion | candidate/retrieval bounds refuse visibly rather than silently broadening |
| R15 | timeout or unavailable inference | timeout is failure/refusal, not miss/no-source claim; no hidden provider retry |
| R16 | injected source/glossary control instruction | source bytes remain untrusted data and cannot change provider/tool/budget/policy/authority behavior |

The first eight are representative mechanical/product cases. R09–R15 are adversarial
injections. A case may satisfy more than one slot only if every slot's expected assertions
are independently recorded; do not shrink the suite merely by relabeling one friendly
fixture many times.

## Rehearsal pass condition

The rehearsal passes only when:

- every required slot is instantiated against the exact accepted release/scope;
- every non-injected mechanical case meets its declared expected outcome;
- **every injected critical failure is detected/refused before acceptance**;
- no unresolved critical defect remains;
- every receipt records release, query plan, executed arms, bounds, evidence identities
  and generation metadata applicable to that case;
- all rights/export cases follow the current rights contract;
- no live/paid provider is invoked merely to prove the rehearsal harness; deterministic
  fake/local fixtures are used until an inference route is separately authorized; and
- once an inference route is separately authorized, its bounded source-bound quality sample
  satisfies the frozen translation rubric before `rehearsal_trust` becomes ready.

A rehearsal pass establishes only that these declared cases and safeguards behaved as
expected at the named revision/release. It does **not** establish participant task success,
market demand, exhaustive corpus coverage, general retrieval quality or translation quality
outside the evaluated passages.

Rehearsal cases **never enter the 24-task participant denominator** and must be excluded
from the held-out participant outcome calculations.

# 5. Preflight disposition after freezing this contract

This document plus `pilot_acceptance.json` is sufficient evidence to change three
bookkeeping gates from "not frozen" to **ready as specifications**:

- `execution_bounds`;
- `evaluation_rubric`;
- `critical_taxonomy`.

"Ready" for those gates means their policy artifact is frozen and reviewable. It does not
mean implementation enforces it, inference is authorized, a baseline exists or the pilot
may run. Those independent gates remain mandatory.

`rehearsal_trust` remains **blocked** because the exact cases have not been materialized
against a frozen pilot scope and have not executed.

`retrieval_baseline` remains **blocked** because held-out Chinese cases and per-arm
measurements have not been run against the accepted pilot release.

`pilot_scope`, `foundry_g0`, rights/provider/inference, evaluator and participant gates
remain governed by their own evidence.

## Next independent handoff

After this contract is accepted, the next independent pre-G0 task is to materialize and
freeze the exact Chinese pilot scope from an accepted release:

- exact 14 seed work IDs;
- allowed relation types and traversal depth;
- every expanded work ID;
- passage-alignment coverage;
- release/content identity; and
- denominator(s) used by evaluation.

That scope artifact can then instantiate R01–R16 and the held-out retrieval baseline
without changing this contract to fit the results.
