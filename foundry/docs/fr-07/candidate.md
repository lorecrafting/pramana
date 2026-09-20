# FR-07 candidate

Frozen 2026-09-13 for independent review.

## Identity and scope

- Base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- Implementation commit: `53738a005eefac1cd30376243767ccbcd9b472db`.
- Implementation tree: `a6ddde723739ddb7aaf26391fc469d54fc803193`.
- Worktree/branch: `/private/tmp/pramana-fr07-replay4`, `repair/fr07`.
- Binding: Elixir 1.20.3/OTP 29.0.5, `exqlite == 0.40.0`; `mix.lock` pins
  Exqlite and its transitive packages. Exqlite's native SQLite NIF is the required
  in-process database engine. No new Python implementation exists. The existing test
  suite still contains unrelated historical Python probes.
- The fetched `foundry/deps/` directories are untracked and excluded. No root-worktree
  CLI/Coordinator changes, local state, provider state or credentials are present.

FR-07 owns the new SQLite schema/gateway, pure candidate proposal validation, protected
capability/verifier boundary, canonical request digest, opt-in compatibility event writer,
offline JSONL evidence import, coherent SQLite-engine snapshot and their tests/docs.
It does not migrate all Coordinator mutations or implement the one replay reducer (FR-08),
prove OS-account/capability isolation and full safety predicates (FR-15a), dispatch/reconcile
effects (FR-10), operate retention/checkpoint/compaction/relocation (FR-19), activate a
release (FR-17), or establish lifecycle acceptance (FR-22).

## Reviewed paths and SHA-256

```text
33136e5c3c25e92976762c3a581380d24d3ca2771162557d9d42bb0d4cc74c83  foundry/README.md
11011de2498e324355be95bc1c17667663ebedc57dd62467adb5df329691c6f0  foundry/docs/DURABLE-STORE.md
ebbf593cfb9acb975ff37ae12affcea5f9dae1896b2f4b679f56f83f85733182  foundry/lib/pramana_foundry/durable_store/compatibility_writer.ex
7818b553bde34fb3dfd6e749d4c6d82d60f9c30c2dead1569576b8b12bc14c5f  foundry/lib/pramana_foundry/durable_store/database.ex
b706e1976f8cd09f9fa0b311e099343e3498586539c1e92c1b78e5fa3f42e8a0  foundry/lib/pramana_foundry/durable_store/encoding.ex
b85aa65f52eb4da8f6185e60b9b4ab58a5ecf8ea93889a1f82e2de193baefe5b  foundry/lib/pramana_foundry/durable_store/gateway.ex
191c8038857005a4ceb6f637f14c5d8a1e4b04027b103b8c23ee23fbe9703c67  foundry/lib/pramana_foundry/durable_store/kernel.ex
2b56047016cb74ef6354604bcbb2e0809823bf9212842ff4304616ccd4fadb4d  foundry/lib/pramana_foundry/durable_store/legacy_import.ex
4a3dd40378a7d02fc490b5f72d9a4556d152b2d0aa5521e4700d739a8e6fdb48  foundry/lib/pramana_foundry/durable_store/protected_verifier.ex
02735f8c61c864e003fe3ec596476cd315f8833080ee5c26e7cb152abf27fd41  foundry/lib/pramana_foundry/event_log.ex
df569423c58a67452cdb93d98259615ac0996b671dccb40089de28dce8c24caf  foundry/mix.exs
bf2a61f815533a96b2abec87b1690ae49145bec56e60703a22b4db178c56e954  foundry/mix.lock
55048c42848fb44086bbf8864b566d20137cf2f6994baa866cafc3ac8900b52a  foundry/test/pramana_foundry/durable_store/gateway_test.exs
dbef76cf8a02bf544617ff76b5ef2303cf20064d6fa3c7b6aac64f10e5ba3fc4  foundry/test/pramana_foundry/durable_store/legacy_import_test.exs
372365daecf086fd4af6e6bddc8ee16ef937ad16ef96b84669e0de759bdde371  foundry/test/support/durable_store_crash_fixture.exs
```

## Acceptance evidence

All commands used the pinned PATH:

```text
/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin
/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin
```

- `MIX_ENV=test mix compile --force --warnings-as-errors`: 84 Elixir files compiled,
  exit zero.
- `mix format --check-formatted` over every owned Elixir/test/Mix path: exit zero.
  The repository has unrelated pre-existing formatter drift, so whole-project formatting
  is not claimed.
