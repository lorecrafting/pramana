defmodule PramanaFoundry.Assessor.Result do
  @moduledoc """
  Typed advisory assessment result.

  Numeric model outputs are converted to fixed-point integers before entering this
  contract. Raw response bytes are not made authoritative; only their SHA-256 may be
  retained here for Stage A evidence.
  """

  alias PramanaFoundry.Assessor.Request

  @statuses [:valid, :abstain, :unavailable, :not_requested, :invalid, :stale]
  @max_ppm 1_000_000
  @max_score_micros 2_000_000

  @enforce_keys [
    :status,
    :reason,
    :assessment_id,
    :request_digest,
    :candidate_digest,
    :policy_digest,
    :provider,
    :model
  ]
  defstruct [
    :status,
    :reason,
    :assessment_id,
    :request_digest,
    :candidate_digest,
    :policy_digest,
    :provider,
    :model,
    :recommendations,
    :explicit_none?,
    :usage,
    :raw_response_sha256
  ]

  @type recommendation :: %{
          candidate_id: String.t(),
          score_micros: non_neg_integer(),
          confidence_ppm: non_neg_integer(),
          probabilities_ppm: %{required(String.t()) => non_neg_integer()}
        }
  @type t :: %__MODULE__{}

  @spec valid(Request.t(), [recommendation()], keyword()) :: t()
  def valid(%Request{} = request, recommendations, opts \\ []) do
    explicit_none? = Keyword.get(opts, :explicit_none?, false)

    if valid_recommendations?(request, recommendations, explicit_none?) do
      base(request, :valid, :ok, opts)
      |> Map.put(:recommendations, recommendations)
      |> Map.put(:explicit_none?, explicit_none?)
    else
      invalid(request, :invalid_recommendations, opts)
    end
  end

  @spec abstain(Request.t(), atom(), keyword()) :: t()
  def abstain(request, reason, opts \\ []), do: base(request, :abstain, reason, opts)

  @spec unavailable(Request.t(), atom(), keyword()) :: t()
  def unavailable(request, reason, opts \\ []), do: base(request, :unavailable, reason, opts)

  @spec not_requested(Request.t(), atom(), keyword()) :: t()
  def not_requested(request, reason, opts \\ []),
    do: base(request, :not_requested, reason, opts)

  @spec invalid(Request.t(), atom(), keyword()) :: t()
  def invalid(request, reason, opts \\ []), do: base(request, :invalid, reason, opts)

  @spec stale(Request.t(), atom()) :: t()
  def stale(request, reason), do: base(request, :stale, reason, [])

  @spec fresh?(t(), Request.t()) :: boolean()
  def fresh?(%__MODULE__{} = result, %Request{} = request) do
    result.assessment_id == request.assessment_id and
      result.request_digest == request.request_digest and
      result.candidate_digest == request.candidate_digest and
      result.policy_digest == request.policy_digest and
      result.provider == request.provider and
      result.model == request.model
  end

  @spec statuses() :: [atom()]
  def statuses, do: @statuses

  defp base(%Request{} = request, status, reason, opts) when status in @statuses do
    %__MODULE__{
      status: status,
      reason: reason,
      assessment_id: request.assessment_id,
      request_digest: request.request_digest,
      candidate_digest: request.candidate_digest,
      policy_digest: request.policy_digest,
      provider: request.provider,
      model: request.model,
      recommendations: Keyword.get(opts, :recommendations, []),
      explicit_none?: Keyword.get(opts, :explicit_none?, false),
      usage: Keyword.get(opts, :usage, %{"input_tokens" => nil, "output_tokens" => nil}),
      raw_response_sha256: Keyword.get(opts, :raw_response_sha256)
    }
  end

  defp valid_recommendations?(_request, [], true), do: true

  defp valid_recommendations?(%Request{} = request, recommendations, false)
       when is_list(recommendations) do
    expected = Enum.map(request.candidates, & &1.id)
    ids = Enum.map(recommendations, &Map.get(&1, :candidate_id))

    ids == Enum.uniq(ids) and Enum.sort(ids) == Enum.sort(expected) and
      Enum.all?(recommendations, &valid_recommendation?/1)
  end

  defp valid_recommendations?(_request, _recommendations, _explicit_none?), do: false

  defp valid_recommendation?(recommendation) when is_map(recommendation) do
    score = Map.get(recommendation, :score_micros)
    confidence = Map.get(recommendation, :confidence_ppm)
    probabilities = Map.get(recommendation, :probabilities_ppm)

    is_binary(Map.get(recommendation, :candidate_id)) and
      is_integer(score) and score >= 0 and score <= @max_score_micros and
      is_integer(confidence) and confidence >= 0 and confidence <= @max_ppm and
      valid_probabilities?(probabilities)
  end

  defp valid_recommendation?(_recommendation), do: false

  defp valid_probabilities?(probabilities) when is_map(probabilities) do
    keys = Map.keys(probabilities) |> Enum.sort()
    values = Map.values(probabilities)

    keys == ["0", "1", "2"] and
      Enum.all?(values, &(is_integer(&1) and &1 >= 0 and &1 <= @max_ppm)) and
      abs(Enum.sum(values) - @max_ppm) <= 3
  end

  defp valid_probabilities?(_probabilities), do: false
end
