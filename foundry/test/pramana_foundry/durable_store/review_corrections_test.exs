defmodule PramanaFoundry.DurableStore.ReviewCorrectionsTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Database, Encoding, Gateway, LegacyImport}

  setup do
    root = Path.join(System.tmp_dir!(), "fr07-corrections-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    path = Path.join(root, "authority.sqlite3")
    assert :ok = Gateway.initialize(path)
    %{root: root, path: path}
  end

  test "candidate operations accept only bounded pending intents and known operations", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})

    for mutation <- [
          &put_in(&1, [:intents, Access.at(0), :status], "issued"),
          &put_in(&1, [:intents, Access.at(0), :request_digest], "not-a-digest"),
          &put_in(&1, [:intents, Access.at(0), :request_digest], String.duplicate("b", 64)),
          &put_in(&1, [:intents, Access.at(0), :value, "operation"], "update_ref"),
          &put_in(&1, [:events, Access.at(0), :type], "arbitrary_authority")
        ] do
      assert {:error, _reason} = Gateway.transact(gateway, "actor", command("R1"), mutation.(bundle("R1")))
    end

    assert {:error, :invalid_command} =
             Gateway.transact(
               gateway,
               "actor",
               %{command("R1") | "type" => "arbitrary_command"},
               bundle("R1")
             )

    assert_empty(gateway)
  end

  test "read preconditions are authoritative and rejected decisions cannot mutate", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("BASE"), bundle("BASE"))

    dependency = projection_key("BASE") |> String.replace_prefix("projection/", "dependency/")
    stale_command = put_in(command("STALE")["expected_revisions"], %{projection_key("STALE") => "absent", dependency => 99})

    assert {:error, {:bundle_rejected, {:revision_conflict, ^dependency, 99, 0}}} =
             Gateway.transact(gateway, "actor", stale_command, bundle("STALE"))

    conn = :sys.get_state(gateway).conn
    object = {:blob, ~s({"schema_version":1})}
    assert :ok = Database.execute(conn, "INSERT INTO policy_revisions VALUES ('policy', 'BASE', 1, 3, ?)", [object])
    assert :ok = Database.execute(conn, "INSERT INTO control_revisions VALUES ('control', 'BASE', 1, 4, ?)", [object])

    for {kind, id} <- [{"policy", "policy"}, {"control", "control"}] do
      key = kind <> "/" <> Base.url_encode64(id, padding: false)
      command_id = String.upcase(kind)
      stale = put_in(command(command_id)["expected_revisions"], %{projection_key(command_id) => "absent", key => 99})
      assert {:error, {:bundle_rejected, {:revision_conflict, ^key, 99, ^actual}}} = Gateway.transact(gateway, "actor", stale, bundle(command_id))
    end

    rejected =
      bundle("REJECT")
      |> put_in([:result, :disposition], "rejected")
      |> put_in([:result, :reason_code], "operator_rejected")

    assert {:error, :rejected_result_has_domain_mutation} =
             Gateway.transact(gateway, "actor", command("REJECT"), rejected)

    assert {:ok, %{"commands" => 1, "events" => 1}} = Gateway.counts(gateway)
    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "same semantic protected retry returns durable result before changed current facts", %{path: path} do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})
    command = command("RETRY")
    proposal = bundle("RETRY")

    assert {:ok, result, :committed} =
             Gateway.transact_verified(gateway, capability, "actor", command, proposal, protected("RETRY"))

    assert {:ok, ^result, :idempotent} =
             Gateway.transact_verified(gateway, capability, "actor", command, %{proposal | schema_version: 99}, %{})
  end

  test "corrupt bodies fence startup and corrupt reads fence the live gateway", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("BODY"), bundle("BODY"))

    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "UPDATE command_results SET result = ? WHERE command_id = 'BODY'", [{:blob, "not-json"}])
    assert {:error, {:recovery_mode, {:corrupt_authority, :corrupt_result}}} = Gateway.command(gateway, "BODY")
    assert %{mode: :recovery} = Gateway.status(gateway)
    stop_supervised!(Gateway)

    reopened = start_supervised!({Gateway, path: path})
    assert %{mode: :recovery, reason: {:invalid_stored_body, "command_results", _rowid, :malformed_json}} = Gateway.status(reopened)
  end

  test "unknown retained versions and foreign-key violations fence recovery", %{root: root} do
    version_path = Path.join(root, "unknown-version.sqlite3")
    assert :ok = Gateway.initialize(version_path)
    gateway = start_supervised!({Gateway, path: version_path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("VERSION"), bundle("VERSION"))
    conn = :sys.get_state(gateway).conn
    assert :ok = Database.execute(conn, "UPDATE command_results SET result = ?", [{:blob, ~s({"schema_version":99,"disposition":"accepted"})}])
    assert :ok = stop_supervised(Gateway)
    gateway = start_supervised!({Gateway, path: version_path})
    assert %{mode: :recovery, reason: {:invalid_stored_body, "command_results", _rowid, :unsupported_version}} = Gateway.status(gateway)
    assert :ok = stop_supervised(Gateway)

    fk_path = Path.join(root, "foreign-key.sqlite3")
    assert :ok = Gateway.initialize(fk_path)
    {:ok, conn} = Database.open(fk_path)
    assert :ok = Database.execute(conn, "PRAGMA foreign_keys = OFF")
    assert :ok = Database.execute(conn, "INSERT INTO projections VALUES ('kernel-v1', 'orphan', 1, 0, 'missing-event', ?)", [{:blob, ~s({"state":"orphan"})}])
    assert :ok = Database.close(conn)
    gateway = start_supervised!({Gateway, path: fk_path})
    assert %{mode: :recovery, reason: {:invalid_store, [["projections", _, "events", 0]]}} = Gateway.status(gateway)
  end

  test "one persistent owner excludes a second gateway and migration reruns", %{path: path} do
    first = start_supervised!({Gateway, path: path})
    second = start_supervised!({Gateway, path: path}, id: :second_gateway)
    assert %{mode: :recovery, reason: {:store_owner_unavailable, _reason}} = Gateway.status(second)
    assert :ok = stop_supervised(:second_gateway)

    fixture = Path.expand("test/support/durable_store_owner_probe.exs")
    {_output, 0} = System.cmd(System.find_executable("mix"), ["run", "--no-start", fixture, path], stderr_to_stdout: true)
    assert :ok = stop_supervised(Gateway)

    assert :ok = Gateway.migrate(path)
    assert :ok = Gateway.migrate(path)

    {:ok, conn} = Database.open(path)
    assert {:ok, [["complete"]]} = Database.query(conn, "SELECT value FROM metadata WHERE key = 'migration_v1'")
    assert :ok = Database.close(conn)
    refute Process.alive?(first)
  end

  test "every protected-table failpoint rolls back and preserves prior committed content", %{path: path} do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})
    assert {:ok, _result, :committed} = Gateway.transact_verified(gateway, capability, "actor", command("BASE"), bundle("BASE"), protected("BASE"))
    assert :ok = stop_supervised(Gateway)

    for point <- [:after_input, :after_command, :after_events, :after_projections, :after_intents, :after_generations, :after_claims, :after_reservations, :after_result] do
      gateway = start_supervised!({Gateway, path: path, protected_capability: capability, fault: {:after_insert, point}})

      assert {:error, {:storage_unavailable, {:injected_after_insert, ^point}}} =
               Gateway.transact_verified(gateway, capability, "actor", command("FAIL-#{point}"), bundle("FAIL-#{point}"), protected("FAIL-#{point}"))

      assert :ok = stop_supervised(Gateway)
      gateway = start_supervised!({Gateway, path: path, protected_capability: capability})
      assert {:ok, %{"inputs" => 1, "commands" => 1, "events" => 1, "effects" => 1, "claims" => 1, "ledger_generations" => 1, "reservations" => 1}} = Gateway.counts(gateway)
      assert :ok = stop_supervised(Gateway)
    end
  end

  test "real OS file-size limit reaches SQLite commit I/O failure without acknowledgment", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})
    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", command("BASE"), bundle("BASE"))
    assert :ok = stop_supervised(Gateway)

    fixture = Path.expand("test/support/durable_store_write_fault_fixture.exs")
    script = "trap '' XFSZ; ulimit -f 100; exec mix run --no-start \"$1\" \"$2\""

    {output, 0} =
      System.cmd("/bin/zsh", ["-c", script, "fr07-rlimit", fixture, path],
        stderr_to_stdout: true,
        env: [{"MIX_ENV", "test"}]
      )

    assert output =~ "real_rlimit_write_failure"
    assert output =~ "commit_failed"
    assert output =~ "disk I/O error"

    gateway = start_supervised!({Gateway, path: path, recovery_evidence: "RLIMIT_FSIZE child exited after checked commit error"})
    assert {:ok, %{"commands" => 1, "events" => 1}} = Gateway.counts(gateway)
    assert {:error, :not_found} = Gateway.command(gateway, "rlimit-write")
  end

  test "canonical command protocol uses exact lowercase control escapes and domain tag" do
    assert {:ok, ~S({"x":"\u0000\u0008\u0009\u000a\u000c\u000d\u001f"})} =
             Encoding.canonical(%{"x" => <<0, 8, 9, 10, 12, 13, 31>>})

    assert {:ok, canonical} = Encoding.canonical(%{"domain" => "pramana-foundry-command-v1", "schema_version" => 1})
    assert Encoding.digest(canonical) == "a97024e2321b4803bd4f714ab66a47b0376e1a148bfc119154aa9992cb790b01"
  end

  test "engine backup verifies every authority table with nonempty protected/import content", %{root: root, path: path} do
    source = Path.join(root, "legacy.jsonl")
    File.write!(source, ~s({"schema_version":1,"event":"old","at":"2026-09-13T00:00:00Z","attributes":{},"evidence":{}}\n))
    assert {:ok, _manifest} = LegacyImport.run(path, source, Path.join(root, "archive"))

    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})
    assert {:ok, _result, :committed} = Gateway.transact_verified(gateway, capability, "actor", command("BACKUP"), bundle("BACKUP"), protected("BACKUP"))
    conn = :sys.get_state(gateway).conn
    object = {:blob, ~s({"schema_version":1})}
    assert :ok = Database.execute(conn, "INSERT INTO receipts VALUES ('receipt', 'effect-BACKUP', 'request', 1, ?)", [object])
    assert :ok = Database.execute(conn, "INSERT INTO leases VALUES ('lease', 'claim-BACKUP', 1, ?)", [object])
    assert :ok = Database.execute(conn, "INSERT INTO policy_revisions VALUES ('policy', 'BACKUP', 1, 0, ?)", [object])
    assert :ok = Database.execute(conn, "INSERT INTO control_revisions VALUES ('control', 'BACKUP', 1, 0, ?)", [object])
    assert :ok = Database.execute(conn, "INSERT INTO artifact_references VALUES ('artifact', 'BACKUP', 1, ?, ?)", [String.duplicate("b", 64), object])

    backup = Path.join(root, "complete-backup.sqlite3")
    assert {:ok, %{content: content, reconstruction: reconstruction}} =
             Gateway.backup(gateway, backup)

    assert reconstruction.projection_count == 1
    assert byte_size(reconstruction.sha256) == 64

    expected = ~w(metadata inputs commands command_results events projections effects claims receipts leases ledger_generations reservations policy_revisions control_revisions artifact_references import_runs legacy_records sqlite_sequence)
    assert Enum.sort(Map.keys(content)) == Enum.sort(expected)

    for table <- ~w(inputs commands command_results events projections effects claims receipts leases ledger_generations reservations policy_revisions control_revisions artifact_references import_runs legacy_records) do
      assert content[table].count > 0
      assert byte_size(content[table].sha256) == 64
    end

    {:ok, copied} = Database.open(backup)
    assert {:ok, [[1, 1, 1]]} = Database.query(copied, "SELECT (SELECT count(*) FROM import_runs), (SELECT count(*) FROM claims), (SELECT count(*) FROM receipts)")
    assert :ok = Database.close(copied)

    {:ok, [[projection_bytes]]} = Database.query(conn, "SELECT projection FROM projections")
    projection = :json.decode(projection_bytes)
    {:ok, damaged} = Encoding.json(put_in(projection["value"]["status"], "invented"))
    assert :ok = Database.execute(conn, "UPDATE projections SET projection = ?", [{:blob, damaged}])

    assert {:error,
            {:authority_corrupt, "projections", "reconstruction",
             :projection_replay_mismatch}} =
             Gateway.backup(gateway, Path.join(root, "corrupt-projection-backup.sqlite3"))

    assert %{
             mode: :recovery,
             reason:
               {:authority_corrupt, "projections", "reconstruction",
                :projection_replay_mismatch}
           } =
             Gateway.status(gateway)
  end

  defp assert_empty(gateway) do
    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  defp command(id) do
    %{"schema_version" => 1, "command_id" => id, "expected_revisions" => %{projection_key(id) => "absent"}, "type" => "request_effect", "target_ids" => %{"ticket_id" => "T1"}, "payload" => %{}}
  end

  defp bundle(id) do
    event_id = "event-#{id}"
    %{schema_version: 1, result: %{schema_version: 1, disposition: "accepted", reason_code: nil}, events: [%{schema_version: 1, event_id: event_id, type: "effect_requested", payload: %{}}], projections: [%{schema_version: 1, namespace: "kernel-v1", entity_id: "ticket-#{id}", expected_revision: -1, revision: 0, last_event_id: event_id, value: %{"status" => "ready"}}], intents: [%{schema_version: 1, effect_id: "effect-#{id}", request_digest: String.duplicate("a", 64), status: "pending", value: %{"operation" => "check"}}]}
  end

  defp protected(id) do
    %{writer_epoch: "epoch", required_revisions: %{projection_key(id) => "absent"}, ledger_generations: [%{schema_version: 1, generation_id: "generation-#{id}", parent_generation_id: nil, allocation: 1, consumed: 0}], effect_authorizations: [%{effect_id: "effect-#{id}", claim_id: "claim-#{id}", generation_id: "generation-#{id}", reservation_id: "reservation-#{id}", dimension: "starts.developer", units: 1}]}
  end

  defp projection_key(id), do: "projection/" <> Base.url_encode64("kernel-v1", padding: false) <> "/" <> Base.url_encode64("ticket-#{id}", padding: false)
end
