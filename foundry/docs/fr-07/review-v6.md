# FR-07 recovered v6 independent review — FAIL

Reviewed 2026-09-19 (Hawaii), against the exact immutable revision below. This review
does not accept FR-07. The narrower v5 corrections include substantial working fixes,
but independently executed probes still reproduce invalid authority being used for
decisions, incomplete admission validation, and destructive import publication.

## Exact identity and scope

- Reviewed revision: `103ee1de234af8929d504e78c51297b6d9907d71`.
- Reviewed tree: `89e7dbf935211b63dff3353c246eefd546fbbae1`.
- Checkout: `/Users/raymondluong/dev/pramana-fr07-worktree`.
- Implementation/docs revision: `940b8f710c661ef5f7ecd7c5c5ae9cc3fbed2ea6`.
- Current-main base: `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`.
- Independently rehashed all **45** manifest entries in `candidate-v6.md`: all match.
- Candidate document SHA256:
  `06a0d33720e024dae2a322030c831d111dd3672d0b67d8a473fc732214def7c4`.
- Supplement SHA256:
  `2fa7ea6390031b53ad6b4f833b4b5612e808dcad1b3d8e3e1832f9a554316690`.
- Implementation-to-reviewed-revision differences are only candidate-v6, its supplement,
  and the restored historical diagnosis-v3 document. HEAD/tree and clean tracked/untracked
  status were rechecked after tests. No candidate source, test, documentation, or Git ref
  was changed by this reviewer.

Read the project instructions/conventions, relevant orientation and Rules 8/41/60/63/79,
FR-07 acceptance/allocation, WORKFLOW-CONTRACT authority/storage/recovery requirements,
v5 review, v6 diagnosis, candidate and supplement, DURABLE-STORE, all durable-store
production modules, and focused tests/support fixtures. Tests ran against disposable
state with tick disabled and no live daemon, provider, credential, activation or production
database access. Trusted SQL corruption below tests the allocated retained-authority
contract; it is not a claim of an untrusted caller's SQL access.

## Blocking findings

All paths in this section are relative to `foundry/`. B1–B5 have executed reproductions.
B6 is a source-derived bounded-query acceptance shortfall, without a performance claim.

### B1 — A rewound projection is certified by live reads and used to commit a new decision

`lib/pramana_foundry/durable_store/authority.ex:835` validates a projection against its
stored last event. `validate_projection_chain/2:905` then reads only events whose sequence
is at most that stored pointer (`seq <= last_seq`, line 913). It never establishes that
the pointer is the current final carrier for this entity. Command event closures at line
811 merely require that this projection lookup succeeds; they do not establish that a
later event supplied by the command is represented by the returned current projection.

Executed trace:

1. Commit A creating `ticket-A`, revision 0; save its projection bytes.
2. Commit B advancing the same entity to revision 1.
3. Change only the projection row back to its genuine historical revision-0 bytes,
   `revision=0`, and `last_event_id='event-A'`. All events remain present.
4. The scoped projection read returns revision 0; `Gateway.command(g, "B")` succeeds.
5. Submit eventless C with the projection's expected revision set to 0. C commits an
   accepted result and the gateway remains ready.
6. `Authority.read(conn, :all)` reports
   `{:authority_corrupt, "projections", "reconstruction", :projection_replay_mismatch}`.

This is one row restored to a valid older value, not a coordinated rewrite into another
internally valid history. The acknowledged revision-1 event remains visible and global
reconstruction already knows the projection is wrong. The live reader used it anyway.

Required: prove the retained projection equals the final authoritative state for that
entity before returning/using its revision, including when an event-bearing command is
read or retried. Preserve legitimate intermediate projection materialization within a
transaction explicitly; that internal phase must not weaken completed live reads.

### B2 — Required owner relations still differ between scoped and global authority reads

The projection path queries event bodies without the owning command/result closure.
The ledger path's `validate_scoped_reservations/2` at `authority.ex:1069` reaches a typed
effect but stops before its required command/input/result. Global `validate_content/2:205`
checks event owners, but `validate_command_relations/3:518` only iterates existing commands;
effects grouped under an absent command are ignored. `Authority.read(:all)` itself does
not perform SQLite's foreign-key check.

Two executed counterexamples:

