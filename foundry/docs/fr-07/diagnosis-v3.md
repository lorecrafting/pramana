# FR-07 v3 schema/path diagnosis and unified correction design

Date: 2026-09-13  
Reviewed boundary: `/private/tmp/pramana-fr07` at `f4a77de4ab3795716b00f807b4cd659e602654c4`
(implementation `5f3af472a3c59f2ad3dcbaae6d448145869ba9ca`, tree
`d7e6f4e40b64ce2f972b852414e865807af1cbf6`). This is an implementation-owner
diagnosis, not an independent review. It makes no repository edit, starts no live daemon,
and uses no provider, credential, Git promotion, integration, or activation.

Inputs read in full: `review.md`, `review-response.md`, `review-v2.md`,
`review-response-v2.md`, `candidate-v3.md`, and `/private/tmp/fr07-review-v3.md`, plus the
current durable-store modules/tests and the governing FR-07/FR-08 and transaction/storage
contract passages.

## Finding

The three review rounds expose two recurring design defects, not three isolated v3 bugs.

1. **There is no single persisted-record language.** `Kernel.validate_bundle/1` defines
   candidate admission; `Gateway.insert_result/4`, `decode_json/1`, and `decode_result/5`
   independently define materialization and live reads; `Database.validate_bodies/1` and
   `validate_*_rows/1` define startup; and `Gateway.replay_projection_events/1` plus
   `stored_projection_state/1` define reconstruction. These copies disagree about required
   keys, defaults, shapes, field/column bindings, and which event payloads mutate a
   projection. V2 accepted a scalar projection that startup rejected. V3 accepts an omitted
   result `reason_code`, writes it without adding the field, acknowledges COMMIT, then the
   first read/reopen rejects it. The one-way projection check is the same failure at a
   relational level: admission proves projection -> event, while replay interprets event ->
   projection.

2. **There is no single store pathname handed to every authority participant.**
   `Owner.canonical_database_path/1` first applies lexical `Path.expand/1`, derives the lock
   from that result, but `Gateway.open/2`, `Gateway.migrate/2`, and `LegacyImport.run/4` pass
   the original caller string to SQLite. `LegacyImport` contains a second, different
   canonicalizer. On `link/../authority.sqlite3`, the OS follows `link` before `..`, whereas
   `Path.expand/1` removes both lexically. The lock therefore protects one file while SQLite
   opens another. V2's final-leaf symlink/hardlink checks fixed only two aliases; v3's
   parent-symlink/`..` trace demonstrates the underlying split remains.

The correction must replace those parallel definitions. Adding `Map.put_new(reason_code)`,
another reverse-loop in `Kernel`, or one more path predicate would leave the next mismatch
available.

## Correction A: one typed persisted-record codec

Add `PramanaFoundry.DurableStore.RecordCodec`. It is the sole parser, normalizer,
validator, encoder, relational binder, and FR-07 projection-transition reducer for every
JSON/BLOB record the v1 gateway can write or accept as retained authority.

### Public contract

The module should expose only typed operations (names may vary, semantics may not):

```elixir
normalize_bundle(term) :: {:ok, normalized_bundle} | {:error, reason}
materialize_result(normalized_candidate_result, committed_seq) :: {:ok, stored_result}
encode(type, normalized_value) :: {:ok, bytes}
decode(type, bytes) :: {:ok, normalized_value} | {:error, reason}
decode_bound(type, bytes, relational_columns) :: {:ok, normalized_value} | {:error, reason}
projection_plan(events, projections) :: {:ok, ordered_transitions} | {:error, reason}
apply_projection(state, transition) :: {:ok, state} | {:error, reason}
reconstruct(event_rows, projection_rows) :: {:ok, state} | {:error, reason}
```

`encode/2` must validate/normalize first and encode the normalized value; there is no
"encode arbitrary map" persistence path. `decode_bound/3` must call the same decoder and
then compare every duplicated SQL column to the normalized body. Startup, direct result
read, same-ID lookup, backup validation, and reconstruction call these functions rather
than their own JSON predicates.

