defmodule PramanaFoundry.Board.Inspection do
  @moduledoc """
  Local sanitized BEAM inspection exposing formatted status and documented attach
  instructions without opening public distribution ports, binding insecure listeners,
  or exposing environment secrets or credentials.
  """

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Status.Report

  @security_guarantees [
    "Strictly local: bound to 127.0.0.1 loopback only; no public distribution ports (EPMD or inet_dist) bound to 0.0.0.0.",
    "No insecure network listeners opened.",
    "No environment secrets, API keys, or credentials exposed."
  ]

  @doc """
  Returns a sanitized status map of the local BEAM node and coordinator.
  """
  @spec status(keyword()) :: map()
  def status(opts \\ []) do
    coordinator = Keyword.get(opts, :coordinator, Coordinator)
    coordinator_alive? = Process.whereis(coordinator) != nil

    coord_info =
      if coordinator_alive? do
        try do
          state = coordinator.state()
          status = coordinator.status()
          accepted = Map.get(state, "accepted_revision")
          runtime = Report.runtime_implementation_revision()
          assignments = Map.get(state, "assignments", %{})

          active_workers =
            assignments
            |> Map.values()
            |> Enum.count(fn a ->
              Map.get(a, "status") in ~w(dispatched prompting working queued_correction)
            end)

          %{
            "alive?" => true,
            "paused" => Map.get(state, "paused", false),
            "stop_requested" => Map.get(state, "stop_requested", false),
            "accepted_revision" => accepted,
            "runtime_implementation_revision" => runtime,
            "revisions_match?" => accepted == runtime,
            "active_workers_count" => active_workers,
            "queue_length" => length(Map.get(state, "queue", [])),
            "status_report" => status
          }
        rescue
          _ ->
            %{
              "alive?" => true,
              "error" => "coordinator temporarily unresponsive"
            }
        end
      else
        %{
          "alive?" => false,
          "error" => "coordinator process not registered"
        }
      end

    mem = :erlang.memory()

    %{
      "node" => to_string(Node.self()),
      "otp_release" => System.otp_release(),
      "elixir_version" => System.version(),
      "process_count" => length(Process.list()),
      "process_limit" => :erlang.system_info(:process_limit),
      "uptime_seconds" => :erlang.element(1, :erlang.statistics(:wall_clock)) |> div(1000),
      "memory" => %{
        "total_bytes" => Keyword.get(mem, :total, 0),
        "processes_bytes" => Keyword.get(mem, :processes, 0),
        "atom_bytes" => Keyword.get(mem, :atom, 0),
        "binary_bytes" => Keyword.get(mem, :binary, 0),
        "ets_bytes" => Keyword.get(mem, :ets, 0)
      },
      "coordinator" => coord_info,
      "sanitized" => true
    }
  end

  @doc """
  Returns documented attach instructions for local-only BEAM connection.
  """
  @spec attach_instructions(keyword()) :: map()
  def attach_instructions(opts \\ []) do
    node_name = Keyword.get(opts, :node_name, Node.self())

    remsh_cmd =
      if node_name == :nonode@nohost do
        "iex --name attach_#{unique_id()}@127.0.0.1 --remsh <target_node_name>"
      else
        "iex --name attach_#{unique_id()}@127.0.0.1 --remsh #{node_name}"
      end

    %{
      "local_remsh" => remsh_cmd,
      "local_socket" =>
        "Attach via local UNIX domain socket or attached console pane: no network listeners or public ports.",
      "security_guarantees" => @security_guarantees,
      "notes" =>
        "Distribution must be bound to 127.0.0.1 loopback only. Never expose EPMD or distribution ports to public interfaces."
    }
  end

  @doc """
  Formats system status and attach instructions as human-readable text.
  """
  @spec format(keyword()) :: String.t()
  def format(opts \\ []) do
    st = status(opts)
    inst = attach_instructions(opts)
    mem = st["memory"]
    coord = st["coordinator"]

    total_mb = Float.round(mem["total_bytes"] / (1024 * 1024), 1)
    proc_mb = Float.round(mem["processes_bytes"] / (1024 * 1024), 1)
    bin_mb = Float.round(mem["binary_bytes"] / (1024 * 1024), 1)
    ets_mb = Float.round(mem["ets_bytes"] / (1024 * 1024), 1)

    coord_summary =
      if coord["alive?"] do
        match_str =
          if coord["revisions_match?"] do
            "yes (in sync)"
          else
            "NO (MISMATCH: runtime #{coord["runtime_implementation_revision"]} != accepted #{coord["accepted_revision"]})"
          end

        """
        Coordinator:     alive (workers: #{coord["active_workers_count"]}, queue: #{coord["queue_length"]})
        Accepted Rev:    #{coord["accepted_revision"] || "-"}
        Runtime Rev:     #{coord["runtime_implementation_revision"] || "-"}
        Revisions Match: #{match_str}
        """
      else
        "Coordinator:     NOT RUNNING (#{coord["error"]})\n"
      end

    """
    === PramanaFoundry BEAM System Status ===
    Node:            #{st["node"]}
    OTP Release:     #{st["otp_release"]}
    Elixir Version:  #{st["elixir_version"]}
    Uptime:          #{st["uptime_seconds"]}s
    Processes:       #{st["process_count"]} / #{st["process_limit"]}
    Memory Total:    #{total_mb} MB (proc: #{proc_mb} MB, bin: #{bin_mb} MB, ets: #{ets_mb} MB)
    #{String.trim_trailing(coord_summary)}

    === Local Attach Instructions ===
    1. Local IEx Remsh (local loopback only, never public interface):
       #{inst["local_remsh"]}
    2. Local Socket Attach:
       #{inst["local_socket"]}

    === Security Guarantees ===
    - #{Enum.join(@security_guarantees, "\n- ")}
    """
  end

  @doc """
  Alias for format/1.
  """
  def formatted_status(opts \\ []), do: format(opts)

  defp unique_id do
    System.unique_integer([:positive])
  end
end
