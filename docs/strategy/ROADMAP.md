# Strategic roadmap and candidate initiatives

[Strategy overview](../PRODUCT_STRATEGY.md) · [Pilot charter](PILOT_CHARTER.md) · [participant protocol](PILOT_PARTICIPANTS.md) · [Decisions](DECISIONS.md)
**Status:** proposed sequencing, not a scheduled or admitted backlog.

## How to read this roadmap

H1–H4 are strategic horizons. G1–G4 are decision gates, not replacements for existing
engineering phases. The former Foundry H0/G0 gate is retired for Pramāṇa.
Initiative IDs below are stable planning
handles; they are **not tickets**. Dates, staffing, estimates and budget grants are
intentionally uncommitted. Before implementation, reconcile each candidate against
current PLAN, open PRs, the live source and Pramāṇa's preflight evidence.

## H1 / G1 — choose a customer task and establish baselines

**Work:** I-P1 and its baseline measurement. No new infrastructure is required
for interviews or planning.

[The initial pilot charter](PILOT_CHARTER.md) now resolves D1–D7 before results are
seen: audience, recurring task, bounded Chinese commentary-rich user scope, bilingual retrieval
and reading-translation boundaries, rights gate, evaluation thresholds, privacy/export
behavior, capacity and replay promise. The charter authorizes no new cash spend.

Before execution, recheck the live source/corpus baseline, complete the charter/preflight operation-specific rights matrix for the selected CBETA
source, lexicons and model-processing route, identify the qualified Buddhist-Chinese
evaluators and follow the frozen [participant protocol](PILOT_PARTICIPANTS.md), including
each participant's current-alternative intake. Actual retrieval limitations and operator time must be
measured locally; public benchmarks do not substitute.

**Exit:** the operator confirms that the charter's rights/evaluator prerequisites
are satisfied and admits the bounded pilot implementation. **Stop/reframe:** no recurring
need, no usable rights-cleared source access, no evaluator, or the proposed advantage
disappears in comparison with existing tools. Do not solve weak demand by adding more
models or corpora.

## H2 / G2 — deliver one complete evidence workflow

**Work:** I-P2 and I-P3 together as a thin vertical slice. **Dependency:** G1.

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

**Work:** choose I-P4 or I-P5 based on observed friction, not both by default.
Try a workflow improvement only against a demonstrated engineering bottleneck.

**Exit:** users voluntarily return for new natural research tasks, reuse evidence
correctly, and report a meaningful advantage over their alternatives. Workflow
improvements show net effort savings within matched task classes without worsening
quality or authority controls. Record actual failures, abandonment and maintenance.
**Stop:** another feature does not resolve the documented reason people fail to return.

## H4 / G4 — expand by separate decisions

Pramāṇa may pursue I-P6 (cross-canon/deeper coverage) or I-P7 (collaboration) only
when demand, rights, data quality and evaluation justify it. Never bundle all
expansions into one release obligation.

Each expansion requires an owner, beneficiary, measured baseline, bounded pilot,
permission/security review, operating cost and stop/rollback rule. Multi-user work
adds identity, access, privacy, conflict and support obligations; it is not “just
Presence.” Larger corpora add fidelity and maintenance obligations; they are not
merely a batch embedding job.

## Candidate initiatives

### I-P1 — pilot charter and research baseline

**Charter:** [initial evidence-first pilot](PILOT_CHARTER.md).

**Outcome:** the ask → answer → evidence → explanation → reuse job is tested across
scholars, practitioners/study leaders and ordinary readers in one bounded Chinese scope
that includes actual treatise/commentary/subcommentary neighborhoods.
**Evidence:** consented task records, failed searches, source-specific rights clearance,
qualified evaluator review, segmented user outcomes and the charter's predeclared
thresholds. **Gate:** G1 admits bounded implementation after the relevant rights,
scope and evaluator conditions clear; participant tasks require full preflight.
**Excludes:** declaring product-market
fit from interviews, prototype enthusiasm or a corpus count.

### I-P2 — evidence and trust contract

**Outcome:** readers can distinguish quotation match, source identity, rendering,
interpretation and search coverage, including the first pilot's required source,
treatise, commentary and subcommentary roles. **Evidence:** adversarial cases for missing or
altered citations, existence-only results, no recognized citations, wrong scope,
wrong source role, generated renderings and state drift. **Dependencies:** G1 and
current guard/release inspection. **Excludes:** using a hash as proof of truth or
claiming exact replay from a matching release stamp (including v2 content identity).

### I-P3 — scoped find/inspect/export experience

**Outcome:** one usable end-to-end workflow in the current reader and relevant API,
including typed commentary access and terminology needed for the first Chinese pilot.
**Evidence:** observed task completion, keyboard/mobile/script readability checks,
correct source context and permitted export round-trips. **Dependencies:** I-P2's
contract, chosen source scope and G1. **Excludes:** a new reader framework, automatic
three-canon agents or every citation style at launch.

### I-P4 — commentary and terminology improvements after the pilot

**Outcome:** improve explanatory relationships and terminology beyond the first pilot's
required core. **Evidence:** expert-reviewed edge
fixtures, ambiguous/missing endpoints, directional uncertainty, cycle/depth bounds
and observed benefit on the pilot tasks. **Dependencies:** G2 and adequate relation
coverage. **Excludes:** a new graph database or role-based inference of historical influence.

### I-P5 — private research continuity

**Outcome:** users resume and reuse research without losing provenance or privacy.
**Evidence:** access isolation, export/deletion behavior, cited-state drift warning,
and repeat-use improvement. **Dependencies:** G2 and approved privacy/retention
contract. **Excludes:** storing personal notes in the canonical source layer or
sharing them with an agent workflow.

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

## Prioritization and formal-roadmap handoff

Mandatory safety, fidelity, access and acceptance defects take precedence. Among
optional candidates, prefer the smallest work that resolves a measured bottleneck
in the chosen user job. Compare expected benefit, confidence,
review/support effort, dependencies and reversibility; do not invent numeric RICE
scores without inputs. Limit work in progress to the operator's actual capacity.

After each gate, use [the planning process](DECISIONS.md#from-strategy-to-a-ticket)
to update PLAN and the formal ROADMAP. Carry forward existing SAT/coverage blockers,
rejected experiments and isolation constraints; do not reset history or restart
completed phases because the strategic horizon labels are new.