The codec owns schemas for the FR-07 records actually persisted: canonical command request,
candidate/stored result, event, projection, pending effect intent, protected claim,
reservation, and import manifest. For currently reserved downstream tables (receipt,
lease, policy/control revision, artifact reference), either define their exact current v1
scaffold envelope and column bindings or reject nonempty unsupported rows. Do not retain a
generic `is_map` acceptance path and then claim strict authority validation. Ledger rows
have no JSON body but remain covered by SQL constraints and an exact typed row validator in
the same startup pass.

All normalized records use **string keys only**. Atom-key and string-key API inputs may be
accepted for compatibility, but are converted once. A map containing both semantic forms
of one key is rejected as duplicate; unknown keys, floats, malformed Unicode, unsupported
versions, and wrong scalar/container types are rejected. Persistence and comparisons use
only the normalized value.

### Explicit optional/default semantics

The schema must declare defaults, rather than obtaining them accidentally from `Map.get/3`:

| Input field | Admission forms | Normalized value | Persisted form |
|---|---|---|---|
| bundle `events` | omitted or list | omitted -> `[]` | always present list |
| bundle `projections` | omitted or list | omitted -> `[]` | always present list |
| bundle `intents` | omitted or list | omitted -> `[]` | always present list |
| result `reason_code` | omitted, JSON null/Elixir `nil`, or nonempty string | omitted and null are the one explicitly declared equivalent: `nil`; string retained | key always present; JSON null or string |
| result `committed_seq` | forbidden from candidate | gateway supplies a nonnegative integer only after all bundle inserts | key always present |

No other omitted/null equivalence or implicit default exists. In particular, an omitted
collection and a null collection differ: null is invalid. Event `payload`, projection
`value`, intent `value`, and all identities are required. Cross-field result semantics are
also one rule in the codec: `accepted` requires null `reason_code`; `rejected` and `blocked`
require a nonempty reason. If compatibility requires a broader pairing, encode that exact
pairing in this one table, not in callers.

This intentionally applies the contract's "omitted and null differ unless the schema
explicitly normalizes them" clause. It resolves the v3 trace because an accepted result
without `reason_code` becomes a full normalized result before COMMIT; the exact same stored
shape is returned by direct read, idempotent retry, startup, and backup.

### Admission-to-reopen invariant

For every accepted new command, enforce this property in code and tests:

```text
normalize candidate
  -> materialize gateway fields
  -> encode
  -> insert with matching relational columns
  -> decode_bound immediately
  -> checked COMMIT/acknowledgment
  -> decode_bound by direct read and same-ID retry
  -> decode_bound during clean reopen
  -> decode_bound and reconstruct during backup
```

Every arrow must use `RecordCodec`; a value that cannot traverse the entire sequence must
be rejected before the transaction writes. Corrupt/unsupported retained data encountered
at any read boundary returns one common `{:authority_corrupt, type, identity, reason}`
classification, and `Gateway.transition_after_result/2` fences on that class. Storage I/O
errors remain a separate `storage_unavailable` class; semantic candidate rejection does not
fence.

## Correction B: exact event/projection coupling for the supported FR-07 format

This does not implement FR-08's lifecycle reducer. It defines only the projection carrier
already supported and persisted by FR-07.

An event is projection-changing iff its payload contains the reserved `"projection"` key.
That value has the exact shape:

```text
{namespace: nonempty string, entity_id: nonempty string,
 revision: nonnegative integer, value: object}
```

For a normalized proposal:

1. Extract projection-changing events in **event list order**.
2. Require a bijection with projection writes in **projection list order**. The corresponding
   projection must have `last_event_id == event.event_id`, and its namespace, entity ID,
   revision, and value must equal the event transition exactly. Thus neither an extra
   projection nor an event-only transition can commit.
3. Reject duplicate event IDs, duplicate `last_event_id` ownership, reordered pairs, and
   duplicate/missing transitions before SQL.
4. Inside the same `BEGIN IMMEDIATE`, seed each touched entity from its authoritative
   current projection. The first transition's expected revision must match the command's
   complete initial read (`absent` maps to proposal `-1`); later transitions for that entity
   must use the revision produced by the previous event. Every new revision is exactly
   previous + 1. This avoids today's `Map.new/2` loss of duplicate entity writes.
5. Apply writes in event order. Compare the reducer's final touched state with the rows that
   will be/live in `projections` before returning the transaction result.

