defmodule PramanaFoundry.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    args = :init.get_plain_arguments()
    mix_env = mix_env()
    test_mode = mix_env == :test
    mode = if test_mode, do: :daemon, else: startup_mode(args)
    operator_root = PramanaFoundry.RuntimeRoot.initialize_operator_root!()
    runtime_root = PramanaFoundry.RuntimeRoot.resolve_and_publish!(mix_env, operator_root)

    herdr_cmd = Application.get_env(:pramana_foundry, :herdr_command, "herdr")
    poll_ms = Application.get_env(:pramana_foundry, :poll_seconds, 15) * 1000

    enable_tick =
      System.get_env("COORDINATOR_TICK") == "1" ||
        Application.get_env(:pramana_foundry, :enable_tick, false)

    IO.puts("PramanaFoundry starting: tick=#{enable_tick} herdr=#{herdr_cmd} poll=#{poll_ms}ms")

    runtime_children =
      if mode == :client do
        IO.puts("  client mode: skipping coordinator/improver stack")
        []
      else
        [
          {Registry, keys: :unique, name: PramanaFoundry.Registry},
          {Task.Supervisor,
           name: PramanaFoundry.TaskSupervisor,
           max_children: Application.fetch_env!(:pramana_foundry, :max_tasks)},
          {PramanaFoundry.Coordinator,
           [
             herdr_command: herdr_cmd,
             poll_ms: poll_ms,
             enable_tick: enable_tick,
             require_runtime_owner: not test_mode,
             telemetry_log_path: Path.join(runtime_root, "state/current/telemetry.jsonl"),
             event_log_path: Path.join(runtime_root, "state/current/events.jsonl"),
             coordinator_log_path: Path.join(runtime_root, "state/current/coordinator.jsonl")
           ]},
          # The coordinator is deliberately started before the assignment supervisor.
          # Reverse-order shutdown therefore leaves its checked persistence gateway
          # available while AgentServer terminate callbacks record cleanup receipts.
          {DynamicSupervisor,
           name: PramanaFoundry.AssignmentSupervisor,
           strategy: :one_for_one,
           max_children: Application.fetch_env!(:pramana_foundry, :max_assignments)},
          {PramanaFoundry.Improver,
           [
             telemetry_path:
               Path.join(
                 runtime_root,
                 "state/current/telemetry.jsonl"
               ),
             interval_ms: 300_000
           ]},
          {PramanaFoundry.HardeningPM, [interval_ms: 600_000]}
        ]
      end

    children =
      cond do
        mode == :client ->
          []

        test_mode ->
          runtime_children

        true ->
          [{PramanaFoundry.RuntimeOwner, runtime_root: runtime_root, children: runtime_children}]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: PramanaFoundry.Supervisor)
  end

  @doc false
  @spec startup_mode([binary()]) :: :daemon | :client
  def startup_mode(args) do
    case System.get_env("PRAMANA_STARTUP_MODE") do
      "daemon" -> :daemon
      "client" -> :client
      _ -> if(args == [], do: :daemon, else: :client)
    end
  end

  defp mix_env do
    if Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0),
      do: apply(Mix, :env, []),
      else: :prod
  end
end
