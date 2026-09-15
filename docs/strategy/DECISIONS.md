# Decision register and planning handoff

[Strategy overview](../PRODUCT_STRATEGY.md) · [Candidate initiatives](ROADMAP.md)
**Status:** recommendations awaiting operator decisions; no tickets admitted.

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
| D1 | Accept or revise the initial teacher/writer/study-leader audience and recurring job | Product owner/operator | G1 charter |
| D2 | Select one pilot canon/collection using task coverage, human renderings, rights and reviewer availability; no canon is preselected here | Product owner with qualified evaluator | G1 charter |
| D3 | Approve proposed quality/time/cost thresholds, evaluation cohort and effort cap | Operator and evaluation owner | Any pilot implementation or experiment |
| D4 | Use attributed human renderings by default; decide whether any generated reading aid is allowed in this pilot and by its partners | Product owner and rights/partner reviewer | User-facing rendering or provider processing |
| D5 | Approve a concrete storage/retention/export policy for evidence packets and private research | Product owner and implementation owner | Persistent notebooks or public sharing |
| D6 | Allocate capacity between one Pramāṇa delivery slice, bounded Foundry improvement and a possible second-repository pilot | Operator | H1 execution and later reallocations |
| D7 | Decide whether exact historical replay is necessary for the initial job; otherwise promise inspectable receipts with explicit drift/unavailability | Product owner and architecture reviewer | I-P2/I-P3 export contract |
| D8 | Decide which distribution/sustainability option deserves a real pilot; no prices or revenue assumptions are locked | Product owner/operator | Hosting or commercialization |
| D9 | Select a second repository, success criteria and explicitly authorized project scope for Foundry portability | Operator and that repository's owner | I-F3 |
| D10 | Decide a session-backend cutover only after actual conformance; Superlogical remains a future candidate | Operator and protected-boundary reviewer | I-F4 activation |

These are roles to assign, not invented team members. D1–D7 can be resolved in one
pilot charter; they need not become ten meetings or a new governance service.
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
