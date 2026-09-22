defmodule PramanaFoundry.SystemMetrics do
  @moduledoc """
  Captures system-level and per-process metrics as structured snapshots.

  Every GenServer in the workflow system emits these periodically so the
  Improver, dashboard, and CLI have raw primitives for diagnosis across
  all dimensions: memory, CPU, mailbox depth, ETS sizes, atom usage, etc.
  """

  @known_processes [
    PramanaFoundry.Coordinator,
    PramanaFoundry.Improver,
    PramanaFoundry.HardeningPM,
    PramanaFoundry.AssignmentSupervisor
  ]

  @doc false
  def unwrap_count(value) when is_integer(value), do: value
  def unwrap_count({count, _limit}), do: count
  def unwrap_count(value), do: value

  @doc """
  Returns a map of system-level metrics: VM stats that apply to the whole node.
  """
  def system do
    mem = :erlang.memory()
    wall_clock = :erlang.statistics(:wall_clock)
    run_queue = :erlang.statistics(:run_queue)

    %{
      "total_memory_bytes" => Keyword.get(mem, :total, 0),
      "processes_memory_bytes" => Keyword.get(mem, :processes, 0),
      "ets_memory_bytes" => Keyword.get(mem, :ets, 0),
      "atom_memory_bytes" => Keyword.get(mem, :atom, 0),
      "code_memory_bytes" => Keyword.get(mem, :code, 0),
      "binary_memory_bytes" => Keyword.get(mem, :binary, 0),
      "atom_count" => unwrap_count(:erlang.system_info(:atom_count)),
      "atom_limit" => unwrap_count(:erlang.system_info(:atom_limit)),
      "process_count" => unwrap_count(:erlang.system_info(:process_count)),
      "process_limit" => unwrap_count(:erlang.system_info(:process_limit)),
      "run_queue_length" => if(is_list(run_queue), do: hd(run_queue), else: run_queue),
      "uptime_seconds" => elem(wall_clock, 0) |> div(1000),
      # `:ets_data` is not a system info item, so this raised on every call and took the
      # Improver's whole cycle with it. It was also malformed twice over: had the item
      # existed, `length(elem(_, 0))` is not a table count. `:ets_count` returns it directly
      # and goes through `unwrap_count/1` like every other system_info read above.
      "ets_table_count" => unwrap_count(:erlang.system_info(:ets_count))
    }
  end

  @doc """
  Returns per-process metrics for all known workflow GenServers.

  Each entry contains memory, mailbox depth, reductions (CPU proxy),
  and heap size for the process identified by its named registration.
  """
  def per_process do
    @known_processes
    |> Enum.map(fn name -> {name, metricize(name)} end)
    |> Enum.filter(fn {_name, metrics} -> metrics != nil end)
    |> Map.new()
  end

  @doc """
  Returns metrics for a single named process.
  """
  def metricize(name) do
    case Process.whereis(name) do
      nil ->
        nil

      pid ->
        info =
          Process.info(pid, [
            :memory,
            :message_queue_len,
            :reductions,
            :heap_size,
            :total_heap_size
          ])

        %{
          "pid" => inspect(pid),
          "memory_bytes" => Keyword.get(info, :memory, 0),
          "mailbox_depth" => Keyword.get(info, :message_queue_len, 0),
          "reductions" => Keyword.get(info, :reductions, 0),
          "heap_size_words" => Keyword.get(info, :heap_size, 0),
          "total_heap_size_words" => Keyword.get(info, :total_heap_size, 0)
        }
    end
  end

  @doc """
  Returns AgentServer child metrics from the AssignmentSupervisor.
  """
  def agent_servers do
    sup = Process.whereis(PramanaFoundry.AssignmentSupervisor)

    case sup do
      nil ->
        %{"count" => 0, "agents" => []}

      pid ->
        children = DynamicSupervisor.which_children(pid)

        agents =
          children
          |> Enum.map(fn {_id, child_pid, _type, _mod} ->
            info = Process.info(child_pid, [:memory, :message_queue_len, :reductions])

            %{
              "pid" => inspect(child_pid),
              "memory_bytes" => Keyword.get(info, :memory, 0),
              "mailbox_depth" => Keyword.get(info, :message_queue_len, 0),
              "reductions" => Keyword.get(info, :reductions, 0)
            }
          end)

        %{"count" => length(agents), "agents" => agents}
    end
  end

  @doc """
  Builds a full metrics snapshot suitable for Telemetry and LogStore.
  """
  def snapshot do
    %{
      "event" => "metrics_snapshot",
      "source" => "system_metrics",
      "at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "system" => system(),
      "per_process" => per_process(),
      "agent_servers" => agent_servers()
    }
  end
end
