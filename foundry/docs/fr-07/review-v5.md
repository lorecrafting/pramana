# FR-07 v5 independent review — FAIL

Reviewed 2026-09-13. Reviewer: independent Astra-high review agent. This is a verdict on the exact frozen v5 candidate, not on withdrawn v4. No candidate files were edited. All mutation/fault probes used disposable, isolated databases; no live daemon, provider, credentials, deployment, or production database was used.

## Exact identity and provenance

- Candidate commit: `ff9cbb725a32e13d4062b570521574f01e00af17`; tree: `5055e3687feac8e5a60499b920d8f8b565d07597`.
- Implementation commit: `d25a51f8b219a8a49ed9e83b3d97d972058254f3`; tree: `b454a2fd0f4af1669ad02d616bacfd3148630738`.
- Review base: `8aa0ebddbfb5fa834bbefa53d1f84b992e4c25bd`.
- `candidate-v5.md` SHA256: `5eb42bbbe4a27e4d58f0c570f532483b23d395730bf733007116dd744011975f`. All 39 manifest entries independently matched. Implementation-to-candidate difference is only that candidate document.
- Preparatory checklist SHA256: `4e3b5a2c00708a99830b951d86e26a0e344a9f7ea808f3e6e46cab3dceaabda2`; fsync design SHA256: `d3c2da810a3d44068ed38fdfc878323168e34005dad3c30b0ab3fac4a6a394d7`.
- Withdrawal document SHA256: `20c6c81fce5bdbc64919a0421803e75627b0a43da762713a0f180e2e7ef61726`. V4 was withdrawn before a review verdict; its narrower fixtures are not substituted for v5 evidence.
- Final HEAD/tree/status check remained identical. Untracked candidate inputs were only fetched dependency directories `cc_precompiler`, `db_connection`, `elixir_make`, `exqlite`, `telemetry`; no source/test contamination was found.
- `git diff --check` against the base exits 2 for the intentionally preserved historical `diagnosis-v3.md` trailing whitespace at line 3. It is not reported as a clean check.

Independently downloaded the six pinned Hex tarballs, verified outer archive SHA256 and inner CHECKSUM against `mix.lock`, and compared packaged regular-file contents with fetched dependencies: cc_precompiler 0.1.11 (8 files), db_connection 2.10.2 (22), elixir_make 0.10.0 (12), exqlite 0.40.0 (24), owl 0.13.1 (23), telemetry 1.4.2 (16). All matched. The actual precompiled Exqlite artifact was also downloaded from the pinned v0.40.0 GitHub release: `exqlite-nif-2.17-aarch64-apple-darwin-0.40.0.tar.gz`, SHA256 `fb508638eff1ccb6bf42f8bed2de3879e3adeb81ef802ad57aa80168f9e02fba`, matching dependency `checksum.exs`. Its NIF and the loaded NIF both hash to `7b855b28389db2fd16f250184060231c2ae337bd73ee455e625212fac303de95`.

Runtime: Elixir 1.20.3 from the pinned OTP-29 build, Erlang executable under 29.0.5, actual SQLite 3.53.4, source ID `2026-07-24 19:02:57 bf7c7f30031888f4e796e429ab3978879485813aaca6f641c7b33e4e09459bcc`. The shim used the actual loaded Exqlite connection, not a separate system SQLite engine.

## Blocking findings

Paths below are relative to `foundry/`. R1–R5 have executed concrete reproductions. R6 is an explicit source-level design/acceptance shortfall, not a newly observed projection mismatch. The SQL injections are trusted corruption fixtures used to test allocated recovery behavior; they are not claims that an unauthorized actor can access the connection.

### R1 — Authority completeness and discovered-corruption fencing are incomplete

`lib/pramana_foundry/durable_store/database.ex:437` validates existing result rows but does not require a result for every acknowledged command. The command/input check at line 551 does not supply that missing relation. `gateway.ex:633` uses a commands/results inner join, which converts a retained command without its result into `not_found`.

Minimal executed trace: commit protected command A; execute `DELETE FROM command_results WHERE command_id='A'`; cleanly stop/reopen gateway. Observed `mode: :ready`, `Gateway.command(g, "A") == {:error, :not_found}`; command B commits; backup succeeds with two commands but one result. Thus startup and backup certify incomplete authority rather than fence it.

A second trace modifies A's result consistently in both canonical body and `committed_seq` column to 999 while only event sequence 1 exists:

