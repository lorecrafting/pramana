# FR-07 v6 closure diagnosis and bounded patch design

2026-09-13. Diagnosis only. No candidate source, test, dependency, runtime state, or Git
ref was modified; no implementation verdict is issued. This document specifies work
and acceptance probes that have not been executed by this diagnosis.

## Exact evidence boundary

- Rejected v5 candidate: `ff9cbb725a32e13d4062b570521574f01e00af17`.
- Candidate tree: `5055e3687feac8e5a60499b920d8f8b565d07597`.
- Implementation commit/tree: `d25a51f8b219a8a49ed9e83b3d97d972058254f3` /
  `b454a2fd0f4af1669ad02d616bacfd3148630738`.
- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Checkout inspected: `/private/tmp/pramana-fr07`. All 39 candidate-v5 manifest entries
  were independently rehashed in this diagnosis; zero mismatches. Its candidate document
  hashes to `5eb42bbbe4a27e4d58f0c570f532483b23d395730bf733007116dd744011975f`.
- V5 review, both `foundry/docs/fr-07/review-v5.md` and `/tmp/fr07-v5-review.md`:
  `e5d838581d3dd76156798ec4423cba99a3b21090037afa2d90ebc653cd6811fa`.
  The review file is an untracked additional input, not part of the frozen v5 tree.
- Previous diagnosis: `5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`.
- WORKFLOW-CONTRACT: `5d1621ff98fcb1aad2d6d37ba523b2a00c6bf90120873ffeb2518f23fd831488`.
- REPAIR-PLAN: `8ecb2900160c7a8c7e711039251d2a7ced2eacc20a567ebc46a9d2865c872581`.

Read: AGENTS orientation/invariants and relevant Rules 8/41/60/79; relevant current
STATUS/PLAN/ROADMAP passages; Foundry README, FR-07/08/19 and F02/F20/F21 allocation;
WORKFLOW-CONTRACT storage/identity/transaction/recovery/ledger/compatibility sections;
FR-06 v2 review and v3 R4a response/focused review; FR-07 review history v1/v2/v3/v5,
diagnosis-v3, response-v3, candidate-v5 and DURABLE-STORE. All ten current durable-store
modules were inspected, with focused test bodies and support-path reads. This is not a
claim to have reread every unrelated corpus document or rerun any prior test result.

The v5 review's R1-R5 are executed defects. R6 is an implementation/design mismatch:
no new accepted projection/replay divergence was observed in that review. Additional
omissions below are source-derived sweep findings, not newly executed reproductions.

## Conclusion and invariant

The previous diagnosis chose the right shared abstractions, but v5 implements shared
JSON decoding without a shared authority read. Relations and failure dispositions still
live in callers: missing result rows vanish through a join; results acquire different
sequence checks in backup; revision reads skip typed decoding; import reruns trust the
manifest alone; SQL projection updates implement their own transition. Sidecar identity
is similarly a list at one caller instead of a namespace enforced by every publisher.

The smallest closure patch is one database authority validator/reader, using the existing
codec for types and the existing projection reducer for transitions, plus one complete
path namespace used by ownership and publication. It does not need another database,
a new lifecycle reducer, a new SQL table, or a broad workflow migration.

Required invariant: every admitted normalized record is exactly the record persisted;
every authority value returned or used for a decision has passed the same typed and
required-relational checks; every discovered retained inconsistency reaches the same
recovery fence; every published backup/import target is outside every reserved store
namespace. No caller can obtain an unchecked revision or certify a manifest in isolation.

## Shared interfaces and exact routing

Add `DurableStore.Authority` as the only retained-authority query/validation owner.
Names are proposed; the following separation is required:

```elixir
Authority.read(conn, :all | {:command, id} | {:revision, typed_key} |
                     {:import, digest} | {:touched, normalized_write_set})
  :: {:ok, checked_view} | {:error, {:authority_corrupt, table, identity, reason}} |
     {:error, {:storage_unavailable, reason}}
```

`:all` covers the entire table inventory, metadata/sequence/FK validation, imported
evidence and projection reconstruction. Scoped reads select full rows with indexed keys,
then use the exact same row and relation validators and required-neighbor traversal as
`:all`. A missing *optional entity* may return absent; a missing required neighbor never
does. The implementation must make this distinction explicit, rather than giving every
query a generic `[] -> absent` clause. `checked_view` carries decoded rows, projection
state and watermark evidence so callers do not query the same value unchecked afterward.
No raw SQL/query strings, connection, codec type or validation scope crosses Gateway's
candidate-facing protocol.

