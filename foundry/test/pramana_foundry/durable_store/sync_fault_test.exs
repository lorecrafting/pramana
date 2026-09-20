defmodule PramanaFoundry.DurableStore.SyncFaultTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, Gateway}

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-sync-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    extension = compile_extension!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, "authority.sqlite3"), extension: extension}
  end

  test "connection-scoped WAL xSync fault is attributed, unacknowledged and ambiguity safe", ctx do
    assert :ok = Gateway.initialize(ctx.path)
    gateway = start_supervised!({Gateway, path: ctx.path})

    assert {:ok, _seed, :committed} =
             Gateway.transact(gateway, "actor", command("SEED"), bundle("SEED"))

    baseline_path = Path.join(ctx.root, "baseline.sqlite3")
    assert {:ok, %{content: baseline}} = Gateway.backup(gateway, baseline_path)
    assert File.stat!(ctx.path <> "-wal").size > 0

    conn = :sys.get_state(gateway).conn
    assert :ok = Sqlite3.enable_load_extension(conn, true)

    assert {:ok, [[nil]]} =
             Database.query(conn, "SELECT load_extension(?, ?)", [
               ctx.extension,
               "sqlite3_fr07syncfault_init"
             ])

    assert :ok = Sqlite3.enable_load_extension(conn, false)
    assert {:ok, [[1]]} = Database.query(conn, "SELECT fr07_sync_arm()")

    failed_command = command("SYNC-FAIL")
    failed_bundle = bundle("SYNC-FAIL")

    assert {:error,
            {:storage_unavailable,
             {:rollback_failed, _rollback_error,
              {:error, {:commit_failed, _binding_error}}}}} =
             Gateway.transact(gateway, "actor", failed_command, failed_bundle)

    assert %{mode: :recovery} = Gateway.status(gateway)
    assert {:ok, [[1, 1034, flags, writes, write_sequence, sync_sequence]]} =
             Database.query(
               conn,
               "SELECT fr07_sync_hits(), fr07_sync_code(), fr07_sync_flags(), fr07_sync_writes(), fr07_write_sequence(), fr07_sync_sequence()"
             )

    assert is_integer(flags)
    assert writes > 0
    assert write_sequence > 0
    assert sync_sequence > write_sequence
    assert {:error, {:recovery_mode, _reason}} =
             Gateway.transact(gateway, "actor", command("LATER"), bundle("LATER"))

    assert {:ok, [[1]]} = Database.query(conn, "SELECT fr07_sync_disarm()")

    assert :ok = stop_supervised(Gateway)
    reopened = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :ready} = Gateway.status(reopened)

    case Gateway.command(reopened, "SYNC-FAIL") do
      {:error, :not_found} ->
        after_path = Path.join(ctx.root, "after.sqlite3")
        assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, after_path)

      {:ok, result} ->
        assert {:ok, ^result, :idempotent} =
                 Gateway.transact(reopened, "actor", failed_command, %{})

        assert {:ok, counts} = Gateway.counts(reopened)
        assert counts["commands"] == 2
        assert counts["events"] == 2
        assert counts["projections"] == 2
    end

    unrelated_path = Path.join(ctx.root, "unrelated.sqlite3")
    assert :ok = Gateway.initialize(unrelated_path)
    unrelated = start_supervised!({Gateway, path: unrelated_path}, id: :unrelated_sync_store)

    assert {:ok, _result, :committed} =
             Gateway.transact(unrelated, "actor", command("CONTROL"), bundle("CONTROL"))
  end

  test "hard exit after attributed xSync failure reopens without a partial bundle", ctx do
    fixture = Path.expand("test/support/fr07_sync_crash_fixture.exs")

    {output, 73} =
      System.cmd(
        System.find_executable("mix"),
        ["run", "--no-start", fixture, ctx.path, ctx.extension],
        stderr_to_stdout: true,
        env: [{"COORDINATOR_TICK", nil}, {"HERDR_ENV", nil}]
      )

    assert output =~ "SYNC_OBS="
    assert output =~ ", 1, 1034,"

    fenced = start_supervised!({Gateway, path: ctx.path}, id: :fenced_sync_store)

    assert %{
             mode: :recovery,
             reason: {:store_owner_unavailable, {:ambiguous_previous_owner, _, _}}
           } = Gateway.status(fenced)

    assert :ok = stop_supervised(:fenced_sync_store)

    gateway =
      start_supervised!(
        {Gateway, path: ctx.path, recovery_evidence: "verified xSync fixture hard exit"},
        id: :recovered_sync_store
      )

    assert %{mode: :ready} = Gateway.status(gateway)
    assert {:ok, counts} = Gateway.counts(gateway)
    assert counts["commands"] in [1, 2]
    assert counts["events"] == counts["commands"]
    assert counts["projections"] == counts["commands"]

    retry = Gateway.transact(gateway, "actor", command("SYNC-CRASH"), bundle("SYNC-CRASH"))
    assert match?({:ok, _result, status} when status in [:committed, :idempotent], retry)

    assert {:ok, final_counts} = Gateway.counts(gateway)
    assert final_counts["commands"] == 2
    assert final_counts["events"] == 2
    assert final_counts["projections"] == 2

    assert {:ok, %{reconstruction: %{projection_count: 2}}} =
             Gateway.backup(gateway, Path.join(ctx.root, "crash-recovered.sqlite3"))
  end

  defp compile_extension!(root) do
    source = Path.expand("test/support/fr07_sync_fault.c")
    output = Path.join(root, "fr07_sync_fault.dylib")
    include = Path.expand("deps/exqlite/c_src")

    {compiler_output, 0} =
      System.cmd("/usr/bin/clang", [
        "-dynamiclib",
        "-undefined",
        "dynamic_lookup",
        "-Wall",
        "-Wextra",
        "-Werror",
        "-I",
        include,
        "-o",
        output,
        source
      ], stderr_to_stdout: true)

    assert compiler_output == ""
    output
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "legacy_event_append",
      "target_ids" => %{},
      "payload" => %{}
    }
  end

  defp bundle(id) do
    event_id = "event-#{id}"
    value = %{"status" => "ready"}

    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted"},
      events: [
        %{
          schema_version: 1,
          event_id: event_id,
          type: "legacy_event",
          payload: %{
            "projection" => %{
              "namespace" => "kernel-v1",
              "entity_id" => "ticket-#{id}",
              "revision" => 0,
              "value" => value
            }
          }
        }
      ],
      projections: [
        %{
          schema_version: 1,
          namespace: "kernel-v1",
          entity_id: "ticket-#{id}",
          expected_revision: -1,
          revision: 0,
          last_event_id: event_id,
          value: value
        }
      ]
    }
  end

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-#{id}", padding: false)
  end
end
