# Validation, economics and learning

[Strategy overview](../PRODUCT_STRATEGY.md) · [Roadmap gates](ROADMAP.md) · [Chinese pilot acceptance](PILOT_ACCEPTANCE.md) · [participant protocol](PILOT_PARTICIPANTS.md)
**Status:** proposed measurement plan. No new performance, demand or revenue results
were produced by this rewrite.

## Two scorecards, not one ambiguous efficiency number

### Pramāṇa

Primary outcome: **successful source-backed research tasks / eligible attempted
tasks**, reported by user job and source scope. A task succeeds when the user finds
adequate evidence, understands its source/rendering limitations and can correctly
reuse it; qualified review checks a sample against a predefined rubric. A click,
a generated answer or a green quotation badge alone does not count.

| Measure | Definition and use |
|---|---|
| Task success and failure reasons | Include failed, abandoned and unsupported attempts; separate navigation, coverage, retrieval and interpretation failures |
| Time to useful evidence / export | Median and tail for a fixed task class; record assistance and abandonment rather than timing only successes |
| Trust errors | False verified badges, misattribution, source/translation conflation, unsupported interpretive claims and overclaimed absence reported separately |
| Scope-aware retrieval | Relevant passages found for the chosen task, with available corpus/witness coverage and active retrieval arms |
| Repeat use | Users return on a later occasion with a new natural task; distinguish prompted study visits from voluntary return |
| Evidence reuse | Correct permitted export/citation or later reopening; do not equate copying text with correct understanding |
| Service burden | Per-task model/infrastructure cost, latency, operator/support time and failed/abandoned-task costs |

Canonical-source fidelity, quotation verification and interpretation quality need
different evaluators. Measure false acceptance as well as refusal. Show denominators,
unknowns and per-scope results; an average must not hide a nonfunctional canon.

### Foundry

Primary outcome: **accepted changes that remain acceptable through a declared
observation window / total operator hours**, within comparable task classes.
Operator hours include steering, review, intervention, rework and maintenance—not
just time spent pressing Approve. Declare the observation window before scoring.
Do not compare a typo fix and an architecture change as equivalent units.

