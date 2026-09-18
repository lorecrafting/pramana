# Chinese pilot acceptance and rehearsal contract

**Status:** planning draft; no pilot execution or provider use is authorized by this file.
**Scope:** freeze the Chinese-first pilot's evaluation protocol, execution bounds,
critical-failure taxonomy and rehearsal contract without touching active Foundry FR-07 work.

## Work plan

1. Inventory current pilot thresholds, retrieval/translation limits and trust invariants.
2. Define hard per-task execution ceilings and fail-closed behavior independent of provider choice.
3. Freeze evaluation rubrics for retrieval, query expansion, generated reading translation,
answer support, source-role fidelity, evidence reuse and ordinary-user comprehension.
4. Define a critical-failure taxonomy whose failures override aggregate scores.
5. Define a committed rehearsal contract and fixtures that test mechanics but never count
toward the participant-pilot denominator.
6. Update the preflight manifest only where the new artifacts genuinely satisfy a gate.
7. Self-review, correct findings, adversarially attack the contract, correct again, then
run exact-head validation and record the verdict in the PR.

## Non-goals

- no Foundry FR-07 implementation changes;
- no live retrieval/model/provider execution;
- no provider selection or spending authority;
- no claim that rehearsal has passed merely because the rehearsal contract is frozen;
- no exact pilot-scope materialization in this PR.
