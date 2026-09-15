defmodule PramanaFoundry.Telemetry.Telemetry do
  @moduledoc """
  Pure construction of allowlisted local workflow telemetry.

  Missing provider metrics remain explicit JSON `null` values with `unavailable` source and
  quality classifications. Prompt/response bodies, environment values, transcripts, and
  unknown provider payload fields are never copied into a durable record.
  """

  @metric_fields ~w(prompt_input_tokens cached_input_tokens output_tokens reasoning_tokens context_window_utilization)
  @common_fields ~w(task_id run_id role phase provider profile model reasoning started_at ended_at duration_ms retries cooldowns outcome workload risk scope_profile check_profile)
  @llm_fields @common_fields ++ ["provider_metrics"]
  @command_fields ~w(task_id run_id phase started_at ended_at duration_ms exit_code resource_class command)
  @secret_flags ~w(--api-key --token --password --secret -p)

  @spec llm(map()) :: {:ok, map()} | {:error, term()}
  def llm(attrs) when is_map(attrs) do
    with :ok <-
           require_fields(
             attrs,
             ~w(task_id run_id role phase provider profile model reasoning started_at ended_at duration_ms outcome)
           ),
         :ok <- reject_sensitive_fields(attrs),
         :ok <- reject_unknown_fields(attrs, @llm_fields),
         :ok <-
           validate_strings(
             attrs,
             ~w(task_id run_id role phase provider profile model reasoning started_at ended_at outcome),
             ~w(workload risk scope_profile check_profile)
           ),
         :ok <- validate_duration(attrs["duration_ms"]),
         :ok <- validate_clock(attrs),
         :ok <- validate_counts(attrs),
         {:ok, metrics} <- metrics(attrs["provider_metrics"] || %{}) do
      base =
        attrs
        |> Map.take(@common_fields)
        |> Map.merge(%{
          "schema_version" => 1,
          "record_type" => "llm_phase",
          "metrics" => metrics
        })

      {:ok, identify(base)}
    end
  end

  def llm(_attrs), do: {:error, :not_an_object}

  @spec command(map()) :: {:ok, map()} | {:error, term()}
  def command(attrs) when is_map(attrs) do
    with :ok <-
           require_fields(
             attrs,
             ~w(task_id run_id phase started_at ended_at duration_ms exit_code resource_class command)
           ),
         :ok <- reject_sensitive_fields(attrs),
         :ok <- reject_unknown_fields(attrs, @command_fields),
         :ok <-
           validate_strings(
             attrs,
             ~w(task_id run_id phase started_at ended_at resource_class),
             []
           ),
         :ok <- validate_duration(attrs["duration_ms"]),
         :ok <- validate_clock(attrs),
         true <- is_integer(attrs["exit_code"]),
         true <- valid_argv?(attrs["command"]) do
      argv = sanitize_argv(attrs["command"])

      base = %{
        "schema_version" => 1,
        "record_type" => "command",
        "task_id" => attrs["task_id"],
        "run_id" => attrs["run_id"],
        "phase" => attrs["phase"],
        "started_at" => attrs["started_at"],
        "ended_at" => attrs["ended_at"],
        "duration_ms" => attrs["duration_ms"],
        "exit_code" => attrs["exit_code"],
        "resource_class" => attrs["resource_class"],
        "command" => argv,
        "command_id" => digest(argv)
      }

      {:ok, identify(base)}
    else
      false -> {:error, :invalid_command_record}
      error -> error
    end
  end

  def command(_attrs), do: {:error, :not_an_object}

  @spec validate(map()) :: {:ok, map()} | {:error, term()}
  def validate(%{"record_type" => "llm_phase"} = record) do
    canonical = normalize_null_metrics(record)

    attrs =
      canonical
      |> Map.drop(~w(schema_version record_type record_id record_digest metrics))
      |> Map.put("provider_metrics", canonical["metrics"])

    with {:ok, validated} <- llm(attrs),
         true <- validated == canonical do
      {:ok, validated}
    else
      false -> {:error, :record_digest_mismatch}
      error -> error
    end
  end

  def validate(%{"record_type" => "command"} = record) do
    attrs = Map.drop(record, ~w(schema_version record_type record_id record_digest command_id))

    with {:ok, validated} <- command(attrs) do
      {:ok, validated}
    end
  end

  def validate(%{"record_type" => _unknown}), do: {:error, :unsupported_record_type}
  def validate(_record), do: {:error, :invalid_telemetry_record}

  @spec validate_all([map()]) :: {:ok, [map()]} | {:error, term()}
  def validate_all(records) when is_list(records) do
    Enum.reduce_while(records, {:ok, []}, fn record, {:ok, validated} ->
      case validate(record) do
        {:ok, value} -> {:cont, {:ok, [value | validated]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, validated} -> {:ok, Enum.reverse(validated)}
      error -> error
    end
  end

  def validate_all(_records), do: {:error, :invalid_telemetry_records}

  @doc "Runs the action once; instrumentation cannot alter or delay success, exception, throw, or exit."
  @spec observe((-> result), (term() -> term())) :: result when result: var
  def observe(action, emit) when is_function(action, 0) and is_function(emit, 1) do
    try do
      result = action.()
      async_emit(emit, result)
      result
    rescue
      exception ->
        stacktrace = __STACKTRACE__
        async_emit(emit, %{"outcome" => "exception", "class" => inspect(exception.__struct__)})
        reraise exception, stacktrace
    catch
      kind, reason ->
        stacktrace = __STACKTRACE__
        async_emit(emit, %{"outcome" => to_string(kind)})
        :erlang.raise(kind, reason, stacktrace)
    end
  end

  defp async_emit(emit, value) do
    spawn(fn -> safe_emit(emit, value) end)
    :ok
  end

  defp safe_emit(emit, value) do
    try do
      emit.(value)
    rescue
      _ -> :ignored
    catch
      _, _ -> :ignored
    end
  end

  defp metrics(payload) when is_map(payload) do
    unknown = Map.keys(payload) -- @metric_fields

    if unknown == [] do
      {:ok,
       Map.new(@metric_fields, fn field ->
         metric =
           case Map.get(payload, field) do
             %{"value" => value, "source" => source, "quality" => quality} = candidate
             when map_size(candidate) == 3 and
                    (is_number(value) or is_nil(value) or value == :null) and
                    is_binary(source) and byte_size(source) > 0 and
                    is_binary(quality) and byte_size(quality) > 0 ->
               %{
                 "value" => if(is_nil(value), do: :null, else: value),
                 "source" => source,
                 "quality" => quality
               }

             _ ->
               %{"value" => :null, "source" => "unavailable", "quality" => "unavailable"}
           end

         {field, metric}
       end)}
    else
      {:error, {:unknown_metric_fields, Enum.sort(unknown)}}
    end
  end

  defp metrics(_payload), do: {:error, :invalid_provider_metrics}

  defp require_fields(attrs, fields) do
    case Enum.reject(fields, &Map.has_key?(attrs, &1)) do
      [] -> :ok
      missing -> {:error, {:missing_fields, missing}}
    end
  end

  defp reject_sensitive_fields(attrs) do
    forbidden =
      ~w(prompt prompt_body response response_body transcript environment env credentials secrets provider_payload corpus_text)

    case Enum.filter(forbidden, &Map.has_key?(attrs, &1)) do
      [] -> :ok
      fields -> {:error, {:sensitive_fields, fields}}
    end
  end

  defp validate_strings(attrs, required, optional) do
    fields = required ++ Enum.filter(optional, &Map.has_key?(attrs, &1))

    case Enum.find(fields, fn field ->
           not (is_binary(attrs[field]) and byte_size(attrs[field]) > 0)
         end) do
      nil -> :ok
      field -> {:error, {:invalid_type, field}}
    end
  end

  defp reject_unknown_fields(attrs, allowed) do
    case Map.keys(attrs) -- allowed do
      [] -> :ok
      fields -> {:error, {:unknown_fields, Enum.sort(fields)}}
    end
  end

  defp validate_duration(value) when is_integer(value) and value >= 0, do: :ok
  defp validate_duration(_value), do: {:error, :invalid_duration}

  defp validate_clock(attrs) do
    with {:ok, started, _started_offset} <- DateTime.from_iso8601(attrs["started_at"]),
         {:ok, ended, _ended_offset} <- DateTime.from_iso8601(attrs["ended_at"]),
         derived when derived >= 0 <- DateTime.diff(ended, started, :millisecond),
         true <- derived == attrs["duration_ms"] do
      :ok
    else
      _ -> {:error, :invalid_clock_boundary}
    end
  end

  defp validate_counts(attrs) do
    if Enum.all?(~w(retries cooldowns), fn field ->
         not Map.has_key?(attrs, field) or
           (is_integer(attrs[field]) and attrs[field] >= 0)
       end),
       do: :ok,
       else: {:error, :invalid_count}
  end

  defp valid_argv?(argv), do: is_list(argv) and argv != [] and Enum.all?(argv, &is_binary/1)

  defp sanitize_argv(argv) do
    {sanitized, _redact_next} =
      Enum.map_reduce(argv, false, fn arg, redact_next ->
        cond do
          redact_next ->
            {"[REDACTED]", false}

          arg in @secret_flags ->
            {arg, true}

          String.match?(arg, ~r/(?i)(api[_-]?key|token|password|secret)=/) ->
            {Regex.replace(~r/=.*/, arg, "=[REDACTED]"), false}

          true ->
            {arg, false}
        end
      end)

    sanitized
  end

  defp identify(record) do
    identity =
      Map.take(
        record,
        ~w(record_type task_id run_id role phase started_at command_id)
      )

    identified = Map.put(record, "record_id", digest(identity))
    Map.put(identified, "record_digest", digest(identified))
  end

  defp normalize_null_metrics(record) do
    update_in(record, ["metrics"], fn
      metrics when is_map(metrics) ->
        Map.new(metrics, fn {name, metric} ->
          normalized =
            case metric do
              %{"value" => nil} -> Map.put(metric, "value", :null)
              value -> value
            end

          {name, normalized}
        end)

      metrics ->
        metrics
    end)
  end

  defp digest(value) do
    value
    |> :json.encode()
    |> IO.iodata_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end
end
