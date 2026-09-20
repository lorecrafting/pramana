# FR-07 response to independent review

This response addresses the exact independent FAIL in `review.md` (SHA-256
`bba396dd837ad06018c460a4dd68223792d536542b7fbdb53cfaea2092597f30`). It does not
replace that review or assert an independent PASS. A new immutable candidate requires
renewed review.

## Disposition

- **R1 corrected:** candidate proposals accept only known command/event operations and
  pending intents whose domain-tagged digest exactly binds effect identity and bounded
  operation. Candidate rows cannot assert issued/terminal state, claims or reservations.
- **R2 corrected:** complete projection and protected read sets are checked against SQLite
  inside `BEGIN IMMEDIATE`, including read-only dependency, policy, control and ledger
  keys. Stale reads and rejected decisions with domain mutations roll back as semantic
  rejection without fencing a healthy store.
- **R3 corrected:** actor/command digest and durable same-ID lookup precede current kernel
  or protected-fact validation. A lost-reply retry returns the original result even when
  its old proposal/current facts are no longer valid.
- **R4 corrected:** startup checks foreign keys, event sequence, metadata and all retained
  authority JSON bodies/versions. Corruption found by a live result read immediately
  enters recovery and prevents later writes.
- **R5 corrected:** resolved path and inode collisions with source/archive/manifest and
  database sidecars are rejected. Import holds the persistent offline owner, parses the
  verified immutable archive, rolls back interrupted line ingestion, and reruns after
  external manifest publication failure.
- **R6 corrected:** a persistent SQLite exclusive-owner sidecar excludes same-VM and
  separate-OS gateways and the importer. A durable unclean marker makes owner loss
  ambiguous until recovery evidence is supplied.
- **R7 corrected:** `VACUUM INTO` verification covers every authority, import, metadata and
  sequence table with stable ordering, exercises nonempty protected/import/control rows,
  validates relational reconstruction and matches a command reconstruction digest.
- **R8 partially corrected:** failpoints after every bundle table prove rollback over a
  previously populated protected store; hard exits cover complete protected bundles;
  import interruption/publication reruns and migration reruns are exercised. A real
  nonprivileged OS `RLIMIT_FSIZE` probe reaches SQLite `COMMIT` and returns checked
  `disk I/O error` without acknowledgment, preserving prior content. Exqlite 0.40.0 and
  this host expose no controlled failed-fsync hook, so a specifically failed fsync syscall
  remains unpassed evidence and must receive independent acceptance disposition.
- **R9 corrected:** all U+0000–U+001F scalars use exact lowercase `\\u00xx`-form escapes;
  command and effect identities use explicit versioned domain tags, with exact byte/hash
  vectors.

## Preserved downstream scope

FR-08 still owns complete command migration and the single replay/apply reducer; FR-15a
owns hostile kernel host isolation and final protected predicates; FR-17 owns Git
integration/activation; FR-19 owns operational checkpoint, retention, relocation and
physical fault matrices. The opt-in compatibility writer is not activation, deployment,
or proof that legacy Coordinator mutations use this gateway.
