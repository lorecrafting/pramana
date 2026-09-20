defmodule PramanaFoundry.DurableStore.GatewayTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.{Database, Gateway}
  alias PramanaFoundry.EventLog

  setup do
    root = Path.join(System.tmp_dir!(), "durable-store-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, "authority.sqlite3")}
  end

  test "missing initialization and unknown store versions enter explicit recovery", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})
    assert %{mode: :recovery, reason: :not_initialized} = Gateway.status(gateway)

    assert {:error, {:recovery_mode, :not_initialized}} =
             Gateway.transact(gateway, "actor", command("C0"), bundle("C0"))

    stop_supervised!(Gateway)

    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation",
               repository_id: "repository"
             )

    assert {:error, :already_initialized} = Gateway.initialize(path)

    {:ok, conn} = Database.open(path)

    assert :ok =
             Database.execute(
               conn,
               "UPDATE metadata SET value = '99' WHERE key = 'event_version'"
             )

    assert :ok = Database.close(conn)

    gateway = start_supervised!({Gateway, path: path})

    assert %{mode: :recovery, reason: {:unsupported_metadata, "event_version", "99", "1"}} =
             Gateway.status(gateway)
  end

  test "corrupt SQLite authority never becomes an empty workflow", %{path: path} do
    File.write!(path, "not a sqlite database\n")
    gateway = start_supervised!({Gateway, path: path})
    assert %{mode: :recovery, reason: reason} = Gateway.status(gateway)
    refute is_nil(reason)
    assert File.read!(path) == "not a sqlite database\n"
  end

  test "one commit atomically writes separately constrained authority rows", %{path: path} do
    gateway = ready_gateway(path)
    command = command("C1")

    assert {:ok, %{"committed_seq" => 1, "disposition" => "accepted"}, :committed} =
             Gateway.transact(gateway, "operator", command, bundle("C1"))

    assert {:ok,
            %{
              "inputs" => 1,
              "commands" => 1,
              "command_results" => 1,
              "events" => 1,
              "projections" => 1,
              "effects" => 1,
              "claims" => 1,
              "ledger_generations" => 1,
              "reservations" => 1
            }} = Gateway.counts(gateway)

    assert {:ok, _result, :idempotent} =
             Gateway.transact(gateway, "operator", command, bundle("C1"))

    assert {:error, :idempotency_conflict} =
             Gateway.transact(gateway, "other", command, bundle("C1"))

    changed = put_in(command["payload"], %{"changed" => true})

    assert {:error, :idempotency_conflict} =
             Gateway.transact(gateway, "operator", changed, bundle("C1"))
  end

  test "a crash before commit leaves no partial authority and fences effects", %{path: path} do
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path, fault: :before_commit})

    assert {:error, {:storage_unavailable, :injected_crash_before_commit}} =
             Gateway.transact(gateway, "operator", command("C2"), bundle("C2"))

    assert %{mode: :recovery} = Gateway.status(gateway)
    stop_supervised!(Gateway)

    gateway = start_supervised!({Gateway, path: path})
    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  test "commit before lost reply is recovered by same command retry", %{path: path} do
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path, fault: :after_commit_before_reply})
    command = command("C3")

    assert {:error, {:outcome_unknown, "C3"}} =
             Gateway.transact(gateway, "operator", command, bundle("C3"))

    assert {:ok, %{"committed_seq" => 1}, :idempotent} =
             Gateway.transact(gateway, "operator", command, bundle("C3"))

    assert {:ok, %{"commands" => 1, "events" => 1}} = Gateway.counts(gateway)
  end

  test "injected write and capacity failures cannot acknowledge", %{path: path} do
    for fault <- [:write_error, :full] do
      fault_path = path <> ".#{fault}"
      assert :ok = Gateway.initialize(fault_path)
      gateway = start_supervised!({Gateway, path: fault_path, fault: fault, name: fault})

      assert {:error, {:storage_unavailable, reason}} =
               Gateway.transact(gateway, "operator", command("C-#{fault}"), bundle("C-#{fault}"))

      assert reason in [:injected_write_error, :injected_full]
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert :ok = stop_supervised(Gateway)
    end
  end

  test "the real SQLite capacity limit rolls back a large command and enters recovery", %{
    path: path
  } do
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path, max_page_count: 50})
    large = put_in(command("REAL-FULL")["payload"], %{"bytes" => String.duplicate("x", 1024 * 1024)})

    assert {:error, {:storage_unavailable, reason}} =
             Gateway.transact(gateway, "operator", large, bundle("REAL-FULL"))

    assert reason in [:full, :ioerr_write, "database or disk is full"]
    assert %{mode: :recovery} = Gateway.status(gateway)
  end

  test "legacy EventLog writers can opt into the checked durable boundary", %{path: path} do
    gateway = ready_gateway(path)

    record = %{
      "schema_version" => 1,
      "event" => "ticket_enqueued",
      "at" => "2026-09-13T00:00:00Z",
      "attributes" => %{},
      "evidence" => %{}
    }

    destination = {:durable_store, gateway, "legacy-controller", "opaque-command-1"}
    assert :ok = EventLog.append(destination, record)
    assert :ok = EventLog.append(destination, record)
    assert {:ok, %{"commands" => 1, "events" => 1}} = Gateway.counts(gateway)

    changed = put_in(record["event"], "different")
    assert {:error, :idempotency_conflict} = EventLog.append(destination, changed)
  end

  test "foreign-key, uniqueness and projection CAS failures roll back the entire bundle", %{
    path: path
  } do
    cases = [
      {"FK", put_in(bundle("FK")[:projections], [projection("FK", "missing-event")])},
      {"UNIQUE", update_in(bundle("UNIQUE")[:events], fn [event] -> [event, event] end)},
      {"CAS",
       put_in(bundle("CAS")[:projections], [
         %{projection("CAS", "event-CAS") | expected_revision: 0, revision: 1}
       ])}
    ]

    Enum.each(cases, fn {id, invalid_bundle} ->
      _ = stop_supervised(Gateway)

      if File.exists?(path), do: File.rm!(path)
      Enum.each([path <> "-wal", path <> "-shm"], &File.rm(&1))
      gateway = ready_gateway(path)

      assert {:error, {:bundle_rejected, _reason}} =
               Gateway.transact(gateway, "operator", command(id), invalid_bundle)

      assert {:ok, counts} = Gateway.counts(gateway)
      assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
      assert %{mode: :ready} = Gateway.status(gateway)
    end)
  end

  test "unknown proposal versions and candidate-supplied fields fail before SQL", %{path: path} do
    gateway = ready_gateway(path)

    assert {:error, :unsupported_version} =
             Gateway.transact(gateway, "operator", command("V2"), %{
               bundle("V2")
               | schema_version: 2
             })

    assert {:error, :unknown_field} =
             Gateway.transact(
               gateway,
               "operator",
               command("SQL"),
               Map.put(bundle("SQL"), :sql, "DROP TABLE commands")
             )

    assert %{mode: :ready} = Gateway.status(gateway)
    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  test "SQLite WAL/FULL and verified content backup survive reopen", %{root: root, path: path} do
    gateway = ready_gateway(path)

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "operator", command("BACKUP"), bundle("BACKUP"))

    backup = Path.join(root, "backup.sqlite3")
    assert {:ok, %{path: ^backup, content: content}} = Gateway.backup(gateway, backup)
    assert content["events"].count == 1
    assert is_binary(content["events"].sha256)
    assert {:error, :backup_exists} = Gateway.backup(gateway, backup)

    {:ok, conn} = Database.open(backup)
    assert {:ok, [["wal"]]} = Database.query(conn, "PRAGMA journal_mode")
    assert {:ok, [[2]]} = Database.query(conn, "PRAGMA synchronous")
    assert {:ok, [[1]]} = Database.query(conn, "PRAGMA foreign_keys")
    assert :ok = Database.close(conn)
  end

  defp ready_gateway(path) do
    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation",
               repository_id: "repository"
             )

    start_supervised!({Gateway, path: path})
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{},
      "type" => "test",
      "target_ids" => %{"ticket_id" => "T1"},
      "payload" => %{"text" => "literal"}
    }
  end

  defp bundle(id) do
    event_id = "event-#{id}"

    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [%{schema_version: 1, event_id: event_id, type: "tested", payload: %{"id" => id}}],
      projections: [projection(id, event_id)],
      intents: [
        %{
          schema_version: 1,
          effect_id: "effect-#{id}",
          request_digest: String.duplicate("a", 64),
          status: "pending",
          value: %{"operation" => "test"}
        }
      ],
      ledger_generations: [
        %{
          schema_version: 1,
          generation_id: "generation-#{id}",
          parent_generation_id: nil,
          allocation: 1,
          consumed: 0
        }
      ],
      claims: [
        %{
          schema_version: 1,
          claim_id: "claim-#{id}",
          effect_id: "effect-#{id}",
          writer_epoch: "epoch-1",
          status: "active",
          value: %{}
        }
      ],
      reservations: [
        %{
          schema_version: 1,
          reservation_id: "reservation-#{id}",
          generation_id: "generation-#{id}",
          claim_id: "claim-#{id}",
          dimension: "starts.developer",
          units: 1,
          status: "reserved",
          value: %{}
        }
      ]
    }
  end

  defp projection(id, event_id) do
    %{
      schema_version: 1,
      namespace: "kernel-v1",
      entity_id: "ticket-#{id}",
      expected_revision: -1,
      revision: 0,
      last_event_id: event_id,
      value: %{"status" => "ready"}
    }
  end
end