- Seed a complete protected A, then delete only A's result. In separate stores, submit
  eventless B reading A's projection revision or its ledger revision. Both B commands
  commit and leave the gateway ready. The global reader reports A's missing result.
  Direct A reads correctly fence; dependency reads still use its incomplete authority.
- Seed protected A, temporarily disable FK checking for one trusted injection, change
  only `effects.command_id` to `missing`, then re-enable FK checking. SQLite reports the
  orphan. Nevertheless, `Authority.read(:all)` and `Gateway.counts` succeed, and a new
  command dependent on that effect's ledger commits. Backup discovers the FK violation
  only while reopening the already-created destination, returning a physical-corruption
  error after the invalid snapshot file exists.

Required: share owner/required-neighbor checks through projection and ledger/effect
closures, and validate every effect's required command globally. Source backup validation
must reject this before destination publication. A missing related result or owner is
not the documented limit concerning erasing every protected-membership witness.

### B3 — Malformed protected facts can crash or fence a healthy gateway; malformed lookup also fences

`protected_verifier.ex:37` accepts any map as `required_revisions`, then enumerates it.
An otherwise valid protected call with `required_revisions: %URI{scheme: "x"}` raises
`Protocol.UndefinedError` at line 41 before entering the transaction. The caller exits
and the monitored gateway dies. This is an executed public protected API trace using the
proper capability, not SQL injection.

Its epoch predicate at line 11 checks only nonempty binary. An otherwise valid call with
`writer_epoch: <<255>>` reaches claim encoding inside the transaction, returns
`{:error, {:storage_unavailable, :invalid_utf8}}`, and moves the gateway into recovery.
An immediate independent full authority read succeeds: the store is healthy and empty.

Separately, `Gateway.command(g, "")` reaches the catch-all `Authority.read/2:118` and
returns recovery with `{:authority_corrupt, "authority", ..., :unsupported_read_scope}`.
A malformed lookup has been classified as discovered retained corruption without reading
any corrupt row. The store independently validates successfully.

Required: normalize the complete protected-fact language, including nested read sets,
identities and derived claim/reservation values, before policy/SQL. Validate command-lookup
IDs at ingress. Malformed requests must return typed nonfencing errors and preserve live
gateway/readiness/rows; retained corruption must still fence. Preserve existing-ID retry
before obsolete proposal/fact validation. The v5 non-map ordinary-result crash is fixed,
but the diagnosis's analogous admission sweep is unfinished.

### B4 — Import overwrites and removes preexisting staging evidence

`legacy_import.ex:425` resolves planned publication paths but permits an existing regular
single-link archive temp. `copy_and_sync/3:237` then uses `File.copy(source_path, temp)`
without exclusive creation or checking existing bytes, followed by renaming that temp
over the archive path. Its error branch can also remove that unowned temp.

Executed public import trace: source bytes are `{}\n`; precreate the computed
`<digest>.jsonl.tmp-<first-16-digest-characters>` as a regular single-link file containing
`PRESERVE PREEXISTING EVIDENCE`. `LegacyImport.run/4` succeeds. The previous bytes were
overwritten, the temp path is now absent, and the archive contains the new source bytes.
No concurrent writer, alias, symlink or hostile OS race is needed.

Required: refuse an occupied staging target, or explicitly verify/adopt matching owned
staging evidence before reuse; use exclusive creation and cleanup only for files the
operation established ownership of. Keep rerun recovery for matching evidence. Complete
namespace collision checks do not establish ownership of every regular file inside it.
Only a disposable reviewer-created evidence file was destroyed by this reproduction.

### B5 — Schema validation certifies a store without the required active-claim uniqueness

`authority.ex:154` checks table names, column names and STRICT flags. Its required-index
check at lines 165–171 verifies only index names, not uniqueness, indexed columns or the
partial predicate. Table validation likewise ignores the key/FK/type attributes returned
by the relevant schema pragmas.

Executed trace on an initialized store:

```sql
DROP INDEX one_active_claim_per_effect;
CREATE INDEX one_active_claim_per_effect ON claims(writer_epoch);
```

`Authority.read(:all)` succeeds; clean gateway reopen is ready; backup succeeds and
certifies the same malformed schema. This is a direct failure of the v6 diagnosis's
explicit required keys/FKs/indexes schema validation. The probe establishes acceptance of
the missing constraint; it does not claim to have executed duplicate external issuance.

