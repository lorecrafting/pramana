# Decision register and planning handoff

[Strategy overview](../PRODUCT_STRATEGY.md) · [Candidate initiatives](ROADMAP.md)
**Status:** D1–D7 are resolved for the initial pilot by [the pilot charter](PILOT_CHARTER.md); D8–D10 remain open. No implementation ticket is admitted before G0.

## Authority and decision types

**Constraints** come from the user, accepted repository invariants and Foundry's
repair/workflow contract. **Recommendations** are this strategy's proposed choices.
**Hypotheses** need evidence. **Deferred options** are not commitments. A strategy PR
approves documentation only; a task admission, spending grant, deployment or change
to the protected root still requires its applicable authorization.

Do not promote the original notebook's “adopted,” “active,” or “production standard”
labels to acceptance evidence. Conversely, do not remove agreed autonomous kernel
repair merely because some untrusted code needs a protected verifier.

## Blocking and expansion decisions

| ID | Decision / recommended default | Owner role | Required before |
|---|---|---|---|
| D1 | **Resolved:** one shared ask → answer → evidence → reuse job for scholars, practitioners/study leaders and ordinary readers; evaluate each stratum separately | Product owner/operator | Pilot charter |
| D2 | **Resolved conditionally:** first user pilot targets the four main Pāli Nikāyas/discourse collection; source witness + human rendering need an operation-specific rights matrix before AI-assisted processing. If clearance fails, D2 reopens—no automatic canon/translation/generated-English fallback | Product owner with qualified evaluator | Pilot execution |
| D3 | **Resolved:** 6–8 partner design, ≥24 eligible tasks with ≥6 per user stratum, preregistered trust/task/time/reuse thresholds frozen at first participant task, 40 operator-hour iteration cap, and no new cash spend authorized by the charter | Operator and evaluation owner | Pilot execution |
| D4 | **Resolved:** original witness + rights-cleared attributed human rendering for evidence; generated synthesis may explain but generated translation is not reader evidence; optional AI reading aid is off by default | Product owner and rights/partner reviewer | User-facing rendering/provider processing |
| D5 | **Resolved:** no persistent notebook required; minimal non-content telemetry by default, explicit opt-in study retention, local/user-controlled evidence export, and rights-aware excerpt handling | Product owner and implementation owner | Pilot implementation |
| D6 | **Resolved:** before G0 only non-operational discovery; after G0 one Pramāṇa product slice plus at most one bounded Foundry improvement; no second-repository pilot during the first user pilot | Operator | H1 execution |
| D7 | **Resolved:** no exact historical replay promise for the first pilot; carry source/release identity and report explicit drift/unavailability | Product owner and architecture reviewer | I-P2/I-P3 export contract |
| D8 | Decide which distribution/sustainability option deserves a real pilot; no prices or revenue assumptions are locked | Product owner/operator | Hosting or commercialization |
| D9 | Select a second repository, success criteria and explicitly authorized project scope for Foundry portability | Operator and that repository's owner | I-F3 |
| D10 | Decide a session-backend cutover only after actual conformance; Superlogical remains a future candidate | Operator and protected-boundary reviewer | I-F4 activation |

These are roles to assign, not invented team members. D1–D7 were resolved together in
[the pilot charter](PILOT_CHARTER.md); revising one of those decisions should amend the
charter and this register rather than creating a parallel mini-roadmap.
A change to the current manual paid-provider rule requires separate authenticated
steering, not merely D3 or adoption of provider-neutral docs.

## From strategy to a ticket

Use this sequence when product implementation becomes eligible:

1. Confirm G0 and read the current repair closure/limitations. Reinspect relevant
   source and pending work; strategy snapshots cannot prove the live state.
2. Choose one initiative and state its user outcome. Search PLAN, the repair backlog,
   existing PRs and rejected experiments for overlap. Reuse completed capability;
   create only the missing change. Do not renumber or reset the old engineering phases.
3. Write a short initiative brief: hypothesis, baseline, scope/non-goals, dependencies,
   risk, evaluator, measurable exit/stop conditions and operator-approved effort limit.
4. Split into independently testable tickets with explicit ownership and interface
   boundaries. Already specified work can use the existing admission path; ambiguous
   objectives use the existing PM process, not a second planner implementation.
5. Update the owned PLAN sections and the formal ROADMAP with initiative links,
   dependencies and supersessions in the same reviewed change. Then admit only the
   ready ticket through the existing workflow.

A ticket should carry this contract, adapted to the actual schema rather than
inventing executable fields or commands:

```text
Strategic initiative and user outcome:
Current baseline and missing behavior:
Scope, non-goals, exact owned paths/interfaces:
Dependencies and acceptance evidence:
Data/source/model permissions and environment:
Deliverable and exact-candidate verification:
Quality, cost and performance thresholds:
Effort/resource authorization and stop/escalation conditions:
Rollback or safe non-success outcome:
Operator decision reference and accountable owner:
```

Tests should establish actual intended work, not only a successful exit code.
A task may end blocked, cancelled or budget-exhausted without pretending it passed.
A safe default may resolve a reversible implementation detail; uncertainty about
scope, authority, spending, source rights or interpretation is not resolved by
instructing an unattended model to ignore it.

## Risks that change investment decisions

| Risk | Response / evidence owner |
|---|---|
| Foundry consumes all product capacity | Operator enforces bounded improvement trials and reviews net effort saved |
| Users trust a badge beyond what was checked | I-P2's evidence contract and evaluator's adversarial comprehension cases |
| Narrow pilot lacks sufficient relevant material | D2 task/coverage review; change scope rather than hide missing results |
| Existing archives or generic tools already satisfy the job | I-P1 comparative observation; stop or redefine differentiation |
| Generated text or source reuse violates partner expectations | D4/D5 review before processing, display or sharing; do not claim endorsement |
| Cross-canon comparison collapses real differences | Defer automatic synthesis; explicit scope, source roles and independent evaluation |
| A dependency promises savings but adds maintenance or authority risk | One-mechanism experiment, known owner, fixed budget and reversal path |
| Self-improvement corrupts rules or evidence | Accepted protected verifier, scoped promotion and traceable supersession |
| Repeat use or willingness to support never appears | Do not expand hosting/features solely to justify sunk costs |
| Another session changes the implementation baseline | Reconcile at ticket elaboration and before merging shared plans |

## Review prompt and maintenance

A future reviewer should answer: What user decision improves? Which claims are
constraints, recommendations or hypotheses? What could falsify the bet? Are source
rights and authority boundaries preserved? Is the next slice smaller than the
architecture it replaces? Are independent evidence and a safe stop defined?

Write new research into [RESEARCH](RESEARCH.md) with an attributable source and
proposed disposition. Change the owning strategy section through a recorded decision;
do not append a new miniature product roadmap after it. Keep historical wording in
Git and [the reconciliation](RECONCILIATION.md), not in parallel current policies.
