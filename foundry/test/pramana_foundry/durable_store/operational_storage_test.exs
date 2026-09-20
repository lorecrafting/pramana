defmodule PramanaFoundry.DurableStore.OperationalStorageTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.DurableStore.{Encoding, Gateway, Maintenance}

  setup do
    root = Path.join(canonical_tmp(), "fr19a-storage-#{System.unique_integer([:positive])}")
    File.mkdir!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, path: Path.join(root, "authority.sqlite3")}
  end

  test "operational inspection is bounded and reports capacity without inventing it", ctx do
    gateway = ready_gateway(ctx.path, capacity_probe: fn _path -> {:ok, 12_345} end)
    commit_protected(gateway, "A")
    commit_protected(gateway, "B")

    assert {:ok,
            %{
              mode: :ready,
              last_durable_sequence: 2,
              capacity: %{
                status: :known,
                physical_available_bytes: 12_345,
                sqlite_available_bytes: available
              }
            }} = Gateway.operational_health(gateway)

    assert available > 0

    assert {:ok, [%{sequence: 2, event_id: "event-B"}]} = Gateway.recent_events(gateway, 1)

    assert {:error, {:invalid_limit, %{minimum: 1, maximum: 1_000}}} =
             Gateway.recent_events(gateway, 1_001)

    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "capacity probe failures remain explicit unknowns and cannot crash the owner", ctx do
    gateway =
      ready_gateway(ctx.path,
        capacity_probe: fn _path -> exit(:capacity_probe_failed) end
      )

    assert {:ok,
            %{
              capacity: %{
                status: :unknown,
                physical_available_bytes:
                  {:unknown, {:capacity_probe_exit, :capacity_probe_failed}}
              }
            }} = Gateway.operational_health(gateway)

    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "a stalled capacity probe is bounded and leaves the owner usable", ctx do
    gateway =
      ready_gateway(ctx.path,
        capacity_probe: fn _path -> receive do: (:never -> :ok) end,
        capacity_probe_timeout_ms: 10
      )

    assert {:ok,
            %{
              capacity: %{
                status: :unknown,
                physical_available_bytes: {:unknown, :capacity_probe_timeout}
              }
            }} = Gateway.operational_health(gateway)

    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "the host filesystem probe reports observed physical capacity", ctx do
    gateway = ready_gateway(ctx.path, [])

    assert {:ok,
            %{
              capacity: %{status: :known, physical_available_bytes: available_bytes}
            }} = Gateway.operational_health(gateway)

    assert available_bytes > 0
  end

  test "backup is content/replay verified and offline verification refuses a live owner", ctx do
    capability = make_ref()
    gateway = ready_gateway(ctx.path, protected_capability: capability)
    commit_protected(gateway, "BACKUP", capability)

    backup = Path.join(ctx.root, "backup.sqlite3")

    assert {:ok,
            %{
              content: source_content,
              reconstruction: %{sha256: replay_digest, projection_count: 1}
            }} = Gateway.backup(gateway, backup)

    assert {:error, {:store_owner_unavailable, _reason}} = Maintenance.verify(ctx.path)
    assert :ok = stop_supervised(Gateway)

    assert {:ok,
            %{
              last_durable_sequence: 1,
              content: ^source_content,
              replay: %{sha256: ^replay_digest, projection_count: 1}
            }} = Maintenance.verify(backup)

    assert source_content["claims"].count == 1
    assert source_content["ledger_generations"].count == 1
    assert source_content["reservations"].count == 1
  end

  test "real WAL checkpoint preserves complete claim and ledger history", ctx do
    capability = make_ref()
    gateway = ready_gateway(ctx.path, protected_capability: capability)
    commit_protected(gateway, "CHECKPOINT", capability)
    assert File.stat!(ctx.path <> "-wal").size > 0

    assert {:ok, %{busy: 0, last_durable_sequence: 1}} = Gateway.checkpoint(gateway)
    assert File.stat!(ctx.path <> "-wal").size == 0

    backup = Path.join(ctx.root, "checkpoint.sqlite3")
    assert {:ok, %{content: content}} = Gateway.backup(gateway, backup)
    assert content["claims"].count == 1
    assert content["ledger_generations"].count == 1
    assert content["reservations"].count == 1
  end

  test "physical SQLite corruption is retained and fenced while verified backup survives", ctx do
    capability = make_ref()
    gateway = ready_gateway(ctx.path, protected_capability: capability)
    commit_protected(gateway, "CORRUPT", capability)
    backup = Path.join(ctx.root, "before-corruption.sqlite3")
    assert {:ok, %{content: content}} = Gateway.backup(gateway, backup)
    assert :ok = stop_supervised(Gateway)

    {:ok, file} = :file.open(String.to_charlist(ctx.path), [:read, :write, :binary, :raw])
    assert :ok = :file.pwrite(file, 100, :binary.copy(<<0>>, 256))
    assert :ok = :file.sync(file)
    assert :ok = :file.close(file)
    damaged_digest = file_digest(ctx.path)

    corrupt = start_supervised!({Gateway, path: ctx.path})
    assert %{mode: :recovery, reason: reason} = Gateway.status(corrupt)
    refute is_nil(reason)
    assert file_digest(ctx.path) == damaged_digest
    assert {:error, {:recovery_mode, _reason}} = Gateway.checkpoint(corrupt)

    assert {:error, {:recovery_mode, _reason}} =
             Gateway.backup(corrupt, Path.join(ctx.root, "bad.sqlite3"))

    assert :ok = stop_supervised(Gateway)

    assert {:ok, %{content: ^content}} = Maintenance.verify(backup)
  end

  test "process interruption after real checkpoint or backup never loses prior authority", ctx do
    fixture = Path.expand("test/support/fr19a_maintenance_crash_fixture.exs")

    for operation <- ["checkpoint", "backup"] do
      path = Path.join(ctx.root, "#{operation}.sqlite3")
      capability = make_ref()

      gateway =
        start_store(path,
          protected_capability: capability,
          capacity_probe: fn _path -> {:ok, 1} end
        )

      commit_protected(gateway, String.upcase(operation), capability)
      baseline = Path.join(ctx.root, "#{operation}-baseline.sqlite3")
      assert {:ok, %{content: content}} = Gateway.backup(gateway, baseline)
      assert :ok = stop_supervised(Path.basename(path))

      destination = Path.join(ctx.root, "#{operation}-interrupted.sqlite3")

      {_output, 74} =
        System.cmd(
          System.find_executable("mix"),
          ["run", "--no-start", fixture, path, operation, destination],
          stderr_to_stdout: true,
          env: [{"COORDINATOR_TICK", nil}, {"HERDR_ENV", nil}, {"TMPDIR", canonical_tmp()}]
        )

      fenced = start_supervised!({Gateway, path: path}, id: {:fenced, operation})

      assert %{
               mode: :recovery,
               reason: {:store_owner_unavailable, {:ambiguous_previous_owner, _, _}}
             } = Gateway.status(fenced)

      assert :ok = stop_supervised({:fenced, operation})

      recovered =
        start_supervised!(
          {Gateway, path: path, recovery_evidence: "verified fixture exit 74"},
          id: {:recovered, operation}
        )

      after_path = Path.join(ctx.root, "#{operation}-after.sqlite3")
      assert {:ok, %{content: ^content}} = Gateway.backup(recovered, after_path)
      assert content["claims"].count == 1
      assert content["ledger_generations"].count == 1
      assert :ok = stop_supervised({:recovered, operation})
    end
  end

  defp ready_gateway(path, opts) do
    assert :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repo")
    start_supervised!({Gateway, Keyword.put(opts, :path, path)})
  end

  defp start_store(path, opts) do
    assert :ok = Gateway.initialize(path, installation_id: "installation", repository_id: "repo")
    start_supervised!({Gateway, Keyword.put(opts, :path, path)}, id: Path.basename(path))
  end

  defp commit_protected(gateway, id, capability \\ nil) do
    capability = capability || :sys.get_state(gateway).protected_capability

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "operator",
               command(id),
               bundle(id),
               protected(id)
             )
  end

  defp command(id) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "request_effect",
      "target_ids" => %{"ticket_id" => id},
      "payload" => %{}
    }
  end

  defp bundle(id) do
    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [
        %{
          schema_version: 1,
          event_id: "event-#{id}",
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
          last_event_id: "event-#{id}",
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

  defp projection_key(id) do
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-#{id}", padding: false)
  end

  defp effect_digest(id) do
    {:ok, digest} =
      Encoding.semantic_digest(
        "pramana-foundry-effect-request-v1",
        %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
      )

    digest
  end

  defp file_digest(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1)) |> Base.encode16(case: :lower)
  end

  defp canonical_tmp do
    case :os.type() do
      {:unix, :darwin} -> "/private/tmp"
      _other -> System.tmp_dir!()
    end
  end
end