Required: verify the actual contracted key/FK/index definitions, including the unique
active-claim predicate, before declaring schema compatible. Do not treat a matching name
as evidence that SQLite enforces the required relation.

### B6 — Scoped projection validation rebuilds an unbounded prefix of unrelated history

At `authority.ex:911`, the fold scans every event through `last_seq`, decodes each and
accumulates every decoded event in a list. Only after the full prefix has been retained
does it filter to the requested entity. This is invoked on live revision reads, initial
projection reads, materialization readback, command/retry reads and touched validation.
`Database.fold` stepping one row at a time does not bound its accumulating result.

This violates the diagnosis's indexed dependency-closure/bounded-scan requirement and
FR-07's allocated F20 bounded queries; ordinary commits to independent entities repeatedly
scan unrelated history. It is not a request for FR-19 retention or an unsupported latency
claim. No scale benchmark was run. Required: keep the live checked closure bounded to
relevant authority and stream its validation without retaining unrelated history. Resolve
B1 without extending this already-unbounded full-prefix scan to every event.

## V5 R1–R6 disposition and credited behavior

| V5 finding | Fresh v6 disposition |
|---|---|
| R1 missing results/result bounds/fencing | Direct command totality, sequence bounds and source-backup corruption fencing work in the relevant tests. Required global/scoped owner closure remains incomplete (B2). |
| R2 unchecked ordinary result | Fixed: codec normalization precedes ordinary policy. Arbitrary ordinary-result tests pass. Protected facts and invalid read ingress retain analogous failures (B3). |
| R3 owner journal backup collision | Fixed for the concrete owner journal and enumerated reserved namespaces; current tests reject before creation. Import staging custody remains incomplete (B4). |
| R4 typed live ledger rows | Shared typed ledger validation rejects unsupported children/revisions/funding faults. Scoped owning relations remain incomplete (B2). |
| R5 retained import completeness | The specific deleted-record rerun defect is fixed; import groups are streamed, byte/range/digest/classification/count checked and missing evidence rejected. This credit does not cure publication loss (B4). |
| R6 shared narrow reducer | Fixed structurally: live `insert_projections` invokes `RecordCodec.apply_projection`, checks CAS row count and materialized values; replay uses that reducer. Completed retained projection validation remains defective (B1). |

The 18-table independent matrix first establishes actual `sqlite_schema` table inventory
against a separately listed oracle, then corrupts one representative supported dimension
per table. Metadata, inputs, commands, results, events, projections, effects, ledgers,
claims, reservations, import manifests, legacy records and sqlite_sequence all reject
those representative corruptions. Nonempty receipts, leases, policy revisions, control
revisions and artifact references are rejected as unsupported. In every matrix case,
source backup refuses before creating a destination, fences, refuses a subsequent protected
mutation and leaves exact rows unchanged. This is representative coverage of all tables,
not a claim that every column/value/relationship permutation was exhaustively tested.
B1/B2/B5 demonstrate why the matrix's valid successes do not prove the entire boundary.

## Independent verification

