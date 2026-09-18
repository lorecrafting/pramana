# Chinese pilot scope materialization

**Status:** planning draft; no live pilot scope is claimed by this file.
**Scope:** implement a deterministic, release-bound materializer for the Chinese-first pilot
without touching Foundry FR-07 or changing the blocked `pilot_scope` gate.

## Work plan

1. Reconstruct the current directed quotation-demand ranking from the live corpus using the
   repository's rule-72/73 graph semantics rather than copying historical top-ten IDs.
2. Resolve the four Āgama work IDs from live corpus/catalogue facts and combine them with
   the top-ten demand seeds without duplication.
3. Traverse only accepted `comments_on` / `subcommentary_of` work relations, preserving
   direction, method/confidence, seed ancestry and hop depth, never topical similarity.
4. Bound traversal by the frozen pilot acceptance ceiling and record every expanded work.
5. Census passage-level commentary alignment coverage for accepted scope relations.
6. Bind the materialized artifact to the explicitly selected release and refuse unstamped,
   drifted, legacy/incompatible or mismatched state rather than guessing.
7. Emit deterministic JSON with stable ordering, exact denominators, relation/alignment
   evidence, scope hash and generation metadata.
8. Add an independent validator and fixture-driven tests that prove determinism, duplicate
   handling, cycles, unsupported relations, stale release refusal and alignment counting.
9. Wire the command into documentation/testing guidance while leaving `pilot_scope`
   blocked until a live artifact is generated and reviewed.
10. Self-review, correct, adversarially review, correct, run exact-head validation, and mark
    Ready only if the final head is clean and green.

## Non-goals

- no hard-coded historical top-ten seed list;
- no claim that GitHub fixtures represent the live pilot corpus;
- no provider/model call or spend;
- no participant/evaluator activity;
- no mutation of corpus relations or alignments;
- no Foundry FR-07 changes;
- no automatic transition of `pilot_scope` to ready.
