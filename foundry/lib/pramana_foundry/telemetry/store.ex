defmodule PramanaFoundry.Telemetry.Store do
  @moduledoc "Append-safe, idempotent local telemetry storage and bounded compaction."

  alias PramanaFoundry.{AtomicFile}
  alias PramanaFoundry.Telemetry.Telemetry

  @max_file_bytes 8 * 1024 * 1024
  @max_line_bytes 256 * 1024
  @max_records 50_000
  @spec append(Path.t(), map()) :: :ok | :duplicate | {:error, term()}
  def append(path, %{"record_id" => record_id} = record) when is_binary(record_id) do
    with {:ok, validated} <- Telemetry.validate(record),
         :ok <- File.mkdir_p(Path.dirname(path)),
         {:ok, known} <- known_ids(path) do
      record_digest = validated["record_digest"]

      case Map.fetch(known, record_id) do
        {:ok, ^record_digest} ->
          :duplicate

        {:ok, _existing_digest} ->
          encode_and_append(path, validated)

        :error ->
          encode_and_append(path, validated)
      end
    end
  end

  def append(_path, _record), do: {:error, :missing_record_id}

  defp encode_and_append(path, validated) do
    encoded = IO.iodata_to_binary([:json.encode(validated), "\n"])

    with :ok <- bounded_line(encoded),
         :ok <- bounded_append(path, byte_size(encoded)),
         {:ok, file} <- :file.open(String.to_charlist(path), [:append, :binary, :raw]),
         :ok <- :file.write(file, encoded),
         :ok <- :file.sync(file),
         :ok <- :file.close(file) do
      :ok
    end
  end

  @spec read(Path.t()) :: {:ok, [map()]} | {:error, term()}
  def read(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_bytes ->
        {:error, :oversized_telemetry_file}

      {:ok, _stat} ->
        with {:ok, bytes} <- File.read(path),
             true <- String.valid?(bytes),
             {:ok, records} <- decode_lines(bytes),
             {:ok, validated} <- Telemetry.validate_all(records) do
          {:ok, validated}
        else
          false -> {:error, :invalid_utf8}
          error -> error
        end

      {:error, :enoent} ->
        {:ok, []}

      error ->
        error
    end
  end

  @spec compact(Path.t(), Path.t(), binary(), keyword()) :: :ok | {:error, term()}
  def compact(log_path, output_path, cutoff, opts \\ []) when is_binary(cutoff) do
    with {:ok, records} <- read(log_path),
         {:ok, previous} <- read_compaction(output_path, cutoff) do
      unique = records |> Enum.reverse() |> Enum.uniq_by(& &1["record_id"]) |> Enum.reverse()
      {eligible, retained} = Enum.split_with(unique, &older_than?(&1, cutoff))
      existing_ids = MapSet.new(previous["compacted"]["record_ids"])
      newly_compacted = Enum.reject(eligible, &MapSet.member?(existing_ids, &1["record_id"]))
      new_ids = MapSet.new(newly_compacted, & &1["record_id"])
      new_input_records = Enum.count(records, &MapSet.member?(new_ids, &1["record_id"]))
      compacted = merge_aggregates(previous["compacted"], aggregate(newly_compacted))

      artifact = %{
        "schema_version" => 1,
        "cutoff" => cutoff,
        "compacted" => compacted,
        "retained" => retained,
        "deduplication" => %{
          "input_records" => previous["deduplication"]["input_records"] + new_input_records,
          "unique_records" => compacted["records"],
          "duplicate_records" =>
            previous["deduplication"]["duplicate_records"] +
              max(new_input_records - length(newly_compacted), 0)
        }
      }

      with :ok <- AtomicFile.write(output_path, artifact, opts),
           :ok <- inject(opts, :after_summary),
           :ok <- rewrite_log(log_path, retained, opts) do
        :ok
      end
    end
  end

  @spec aggregate([map()]) :: map()
  def aggregate(records) do
    %{
      "records" => length(records),
      "outcomes" => counts(records, & &1["outcome"]),
      "phases" => counts(records, & &1["phase"]),
      "roles" => counts(records, & &1["role"]),
      "providers" => counts(records, &provider_key/1),
      "duration_ms" => %{
        "sum" => Enum.sum(Enum.map(records, &(&1["duration_ms"] || 0))),
        "samples" => Enum.map(records, & &1["duration_ms"])
      },
      "metric_sources" => metric_counts(records, "source"),
      "metric_qualities" => metric_counts(records, "quality"),
      "record_ids" => records |> Enum.map(& &1["record_id"]) |> Enum.sort()
    }
  end

  defp read_compaction(path, cutoff) do
    case File.stat(path) do
      {:ok, %{size: size}} when size > @max_file_bytes ->
        {:error, :oversized_compaction_file}

      {:ok, _stat} ->
        with {:ok, bytes} <- File.read(path),
             true <- String.valid?(bytes),
             {:ok, artifact} <- decode_compaction(bytes),
             :ok <- validate_compaction(artifact, cutoff) do
          {:ok, artifact}
        else
          false -> {:error, :invalid_utf8}
          error -> error
        end

      {:error, :enoent} ->
        {:ok, empty_compaction(cutoff)}

      error ->
        error
    end
  end

  defp decode_compaction(bytes) do
    try do
      {:ok, :json.decode(bytes)}
    rescue
      _ -> {:error, :malformed_compaction}
    catch
      _, _ -> {:error, :malformed_compaction}
    end
  end

  defp validate_compaction(artifact, cutoff) when is_map(artifact) do
    exact_fields? =
      Enum.sort(Map.keys(artifact)) ==
        Enum.sort(~w(schema_version cutoff compacted retained deduplication))

    with true <- exact_fields?,
         true <- artifact["schema_version"] == 1,
         true <- artifact["cutoff"] == cutoff,
         true <- valid_aggregate?(artifact["compacted"]),
         {:ok, retained} <- Telemetry.validate_all(artifact["retained"]),
         true <- retained == artifact["retained"],
         true <- valid_deduplication?(artifact["deduplication"]) do
      :ok
    else
      _ -> {:error, :invalid_compaction_artifact}
    end
  end

  defp validate_compaction(_artifact, _cutoff), do: {:error, :invalid_compaction_artifact}

  defp valid_aggregate?(aggregate) when is_map(aggregate) do
    exact_fields? =
      Enum.sort(Map.keys(aggregate)) ==
        Enum.sort(
          ~w(records outcomes phases roles providers duration_ms metric_sources metric_qualities record_ids)
        )

    duration = aggregate["duration_ms"]
    record_ids = aggregate["record_ids"]

    exact_fields? and non_negative_integer?(aggregate["records"]) and
      valid_count_map?(aggregate["outcomes"]) and valid_count_map?(aggregate["phases"]) and
      valid_count_map?(aggregate["roles"]) and valid_count_map?(aggregate["providers"]) and
      valid_count_map?(aggregate["metric_sources"]) and
      valid_count_map?(aggregate["metric_qualities"]) and is_map(duration) and
      Enum.sort(Map.keys(duration)) == ~w(samples sum) and
      non_negative_integer?(duration["sum"]) and is_list(duration["samples"]) and
      Enum.all?(duration["samples"], &non_negative_integer?/1) and
      Enum.sum(duration["samples"]) == duration["sum"] and is_list(record_ids) and
      Enum.all?(record_ids, &(is_binary(&1) and byte_size(&1) > 0)) and
      Enum.uniq(record_ids) == record_ids and length(record_ids) == aggregate["records"]
  end

  defp valid_aggregate?(_aggregate), do: false

  defp valid_deduplication?(deduplication) when is_map(deduplication) do
    Enum.sort(Map.keys(deduplication)) ==
      ~w(duplicate_records input_records unique_records) and
      Enum.all?(Map.values(deduplication), &non_negative_integer?/1) and
      deduplication["unique_records"] <= deduplication["input_records"]
  end

  defp valid_deduplication?(_deduplication), do: false

  defp valid_count_map?(value) when is_map(value) do
    Enum.all?(value, fn {key, count} ->
      is_binary(key) and byte_size(key) > 0 and non_negative_integer?(count)
    end)
  end

  defp valid_count_map?(_value), do: false
  defp non_negative_integer?(value), do: is_integer(value) and value >= 0

  defp empty_compaction(cutoff) do
    %{
      "schema_version" => 1,
      "cutoff" => cutoff,
      "compacted" => aggregate([]),
      "retained" => [],
      "deduplication" => %{
        "input_records" => 0,
        "unique_records" => 0,
        "duplicate_records" => 0
      }
    }
  end

  defp merge_aggregates(previous, current) do
    %{
      "records" => previous["records"] + current["records"],
      "outcomes" => merge_counts(previous["outcomes"], current["outcomes"]),
      "phases" => merge_counts(previous["phases"], current["phases"]),
      "roles" => merge_counts(previous["roles"], current["roles"]),
      "providers" => merge_counts(previous["providers"], current["providers"]),
      "duration_ms" => %{
        "sum" => previous["duration_ms"]["sum"] + current["duration_ms"]["sum"],
        "samples" => previous["duration_ms"]["samples"] ++ current["duration_ms"]["samples"]
      },
      "metric_sources" => merge_counts(previous["metric_sources"], current["metric_sources"]),
      "metric_qualities" =>
        merge_counts(previous["metric_qualities"], current["metric_qualities"]),
      "record_ids" => Enum.sort(Enum.uniq(previous["record_ids"] ++ current["record_ids"]))
    }
  end

  defp merge_counts(previous, current),
    do: Map.merge(previous, current, fn _key, left, right -> left + right end)

  defp known_ids(path) do
    with {:ok, records} <- read(path) do
      {:ok, Map.new(records, &{&1["record_id"], &1["record_digest"]})}
    end
  end

  defp decode_lines(bytes) do
    lines = String.split(bytes, "\n", trim: true)

    cond do
      length(lines) > @max_records ->
        {:error, :too_many_telemetry_records}

      Enum.any?(lines, &(byte_size(&1) > @max_line_bytes)) ->
        {:error, :oversized_telemetry_line}

      true ->
        lines
        |> Enum.reduce_while({:ok, []}, fn line, {:ok, records} ->
          try do
            {:cont, {:ok, [:json.decode(line) | records]}}
          rescue
            _ -> {:halt, {:error, :malformed_jsonl}}
          catch
            _, _ -> {:halt, {:error, :malformed_jsonl}}
          end
        end)
        |> case do
          {:ok, records} -> {:ok, Enum.reverse(records)}
          error -> error
        end
    end
  end

  defp older_than?(record, cutoff) do
    case record["ended_at"] do
      value when is_binary(value) -> value < cutoff
      _ -> false
    end
  end

  defp bounded_line(bytes) when byte_size(bytes) > @max_line_bytes,
    do: {:error, :oversized_telemetry_line}

  defp bounded_line(_bytes), do: :ok

  defp bounded_append(path, appended_bytes) do
    current_bytes =
      case File.stat(path) do
        {:ok, stat} -> stat.size
        {:error, :enoent} -> 0
        {:error, reason} -> {:error, reason}
      end

    case current_bytes do
      {:error, reason} -> {:error, reason}
      size when size + appended_bytes > @max_file_bytes -> {:error, :oversized_telemetry_file}
      _size -> :ok
    end
  end

  defp rewrite_log(path, records, opts) do
    temp = path <> "." <> Keyword.get(opts, :txid, "compact") <> ".tmp"
    bytes = records |> Enum.map(&[:json.encode(&1), "\n"]) |> IO.iodata_to_binary()

    with {:ok, file} <- :file.open(String.to_charlist(temp), [:write, :binary, :raw]),
         :ok <- :file.write(file, bytes),
         :ok <- :file.sync(file),
         :ok <- :file.close(file),
         :ok <- inject(opts, :before_log_replace),
         :ok <- File.rename(temp, path),
         :ok <- sync_directory(Path.dirname(path)) do
      :ok
    end
  end

  defp sync_directory(path) do
    with {:ok, directory} <- :file.open(String.to_charlist(path), [:read, :raw, :directory]),
         :ok <- :file.sync(directory),
         :ok <- :file.close(directory) do
      :ok
    end
  end

  defp inject(opts, point) do
    if Keyword.get(opts, :crash_at) == point, do: {:error, {:injected_crash, point}}, else: :ok
  end

  defp counts(records, key_fun) do
    records
    |> Enum.map(key_fun)
    |> Enum.reject(&is_nil/1)
    |> Enum.frequencies()
  end

  defp provider_key(record) do
    case {record["provider"], record["profile"], record["model"]} do
      {nil, nil, nil} -> nil
      tuple -> tuple |> Tuple.to_list() |> Enum.map_join("/", &to_string/1)
    end
  end

  defp metric_counts(records, field) do
    records
    |> Enum.flat_map(fn record ->
      for {metric, values} <- record["metrics"] || %{},
          is_map(values),
          do: "#{metric}:#{values[field]}"
    end)
    |> Enum.frequencies()
  end
end
