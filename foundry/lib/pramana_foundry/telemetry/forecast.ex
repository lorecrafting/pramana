defmodule PramanaFoundry.Telemetry.Forecast do
  @moduledoc "Deterministic confidence-rated duration forecasts from comparable durable observations."

  @comparison_fields ~w(workload risk scope_profile check_profile provider profile model reasoning correction_behavior)

  @spec estimate([map()], map(), keyword()) :: map()
  def estimate(observations, target, opts \\ []) do
    now = Keyword.get(opts, :now, "unknown")
    comparable = Enum.filter(observations, &comparable?(&1, target))
    completed = Enum.filter(comparable, &terminal_duration?/1)
    censored = Enum.count(comparable, &(not terminal_duration?(&1)))
    durations = completed |> Enum.map(& &1["duration_ms"]) |> Enum.sort()

    base = %{
      "sample_size" => length(durations),
      "right_censored" => censored,
      "freshness" => now,
      "assumptions" => Keyword.get(opts, :assumptions, []),
      "parallel_resource_limit" => Keyword.get(opts, :parallel_resource_limit, 1),
      "serial_integration" => Keyword.get(opts, :serial_integration, true),
      "confidence" => confidence(length(durations), censored)
    }

    if length(durations) < 2 do
      Map.merge(base, %{
        "status" => "unavailable",
        "reason" => "fewer than two comparable completed observations"
      })
    else
      p50 = percentile(durations, 0.50)
      p80 = percentile(durations, 0.80)

      Map.merge(base, %{
        "status" => "available",
        "p50_ms" => p50,
        "p80_ms" => p80,
        "range_ms" => [p50, p80],
        "band" => band(p80)
      })
    end
  end

  @spec recalculate([map()], [map()], map(), keyword()) :: [map()]
  def recalculate(history, observations, target, opts \\ []) do
    prediction = %{
      "schema_version" => 1,
      "predicted_at" => Keyword.get(opts, :now, "unknown"),
      "task_id" => target["task_id"],
      "forecast" => estimate(observations, target, opts)
    }

    history ++ [prediction]
  end

  @spec critical_path([map()], map(), keyword()) :: map()
  def critical_path(tickets, observations_by_task, opts \\ []) do
    estimates =
      Map.new(tickets, fn ticket ->
        {ticket["task_id"],
         estimate(Map.get(observations_by_task, ticket["task_id"], []), ticket, opts)}
      end)

    paths = Map.new(tickets, &{&1["task_id"], longest_path(&1, tickets, estimates, %{})})

    {_task_id, longest} =
      Enum.max_by(paths, fn {_id, value} -> value["p80_ms"] end, fn ->
        {nil, unavailable_path()}
      end)

    %{
      "schema_version" => 1,
      "ticket_estimates" => estimates,
      "critical_path" => longest,
      "parallel_resource_limit" => Keyword.get(opts, :parallel_resource_limit, 1),
      "serial_integration" => true
    }
  end

  defp longest_path(ticket, tickets, estimates, seen) do
    task_id = ticket["task_id"]

    if Map.has_key?(seen, task_id) do
      unavailable_path()
    else
      own = Map.get(estimates, task_id, %{})
      dependencies = ticket["dependencies"] || []
      ticket_by_id = Map.new(tickets, &{&1["task_id"], &1})

      dependency_paths =
        for dependency <- dependencies,
            dependency_ticket = ticket_by_id[dependency],
            dependency_ticket != nil,
            do: longest_path(dependency_ticket, tickets, estimates, Map.put(seen, task_id, true))

      prior =
        Enum.max_by(dependency_paths, & &1["p80_ms"], fn ->
          %{"tasks" => [], "p50_ms" => 0, "p80_ms" => 0}
        end)

      %{
        "tasks" => prior["tasks"] ++ [task_id],
        "p50_ms" => prior["p50_ms"] + (own["p50_ms"] || 0),
        "p80_ms" => prior["p80_ms"] + (own["p80_ms"] || 0),
        "available" => own["status"] == "available" and Map.get(prior, "available", true)
      }
    end
  end

  defp unavailable_path, do: %{"tasks" => [], "p50_ms" => 0, "p80_ms" => 0, "available" => false}

  defp comparable?(observation, target) do
    Enum.all?(@comparison_fields, fn field -> observation[field] == target[field] end) and
      observation["outcome"] in ~w(completed blocked parked failed running correcting)
  end

  defp terminal_duration?(observation) do
    observation["outcome"] in ~w(completed blocked parked failed) and
      is_integer(observation["duration_ms"]) and observation["duration_ms"] >= 0
  end

  defp percentile(values, fraction) do
    index = max(ceil(length(values) * fraction) - 1, 0)
    Enum.at(values, index)
  end

  defp confidence(size, _censored) when size < 2, do: "unavailable"
  defp confidence(size, censored) when size < 5 or censored > size, do: "low"
  defp confidence(size, _censored) when size < 10, do: "medium"
  defp confidence(_size, _censored), do: "high"

  defp band(milliseconds) when milliseconds < 60_000, do: "under a minute"
  defp band(milliseconds) when milliseconds < 15 * 60_000, do: "minutes"
  defp band(milliseconds) when milliseconds < 2 * 60 * 60_000, do: "about an hour"
  defp band(_milliseconds), do: "hours"
end
