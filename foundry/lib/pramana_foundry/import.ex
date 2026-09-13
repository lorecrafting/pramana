defmodule PramanaFoundry.Import do
  @moduledoc "Validates imports without dropping rejected bytes or structured evidence."

  alias PramanaFoundry.Schema

  @spec read(Path.t(), atom(), keyword()) :: {:ok, map()} | {:error, map()}
  def read(path, kind, opts \\ []) do
    case Schema.decode_file(path, kind, opts) do
      {:ok, value} -> {:ok, value}
      {:error, error} -> {:error, Map.put(error, :source_path, path)}
    end
  end

  @spec read_jsonl(Path.t(), atom(), keyword()) :: {:ok, [map()]} | {:error, map()}
  def read_jsonl(path, kind, opts \\ []) do
    limit = Keyword.get(opts, :max_bytes, Schema.max_bytes())

    with {:ok, stat} <- File.stat(path),
         :ok <- within_limit(stat.size, limit),
         {:ok, bytes} <- File.read(path),
         :ok <- within_limit(byte_size(bytes), limit),
         :ok <- valid_utf8(bytes) do
      bytes
      |> String.split("\n", trim: true)
      |> Enum.with_index(1)
      |> Enum.reduce_while({:ok, []}, fn {line, line_number}, {:ok, records} ->
        case decode_line(line, kind, opts) do
          {:ok, record} -> {:cont, {:ok, [record | records]}}
          {:error, error} -> {:halt, {:error, Map.put(error, :line, line_number)}}
        end
      end)
      |> case do
        {:ok, records} -> {:ok, Enum.reverse(records)}
        {:error, error} -> {:error, Map.put(error, :source_path, path)}
      end
    else
      {:error, reason} -> error(path, reason)
    end
  end

  defp decode_line(line, kind, opts) do
    try do
      Schema.validate(kind, :json.decode(line), opts)
    rescue
      _ -> {:error, %{reason: :malformed_json, evidence: line}}
    catch
      _, _ -> {:error, %{reason: :malformed_json, evidence: line}}
    end
  end

  defp within_limit(size, limit) when size <= limit, do: :ok
  defp within_limit(_size, _limit), do: {:error, :oversized}

  defp valid_utf8(bytes) do
    if String.valid?(bytes), do: :ok, else: {:error, :invalid_utf8}
  end

  defp error(path, reason), do: {:error, %{reason: reason, evidence: path, source_path: path}}
end
