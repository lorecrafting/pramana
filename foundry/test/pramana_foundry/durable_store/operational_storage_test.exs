defmodule PramanaFoundry.DurableStore.OperationalStorageTest do
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias PramanaFoundry.DurableStore.{Database, Encoding, Gateway, Maintenance}

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

  test "untrappable owner loss stops a default stalled probe and permits recovery", ctx do
    assert :ok = Gateway.initialize(ctx.path)
    parent = self()

    {:ok, gateway} =
      Gateway.start_link(
        path: ctx.path,
        capacity_probe: fn _path ->
          send(parent, {:owner_loss_probe_started, self()})
          receive do: (:never -> :ok)
        end
      )

    Process.unlink(gateway)
    gateway_monitor = Process.monitor(gateway)

    caller =
      spawn(fn ->
        try do
          Gateway.operational_health(gateway)
        catch
          :exit, reason -> send(parent, {:owner_loss_caller_exit, self(), reason})
        end
      end)

    caller_monitor = Process.monitor(caller)
    assert_receive {:owner_loss_probe_started, probe}
    probe_monitor = Process.monitor(probe)

    [request] = :sys.get_state(gateway).operational_health_requests |> Map.values()
    controller = request.pid
    controller_monitor = Process.monitor(controller)

    Process.exit(gateway, :kill)

    assert_receive {:DOWN, ^gateway_monitor, :process, ^gateway, :killed}
    assert_receive {:owner_loss_caller_exit, ^caller, {:killed, {GenServer, :call, _call}}}
    assert_receive {:DOWN, ^caller_monitor, :process, ^caller, :normal}
    assert_receive {:DOWN, ^probe_monitor, :process, ^probe, :killed}, 1_000
    assert_receive {:DOWN, ^controller_monitor, :process, ^controller, :normal}, 1_000

    {:ok, recovered} =
      Gateway.start_link(
        path: ctx.path,
        recovery_evidence: "observed killed test owner",
        capacity_probe: fn _path -> {:ok, 321} end
      )

    assert %{mode: :ready} = Gateway.status(recovered)

    assert {:ok, %{capacity: %{status: :known, physical_available_bytes: 321}}} =
             Gateway.operational_health(recovered)

    assert :ok = GenServer.stop(recovered)
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
      parent = self()
      armed = :atomics.new(1, signed: false)

      fault = fn conn ->
        if :atomics.get(armed, 1) == 0 do
          :ok
        else
          ready = make_ref()
          callback = self()
          worker = spawn(fn -> interrupt_connection(conn, callback, ready) end)

          receive do
            {:maintenance_interrupter_ready, ^ready, ^worker} -> :ok
          after
            1_000 -> raise "maintenance interrupter did not start"
          end

          send(parent, {:maintenance_interrupter, operation, worker})

          {:scoped,
           fn operation_result ->
             worker_monitor = Process.monitor(worker)
             send(worker, :stop)

             stopped =
               receive do
                 {:DOWN, ^worker_monitor, :process, ^worker, :normal} -> :ok
               after
                 1_000 -> {:error, :maintenance_interrupter_stop_timeout}
               end

             send(parent, {:maintenance_operation_result, operation, operation_result})
             stopped
           end}
        end
      end

      seed =
        start_store(path,
          protected_capability: capability,
          capacity_probe: fn _path -> {:ok, 1} end,
          maintenance_fault: {:during, :"during_#{operation}", fault}
        )

      connection = :sys.get_state(seed).conn
      assert {:ok, [[0]]} = Database.query(connection, "PRAGMA wal_autocheckpoint=0")

      prior_count = 4

      for index <- 1..prior_count do
        commit_protected(seed, "#{operation}-PRIOR-#{index}", capability, 4_000_000)
      end

      baseline_path = Path.join(ctx.root, "#{operation}-baseline.sqlite3")
      assert {:ok, %{content: baseline}} = Gateway.backup(seed, baseline_path)
      baseline_digest = file_digest(baseline_path)
      assert_complete_authority(baseline, prior_count)
      source_identity = File.stat!(path).inode

      wal_precondition =
        if operation == :checkpoint do
          wal_precondition(path, connection)
        end

      :atomics.put(armed, 1, 1)

      destination = Path.join(ctx.root, "#{operation}-partial.sqlite3")

      request =
        Task.async(fn ->
          case operation do
            :checkpoint -> Gateway.checkpoint(seed)
            :backup -> Gateway.backup(seed, destination)
          end
        end)

      assert_receive {:maintenance_interrupter, ^operation, interrupter}, 5_000
      interrupter_monitor = Process.monitor(interrupter)
      assert_receive {:DOWN, ^interrupter_monitor, :process, ^interrupter, :normal}, 5_000
      assert_receive {:maintenance_operation_result, ^operation, operation_result}, 5_000
      result = Task.await(request, 10_000)

      assert {:error, operation_reason} = operation_result
      assert inspect(operation_reason) =~ "interrupt"

      assert {:error, {:storage_unavailable, reason}} = result
      assert inspect(reason) =~ "interrupt"
      assert %{mode: :recovery} = Gateway.status(seed)
      assert File.stat!(path).inode == source_identity

      if operation == :checkpoint do
        assert %{size: size, frames: frames, inode: wal_inode} = wal_precondition
        assert size > 32
        assert frames > 0
        retained_wal = File.stat!(path <> "-wal")
        assert retained_wal.inode == wal_inode
        assert retained_wal.size > 0
      end

      assert {:error, {:recovery_mode, _reason}} =
               Gateway.transact_verified(
                 seed,
                 capability,
                 "operator",
                 command("#{operation}-LATER"),
                 bundle("#{operation}-LATER"),
                 protected("#{operation}-LATER")
               )

      assert {:error, {:recovery_mode, _reason}} =
               Gateway.backup(seed, Path.join(ctx.root, "#{operation}-fenced.sqlite3"))

      partial =
        if File.exists?(destination), do: {File.stat!(destination).size, file_digest(destination)}

      assert :ok = stop_supervised(Path.basename(path))

      reopened =
        start_supervised!(
          {Gateway, path: path, protected_capability: capability},
          id: {:reopened, operation}
        )

      recovered_path = Path.join(ctx.root, "#{operation}-recovered.sqlite3")
      assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, recovered_path)
      assert_complete_authority(baseline, prior_count)
      assert {:ok, %{content: ^baseline}} = Maintenance.verify(baseline_path)
      assert {:ok, %{content: ^baseline}} = Maintenance.verify(recovered_path)
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

    test "checkpoint on an owned full filesystem returns real ENOSPC and retains the WAL", ctx do
      capability = make_ref()
      image = attach_disk_image(ctx.root, "checkpoint-enospc", 20)
      source = Path.join(image.mount, "authority.sqlite3")

      gateway = ready_gateway(source, protected_capability: capability)
      commit_protected(gateway, "CHECKPOINT-ENOSPC", capability, 2_000_000)
      assert File.stat!(source <> "-wal").size > 0

      baseline_path = Path.join(ctx.root, "checkpoint-enospc-baseline.sqlite3")
      assert {:ok, %{content: baseline}} = Gateway.backup(gateway, baseline_path)
      assert_complete_authority(baseline)
      assert File.stat!(source <> "-wal").size > 0

      filler = fill_to_enospc(image.mount)
      assert File.exists?(filler)

      assert {:error, {:storage_unavailable, reason}} = Gateway.checkpoint(gateway)
      assert inspect(reason) =~ "full"
      assert %{mode: :recovery} = Gateway.status(gateway)
      assert File.exists?(source)
      assert File.stat!(source <> "-wal").size > 0

      assert {:error, {:recovery_mode, _reason}} =
               Gateway.transact_verified(
                 gateway,
                 capability,
                 "operator",
                 command("CHECKPOINT-ENOSPC-LATER"),
                 bundle("CHECKPOINT-ENOSPC-LATER"),
                 protected("CHECKPOINT-ENOSPC-LATER")
               )

      assert :ok = stop_supervised(Gateway)
      File.rm!(filler)

      reopened =
        start_supervised!({Gateway, path: source, protected_capability: capability})

      recovered_path = Path.join(ctx.root, "checkpoint-enospc-recovered.sqlite3")
      assert {:ok, %{content: ^baseline}} = Gateway.backup(reopened, recovered_path)
      assert_complete_authority(baseline)
    end

    test "forced loss of an owned filesystem invalidates a descriptor but is not sync acceptance",
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

  defp interrupt_connection(conn, parent, ready) do
    owner_monitor = Process.monitor(parent)
    send(parent, {:maintenance_interrupter_ready, ready, self()})
    interrupt_connection_loop(conn, parent, owner_monitor)
  end

  defp interrupt_connection_loop(conn, owner, owner_monitor) do
    receive do
      :stop ->
        Process.demonitor(owner_monitor, [:flush])
        :ok

      {:DOWN, ^owner_monitor, :process, ^owner, _reason} ->
        :ok
    after
      1 ->
        :ok = Sqlite3.interrupt(conn)
        interrupt_connection_loop(conn, owner, owner_monitor)
    end
  end

  defp wal_precondition(path, conn) do
    wal = File.stat!(path <> "-wal")
    assert {:ok, [[page_size]]} = Database.query(conn, "PRAGMA page_size")
    frame_bytes = page_size + 24
    assert wal.size > 32
    assert rem(wal.size - 32, frame_bytes) == 0

    %{
      size: wal.size,
      page_size: page_size,
      frames: div(wal.size - 32, frame_bytes),
      inode: wal.inode
    }
  end

  defp assert_complete_authority(content, expected \\ 1) do
    assert content["commands"].count == expected
    assert content["events"].count == expected
    assert content["projections"].count == expected
    assert content["effects"].count == expected
    assert content["claims"].count == expected
    assert content["ledger_generations"].count == expected
    assert content["reservations"].count == expected
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
    filler = fill_to_enospc(mount)

    {:ok, file} = :file.open(String.to_charlist(filler), [:read, :write, :binary, :raw])
    {:ok, size} = :file.position(file, :eof)
    assert size > release_bytes
    {:ok, _position} = :file.position(file, size - release_bytes)
    assert :ok = :file.truncate(file)
    assert :ok = :file.sync(file)
    assert :ok = :file.close(file)
    release_bytes
  end

  defp fill_to_enospc(mount) do
    filler = Path.join(mount, "filler-#{System.unique_integer([:positive])}.bin")
    {:ok, file} = :file.open(String.to_charlist(filler), [:write, :binary, :raw])
    chunk = :binary.copy(<<0>>, 1_024 * 1_024)
    assert :enospc = fill_until_enospc(file, chunk)
    assert :ok = :file.sync(file)
    assert :ok = :file.close(file)
    filler
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