Do not rescan the entire imported history for each command. Global checks run at startup,
source backup, snapshot validation and offline maintenance; a live lookup checks its
dependency closure. All scans use bounded batches/cursors and streaming hashes, especially
legacy raw bytes. This is not a performance claim: publish no new latency figure without
measurement. F20's bounded query requirement would be undermined by adding full-history
`fetch_all` validation to every read. A ready state certifies the last completed global
validation plus serialized gateway writes, not perpetual detection of arbitrary trusted
out-of-band SQL corruption before an unrelated read encounters it.

| Boundary / exact current call site | Required v6 routing |
|---|---|
| Admission: `Kernel.normalize_bundle/1:16` | Codec normalization first; policy inspects only normalized fields. Delete `raw_disposition_consistency/1`, keep normalized rejected/blocked mutation prohibition. |
| Command preparation: `Gateway.prepare_command/2:330` | Return and carry normalized command with canonical bytes/digest/ID; stop passing original atom-key input into later string-key `get` calls. This analogous admission/materialization mismatch is visible in source. |
| Protected admission: `ProtectedVerifier.derive/3`, `validate_generations/1:45` | Normalize typed facts/generations through codec, then apply root authorization/allocation policy; materialize revision zero once. |
| Existing-ID paths: `do_transact/6:266`, `do_verified_transact/6:302`, `existing/4:633` | Authenticate/prepare request, then `Authority.read({:command,id})`; validate retained command/input/result together, return original result or conflict before obsolete proposal/facts/revision processing. |
| Direct result: `fetch_command/2:653`, command `handle_call` | Same command read; remove independent result-only query and special local fence. |
| Revision decision: `check_expected_revisions/4:691`, `read_revision/2:735`, `read_optional_revision/3:779` | Parse key once, then typed authority read for projection, dependency, ledger, policy and control. Remove all bare `SELECT revision` paths, including projection CAS at `check_projection_revision/2:527`. |
| Accepted transaction: `commit_accepted_bundle/8:394` | Under BEGIN IMMEDIATE: validate retained touched/read rows, apply shared projection plan, insert codec-encoded rows, materialize result, then validate actual touched write set and required relations before COMMIT. |
| Durable stale rejection: `commit_rejected_command/6:440` | Same normalized input/result materialization and touched validation; assert no command-owned events/effects/protected mutations. |
| Startup/reopen: `Database.open_identity/2:190`, `validate/1:342` | Keep SQLite connection configuration/physical checks in Database; call `Authority.read(:all)` before ready. Remove its parallel body/ledger/reconstruction validators after extraction. Initialization validates typed metadata before creation and full store before success. |
| Migration: `Gateway.migrate/2:43`, `Database.record_v1_migration/1` | Owner/path fence; full validation before, transactionally validate updated metadata before committing, full checked reopen as already applicable. No rewrite/reset repair. |
| Backup: `backup_database/2:863`, `verify_backup/2:884` | Namespace preflight, full source validation before VACUUM INTO, engine snapshot, full snapshot validation through same entry, exact ordered row equality and same reconstructed state. Delete separate `validate_reconstruction/1:957`, decoder copies and sequence-error variant. |
| Reconstruction: Database `validate_projection_reconstruction/1:597`, Gateway `reconstruction_evidence/1:986` | Obtain decoded typed events/projections and reconstruction from Authority; no private alternate parsers/replay predicates. |
| Import commit/rerun: `LegacyImport.import/6:77`, `existing_manifest/2:221`, `import_or_replay/6:69` | `Authority.read({:import,digest})` after final manifest update but before COMMIT, and before returning an existing manifest. Database open performs full validation. Never silently refill missing records on rerun. |
| Results/fencing: `transition_after_result/2:814` and all data-serving handlers | One disposition helper handles authority corruption and storage unavailability for direct read, both transact paths, revision/CAS, counts I/O and backup. Keep semantic rejection/path collision separate and nonfencing when source authority is healthy. |