`RecordCodec.apply_projection/2` is used for both the in-transaction plan and ordered replay.
Startup reconstructs from all retained events and compares the full reconstructed map
`{namespace, entity_id} -> {revision, last_event_id, value}` with decoded stored projections.
Backup validates the source before `VACUUM INTO`, opens/validates the snapshot through the
same startup path, compares all ordered table content, and runs this same reconstruction.
There is no separate permissive backup decoder.

Events without the reserved key (including the opt-in `legacy_event`) have no projection
transition and require no projection write. This preserves the narrow FR-07 compatibility
writer. Defining lifecycle meaning for `ticket_*`, review, control, budget, and reset events,
and routing all mutations through one full reducer remain FR-08.

## Correction C: one canonical database identity before ownership or SQLite

Add `PramanaFoundry.DurableStore.PathIdentity` and make its returned struct—not a caller
string—the value passed through owner acquisition, database open/initialize/migrate,
import, and backup destination creation.

Use a strict **reject-noncanonical** contract. It is smaller and safer than trying to
support aliases:

1. Input must be a nonempty absolute binary path with no NUL. Inspect its raw components
   before normalization. Reject `.`, `..`, repeated separators, trailing separator, or any
   representation whose component-wise rejoin is not byte-identical. Never call
   `Path.expand/1` before this check.
2. Walk from root with `File.lstat/1`. Every parent component must already exist, be a
   directory, and not be a symlink. Reject a symlink anywhere in the chain, including a
   dangling link or loop. This directly rejects the v3 `link/../authority.sqlite3` input;
   SQLite never sees it.
3. Existing-database mode requires a regular leaf with link count exactly one. Record
   `{major_device, inode}` plus the accepted absolute path and parent identity. A symlink
   leaf, hardlinked leaf (including the original name once link count > 1), directory,
   device, FIFO, or socket is rejected.
4. New-database mode requires an absent leaf and an existing nonsymlink directory parent.
   Its pre-creation identity is `{parent_major_device, parent_inode, basename}`. Acquire the
   owner sidecar for this identity first, create the database with exclusive create, then
   resolve it in existing mode and retain the resulting inode identity. Missing parent
   directories are rejected; initialization does not silently create an unvalidated tree.
5. Derive WAL/SHM/owner/unclean paths only from `identity.path`. Validate existing owner and
   marker sidecars with the same no-symlink/no-hardlink/nonregular rules before opening or
   writing them.
6. `Owner.acquire/2` stores the identity in `%Owner{}`. Re-stat and compare the leaf identity
   immediately before and after acquiring the exclusive owner lock, and immediately before
   and after `Exqlite.Sqlite3.open`. Any change fails closed. `Database.open` receives only
   `owner.identity.path`; it never receives the original argument.
7. `Gateway.init/open`, `Gateway.migrate`, and `LegacyImport.run` obtain one identity once,
   acquire its owner, and use `owner.identity.path` for every SQLite call. Status reports
   that canonical path. Import path-collision checks compare typed identities: existing
   files by device/inode and absent targets by parent-device/parent-inode/basename. The
   source, digest archive, manifest, database, and every sidecar are compared through this
   same utility; delete `LegacyImport`'s private canonicalizer and `same_file?/2`.
8. `Gateway.backup` resolves its absent destination with the same new-target rules before
   `VACUUM INTO`, then resolves/validates the created file as an existing identity before
   opening it.

This gives all common entry points the exact same path string and identity. The explicit
re-stat checks limit rename/substitution races possible with pathname-only Exqlite. Final
hostile-account filesystem isolation/openat-style descriptor custody remains FR-15a; it is
not claimed here. Common lexical/symlink/hardlink aliases must nevertheless be closed now.

## Exhaustive test matrix

### Codec and phase equivalence

