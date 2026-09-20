# FR-08A protected-primitives candidate

Refrozen 2026-09-19 (Hawaii) after correcting the first critical review's B1–B9
blocker families. This candidate implements
the protected semantic boundary required before FR-08B and reports all seven executable
handoff capabilities passed. It does not perform the FR-08B all-ingress migration, launch
a provider or daemon, activate Git/deployment state, or claim FR-22 completion.

## Exact identity

- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Corrected protected core subject: `44a56be3b4854b7cd392215beef6e01f4f30097a`,
  tree `08aeb550ae5bf6b4c178ac8b933bcfc7e7d956df`.
- Loaded-code gate/evidence layer: `7d81b5bf634a85ad9a26632c3a9bc11fbe5380d5`.
- Isolated native-fixture path correction: `06d388f2e7683862e4f599cf21b639331f223c1e`.
- Branch/worktree: `repair/fr08a-protected-primitives`,
  `/private/tmp/pramana-fr08a`.

The frozen report is `fr08a-protected-report.txt`. It binds nine exercised modules by
compile-metadata source SHA-256 and loaded BEAM MD5, including Gateway, Database,
ProtectedPrimitives, Authority, Kernel, RecordCodec, Encoding, LegacyImport and the
handoff gate. Its fresh-BEAM negative control changes executable Gateway behavior while
leaving source unchanged and proves all seven capabilities become unavailable. The report
records 7 pass, 0 fail, 0 unavailable, `ready=true`; its SHA-256 is
`7d42a41e4baca03e6d5a44baf89f2f467da6ea6d5176bff4ba95329119feb14e`.

## Protected authority and migration

The existing `DurableStore.Gateway` remains the only owner and transaction boundary.
Capability-authenticated public semantic commands and bounded fact queries expose no SQL,
connection or table name. `protected_schema_version=1` is an additive layer over the
accepted SQL schema v1; an owner-locked migration creates and validates it atomically,
records `migration_fr08a_v1`, preserves legacy bytes and is idempotent on rerun. Migration
accepts only the exact accepted-v1 starting state and refuses future versions, partial
markers, missing protected rows and damaged already-migrated authority without repair.

The Authority registry, metadata allowlist and content validator evolve with the schema.
Legacy and root authority are explicit mutually exclusive Gateway modes: an existing
legacy authority store may continue through the accepted FR-07 route but cannot begin root
writes, while the first root command permanently retires productive legacy writes. Thus
one store never has two writable authority truths.
Recovery validates canonical blobs, command bindings, policy/control lineage, inbox
sequence/seal state, ledger conservation and tree relations, reservation aggregates and
effect/claim/receipt/lease relationships, exact column/state carriers, semantic owner and
request identities, operation/dimension binding and authenticated receipt provenance.

The bounded snapshot includes installation and repository identity, writer epoch,
SQL/protected/protocol/event/projection versions, domain/protected sequence frontiers,
per-fact revision frontiers and three typed pointer slots: accepted source, selected
deployment and healthy build. Those pointer producers honestly remain `absent`; FR-17 may
later add their authorized mutation path. Effects expose explicit ticket, attempt and
execution identities. Claims, reservations, receipts, leases, ledgers and effects have
semantic public queries suitable for the later FR-18A DTO/redaction layer. Effect facts
also bind assignment, role, phase generation, operation ordinal, predecessor, immutable
request ID, issuer/channel, profile and deadline.

## Acceptance matrix

| Area | Positive and hostile evidence |
|---|---|
| Idempotency | Same actor/ID/digest returns the original result before current CAS; changed actor or payload conflicts; root and domain command IDs cannot collide. |
| Complete CAS | Root derives the complete policy/control/ledger/reservation/lease/effect read set; missing members reject durably as incomplete and equal-key stale values reject durably as stale. |
| Inbox | Authenticated monotonic append, seal and late evidence are durable; a sealed result wins over a later exit and post-seal evidence cannot move the boundary. |
| Claims | Effect creation, claim, explicit quiescent epoch takeover, immediate pre-delivery issue and receipt settlement atomically bind current policy/control, current Gateway epoch, reservation, ledger and lease state. Control cancellation revokes unissued descendants; cancellation after issue retains named outstanding authority. |
| Receipts/leases | Exact retries are idempotent; conflicting receipt identity quarantines reconciliation without credit; unknown outcomes retain holds/leases; release requires terminal/proved-unused evidence and active resources are uniquely owned. |
| R5 ledger | Root grant, same-dimension parent-funded delegation, proposal-to-admission reservation, consumption, unused return, recursive close/reset and retired closed-generation refunds preserve `authorized = available + held + consumed + delegated + retired` and tree conservation. Closed generations cannot issue or refill; no child self-grant or implicit conversion exists. |
| Boundary/recovery | Domain proposals cannot forge protected namespaces or facts. Root payloads cannot choose derived balances/status. Malformed requests fail before history without fencing a healthy store. Missing/corrupt stores fail closed. Restart reconstructs state without issuing work. |