Authority normalizes all retained semantic failures into the one four-element corruption
tuple, including missing neighbors, sequence bounds, unsupported scaffold, reconstruction
and import completeness. Database engine/query errors become storage_unavailable. Preserve
typed corruption through `commit_bundle/8`; do not bury it in storage_unavailable or
classify it by `inspect(reason)` containing “constraint”. SQLite constraint failures from
a malformed new proposal may remain semantic rejection after checked rollback; an
already-corrupt retained row is never reclassified as a harmless candidate error. Any
rollback failure also fences. Source-corruption errors during backup fence the source;
destination-only creation/sync/I/O failures must retain their attribution. Diagnostics
are not a separate health certification. Status remains callable in recovery, while
authority reads/mutations continue to refuse until an explicit successful reopen/recovery.

## R1: total command/results and precise sequence semantics

Read commands as the owning relation (LEFT JOIN or explicit required lookups), never an
inner join that hides incompleteness. Require one input and one result for each command,
one command per input, no orphan result/input, and all identity/digest/protocol/type
bindings already supported by `decode_bound(:command_request, ...)`. Direct result lookup
must distinguish no command from command-without-result. SQL PK/FK checks establish only
some directions and cannot replace this totality test.

Use one result-bound validator with typed context: `0 <= committed_seq <= current event
high-water mark`. For commands owning events, require one contiguous ordered event block
and `committed_seq == max(its event seqs)`; a result cannot point before its own events or
into an unrelated later block. Rejected/blocked command results must own no domain events
or effects. For an eventless accepted/rejected/blocked command, the watermark is the global
maximum *at its commit*, and can legitimately be zero or older than today's maximum.
Do not require every historical result to equal today's maximum, require a nonexistent
sequence-zero event, or invent durable command order from uncontracted SQLite rowid.
Check exact write-time watermark using the captured transaction context; retained reads
can check the supported bounds and relations but cannot infer an absent ordering witness.

Validate `sqlite_sequence` as well: only the `events` entry, integer nonnegative value,
consistent with retained events. In this append-only FR-07 store with no deletion/retention
API, after committed events exist it equals their maximum; before the first event no entry
is expected. Rollback and VACUUM snapshots must preserve the supported state. An unknown
entry, duplicate, impossible high-water value or sequence gap is corruption, not automatic
repair. This closes the analogous sequence inventory omission.

## R2/R4: one typed language before policy and at every authority read

The malformed-result matrix must include nil, boolean, integer, binary, list, tuple,
struct, improper list, missing key, duplicate atom/string keys and malformed nested values.
Every public new-command case returns a typed validation error, remains alive/ready and
writes no rows; exact-ID retries with obsolete malformed proposals retain the original
idempotent behavior. Codec validation must be total over terms, not just JSON-shaped maps.

Add codec kinds for candidate and retained ledger generation, with exact keys,
schema version 1, nonempty Unicode ID, parent nil, retained revision 0, signed-64-bit
nonnegative allocation/consumed and consumed <= allocation. Candidate materialization adds
revision zero explicitly; any other revision/child allocation is unsupported. The same
function validates verifier admission, SQL materialization, startup, backup and full-row
live ledger reads. Do not implement child allocation, new R5 dimensions or settlement.

Sweep analogous duplicated policy: normalize/encode events with `RecordCodec.encode`,
and put fixed supported event/intent envelope, pending-only status and semantic effect
request digest checks in the shared stored-record contract. Current Kernel-only operation
and digest checks cannot let a retained bogus digest become healthy after reopen. Keep
runtime policy authorization in Kernel/ProtectedVerifier; do not replay current policy.
Derived claims/reservations must likewise traverse shared typed normalization before SQL.

## R3: reserve complete authority and owner namespaces

Move the source of truth from the partial `Owner.sidecars/1:69` list into PathIdentity's
typed store-namespace helper. Let D be the authority filename and O = D + `.owner.sqlite3`.
The reserved set is D, D-wal, D-shm, D-journal, O, O-wal, O-shm, O-journal,
D.owner.unclean, and the marker recovery-archive family D.owner.unclean.recovered.*.
The authority can be opened before WAL mode is established, and the owner is a SQLite
database with persistent mode, so reserve rollback *and* WAL families for both. Do not
infer the allowed namespace from whichever files happen to exist today.

