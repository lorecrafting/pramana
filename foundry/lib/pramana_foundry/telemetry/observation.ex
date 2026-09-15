defmodule PramanaFoundry.Telemetry.Observation do
  @moduledoc "Derives deterministic duration observations from durable planning transitions."

  @terminal_events %{
    "phase_completed" => "completed",
    "phase_blocked" => "blocked",
    "phase_parked" => "parked",
    "phase_failed" => "failed"
  }

  @identity_fields ~w(task_id run_id phase)
  @population_fields ~w(role workload risk scope_profile check_profile provider profile model reasoning)

  @spec from_events([map()]) :: {:ok, [map()]} | {:error, term()}
  def from_events(events) when is_list(events) do
    with {:ok, normalized} <- normalize(events) do
      starts =
        normalized
        |> Enum.filter(&(&1["event"] == "phase_started"))
        |> Enum.group_by(&identity/1)

      terminals =
        normalized
        |> Enum.filter(&Map.has_key?(@terminal_events, &1["event"]))
        |> Enum.group_by(&identity/1)

      observations =
        starts
        |> Enum.sort_by(fn {identity, _events} -> identity end)
        |> Enum.map(fn {identity, start_events} ->
          started = Enum.min_by(start_events, &timestamp/1)

          ended =
            terminals
            |> Map.get(identity, [])
            |> Enum.filter(&(DateTime.compare(&1["_at"], started["_at"]) in [:eq, :gt]))
            |> Enum.min_by(&timestamp/1, fn -> nil end)

          observation(started, ended)
        end)

      {:ok, observations}
    end
  end

  def from_events(_events), do: {:error, :not_a_list}

  defp normalize(events) do
    events
    |> Enum.reduce_while({:ok, []}, fn event, {:ok, accepted} ->
      with true <- is_map(event),
           true <- Enum.all?(@identity_fields ++ ["event", "at"], &non_empty?(event[&1])),
           {:ok, at, _offset} <- DateTime.from_iso8601(event["at"]) do
        {:cont, {:ok, [Map.put(event, "_at", at) | accepted]}}
      else
        _ -> {:halt, {:error, {:invalid_transition, event}}}
      end
    end)
    |> case do
      {:ok, accepted} -> {:ok, Enum.reverse(accepted)}
      error -> error
    end
  end

  defp observation(started, nil) do
    started
    |> Map.take(@identity_fields ++ @population_fields)
    |> Map.merge(%{
      "started_at" => started["at"],
      "ended_at" => nil,
      "duration_ms" => nil,
      "outcome" => "running",
      "right_censored" => true
    })
  end

  defp observation(started, ended) do
    started
    |> Map.take(@identity_fields ++ @population_fields)
    |> Map.merge(%{
      "started_at" => started["at"],
      "ended_at" => ended["at"],
      "duration_ms" => DateTime.diff(ended["_at"], started["_at"], :millisecond),
      "outcome" => @terminal_events[ended["event"]],
      "right_censored" => false
    })
  end

  defp identity(event), do: Enum.map(@identity_fields, &event[&1])
  defp timestamp(event), do: DateTime.to_unix(event["_at"], :microsecond)
  defp non_empty?(value), do: is_binary(value) and value != ""
end
