defmodule PramanaFoundry.LogStore do
  @moduledoc """
  Lightweight append-only JSONL store for structured logging.
  No validation, no dedup — just fast fsynced writes for coordinator lifecycle events.
  """

  def append(path, record) when is_map(record) do
    enriched = Map.put(record, "at", DateTime.utc_now() |> DateTime.to_iso8601())
    encoded = :json.encode(enriched)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, file} <- :file.open(String.to_charlist(path), [:append, :binary, :raw]),
         :ok <- :file.write(file, [encoded, "\n"]),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  def append(_path, _record), do: {:error, :invalid_record}

  @spec read(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def read(path) do
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
end