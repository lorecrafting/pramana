defmodule PramanaFoundry.Assessor.ContextSelector do
  @moduledoc """
  Deterministic optional-context consumer.

  Mandatory context is opaque and unchanged. Off, shadow, stale, invalid, uncertain, and
  unavailable assessment paths retain the full deterministic optional baseline. A valid
  enabled assessment may select only a bounded initial subset; omitted optional material
  remains eligible for later retrieval through the caller's normal tools.
  """

  alias PramanaFoundry.Assessor
  alias PramanaFoundry.Assessor.Off
  alias PramanaFoundry.Assessor.Request
  alias PramanaFoundry.Assessor.Result
  alias PramanaFoundry.Assessor.Selection

  @modes [:off, :shadow, :enabled]
  @selection_version "initial-top-k-v1"

  @spec selection_version() :: String.t()
  def selection_version, do: @selection_version

  @spec select(list(), Request.t(), keyword()) :: Selection.t()
  def select(mandatory, %Request{} = request, opts \\ []) when is_list(mandatory) do
    opts = Keyword.validate!(opts, [:mode, :authorized?, :adapter, :adapter_opts])
    mode = Keyword.get(opts, :mode, :off)
    authorized? = Keyword.get(opts, :authorized?, false)

    unless mode in @modes, do: raise(ArgumentError, "invalid assessor mode")
    unless is_boolean(authorized?), do: raise(ArgumentError, "authorized? must be boolean")

    adapter_opts = Keyword.get(opts, :adapter_opts, [])

    unless Keyword.keyword?(adapter_opts),
      do: raise(ArgumentError, "adapter_opts must be keyword")

    result =
      request
      |> assess(mode, authorized?, Keyword.get(opts, :adapter, Off), adapter_opts)
      |> normalize_result(request)

    baseline = request.candidates
    recommended = recommendation(request, result)

    {delivered, applied?, fallback_reason} =
      delivery(
        mode,
        baseline,
        recommended,
        result,
        authorized?,
        request.policy.max_initial_optional
      )

    %Selection{
      mode: mode,
      selection_version: @selection_version,
      mandatory: mandatory,
      baseline_optional: baseline,
      recommended_optional: recommended,
      delivered_optional: delivered,
      assessment: result,
      applied?: applied?,
      fallback_reason: fallback_reason
    }
  end

  defp assess(request, :off, _authorized?, _adapter, _opts),
    do: Result.not_requested(request, :disabled)

  defp assess(request, _mode, false, _adapter, _opts),
    do: Result.not_requested(request, :unauthorized)

  defp assess(
         %Request{policy: %{selection_version: version}} = request,
         _mode,
         true,
         _adapter,
         _opts
       )
       when version != @selection_version,
       do: Result.invalid(request, :selection_version_mismatch)

  defp assess(%Request{candidates: []} = request, _mode, true, _adapter, _opts),
    do: Result.not_requested(request, :no_candidates)

  defp assess(request, _mode, true, adapter, opts),
    do: Assessor.call(adapter, request, opts)

  defp normalize_result(%Result{} = result, request) do
    if Result.fresh?(result, request),
      do: result,
      else: Result.stale(request, :identity_mismatch)
  end

  defp recommendation(_request, %Result{status: :valid, explicit_none?: true}), do: []

  defp recommendation(%Request{} = request, %Result{status: :valid} = result) do
    scores = Map.new(result.recommendations, &{&1.candidate_id, &1.score_micros})
    positions = request.candidates |> Enum.with_index() |> Map.new(fn {c, i} -> {c.id, i} end)

    Enum.sort_by(request.candidates, fn candidate ->
      {-Map.fetch!(scores, candidate.id), Map.fetch!(positions, candidate.id)}
    end)
  end

  defp recommendation(%Request{} = request, _result), do: request.candidates

  defp delivery(
         :enabled,
         _baseline,
         recommended,
         %Result{status: :valid, explicit_none?: false},
         true,
         max_initial_optional
       ),
       do: {Enum.take(recommended, max_initial_optional), true, nil}

  defp delivery(
         :enabled,
         _baseline,
         _recommended,
         %Result{status: :valid, explicit_none?: true},
         true,
         _max_initial_optional
       ),
       do: {[], true, nil}

  defp delivery(
         :shadow,
         baseline,
         _recommended,
         %Result{status: :valid},
         true,
         _max_initial_optional
       ),
       do: {baseline, false, :shadow_only}

  defp delivery(_mode, baseline, _recommended, %Result{} = result, _authorized?, _limit),
    do: {baseline, false, result.reason}
end
