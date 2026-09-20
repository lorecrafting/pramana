alias PramanaFoundry.DurableStore.{Encoding, Gateway, Maintenance}

[source, baseline_path, destination, recovered_path, host_script, state_dir, artifact_dir] =
  System.argv()

parent = self()
capability = make_ref()

command = fn id ->
  %{
    "schema_version" => 1,
    "command_id" => id,
    "expected_revisions" => %{
      ("projection/" <>
         Base.url_encode64("kernel-v1", padding: false) <>
         "/" <> Base.url_encode64("ticket-#{id}", padding: false)) => "absent"
    },
    "type" => "request_effect",
    "target_ids" => %{"ticket_id" => id},
    "payload" => %{}
  }
end

effect_digest = fn id ->
  {:ok, digest} =
    Encoding.semantic_digest(
      "pramana-foundry-effect-request-v1",
      %{"effect_id" => "effect-#{id}", "operation" => %{"operation" => "check"}}
    )

  digest
end

bundle = fn id ->
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
        request_digest: effect_digest.(id),
        status: "pending",
        value: %{"operation" => "check"}
      }
    ]
  }
end

projection_key = fn id ->
  "projection/" <>
    Base.url_encode64("kernel-v1", padding: false) <>
    "/" <> Base.url_encode64("ticket-#{id}", padding: false)
end

protected = fn id ->
  %{
    writer_epoch: "epoch-1",
    required_revisions: %{projection_key.(id) => "absent"},
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

file_digest = fn path ->
  path
  |> File.read!()
  |> then(&:crypto.hash(:sha256, &1))
  |> Base.encode16(case: :lower)
end

run_host = fn mode ->
  caller = self()
  token = make_ref()

  spawn(fn ->
    result =
      System.cmd("/usr/bin/bash", [host_script, mode, state_dir, artifact_dir],
        stderr_to_stdout: true
      )

    send(caller, {token, result})
  end)

  receive do
    {^token, {output, 0}} ->
      IO.write(output)
      :ok

    {^token, {output, status}} ->
      raise "host helper #{mode} failed with #{status}: #{output}"
  after
    30_000 -> raise "host helper #{mode} timed out"
  end
end

holder = fn controller ->
  {:ok, file} = :file.open(String.to_charlist(destination), [:read, :write, :binary, :raw])
  {:ok, bytes} = :file.pread(file, 0, 4096)
  send(controller, {:holder_ready, self()})

  receive do
    {:dirty, reply_to} ->
      result = :file.pwrite(file, 0, bytes)
      send(reply_to, {:dirty_written, self(), result})
  end

  receive do
    {:close, reply_to} ->
      result = :file.close(file)
      send(reply_to, {:holder_closed, self(), result})
  end
end

assert_complete = fn content ->
  for table <- ~w(commands events projections effects claims ledger_generations reservations) do
    unless content[table].count == 1 do
      raise "incomplete #{table}: #{inspect(content[table])}"
    end
  end
end

:ok = Gateway.initialize(source, installation_id: "installation", repository_id: "repo")
{:ok, seed} = Gateway.start_link(path: source, protected_capability: capability)

{:ok, _result, :committed} =
  Gateway.transact_verified(
    seed,
    capability,
    "operator",
    command.("SYNC-EIO"),
    bundle.("SYNC-EIO"),
    protected.("SYNC-EIO")
  )

{:ok, %{content: baseline}} = Gateway.backup(seed, baseline_path)
assert_complete.(baseline)
baseline_digest = file_digest.(baseline_path)
:ok = GenServer.stop(seed)

fault = fn _gateway_file ->
  controller = self()
  dirty_holder = spawn(fn -> holder.(controller) end)

  receive do
    {:holder_ready, ^dirty_holder} -> :ok
  after
    10_000 -> raise "dirty holder did not open and pre-read the target"
  end

  run_host.("suspend")
  send(dirty_holder, {:dirty, controller})

  receive do
    {:dirty_written, ^dirty_holder, :ok} -> IO.puts("DIRTY_PWRITE=ok")
    {:dirty_written, ^dirty_holder, other} -> raise "dirty pwrite failed: #{inspect(other)}"
  after
    10_000 -> raise "dirty pwrite timed out while mapper was suspended"
  end

  run_host.("error-resume")
  send(parent, {:dirty_holder, dirty_holder})
  :ok
end

{:ok, gateway} =
  Gateway.start_link(
    path: source,
    protected_capability: capability,
    maintenance_fault: {:during, :during_backup_sync, fault}
  )

backup_result = Gateway.backup(gateway, destination)

dirty_holder =
  receive do
    {:dirty_holder, pid} -> pid
  after
    10_000 -> raise "maintenance hook did not return the dirty holder"
  end

case backup_result do
  {:error, {:storage_unavailable, {:backup_failed, :eio}}} ->
    IO.puts("GATEWAY_STORAGE_FAILURE=eio")

  other ->
    raise "expected typed EIO storage failure, got: #{inspect(other)}"
end

%{mode: :recovery} = Gateway.status(gateway)

{:error, {:recovery_mode, _reason}} =
  Gateway.transact_verified(
    gateway,
    capability,
    "operator",
    command.("LATER"),
    bundle.("LATER"),
    protected.("LATER")
  )

:ok = run_host.("restore")
holder_monitor = Process.monitor(dirty_holder)
send(dirty_holder, {:close, self()})

receive do
  {:holder_closed, ^dirty_holder, :ok} -> :ok
after
  10_000 -> raise "dirty holder did not close after mapper restore"
end

receive do
  {:DOWN, ^holder_monitor, :process, ^dirty_holder, :normal} -> :ok
after
  10_000 -> raise "dirty holder remained alive"
end

unless File.exists?(destination), do: raise("partial backup destination was removed")
partial_digest = file_digest.(destination)
{:ok, %{content: ^baseline}} = Maintenance.verify(destination)
^partial_digest = file_digest.(destination)
^baseline_digest = file_digest.(baseline_path)
:ok = GenServer.stop(gateway)

{:ok, reopened} = Gateway.start_link(path: source, protected_capability: capability)
{:ok, %{content: ^baseline}} = Gateway.backup(reopened, recovered_path)
assert_complete.(baseline)
:ok = GenServer.stop(reopened)

IO.puts("BASELINE_SHA256=#{baseline_digest}")
IO.puts("PARTIAL_SHA256=#{partial_digest}")
IO.puts("FIXTURE_RESULT=pass")
