defmodule PramanaFoundry.Assessor.Evaluator do
  @moduledoc """
  Offline evaluator for Stage A context-selection experiments.

  It compares baseline and assessor orderings over the same exact candidate manifest and
  records operational measurements separately for each arm. It performs no provider calls
  and reports integer totals rather than inventing precision from a small fixture set.
  """

  @observed_fields ~w(input_tokens assessor_calls latency_ms operator_effort_ms rework_events)
  @arms ~w(baseline assessor)
  @case_keys [
    "case_id",
    "candidate_manifest_digest",
    "baseline_order",
    "assessor_order",
    "relevant_ids",
    "observed"
  ]
  @max_cases 1_000
  @max_candidates 24
  @max_id_bytes 128
  @sha_pattern ~r/\A[0-9a-f]{64}\z/

  @spec compare([map()], pos_integer()) :: {:ok, map()} | {:error, atom()}
  def compare(cases, top_k)
      when is_list(cases) and length(cases) <= @max_cases and is_integer(top_k) and
             top_k > 0 and top_k <= @max_candidates do
    with {:ok, normalized} <- normalize_cases(cases),
         true <- normalized != [],
         true <- unique_case_ids?(normalized),
         true <- Enum.all?(normalized, &(length(&1["baseline_order"]) >= top_k)) do
      baseline = aggregate_arm(normalized, "baseline_order", top_k)
      assessor = aggregate_arm(normalized, "assessor_order", top_k)

      {:ok,
       %{
         "schema_version" => 2,
         "cases" => length(normalized),
         "top_k" => top_k,
         "baseline" => baseline,
         "assessor" => assessor,
         "observed" => %{
           "baseline" => aggregate_observed(normalized, "baseline"),
           "assessor" => aggregate_observed(normalized, "assessor")
         }
       }}
    else
      _ -> {:error, :invalid_evaluation_cases}
    end
  end

  def compare(_cases, _top_k), do: {:error, :invalid_evaluation_cases}

  defp normalize_cases(cases) do
    Enum.reduce_while(cases, {:ok, []}, fn value, {:ok, acc} ->
      case normalize_case(value) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, _reason} -> {:halt, {:error, :invalid_evaluation_cases}}
      end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp normalize_case(value) when is_map(value) and not is_struct(value) do
    case_id = Map.get(value, "case_id")
    manifest_digest = Map.get(value, "candidate_manifest_digest")
    baseline = Map.get(value, "baseline_order")
    assessor = Map.get(value, "assessor_order")
    relevant = Map.get(value, "relevant_ids")
    observed = Map.get(value, "observed")

    cond do
      Enum.sort(Map.keys(value)) != Enum.sort(@case_keys) ->
        {:error, :unknown_case_fields}

      not valid_id?(case_id) or not valid_manifest_digest?(manifest_digest) ->
        {:error, :invalid_case_identity}

      not valid_id_list?(baseline) or baseline == [] or not valid_id_list?(assessor) or
          not valid_id_list?(relevant) ->
        {:error, :invalid_case}

      length(baseline) > @max_candidates or length(assessor) > @max_candidates or
          length(relevant) > @max_candidates ->
        {:error, :too_many_candidates}

      Enum.sort(baseline) != Enum.sort(assessor) ->
        {:error, :candidate_set_changed}

      Enum.any?(relevant, &(&1 not in baseline)) ->
        {:error, :unknown_relevant_id}

      not valid_observed?(observed) ->
        {:error, :invalid_observed_metrics}

      true ->
        {:ok,
         %{
           "case_id" => case_id,
           "candidate_manifest_digest" => manifest_digest,
           "baseline_order" => baseline,
           "assessor_order" => assessor,
           "relevant_ids" => relevant,
           "observed" => observed
         }}
    end
  end

  defp normalize_case(_value), do: {:error, :invalid_case}

  defp valid_id_list?(value) when is_list(value) do
    Enum.all?(value, &valid_id?/1) and Enum.uniq(value) == value
  end

  defp valid_id_list?(_value), do: false

  defp valid_id?(value)
       when is_binary(value) and value != "" and byte_size(value) <= @max_id_bytes do
    String.valid?(value) and String.trim(value) == value and
      Enum.all?(:binary.bin_to_list(value), fn byte -> byte >= 32 and byte != 127 end)
  end

  defp valid_id?(_value), do: false

  defp valid_manifest_digest?(value) when is_binary(value),
    do: Regex.match?(@sha_pattern, value)

  defp valid_manifest_digest?(_value), do: false

  defp unique_case_ids?(cases) do
    ids = Enum.map(cases, & &1["case_id"])
    Enum.uniq(ids) == ids
  end

  defp valid_observed?(value) when is_map(value) and not is_struct(value) do
    Enum.sort(Map.keys(value)) == Enum.sort(@arms) and
      Enum.all?(@arms, fn arm -> valid_observed_arm?(Map.get(value, arm)) end)
  end

  defp valid_observed?(_value), do: false

  defp valid_observed_arm?(value) when is_map(value) and not is_struct(value) do
    Enum.all?(value, fn {key, metric} ->
      key in @observed_fields and (is_nil(metric) or (is_integer(metric) and metric >= 0))
    end)
  end

  defp valid_observed_arm?(_value), do: false

  defp aggregate_arm(cases, key, top_k) do
    Enum.reduce(
      cases,
      %{
        "important_context_misses_at_k" => 0,
        "reads_to_cover_all_relevant" => 0,
        "unnecessary_reads_before_full_relevance" => 0
      },
      fn value, acc ->
        metrics = metrics(value[key], value["relevant_ids"], top_k)
        Map.new(acc, fn {metric, total} -> {metric, total + Map.fetch!(metrics, metric)} end)
      end
    )
  end

  defp metrics(order, relevant, top_k) do
    relevant_set = MapSet.new(relevant)
    top = Enum.take(order, top_k)

    important_misses =
      relevant
      |> Enum.reject(&(&1 in top))
      |> length()

    {reads_to_cover, unnecessary} =
      if relevant == [] do
        {0, 0}
      else
        positions = order |> Enum.with_index() |> Map.new(fn {id, index} -> {id, index} end)
        last_relevant = relevant |> Enum.map(&Map.fetch!(positions, &1)) |> Enum.max()
        prefix = Enum.take(order, last_relevant + 1)
        {length(prefix), Enum.count(prefix, &(not MapSet.member?(relevant_set, &1)))}
      end

    %{
      "important_context_misses_at_k" => important_misses,
      "reads_to_cover_all_relevant" => reads_to_cover,
      "unnecessary_reads_before_full_relevance" => unnecessary
    }
  end

  defp aggregate_observed(cases, arm) do
    Map.new(@observed_fields, fn field ->
      values = Enum.map(cases, &get_in(&1, ["observed", arm, field]))

      {field,
       %{
         "known_total" => values |> Enum.reject(&is_nil/1) |> Enum.sum(),
         "unknown_cases" => Enum.count(values, &is_nil/1)
       }}
    end)
  end
end