| Class | Cases | Required assertion |
|---|---|---|
| Key representation | all-string; all-atom; mixed nonduplicate; atom+string duplicate | first three normalize to identical string-key value; duplicate rejects before SQL |
| Result optional field | accepted with omitted/null `reason_code`; accepted with string; rejected/blocked with omitted/null/empty/nonempty; candidate-supplied `committed_seq` | declared equivalents persist identical bytes/results; invalid pairs and supplied gateway field reject before SQL |
| Bundle defaults | each collection omitted, `[]`, null, scalar | omitted and `[]` normalize identically; null/scalar reject |
| Shape/version | scalar body; missing required; unknown key; v0/v2; float; invalid UTF-8/surrogate; empty IDs | reject before SQL at admission; injected retained form fences startup/read |
| Round trip | every supported record type and boundary values | `decode(type, encode(type, normalized)) == normalized` |
| Relational binding | mutate each duplicated column or body field independently (schema, ID, type/status, digest, revision, last event, disposition/reason/seq) | `decode_bound` rejects; startup and any live read fence |
| Full phase property | generated valid bundles across optional forms, 0/many nonprojection events, 0/many transitions, and pending intents | commit acknowledgment implies equal direct result, same-ID result, clean reopen ready, backup ready, source/backup content equality, and equal reconstruction |
| Corruption classification | malformed bytes, unsupported version, legal JSON/wrong semantics at command read, retry, startup, source backup, snapshot reopen, reconstruction | every path returns the common corrupt-authority class and prevents a later mutation |
| Import manifest | placeholder/final exact shapes, omitted/extra/wrong count/range/digest fields, body/column mismatch | valid import/replay/reopen succeeds; every mismatch fails closed without replacing originals |

Use a property generator bounded to the v1 semantic domain (null/booleans/signed 64-bit
integers/Unicode scalar strings/lists/unique-key objects; no floats). For every generated
value accepted by admission, assert the full phase property above. Separately mutate one
field after encoding to ensure startup is not merely reusing happy-path fixtures.

### Event/projection coupling

| Events | Projection writes | Order/revision | Expected |
|---|---|---|---|
| no carrier | none | n/a | accept; replay unchanged |
| one carrier | exact one | create absent -> 0 | accept; live equals replay |
| one carrier | missing | n/a | reject before SQL (v3 regression) |
| no carrier | extra write | n/a | reject before SQL |
| one carrier | wrong event ID/namespace/entity/revision/value | n/a | reject before SQL |
| two entities | two exact writes | same order | accept |
| two entities | exact writes reversed | reversed proposal order | reject |
| same entity twice | two exact writes | absent -> 0 -> 1 | accept; one final row at revision 1 |
| same entity twice | two exact writes | gap, duplicate revision, wrong second expected, command read names final rather than initial | reject atomically |
| duplicate event IDs or duplicate projection ownership | any | any | reject before SQL |
| mixed projection/nonprojection events | only carrier matches | event-relative order preserved | accept; noncarrier ignored by projection reducer |
| corrupted retained order/body with same row counts | existing projection unchanged or adjusted | any | startup/backup reconstruction mismatch and fence |

Run each accepted row through ordinary and protected transactions where applicable, then
direct read, lost-reply retry with obsolete proposal/facts, clean stop/reopen, and backup.
Assert complete table hashes before and after every rejected/faulted case.

### Database identity and aliases

Run gateway-vs-gateway (same VM and separate OS), gateway-vs-importer, migrate, and where
applicable initialize/backup for each row:

| Path class | Expected |
|---|---|
| exact absolute existing path | first owner ready; second excluded; importer/migrate excluded while live |
| relative path; `.`; `..`; repeated slash; trailing slash | rejected before owner or SQLite |
| v3 `parent_symlink/../database` | rejected before owner; neither wrong sidecar nor DB touched |
| symlink in first/middle/final component, absolute/relative target, chain, dangling, loop | rejected before owner/SQLite/import |
| hardlink leaf, presented by alias and by original | both rejected once link count > 1; live original authority remains fenced from a new entrant |
| case/spelling alias on case-insensitive filesystem (feature-detect) | resolves to the same exclusion outcome; never two ready gateways |
| directory, FIFO, socket, device leaf | rejected as nonregular without modifying it |
| absent leaf under existing real parent | accepted only by initialize/new-target or backup destination; existing/open/import report absent |
| absent leaf under absent or symlink parent | rejected; no implicit unvalidated `mkdir_p` |
| concurrent initialize of same absent target | exactly one creates/initializes; loser reports occupied/unavailable; created DB validates |
| preexisting symlink/hardlink/nonregular owner or marker sidecar | rejected without following or overwriting it |
| leaf swapped/renamed or hardlinked at deterministic pre-lock, post-lock/pre-open, post-open verification hooks | identity mismatch; no ready acknowledgment |
| import source/archive/manifest equal lexically, same inode, or same parent+basename target as DB/any sidecar/each other | reject before archive/database/manifest mutation; original bytes unchanged |
| backup destination aliases source DB/sidecar or is substituted between validation and open | reject/fence; source authoritative hashes unchanged |