The maintained critical-correction tests additionally cover explicit epoch reclaim,
control cancellation, dimension/semantic identity bypasses, recursive closure, mutually
exclusive legacy/root modes, precommit rollback and postcommit lost-reply recovery. The
focused suite covers additive migration/reopen, accepted-v1 content preservation, root
pointer absence, semantic snapshot identity, restart after inbox boundaries and full
claim/receipt/lease/ledger settlement. The executable provider uses
only public Gateway and LegacyImport operations; its evidence strings are bounded SHA-256
receipts. A revision mismatch makes all seven capabilities unavailable.

## Verification

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 and canonical `/private/tmp` roots:

- warnings-as-errors compile: exit 0, 108 files;
- focused protected/correction tests at seed 9282: 9 passed;
- independent recovery probes at seed 9283: 7 passed;
- independently authored public probes: 9/12 pass, with the remaining three failing only
  because the corrected implementation durably rejects the unsafe operation at effect
  admission rather than at the probe's later expected step;
- native xSync fixture after its bounded dependency-path correction: 2 passed;
- full model-free suite at seed 9282: 571 passed, 1 optional Python/tiktoken recomputation
  excluded;
- canonical `ci/run.exs`: exit 0, 571 passed, 1 optional recomputation excluded; dependency
  policy, warnings-as-errors compile, formatting, escript and clean-source postflight all
  passed. Provenance SHA-256:
  `82c429e30479fd1a1a27bee5ec577b9573380ce0748360b8e68ca4785b4a3637`.

The earlier exit 139 was a test-fixture include-path defect: the fixture used a repository-
relative `deps/` path while CI deliberately isolates `MIX_DEPS_PATH`. It now resolves the
locked exqlite source through `Mix.Project.deps_path/0`; the native tests and canonical CI
both pass. This changes no runtime checkpoint, backup or FR-19A path.

## Candidate path manifest

This candidate record is excluded to avoid a recursive self-hash.

```text
7d42a41e4baca03e6d5a44baf89f2f467da6ea6d5176bff4ba95329119feb14e  foundry/docs/fr-08/fr08a-protected-report.txt
d0b94ba108f8a1be0b3c17db4478bcbe25783991ceb17bc5ca3bb8edd886d99c  foundry/lib/pramana_foundry/durable_store/authority.ex
bf21cc2dc37b58cdec0de191025a7753529fc08d66b887f15331d8bdf026e464  foundry/lib/pramana_foundry/durable_store/database.ex
e60158b2f95ace9c1f143f3a9b8a12d8c6cf08ca279bbe7c90ced6b955793d1e  foundry/lib/pramana_foundry/durable_store/gateway.ex
f08d975d1ce5f7d12352d2de0b5d20ef9cf261c0afe78666f350f64426e88bf7  foundry/lib/pramana_foundry/durable_store/protected_primitives.ex
9849e931729c4bc685696d628dcb959a5622c3f7578915261022a770a5b23fbc  foundry/lib/pramana_foundry/repair/fr08a_protected_boundary.ex
a78f590a4692ec8bd7e7999ab1d26d9dd776a6e319d35c3cefeb6ba416448965  foundry/test/pramana_foundry/durable_store/protected_primitives_test.exs
2c077d8de958f1d331a518798496ec6126b9a5580bba95031664ecd7f2fdfa3d  foundry/test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs
95c16a61d9ce79d5a246b72f6051c3a535cd2ba6b8bc47a5f6424646f83df124  foundry/test/pramana_foundry/durable_store/sync_fault_test.exs
b2b1ab0fb9eef9f158c3a376a6ae48010a91f6e5949952c4026f84fb4f1cf058  foundry/test/pramana_foundry/repair/fr08a_protected_boundary_test.exs
a680b6f036515f673fabb248cb7fdaeb089041db633f08be053825ac84ebf527  foundry/test/support/fr08a_identity_negative_fixture.exs
```

Independent Astra-high critical review is required before integration. FR-08B must not
start from this branch before that review and integration complete.
