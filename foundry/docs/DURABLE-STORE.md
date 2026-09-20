# Durable workflow store

FR-07 introduces the version-1 SQLite authority boundary. It is an implementation
foundation, not activation of the redesigned workflow: legacy mutation paths remain
contained until FR-08 routes every command through the kernel and gateway.

## Boundary

`PramanaFoundry.DurableStore.Gateway` owns one in-process Exqlite connection in one
GenServer. The dependency is pinned to `exqlite == 0.40.0`; its bundled native SQLite
implementation is the necessary database engine, not a Python service or sidecar.
An independent SQLite lock sidecar and durable unclean-owner marker admit one gateway or
offline importer across BEAM/OS processes. Ambiguous owner loss requires explicit
recovery evidence before redispatch. The authority connection is configured and checked
for WAL, `synchronous=FULL`, foreign keys and schema/application versions before ready.
One strict `PathIdentity` is established before ownership or SQLite. Relative or lexical
alias paths, dot/dotdot components, repeated/trailing separators, symlinks in any parent
or leaf, hardlinks and non-regular database files are refused. The same identity is
revalidated around owner acquisition and database open and is passed through gateway,
migration, importer and backup operations.

The updatable kernel supplies only a versioned, pure-data proposal containing a result,
known domain events, projections and pending effect requests. Exact domain-tagged request
digests bind effect identities and bounded operations. `Kernel.validate_bundle/1` rejects
SQL, callbacks, protected rows, candidate-issued/terminal status and rejected decisions
that attempt domain mutation. The protected controller path passes facts through the
fixed `ProtectedVerifier`, which derives claim and reservation rows, and requires an
unforgeable reference supplied to the gateway at protected startup. It is absent from the
candidate-facing operation and all status/results. FR-15a must prove the separate kernel
process/account cannot inspect the protected BEAM or obtain this capability; an Elixir
reference is an interface capability, not the eventual OS security boundary.
Protected facts name the root-required revision set; omission is rejected before SQL,
then every expected projection/dependency/policy/control/ledger revision is checked from
authority inside the write transaction. The fixed verifier also requires one authorization per proposed intent and
checks that a newly introduced top-level allocation is consumed exactly by its request.
Parent/child allocation transfer is rejected until its owning ledger ticket implements
an authoritative in-transaction debit; FR-07 does not claim that lifecycle early.

The gateway calculates command identity from the authenticated actor and complete
canonical request, checks an existing command ID before current proposal processing, and
commits the input, command, result, events, projections, intents, claims and ledger rows
in one `BEGIN IMMEDIATE` transaction. Reply and opt-in compatibility publication happen
only after checked `COMMIT`. Same actor/ID/digest returns the stored result; a different
actor or request returns an idempotency conflict. Storage errors put the gateway into
visible recovery mode. Constraint-invalid proposals roll back without poisoning an
otherwise valid store.
Valid stale-revision decisions instead durably commit an authenticated rejected
command/result with no events, projections, intents or protected rows. Same-ID retry
returns that immutable rejection.

`EventLog.append/2` retains its JSONL destination and has a narrow opt-in destination:

```elixir
{:durable_store, gateway, authenticated_actor_id, opaque_command_id}
```

The caller must allocate the opaque ID; the adapter does not derive identity from a
digest, ticket, process or clock. This is only a compatibility writer. It does not migrate
the Coordinator's other mutations, replay or effect dispatch, which belong to FR-08.

## Initialization, recovery and versions

Initialization is a separate exclusive operation:

```elixir
:ok = PramanaFoundry.DurableStore.Gateway.initialize("/absolute/offline/path.sqlite3")
```

