# FR-08A protected-primitives candidate

Refrozen 2026-09-19 (Hawaii) after correcting the first critical review's B1–B9,
the independent rereview's R1–R6 and the fresh final review's F1–F3 blocker families.
This candidate implements
the protected semantic boundary required before FR-08B and reports all seven executable
handoff capabilities passed. It does not perform the FR-08B all-ingress migration, launch
a provider or daemon, activate Git/deployment state, or claim FR-22 completion.

## Exact identity

- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Final-review-corrected protected core subject: `e79a88a163202ef38cf32ea65ed348554a3dedc1`,
  tree `5afd76721c082c596ddd32898c46520a1f23d775`.
- Rebound loaded-code evidence: `408fd0d21d7ba8a07170809dab2a2f1e30c5d5b2`,
  tree `9e33ee71bca59c9df0767575b3cd0d1c42b25d35`.
- Earlier rereview-corrected core: `066e29e1b50535759730b64583876b466629195b`,
  tree `ca0339489e051f3c8ae6e0315bdd0139771b21de`.
- Bounded inherited format-debt identity correction: `8688b7a3f5079e4a2ed154d681f281f878003271`,
  tree `5d86c971eb1fe2179611705910f02abcf2146e56`.
- Earlier corrected core: `44a56be3b4854b7cd392215beef6e01f4f30097a`,
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
`7dbece07e252b5a7d45e07a48c87591b622f7c758e7fd1c0793af4a54f03f139`.

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
Ledger creation identity and units are reconstructed jointly from the authenticated
grant/delegation/reset request and its result; current authorization cannot exceed that
origin. Immutable effect issuer, assignment, generation, ordinal, predecessor, request
and admission fields are reconstructed from the originating authenticated command.
Claim writer epoch is reconstructed from the authenticated initial claim and linear
quiescent reclaim commands rather than trusted from mutually consistent rows.

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
| Claims | Effect creation, claim, explicit quiescent epoch takeover, immediate pre-delivery issue and receipt settlement atomically bind current policy/control, current Gateway epoch, reservation, ledger, lease and predecessor state. Control cancellation revokes unissued descendants; cancellation after issue retains named outstanding authority. Any ancestor in the complete owner chain that becomes unknown or reconciliation-required fences every later ordinal before claim or issue, while attributable terminal ancestry permits progress. |
| Receipts/leases | Exact retries are idempotent; globally reused or changed receipt observation identity quarantines durably without SQL fencing or credit; distinct observations reconcile the immutable request; unknown outcomes retain holds/leases; release requires terminal/proved-unused evidence and active resources are uniquely owned. |
| R5 ledger | Root grant, same-dimension parent-funded delegation, proposal-to-admission reservation, consumption, unused return, recursive close/reset and retired closed-generation refunds preserve `authorized = available + held + consumed + delegated + retired` and tree conservation. Mixed open/already-closed subtrees close idempotently. Closed generations cannot issue or refill; no child self-grant or implicit conversion exists. |
| Boundary/recovery | Domain proposals cannot forge protected namespaces or facts. Root payloads cannot choose derived balances/status. Malformed requests fail before history without fencing a healthy store. Missing/corrupt stores fail closed. Restart reconstructs state without issuing work. |

The maintained critical-correction tests additionally cover explicit epoch reclaim,
control cancellation, dimension/semantic identity bypasses, recursive closure, mutually
exclusive legacy/root modes, precommit rollback and postcommit lost-reply recovery. A
maintained wrapper executes all 22 independently authored final-review probes, covering
semantic-rejection rollback, derived phase/ordinal/policy identity, predecessor fencing,
complete owner-chain quarantine, authenticated ledger/effect/claim recovery provenance,
mandatory declared deadlines, receipt observation collision and mixed-subtree close.
The focused suite covers additive migration/reopen, accepted-v1 content preservation, root
pointer absence, semantic snapshot identity, restart after inbox boundaries and full
claim/receipt/lease/ledger settlement. The executable provider uses
only public Gateway and LegacyImport operations; its evidence strings are bounded SHA-256
receipts. A revision mismatch makes all seven capabilities unavailable.

## Verification

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 and canonical `/private/tmp` roots:

- warnings-as-errors compile: exit 0, 108 files;
- focused protected/correction tests: passed;
- independent recovery probes at seed 9283: 7 passed;
- independently authored final-review probes at seed 9302: 22 passed;
- native xSync fixture after its bounded dependency-path correction: 2 passed;
- full model-free suite at seed 9302: 572 passed, 1 optional Python/tiktoken recomputation
  excluded;
- canonical `ci/run.exs`: exit 0, 572 passed, 1 optional recomputation excluded; dependency
  policy, warnings-as-errors compile, formatting, escript and clean-source postflight all
  passed. All seven inherited format-debt paths matched their bounded current identities.
  Provenance SHA-256:
  `fd2aa2e1cbddf092a2afd0c9eb0dd998934368d1f27211902f88fc576fd8f70d`.

The first unchanged canonical invocation observed one unrelated live-process identity
race: the same PID changed transient state from `Rs` to `Ss` between consecutive reads;
all FR-08A and 571 other tests passed. An immediate unchanged isolated rerun produced the
passing provenance above with 572/572 model-free tests.

The earlier exit 139 was a test-fixture include-path defect: the fixture used a repository-
relative `deps/` path while CI deliberately isolates `MIX_DEPS_PATH`. It now resolves the
locked exqlite source through `Mix.Project.deps_path/0`; the native tests and canonical CI
both pass. This changes no runtime checkpoint, backup or FR-19A path.

## Candidate path manifest

This candidate record is excluded to avoid a recursive self-hash.

```text
7dbece07e252b5a7d45e07a48c87591b622f7c758e7fd1c0793af4a54f03f139  foundry/docs/fr-08/fr08a-protected-report.txt
fc3b6c7685a9a2743e84ed338551ce9aaa7aeed5ce1b0e2c270cd865d351ab99  foundry/ci/format_debt.exs
d0b94ba108f8a1be0b3c17db4478bcbe25783991ceb17bc5ca3bb8edd886d99c  foundry/lib/pramana_foundry/durable_store/authority.ex
bf21cc2dc37b58cdec0de191025a7753529fc08d66b887f15331d8bdf026e464  foundry/lib/pramana_foundry/durable_store/database.ex
e60158b2f95ace9c1f143f3a9b8a12d8c6cf08ca279bbe7c90ced6b955793d1e  foundry/lib/pramana_foundry/durable_store/gateway.ex
c1641774feaf9348ead1a2259d64541c44bc24038188f153eb0c1f5b0c05d460  foundry/lib/pramana_foundry/durable_store/protected_primitives.ex
584cbd54d058853314849ca7139ed07af2bcff0146778818b981e00157b3409e  foundry/lib/pramana_foundry/repair/fr08a_protected_boundary.ex
a78f590a4692ec8bd7e7999ab1d26d9dd776a6e319d35c3cefeb6ba416448965  foundry/test/pramana_foundry/durable_store/protected_primitives_test.exs
2c077d8de958f1d331a518798496ec6126b9a5580bba95031664ecd7f2fdfa3d  foundry/test/pramana_foundry/durable_store/fr08a_critical_corrections_test.exs
2d0c5e79fc59133da362c17980770c4a1425d1a8d593c5a63d473e12d9e879c7  foundry/test/pramana_foundry/durable_store/fr08a_rereview_matrix_test.exs
95c16a61d9ce79d5a246b72f6051c3a535cd2ba6b8bc47a5f6424646f83df124  foundry/test/pramana_foundry/durable_store/sync_fault_test.exs
db709821c7323bced4dd373d2611d130e2d26c449342a3735e12d2531cc3c238  foundry/test/pramana_foundry/repair/fr08a_protected_boundary_test.exs
a680b6f036515f673fabb248cb7fdaeb089041db633f08be053825ac84ebf527  foundry/test/support/fr08a_identity_negative_fixture.exs
04cd3821181cb003f237d8c25c8a955951570e864b1dddbd58c28ccd733f8f3f  foundry/docs/fr-08/fr08a-rereview-probes.exs
ba29f581504c44494777b7ec5128fbed8a6bf71049bfaa457ec8371079af3bc5  foundry/docs/fr-08/fr08a-final-review-probes.exs
```

Independent Astra-high critical review is required before integration. FR-08B must not
start from this branch before that review and integration complete.