Compare identities and canonical parent/basename paths for absent targets. Compare whole
prospective namespaces, not just target main file: a backup B whose B-wal or B-journal
collides with D/O/evidence is also unsafe. Before opening/initializing a prospective
authority/backup database, validate its own existing sidecars; a preexisting hot journal,
WAL, SHM, symlink, hardlink or unrelated file cannot silently be adopted for a new target.
An explicit zero-sidecar requirement is simplest for new initialization/backup targets.
For existing owned stores retain ordinary legitimate SQLite recovery under the validated
namespace and owner fence.

Call the same helper from Owner.acquire, Gateway initialize/open/migrate/backup and
LegacyImport.validate_paths. Import source, archive root, archive file, external manifest
and generated temporary/intent publication paths all participate, not just the three file
arguments. Preflight before `ensure_archive_dir/1` creates a directory: an absent archive
directory named D-journal must not be created and only afterward discovered as invalid.
Either bound generated temp names through explicit planned IDs and validate them, or use
an exclusively created validated staging directory. Do not modify general relocation.

Owner recovery archives must also use checked identity/exclusive creation. In
`archive_previous_marker/3`, `eexist` cannot justify deleting the original marker without
verifying that the existing regular single-link archive contains the expected evidence.
Marker removal validates the exact owned marker identity/content rather than a substring.
This is a local evidence/path sweep, not proof of hostile-account descriptor custody;
FR-15a still owns that isolation boundary. Revalidate around ownership/open and publication
as already designed, retaining the strict no-dot/dotdot/symlink/hardlink contract.

## R5: imported evidence is a complete retained byte stream

Add a typed legacy-record envelope/row validator and a streaming import-group validator.
For each completed manifest, ordered rows must have line numbers 1..N, first byte_start 0,
each next start equal prior end, byte_end - byte_start equal raw byte length, and final end
equal source_bytes/manifest range. Validate every raw-record SHA256, valid/error pairing,
and the full stream SHA256 against source_digest, including newline and invalid bytes.
Derive valid/invalid counts and the exact ordered error entries from retained rows and
compare them to the manifest; equal total counts alone are insufficient. Empty input is
the deliberate zero-row, zero-byte, empty-hash case. A one-line imported source whose one
row vanished is not empty input.

Share deterministic legacy-line classification between new import and retained evidence
validation, under the pinned import/schema version; do not parse legacy text into domain
events or fabricate receipts. Preserve an invalid UTF-8/torn/malformed/unknown-version
line as bytes plus the same explicit error, rather than reject the whole group as though
invalid legacy content itself were SQLite corruption. Corruption means missing/mismatched
evidence or unsupported retained envelope. New import reads the verified archive; its
computed streaming digest must still equal the captured source digest before COMMIT, so
mid-import archive mutation cannot commit mislabeled bytes.

Retained completeness is checked without requiring historical external paths to exist
at every Gateway startup. Import rerun separately verifies the supplied source/archive
copies and path identities, then validates retained evidence before returning its original
manifest or publishing the external manifest. Refuse inconsistency and retain all bytes;
never silently reconstruct missing database authority from the archive. A failed external
manifest publication remains rerunnable only after the database evidence passes.

## R6: shared narrow transition reducer, exercised by live application

Keep `RecordCodec.projection_plan/2` as the ordered event/projection bijection. Inside the
live BEGIN IMMEDIATE, seed touched entities from fully decoded authoritative projections,
validate the complete initial read set, and reduce the plan using the actual exported
`RecordCodec.apply_projection/2`. Later steps for the same entity consume its preceding
reducer output. The reducer returns the next value/revision/event identity; SQL only
materializes that decision with an absent insert or revision CAS. Check exactly one row
affected and decode/read back the stored row; compare to the reducer-produced state before
commit. Remove the independent revision-sequencing decision from insert_projections.

Reconstruction reduces the decoded event carriers through the same function from empty
state, then compares every final namespace/entity/revision/last_event/value with retained
projections. Carrier-free legacy events are no-ops. This is only the already-approved
projection carrier; no ticket lifecycle, PM, reset, claim issuance or budget event reducer
is absorbed from FR-08. A test calling the reducer directly is not proof the live gateway
uses it: exercise Gateway and inspect source wiring (or bounded test tracing) as well.

## Rule-41 complete table inventory

This is the full v5 18-table inventory, including SQLite's internal sequence table.
Maintain one static trusted registry for typed table readers/orderings; global validation
and backup inventory consume it. Assert actual sqlite_schema tables match the supported
registry and required columns/keys/FKs/indexes/STRICT shape, rather than letting a newly
created or malformed table fall outside validation. Do not accept dynamic caller tables.

