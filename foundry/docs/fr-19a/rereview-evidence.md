# FR-19A correction rereview evidence

Snapshot supporting [the BLOCKER rereview](rereview.md), 2026-09-19, Hawaii. Candidate
`ad455a8137b9cafbbec1670a3f683aa9364d5789`, tree
`282234589a15856449389cbed21530d457aa3c41`. These are reviewer diagnostics and evidence,
not implementation changes or a replacement acceptance harness.

## Local verification environment

Commands ran from `foundry/`, with the following toolchain path:

```text
/Users/raymondluong/.local/share/mise/installs/elixir/1.20.3-otp-29/bin
/Users/raymondluong/.local/share/mise/installs/erlang/29.0.5/bin
/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
```

`TMPDIR=/private/tmp/fr19a-rereview.rTTr6P` and
`CPATH=/Users/raymondluong/dev/pramana/foundry/deps/exqlite/c_src` were supplied to the
canonical command:

```sh
elixir ci/run.exs --output /private/tmp/fr19a-rereview.rTTr6P/ci-artifacts
```

Exit 0; 554 passed, 13 skipped, 1 excluded. Both source snapshots are clean and match
the candidate/tree. For direct Mix commands, `MIX_ENV=test`, `COORDINATOR_TICK=0`,
`MIX_BUILD_PATH=/private/tmp/fr19a-rereview.rTTr6P/diagnostic-build` and
`MIX_DEPS_PATH=/Users/raymondluong/dev/pramana/foundry/deps` were supplied.

```sh
mix test test/pramana_foundry/durable_store/operational_storage_test.exs \
  test/pramana_foundry/durable_store/sync_fault_test.exs \
  test/pramana_foundry/relocation_containment_test.exs \
  test/fr19a_sync_eio_orchestration_test.exs \
  test/fr19a_sync_eio_workflow_test.exs --seed 19233
```

Exit 0; 24 passed. Focused log SHA-256:
`bde8d7a22efe2ac371b10d7f26727fa2402820416efb8f9bc4f8af8fdc041faa`.

## B2 localization diagnostic

The reviewer ran this temporary script using `mix run --no-start`. It changes only the
test module in the isolated VM: one tag selects the existing interruption matrix and
one observation reads the WAL stat at its existing hook. Production module code is not
recompiled or replaced. BEAM tracing captures the real `Database.query/2` return.

```elixir
alias PramanaFoundry.DurableStore.Database
ExUnit.start(autorun: false)
ExUnit.configure(exclude: [review_other: true], include: [review_probe: true], seed: 19231)
{:module, Database} = Code.ensure_loaded(Database)
tracer = spawn(fn ->
  loop = fn loop ->
    receive do
      event ->
        IO.inspect(event, label: "CHECKPOINT_SQL_TRACE", limit: :infinity)
        loop.(loop)
    end
  end
  loop.(loop)
end)
:erlang.trace_pattern({Database, :query, 2}, [{[:_, "PRAGMA wal_checkpoint(TRUNCATE)"], [], [{:return_trace}]}], [:local])
:erlang.trace(:all, true, [:call, {:tracer, tracer}])
source = File.read!("test/pramana_foundry/durable_store/operational_storage_test.exs")
source = String.replace(source, "use ExUnit.Case, async: false", "use ExUnit.Case, async: false\n  @moduletag review_other: true")
source = String.replace(source, "  test \"engine interruption during checkpoint", "  @tag review_probe: true\n  test \"engine interruption during checkpoint")
source = String.replace(source, "fault = fn conn ->", "fault = fn conn ->\n        IO.inspect({operation, File.stat(path <> \"-wal\")}, label: \"PRE_OPERATION_WAL\")")
Code.compile_string(source, "test/pramana_foundry/durable_store/operational_storage_test.exs")
result = ExUnit.run()
IO.inspect(result, label: "DIAGNOSTIC_RESULT")
```

Observed WAL size at the checkpoint hook: `0`. Exact relevant trace/result:

```text
CHECKPOINT_SQL_TRACE: {:trace, #PID<0.1239.0>, :call,
 {PramanaFoundry.DurableStore.Database, :query,
  [#Reference<0.601774758.1102708759.36603>, "PRAGMA wal_checkpoint(TRUNCATE)"]}}
CHECKPOINT_SQL_TRACE: {:trace, #PID<0.1239.0>, :return_from,
 {PramanaFoundry.DurableStore.Database, :query, 2}, {:ok, [[0, 0, 0]]}}
Result: 1 passed, 14 excluded
DIAGNOSTIC_RESULT: %{total: 15, skipped: 0, failures: 0, excluded: 14}
```

The original storage-error/interrupt and recovery assertions all passed despite this
successful zero-frame checkpoint. The repeating interrupter therefore reaches beyond
the intended engine operation. This observation does not claim checkpoint corruption.

## B1 owner-loss diagnostic

The reviewer ran this with `mix run --no-start --no-compile` in a fresh, exclusively
created directory under the review root. It uses the unchanged public API and default
deadline. The root/database and ambiguous owner marker were left as disposable evidence;
the orphan worker was explicitly killed and joined.