```elixir
{:ok, result} = RecordCodec.materialize_result(%{schema_version: 1, disposition: "accepted"}, 999)
{:ok, bytes} = RecordCodec.encode(:result, result)
:ok = Database.execute(conn,
  "UPDATE command_results SET committed_seq=999, result=? WHERE command_id='A'",
  [{:blob, bytes}])
```

After clean reopen, startup is ready and command read returns 999. Backup detects `{:error, :result_sequence_not_reconstructable}` at `gateway.ex:957`, but `transition_after_result/2` at line 814 does not fence that error: gateway remains ready and B commits. This is both missing startup/read semantic validation and a concrete failure to enter recovery after detecting corruption.

Required correction: extend the existing authority validator to command/result totality and valid result/event bounds; apply it consistently at the relevant reads/reopen/backup, with one corruption-to-recovery disposition. Do not recreate missing acknowledged results silently.

### R2 — Non-map result crashes admission before the codec

`kernel.ex:17` invokes `raw_disposition_consistency/1` before `RecordCodec.normalize_bundle/1`; line 28 performs `Map.get` on an unchecked result value.

Minimal executed public API call, using a valid new command envelope:

```elixir
Gateway.transact(g, "actor", H.command("BAD"), %{schema_version: 1, result: true})
```

Observed `BadMapError`, caller exit, and monitored gateway `DOWN`, rather than a typed validation error. This requires no database injection. The review probe caught the exit deliberately; its green characterization assertion does not mean correct admission behavior.

Required correction: normalize/type-check through the codec before policy code accesses the result; preserve the rejected/blocked mutation restriction on normalized values. Same-ID retries already correctly bypass obsolete malformed proposal validation and should keep doing so.

### R3 — Backup target may collide with the owner's SQLite journal and be deleted

`gateway.ex:863` compares the destination only with the authority database identity, not the reserved database/owner sidecar namespace.

Minimal executed public API trace on a new store:

```elixir
target = database_path <> ".owner.sqlite3-journal"
{:ok, _} = Gateway.backup(g, target)  # target did not exist
# cleanly stop g, then start a gateway on database_path
```

The backup was accepted, verified, and existed as a 184,320-byte SQLite snapshot. On the next ordinary gateway open, the owner SQLite connection treated that filename as its rollback journal and removed it. The gateway became ready, while `File.stat(target)` returned `{:error, :enoent}`. Reproduction database: `/private/tmp/fr07-v5-independent.unTTL9/probe-195/authority.sqlite3`. This follow-up reopen was executed after the nine-test script; the snapshot was confirmed present before it.

Required correction: use the existing path-identity design to reserve/reject all authority and owner database sidecar destinations before backup creation. This is a direct public backup correctness issue, not a hypothetical hostile symlink race or FR-19 physical-fsync demand. Only the disposable review backup was removed; original authority remains available for another backup.

### R4 — V5 ledger validation fixes startup/backup, but not the live read contract

V5 adds a typed pattern in `database.ex:417`, not a ledger validator in `RecordCodec`. It duplicates admission semantics in `ProtectedVerifier` while `gateway.ex:764` reads only `revision` from `ledger_generations`.

Executed trusted corruption insertion after seeding valid parent `generation:A`:

```sql
INSERT INTO ledger_generations VALUES ('child', 'generation:A', 1, 0, 100, 0);
```

Positive correction: backup returns `{:authority_corrupt, "ledger_generations", 2, :invalid_ledger_row}`, fences the live gateway, and a clean reopen enters recovery with the same reason. New mutation is then refused. This independently verifies the disclosed v4 issue is partly fixed.

Counterexample: inject that same child into a ready gateway and submit B with expected revisions containing `"ledger/" <> Base.url_encode64("child", padding: false) => 0`, plus B's valid absent projection revision. The live revision reader accepts it, B commits sequence 2, and gateway remains ready. This is semantically unsupported retained authority used as a valid revision dependency.

Required correction: represent ledger rows in the shared typed codec/validator and use it for admission, retained-row validation and live revision reads, returning the same fencing corruption result. No child-ledger implementation is requested.

### R5 — Import rerun certifies a manifest whose retained evidence is missing

`database.ex:571` validates import manifest fields, but does not reconcile them with the retained `legacy_records`; `legacy_import.ex:221` returns the existing manifest without such reconciliation.

Minimal executed trace: import a one-line valid JSONL source; retain the returned manifest; execute `DELETE FROM legacy_records`; close the database; rerun `LegacyImport.run(database, source, archive)`. Observed success with the identical manifest claiming `line_count == 1`, while the database contains zero legacy rows and the gateway starts ready.

