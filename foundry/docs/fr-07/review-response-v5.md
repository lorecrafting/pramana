# FR-07 v5 review disposition for v6

The independent v5 verdict remains **FAIL** and is preserved byte-for-byte in
`review-v5.md`. V6 implements the focused `diagnosis-v6.md` correction rather than
recasting that verdict.

- R1: `DurableStore.Authority` now owns command/input/result totality, event/result and
  `sqlite_sequence` bounds, scoped reads, startup validation, backup validation, and the
  common corruption fence. Missing or inconsistent acknowledged authority cannot become
  `not_found` or remain ready.
- R2: candidate and retained values enter through `RecordCodec` before policy or SQL
  decisions. Non-map, improper-list, duplicate-key, malformed nested and column/body
  mismatch cases return typed errors without killing the gateway.
- R3: `PathIdentity` defines the full authority/owner/marker/recovery namespace for
  initialization, ownership, import and backup. Dot/dotdot, parent/leaf symlinks,
  hardlinks, prospective SQLite sidecars and unrelated publication state are refused or
  preserved before SQLite opens them.
- R4: ledger generations, claims and reservations use one typed retained contract at
  admission, write, scoped revision read, reopen and backup. Unsupported children and
  cross-generation/cardinality/funding faults fence; the supported zero-available root
  needs no invented reservation.
- R5: import validation streams the retained byte sequence, checking every line number,
  byte range, row digest, classification, aggregate digest/count/error manifest and the
  verified archive. Interrupted or mutated imports roll back; rerun never silently fills
  missing authority.
- R6: live projection writes and reconstruction use the same ordered
  `RecordCodec.apply_projection/2` reducer and reject missing, extra, reordered or
  revision-inconsistent transitions.

The v5 xSync evidence remains narrowly credited. V6 retains the test-only connection-
scoped WAL VFS fault and promotes exact ordered rows for all 18 tables across fault,
ordinary/crash reopen, backup and same-command retry. This is VFS xSync attribution, not
a physical kernel `fsync(2)`, power-loss or media-durability claim.

Limits remain explicit: FR-08 owns full workflow/event migration; FR-15a owns hostile
process/account isolation; FR-17 owns activation; FR-19 owns physical maintenance,
capacity/checkpoint/retention behavior; FR-22 owns end-to-end acceptance. The current
schema does not detect a trusted coordinated self-consistent rewrite without a separate
external witness, which the present contract does not require.

Recovered execution on current main base `75a56c13ebafa0ab7e67f2cf12f47ad84aad2ebc`:

- pinned Elixir 1.20.3 / OTP 29.0.5 warnings-as-errors compile: exit 0, 90 files;
- fresh `TMPDIR`, durable-store suite seed 9044: 68 passed, exit 0;
- no daemon, provider, credential, deployment or activation operation was performed.

A fresh independent review is still required; this response is implementation-owner
disposition, not a PASS.