```elixir
alias PramanaFoundry.DurableStore.Gateway
Process.flag(:trap_exit, true)
root = "/private/tmp/fr19a-rereview.rTTr6P/health-kill-owned"
File.mkdir!(root)
path = Path.join(root, "authority.sqlite3")
:ok = Gateway.initialize(path)
parent = self()
{:ok, gateway} = Gateway.start_link(path: path, capacity_probe: fn _ ->
  send(parent, {:probe, self()})
  receive do :stop -> :ok end
end)
caller = spawn(fn ->
  try do
    Gateway.operational_health(gateway)
  catch
    :exit, reason -> send(parent, {:caller_exit, reason})
  end
end)
probe = receive do {:probe, pid} -> pid after 2000 -> raise "no probe" end
monitor = Process.monitor(probe)
Process.exit(gateway, :kill)
receive do {:caller_exit, reason} -> IO.inspect(reason, label: "CALLER_EXIT") end
receive do
  {:DOWN, ^monitor, :process, ^probe, reason} -> IO.inspect(reason, label: "PROBE_STOPPED")
after
  5500 -> IO.inspect({Process.alive?(probe), Process.alive?(caller)}, label: "AFTER_DEFAULT_DEADLINE_PROBE_CALLER_ALIVE")
end
Process.exit(probe, :kill)
receive do {:DOWN, ^monitor, :process, ^probe, _} -> :ok after 1000 -> raise "probe cleanup failed" end
```

```text
CALLER_EXIT: {:killed, {GenServer, :call, [#PID<0.176.0>, :operational_health, :infinity]}}
AFTER_DEFAULT_DEADLINE_PROBE_CALLER_ALIVE: {true, false}
```

## Downloaded Linux evidence

Run `35498430877`, attempt 1, artifact `10601228576`, revision
`5f4984be07c67de8515a26d953d4d5b7de907c05`, tree
`7f6b91e6815bc19b4110e697c1d9fc6d7361ad85`. The reviewer independently retrieved the
artifact through `gh run download` and downloaded the original ZIP through the artifact
API. ZIP SHA-256 matched the API digest:
`ad315c15657068a921a1faeb73831a66c08bbecd252dc79145f539c7cca76959`.
Size 655,833 bytes; GitHub expiry is 2026-10-04T08:02:14Z. The report retains key raw
observations and identities here rather than assuming the remote artifact is permanent.

Exact Gateway target identity:

```text
image=/home/runner/work/_temp/fr19a-sync-eio-gateway/image.raw
loop=/dev/loop0
loop_maj_min=7:0
back_inode=8952534
back_dev=8:1
map=fr19a_sync_eio_35498430877_1_2953
sectors=262144
mount=/home/runner/work/_temp/fr19a-sync-eio-gateway/mountpoint
linear_table=0 262144 linear 7:0 0
loop_offset=0
loop_sizelimit=134217728
```

Recorded error-table phases and Gateway trace, with paths shortened here only by the
explicit `DEST` label below:

```text
DEST=/home/runner/work/_temp/fr19a-sync-eio-gateway/mountpoint/backup.sqlite3
1789891327.603404 openat(..., DEST, O_RDONLY) = 25<DEST>
epoch_ns=1789891329262534294 phase=load status=0
epoch_ns=1789891329395109355 phase=resume status=0
observed_table_begin
0 262144 error
observed_table_end
epoch_ns=1789891329528969057 phase=semantic-assert status=0
1789891329.806418 fsync(25<DEST>) = -1 EIO (Input/output error)
1789891329.808686 close(25<DEST>) = 0
```

The raw control separately records:

```text
1789891313.671969 fsync(17</home/runner/work/_temp/fr19a-sync-eio-capability/mountpoint/raw-sync.bin>) = -1 EIO (Input/output error)
```

The fixture's asserted sequence records typed `GATEWAY_STORAGE_FAILURE=eio`, recovery
mode, later protected refusal, dirty-helper joined, Gateway stopped, ordinary remount,
destination content/replay verification and source authority verification, then
`FIXTURE_RESULT=pass`. The retained destination is 188,416 bytes with baseline and
retained SHA-256
`ccb2b4d029ac200f013abb2ea07ad949484bcadcb645bd8938116a538760b852`.
The fixture's pin matches enforce equality before remount, after remount and after
verification; the verifier compares complete ordered-table digests and replay.

Same mapper mount options changed from
`rw,nosuid,nodev,noexec,relatime,emergency_ro` to
`rw,nosuid,nodev,noexec,relatime` through ordinary unmount and mount. Pre-mount loop
identity still names inode 8952534, backing device 8:1, loop major/minor 7:0, offset 0
and 128 MiB size limit. Cleanup records removal of exactly that mount/mapper/loop;
the subsequent loop JSON has a null backing file/inode/offset/size limit. Raw-control
cleanup likewise reports no exact resources remaining; workflow cleanup exits zero.

Selected original artifact file SHA-256 values:

```text
a6fdafbe8423b2f671a28ebbf7c26db47de1ac37563fa53410ce9b2b7e85aa65  gateway/strace.3158
1839744fe558ab0a975cce6bb077b29b85611831ada34071d6eeb6e29286115b  gateway/fixture.log
092ecd2df4cd0edb636773911e576a63ac9de8cd102460e29f513b54a7887df4  gateway-host/error-table-phase.txt
738008675b8064c949accaea60a43006561f2add57af6d48ccce29ef12e2c3cc  gateway-host/mapper-transitions.txt
60afdfe1ff4f26e051830c6583c1b0cbbc78d008c2d434b29af29d8b80aea2f8  gateway-host/recovery-remount.txt
6f103d700061c5de9b0d9be81c3f6e591888a3baf03a1877090eb943364ab104  gateway-host/cleanup.txt
```

Independent parser invocation used the downloaded `gateway/strace.*` glob, exact original
Linux destination, fixture log, error-table phases and mapper transitions; exit 0.
Inspection of the raw traces and fixture remains necessary: this parser's
`ext4_emergency_ro=false` field means EROFS provenance was not required for EIO and
does not accurately describe the observed later emergency-read-only state.