| Table | Shared type and required relation; applicable entry paths |
|---|---|
| metadata | Exact required version values, nonempty installation/repository identity; optional migration_v1 only `complete`; unknown/missing keys rejected. Initialize/migrate, global startup/reopen/backup. |
| inputs | Canonical actor/request/digest/protocol and deterministic input ID bound to exactly one command. Admission/commit, command/retry closure, global validation. |
| commands | Full input binding plus mandatory one result; no hiding inner join. Commit, direct/retry, related event/effect closures, global validation. |
| command_results | Shared result shape/bindings, owning command, disposition/mutation relation and sequence rules above. Commit, direct/retry, global validation. |
| events | Supported version/type, codec bytes and SQL ID/type binding, valid owner command, contiguous sequence/block/result relation, projection-carrier semantics. Commit, related projection closure, reconstruction/global validation. |
| projections | Full codec binding, nonnull owning event, initial read/ordered transitions, full replay equality. Commit/CAS, projection/dependency revision reads, reconstruction/global validation. |
| effects | Exact pending intent, canonical operation digest, required command; no manufactured issue/terminal state. Commit, claim closure, global validation. |
| claims | Full typed binding, actual FR-07 derived claimed/verified form, required effect, unique active claim; required reservation in supported protected scaffold. Protected commit, ledger/claim closure, global validation. |
| ledger_generations | Shared top-level v1/revision-zero typed row; no children. Allocation/consumed/reservations relation identical to supported admission (`sum(reserved units) == allocation - consumed` for committed protected generations). Protected commit, ledger revision, global validation. |
| reservations | Typed derived reserved/verified form, positive units, required generation and claim, one supported reservation per claim, matching effect ownership through claim, aggregate funding relation. Protected commit, ledger/claim closure, global validation. |
| receipts | No production FR-07 writer or exact receipt envelope exists. Smallest choice: reject nonempty rows as unsupported retained authority; no fabricated receipt meaning. Global validation; any future reader must first add a typed contract. |
| leases | Same explicit unsupported/nonempty refusal; do not treat `{"schema_version":1}` as proof of a lease. Global validation. |
| policy_revisions | Same unsupported/nonempty refusal. A revision lookup returns absent only if no row; a present scaffold returns corruption, not a usable policy revision. Global and live policy read. |
| control_revisions | Same unsupported/nonempty refusal, including live control revision read. |
| artifact_references | Same unsupported/nonempty refusal; body-only scaffold validation is not artifact/digest provenance. Global validation. |
| import_runs | Completed typed manifest/SQL binding plus required retained group; importing placeholder allowed only internally before transaction completion. Import commit/rerun, global validation. |
| legacy_records | Exact typed ranges/digest/raw/classification and group completeness above; owner manifest mandatory. Import commit/rerun, global validation. |
| sqlite_sequence | Typed supported event high-water entry, consistency with retained event stream; no unknown rows. Commit frontier check, global validation. |

The explicit unsupported-table choice is already allowed by diagnosis-v3. Rewrite the
existing test that injects fake nonempty scaffold rows and calls backup healthy: such rows
become corruption fixtures. Preserve full-content comparison for all 18 tables, including
empty reserved tables. This prevents premature policy/receipt/lease implementation.

Completeness limit: valid ordinary pending intents need not have protected claims. The
v5 format contains no independent protected-command membership witness, nor an external
acknowledgment log. Removing *all* of a command's protected rows (or rewriting an entire
history into another internally valid history) can erase that distinction. The scoped
patch detects required-row omissions and inconsistent retained authority; it cannot prove
resistance to arbitrary coordinated, self-consistent rewriting by trusted raw SQL. Do not
claim that guarantee. The existing FR-06/FR-07 contract requires checked atomic bundles,
typed retained authority, required relational completeness, and explicit recovery on
detected corruption; it does not specify an externally anchored protected-membership
witness or detection of a coordinated rewrite into a different internally valid history.
The R1-R6 review likewise requests no such witness. Consequently this bounded correction
needs no acceptance amendment: it preserves the existing guarantee and states its evidence
limit. If a stronger guarantee is later required, specify a separately versioned immutable
per-command membership witness and trust anchor first; silently backfilling one from
potentially damaged v5 rows cannot prove original membership. This is not permission to
leave any R1-R6 correction unfinished.

