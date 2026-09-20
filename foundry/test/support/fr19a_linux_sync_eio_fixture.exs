Code.require_file("../../ci/fr19a_sync_eio_orchestration.exs", __DIR__)

alias PramanaFoundry.DurableStore.{Encoding, Gateway, Maintenance}
alias PramanaFoundry.CI.FR19ASyncEIOOrchestration, as: Orchestration

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

assert_complete = fn content ->
  for table <- ~w(commands events projections effects claims ledger_generations reservations) do
    unless content[table].count == 1 do
      raise "incomplete #{table}: #{inspect(content[table])}"
    end
  end
end

restore_and_stop = fn dirty_holder ->
  restore_result =
    try do
      run_host.("restore")
    rescue
      error -> {:error, error, __STACKTRACE__}
    end

  stop_result = Orchestration.stop_pwrite_holder(dirty_holder)

  case {restore_result, stop_result} do
    {:ok, :ok} -> :ok
    {{:error, error, stacktrace}, _stop} -> reraise error, stacktrace
    {:ok, {:error, reason}} -> raise "dirty holder cleanup failed: #{inspect(reason)}"
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
  {:ok, dirty_holder} = Orchestration.start_pwrite_holder(destination)
  send(parent, {:dirty_holder, dirty_holder})

  try do
    run_host.("suspend")
    :ok = Orchestration.start_pwrite(dirty_holder)

    case Orchestration.resume_before_await(dirty_holder.pid, dirty_holder.token, fn ->
           run_host.("error-resume")
         end) do
      {:ok, :ok} ->
        IO.puts("DIRTY_PWRITE=ok")
        :ok

      {:ok, {:error, :eio}} ->
        IO.puts("DIRTY_PWRITE=error:eio")
        :ok

      {:ok, other} ->
        raise "dirty pwrite failed: #{inspect(other)}"

      {:error, reason} ->
        raise "dirty pwrite orchestration failed: #{inspect(reason)}"
    end
  rescue
    error ->
      _ = restore_and_stop.(dirty_holder)
      reraise error, __STACKTRACE__
  end
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
    {:dirty_holder, holder} -> holder
  after
    10_000 -> raise "maintenance hook did not return the dirty holder"
  end

:ok = restore_and_stop.(dirty_holder)

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