A gateway never creates a missing database. Missing initialization, a malformed SQLite
file, failed WAL/FULL configuration, failed integrity check, unknown SQL `user_version`,
unknown protocol/event/projection metadata, foreign-key violation, sequence gap or
malformed/unknown-version retained body starts in `:recovery` and refuses writes. It does
not replace the file or report empty healthy state. A corrupt result found on a live read
or idempotent retry also fences immediately. `RecordCodec` is the single normalization,
encoding, decoding and relational-binding definition used by admission, materialization,
startup, result reads, backup and reconstruction. It applies only the declared omitted
result-reason and omitted-bundle-collection defaults. Corruption at these boundaries uses
one `authority_corrupt` classification. SQL,
protocol, event and projection versions are recorded
independently; schema creation is transactional and the offline v1 migration checkpoint
is rerun-safe.

Schema v1 has separate metadata, authenticated inputs, commands/results, ordered events,
projections, effects, claims, receipts, leases, ledger generations/reservations,
policy/control revisions, artifact references and legacy-import evidence. Foreign keys
bind owners. Unique constraints cover command, event, effect, receipt/request and
outstanding-claim identities. Effect and claim status retain
`pending/claimed/issued/unknown/succeeded/failed/non_started/cancelled` distinctions.

## Offline legacy import

`PramanaFoundry.DurableStore.LegacyImport.run/4` is explicitly offline maintenance. It
streams JSONL without the legacy eight-MiB whole-file limit, copies the original to a
digest-named archive, fsyncs it, verifies its SHA-256 before publication, and retains every
line as raw bytes with its digest and half-open byte range. Torn, malformed, invalid UTF-8,
schema-invalid and unknown-version rows remain invalid evidence; they never become
authority and are never silently skipped. The manifest records source/archive paths,
full digest/range, counts and each error. A repeated source digest returns the original
database manifest and regenerates a missing external manifest without duplicate rows.

The importer validates strict path identities against the database, its
sidecars, archive and manifest before writing. It parses only the digest-verified archive
and holds the same exclusive owner as the gateway. Import and manifest-publication
interruptions can rerun without duplicate database rows.

The importer does not remove or relocate the source. FR-19 still owns live-handle/space
preflight, retention, checkpoint interruption, archival removal and collision-safe
relocation.

## Backup and limitations

`Gateway.backup/2` uses SQLite `VACUUM INTO`, an engine-produced coherent snapshot rather
than copying a live database/WAL pair. The destination must be a new absolute normalized
path. The gateway reopens the snapshot under the same version checks and compares a
stable SHA-256 over complete ordered rows of every authority/import/metadata table.
Projection-changing events and projection writes are bijective and ordered. Multiple
transitions for one entity consume one initial authoritative read and advance exactly one
revision at a time. The same codec reducer is used before commit and during replay, and
the verifier compares reconstructed projection state with the stored projection table,
detecting missing, reordered and same-count body corruption. FR-19 owns retention,
checkpoint/compaction interruption, archival and operational
backup policy.

The acceptance suite uses the real pinned binding and exercises an actual SQLite
`max_page_count` FULL failure, an actual read-only filesystem/open failure and a real OS
`RLIMIT_FSIZE` SQLite commit/write error. It also checks that WAL/FULL is active on real
commits. Deterministic failures after each bundle
table test rollback/fencing, and subprocess `System.halt/1` fixtures test process loss
immediately before and after multi-table protected commits over prior protected history.
A test-only loadable extension interposes only the tested connection's WAL
`sqlite3_io_methods`. It observes successful WAL writes, then returns
`SQLITE_IOERR_FSYNC` from the targeted WAL `xSync` during checked COMMIT. Ordinary and
hard-exit fixtures submit complete protected bundles, including effect, claim, reservation
and ledger rows, and prove no success acknowledgment, immediate write fencing, explicit
owner recovery, full-table-content/reconstruction consistency, and ambiguity-safe
same-command retry whether recovery retained the full bundle or none of it. This is
attributed SQLite VFS `xSync` fault evidence through the production
Exqlite connection; it is not a claim that a kernel `fsync(2)` syscall or physical medium
failed. FR-19 retains the broader physical capacity, filesystem sync, WAL/checkpoint and
compaction fault matrix.