- `mix test test/pramana_foundry/durable_store
  test/pramana_foundry/legacy_persistence_containment_test.exs
  test/pramana_foundry/effects/checkpoint_test.exs --seed 424207`: 31 passed, exit zero.
- First whole model-free attempt, without a fresh `TMPDIR`: 426/437 passed; all eleven
  failures were `Relocation.CrashRecoveryTest` setup failures whose copied fixture repo
  had nothing to commit. This superseded attempt is retained rather than hidden.
- Corrected whole model-free attempt under a fresh `mktemp -d` `TMPDIR`, before the final
  protected-required-read validation was added: 440 passed, exit zero. This is retained as
  superseded evidence, not validation of the frozen source.
- Final fresh-root whole-suite attempt: 439/440 passed. The only failure was the unrelated
  `TelemetryTest` scheduler-timing assertion `instrumentation emission cannot delay the
  observed action`; its immediate isolated fresh-root rerun passed 1/1. No FR-07 or
  persistence test failed. The earlier complete 440/440 fresh-root run and this final
  result/rerun are both retained; a serial full-suite green run is not claimed.

Executable cases establish:

- separate explicit initialization; rerun refuses replacement; corrupt header, missing
  database and unknown metadata version remain intact and enter visible recovery;
- actual subprocess `System.halt/1` before commit leaves zero rows, while halt after commit
  leaves the complete command/result/event and same-ID recovery returns it;
- same actor/ID/digest deduplicates while actor or payload changes conflict;
- one checked transaction creates command/result/event/projection/intent plus verifier-
  derived claim/generation/reservation rows; FK, uniqueness and revision-CAS failures
  leave no partial rows;
- candidate proposals cannot contain protected rows, SQL or callbacks; protected writes
  require an unforgeable startup reference, complete root-required revisions, one fixed-
  verifier authorization per intent and conserved referenced allocation;
- real WAL/FULL/FK pragmas, real SQLite `max_page_count` FULL, actual read-only filesystem
  open/write refusal, injected write/before-commit faults and recovery fencing;
- `VACUUM INTO` creates a coherent SQLite-engine snapshot at a new normalized absolute
  path; reopening/version checks and full ordered-row SHA-256 comparisons match every
  authoritative/import table;
- streamed import exceeds the old eight-MiB reader limit, byte-preserves original/archive,
  records digest and half-open range for every valid/invalid/torn/unknown-version line,
  creates no authority from invalid lines and reruns without duplicates.

## F02/F20/F21 routing checksum

- **F02 / FR-07:** checked commit precedes reply and compatibility publication; all bundle
  rows roll back together; storage failure acknowledges nothing and fences subsequent
  calls; lost reply is idempotently recoverable; corrupt/unknown authority never resets;
  torn, oversized and unknown-version legacy bytes are archived and reported. FR-08 still
  owns complete mutation migration and live/replay equivalence; legacy containment remains.
- **F20 / FR-07:** command/effect lookups are indexed, public diagnostics return bounded
  aggregates, and large import streams rather than loading the legacy file wholesale.
  The engine snapshot is serialized through the gateway and verifies full content. FR-18
  still owns canonical operational projections/capacity health; FR-19 owns measured limits,
  retention, WAL checkpoints, compaction interruption, archival and unattended policy.
- **F21 / FR-07:** import is explicit/offline, archives to a digest-derived collision-
  checked path, fsyncs and verifies copied bytes, retains source, raw records/ranges/errors
  and a rerun-safe database/external manifest. It performs no source deletion or relocation.
  FR-19 retains unknown-space/live-handle preflight, cross-device removal, collision-safe
  rollback and relocation acceptance; an idle process holding a connection is not claimed
  to be an offline-maintenance fence here.

## Honest limitations

- `VACUUM INTO` is SQLite's coherent engine snapshot mechanism used here because Exqlite
  0.40.0 does not expose `sqlite3_backup_*`; it is not a bare database/WAL file copy.
- Actual FULL and read-only binding failures are exercised. Commits really run with
  `synchronous=FULL`, but this macOS environment/binding exposes no controllable VFS fsync
  failure hook. A specifically failed fsync syscall, hardware power loss, page/WAL
  corruption, checkpoint interruption and soak are **not passed evidence**.
- The protected capability is structurally absent from candidate-facing calls and is an
  unforgeable BEAM reference. FR-15a must still prove the candidate account cannot inspect
  the protected VM/process/filesystem and must complete policy/authentication predicates.
- The compatibility destination is opt-in and requires an externally allocated opaque
  command ID. No current live legacy writer is silently redirected. This candidate is not
  deployed or activated.
