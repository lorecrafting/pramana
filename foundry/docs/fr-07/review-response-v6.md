# FR-07 v6 recovered review response

Date: 2026-09-19
Review: `review-v6.md`, SHA-256
`7151d544e1d64e757d75f33428e361d668c84356631b09fed1d3daeda491f35f`

The implementation owner accepts B1–B6 as blockers. The next candidate replaces the
repeated point fixes with shared retained-authority boundaries and executable regressions.
This response is not an acceptance verdict; renewed independent review is required.

## Disposition

- **B1/B6 — corrected.** Events now carry a schema-constrained projection carrier and an
  ordered partial index over `(projection_namespace, projection_entity_id, seq)`. Scoped
  projection validation streams only that entity's carriers through the shared reducer,
  verifies the retained projection is the final state and validates every carrier owner.
  A separate transaction-only scope validates an explicitly named intermediate carrier;
  completed live reads cannot use it. Tests cover the exact historic-row rewind and show
  that unrelated malformed event bytes are not retained or decoded by the scoped read.
- **B2 — corrected.** Command/input/result validation is one shared owner closure used by
  direct command reads, projection carriers and protected effect/ledger traversal. Global
  validation now rejects every orphan effect, and `Authority.read(:all)` runs SQLite's
  foreign-key check before content certification. Source backup therefore rejects and
  fences before destination publication. Tests reproduce missing-result projection and
  ledger dependencies plus the foreign-key-disabled orphan-effect trace.
- **B3 — corrected.** Revision-read syntax and decoded identities are normalized in
  `RecordCodec` for both commands and protected facts. Protected epochs and authorization
  identities require valid nonempty UTF-8. Command lookup validates its ID before reading
  authority. Struct read sets, malformed encoded keys, invalid UTF-8 epochs/identities and
  empty/invalid lookup IDs return typed nonfencing errors while the gateway remains ready
  and empty. Existing-ID lookup still precedes proposal and protected-fact validation.
- **B4 — corrected.** Archive staging uses exclusive creation. A temp created by the
  current operation is the only temp its failure path may remove. A preexisting regular
  temp is adopted only after exact digest verification and identity revalidation; foreign
  bytes are preserved and refused. Tests cover both foreign evidence and exact rerun
  evidence.
- **B5 — corrected.** `Database` derives one schema contract from the exact trusted DDL
  used for initialization. Validation compares complete `sqlite_schema` objects,
  `table_xinfo`, `table_list`, `foreign_key_list`, `index_list`, and `index_xinfo` for every
  table/index. This binds types, nullability, defaults, primary-key order, foreign keys,
  unique keys, index column order and the exact partial-index predicate without a second
  hand-maintained oracle. Tests reject the review's wrong-column/nonunique index, a
  unique-but-wrong partial predicate, and a same-column table rebuilt without its FK;
  backup destinations remain absent.

The credited shared projection reducer, 18 authority tables, streaming import evidence,
complete protected bundles and connection-scoped WAL xSync evidence remain intact. No
coordinator, CLI, live daemon, provider, credential, deployment or activation behavior was
changed.

## Executed implementation-owner evidence

Using pinned Elixir 1.20.3 / OTP 29.0.5 and fresh `/private/tmp` roots:

- `MIX_ENV=test mix compile --force --warnings-as-errors`: exit 0; 90 files.
- `mix test test/pramana_foundry/durable_store --seed 9137`: exit 0; 75 passed.
- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 9138`:
  exit 0; 88 passed.
- `mix test --seed 9139`: exit 2; 508 tests, one failure. The sole failure is the
  pre-existing projections benchmark mismatch when Python cannot import `tiktoken`; the
  durable-store and related acceptance tests pass in that run. This is an explicit
  non-FR-07 environment exclusion, not a full-suite pass.

FR-08, FR-15a, FR-17, FR-19 and FR-22 remain downstream and are not claimed here.