## Table-driven closure matrix and evidence discipline

Use disposable stores and the actual pinned Exqlite binding. Each corruption case starts
from its own valid fixture; mutate one dimension after recording exact ordered rows. The
expected assertion is the repaired contract, never a characterization that calls a crash
or observed bad result “passed.” For each rejecting authority read, assert error identity,
recovery status and a subsequent valid protected mutation refused with unchanged rows.
For each semantic/path rejection, assert process alive, healthy source stays ready, no
new rows/files, and a later valid operation succeeds. Keep source and archive hashes.

| Matrix | Cases and proof required |
|---|---|
| Whole successful phase chain | Ordinary accepted, protected accepted, stale durable rejection, explicit blocked/rejected, eventless commands before/after events, omitted/null reason, atom/string commands/proposals/facts; direct read and obsolete retry equality; clean reopen ready; validated backup; independently reopen snapshot; compare actual rows in all 18 tables and reconstructed state. |
| R1 omissions and bounds | Delete only result; orphan result/input/command using trusted FK-off corruption where needed; mismatched input binding; result seq -1, beyond max, before own event, at other command's block, legal historic/eventless zero. Test direct read, both retries, startup, source backup; deleted result never becomes `not_found`. |
| R2 malformed admission | Full term/type matrix above at proposal/result/collection/element and protected facts. Monitor Gateway; no DOWN/exit; all rows unchanged. Valid exact-ID retry bypasses these obsolete invalid proposals/facts. |
| Row/column language | For every supported type mutate each required field, unknown key/version, invalid Unicode/float/int overflow, canonical bytes, duplicated SQL binding and required FK neighbor. Cover all 18 registry entries, with nonempty unsupported rows rejected. |
| R4 all revision families | For projection/dependency inject bad projection body, event binding, revision; for ledger inject child/revision/type/allocation faults; for policy/control inject present unsupported scaffold. Both ordinary/protected submissions fail before durable semantic rejection or mutation, fence, then remain refused. Truly absent keys retain existing absent/stale behavior. |
| Cross-table protected relations | Delete reservation while claim remains; delete claim with surviving reservation; missing/retargeted generation/effect, duplicate supported reservation, unsupported statuses, units/funding mismatch and zero-available supported edge. Full validator and related live closure agree. Keep the coordinated-rewrite limit explicit. |
| R3 namespace Cartesian set | Every D/O main/WAL/SHM/journal/marker/recovered-family destination, absent and present; every prospective backup's own colliding sidecar; import source/archive-root/archive/manifest/planned publication files. Check initialize/migrate/gateway/import/backup, same VM and separate OS where applicable. The exact O-journal backup is refused before creation and survives no destructive reopen because no backup was written there. |
| R3 filesystem aliases | Preserve existing dot/dotdot/parent-symlink/hardlink/leaf checks; add nonregular sidecars, owner WAL/SHM, D-journal, existing recovery archive mismatch, new target with preexisting hot sidecars; feature-detect case-insensitive filename aliases and require one owner/rejection. Check original files unchanged after failed publication and normal source reopen. |
| R5 imported group | Empty, one valid line, interior invalid, invalid UTF-8, blank, CRLF, torn final, unknown version, >8 MiB with distinct first/middle/last records; compare every retained byte and full digest. Then delete first/middle/last/all, duplicate/skip numbering, gaps/overlaps, changed bytes with same length, wrong per-record/full hash, wrong classification/error/count/range and placeholder left committed. Rerun/startup/backup all refuse. |
| Import interruption | Fail before/after group rows, after manifest update/precommit, after commit/prepublication, publication failure and archive mutation during read using deterministic barrier. Prior authority preserved, no partial committed group, ordinary rerun only when complete retained evidence matches. |
| R6 transition matrix | Zero carrier; one create/update; repeated same entity; mixed entities/carrier-free events; missing/extra/reordered pairs; duplicate IDs; wrong entity/value/expected/new revision; stale first read and wrong intermediate revision. Accepted Gateway paths equal direct reducer/reconstruction and stored rows; invalid plans leave all tables unchanged; CAS affects exactly one row. |
| Corruption disposition | One shared corrupt tuple from every retained boundary, including result sequence, FK/schema, ledger, import and projection mismatch; source-backup discovered error fences. Separate engine I/O and destination failure controls; no branch-list omission allows later writes. |
| Fault regression | All insertion failpoints, real max_page_count FULL, read-only refusal, RLIMIT_FSIZE COMMIT I/O, before/after commit subprocess loss, checked rollback behavior and existing sync fixtures. Compare exact prior/absent-or-complete row states, not counts or digest-string lengths. |

