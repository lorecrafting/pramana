# FR-19A operational storage candidate

Date: 2026-09-19

## Immutable identity and scope

- Implementation revision: `0391468926bc8f9c1591e8a619d80d6661cf9a5d`.
- Implementation tree: `8db0157cec66fbf140a38853f6259be9d864e4be`.
- Exact base: `4a9098d8f6d8bcfbe21c0276f14230d888d04038`.
- Branch: `repair/fr19a-operational-storage`.
- Worktree: `/Users/raymondluong/dev/pramana-fr19a`.

This candidate owns only FR-19A. It does not implement FR-19B retention, compaction or
cross-device relocation repair, FR-08 protected primitives, live-provider work, daemon
rollout or activation. Independent review remains required.

## Implemented baseline

- `Gateway.operational_health/1` publishes last durable sequence, database/WAL bytes,
  SQLite page capacity and physical free bytes from a fixed `df -Pk` probe. The external
  probe is isolated, monitored and bounded to five seconds by default; unavailable,
  malformed, exited and timed-out results remain explicit `unknown` values.
- `Gateway.recent_events/2` is a diagnostic-only indexed descending-sequence query with an
  enforced 1–1,000 row limit. It does not decode or replace authoritative replay.
- `Gateway.checkpoint/1` serializes a real `wal_checkpoint(TRUNCATE)` through the sole
  gateway connection and compares complete authority content plus replayed projections
  before and after. Storage/corruption failure fences mutations.
- `Maintenance.verify/2` acquires the same cross-process owner lock, refuses a live store,
  opens through the accepted validator and returns complete content plus deterministic
  replay evidence. It has no repair, removal or relocation operation.
- Existing SQLite `VACUUM INTO` backups are checked against complete ordered content and
  reconstructed state, then reopened successfully through offline verification. Tests
  retain old effect, claim, ledger-generation and reservation rows across backup,
  checkpoint, hard process interruption and recovery.
- `Relocation.execute/2`, `resume/2` and `rollback/2` fail before journal/path access with
  `{:relocation_disabled, :fr19b_required}`. Historical relocation success/recovery tests
  remain in place but are explicitly skipped until FR-19B; read-only planning remains
  tested.

## Fault evidence and exact attribution

The owned FR-19A tests perform a real SQLite WAL checkpoint, hard-exit a separate BEAM
immediately after a real checkpoint and immediately after `VACUUM INTO`, and overwrite and
sync 256 bytes of a previously valid SQLite file before reopening it. The source authority
is never replaced or removed; corruption enters recovery, maintenance is refused and the
pre-damage verified backup retains complete claim/ledger evidence. The hard-exit cases
require explicit unclean-owner recovery evidence and reproduce the complete baseline after
reopen.

These process boundaries are deterministic fault seams. They are not physical power-loss
or media failures. Accepted FR-07 evidence retains these narrower classifications:

- `PRAGMA max_page_count` is a real SQLite logical-full error, not filesystem ENOSPC.
- `RLIMIT_FSIZE` is a real kernel file-size-limit I/O failure, not filesystem ENOSPC.
- the loadable VFS extension returns an injected SQLite `SQLITE_IOERR_FSYNC` from WAL
  `xSync`; it is not an observed kernel `fsync(2)` or device failure.

The host had 287,327,356 KiB reported available on `/System/Volumes/Data` during candidate
freeze, so safely inducing physical ENOSPC was unavailable. Physical filesystem ENOSPC,
kernel sync failure, power loss, controller/cache flush and media durability are not
proved. No privileged mount, destructive fill or live-store experiment was attempted.

Measured/enforced operational bounds are 1,000 rows per recent-event call and a five-second
default capacity-probe deadline. No throughput or latency claim is made from the test
durations.

## Executed evidence

Pinned Elixir 1.20.3 / OTP 29.0.5 with canonical `TMPDIR=/private/tmp` and isolated build
root `/private/tmp/fr19a-build`:

- `mix format --check-formatted`: exit 0.
- `mix compile --force --warnings-as-errors`: exit 0; 107 project files.
- focused FR-19A storage/relocation containment, seed 1914: exit 0; 10 passed.
- durable-store suite excluding the pre-existing native `sync_fault_test.exs`, seed 1915:
  exit 0; 85 passed.
- all Foundry tests except `sync_fault_test.exs`, seed 1913: exit 0; 541 passed and 13
  intentional historical relocation skips.
- repository documentation check: exit 0; 80 passed.

Two checks did not pass and are not acceptance evidence:

- `sync_fault_test.exs` exited 139 in this worktree at seeds 1907, 1908 and 1912. The same
  test passed 2/2 at seed 1912 in the accepted FR-07 worktree, and both loaded Exqlite NIFs
  had SHA-256 `7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.
  This candidate therefore does not claim a successful current-tree VFS sync rerun.
- `mise exec -- elixir ci/run.exs --output /private/tmp/fr19a-ci-artifacts` compiled cleanly
  but failed 74 durable-store tests because the macOS runner created its isolated temporary
  root below symlinked `/var/folders`, which the accepted strict `PathIdentity` correctly
  rejects. Result: 468/542 passed, 13 skipped and 1 excluded. Running without `mise`
  separately failed the runner's pinned toolchain check, as expected.

## Implementation manifest

The candidate record itself is excluded from this implementation manifest.

```text
9e6a3d82b876c5ab56ef0e920e1310a32cb4d81522baa45a70490c6a8669293f  foundry/README.md
772ea67f949c077ec0050ed64a0576261eb965e1779372458fa00fb9c7bbc86e  foundry/docs/DURABLE-STORE.md
eacaff5508e7e9260d0b2df013afce00c2990c9728b8f34eb2ffd8a7dd5e2b0d  foundry/docs/REPAIR-PLAN.md
6017979eb873e6bb6de287bd67ac201b4c440f3decfd710aacde2721c98b20e3  foundry/lib/pramana_foundry/durable_store/capacity.ex
3001ed35c061621e91a37a38d5f40d8c9c2d9ada874073cca6be4284f881e135  foundry/lib/pramana_foundry/durable_store/gateway.ex
eb4a5c8efb13a2da1f730730572f11059bf029b75a755a040673a6c259ac42bc  foundry/lib/pramana_foundry/durable_store/maintenance.ex
df2dcc9c214384bba83dbbf2938fd12c7c462f8e446e62f9e6cea6aa8f51ae80  foundry/lib/pramana_foundry/relocation.ex
bbaaa66c93c767f5333bdf902d52473bb76f3791a44f11e50fedae4640d7e463  foundry/test/pramana_foundry/durable_store/operational_storage_test.exs
b9e27eb90968b36c0b711cb1d0390719929c4068f8b58f239f1d541d6e4a1bc0  foundry/test/pramana_foundry/relocation/crash_recovery_test.exs
a1a29f8f7d243fdc33a04de1d2a68c4b9fc39b0b8ddc33e9cc2a9636a8ffbe2a  foundry/test/pramana_foundry/relocation_containment_test.exs
a09cf5ff88473bcc1ef3541238994198becba0a759761159a37b5f247cdca3ac  foundry/test/pramana_foundry/relocation_test.exs
1fe6c8b11015b0317333f27bcaf5c9e8b726a11a1c864bcb20b0f1495ca4f8a7  foundry/test/support/fr19a_maintenance_crash_fixture.exs
```