Pinned Elixir 1.20.3/OTP 29.0.5, actual SQLite 3.53.4; SQLite source ID:
`2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`.
Loaded Exqlite NIF SHA256:
`7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.
The build directory was fresh; existing fetched dependency sources were reused. This
review does not claim a new independent redownload/verification of every Hex package.

Commands ran from the candidate `foundry/` using `mise exec --`, with
`MIX_ENV=test`, `MIX_BUILD_PATH=/private/tmp/fr07-v6-review.MmDty1/build`,
`TMPDIR=/private/tmp/fr07-v6-review.MmDty1`, `COORDINATOR_TICK=0`, and HERDR_ENV,
PRAMANA_OPERATOR_RUNTIME_ROOT and PRAMANA_RUNTIME_ROOT removed from the environment.

- `mix compile --force --warnings-as-errors`: exit 0; 90 project files compiled.
- `mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 9119`:
  exit 0; **81 passed**.
- `mix test --seed 9120`: exit 0; **501 passed**. The supplement's missing-tiktoken
  benchmark failure was not reproduced in this environment; no dependency was installed
  or changed by this reviewer to obtain this result.
- Changed durable modules/tests/support and Mix-file format check: exit 0.
- Independent `mix run --no-start` probes: six characterization tests reproduced B1–B4
  and the malformed lookup; three relation/matrix tests executed the all-table positive
  matrix and reproduced B2/B5; one independent VFS test exercised both concrete outcomes.
  Characterization tests asserting defects are not acceptance passes.
- `git diff --check 75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc HEAD`: exit 2 solely for
  the preserved historical `diagnosis-v3.md:3` trailing whitespace. Not reported as clean.

## Bounded WAL xSync evidence — passed, with exact independent full-row oracle

The independent probe builds a separate successful A/CONTROL/B oracle with fixed
installation/repository IDs and complete command/input/result/event/projection/effect/
claim/ledger/reservation bundles. Actual SQL table inventory is checked against the
independent 18-table list, without deriving the oracle from `Authority.registry`.

The candidate C shim was independently compiled with Clang warning errors enabled.
`otool -L` shows only its own library and libSystem, no separately linked SQLite engine.
Its extension API operates on the actual Exqlite connection. C SHA256 remains
`508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d`;
this probe's dylib SHA256 is
`e2097d0e694f4ae3cc7ef4f759b33d3b139a71a7c868614ea8e79dc9e36c9e4b`.

Both scenarios observed WAL/FULL/FK enabled, an unrelated connection committing while the
target was armed without a fault hit, then 50 successful target WAL writes, last-write
order 50, xSync order 51, flags 2, one returned code 1034 (`SQLITE_IOERR_FSYNC`), COMMIT
`disk I/O error`, no success acknowledgment, and immediate refusal of another protected
mutation. These were observed outcomes, not merely allowed branches in a conditional:

| Fault termination | Independently checked recovery | Same-ID retry |
|---|---|---|
| Disarm and ordinary close | Ready reopen; every table exactly equals prior A/CONTROL, B absent | B commits; all rows equal complete oracle |
| Hard child exit 75 before close | Unproved reopen fences ambiguous owner; explicit observed-exit evidence permits recovery; all rows equal complete A/CONTROL/B oracle | Obsolete empty proposal/facts returns the original B result idempotently, unchanged rows |

Both then execute an additional malformed-obsolete retry, compare exact rows, make a
backup, independently reopen the backup, and compare all rows and all three reconstructed
projections. Both final row maps hash to
`2bcd1d897b9fd489ab2cfedd8d87123b06e6940089048c9e6af7fb04eb33647c`.

Credit this as actual SQLite VFS xSync fault attribution, acknowledgment fencing and
absent-or-complete recovery with executed retry. It is not a physical fsync syscall error,
power-loss, media-durability or ENOSPC-at-sync claim.

## Reusable evidence and remaining boundaries

Temporary evidence is retained under `/private/tmp/fr07-v6-review.MmDty1/`:

| File | SHA256 |
|---|---|
| helpers.exs | `75244b7ed94ef3b97a5308de46754deeec378e6c56bd857f9e5d6b6fdb5b7bb7` |
| probes.exs | `de336233b58fa77b6d41e6dfa5140f52b58d04afa9205b867e0a5a31c197e9d9` |
| relations_probes.exs | `3485c2c3b45c57408fe60e92241dd90d34dc912069c1041e6c36f70462ccc7bd` |
| sync_child.exs | `a08460d3be91920a6c62f2aa66aea3948fd928eea594d1cdbabcc230c025e6ca` |
| sync_probes.exs | `d19505385f11d5485eb53abc4a5c4b232fab699765853b80cebac2e6904ee61d` |

Suggestion, separate from the blockers: retain an executable equivalent of the independent
VFS oracle in owned test support. Current candidate sync tests compare source with backup
and conditionally accept either outcome; they do not independently construct the complete
expected transaction rows, and their snapshot inventory is derived from production's
registry. This review supplied the stronger bounded evidence and does not reject the VFS
mechanism for being test-only.

FR-08 full workflow/replay migration, FR-15a hostile process/account isolation, FR-17
activation/rollback, FR-19 physical storage/retention/checkpoint/compaction/relocation and
FR-22 complete lifecycle proof remain explicitly deferred. No issue here demands those
capabilities be implemented early, an external acknowledgment trust anchor, or resistance
to coordinated self-consistent rewriting by trusted SQL.

Do not mark FR-07 or all F02/F20/F21 obligations complete. Correct the concrete retained
reader, input validation, staging custody and schema checks, preserve the shared reducer
and credited fault evidence, then freeze a new exact candidate for renewed independent
review. This verdict authorizes no implementation, integration, deployment or activation.
