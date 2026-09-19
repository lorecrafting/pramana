# Pilot derivation completion receipts

**Status:** implementation contract; no live pilot derivation is certified by this file.
**Scope:** durable completion evidence for quotation, relation and alignment derivations
consumed by the Chinese-pilot preflight.

## Receipt contract

Every non-dry write run records an append-only `derivation_runs` row binding the attempt
to its source bake, implementation version, exact scope/parameters, input digest, output
digest, counts and timestamps. Database triggers reject update or deletion of a receipt.

A receipt is `complete` only when all of these are true at the end of the run:

- the producer reports zero explicit or per-item failures;
- the recomputed input digest is unchanged from the start of the run; and
- the derived table contains exactly the number of rows the producer expected to leave
  for that derivation.

The last condition is intentionally stricter than "the command exited successfully."
Title/shared-text relations and commentary alignments are convergent writes, not wholesale
table replacements. A stale row from an older rule can therefore survive a successful
run. Such a run records a `partial` receipt instead of certifying the stale output.
The receipt mechanism does not delete that row automatically.

The output digest binds the receipt to the exact derived rows that were observed.
Any later mutation makes the receipt stale when the verifier recomputes that digest.

## Producers covered

The pilot requires current receipts for all four deterministic producers:

- `quotations_scan` — the quotation graph;
- `relations_title` — title-derived work relations;
- `relations_shared_text` — quotation-graph-derived work relations;
- `commentary_align` — passage-level commentary alignment.

Dry-runs and report-only executions do not create completion receipts. Scoped runs may
record useful evidence, but they do not satisfy the full-pilot requirement.

## Pilot acceptance

Run:

```sh
mix pramana.pilot.derivations --bake-id <source-bake-id>
```

The verifier accepts only clean, current receipts with the pilot's frozen full/default
shape:

- quotation scan: full CBETA-compatible scope at a 20-character minimum;
- title relations: full scope at the default three-character title floor;
- shared-text relations: full write scope at the default one-passage floor;
- commentary alignment: all eligible pairs at the current default windows/density floors.

Old implementation versions, changed inputs, changed outputs, output-count mismatches,
partial runs and narrower scopes are refused. A passing result is derivation-completion
evidence only; it does not make `pilot_scope` ready by itself.

## Non-goals

- no claim that a receipt proves scholarly correctness of a derived relation;
- no backfilling fake receipts from historical row counts;
- no provider/model call or participant activity;
- no automatic transition of `pilot_scope` to ready;
- no Foundry FR-07 changes;
- no destructive cleanup of existing derived rows merely to make receipts pass.
