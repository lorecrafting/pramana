defmodule PramanaFoundry.Assessor.Request do
  @moduledoc """
  Immutable Stage A assessment request.

  Request identity binds the task objective, candidate manifest, policy, provider/model
  selection, and resource limits. It is advisory metadata only and is not a Foundry
  effect claim, budget reservation, or workflow command.
  """

  alias PramanaFoundry.Assessor.Candidate
  alias PramanaFoundry.Assessor.Policy

  @purpose "optional_context_selection_v1"
  @max_candidates 24
  @max_objective_bytes 16_384
  @max_total_candidate_bytes 131_072
  @max_timeout_ms 10_000
  @max_body_bytes 262_144

  @enforce_keys [
    :assessment_id,
    :purpose,
    :objective,
    :candidates,
    :policy,
    :provider,
    :model,
    :timeout_ms,
    :max_request_bytes,
    :max_response_bytes,
    :candidate_digest,
    :policy_digest,
    :request_digest
  ]
  defstruct [
    :assessment_id,
    :purpose,
    :task_id,
    :attempt_id,
    :objective,
    :candidates,
    :policy,
    :provider,
    :model,
    :timeout_ms,
    :max_request_bytes,
    :max_response_bytes,
    :candidate_digest,
    :policy_digest,
    :request_digest
  ]

  @type t :: %__MODULE__{}

  @spec new(map() | keyword()) :: {:ok, t()} | {:error, atom()}
  def new(attrs) do
    attrs = if Keyword.keyword?(attrs), do: Map.new(attrs), else: attrs

    with true <- is_map(attrs) and not is_struct(attrs),
         {:ok, assessment_id} <- required_binary(attrs, :assessment_id, 128),
         {:ok, objective} <- required_binary(attrs, :objective, @max_objective_bytes),
         {:ok, task_id} <- optional_binary(attrs, :task_id, 128),
         {:ok, attempt_id} <- optional_binary(attrs, :attempt_id, 128),
         {:ok, candidates} <- candidates(Map.get(attrs, :candidates, [])),
         {:ok, policy} <- policy(Map.get(attrs, :policy)),
         {:ok, provider} <- required_binary(attrs, :provider, 64),
         {:ok, model} <- required_binary(attrs, :model, 128),
         {:ok, timeout_ms} <- bounded_integer(attrs, :timeout_ms, 1, @max_timeout_ms, 2_000),
         {:ok, max_request_bytes} <-
           bounded_integer(attrs, :max_request_bytes, 256, @max_body_bytes, 196_608),
         {:ok, max_response_bytes} <-
           bounded_integer(attrs, :max_response_bytes, 256, @max_body_bytes, 131_072) do
      candidate_digest =
        digest_term({
          "assessor-candidate-manifest-v1",
          Enum.map(candidates, &Candidate.manifest_entry/1)
        })

      policy_digest =
        digest_term({
          "assessor-policy-v1",
          policy.version,
          policy.question_set_version,
          policy.selection_version,
          policy.min_confidence_ppm,
          policy.max_initial_optional
        })

      request_digest =
        digest_term({
          "assessor-request-v1",
          @purpose,
          assessment_id,
          task_id,
          attempt_id,
          objective,
          candidate_digest,
          policy_digest,
          provider,
          model,
          timeout_ms,
          max_request_bytes,
          max_response_bytes
        })

      {:ok,
       %__MODULE__{
         assessment_id: assessment_id,
         purpose: @purpose,
         task_id: task_id,
         attempt_id: attempt_id,
         objective: objective,
         candidates: candidates,
         policy: policy,
         provider: provider,
         model: model,
         timeout_ms: timeout_ms,
         max_request_bytes: max_request_bytes,
         max_response_bytes: max_response_bytes,
         candidate_digest: candidate_digest,
         policy_digest: policy_digest,
         request_digest: request_digest
       }}
    else
      _ -> {:error, :invalid_request}
    end
  end

  @spec digest_term(term()) :: String.t()
  def digest_term(term) do
    bytes = :erlang.term_to_binary(term, [:deterministic])
    :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)
  end

  defp candidates(value) when is_list(value) and length(value) <= @max_candidates do
    with {:ok, candidates} <- normalize_candidates(value),
         true <- unique_candidate_ids?(candidates),
         true <-
           Enum.sum(Enum.map(candidates, &byte_size(&1.content))) <= @max_total_candidate_bytes do
      {:ok, candidates}
    else
      _ -> {:error, :invalid_candidates}
    end
  end

  defp candidates(_value), do: {:error, :invalid_candidates}

  defp normalize_candidates(candidates) do
    Enum.reduce_while(candidates, {:ok, []}, fn
      %Candidate{} = candidate, {:ok, acc} ->
        {:cont, {:ok, [candidate | acc]}}

      attrs, {:ok, acc} ->
        case Candidate.new(attrs) do
          {:ok, candidate} -> {:cont, {:ok, [candidate | acc]}}
          {:error, _reason} -> {:halt, {:error, :invalid_candidates}}
        end
    end)
    |> case do
      {:ok, reversed} -> {:ok, Enum.reverse(reversed)}
      error -> error
    end
  end

  defp unique_candidate_ids?(candidates) do
    ids = Enum.map(candidates, & &1.id)
    Enum.uniq(ids) == ids
  end

  defp policy(%Policy{} = policy), do: {:ok, policy}
  defp policy(attrs), do: Policy.new(attrs)

  defp required_binary(attrs, key, max_bytes) do
    case Map.fetch(attrs, key) do
      {:ok, value}
      when is_binary(value) and value != "" and byte_size(value) <= max_bytes ->
        if String.valid?(value) and String.trim(value) == value,
          do: {:ok, value},
          else: {:error, :invalid_request}

      _ ->
        {:error, :invalid_request}
    end
  end

  defp optional_binary(attrs, key, max_bytes) do
    case Map.fetch(attrs, key) do
      :error ->
        {:ok, nil}

      {:ok, nil} ->
        {:ok, nil}

      {:ok, value}
      when is_binary(value) and value != "" and byte_size(value) <= max_bytes ->
        if String.valid?(value) and String.trim(value) == value,
          do: {:ok, value},
          else: {:error, :invalid_request}

      _ ->
        {:error, :invalid_request}
    end
  end

  defp bounded_integer(attrs, key, minimum, maximum, default) do
    value = Map.get(attrs, key, default)

    if is_integer(value) and value >= minimum and value <= maximum,
      do: {:ok, value},
      else: {:error, :invalid_request}
  end
end
