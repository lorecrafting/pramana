defmodule PramanaFoundry.DurableStore.FR08AFR19AIntegrationTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3

  alias PramanaFoundry.DurableStore.{
    Authority,
    Database,
    Gateway,
    Maintenance
  }

  alias PramanaFoundry.Repair.{FR08HandoffGate, H0AcceptedFR07Boundary}

  @accepted_h0_revision "af0c51b4682c50080e67194dd853fbaa1eebace7"
  @protected_tables ~w(root_infrastructure_settlements durable_operations atomic_bundles root_leases root_receipts root_reservations root_claims root_effects root_ledgers root_control_history root_controls root_policy_history root_policies authenticated_inbox_items authenticated_inboxes root_pointers root_commands)
  @legacy_tables ~w(inputs commands command_results events projections effects ledger_generations claims reservations receipts leases policy_revisions control_revisions artifact_references import_runs legacy_records sqlite_sequence)

  setup do
    root =
      Path.join(
        canonical_tmp(),
        "fr08a-fr19a-integration-#{System.pid()}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root}
  end

  test "combined ready and recovery states preserve both public shapes", %{root: root} do
    ready_path = Path.join(root, "ready.sqlite3")
    capability = make_ref()
    gateway = start_gateway(ready_path, capability, "epoch-ready")
    state = :sys.get_state(gateway)

    assert %{mode: :ready, reason: nil, conn: conn, owner: owner} = state
    assert is_reference(conn)
    assert is_struct(owner)
    assert state.protected_capability == capability
    assert state.writer_epoch == "epoch-ready"
    assert is_function(state.capacity_probe, 1)
    assert state.operational_health_requests == %{}

    assert {:ok, %{mode: :ready, last_durable_sequence: 0, capacity: %{status: :known}}} =
             Gateway.operational_health(gateway)

    assert :ok = GenServer.stop(gateway)

    missing_path = Path.join(root, "missing.sqlite3")
    {:ok, recovering} = Gateway.start_link(path: missing_path)
    Process.unlink(recovering)

    assert %{mode: :recovery, reason: :not_initialized, path: ^missing_path} =
             Gateway.status(recovering)

    assert {:error,
            {:recovery_mode, :not_initialized,
             %{capacity: %{status: :unknown}, last_durable_sequence: :unknown}}} =
             Gateway.operational_health(recovering)

    assert {:error, {:recovery_mode, :not_initialized}} =
             Gateway.protected_snapshot(recovering, make_ref())

    recovery_state = :sys.get_state(recovering)
    assert recovery_state.conn == nil
    assert recovery_state.owner == nil
    assert is_function(recovery_state.capacity_probe, 1)
    assert recovery_state.operational_health_requests == %{}
    assert :ok = GenServer.stop(recovering)
  end

  test "accepted-v1 migration is additive and idempotent while future, partial and corrupt states refuse",
       %{root: root} do
    accepted_path = Path.join(root, "accepted-v1.sqlite3")
    capability = make_ref()
    gateway = start_gateway(accepted_path, capability, "epoch-migration")
    commit_domain!(gateway, "MIGRATION-DOMAIN")
    assert :ok = GenServer.stop(gateway)

    before = content!(accepted_path)
    legacy_before = Map.take(before, @legacy_tables)
    make_accepted_v1!(accepted_path)

    assert :ok = Gateway.migrate(accepted_path)
    assert :ok = Gateway.migrate(accepted_path)
    assert Map.take(content!(accepted_path), @legacy_tables) == legacy_before

    migrated = start_existing(accepted_path, capability, "epoch-after-migration")

    assert {:ok,
            %{
              "protected_schema_version" => "2",
              "authority_mode" => "empty_or_legacy",
              "writer_epoch" => "epoch-after-migration"
            }} = Gateway.protected_snapshot(migrated, capability)

    assert {:ok, %{mode: :ready, last_durable_sequence: 1}} =
             Gateway.operational_health(migrated)

    assert :ok = GenServer.stop(migrated)

    future = initialized_path(root, "future")
    execute_raw!(future, "UPDATE metadata SET value = '3' WHERE key = 'protected_schema_version'")

    assert {:error, {:unsupported_protected_migration, :partial_or_future_protected_state}} =
             Gateway.migrate(future)

    assert metadata!(future, "protected_schema_version") == "3"

    partial = initialized_path(root, "partial")
    execute_raw!(partial, "DELETE FROM metadata WHERE key = 'migration_fr08a_v1'")

    assert {:error, {:unsupported_protected_migration, :partial_or_future_protected_state}} =
             Gateway.migrate(partial)

    assert metadata!(partial, "migration_fr08a_v1") == nil

    corrupt = initialized_path(root, "corrupt")
    execute_raw!(corrupt, "DROP TABLE root_pointers")

    assert {:error, {:unsupported_protected_migration, :partial_or_future_protected_state}} =
             Gateway.migrate(corrupt)

    refute table_exists?(corrupt, "root_pointers")
  end

  test "root authority survives health, checkpoint, backup and writer-epoch recovery", %{
    root: root
  } do
    path = Path.join(root, "root-lifecycle.sqlite3")
    capability = make_ref()
    gateway = start_gateway(path, capability, "epoch-A")
    commit_domain!(gateway, "ROOT-DOMAIN")
    seed_claim!(gateway, capability, "epoch-A")

    assert {:ok, %{mode: :ready, last_durable_sequence: 1}} =
             Gateway.operational_health(gateway)

    assert {:ok, %{busy: 0, last_durable_sequence: 1}} = Gateway.checkpoint(gateway)

    backup = Path.join(root, "root-lifecycle-backup.sqlite3")

    assert {:ok, %{content: content, reconstruction: reconstruction}} =
             Gateway.backup(gateway, backup)

    assert_combined_content(content)
    assert reconstruction.projection_count == 1
    assert :ok = GenServer.stop(gateway)

    assert {:ok, %{content: ^content, replay: %{state: replay}}} = Maintenance.verify(backup)
    assert map_size(replay) == 1

    reopened = start_existing(path, capability, "epoch-B")
    assert %{mode: :ready} = Gateway.status(reopened)

    assert {:ok, %{"writer_epoch" => "epoch-B", "authority_mode" => "root"}} =
             Gateway.protected_snapshot(reopened, capability)

    assert_rejected!(
      reopened,
      capability,
      issue_operation("epoch-A"),
      "claim_issue_not_permitted"
    )

    accept_current!(reopened, capability, %{
      "type" => "reclaim_claim",
      "claim_id" => "claim-1",
      "prior_writer_epoch" => "epoch-A",
      "new_writer_epoch" => "epoch-B",
      "proof" => "issuer_quiescent"
    })

    accept_current!(reopened, capability, issue_operation("epoch-B"))

    assert {:ok, %{"status" => "issued", "writer_epoch" => "epoch-B"}} =
             protected_fact(reopened, capability, "claim", "claim_id", "claim-1")

    assert :ok = GenServer.stop(reopened)
  end

  test "owner loss terminates an in-flight health probe without losing root authority", %{
    root: root
  } do
    path = Path.join(root, "health-owner-loss.sqlite3")
    capability = make_ref()
    parent = self()

    gateway =
      start_gateway(path, capability, "epoch-A",
        capacity_probe: fn _path ->
          send(parent, {:combined_probe_started, self()})
          receive do: (:never -> :ok)
        end
      )

    seed_claim!(gateway, capability, "epoch-A")

    caller =
      spawn(fn ->
        try do
          Gateway.operational_health(gateway)
        catch
          :exit, reason -> send(parent, {:combined_health_exit, self(), reason})
        end
      end)

    caller_monitor = Process.monitor(caller)
    assert_receive {:combined_probe_started, probe}
    probe_monitor = Process.monitor(probe)
    [request] = :sys.get_state(gateway).operational_health_requests |> Map.values()
    controller = request.pid
    controller_monitor = Process.monitor(controller)
    gateway_monitor = Process.monitor(gateway)

    Process.exit(gateway, :kill)

    assert_receive {:DOWN, ^gateway_monitor, :process, ^gateway, :killed}
    assert_receive {:combined_health_exit, ^caller, {:killed, {GenServer, :call, _call}}}
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}
    assert_receive {:DOWN, ^probe_monitor, :process, ^probe, :killed}, 1_000
    assert_receive {:DOWN, ^controller_monitor, :process, ^controller, :normal}, 1_000

    reopened =
      start_recovered(
        path: path,
        protected_capability: capability,
        writer_epoch: "epoch-B",
        recovery_evidence: "observed killed integration owner",
        capacity_probe: fn _path -> {:ok, 321} end
      )

    assert {:ok, %{"status" => "claimed", "writer_epoch" => "epoch-A"}} =
             protected_fact(reopened, capability, "claim", "claim_id", "claim-1")

    assert {:ok, %{capacity: %{status: :known, physical_available_bytes: 321}}} =
             Gateway.operational_health(reopened)

    assert :ok = GenServer.stop(reopened)
  end

  test "checkpoint and backup failures retain complete domain and root authority", %{root: root} do
    for operation <- [:checkpoint, :backup] do
      path = Path.join(root, "#{operation}-failure.sqlite3")
      capability = make_ref()

      maintenance_fault =
        case operation do
          :checkpoint -> {:error, :before_checkpoint}
          :backup -> {:during, :during_backup, fn _conn -> {:error, :injected_backup_failure} end}
        end

      gateway =
        start_gateway(path, capability, "epoch-A", maintenance_fault: maintenance_fault)

      commit_domain!(gateway, "#{operation}-DOMAIN")
      seed_claim!(gateway, capability, "epoch-A")
      conn = :sys.get_state(gateway).conn
      assert {:ok, baseline} = Authority.read(conn, :all)
      assert_combined_content(baseline.content)

      result =
        case operation do
          :checkpoint -> Gateway.checkpoint(gateway)
          :backup -> Gateway.backup(gateway, Path.join(root, "failed-target.sqlite3"))
        end

      injected_reason =
        case operation do
          :checkpoint -> {:injected_maintenance, :before_checkpoint}
          :backup -> {:backup_failed, :injected_backup_failure}
        end

      assert {:error, {:storage_unavailable, ^injected_reason}} = result
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert {:ok, ^baseline} = Authority.read(conn, :all)
      assert :ok = GenServer.stop(gateway)

      reopened = start_existing(path, capability, "epoch-B")
      recovered = Path.join(root, "#{operation}-recovered.sqlite3")

      assert {:ok, %{content: content, reconstruction: %{state: replay}}} =
               Gateway.backup(reopened, recovered)

      assert content == baseline.content
      assert replay == baseline.reconstructed
      assert_combined_content(content)

      assert {:ok, %{content: ^content, replay: %{state: ^replay}}} =
               Maintenance.verify(recovered)

      assert :ok = GenServer.stop(reopened)
    end
  end

  test "frozen H0 stays historical while the evolved live provider refuses all seven", %{
    root: _root
  } do
    artifact =
      Path.expand("../../../docs/fr-08/h0-accepted-fr07-report.txt", __DIR__)
      |> File.read!()

    assert artifact =~ "subject_revision=#{@accepted_h0_revision}\n"
    assert artifact =~ "passed_count=4\n"
    assert artifact =~ "unavailable_count=3\n"

    live = H0AcceptedFR07Boundary.report(String.duplicate("a", 40))
    refute FR08HandoffGate.ready?(live.gate)
    assert live.gate.passed_count == 0
    assert live.gate.failed_count == 0
    assert live.gate.unavailable_count == 7

    assert Enum.all?(live.gate.capabilities, fn capability ->
             capability.status == "unavailable" and
               capability.reason == "h0:loaded_accepted_api_identity_mismatch"
           end)
  end

  defp start_gateway(path, capability, epoch, opts \\ []) do
    assert :ok =
             Gateway.initialize(path,
               installation_id: "fr08a-fr19a-integration",
               repository_id: "pramana-foundry"
             )

    {:ok, gateway} =
      Gateway.start_link(
        Keyword.merge(opts,
          path: path,
          protected_capability: capability,
          writer_epoch: epoch
        )
      )

    Process.unlink(gateway)
    gateway
  end

  defp start_existing(path, capability, epoch) do
    {:ok, gateway} =
      Gateway.start_link(path: path, protected_capability: capability, writer_epoch: epoch)

    Process.unlink(gateway)
    gateway
  end

  defp start_recovered(opts) do
    deadline = System.monotonic_time(:millisecond) + 2_000
    start_recovered(opts, deadline)
  end

  defp start_recovered(opts, deadline) do
    {:ok, gateway} = Gateway.start_link(opts)
    Process.unlink(gateway)

    case Gateway.status(gateway) do
      %{mode: :ready} ->
        gateway

      %{mode: :recovery, reason: {:store_owner_unavailable, "database is locked"}} ->
        :ok = GenServer.stop(gateway)

        if System.monotonic_time(:millisecond) < deadline do
          receive do
          after
            10 -> start_recovered(opts, deadline)
          end
        else
          flunk("killed combined Gateway retained its SQLite lock")
        end

      status ->
        :ok = GenServer.stop(gateway)
        flunk("unexpected combined recovery status: #{inspect(status)}")
    end
  end

  defp seed_claim!(gateway, capability, epoch) do
    accept_current!(gateway, capability, policy_operation())
    accept_current!(gateway, capability, control_operation())
    accept_current!(gateway, capability, grant_operation())
    accept_current!(gateway, capability, reserve_operation())
    accept_current!(gateway, capability, effect_operation())
    accept_current!(gateway, capability, claim_operation(epoch))
  end

  defp accept_current!(gateway, capability, operation) do
    initial = protected_command(unique_id(), %{}, operation)

    assert {:ok, result, :committed} =
             Gateway.protected_command(gateway, capability, "operator", initial)

    case result do
      %{"disposition" => "rejected", "reason_code" => "incomplete_read_set"} ->
        assert {:ok, %{"disposition" => "accepted"} = accepted, :committed} =
                 Gateway.protected_command(
                   gateway,
                   capability,
                   "operator",
                   protected_command(
                     unique_id(),
                     result["facts"]["required_revisions"],
                     operation
                   )
                 )

        accepted

      %{"disposition" => "accepted"} ->
        result
    end
  end

  defp assert_rejected!(gateway, capability, operation, reason) do
    initial = protected_command(unique_id(), %{}, operation)

    assert {:ok, result, :committed} =
             Gateway.protected_command(gateway, capability, "operator", initial)

    final =
      case result do
        %{"reason_code" => "incomplete_read_set"} ->
          assert {:ok, retried, :committed} =
                   Gateway.protected_command(
                     gateway,
                     capability,
                     "operator",
                     protected_command(
                       unique_id(),
                       result["facts"]["required_revisions"],
                       operation
                     )
                   )

          retried

        other ->
          other
      end

    assert %{"disposition" => "rejected", "reason_code" => ^reason} = final
  end

  defp policy_operation do
    %{
      "type" => "set_policy",
      "policy_id" => "policy-1",
      "value" => %{
        "allowed_operations" => ["launch"],
        "allowed_scopes" => ["ticket:T1"]
      }
    }
  end

  defp control_operation do
    %{"type" => "set_control", "control_id" => "control-1", "value" => %{"status" => "active"}}
  end

  defp grant_operation do
    %{
      "type" => "grant_ledger",
      "ledger_id" => "root",
      "generation" => 0,
      "dimension" => "starts.developer",
      "units" => 5
    }
  end

  defp reserve_operation do
    %{
      "type" => "reserve",
      "reservation_id" => "reservation-1",
      "ledger_id" => "root",
      "generation" => 0,
      "owner_kind" => "effect",
      "owner_id" => "effect-1",
      "units" => 1
    }
  end

  defp effect_operation do
    %{
      "type" => "create_effect",
      "effect_id" => "effect-1",
      "request" => %{"request_id" => "request-1", "role" => "developer", "profile" => "sol"},
      "operation" => "launch",
      "scope" => "ticket:T1",
      "ticket_id" => "T1",
      "attempt_id" => "A1",
      "execution_id" => "execution-1",
      "policy_id" => "policy-1",
      "policy_revision" => 0,
      "control_id" => "control-1",
      "control_revision" => 0,
      "reservation_ids" => ["reservation-1"],
      "leases" => []
    }
  end

  defp claim_operation(epoch) do
    %{
      "type" => "claim_effect",
      "effect_id" => "effect-1",
      "claim_id" => "claim-1",
      "writer_epoch" => epoch
    }
  end

  defp issue_operation(epoch),
    do: %{"type" => "issue_claim", "claim_id" => "claim-1", "writer_epoch" => epoch}

  defp protected_command(id, reads, operation) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => reads,
      "operation" => operation
    }
  end

  defp protected_fact(gateway, capability, type, key, value) do
    Gateway.protected_query(gateway, capability, %{
      "schema_version" => 1,
      "type" => type,
      key => value
    })
  end

  defp commit_domain!(gateway, id) do
    command = %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "request_effect",
      "target_ids" => %{"ticket_id" => id},
      "payload" => %{}
    }

    bundle = %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [
        %{
          schema_version: 1,
          event_id: "event-#{id}",
          type: "effect_requested",
          payload: %{
            "projection" => %{
              "namespace" => "integration-v1",
              "entity_id" => id,
              "revision" => 0,
              "value" => %{"status" => "ready"}
            }
          }
        }
      ],
      projections: [
        %{
          schema_version: 1,
          namespace: "integration-v1",
          entity_id: id,
          expected_revision: -1,
          revision: 0,
          last_event_id: "event-#{id}",
          value: %{"status" => "ready"}
        }
      ],
      intents: []
    }

    assert {:ok, _result, :committed} = Gateway.transact(gateway, "operator", command, bundle)
  end

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("integration-v1", padding: false) <>
      "/" <> Base.url_encode64(id, padding: false)
  end

  defp assert_combined_content(content) do
    assert content["commands"].count == 1
    assert content["events"].count == 1
    assert content["projections"].count == 1
    assert content["root_commands"].count >= 6
    assert content["root_claims"].count == 1
    assert content["root_ledgers"].count == 1
    assert content["root_reservations"].count == 1
  end

  defp make_accepted_v1!(path) do
    {:ok, conn} = Sqlite3.open(path, mode: :readwrite)
    assert :ok = Sqlite3.execute(conn, "PRAGMA foreign_keys = OFF")
    Enum.each(@protected_tables, &assert(:ok = Sqlite3.execute(conn, "DROP TABLE #{&1}")))

    assert :ok =
             Database.execute(
               conn,
               "DELETE FROM metadata WHERE key IN ('protected_schema_version', 'migration_fr08a_v1', 'migration_atomic_bundle_v2')"
             )

    assert :ok = Sqlite3.close(conn)
  end

  defp initialized_path(root, name) do
    path = Path.join(root, "#{name}.sqlite3")
    assert :ok = Gateway.initialize(path)
    path
  end

  defp execute_raw!(path, sql) do
    {:ok, conn} = Sqlite3.open(path, mode: :readwrite)
    assert :ok = Sqlite3.execute(conn, sql)
    assert :ok = Sqlite3.close(conn)
  end

  defp metadata!(path, key) do
    {:ok, conn} = Sqlite3.open(path, mode: :readwrite)
    result = Database.query(conn, "SELECT value FROM metadata WHERE key = ?", [key])
    assert :ok = Sqlite3.close(conn)

    case result do
      {:ok, [[value]]} -> value
      {:ok, []} -> nil
    end
  end

  defp table_exists?(path, table) do
    {:ok, conn} = Sqlite3.open(path, mode: :readwrite)

    result =
      Database.query(conn, "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ?", [
        table
      ])

    assert :ok = Sqlite3.close(conn)
    result == {:ok, [[1]]}
  end

  defp content!(path) do
    {:ok, conn} = Database.open(path)
    assert {:ok, content} = Authority.content(conn)
    assert :ok = Database.close(conn)
    content
  end

  defp unique_id,
    do: "integration-#{System.unique_integer([:positive, :monotonic])}"

  defp canonical_tmp,
    do: if(File.dir?("/private/tmp"), do: "/private/tmp", else: System.tmp_dir!())
end
