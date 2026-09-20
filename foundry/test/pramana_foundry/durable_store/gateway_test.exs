defmodule PramanaFoundry.DurableStore.GatewayTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Database, Gateway, RecordCodec}
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

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "metadata", "versions", :unsupported_version}
           } =
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
    capability = make_ref()
    gateway = ready_gateway(path, protected_capability: capability)
    command = command("C1")

    assert {:ok, %{"committed_seq" => 1, "disposition" => "accepted"}, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "operator",
               command,
               bundle("C1"),
               protected("C1")
             )

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
             Gateway.transact_verified(
               gateway,
               capability,
               "operator",
               command,
               bundle("C1"),
               protected("C1")
             )

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

  test "hard process exits on both commit boundaries have the documented durable result", %{
    root: root
  } do
    fixture = Path.expand("test/support/durable_store_crash_fixture.exs")

    for {boundary, status, expected_events} <- [{"before", 71, 1}, {"after", 72, 2}] do
      path = Path.join(root, boundary <> ".sqlite3")

      {_output, ^status} =
        System.cmd(System.find_executable("mix"), ["run", "--no-start", fixture, path, boundary],
          stderr_to_stdout: true,
          env: [{"COORDINATOR_TICK", nil}, {"HERDR_ENV", nil}]
        )

      fenced = start_supervised!({Gateway, path: path})

      assert %{
               mode: :recovery,
               reason: {:store_owner_unavailable, {:ambiguous_previous_owner, _, _}}
             } = Gateway.status(fenced)

      assert :ok = stop_supervised(Gateway)

      gateway =
        start_supervised!({Gateway, path: path, recovery_evidence: "verified child process exit"})

      assert {:ok,
              %{
                "commands" => ^expected_events,
                "events" => ^expected_events,
                "effects" => ^expected_events,
                "claims" => ^expected_events,
                "ledger_generations" => ^expected_events,
                "reservations" => ^expected_events
              }} =
               Gateway.counts(gateway)

      assert :ok = stop_supervised(Gateway)
    end
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

  test "an actual read-only filesystem store fails closed without rewriting it", %{
    root: root,
    path: path
  } do
    assert :ok = Gateway.initialize(path)
    original = File.read!(path)
    File.chmod!(path, 0o400)
    File.chmod!(root, 0o500)

    on_exit(fn ->
      File.chmod(root, 0o700)
      File.chmod(path, 0o600)
    end)

    gateway = start_supervised!({Gateway, path: path})
    assert %{mode: :recovery, reason: reason} = Gateway.status(gateway)
    refute is_nil(reason)
    assert File.read!(path) == original
  end

  test "the real SQLite capacity limit rolls back a large command and enters recovery", %{
    path: path
  } do
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path, max_page_count: 50})

    large =
      put_in(command("REAL-FULL")["payload"], %{"bytes" => String.duplicate("x", 1024 * 1024)})

    assert {:error, {:storage_unavailable, reason}} =
             Gateway.transact(gateway, "operator", large, bundle("REAL-FULL"))

    assert inspect(reason) =~ "database or disk is full"
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

  test "invalid projection references and uniqueness failures never partially commit", %{
    path: path
  } do
    cases = [
      {"FK", put_in(bundle("FK")[:projections], [projection("FK", "missing-event")]),
       {:error, :projection_event_missing}},
      {"UNIQUE", update_in(bundle("UNIQUE")[:events], fn [event] -> [event, event] end),
       :bundle_rejected}
    ]

    Enum.each(cases, fn {id, invalid_bundle, expected} ->
      _ = stop_supervised(Gateway)
      case_path = Path.join(Path.dirname(path), "#{String.downcase(id)}.sqlite3")
      gateway = ready_gateway(case_path)

      result = Gateway.transact(gateway, "operator", command(id), invalid_bundle)

      case expected do
        :bundle_rejected -> assert {:error, {:bundle_rejected, _reason}} = result
        exact -> assert ^exact = result
      end

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

  test "protected facts require the root's unforgeable capability", %{path: path} do
    capability = make_ref()
    gateway = ready_gateway(path, protected_capability: capability)

    assert {:error, :unauthorized_protected_operation} =
             Gateway.transact_verified(
               gateway,
               make_ref(),
               "operator",
               command("FORGED"),
               bundle("FORGED"),
               protected("FORGED")
             )

    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)

    assert {:error, :incomplete_protected_read_set} =
             Gateway.transact_verified(
               gateway,
               capability,
               "operator",
               put_in(command("OMITTED")["expected_revisions"], %{}),
               bundle("OMITTED"),
               protected("OMITTED")
             )
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

  defp ready_gateway(path, opts \\ []) do
    assert :ok =
             Gateway.initialize(path,
               installation_id: "installation",
               repository_id: "repository"
             )

    start_supervised!({Gateway, Keyword.put(opts, :path, path)})
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "request_effect",
      "target_ids" => %{"ticket_id" => "T1"},
      "payload" => %{"text" => "literal"}
    }
  end

  defp bundle(id) do
    event_id = "event-#{id}"

    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [
        %{
          schema_version: 1,
          event_id: event_id,
          type: "effect_requested",
          payload: %{
            "id" => id,
            "projection" => %{
              "namespace" => "kernel-v1",
              "entity_id" => "ticket-#{id}",
              "revision" => 0,
              "value" => %{"status" => "ready"}
            }
          }
        }
      ],
      projections: [projection(id, event_id)],
      intents: [
        %{
          schema_version: 1,
          effect_id: "effect-#{id}",
          request_digest: effect_digest(id),
          status: "pending",
          value: %{"operation" => "check"}
        }
      ]
    }
  end

  defp protected(id) do
    %{
      writer_epoch: "epoch-1",
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

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-#{id}", padding: false)
  end

  defp effect_digest(id) do
    {:ok, digest} =
      PramanaFoundry.DurableStore.Encoding.semantic_digest(
        "pramana-foundry-effect-request-v1",
        %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
      )

    digest
  end

  describe "lifecycle event vocabulary" do
    test "the legacy and lifecycle vocabularies are disjoint" do
      legacy = RecordCodec.legacy_event_types()
      lifecycle = RecordCodec.lifecycle_event_types()

      assert legacy != []
      assert lifecycle != []
      assert MapSet.disjoint?(MapSet.new(legacy), MapSet.new(lifecycle))
      assert Enum.sort(legacy ++ lifecycle) == Enum.sort(RecordCodec.event_types())
    end

    test "a lifecycle event commits, reopens, replays and survives backup validation",
         %{path: path} do
      gateway = ready_gateway(path)
      id = "LC1"

      lifecycle =
        bundle(id)
        |> Map.update!(:events, fn [event] -> [%{event | type: "launch_settled"}] end)

      assert {:ok, %{"disposition" => "accepted"}, :committed} =
               Gateway.transact(gateway, "operator", command(id), lifecycle)

      # Reads back with its type intact, through the real read path.
      assert {:ok, events} = Gateway.recent_events(gateway, 10)
      assert Enum.any?(events, &(&1.event_type == "launch_settled"))

      # A verified backup reconstructs from the durable events and refuses to publish
      # unless that reconstruction matches live authority, so a successful backup is the
      # replay evidence. Capture it for comparison across reopen.
      #
      # Note what each half of this test proves. The reconstruction is built from
      # event["payload"]["projection"] and is agnostic to the type string, so the
      # reconstruction-equality assertions alone would not establish that the name
      # "launch_settled" survived storage — only that some event with that projection
      # payload did. The recent_events assertions are what prove the type string itself
      # round-trips, which is the property this test exists for. Both halves are needed.
      assert {:ok, %{reconstruction: reconstruction}} =
               Gateway.backup(gateway, path <> ".lifecycle-backup")

      assert reconstruction != nil

      # Survives reopen, and replays to the same reconstruction afterwards.
      stop_supervised!(Gateway)
      reopened = start_supervised!({Gateway, path: path})
      assert %{mode: :ready} = Gateway.status(reopened)

      assert {:ok, %{reconstruction: ^reconstruction}} =
               Gateway.backup(reopened, path <> ".lifecycle-backup-2")

      assert {:ok, after_reopen} = Gateway.recent_events(reopened, 10)
      assert Enum.any?(after_reopen, &(&1.event_type == "launch_settled"))
    end

    test "the legacy vocabulary still commits unchanged", %{path: path} do
      gateway = ready_gateway(path)

      assert {:ok, %{"disposition" => "accepted"}, :committed} =
               Gateway.transact(gateway, "operator", command("LEG1"), bundle("LEG1"))
    end

    test "an unknown event type is still refused", %{path: path} do
      gateway = ready_gateway(path)

      unknown =
        bundle("UNK1")
        |> Map.update!(:events, fn [event] -> [%{event | type: "not_a_real_event"}] end)

      assert {:error, :invalid_event} =
               Gateway.transact(gateway, "operator", command("UNK1"), unknown)
    end
  end
end
