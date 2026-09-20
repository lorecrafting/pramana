defmodule PramanaFoundry.DurableStore.OperationalStorageTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
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

  test "the production-default stalled probe returns unknown while ordinary requests stay usable",
       ctx do
    parent = self()

    gateway =
      ready_gateway(ctx.path,
        capacity_probe: fn _path ->
          send(parent, {:capacity_probe_started, self()})
          receive do: (:never -> :ok)
        end
      )

    request = Task.async(fn -> Gateway.operational_health(gateway) end)
    assert_receive {:capacity_probe_started, probe}
    probe_monitor = Process.monitor(probe)

    assert %{mode: :ready} = Gateway.status(gateway)
    assert {:ok, counts} = Gateway.counts(gateway)
    assert counts["commands"] == 0

    assert {:ok,
            %{
              capacity: %{
                status: :unknown,
                physical_available_bytes: {:unknown, :capacity_probe_timeout}
              }
            }} = Task.await(request, 7_000)

    assert_receive {:DOWN, ^probe_monitor, :process, ^probe, :killed}
    assert :sys.get_state(gateway).operational_health_requests == %{}
    assert %{mode: :ready} = Gateway.status(gateway)
  end

  test "a dead health caller cancels its stalled probe without leaking a request", ctx do
    parent = self()

    gateway =
      ready_gateway(ctx.path,
        capacity_probe: fn _path ->
          send(parent, {:orphan_probe_started, self()})
          receive do: (:never -> :ok)
        end
      )

    caller = spawn(fn -> Gateway.operational_health(gateway) end)
    caller_monitor = Process.monitor(caller)
    assert_receive {:orphan_probe_started, probe}
    probe_monitor = Process.monitor(probe)

    Process.exit(caller, :kill)
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :killed}
    assert_receive {:DOWN, ^probe_monitor, :process, ^probe, :killed}
    assert :sys.get_state(gateway).operational_health_requests == %{}
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

  test "harmless backup preflight refusal does not fence the store", ctx do
    gateway = ready_gateway(ctx.path, [])
    destination = Path.join(ctx.root, "already-present.sqlite3")
    File.write!(destination, "operator-owned")

    assert {:error, :backup_exists} = Gateway.backup(gateway, destination)
    assert File.read!(destination) == "operator-owned"
    assert %{mode: :ready, reason: nil} = Gateway.status(gateway)
  end

  test "engine interruption during checkpoint and backup fences later effects and retains authority",
       ctx do
    for operation <- [:checkpoint, :backup] do
      path = Path.join(ctx.root, "#{operation}.sqlite3")
      capability = make_ref()

      seed =
        start_store(path,
          protected_capability: capability,
          capacity_probe: fn _path -> {:ok, 1} end
        )

      commit_protected(seed, "#{operation}-PRIOR", capability, 4_000_000)
      baseline_path = Path.join(ctx.root, "#{operation}-baseline.sqlite3")
      assert {:ok, %{content: baseline}} = Gateway.backup(seed, baseline_path)
      baseline_digest = file_digest(baseline_path)
      assert_complete_authority(baseline)
      assert :ok = stop_supervised(Path.basename(path))

      parent = self()

      fault = fn conn ->
        worker = spawn(fn -> interrupt_connection(conn) end)
        send(parent, {:maintenance_interrupter, operation, worker})
        :ok
      end

      gateway =
        start_supervised!(
          {Gateway,
           path: path,
           protected_capability: capability,
           maintenance_fault: {:during, :"during_#{operation}", fault}},
          id: {:interrupted, operation}
        )

      destination = Path.join(ctx.root, "#{operation}-partial.sqlite3")

      result =
        case operation do
          :checkpoint -> Gateway.checkpoint(gateway)
          :backup -> Gateway.backup(gateway, destination)
        end

      assert_receive {:maintenance_interrupter, ^operation, interrupter}
      interrupter_monitor = Process.monitor(interrupter)
      send(interrupter, :stop)
      assert_receive {:DOWN, ^interrupter_monitor, :process, ^interrupter, :normal}

      assert {:error, {:storage_unavailable, reason}} = result
      assert inspect(reason) =~ "interrupt"
      assert %{mode: :recovery} = Gateway.status(gateway)

      assert {:error, {:recovery_mode, _reason}} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "operator",
                 command("#{operation}-LATER"),
                 bundle("#{operation}-LATER"),
                 protected("#{operation}-LATER")
               )

      assert {:error, {:recovery_mode, _reason}} =
               Gateway.backup(gateway, Path.join(ctx.root, "#{operation}-fenced.sqlite3"))

      partial =
        if File.exists?(destination), do: {File.stat!(destination).size, file_digest(destination)}

      assert :ok = stop_supervised({:interrupted, operation})

      reopened =
        start_supervised!(
          {Gateway, path: path, protected_capability: capability},
          id: {:reopened, operation}
        )

      recovered_path = Path.join(ctx.root, "#{operation}-recovered.sqlite3")
      assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, recovered_path)
      assert_complete_authority(baseline)
      assert file_digest(baseline_path) == baseline_digest

      if partial do
        assert {File.stat!(destination).size, file_digest(destination)} == partial
      end

      assert :ok = stop_supervised({:reopened, operation})
    end
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

  if :os.type() == {:unix, :darwin} do
    test "an owned full filesystem produces real ENOSPC and preserves prior authority", ctx do
      capability = make_ref()
      gateway = ready_gateway(ctx.path, protected_capability: capability)
      commit_protected(gateway, "PHYSICAL-ENOSPC", capability, 4_000_000)

      baseline_path = Path.join(ctx.root, "enospc-baseline.sqlite3")
      assert {:ok, %{content: baseline}} = Gateway.backup(gateway, baseline_path)
      baseline_digest = file_digest(baseline_path)
      assert_complete_authority(baseline)

      image = attach_disk_image(ctx.root, "enospc", 12)
      released_bytes = fill_and_release(image.mount, 512 * 1_024)
      assert released_bytes == 512 * 1_024

      destination = Path.join(image.mount, "partial.sqlite3")
      result = Gateway.backup(gateway, destination)

      assert {:error, {:storage_unavailable, reason}} = result
      assert inspect(reason) =~ "full"
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert File.exists?(image.path)

      partial =
        if File.exists?(destination), do: {File.stat!(destination).size, file_digest(destination)}

      assert :ok = stop_supervised(Gateway)

      reopened =
        start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

      recovered_path = Path.join(ctx.root, "enospc-recovered.sqlite3")
      assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, recovered_path)
      assert file_digest(baseline_path) == baseline_digest

      if partial do
        assert {File.stat!(destination).size, file_digest(destination)} == partial
      end
    end

    test "forced loss of an owned filesystem returns a real kernel sync error and retains backup",
         ctx do
      capability = make_ref()
      parent = self()
      image = attach_disk_image(ctx.root, "sync", 12)

      detach_during_sync = fn _file ->
        {output, status} = detached_command(image.hdiutil, ["detach", "-force", image.mount])

        send(parent, {:physical_sync_detach, status, output})

        if status == 0,
          do: :ok,
          else: {:error, {:physical_sync_detach_failed, status, output}}
      end

      seed = ready_gateway(ctx.path, protected_capability: capability)
      commit_protected(seed, "PHYSICAL-SYNC", capability)
      source_baseline = Path.join(ctx.root, "sync-source-baseline.sqlite3")
      assert {:ok, %{content: baseline}} = Gateway.backup(seed, source_baseline)
      assert_complete_authority(baseline)
      source_baseline_digest = file_digest(source_baseline)
      assert :ok = stop_supervised(Gateway)

      gateway =
        start_supervised!(
          {Gateway,
           path: ctx.path,
           protected_capability: capability,
           maintenance_fault: {:during, :during_backup_sync, detach_during_sync}}
        )

      destination = Path.join(image.mount, "sync-failed.sqlite3")
      result = Gateway.backup(gateway, destination)

      assert_receive {:physical_sync_detach, 0, detach_output}
      assert detach_output =~ "ejected"
      assert {:error, {:storage_unavailable, reason}} = result
      assert inspect(reason) =~ "ebadf"
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert File.exists?(image.path)

      attach_existing_image(image)
      assert File.exists?(destination)
      retained_digest = file_digest(destination)
      assert {:ok, %{content: ^baseline}} = Maintenance.verify(destination)
      assert file_digest(destination) == retained_digest

      assert :ok = stop_supervised(Gateway)

      reopened =
        start_supervised!({Gateway, path: ctx.path, protected_capability: capability})

      assert {:ok, %{content: ^baseline}} =
               Gateway.backup(reopened, Path.join(ctx.root, "sync-source-recovered.sqlite3"))

      assert file_digest(source_baseline) == source_baseline_digest
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

  defp commit_protected(gateway, id, capability \\ nil, padding_bytes \\ 0) do
    capability = capability || :sys.get_state(gateway).protected_capability

    assert {:ok, _result, :committed} =
             Gateway.transact_verified(
               gateway,
               capability,
               "operator",
               command(id, padding_bytes),
               bundle(id),
               protected(id)
             )
  end

  defp command(id, padding_bytes \\ 0) do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "expected_revisions" => %{projection_key(id) => "absent"},
      "type" => "request_effect",
      "target_ids" => %{"ticket_id" => id},
      "payload" => %{"maintenance_padding" => String.duplicate("x", padding_bytes)}
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

  defp interrupt_connection(conn) do
    receive do
      :stop ->
        :ok
    after
      1 ->
        :ok = Sqlite3.interrupt(conn)
        interrupt_connection(conn)
    end
  end

  defp assert_complete_authority(content) do
    assert content["commands"].count == 1
    assert content["events"].count == 1
    assert content["projections"].count == 1
    assert content["effects"].count == 1
    assert content["claims"].count == 1
    assert content["ledger_generations"].count == 1
    assert content["reservations"].count == 1
  end

  defp attach_disk_image(root, name, size_mb) do
    hdiutil = System.find_executable("hdiutil") || flunk("hdiutil is required on Darwin")
    image_root = Path.join(root, "#{name}-image")
    image_path = Path.join(image_root, "fixture.dmg")
    mount = Path.join(image_root, "mount")
    File.mkdir_p!(mount)

    assert {_, 0} =
             System.cmd(
               hdiutil,
               ["create", "-quiet", "-size", "#{size_mb}m", "-fs", "HFS+", image_path],
               stderr_to_stdout: true
             )

    image = %{hdiutil: hdiutil, path: image_path, mount: mount}
    attach_existing_image(image)

    on_exit(fn ->
      _ = System.cmd(hdiutil, ["detach", "-force", mount], stderr_to_stdout: true)
    end)

    image
  end

  defp attach_existing_image(image) do
    assert {_, 0} =
             System.cmd(
               image.hdiutil,
               ["attach", "-quiet", "-nobrowse", "-mountpoint", image.mount, image.path],
               stderr_to_stdout: true
             )

    :ok
  end

  defp fill_and_release(mount, release_bytes) do
    filler = Path.join(mount, "filler.bin")
    {:ok, file} = :file.open(String.to_charlist(filler), [:write, :binary, :raw])
    chunk = :binary.copy(<<0>>, 1_024 * 1_024)
    assert :enospc = fill_until_enospc(file, chunk)
    assert :ok = :file.close(file)

    {:ok, file} = :file.open(String.to_charlist(filler), [:read, :write, :binary, :raw])
    {:ok, size} = :file.position(file, :eof)
    assert size > release_bytes
    {:ok, _position} = :file.position(file, size - release_bytes)
    assert :ok = :file.truncate(file)
    assert :ok = :file.sync(file)
    assert :ok = :file.close(file)
    release_bytes
  end

  defp fill_until_enospc(file, chunk) do
    case :file.write(file, chunk) do
      :ok -> fill_until_enospc(file, chunk)
      {:error, reason} -> reason
    end
  end

  defp detached_command(command, arguments) do
    caller = self()
    token = make_ref()

    spawn(fn ->
      result = System.cmd(command, arguments, stderr_to_stdout: true)
      send(caller, {token, result})
    end)

    receive do
      {^token, result} -> result
    end
  end

  defp canonical_tmp do
    case :os.type() do
      {:unix, :darwin} -> "/private/tmp"
      _other -> System.tmp_dir!()
    end
  end
end