Promote the v5 independent sync oracle structure into reusable owned test support: fixed
installation/repository IDs and complete A/CONTROL/B protected bundles, both ordinary-close
and hard-exit branches. The oracle independently constructs full expected rows; source and
backup content need not trust Gateway's own inventory to enumerate what is tested. Keep a
direct actual-SQL table inventory check so a table absent from production validation is
not also absent from the test oracle.

Run changed-file format, pinned compile with warnings-as-errors, focused durable-store/
legacy-containment/checkpoint suite, then the required isolated full suite with its actual
exit status. Report the previously observed unchanged benchmark-test failure separately
unless it is resolved with evidence; do not certify 471 passes from v5 author output.
Freeze a new candidate manifest only after these checks and preserve all earlier FAIL
reviews, withdrawn v4 and candidate identities. A new independent review is still needed.

## Bounded file ownership, ambiguity and preserved evidence

Production patch ownership: add `durable_store/authority.ex`; edit `record_codec.ex`
(types/reducer), `database.ex` (delegate validation/checked engine operations), `gateway.ex`
(normalized transport/read routing/CAS/fence/backup), `kernel.ex` (codec-first policy),
`protected_verifier.ex` (shared typed generation/derived facts), `path_identity.ex`
(namespace/identity), `owner.ex` (shared namespace/marker custody), `legacy_import.ex`
(group validator and publication preflight). If a tiny pure legacy-line classifier is
extracted, it belongs under durable_store, not general workflow Schema redesign. Keep
AtomicFile's general behavior outside this patch by giving the import publisher validated
bounded staging paths; any necessary shared publication interface change must be named
explicitly before implementation. No Coordinator/CLI/lifecycle/Herdr edits are required.

Test ownership: existing durable_store test directory plus focused `authority_test.exs`
or equivalent table-driven cases; shared exact-row oracle support; strengthen sync fault
tests and child assertions without changing the C hook's mechanism. Documentation:
DURABLE-STORE, new versioned diagnosis/response/candidate evidence and living PLAN in the
same eventual implementation commit. No edit to prior reviews or contract-history hashes.

No unresolved contract ambiguity blocks R1-R6. Historical result watermark semantics,
unsupported reserved tables, ordinary unclaimed intents, and local filesystem versus
hostile-account custody are resolved explicitly above. The full FR-06 result/event
envelopes and workflow/R5 semantics remain downstream; this design does not relabel the
current FR-07 scaffold as those completed capabilities. The coordinated-rewrite evidence
limit would require a new trust/witness requirement if a stronger claim were intended.

Preserve the independent VFS xSync evidence credited in review-v5: actual Exqlite
SQLite 3.53.4 connection; target WAL writes precede one xSync result 1034; no acknowledgment;
gateway fenced; ordinary close reopened with complete prior A/CONTROL and B absent;
hard exit reopened under explicit observed-exit recovery with complete A/CONTROL/B;
both executed same-ID retry paths and matched full rows plus backup/reconstruction.
Its final oracle digest was `680800ede0c777a395cc28b106da2ca28be65a025b479aa64512a9d5308e2b46`.
Native fixture C SHA256 remains
`508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d`.
The diagnosis does not rerun or independently re-credit those probes, and must not replace
them with counts. A new candidate repeats the affected tests using equivalent full-row
assertions; it need not invent a different sync mechanism.

This remains SQLite VFS xSync attribution, not physical fsync syscall failure, ENOSPC at
sync, power loss or media durability. FR-08 owns complete live/replay workflow migration;
FR-15a owns hostile OS/process/channel isolation; FR-17 owns activation/rollback; FR-19
owns physical capacity, retention, checkpoint/compaction/relocation; FR-22 owns lifecycle
acceptance. F02/F20/F21 have only their FR-07 portions specified here. Nothing authorizes
provider use, integration, deployment, activation, or a PASS on the rejected candidate.

The document SHA256 is supplied alongside this file rather than self-embedded.
