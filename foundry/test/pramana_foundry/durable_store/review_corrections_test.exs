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

  test "candidate operations accept only bounded pending intents and known operations", %{
    path: path
  } do
    gateway = start_supervised!({Gateway, path: path})

    # `:invalid_intent` is the shared fallback of every clause in
    # `RecordCodec.normalize(:intent, _)`, so the atom pins the record kind, not the
    # conjunct. See the 2026-09-22 refusal-audit log entry for which conjunct each
    # input actually reaches.
    for {mutation, reason} <- [
          {&put_in(&1, [:intents, Access.at(0), :status], "issued"), :invalid_intent},
          {&put_in(&1, [:intents, Access.at(0), :request_digest], "not-a-digest"),
           :invalid_intent},
          {&put_in(&1, [:intents, Access.at(0), :request_digest], String.duplicate("b", 64)),
           :invalid_intent},
          {&put_in(&1, [:intents, Access.at(0), :request_digest], String.duplicate("b", 64)),
           :invalid_intent},
          {&put_in(&1, [:intents, Access.at(0), :value, "operation"], "update_ref"),
           :invalid_intent},
          {&put_in(&1, [:events, Access.at(0), :type], "arbitrary_authority"), :invalid_event}
        ] do
      assert {:error, ^reason} =
               Gateway.transact(gateway, "actor", command("R1"), mutation.(bundle("R1")))
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

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("BASE"), bundle("BASE"))

    dependency = projection_key("BASE") |> String.replace_prefix("projection/", "dependency/")

    stale_command =
      put_in(command("STALE")["expected_revisions"], %{
        projection_key("STALE") => "absent",
        dependency => 99
      })

    assert {:ok, rejected, :rejected} =
             Gateway.transact(gateway, "actor", stale_command, bundle("STALE"))

    assert rejected["disposition"] == "rejected"
    assert rejected["reason_code"] == "revision_conflict"

    assert {:ok, ^rejected, :idempotent} =
             Gateway.transact(gateway, "actor", stale_command, bundle("STALE"))

    for {kind, id} <- [{"policy", "policy"}, {"control", "control"}] do
      key = kind <> "/" <> Base.url_encode64(id, padding: false)
      command_id = String.upcase(kind)

      stale =
        put_in(command(command_id)["expected_revisions"], %{
          projection_key(command_id) => "absent",
          key => 99
        })

      assert {:ok, %{"disposition" => "rejected", "reason_code" => "revision_conflict"},
              :rejected} = Gateway.transact(gateway, "actor", stale, bundle(command_id))
    end

    rejected =
      bundle("REJECT")
      |> put_in([:result, :disposition], "rejected")
      |> put_in([:result, :reason_code], "operator_rejected")

    assert {:error, :rejected_result_has_domain_mutation} =
             Gateway.transact(gateway, "actor", command("REJECT"), rejected)

    assert {:ok,
            %{
              "inputs" => 4,
              "commands" => 4,
              "command_results" => 4,
              "events" => 1,
              "projections" => 1,
              "effects" => 1
            }} = Gateway.counts(gateway)

    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "same semantic protected retry returns durable result before changed current facts", %{
    path: path
  } do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})
    command = command("RETRY")
    proposal = bundle("RETRY")

    assert {:ok, result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command,
               proposal,
               protected("RETRY")
             )

    assert {:ok, ^result, :idempotent} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command,
               %{proposal | schema_version: 99},
               %{}
             )
  end

  test "corrupt bodies fence startup and corrupt reads fence the live gateway", %{path: path} do
    gateway = start_supervised!({Gateway, path: path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("BODY"), bundle("BODY"))

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(
               conn,
               "UPDATE command_results SET result = ? WHERE command_id = 'BODY'",
               [{:blob, "not-json"}]
             )

    assert {:error,
            {:recovery_mode, {:authority_corrupt, "command_results", "BODY", :malformed_json}}} =
             Gateway.command(gateway, "BODY")

    assert %{mode: :recovery} = Gateway.status(gateway)
    stop_supervised!(Gateway)

    reopened = start_supervised!({Gateway, path: path})

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "command_results", _rowid, :malformed_json}
           } = Gateway.status(reopened)
  end

  test "unknown retained versions and foreign-key violations fence recovery", %{root: root} do
    version_path = Path.join(root, "unknown-version.sqlite3")
    assert :ok = Gateway.initialize(version_path)
    gateway = start_supervised!({Gateway, path: version_path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("VERSION"), bundle("VERSION"))

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(conn, "UPDATE command_results SET result = ?", [
               {:blob, ~s({"schema_version":99,"disposition":"accepted"})}
             ])

    assert :ok = stop_supervised(Gateway)
    gateway = start_supervised!({Gateway, path: version_path})

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "command_results", _rowid, :unsupported_version}
           } = Gateway.status(gateway)

    assert :ok = stop_supervised(Gateway)

    fk_path = Path.join(root, "foreign-key.sqlite3")
    assert :ok = Gateway.initialize(fk_path)
    {:ok, conn} = Database.open(fk_path)
    assert :ok = Database.execute(conn, "PRAGMA foreign_keys = OFF")

    assert :ok =
             Database.execute(
               conn,
               "INSERT INTO projections VALUES ('kernel-v1', 'orphan', 1, 0, 'missing-event', ?)",
               [{:blob, ~s({"state":"orphan"})}]
             )

    assert :ok = Database.close(conn)
    gateway = start_supervised!({Gateway, path: fk_path})

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "sqlite", "physical", [["projections", _, "events", 0]]}
           } =
             Gateway.status(gateway)
  end

  test "ordinary and protected idempotent corruption both fence", %{root: root} do
    for mode <- [:ordinary, :protected] do
      path = Path.join(root, "retry-#{mode}.sqlite3")
      assert :ok = Gateway.initialize(path)
      capability = make_ref()

      gateway =
        start_supervised!({Gateway, path: path, protected_capability: capability}, id: mode)

      id = "RETRY-#{mode}"
      command = command(id)
      proposal = bundle(id)

      case mode do
        :ordinary ->
          assert {:ok, _result, :committed} =
                   Gateway.transact(gateway, "actor", command, proposal)

        :protected ->
          assert {:ok, _result, :committed} =
                   Gateway.transact_verified(
                     gateway,
                     capability,
                     "actor",
                     command,
                     proposal,
                     protected(id)
                   )
      end

      conn = :sys.get_state(gateway).conn
      damaged = if mode == :ordinary, do: "not-json", else: ~s({"schema_version":99})
      cause = if mode == :ordinary, do: :malformed_json, else: :unsupported_version

      assert :ok =
               Database.execute(conn, "UPDATE command_results SET result = ?", [{:blob, damaged}])

      result =
        case mode do
          :ordinary ->
            Gateway.transact(gateway, "actor", command, proposal)

          :protected ->
            Gateway.transact_verified(
              gateway,
              capability,
              "actor",
              command,
              proposal,
              protected(id)
            )
        end

      assert {:error, {:authority_corrupt, "command_results", ^id, ^cause}} = result

      assert %{mode: :recovery, reason: {:authority_corrupt, "command_results", ^id, ^cause}} =
               Gateway.status(gateway)

      assert :ok = stop_supervised(mode)
    end
  end

  test "strict admission and result-column binding cannot create reopen-invalid authority", %{
    root: root
  } do
    path = Path.join(root, "strict.sqlite3")
    assert :ok = Gateway.initialize(path)
    gateway = start_supervised!({Gateway, path: path})

    scalar = put_in(bundle("SCALAR"), [:projections, Access.at(0), :value], true)

    assert {:error, :invalid_projection_revision} =
             Gateway.transact(gateway, "actor", command("SCALAR"), scalar)

    assert %{mode: :ready} = Gateway.status(gateway)

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("BIND"), bundle("BIND"))

    conn = :sys.get_state(gateway).conn

    assert :ok =
             Database.execute(conn, "UPDATE command_results SET result = ?", [
               {:blob,
                ~s({"committed_seq":1,"schema_version":1,"disposition":"invented","reason_code":null})}
             ])

    assert :ok = stop_supervised(Gateway)
    gateway = start_supervised!({Gateway, path: path})

    assert %{
             mode: :recovery,
             reason: {:authority_corrupt, "command_results", _rowid, :invalid_result_semantics}
           } = Gateway.status(gateway)
  end

  test "database symlink and hardlink aliases cannot create another owner or importer", %{
    root: root,
    path: path
  } do
    gateway = start_supervised!({Gateway, path: path})
    source = Path.join(root, "alias-source.jsonl")
    archive = Path.join(root, "alias-archive")

    File.write!(
      source,
      ~s({"schema_version":1,"event":"old","at":"2026-09-13T00:00:00Z","attributes":{},"evidence":{}}\n)
    )

    symlink = Path.join(root, "alias.sqlite3")
    File.ln_s!(path, symlink)
    second = start_supervised!({Gateway, path: symlink}, id: :symlink_gateway)
    assert %{mode: :recovery, reason: :database_symlink_not_allowed} = Gateway.status(second)
    assert {:error, :database_symlink_not_allowed} = LegacyImport.run(symlink, source, archive)

    fixture = Path.expand("test/support/durable_store_owner_probe.exs")

    {_output, 0} =
      System.cmd(System.find_executable("mix"), ["run", "--no-start", fixture, symlink],
        stderr_to_stdout: true
      )

    assert :ok = stop_supervised(:symlink_gateway)

    hardlink = Path.join(root, "hardlink.sqlite3")
    File.ln!(path, hardlink)
    third = start_supervised!({Gateway, path: hardlink}, id: :hardlink_gateway)
    assert %{mode: :recovery, reason: :database_hardlink_not_allowed} = Gateway.status(third)
    assert {:error, :database_hardlink_not_allowed} = LegacyImport.run(hardlink, source, archive)
    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "unsupported child ledger allocation cannot mint authority", %{path: path} do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("PARENT"),
               bundle("PARENT"),
               protected("PARENT")
             )

    facts =
      put_in(
        protected("CHILD"),
        [:ledger_generations, Access.at(0), :parent_generation_id],
        "generation-PARENT"
      )

    facts = put_in(facts, [:ledger_generations, Access.at(0), :allocation], 100)

    assert {:error, :unsupported_child_ledger_generation} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("CHILD"),
               bundle("CHILD"),
               facts
             )

    assert {:ok, %{"ledger_generations" => 1, "commands" => 1}} = Gateway.counts(gateway)
  end

  test "one persistent owner excludes a second gateway and migration reruns", %{path: path} do
    first = start_supervised!({Gateway, path: path})
    second = start_supervised!({Gateway, path: path}, id: :second_gateway)

    assert %{mode: :recovery, reason: {:store_owner_unavailable, _reason}} =
             Gateway.status(second)

    assert :ok = stop_supervised(:second_gateway)

    fixture = Path.expand("test/support/durable_store_owner_probe.exs")

    {_output, 0} =
      System.cmd(System.find_executable("mix"), ["run", "--no-start", fixture, path],
        stderr_to_stdout: true
      )

    assert :ok = stop_supervised(Gateway)

    assert :ok = Gateway.migrate(path)
    assert :ok = Gateway.migrate(path)

    {:ok, conn} = Database.open(path)

    assert {:ok, [["complete"]]} =
             Database.query(conn, "SELECT value FROM metadata WHERE key = 'migration_v1'")

    assert :ok = Database.close(conn)
    refute Process.alive?(first)
  end

  test "every protected-table failpoint rolls back and preserves prior committed content", %{
    path: path
  } do
    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("BASE"),
               bundle("BASE"),
               protected("BASE")
             )

    assert {:ok, %{content: baseline_content, reconstruction: baseline_reconstruction}} =
             Gateway.backup(gateway, Path.join(Path.dirname(path), "baseline.sqlite3"))

    assert :ok = stop_supervised(Gateway)

    for point <- [
          :after_input,
          :after_command,
          :after_events,
          :after_projections,
          :after_intents,
          :after_generations,
          :after_claims,
          :after_reservations,
          :after_result
        ] do
      gateway =
        start_supervised!(
          {Gateway, path: path, protected_capability: capability, fault: {:after_insert, point}}
        )

      assert {:error, {:storage_unavailable, {:injected_after_insert, ^point}}} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "actor",
                 command("FAIL-#{point}"),
                 bundle("FAIL-#{point}"),
                 protected("FAIL-#{point}")
               )

      assert :ok = stop_supervised(Gateway)
      gateway = start_supervised!({Gateway, path: path, protected_capability: capability})

      assert {:ok,
              %{
                "inputs" => 1,
                "commands" => 1,
                "events" => 1,
                "effects" => 1,
                "claims" => 1,
                "ledger_generations" => 1,
                "reservations" => 1
              }} = Gateway.counts(gateway)

      assert {:ok, %{content: ^baseline_content, reconstruction: ^baseline_reconstruction}} =
               Gateway.backup(
                 gateway,
                 Path.join(Path.dirname(path), "after-#{point}.sqlite3")
               )

      assert :ok = stop_supervised(Gateway)
    end
  end

  test "real OS file-size limit reaches SQLite commit I/O failure without acknowledgment", %{
    path: path
  } do
    gateway = start_supervised!({Gateway, path: path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("BASE"), bundle("BASE"))

    assert {:ok, %{content: baseline_content, reconstruction: baseline_reconstruction}} =
             Gateway.backup(gateway, Path.join(Path.dirname(path), "rlimit-baseline.sqlite3"))

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

    gateway =
      start_supervised!(
        {Gateway,
         path: path, recovery_evidence: "RLIMIT_FSIZE child exited after checked commit error"}
      )

    assert {:ok, %{"commands" => 1, "events" => 1}} = Gateway.counts(gateway)
    assert {:error, :not_found} = Gateway.command(gateway, "rlimit-write")

    assert {:ok, %{content: ^baseline_content, reconstruction: ^baseline_reconstruction}} =
             Gateway.backup(gateway, Path.join(Path.dirname(path), "rlimit-after.sqlite3"))
  end

  test "canonical command protocol uses exact lowercase control escapes and domain tag" do
    assert {:ok, ~S({"x":"\u0000\u0008\u0009\u000a\u000c\u000d\u001f"})} =
             Encoding.canonical(%{"x" => <<0, 8, 9, 10, 12, 13, 31>>})

    assert {:ok, canonical} =
             Encoding.canonical(%{
               "domain" => "pramana-foundry-command-v1",
               "schema_version" => 1
             })

    assert Encoding.digest(canonical) ==
             "a97024e2321b4803bd4f714ab66a47b0376e1a148bfc119154aa9992cb790b01"
  end

  test "engine backup verifies every authority table and keeps unsupported authority empty", %{
    root: root,
    path: path
  } do
    source = Path.join(root, "legacy.jsonl")

    File.write!(
      source,
      ~s({"schema_version":1,"event":"old","at":"2026-09-13T00:00:00Z","attributes":{},"evidence":{}}\n)
    )

    assert {:ok, _manifest} = LegacyImport.run(path, source, Path.join(root, "archive"))

    capability = make_ref()
    gateway = start_supervised!({Gateway, path: path, protected_capability: capability})

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "actor",
               command("BACKUP"),
               bundle("BACKUP"),
               protected("BACKUP")
             )

    conn = :sys.get_state(gateway).conn

    backup = Path.join(root, "complete-backup.sqlite3")

    assert {:ok, %{content: content, reconstruction: reconstruction}} =
             Gateway.backup(gateway, backup)

    assert reconstruction.projection_count == 1
    assert byte_size(reconstruction.sha256) == 64

    expected =
      ~w(metadata inputs commands command_results events projections effects claims receipts leases ledger_generations reservations policy_revisions control_revisions artifact_references import_runs legacy_records root_commands authenticated_inboxes authenticated_inbox_items root_policies root_policy_history root_controls root_control_history root_ledgers root_reservations root_effects root_claims root_receipts root_leases root_pointers atomic_bundles durable_operations root_infrastructure_settlements root_attempt_closures sqlite_sequence)

    assert Enum.sort(Map.keys(content)) == Enum.sort(expected)

    for table <-
          ~w(inputs commands command_results events projections effects claims ledger_generations reservations import_runs legacy_records) do
      assert content[table].count > 0
      assert byte_size(content[table].sha256) == 64
    end

    for table <- ~w(receipts leases policy_revisions control_revisions artifact_references) do
      assert content[table].count == 0
      assert byte_size(content[table].sha256) == 64
    end

    {:ok, copied} = Database.open(backup)

    assert {:ok, [[1, 1, 0]]} =
             Database.query(
               copied,
               "SELECT (SELECT count(*) FROM import_runs), (SELECT count(*) FROM claims), (SELECT count(*) FROM receipts)"
             )

    assert :ok = Database.close(copied)

    {:ok, [[projection_bytes]]} = Database.query(conn, "SELECT projection FROM projections")
    projection = :json.decode(projection_bytes)
    {:ok, damaged} = Encoding.json(put_in(projection["value"]["status"], "invented"))

    assert :ok =
             Database.execute(conn, "UPDATE projections SET projection = ?", [{:blob, damaged}])

    assert {:error,
            {:authority_corrupt, "projections", "reconstruction", :projection_replay_mismatch}} =
             Gateway.backup(gateway, Path.join(root, "corrupt-projection-backup.sqlite3"))

    assert %{
             mode: :recovery,
             reason:
               {:authority_corrupt, "projections", "reconstruction", :projection_replay_mismatch}
           } =
             Gateway.status(gateway)
  end

  test "projection reconstruction executes ordered create and update transitions", %{
    root: root,
    path: path
  } do
    gateway = start_supervised!({Gateway, path: path})

    assert {:ok, _result, :committed} =
             Gateway.transact(gateway, "actor", command("STATE"), bundle("STATE"))

    update_command =
      put_in(command("UPDATE")["expected_revisions"], %{projection_key("STATE") => 0})

    update =
      bundle("UPDATE")
      |> put_in([:events, Access.at(0), :payload, "projection"], %{
        "namespace" => "kernel-v1",
        "entity_id" => "ticket-STATE",
        "revision" => 1,
        "value" => %{"status" => "done"}
      })
      |> put_in([:projections, Access.at(0)], %{
        schema_version: 1,
        namespace: "kernel-v1",
        entity_id: "ticket-STATE",
        expected_revision: 0,
        revision: 1,
        last_event_id: "event-UPDATE",
        value: %{"status" => "done"}
      })

    assert {:ok, _result, :committed} = Gateway.transact(gateway, "actor", update_command, update)
    backup = Path.join(root, "updated-state.sqlite3")
    assert {:ok, %{reconstruction: %{projection_count: 1}}} = Gateway.backup(gateway, backup)

    {:ok, conn} = Database.open(backup)

    assert {:ok, [[1, bytes]]} =
             Database.query(
               conn,
               "SELECT revision, projection FROM projections WHERE entity_id = 'ticket-STATE'"
             )

    assert :json.decode(bytes)["value"] == %{"status" => "done"}
    assert :ok = Database.close(conn)
  end

  defp assert_empty(gateway) do
    assert {:ok, counts} = Gateway.counts(gateway)
    assert Enum.all?(counts, fn {_table, count} -> count == 0 end)
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "request_effect",
      "target_ids" => %{"ticket_id" => "T1"},
      "payload" => %{}
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
            "projection" => %{
              "namespace" => "kernel-v1",
              "entity_id" => "ticket-#{id}",
              "revision" => 0,
              "value" => %{"status" => "ready"}
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
          value: %{"status" => "ready"}
        }
      ],
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
      writer_epoch: "epoch",
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

  defp projection_key(id),
    do:
      "projection/" <>
        Base.url_encode64("kernel-v1", padding: false) <>
        "/" <> Base.url_encode64("ticket-#{id}", padding: false)

  defp effect_digest(id) do
    {:ok, digest} =
      Encoding.semantic_digest(
        "pramana-foundry-effect-request-v1",
        %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
      )

    digest
  end
end
