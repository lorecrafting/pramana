defmodule PramanaFoundry.DurableStore.SyncFaultTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Authority, Database, Gateway}

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-sync-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    extension = compile_extension!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, "authority.sqlite3"), extension: extension}
  end

  test "connection-scoped WAL xSync fault is attributed, unacknowledged and ambiguity safe",
       ctx do
    capability = make_ref()
    assert :ok = Gateway.initialize(ctx.path)
    gateway = start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    assert {:ok, _seed, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("SEED"),
               protected_bundle("SEED"),
               protected("SEED")
             )

    baseline_path = Path.join(ctx.root, "baseline.sqlite3")
    assert {:ok, %{content: baseline}} = Gateway.backup(gateway, baseline_path)
    baseline_rows = sql_snapshot(gateway)
    assert baseline_rows == sql_snapshot_path(baseline_path)
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
    failed_bundle = protected_bundle("SYNC-FAIL")

    assert {:error,
            {:storage_unavailable,
             {:rollback_failed, _rollback_error, {:error, {:commit_failed, _binding_error}}}}} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               failed_command,
               failed_bundle,
               protected("SYNC-FAIL")
             )

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
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("LATER"),
               protected_bundle("LATER"),
               protected("LATER")
             )

    assert {:ok, [[1]]} = Database.query(conn, "SELECT fr07_sync_disarm()")

    assert :ok = stop_supervised(Gateway)

    reopened =
      start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

    assert %{mode: :ready} = Gateway.status(reopened)
    reopened_rows = sql_snapshot(reopened)

    case Gateway.command(reopened, "SYNC-FAIL") do
      {:error, :not_found} ->
        assert reopened_rows == baseline_rows
        after_path = Path.join(ctx.root, "after.sqlite3")
        assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, after_path)
        assert baseline_rows == sql_snapshot_path(after_path)

        assert {:ok, _result, :committed} =
                 Gateway.transact_verified(
                   reopened,
                   capability,
                   "actor",
                   failed_command,
                   failed_bundle,
                   protected("SYNC-FAIL")
                 )

      {:ok, result} ->
        refute reopened_rows == baseline_rows

        assert {:ok, ^result, :idempotent} =
                 Gateway.transact_verified(
                   reopened,
                   capability,
                   "actor",
                   failed_command,
                   %{},
                   %{}
                 )
    end

    assert_complete_counts(reopened, 2)

    assert {:ok, %{content: final_content, reconstruction: %{projection_count: 2}}} =
             Gateway.backup(reopened, final_path = Path.join(ctx.root, "final.sqlite3"))

    assert_snapshot_counts(final_content, 2)
    assert sql_snapshot(reopened) == sql_snapshot_path(final_path)

    unrelated_path = Path.join(ctx.root, "unrelated.sqlite3")
    assert :ok = Gateway.initialize(unrelated_path)
    unrelated_capability = make_ref()

    unrelated =
      start_supervised!(
        {Gateway, path: unrelated_path, protected_capability: unrelated_capability},
        id: :unrelated_sync_store
      )

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               unrelated,
               unrelated_capability,
               "actor",
               command("CONTROL"),
               protected_bundle("CONTROL"),
               protected("CONTROL")
             )

    assert_complete_counts(unrelated, 1)
  end

  test "hard exit after attributed xSync failure reopens without a partial bundle", ctx do
    capability = make_ref()
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
        {Gateway,
         path: ctx.path,
         recovery_evidence: "verified xSync fixture hard exit",
         protected_capability: capability},
        id: :recovered_sync_store
      )

    assert %{mode: :ready} = Gateway.status(gateway)
    assert {:ok, counts} = Gateway.counts(gateway)
    assert counts["commands"] in [1, 2]
    assert_consistent_protected_counts(counts)

    before_retry = sql_snapshot(gateway)

    retry =
      Gateway.transact_verified(
        gateway,
        capability,
        "actor",
        command("SYNC-CRASH"),
        protected_bundle("SYNC-CRASH"),
        protected("SYNC-CRASH")
      )

    assert {:ok, _result, retry_status} = retry
    assert retry_status in [:committed, :idempotent]

    case retry_status do
      :committed -> assert before_retry["commands"] |> length() == 1
      :idempotent -> assert before_retry["commands"] |> length() == 2
    end

    assert_complete_counts(gateway, 2)

    assert {:ok, %{content: content, reconstruction: %{projection_count: 2}}} =
             Gateway.backup(
               gateway,
               recovered_path = Path.join(ctx.root, "crash-recovered.sqlite3")
             )

    assert_snapshot_counts(content, 2)
    assert sql_snapshot(gateway) == sql_snapshot_path(recovered_path)
  end

  defp compile_extension!(root) do
    source = Path.expand("test/support/fr07_sync_fault.c")
    include = Path.expand("deps/exqlite/c_src")
    {compiler, linker_flags, suffix} = compiler!()
    output = Path.join(root, "fr07_sync_fault" <> suffix)

    {compiler_output, 0} =
      System.cmd(
        compiler,
        linker_flags ++
          ["-Wall", "-Wextra", "-Werror", "-I", include, "-o", output, source],
        stderr_to_stdout: true
      )

    assert compiler_output == ""
    output
  end

  defp compiler! do
    compiler = System.find_executable("clang") || System.find_executable("cc")

    case {:os.type(), compiler} do
      {{:unix, :darwin}, path} when is_binary(path) ->
        {path, ["-dynamiclib", "-undefined", "dynamic_lookup"], ".dylib"}

      {{:unix, _name}, path} when is_binary(path) ->
        {path, ["-shared", "-fPIC"], ".so"}

      _other ->
        flunk("FR-07 xSync acceptance requires a C compiler on a supported Unix host")
    end
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

  defp protected_bundle(id) do
    Map.put(bundle(id), :intents, [
      %{
        schema_version: 1,
        effect_id: "effect-#{id}",
        request_digest: effect_digest(id),
        status: "pending",
        value: %{"operation" => "check"}
      }
    ])
  end

  defp protected(id) do
    %{
      writer_epoch: "sync-fixture-epoch",
      required_revisions: %{projection_key(id) => "absent"},
      ledger_generations: [
        %{
          schema_version: 1,
          generation_id: "generation-#{id}",
          parent_generation_id: nil,
          allocation: 1,
          consumed: 0
        }
      ],
      effect_authorizations: [
        %{
          effect_id: "effect-#{id}",
          claim_id: "claim-#{id}",
          generation_id: "generation-#{id}",
          reservation_id: "reservation-#{id}",
          dimension: "starts.developer",
          units: 1
        }
      ]
    }
  end

  defp effect_digest(id) do
    {:ok, digest} =
      PramanaFoundry.DurableStore.Encoding.semantic_digest(
        "pramana-foundry-effect-request-v1",
        %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
      )

    digest
  end

  defp assert_complete_counts(gateway, expected) do
    assert {:ok, counts} = Gateway.counts(gateway)
    assert counts["commands"] == expected
    assert_consistent_protected_counts(counts)
  end

  defp assert_consistent_protected_counts(counts) do
    for table <-
          ~w(inputs command_results events projections effects claims ledger_generations reservations) do
      assert counts[table] == counts["commands"]
    end
  end

  defp assert_snapshot_counts(content, expected) do
    for table <-
          ~w(inputs commands command_results events projections effects claims ledger_generations reservations) do
      assert content[table].count == expected
      assert byte_size(content[table].sha256) == 64
    end

    for table <-
          ~w(metadata receipts leases policy_revisions control_revisions artifact_references import_runs legacy_records sqlite_sequence) do
      assert is_integer(content[table].count)
      assert byte_size(content[table].sha256) == 64
    end
  end

  defp sql_snapshot(gateway) do
    gateway
    |> :sys.get_state()
    |> Map.fetch!(:conn)
    |> sql_snapshot_conn()
  end

  defp sql_snapshot_path(path) do
    {:ok, conn} = Database.open(path)

    try do
      sql_snapshot_conn(conn)
    after
      assert :ok = Database.close(conn)
    end
  end

  defp sql_snapshot_conn(conn) do
    Map.new(Authority.registry(), fn {table, ordering, _columns} ->
      assert {:ok, rows} = Database.query(conn, "SELECT * FROM #{table} ORDER BY #{ordering}")
      {table, rows}
    end)
  end

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-#{id}", padding: false)
  end
end
