defmodule PramanaFoundry.Exports.TelemetryExport do
  @moduledoc "Deterministic sanitized JSONL and RFC 4180-compatible CSV telemetry exports."

  alias PramanaFoundry.Telemetry.Telemetry

  @base_columns ~w(schema_version record_id record_digest record_type task_id run_id role provider profile model reasoning phase started_at ended_at duration_ms outcome retries cooldowns exit_code resource_class command_id command)
  @metrics ~w(prompt_input_tokens cached_input_tokens output_tokens reasoning_tokens context_window_utilization)
  @columns @base_columns ++
             for(
               metric <- @metrics,
               property <- ~w(value source quality),
               do: "#{metric}.#{property}"
             )

  @spec jsonl([map()]) :: binary()
  def jsonl(records) do
    records
    |> validated!()
    |> Enum.map(&IO.iodata_to_binary([:json.encode(&1), "\n"]))
    |> IO.iodata_to_binary()
  end

  @spec csv([map()]) :: binary()
  def csv(records) do
    rows = [@columns | Enum.map(validated!(records), &csv_row/1)]

    rows
    |> Enum.map_join("\r\n", &Enum.map_join(&1, ",", fn value -> csv_quote(value) end))
    |> Kernel.<>("\r\n")
  end

  defp csv_row(record), do: Enum.map(@columns, &export_value(record, &1))

  defp export_value(record, column) do
    value =
      case String.split(column, ".", parts: 2) do
        [metric, property] -> get_in(record, ["metrics", metric, property])
        [_base] -> Map.get(record, column)
      end

    case value do
      nil -> "unknown"
      :null -> "unknown"
      item when is_list(item) or is_map(item) -> IO.iodata_to_binary(:json.encode(item))
      item -> to_string(item)
    end
  end

  defp validated!(records) do
    case Telemetry.validate_all(records) do
      {:ok, validated} -> validated
      {:error, reason} -> raise ArgumentError, "invalid telemetry export: #{inspect(reason)}"
    end
  end

  defp csv_quote(value) do
    escaped = String.replace(to_string(value), "\"", "\"\"")
    if String.contains?(escaped, [",", "\"", "\r", "\n"]), do: "\"#{escaped}\"", else: escaped
  end
end
