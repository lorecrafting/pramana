# FR-08A protected-primitives candidate

Frozen 2026-09-19 (Hawaii) for independent critical review. This candidate implements
the protected semantic boundary required before FR-08B and reports all seven executable
handoff capabilities passed. It does not perform the FR-08B all-ingress migration, launch
a provider or daemon, activate Git/deployment state, or claim FR-22 completion.

## Exact identity

- Baseline: `fa636fb592eacf4ebd31b72fa377b0a86a6d3e3e`.
- Protected core subject: `1e3a1ae60ada4e9634ffc20ccc4b68db149aa03d`,
  tree `964a1e756c1704f5e4f5d142680ec4e941b34e92`.
- Gate/provider layer: `64b011a0589fa93028951f82e6591a1e668cfdf1`,
  tree `047486de4a2711e5e9d4874d647647d7c58f95ee`.
- Historical-H0 evolution test: `b7484482ac1305eb47d81be2787fc9a836683339`,
  tree `b094fbc5f7cb44f14aa7fea5f6d352716b342014`.
- Branch/worktree: `repair/fr08a-protected-primitives`,
  `/private/tmp/pramana-fr08a`.

The frozen report is `fr08a-protected-report.txt`. It binds the four protected source
files by SHA-256 and reports 7 pass, 0 fail, 0 unavailable, `ready=true`.
Its SHA-256 is `2b57b3dcb1a23af102956dfc8bb073a4feceea9982dfe84bd531261c1ff82d79`.

## Protected authority and migration

The existing `DurableStore.Gateway` remains the only owner and transaction boundary.
Capability-authenticated public semantic commands and bounded fact queries expose no SQL,
connection or table name. `protected_schema_version=1` is an additive layer over the
accepted SQL schema v1; an owner-locked migration creates and validates it atomically,
records `migration_fr08a_v1`, preserves legacy bytes and is idempotent on rerun.

The Authority registry, metadata allowlist and content validator evolve with the schema.
Legacy empty authority-scaffolding tables remain compatibility-only; the `root_*` rows are
the sole mutable protected representation and are reached only through the Gateway.
Recovery validates canonical blobs, command bindings, policy/control lineage, inbox
sequence/seal state, ledger conservation and tree relations, reservation aggregates and
effect/claim/receipt/lease relationships.

The bounded snapshot includes installation and repository identity, writer epoch,
SQL/protected/protocol/event/projection versions, domain/protected sequence frontiers,
per-fact revision frontiers and three typed pointer slots: accepted source, selected
deployment and healthy build. Those pointer producers honestly remain `absent`; FR-17 may
later add their authorized mutation path. Effects expose explicit ticket, attempt and
execution identities. Claims, reservations, receipts, leases, ledgers and effects have
semantic public queries suitable for the later FR-18A DTO/redaction layer.

## Acceptance matrix

| Area | Positive and hostile evidence |
|---|---|
| Idempotency | Same actor/ID/digest returns the original result before current CAS; changed actor or payload conflicts; root and domain command IDs cannot collide. |
| Complete CAS | Root derives the complete policy/control/ledger/reservation/lease/effect read set; missing members reject durably as incomplete and equal-key stale values reject durably as stale. |
| Inbox | Authenticated monotonic append, seal and late evidence are durable; a sealed result wins over a later exit and post-seal evidence cannot move the boundary. |
| Claims | Effect creation, claim, immediate pre-delivery issue and receipt settlement atomically bind current policy/control, epoch, reservation, ledger and lease state. Cancellation after issue retains outstanding authority. |
| Receipts/leases | Exact retries are idempotent; conflicting receipt identity quarantines reconciliation without credit; unknown outcomes retain holds/leases; release requires terminal/proved-unused evidence and active resources are uniquely owned. |
| R5 ledger | Root grant, same-dimension parent-funded delegation, reservation, consumption, unused return, close/reset generations and retired closed-generation refunds preserve `authorized = available + held + consumed + delegated + retired` and tree conservation. No child self-grant or implicit conversion exists. |
| Boundary/recovery | Domain proposals cannot forge protected namespaces or facts. Root payloads cannot choose derived balances/status. Malformed requests fail before history without fencing a healthy store. Missing/corrupt stores fail closed. Restart reconstructs state without issuing work. |

The focused tests additionally cover additive migration/reopen, accepted-v1 content
preservation, root pointer absence, semantic snapshot identity, restart after inbox
boundaries and full claim/receipt/lease/ledger settlement. The executable provider uses
only public Gateway and LegacyImport operations; its evidence strings are bounded SHA-256
receipts. A revision mismatch makes all seven capabilities unavailable.

## Verification

Pinned Elixir 1.20.3 / OTP 29.0.5 / ERTS 17.0.5 and canonical `/private/tmp` roots:

- warnings-as-errors compile: exit 0, 108 files;
- focused protected/provider tests at seed 1203: 6 passed;
- evolved historical-H0 plus provider tests at seed 1203: 9 passed;
- full model-free suite excluding the inherited native xSync fixture at seed 1203:
  562 passed, 1 provider-tag exclusion;
- canonical `ci/run.exs`: dependency policy and clean-source/toolchain checks passed, then
  the known native xSync fixture exited 139 before a test summary. Provenance SHA-256:
  `5686a7105b95fdddb3064578693d99aac2de2eb0ad7752779eb52a7093de4cbe`.

The exit 139 is the already traced fixture-header-selection issue, not credited as an
FR-08A pass and not a runtime regression. No waiver is claimed. The full suite excluding
that single inherited fixture is recorded separately so the candidate's model-free
regressions are not hidden.

## Candidate path manifest

This candidate record is excluded to avoid a recursive self-hash.

```text
2b57b3dcb1a23af102956dfc8bb073a4feceea9982dfe84bd531261c1ff82d79  foundry/docs/fr-08/fr08a-protected-report.txt
d0b94ba108f8a1be0b3c17db4478bcbe25783991ceb17bc5ca3bb8edd886d99c  foundry/lib/pramana_foundry/durable_store/authority.ex
eb33981a78b6a973f26f8610f660f660c149ba57e2d8c046f09556bb1fd4b6e5  foundry/lib/pramana_foundry/durable_store/database.ex
693fad9919d9bbf91b3a1157f5a775442a95fd3994553757c7912ec22862551b  foundry/lib/pramana_foundry/durable_store/gateway.ex
ef3d27382df97b3919791610da445f3b42e7ec79aaa4bf81dbd165408b030447  foundry/lib/pramana_foundry/durable_store/protected_primitives.ex
3b562b3d6b787e966970932d193d37c23df1eb450c1cc126f10c1fbd069568a9  foundry/lib/pramana_foundry/repair/fr08a_protected_boundary.ex
2a194970b618832e6feda4c27607627fa8f05fc29dc0f637526b26f546609a48  foundry/test/pramana_foundry/durable_store/protected_primitives_test.exs
b7c0abdff1437e7408146eb4d271ec93523c7317401416a5e4239fc6977c34ee  foundry/test/pramana_foundry/repair/fr08a_protected_boundary_test.exs
e762a8827a0c4a82f14bb92154692b2d52bd1337e2580af26133f7415ebd189b  foundry/test/pramana_foundry/repair/h0_accepted_fr07_boundary_test.exs
```

Independent Astra-high critical review is required before integration. FR-08B must not
start from this branch before that review and integration complete.