Required correction: validate retained records against each completed import's declared counts/ranges/digests/raw bytes before certifying existing import success or healthy authority. Preserve source/archive evidence and fence/report inconsistency; do not silently manufacture replacement authority. Source and archive copies survived this probe, so this is specifically false completeness certification, not a claim of loss of every copy.

### R6 — The required single live/reconstruction reducer is not actually shared

`RecordCodec.apply_projection/2` (`record_codec.ex:396`) is invoked by reconstruction's private `reduce_transitions` (line 493) and its unit test. Live materialization remains the separate SQL-CAS implementation in `gateway.ex:492`, `insert_projections/2`. There is no live call to that reducer. Codec normalization and the event/projection bijection are valuable but are not one reducer applying both paths, as required by the surviving diagnosis/checklist.

No new post-v3 accepted projection/replay divergence was reproduced, and this finding must not be described as one. The exact event-only v3 trace is now rejected with `:projection_write_missing` and zero row changes. Required correction is limited to the already-approved narrow projection application design: share its transition decision/validation between live application and reconstruction, or obtain an explicit acceptance amendment with an equivalence argument and tests. This does not demand FR-08's full workflow migration.

## Independently executed verification

All Mix commands ran from `/private/tmp/pramana-fr07/foundry`. Pinned environment:

```sh
PATH=/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin:/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin:/opt/homebrew/bin:/usr/bin:/bin
MIX_ENV=test
MIX_BUILD_PATH=/private/tmp/fr07-v5-independent.unTTL9/build
TMPDIR=/private/tmp/fr07-v5-independent.unTTL9
COORDINATOR_TICK=0
```

Commands/results:

```sh
mix test test/pramana_foundry/durable_store test/pramana_foundry/legacy_persistence_containment_test.exs test/pramana_foundry/effects/checkpoint_test.exs --seed 7735
# 62/62 passed; exit 0, fresh dependency and 87-module compile.
mix compile --force --warnings-as-errors
# 87 modules; exit 0.
mix run --no-start /private/tmp/fr07-v5-independent.unTTL9/probes.exs
# 9/9 characterization tests passed; exit 0, seed 458624.
/usr/bin/clang -dynamiclib -undefined dynamic_lookup -Wall -Wextra -Werror -I deps/exqlite/c_src -o /private/tmp/fr07-v5-independent.unTTL9/fr07_sync_fault.dylib test/support/fr07_sync_fault.c
# exit 0.
mix run --no-start /private/tmp/fr07-v5-independent.unTTL9/sync_probes.exs
# 1/1 passed; exit 0, seed 11655; two independent child scenarios.
```

The nine characterization tests intentionally assert reproduced defects as well as positive corrections; do not count them as nine acceptance passes. Exact reusable helper/envelope/complete protected bundle/facts and reproductions are preserved in that temporary directory:

- `helpers.exs`: SHA256 `63d2fb472427dbd1cf16cb1e43c87c92fa43a8b37d45ec073c6a9b1141db57c3`.
- `probes.exs`: SHA256 `45ed4066887c37372d7a021be32ba98fac076102d73d279aaae4435fc982cfc6`.
- `sync_child.exs`: SHA256 `fd7f1145e0d3e6208d30721ec275e4d7e1b8fd0c3cd096e09d434100bcaf7d37`.
- `sync_probes.exs`: SHA256 `bedd9dbbf3b123973bce6eb0161bec6e13d46abc590c1b265d63b43d15dbddba`.

Also independently ran the entire suite in a second fresh root, `/private/tmp/fr07-v5-full-review.qnv6H8`, with its own `build` and `TMPDIR`, same pinned PATH/MIX_ENV/tick settings, and `env -u HERDR_ENV -u PRAMANA_OPERATOR_RUNTIME_ROOT ... mix test --seed 7736`. Result: **470/471 passed, exit 2**, 41.0 seconds. Sole failure: `test/pramana_foundry/projections/benchmark_test.exs:12`, equality with saved benchmark output. That test is unchanged by this candidate. I have not established the cause of the saved-output difference, so do not certify the author's 471-pass result or attribute this failure to storage. Existing fixture-name and stress-test warnings were printed. Independent formatting was not run.

## Bounded WAL xSync proof — credited, not a blocker

The independent probe strengthens the candidate fixtures: it compares exact contents of all 18 SQLite tables, not just counts or the length of a digest string. It constructs an independent oracle with fixed store identities and complete successful A/CONTROL/B protected transactions. Both fault cases use `transact_verified` with an intent, claim, top-level ledger generation and reservation, as well as command/result/input/event/projection authority. It tests an unrelated store while the target is still armed and a disarmed control on the target connection.

