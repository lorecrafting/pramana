# Chinese pilot rights and data-flow review

**Status:** research in progress; no rights gate is cleared by this planning commit.
**Scope:** product-policy and architecture review for the bounded Chinese-first pilot. This is not legal advice.

## Objective

Record, source by source and operation by operation, what the pilot may do, what is
prohibited, what needs permission, and what remains unresolved. Keep copyright/license
evidence separate from upstream stakeholder norms and from Pramāṇa's own conservative
product-policy choices.

## Research plan

1. Inspect the exact repository source registry and pilot data paths for CBETA, DILA
   glossary resources, existing human English renderings, and the generated-English
   Chinese retrieval tranche.
2. Verify current primary/upstream terms for each underlying resource; do not generalize
   a portal-wide or repository-wide license to a more specific edition or glossary.
3. Build an operation-specific matrix covering storage, indexing, embeddings/derived
   retrieval artifacts, query expansion, external-model processing, local-model
   processing, display, evidence-packet copying, evaluation retention, redistribution,
   and commercial/non-commercial implications.
4. Derive a fail-closed data-flow decision tree and provider-review boundary.
5. Update pilot strategy/preflight evidence only where the research actually supports a
   change. A more precise blocked gate is an acceptable result.
6. Self-review and adversarially attack the clearance assumptions before exact-head
   validation.

## Non-goals

- no Foundry FR-07 implementation changes;
- no provider/model calls or provider authorization;
- no corpus substitution when a source fails clearance;
- no readiness claim for unrelated pilot gates.
