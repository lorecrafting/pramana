# FR-07 response to renewed review

This response addresses the exact independent v2 FAIL in `review-v2.md`, SHA-256
`4dab766e7616e40630d2000499319f37ee8216851f5a73f25cf74f6a2c9e8ad4`. The rejected
v2 candidate and both prior review records remain immutable history. This author response
does not assert independent acceptance.

## Disposition

- **V2-R4a corrected:** ordinary and protected idempotent lookups use the strict result
  reader. Malformed or unsupported stored results transition the gateway to recovery;
  no later mutation is admitted. Backup/reconstruction corruption has the same fence.
- **V2-R4b corrected:** admission requires map-valued projections and payloads plus strict
  result semantics. Stored event, projection, pending-effect and result envelopes retain
  their identity/version fields and are checked against relational columns at startup and
  result reads. Candidate-valid commits reopen under the same contract; invented result
  dispositions and body/column mismatches fence.
- **V2-R6 corrected:** gateway and importer ownership begins by rejecting database
  symlinks, hardlinks and non-regular files. Same-VM, separate-OS and offline-import alias
  regressions prevent a second authority path.
- **V2-R2a corrected:** an authoritative in-transaction revision conflict commits only the
  authenticated input, command and a generated rejected result. It creates no domain or
  protected rows, and same-ID retry returns the immutable rejection.
- **V2-R2b corrected by scope refusal:** FR-07 rejects every child/parent ledger generation.
  A supported new top-level generation must exactly fund its verified reservations; it
  cannot carry caller-declared surplus. Parent conservation/debit remains with the owning
  ledger implementation and is not represented as authoritative early.
- **V2-R7 corrected:** projection-changing events carry the complete supported projection
  transition. Backup verification executes the ordered reducer, compares reconstructed
  state with stored projection envelopes, and detects same-count semantic corruption.
- **V2-R8 strengthened:** insertion failpoints and the real `RLIMIT_FSIZE` SQLite COMMIT
  fault now compare complete before/after table hashes and reconstruction state. Hard-exit
  fixtures preserve prior protected history and verify the complete old/new bundle count.
  A specifically attributed failed fsync remains unavailable and unpassed; the existing
  limitation is unchanged rather than relabeled.

FR-08/15a/17/19/22 downstream ownership and the opt-in-only compatibility boundary remain
unchanged. No deployment, activation, live daemon or provider operation occurred.
