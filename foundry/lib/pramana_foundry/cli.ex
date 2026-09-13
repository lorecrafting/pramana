defmodule PramanaFoundry.CLI do
  @moduledoc "Local command shell for validation and effect-free shadow inspection."

  alias PramanaFoundry.{Import, Parity}
  alias PramanaFoundry.Exports.TelemetryExport
  alias PramanaFoundry.Projections.{Benchmark, Projection}
  alias PramanaFoundry.Status.TelemetryStatus
  alias PramanaFoundry.Telemetry.Store

  def main(["validate", kind, path]) do
    case validate(kind, path) do
      {:ok, value} -> IO.puts(:json.format(value))
      {:error, error} -> abort(error)
    end
  end

  def main(["shadow", path]) do
    with {:ok, bytes} <- File.read(path),
         {:ok, result} <- Parity.shadow(bytes) do
      IO.puts(:json.format(result))
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["runtime-root"]),
    do: IO.puts(Application.fetch_env!(:pramana_foundry, :runtime_root))

  def main(["project-assignment", path]) do
    with {:ok, canonical} <- Import.read(path, :assignment),
         {:ok, projection} <- Projection.assignment(canonical) do
      IO.puts(:json.format(projection))
    else
      {:error, reason} -> abort(reason)
    end
  end

  def main(["telemetry-status", path]) do
    with {:ok, records} <- Store.read(path) do
      IO.puts(:json.format(TelemetryStatus.aggregate(records)))
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["telemetry-export", format, input, output]) when format in ["jsonl", "csv"] do
    with {:ok, records} <- Store.read(input),
         contents <-
           if(format == "jsonl",
             do: TelemetryExport.jsonl(records),
             else: TelemetryExport.csv(records)
           ),
         :ok <- File.write(output, contents) do
      :ok
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["benchmark-projections", input, output]) do
    with {:ok, bytes} <- File.read(input),
         cases <- :json.decode(bytes),
         result <- Benchmark.run(cases),
         :ok <- File.write(output, IO.iodata_to_binary([:json.encode(result), "\n"])) do
      :ok
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["board" | _args]) do
    # Board needs OWL for LiveScreen, but NOT the full supervision tree
    # (coordinator, improver, etc.) since those run in the daemon.
    # Start only OWL and the board process.
    :ok = PramanaFoundry.Board.ensure_owl_started()

    # Use event-log fallback coordinator module (not a full GenServer)
    PramanaFoundry.Board.run(coordinator: :event_log)
  end

  def main(["health"]) do
    case PramanaFoundry.Coordinator.health() do
      %{} = report ->
        IO.puts(:json.format(report))
      _ ->
        IO.puts(:stderr, "coordinator not available")
    end
  end

  def main(["agents"]) do
    agents = PramanaFoundry.SystemMetrics.agent_servers()
    IO.puts("Active agents: #{agents["count"]}")

    Enum.each(agents["agents"], fn agent ->
      IO.puts("  PID: #{agent["pid"]}  Memory: #{div(agent["memory_bytes"], 1024)}KB  Mailbox: #{agent["mailbox_depth"]}  Reductions: #{agent["reductions"]}")
    end)
  end

  def main(["metrics"]) do
    system = PramanaFoundry.SystemMetrics.system()
    per_proc = PramanaFoundry.SystemMetrics.per_process()

    IO.puts("=== System ===")
    IO.puts("Memory: #{div(system["total_memory_bytes"], 1_048_576)}MB total / #{div(system["processes_memory_bytes"], 1_048_576)}MB processes")
    IO.puts("Processes: #{system["process_count"]}/#{system["process_limit"]}  Atoms: #{system["atom_count"]}/#{system["atom_limit"]}")
    IO.puts("Run queue: #{system["run_queue_length"]}  ETS tables: #{system["ets_table_count"]}")
    IO.puts("Uptime: #{div(system["uptime_seconds"], 86_400)}d #{div(rem(system["uptime_seconds"], 86_400), 3600)}h")

    IO.puts("\n=== Per-Process ===")
    Enum.each(per_proc, fn {name, metrics} ->
      IO.puts("  #{inspect(name)}: #{div(metrics["memory_bytes"], 1024)}KB  Mailbox: #{metrics["mailbox_depth"]}  Reductions: #{metrics["reductions"]}")
    end)
  end

  def main(["logs", "tail", count]) do
    n = String.to_integer(count)
    PramanaFoundry.ConsolidatedLog.tail(n)
    |> Enum.each(fn r ->
      at = Map.get(r, "at", "?") |> String.slice(0, 19)
      source = Map.get(r, "source", "?")
      event = Map.get(r, "event", Map.get(r, "phase", "?"))
      task = Map.get(r, "task_id", "-") |> String.slice(0, 12)
      IO.puts("#{at} [#{source}] #{event} #{task}")
    end)
  end

  def main(["logs", "summary"]) do
    IO.puts(:json.format(PramanaFoundry.ConsolidatedLog.summary()))
  end

  def main(["logs" | _args]) do
    PramanaFoundry.ConsolidatedLog.tail(20)
    |> Enum.each(fn r ->
      at = Map.get(r, "at", "?") |> String.slice(0, 19)
      source = Map.get(r, "source", "?")
      event = Map.get(r, "event", Map.get(r, "phase", "?"))
      task = Map.get(r, "task_id", "-") |> String.slice(0, 12)
      IO.puts("#{at} [#{source}] #{event} #{task}")
    end)
  end

  def main(_args) do
    IO.puts(
      :stderr,
      "usage: pramana_foundry validate KIND PATH | shadow PATH | runtime-root | project-assignment PATH | telemetry-status PATH | telemetry-export jsonl|csv INPUT OUTPUT | benchmark-projections INPUT OUTPUT | board | health | agents | metrics | logs [tail N|summary]"
    )

    System.halt(64)
  end

  @spec validate(binary(), Path.t()) :: {:ok, map()} | {:error, map()}
  def validate(kind, path) when is_binary(kind) and is_binary(path) do
    Import.read(path, String.to_existing_atom(kind))
  rescue
    ArgumentError -> {:error, %{reason: :unsupported_schema}}
  end

  defp abort(error) do
    IO.puts(:stderr, :json.format(error))
    System.halt(1)
  end
end