After every alias rejection, prove the original gateway remains ready, the alias cannot
commit, offline import/migrate cannot enter, and unrelated files retain exact hashes.

## Exact minimal production changes

1. **Add** `foundry/lib/pramana_foundry/durable_store/record_codec.ex` with the schema
   registry, normalization/default rules, typed encode/decode/binding, projection-plan and
   shared reducer described above.
2. **Add** `foundry/lib/pramana_foundry/durable_store/path_identity.ex` with strict raw-path
   validation, component walk, existing/new identity structs, equality/collision helpers,
   sidecar validation, and revalidation.
3. **Change** `durable_store/kernel.ex`: replace private record/key/version validators and
   one-way `projection_event_consistency/1` with a call returning the normalized codec bundle
   plus only kernel-level disposition/operation policy. Do not keep a second schema copy.
4. **Change** `durable_store/gateway.ex`:
   - `initialize/2`, `migrate/2`, `init/1`, and `open/2` consume one `PathIdentity` and pass
     only `owner.identity.path` to `Database`;
   - `do_transact/6`, `do_verified_transact/6`, and `commit_bundle/8` normalize only after
     the existing-ID lookup, preserving lost-reply ordering;
   - `insert_events`, `insert_projections`, `insert_intents`, and `insert_result` persist
     codec-normalized records, with result materialized before encoding;
   - `existing/4` and `fetch_command/2` use `RecordCodec.decode_bound(:result, ...)`;
   - `check_expected_revisions`, `required_projection_reads`, and insertion ordering consume
     the codec's complete ordered projection plan;
   - `backup_database`, `verify_backup`, `reconstruction_evidence`,
     `replay_projection_events`, and `stored_projection_state` delegate to shared path/codec
     validation and reducer; remove duplicate decoders;
   - `transition_after_result` fences the single corrupt-authority error class.
5. **Change** `durable_store/database.ex`: `initialize/2` and `open/1` accept/use the validated
   identity path; expose the internal validation pass for source-backup validation; replace
   `decode_body`, `decode_object`, `validate_body_rows`, and the four hand-coded relational
   validators with table-to-codec dispatch and shared reconstruction. Keep SQLite pragma,
   FK, sequence, SQL schema, and transaction checks here.
6. **Change** `durable_store/owner.ex`: store `%PathIdentity{}` in the owner; remove
   `canonical_database_path/1`; derive/validate every sidecar from the identity; revalidate
   around lock acquisition and release.
7. **Change** `durable_store/legacy_import.ex`: resolve/acquire the database identity once,
   open its exact path, validate source/archive/manifest with `PathIdentity` collision
   helpers, and use `RecordCodec` for placeholder/final manifest encode/read. Remove
   `canonical_existing`, `canonical_target`, `canonicalize`, and `same_file?`.

Minimum focused test changes are: add `durable_store/record_codec_test.exs` and
`durable_store/path_identity_test.exs`; extend `review_corrections_test.exs` with the exact
v3 traces and full phase/property matrices; extend `gateway_test.exs`,
`legacy_import_test.exs`, and `durable_store_owner_probe.exs` for shared entry points and
separate-OS aliases. Existing crash/write-fault tests remain and must pass unchanged.

Update `DURABLE-STORE.md`, the candidate response/evidence, and living plan only after the
implementation and fresh tests describe the actual result. Preserve all three FAIL records.

## Scope and remaining gate

This correction closes the recurring FR-07 admission/read/startup/reconstruction and local
database-alias classes. It does not migrate Coordinator mutations, define the complete
workflow reducer, implement downstream lifecycle/budget/control semantics, prove hostile
kernel OS isolation, update Git refs, or deploy anything; those remain FR-08/15a/17 and
later tickets.

The specifically attributed failed-fsync-through-Exqlite acceptance case remains separately
unpassed. This diagnosis neither relabels the `RLIMIT_FSIZE` COMMIT/write failure nor waives
the governing FR-07 requirement. It still needs an actual controlled binding/VFS sync-fault
result or an explicitly approved contract exception before FR-07 can receive acceptance.
