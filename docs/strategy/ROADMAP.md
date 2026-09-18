# Strategic roadmap and candidate initiatives

[Strategy overview](../PRODUCT_STRATEGY.md) · [Pilot charter](PILOT_CHARTER.md) · [Decisions](DECISIONS.md)
**Status:** proposed sequencing, not a scheduled or admitted backlog.

## How to read this roadmap

H0–H4 are strategic horizons. G0–G4 are decision gates, not replacements for existing
engineering phases or FR acceptance. Initiative IDs below are stable planning
handles; they are **not tickets**. Dates, staffing, estimates and budget grants are
intentionally uncommitted. Before implementation, reconcile each candidate against
current PLAN, repair evidence, open PRs and source.

## H0 / G0 — clear the repair boundary

**Owner:** the existing repair owner/operator. **Entry:** current repair process.
**Exit:** FR-22's exact lifecycle and closure evidence, with mandatory obligations
met and remaining unsupported scope explicit. Any waiver requires the governing
process, not this strategy. A component test, design approval or “all green” board
cannot substitute. [FR-22](../../foundry/docs/REPAIR-PLAN.md#fr-22--prove-full-lifecycle-and-reconcile-operating-docs)
owns the scenario details.

Strategy writing and non-operational discovery may proceed now. Do not use these
initiatives to dispatch product builds, alter live policy or divert active repair
ownership before this gate. Capture a fresh post-repair operating/source baseline
rather than assuming today's documented state is the eventual implementation.

## H1 / G1 — choose a customer task and establish baselines

**Work:** I-P1 plus baseline measurement for I-F1. **Dependencies:** G0 for execution;
no new infrastructure required for interviews or planning.

[The initial pilot charter](PILOT_CHARTER.md) now resolves D1–D7 before results are
seen: audience, recurring task, conditional four-Nikāya user scope, rights gate,
evaluation thresholds, rendering policy, privacy/export behavior, capacity and replay
promise. The charter authorizes no post-G0 implementation and no new cash spend.

Before execution, recheck the live source/corpus baseline, clear the selected human
rendering source for AI-assisted use, identify the qualified evaluators and record each
participant's current alternative. Actual retrieval limitations and operator time must be
measured locally; public benchmarks do not substitute.

**Exit:** after G0, the operator confirms that the charter's rights/evaluator prerequisites
are satisfied and admits the bounded pilot implementation. **Stop/reframe:** no recurring
need, no usable rights-cleared source access, no evaluator, or the proposed advantage
disappears in comparison with existing tools. Do not solve weak demand by adding more
models or corpora.

## H2 / G2 — deliver one complete evidence workflow

**Work:** I-P2 and I-P3 together as a thin vertical slice; a bounded I-F1 trial may
run alongside it. **Dependency:** G1.

Use the existing reader/MCP. Deliver scope selection, source inspection, honest
verification states and reusable evidence export. Add narrow synthesis only after
claim/evidence handling is tested. An externally shareable packet must respect
rights and privacy; do not promise exact historical replay before its retention
and identity design is exercised.

**Exit:** target users complete the chosen task without developer intervention;
qualified assessment meets preregistered usefulness/accuracy thresholds; critical
false-verification, source-role confusion and access-control defects are absent
from the release acceptance cases. Inspect failures and denominators, not only pass
rates. **Stop/iterate:** users cannot finish, cannot interpret the evidence badges,
or cannot distinguish source from generated material.

## H3 / G3 — demonstrate repeat value and selective compounding

**Work:** choose I-P4 or I-P5 based on observed friction, not both by default. Run
I-F2 only against a demonstrated engineering bottleneck. I-F3 may begin as a bounded
independent product experiment once G0 is met and an operator allocation is recorded;
it does not require commercial success for Pramāṇa.

**Exit:** users voluntarily return for new natural research tasks, reuse evidence
correctly, and report a meaningful advantage over their alternatives. Foundry
improvements show net effort savings within matched task classes without worsening
quality or authority controls. Record actual failures, abandonment and maintenance.
**Stop:** another feature does not resolve the documented reason people fail to return.

## H4 / G4 — expand by separate decisions

Pramāṇa may pursue I-P6 (cross-canon/deeper coverage) or I-P7 (collaboration) only
when demand, rights, data quality and evaluation justify it. Foundry may pursue
packaging beyond I-F3 or the I-F4 backend migration independently when their own
evidence is sufficient. Never bundle all expansions into one release obligation.

Each expansion requires an owner, beneficiary, measured baseline, bounded pilot,
permission/security review, operating cost and stop/rollback rule. Multi-user work
adds identity, access, privacy, conflict and support obligations; it is not “just
Presence.” Larger corpora add fidelity and maintenance obligations; they are not
merely a batch embedding job.

## Candidate initiatives

### I-P1 — pilot charter and research baseline

**Charter:** [initial evidence-first pilot](PILOT_CHARTER.md).

**Outcome:** the ask → answer → evidence → reuse job is tested across scholars,
practitioners/study leaders and ordinary readers in one conditional Pāli discourse scope,
without optimizing away the richer treatise/commentary hierarchy.
**Evidence:** consented task records, failed searches, source-specific rights clearance,
qualified evaluator review, segmented user outcomes and the charter's predeclared
thresholds. **Gate:** G1 after G0 permits execution. **Excludes:** declaring product-market
fit from interviews, prototype enthusiasm or a corpus count.

### I-P2 — evidence and trust contract

**Outcome:** readers can distinguish quotation match, source identity, rendering,
interpretation and search coverage. **Evidence:** adversarial cases for missing or
altered citations, existence-only results, no recognized citations, wrong scope,
wrong source role, generated renderings and state drift. **Dependencies:** G1 and
current guard/release inspection. **Excludes:** using a hash as proof of truth or
claiming exact replay from a matching release stamp (including v2 content identity).

### I-P3 — scoped find/inspect/export experience

**Outcome:** one usable end-to-end workflow in the current reader and relevant API.
**Evidence:** observed task completion, keyboard/mobile/script readability checks,
correct source context and permitted export round-trips. **Dependencies:** I-P2's
contract, chosen source scope and G1. **Excludes:** a new reader framework, automatic
three-canon agents or every citation style at launch.

### I-P4 — commentary and terminology depth

**Outcome:** the selected users can follow supported explanatory relationships and
terminology without conflating source roles. **Evidence:** expert-reviewed edge
fixtures, ambiguous/missing endpoints, directional uncertainty, cycle/depth bounds
and observed benefit on the pilot tasks. **Dependencies:** G2 and adequate relation
coverage. **Excludes:** a new graph database or role-based inference of historical influence.

### I-P5 — private research continuity

**Outcome:** users resume and reuse research without losing provenance or privacy.
**Evidence:** access isolation, export/deletion behavior, cited-state drift warning,
and repeat-use improvement. **Dependencies:** G2 and approved privacy/retention
contract. **Excludes:** storing personal notes in the canonical source layer or
sharing a Foundry engineering-memory backend.

### I-P6 — evidence-led retrieval and coverage expansion

**Outcome:** a named group of previously unsuccessful tasks becomes reliably usable.
**Evidence:** held-out, isolated comparisons for a selected model/dataset/parallel
feature; fidelity and permissions for new sources; rollback and operating cost.
**Dependencies:** G3 for broad product expansion; bounded prerequisite experiments
may be approved earlier only when needed for the chosen pilot. **Excludes:** buying
GPU capacity or adding OCR because an announcement or public benchmark looks promising.

### I-P7 — collaborative scholarship pilot

**Outcome:** a real team gains from shared evidence review without losing attribution.
**Evidence:** named participating team, access/sharing model, conflict handling,
review attribution, private-input protections and repeat collaborative use.
**Dependencies:** G3, privacy controls and explicit partner requirements.
**Excludes:** assuming 84000 or any institution is a partner or endorses the system.

### I-F1 — task context and compact evidence

**Outcome:** agents resume and finish bounded work with less operator intervention.
**Evidence:** context-reset/restart cases, evidence rehydration, changed-file cache
invalidation, honest idle states and matched-task effort comparison.
**Dependencies:** G0 and accepted state/receipt interfaces. **Excludes:** another
state store, giant mandatory prompt or a fixed tiny context cap that drops constraints.

### I-F2 — one tooling/quality improvement at a time

**Outcome:** reduce an observed class of rework. **Evidence:** representative tasks,
false-positive and maintenance cost, full diffs, failure/no-op cases and rollback.
**Dependencies:** G0 plus a measured bottleneck. **Excludes:** bulk adoption of AST,
lint, replay, gateway and orchestration packages as one “ecosystem upgrade.”

### I-F3 — second-repository portability

**Outcome:** Foundry works on another approved project without Pramāṇa dependencies.
**Evidence:** separate setup/commands, accepted changes, recovery, operator effort,
support burden and owner feedback. **Dependencies:** G0, a bounded allocation and
separate project-scope authorization under the governing contract.
**Excludes:** multi-tenancy, broader privileges or assumed demand from one successful demo.

### I-F4 — future session-backend conformance

**Outcome:** evaluate a reversible Superlogical integration when a usable interface
exists. **Evidence:** installed backend tests against [the Foundry requirements](FOUNDRY.md#portability-and-the-superlogical-option),
including headless behavior and rollback. **Dependencies:** G0, actual availability
and approved interface/security scope. **Excludes:** treating roadmap promises as
Herdr parity or making Pramāṇa delivery depend on the migration.

## Prioritization and formal-roadmap handoff

Mandatory safety, fidelity, access and acceptance defects take precedence. Among
optional candidates, prefer the smallest work that resolves a measured bottleneck
in the chosen user job or Foundry's delivery. Compare expected benefit, confidence,
review/support effort, dependencies and reversibility; do not invent numeric RICE
scores without inputs. Limit work in progress to the operator's actual capacity.

After each gate, use [the planning process](DECISIONS.md#from-strategy-to-a-ticket)
to update PLAN and the formal ROADMAP. Carry forward existing SAT/coverage blockers,
rejected experiments and isolation constraints; do not reset history or restart
completed phases because the strategic horizon labels are new.
