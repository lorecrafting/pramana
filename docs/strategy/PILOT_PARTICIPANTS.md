# Chinese pilot participant protocol and study data governance

**Status:** planning draft; no participant recruitment or data collection is authorized.
**Scope:** freeze the Chinese-first pilot's participant consent, study-record schema,
retention/deletion rules, privacy boundaries, withdrawal behavior and denominator handling.

## Work plan

1. Reconcile the charter's participant/privacy promises with the frozen acceptance contract.
2. Define what participants are told before a task and what requires explicit study consent.
3. Separate product-operation telemetry, participant study records, evaluator judgments and
   evidence packets so one purpose cannot silently authorize another.
4. Define pseudonymous identifiers, sensitive-question handling, retention/deletion,
   withdrawal, export and incident behavior.
5. Freeze a machine-readable participant/task/evaluator record contract, including
   current-alternative intake and outcome/denominator states.
6. Update the preflight manifest only if this artifact genuinely satisfies the
   `participant_protocol` specification gate.
7. Add dependency-free validation and Documentation CI coverage.
8. Self-review, correct, adversarially review, correct, then run exact-head validation and
   mark Ready only if the final candidate is green and mergeable.

## Non-goals

- no participant recruitment, outreach or consent collection;
- no collection or retention of real participant data;
- no claim that evaluators have been identified;
- no provider/model/inference authorization;
- no Foundry FR-07 changes;
- no exact live corpus-scope materialization.