Observed in both fault cases: existing WAL size 206,032 bytes, actual writer WAL/FULL/FK enabled, 50 successful WAL writes before the fault, last-write order 50 followed by xSync order 51, xSync flags 2 and `SQLITE_IOERR_FSYNC` 1034. COMMIT returned `disk I/O error`, no success acknowledgement was delivered, gateway entered recovery and refused a subsequent protected mutation.

| Scenario | Reopen and exact retained state | Executed same-command retry |
| --- | --- | --- |
| Ordinary close after one-shot fault | Disarm/close; ready reopen; all 18 tables exactly matched prior A/CONTROL baseline (B absent) | Same protected B committed; every table exactly matched successful oracle |
| Hard exit after one-shot fault | `System.halt(75)` before close; unproved restart fenced ambiguous owner; explicit observed child-exit evidence permitted recovery; every table exactly matched complete A/CONTROL/B oracle | Same B with obsolete empty proposal/facts returned original result idempotently; all rows unchanged |

Both branches finally had the identical full-row digest `680800ede0c777a395cc28b106da2ca28be65a025b479aa64512a9d5308e2b46`. Both also executed another obsolete-malformed-proposal retry and verified no change, then made a backup, reopened it independently, and matched every oracle table and three reconstructed projections. Thus **both absent and complete outcomes were observed**, not merely handled by an unexercised conditional.

Native isolation: exact candidate C SHA256 `508777be16e52c390aed8986ee60c005c4d5c3e2319c7423012c4e8a3f46f90d`. The test extension receives the actual Exqlite connection's SQLite extension API, obtains its WAL file through `SQLITE_FCNTL_JOURNAL_POINTER`, copies existing I/O methods, delegates writes, and overrides that file's xSync once. Compiled dylib SHA256 `2f99b5a40fb75d7508632edabe5ddf863ff7ae4d3b19e783d1f06b89e25b6c0d`; `otool -L` shows only itself and libSystem, no second SQLite library. `nm` shows the extension API/entry point rather than a linked second SQLite engine. Clang 21.0.0, arm64 Apple target.

The C and extension-loading calls are under test-only paths; no production Mix compiler/lib path builds or loads this fixture. The probe compiles to the isolated temporary directory. Production gateway paths do not load it. This does not claim that trusted host code with direct NIF access is sandboxed; that is outside FR-07.

The shim's static single-target state is acceptable only for this bounded fixture: it is disarmed before ordinary close, or the whole child exits. It is not a general production VFS implementation. This evidence is **SQLite VFS xSync fault attribution**, not an executed physical kernel `fsync` error, power-cut durability proof, ENOSPC-at-sync proof, or storage-media guarantee. Those claims remain deferred.

Evidence/documentation correction: the candidate's own full-state language exceeds its weaker count/hash-shape assertions in places. The independent oracle probes now supply the missing bounded evidence for this review; the next candidate should retain equivalent executable assertions and accurately describe them. This is separate from the implementation blockers, and sync evidence is not being rejected merely for originating in a test-only VFS.

## Other credited behavior and allocation limits

Source review covered all new durable-store modules, all candidate durable-store tests/support fixtures, the C shim, containment changes, configuration/Mix integration, and the design/history/contract material. Focused tests and independent probes credit: canonical optional `reason_code: nil` round trip; exact same-ID lookup preceding stale revision/proposal/fact checks; unequal actor/digest conflicts; supported semantic digest bounds; checked SQLite transactions and fault rollback; multi-table protected commit bundles; ordinary/crash owner handling; importer byte preservation/quarantine on its valid path; backup/reconstruction on valid authority; strict DB identity rejection of dot/dotdot, symlink and hardlink aliases. The exact parent-symlink/`..` v3 gateway/import/migrate trace was rerun independently and rejected; a real gateway on the underlying path stayed ready.

These successes do not discharge R1–R6. In particular the backup filename collision is not cured by rejecting existing inode aliases, and checking unsupported ledgers at startup alone is not one typed read contract.

Do not mark FR-07 complete or all allocated F02/F20/F21 obligations proven. Preserve FR-08 workflow migration/reducer expansion, FR-15a hostile OS/process isolation, FR-17 activation, FR-19 physical fault/retention/checkpoint/relocation work, and FR-22 lifecycle exclusions. Nothing here authorizes implementation, integration, deployment or activation. Recommended next work is limited to the concrete validator, fence, sidecar-identity, and shared narrow reducer corrections above, followed by a newly frozen independent review.