Track autonomous eligible-task completion, correction/reopen rate, rollback and
escaped defects, time to evidence-backed acceptance, restart/recovery outcomes,
false completion/no-op reporting, and resource spend. For task classes where a
practical off-the-shelf software factory or workflow system exists, include that
alternative (or the operator's current manual/agent workflow) as a declared baseline;
custom Foundry infrastructure has not demonstrated value merely by completing the task.
An idle queue can be healthy; it contributes neither a fabricated success nor an
automatic operational failure. No denominator or no qualifying observations means
**insufficient evidence**, not infinite efficiency. The old “45 minutes of review means
zero efficiency” example was not a valid consequence of its formula.

Cost reporting separates cash spend, subscription capacity consumed or held,
infrastructure/storage and human effort. Subscriptions and local infrastructure are
not free merely because marginal cash billing is absent. Unknown usage remains
unknown and cannot relax the protected budget ledger.

## Pilot protocol

For the Chinese-first pilot, the execution ceilings, bilingual evaluation rubric, critical-failure taxonomy and rehearsal pass rules are frozen in [PILOT_ACCEPTANCE](PILOT_ACCEPTANCE.md); consent, retention/deletion, withdrawal, current-alternative intake and study denominator rules are frozen in [PILOT_PARTICIPANTS](PILOT_PARTICIPANTS.md); the charter owns participant-level thresholds. At G1, preregister the remaining live scope, current alternatives, evaluator identities and measured baselines before execution. A reasonable **proposed
study design** is 6–8 design partners doing several real tasks, followed by later
observation of voluntary use. This is a feasibility study, not a statistically
validated market-size or retention estimate. The operator can change the design
before the study; record changes rather than moving goals after results arrive.

Include a remembered quotation, a scoped teaching question, a commentary distinction,
a missing-source case and an ambiguous interpretation. Preserve legitimate multiple
answers. Blind evaluation where feasible and ask evaluators to inspect source context,
not merely agree with a reference wording. Recruit outside the builder's own habits.

The Chinese pilot's frozen critical taxonomy makes any known critical acceptance failure a stop/fix condition regardless of averages. The charter's usefulness/time/reuse thresholds remain separate. Zero observed failures is not proof of zero risk. Human scholarly assessment
and ordinary functional tests remain necessary even when a model reviewer agrees.

## Experiment contract

Each model, retrieval, context or tooling experiment records:

- Hypothesis, target failure class and smallest meaningful benefit; baseline and
  comparison arm; exact code, corpus, index, model, settings and policy identities.
- Held-out tasks split by source/work or another justified leakage boundary;
  independent evaluation, relevant existing rejected attempts and contamination risks.
- Equal scopes/budgets and isolated workspaces/data; actual repetitions and uncertainty,
  or an explicit exploratory label when the sample is too small for significance.
- Quality, latency, spend, operator time, failure/no-op and maintenance results;
  adoption threshold, termination condition and reversible deployment plan.

Do not compare moving indexes, reuse the test set for tuning, or declare a new
embedding superior from a different corpus/denominator. Public MITRA or memory
benchmarks identify candidates, not expected local gains. [Testing](../TESTING.md),
[proxy studies](../../pramana/docs/PROXIES.md) and PLAN's rejected experiments constrain interpretation.

For memory/context pilots, test missing or stale receipts, context reset, superseded
decisions and scope leakage—not just recall of a friendly example. For source graphs,
judge edge direction and evidential basis separately from finding a matching string.
For a backend migration, test the real installed interface; mocks cannot establish
provider behavior or platform availability.

## Foundry cross-workflow portability validation

"Role-agnostic" must be demonstrated, not inferred from configurable model-profile names.

After the active Foundry repair lifecycle is accepted, validate the proposed
[project workflow profile](../../foundry/docs/PROJECT-WORKFLOW-PROFILES.md) abstraction
with at least two materially different workloads under the same protected kernel.

### Arm A — software engineering

Representative flow:

```text
scoped developer
 -> deterministic project checks
 -> independent reviewer
 -> protected integration
```

The developer may receive an isolated checkout plus approved source/build/test tools.

### Arm B — typed Loka content authoring

Representative flow:

```text
world/quest builder
 -> Loka Builder API only
 -> Cartridge Lab/certification evidence
 -> semantic reviewer
 -> exact-hash release gate
```

The builder must not receive engine-source write or arbitrary shell authority merely
because the same model could act as an engine developer in another assignment.

Inject a missing-capability case. The builder must emit an escalation/proposal; it cannot
self-upgrade. If policy admits engine work, a separate engine-capability assignment with a
different grant performs it, receives its own checks/review, and the original content
candidate then resumes/rebases through its own gates.

### Required falsification cases

The portability pilot should deliberately test:

- a builder prompt explicitly instructed not to edit engine source while a hidden alternate
  path tries to do so; enforcement must deny the operation outside the prompt;
- a source developer trying to call a protected publication surface;
- a role attempting an ungranted API operation through both the normal tool and an
  alternate reachable tool/path;
- a project/workflow plan omitting a mandatory protected check;
- a child assignment requesting broader scope/budget than its parent;
- renamed roles/same model/same principal attempting to fake reviewer independence;
- context routing that withholds mandatory policy/evidence;
- escalation attempting to mutate the originating grant;
- stale ProjectProfile/workflow revisions;
- crash/restart/replay across handoff and escalation;
- useful positive completion in both workloads.

Success means the protected authority/evidence model stayed invariant while the
project-specific workflow, context and tool surfaces changed materially.

## Sustainability and distribution

Retain an open-source/self-hosted direction as recorded in the existing phase roadmap,
without asserting a licence grant that has not been checked. Keep code distribution,
source-text rights, translation rights, model terms and hosting rights distinct.
The initial pilot can use permitted data and manual support; no business model is
validated yet.

| Option | Test before committing | Main risk |
|---|---|---|
| Community-supported Pramāṇa | Recurring use, supporter motivation and actual hosting/support burden | Free use does not automatically fund maintenance |
| Institutional support or hosted workspace | A real institution's task, procurement constraints, data permissions and willingness to support/pay | Endorsement, rights or trust requirements may conflict with the proposed AI workflow |
| Developer/API access | A concrete integrating user and cost/reliability expectations | Maintaining another surface before the core job is useful |
| Foundry standalone support/package | Cross-project utility, then materially different workflow utility, setup/support burden and a distinct buyer | Internal software success may not generalize to other projects or workflow/tool surfaces |

Start distribution with consented design partners and useful evidence packets, not
paid acquisition or viral authenticity scores. Conduct exploratory willingness-to-pay
or support conversations after participants experience the workflow; do not infer
revenue from stated enthusiasm. No outreach, purchase or account setup is authorized
by this document.

Before hosting or charging, recheck relevant rights and terms, set a real operating
budget and retention policy, and identify an accountable support owner. For a
partner that rejects generated translation, offer an appropriately constrained
source/human-rendering workflow rather than treating a disclaimer as permission.

## Learning cadence

At each horizon gate, review observed tasks, failed searches, unsafe outcomes,
operator effort and external changes. Promote an essay-derived concept only when
it resolves a demonstrated need. Make a continue, change, stop or defer decision
with evidence and an owner; update the decision record rather than appending
another competing architecture section. Time-based reviews may be scheduled by the
operator, but this strategy creates no background jobs or automations.
