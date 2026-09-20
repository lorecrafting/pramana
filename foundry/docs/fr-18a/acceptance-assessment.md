# FR-18A acceptance assessment

Date: 2026-09-20

Status: **assessment proposing completion; awaiting independent acceptance check.
FR-18A is not marked complete by this document.**

Author: Claude Opus 5.

Assesses [FR-18A's scope and acceptance paragraph](../REPAIR-PLAN.md) clause by clause
against integrated evidence at `main` `9dd30c3fd1624ef74bf697bc78eb0fc4d10154ba`. Every
citation is to a maintained test at that revision, not to a review narrative.

## Scope clauses

FR-18A's scope is "the smallest canonical query/observation identity surface needed for
FR-09/15a trials and later activation".

| Scope clause | Evidence |
|---|---|
| ticket/attempt/execution/effect/control identity | `observations_test.exs:118` "identity correlation is canonical and secret-bearing payloads are not exposed"; `:288` "live protected effect facts preserve ticket through control identity" |
| source and freshness | `:103` "freshness is explicit and deterministic"; `:394` "public canonical quality requires bounded page source and nested schema correlation" |
| accepted versus deployed pointers | `observations.ex:12` declares `@pointer_kinds` as `accepted_source`, `selected_deployment`, `healthy_build`; `:259` "the live FR-08A source reports three distinct absent pointers" covers all three kinds; `:882` "pointer vocabulary matches absent, unavailable and present protected states" |
| unknown outcomes | `:589` "terminal protected state governs reconciled and quarantined outcomes"; the integrated B5b correction reports `unknown/reconciliation_required` for a valid non-start conflict |
| unavailable/corrupt distinct from empty healthy state | `:82` "healthy empty, unavailable and corrupt sources are distinct"; `:466` "a missing live store is unavailable, never healthy empty"; `:475` "live corrupt reopen, unauthorized capability and dead source stay distinct"; `:535` "physical SQLite corruption is corrupt while raw availability failures remain unavailable" |

## Acceptance clauses

| Acceptance clause | Evidence |
|---|---|
| Show supported state and explicit unknown/unavailable/corrupt outcomes | The four distinctness tests above, plus `:589` and `:846` "malformed versions and execution fields cannot be canonical" |
| Without projection-manufactured health | `:466` and `:535` establish that an absent or physically corrupt store cannot present as healthy; the integrated B5c correction binds every emitted settlement scalar three ways, so a mutated projection cannot present as canonical |
| Bind every observation to revision/source/quality | `:394` correlates bounded-response source, installation/repository/frontier and effect revision to the surrounding snapshot before assigning canonical quality; `:846` refuses canonical quality on malformed nested versions |
| Redact representative secrets | `:118`, `:685` "redaction covers live identities and source provenance", `:728` "redaction covers bounded relation, settlement and continuation envelopes" |
| A source inventory or schema declaration alone is not live/deployed truth | Every clause above is evidenced against a live Gateway-backed source, not a declaration. The bounded query executes inside the protected read transaction |

## Review lineage

Each slice was independently reviewed at its exact candidate, and no slice was integrated
on its author's assertion:

- Observation surface: independent BLOCKER, correction, then rereview PASS.
- Residual corruption classification: narrow rereview PASS.
- B5 bounded effect query: independent BLOCKER at `f88f2dc`, correction, then
  [rereview PASS](b5-correction-rereview.md) by Claude Opus 5, fresh session.
- Execution-summary coverage gap: closed at `cb136fa` with three real-store cases.

## Remaining limitations, explicitly not claimed

- FR-18A is the minimal honest observation surface. It does **not** repair the legacy
  producer chain, which is FR-18B's scope, including the recorded producer/schema split
  where AgentServer's lifecycle records do not satisfy the canonical command validator
  while Coordinator writes an EventLog-style shape.
- No board, telemetry or usage chain is claimed. No LLM usage observation exists.
- Nothing here establishes live deployment, activation, provider execution or FR-22
  lifecycle acceptance.
- Missing observation indexes remain a performance suggestion, not a schema change.

## Proposed disposition

FR-18A's scope and acceptance clauses are met by integrated, independently reviewed
evidence. This assessment proposes moving its row to complete.

It should not be moved on this document alone. An independent acceptance check should
verify the clause-to-evidence mapping above against the tests themselves — in particular
that each cited test establishes the clause it is cited for, rather than merely mentioning
the same words — before the status changes.
