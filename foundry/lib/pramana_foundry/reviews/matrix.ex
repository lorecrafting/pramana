defmodule PramanaFoundry.Reviews.Matrix do
  @moduledoc """
  Engine derivation of reviewer profile from model_policy.review_matrix.
  """

  @high_risk_classes ~w(p0_correctness_security workflow_recovery high_risk)
  @high_risk_work_classes ~w(milestone_architecture p0_high_risk)

  @spec high_risk_ticket?(map()) :: boolean()
  def high_risk_ticket?(ticket) when is_map(ticket) do
    Map.get(ticket, "priority") in ["P0", "p0"] or
      Map.get(ticket, "risk") in @high_risk_classes or
      Map.get(ticket, "work_class") in @high_risk_work_classes
  end

  def high_risk_ticket?(_), do: false

  @spec derive_reviewer_profile(map(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def derive_reviewer_profile(ticket, model_policy)
      when is_map(ticket) and is_map(model_policy) do
    matrix = Map.get(model_policy, "review_matrix", %{})

    expected_key = if high_risk_ticket?(ticket), do: "high_risk", else: "routine"

    case Map.fetch(matrix, expected_key) do
      {:ok, profile_name} when is_binary(profile_name) and profile_name != "" ->
        {:ok, profile_name}

      _ ->
        {:error, "model_policy.review_matrix missing profile for #{expected_key}"}
    end
  end

  def derive_reviewer_profile(_ticket, _policy), do: {:error, "invalid ticket or model policy"}
end
