# FR-07 response to focused v3 review and diagnosis

This implementation-owner response addresses the exact independent v3 FAIL in
`review-v3.md`, SHA-256
`b5f7fe402404d8d8e9a41d55a779b56035ce1c39faf4515b82874d88cd9489e6`, using the
required focused diagnosis in `diagnosis-v3.md`, SHA-256
`5f1d7d7113a47e5db07219d933b7f60c491ef130e29054b5b36dc040e591c6f7`.
All rejected candidates and review records remain immutable history. This response is
not independent acceptance.

## Disposition

- **V3-R4 corrected through one record language.** `RecordCodec` is now the sole
  normalization, defaulting, encoding, decoding and relational-binding definition for
  candidate/stored results, events, projections, pending intents, claims, reservations,
  canonical command requests, import manifests and reserved v1 scaffold bodies. The only
  defaults are omitted accepted-result `reason_code -> nil` and omitted bundle collections
  `-> []`. Candidate results are materialized before insertion. Admission, immediate
  materialization, direct read, same-ID retry, startup, backup and reconstruction use the
  same codec. Corrupt retained authority uses one `authority_corrupt` class and fences.
- **V3-R7 corrected through a bijective reducer.** Every event carrying the reserved
  projection transition has exactly one corresponding projection write in the same order,
  and every projection write has one carrier. Missing/extra/reordered transitions,
  mismatched values/identities/revisions and duplicate ownership reject before commit.
  Multiple transitions for one entity use the command's one initial authoritative read,
  then advance in order. The same reducer reconstructs source and backup state and compares
  complete values, so same-count corruption is detected.
- **V3-R6 corrected through one path identity.** Raw relative/noncanonical paths,
  dot/dotdot, repeated/trailing separators, parent or leaf symlinks, hardlinks and
  nonregular database identities reject before owner or SQLite. The owner stores and
  revalidates one `{device,inode,path,parent}` identity around lock and database open.
  Initialization uses a validated absent-target identity and no implicit directory tree
  creation. Gateway, migration, database, importer and backup share the exact identity;
  the importer no longer has a private canonicalizer.
- **Attributed sync acceptance implemented.** A strictly test-only loadable SQLite
  extension replaces only the tested connection's WAL-file `xWrite`/`xSync` methods. It
  delegates and records successful WAL writes, then returns `SQLITE_IOERR_FSYNC` (1034)
  exactly once from `xSync` during the real checked Exqlite COMMIT. Ordinary and hard-exit
  fixtures prove no success acknowledgment, recovery fencing, complete prior contents,
  explicit owner recovery, reconstruction, and ambiguity-safe same-command retry. This is
  an attributed SQLite VFS xSync fault, not proof of a failed kernel `fsync(2)` syscall or
  physical-media durability. FR-19 retains that broader filesystem/WAL/checkpoint matrix.

## Finding preservation

Prior V2-R2a/R2b/R4a/R4b/R6/R7/R8 corrections remain exercised: durable stale rejection,
unsupported child-allocation refusal, same-ID lookup before current facts, strict result
fencing, all-table backup, insertion failpoints, RLIMIT_FSIZE COMMIT/write failure and
hard-crash boundaries. The unified correction replaces duplicated validators rather than
adding exceptions to them.

## Audit obligation mapping

- **F02 retained:** checked commit precedes acknowledgment; write/FULL/xSync/crash errors
  cannot launch later work; same-command retry resolves an ambiguous commit; malformed,
  duplicate/noncanonical, unsupported-version and relationally mismatched authority fences
  instead of resetting; torn/oversize JSONL bytes remain archived and explicitly invalid.
- **F20 FR-07-owned foundation retained:** authoritative event sequence numbers, bounded
  indexed table access, a coherent engine snapshot and one serialized store/import owner
  are implemented and tested. Retention, capacity publication, scheduling and operational
  compaction remain explicitly with FR-19 rather than being collapsed into store closure.
- **F21 FR-07-owned foundation retained:** import is offline and owner-exclusive; unknown
  path/digest evidence blocks; the verified digest archive is read; source bytes are not
  removed; aliases/collisions fail closed. General relocation journals, cross-device copy,
  rollback and source-removal policy remain FR-19 obligations.

FR-08/15a/17/19/22 remain downstream. This candidate does not migrate Coordinator mutation
paths, claim full workflow replay, establish hostile-worker OS isolation, integrate Git,
activate a build, operate the live daemon or call a provider.
