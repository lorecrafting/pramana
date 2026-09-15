defmodule PramanaFoundry.ConsolidatedLog do
  @moduledoc """
  Reads the last N records from all three structured logs (coordinator, telemetry, events)
  and returns them merged with a `source` tag for unified display.
  """

  @default_count 50

  @doc """
  Returns the last `count` records from all logs, merged with source tags.
  Each record has `source` set to `"coord"`, `"telemetry"`, or `"events"`.
  """
  def tail(count \\ @default_count) do
    root = PramanaFoundry.RuntimeRoot.fetch!()
    dir = Path.join(root, "state/current")

    sources = [
      {"coord", Path.join(dir, "coordinator.jsonl")},
      {"telemetry", Path.join(dir, "telemetry.jsonl")},
      {"events", Path.join(dir, "events.jsonl")}
    ]

    sources
    |> Enum.flat_map(fn {tag, path} -> read_tagged(tag, path, count) end)
    |> Enum.sort_by(& &1["at"], :desc)
    |> Enum.take(count)
  end

  @doc """
  Returns a summary of record counts per source.
  """
  def summary do
    root = PramanaFoundry.RuntimeRoot.fetch!()
    dir = Path.join(root, "state/current")

    %{
      "coordinator" => count_lines(Path.join(dir, "coordinator.jsonl")),
      "telemetry" => count_lines(Path.join(dir, "telemetry.jsonl")),
      "events" => count_lines(Path.join(dir, "events.jsonl")),
      "findings" => count_lines(Path.join(dir, "findings.jsonl"))
    }
  end

  defp read_tagged(tag, path, count) do
    case read_file(path) do
      {:ok, records} ->
        records
        |> Enum.reverse()
        |> Enum.take(count)
        |> Enum.map(fn r -> Map.put(r, "source", tag) end)

      _ ->
        []
    end
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, bytes} ->
        lines = String.split(bytes, "\n", trim: true)
        records = Enum.map(lines, &:json.decode/1)
        {:ok, records}

      {:error, :enoent} ->
        {:ok, []}

      error ->
        error
    end
  end

  defp count_lines(path) do
    case File.read(path) do
      {:ok, bytes} -> max(0, String.split(bytes, "\n", trim: true) |> length())
      _ -> 0
    end
  end
end
