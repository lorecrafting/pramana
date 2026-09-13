defmodule PramanaFoundry.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # When running as escript, the CLI main() runs after this.
    # If the escript command is "board", skip the full supervision tree
    # (coordinator, improver, etc.) since those run in the daemon.
    # The board command starts only what it needs.
    args = :init.get_plain_arguments()
    is_board = "board" in args

    herdr_cmd = Application.get_env(:pramana_foundry, :herdr_command, "herdr")
    poll_ms = Application.get_env(:pramana_foundry, :poll_seconds, 15) * 1000

    enable_tick =
      System.get_env("COORDINATOR_TICK") == "1" ||
        Application.get_env(:pramana_foundry, :enable_tick, false)

    IO.puts("PramanaFoundry starting: tick=#{enable_tick} herdr=#{herdr_cmd} poll=#{poll_ms}ms")

    children =
      if is_board do
        # Board mode: only OWL LiveScreen support, no coordinator stack
        IO.puts("  board mode: skipping coordinator/improver stack")
        []
      else
        [
          {Registry, keys: :unique, name: PramanaFoundry.Registry},
          {DynamicSupervisor,
           name: PramanaFoundry.AssignmentSupervisor,
           strategy: :one_for_one,
           max_children: Application.fetch_env!(:pramana_foundry, :max_assignments)},
          {Task.Supervisor,
           name: PramanaFoundry.TaskSupervisor,
           max_children: Application.fetch_env!(:pramana_foundry, :max_tasks)},
          {PramanaFoundry.Coordinator,
           [herdr_command: herdr_cmd, poll_ms: poll_ms, enable_tick: enable_tick]},
          {PramanaFoundry.Improver,
           [
             telemetry_path:
               Path.join(
                 Application.get_env(
                   :pramana_foundry,
                   :runtime_root,
                   "/Users/raymondluong/dev/pramana/foundry/local"
                 ),
                 "state/current/telemetry.jsonl"
               ),
             interval_ms: 300_000
           ]},
          {PramanaFoundry.HardeningPM, [interval_ms: 600_000]}
        ]
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: PramanaFoundry.Supervisor)
  end
end
