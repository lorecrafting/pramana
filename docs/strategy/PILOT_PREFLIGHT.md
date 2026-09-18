# Pramāṇa pilot preflight

**Status:** implementation-plan checkpoint; no pilot execution authorized.
**Base:** `6887cc15457a0bcb555914874173b6a35488da3f`
**Depends on:** [pilot charter](PILOT_CHARTER.md), Foundry G0/FR-22, source-specific rights clearance.

## Objective

Turn the pilot charter's remaining prerequisites into explicit, reviewable artifacts so a
future implementation cannot quietly improvise source permissions, evaluation procedures,
or readiness.

This PR will produce:

1. an operation-specific rights matrix for the proposed four-Nikāya inputs;
2. an alternative-source survey for human English renderings if the preferred source is
   not cleared for the intended AI-assisted workflow;
3. an evaluator/task protocol for the 6–8 partner, ≥24-task feasibility study;
4. a fail-closed readiness checklist/gate that cannot report ready until G0, rights,
   evaluator, source identity, inference authorization and baseline prerequisites are
   satisfied.

## Boundaries

- No participant recruitment or pilot execution.
- No provider/model calls or new spending authorization.
- No source ingest, embedding rebuild, corpus mutation or deployment.
- No interpretation of copyright/licence terms as legal advice.
- A permissive copyright licence and a stakeholder's AI-use request are recorded as
  distinct considerations rather than silently collapsed.
- Natural participant questions remain natural; this PR may define task classes and
  rehearsal cases but must not prewrite the pilot's task corpus.

## Review workflow

Plan → primary-source verification → implementation → self-review → corrections →
adversarial review → corrections → exact-head documentation/CI validation.
