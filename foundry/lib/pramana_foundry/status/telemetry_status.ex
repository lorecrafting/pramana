defmodule PramanaFoundry.Status.TelemetryStatus do
  @moduledoc "Deterministic aggregate telemetry projection for CLI and future board consumers."

  alias PramanaFoundry.Telemetry.{Forecast, Store, Telemetry}

  @spec project([map()], map() | nil, keyword()) :: map()
  def project(records, target \\ nil, opts \\ []) do
    records = validated!(records)

    groups =
      records
      |> Enum.group_by(fn record ->
        Enum.map_join(
          ~w(task_id role provider profile model phase outcome),
          "|",
          &(record[&1] || "unknown")
        )
      end)
      |> Map.new(fn {key, values} ->
        {key,
         Store.aggregate(values)
         |> Map.put("token_availability", token_availability(values))
         |> Map.put("context_utilization", metric_values(values, "context_window_utilization"))
         |> Map.put("retries", Enum.sum(Enum.map(values, &(&1["retries"] || 0))))
         |> Map.put("cooldowns", Enum.sum(Enum.map(values, &(&1["cooldowns"] || 0))))}
      end)

    %{
      "schema_version" => 1,
      "groups" => groups,
      "retention" =>
        Keyword.get(opts, :retention, %{"retained" => length(records), "compacted" => 0}),
      "forecast" => if(target, do: Forecast.estimate(records, target, opts), else: nil)
    }
  end

  @spec aggregate([map()], keyword()) :: map()
  def aggregate(records, opts \\ []) do
    records = validated!(records)

    totals = Store.aggregate(records)

    %{
      "schema_version" => 1,
      "tasks" => Enum.frequencies_by(records, &(&1["task_id"] || "unknown")),
      "roles" => Enum.frequencies_by(records, &(&1["role"] || "unknown")),
      "providers" => Enum.frequencies_by(records, &(&1["provider"] || "unknown")),
      "profiles" => Enum.frequencies_by(records, &(&1["profile"] || "unknown")),
      "models" => Enum.frequencies_by(records, &(&1["model"] || "unknown")),
      "phases" => Enum.frequencies_by(records, &(&1["phase"] || "unknown")),
      "outcomes" => Enum.frequencies_by(records, &(&1["outcome"] || "unknown")),
      "token_availability" => token_availability(records),
      "token_sources" => totals["metric_sources"],
      "token_qualities" => totals["metric_qualities"],
      "context_utilization" => metric_values(records, "context_window_utilization"),
      "duration_ms" => totals["duration_ms"],
      "retries" => Enum.sum(Enum.map(records, &(&1["retries"] || 0))),
      "cooldowns" => Enum.sum(Enum.map(records, &(&1["cooldowns"] || 0))),
      "retention" =>
        Keyword.get(opts, :retention, %{"retained" => length(records), "compacted" => 0}),
      "estimates" => Keyword.get(opts, :estimates, %{})
    }
  end

  defp validated!(records) do
    case Telemetry.validate_all(records) do
      {:ok, validated} ->
        validated

      {:error, reason} ->
        raise ArgumentError, "invalid telemetry status input: #{inspect(reason)}"
    end
  end

  defp token_availability(records) do
    records
    |> Enum.flat_map(fn record -> Map.values(record["metrics"] || %{}) end)
    |> Enum.frequencies_by(fn metric ->
      if metric["value"] in [nil, :null], do: "unknown", else: "available"
    end)
  end

  defp metric_values(records, metric) do
    records
    |> Enum.map(&get_in(&1, ["metrics", metric, "value"]))
    |> Enum.reject(&(&1 in [nil, :null]))
  end
end
