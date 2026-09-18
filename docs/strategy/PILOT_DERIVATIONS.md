# Pilot derivation completion receipts

**Status:** planning draft; no live pilot derivation is certified by this file.
**Scope:** replace terminal-only evidence for quotation/relation/alignment derivations with
durable, immutable run receipts that can be reviewed by the Chinese pilot preflight.

## Work plan

1. Add an append-only `derivation_runs` record that binds one derivation attempt to:
   source bake, implementation/rule version, explicit scope/parameters, input digest,
   output digest, counts, timestamps and clean/partial status.
2. Keep scope honest: partial quotation scans, one-work alignment runs, dry-runs and
   report-only shared-text runs must never satisfy a full-pilot completion requirement.
3. Instrument the four writes that feed the pilot scope:
   - quotation scan;
   - title-derived work relations;
   - shared-text work relations;
   - commentary passage alignment.
4. Record per-item failures instead of allowing a successful process exit to masquerade as
   clean completion. A receipt may describe a partial run, but pilot verification accepts
   only clean coverage.
5. Add a deterministic verifier that asks whether the current source bake has the complete
   receipt set required by the pilot and exposes exactly which receipt/evidence is missing.
6. Bind receipt validation to current database output digests so later mutation makes old
   completion evidence visibly stale instead of silently reusable.
7. Update the pilot scope/preflight runbook to use receipts as derivation-completion
   evidence while leaving `pilot_scope` blocked until a real live scope artifact is run
   and reviewed.
8. Add migration/schema/domain tests, task-level acceptance tests and failure/staleness
   cases.
9. Self-review, correct, adversarially review, correct, then run exact-head CI/container
   validation and mark Ready only if the final head is clean and green.

## Non-goals

- no claim that one receipt proves scholarly correctness of derived relations;
- no backfilling fake receipts from historical row counts;
- no provider/model call or participant activity;
- no automatic transition of `pilot_scope` to ready;
- no Foundry FR-07 changes;
- no destructive cleanup of existing derived rows merely to make receipts pass.
