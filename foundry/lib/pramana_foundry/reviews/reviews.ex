defmodule PramanaFoundry.Reviews do
  @moduledoc """
  Top-level reviewer derivation and artifact validation.
  """

  alias PramanaFoundry.Reviews.Artifact
  alias PramanaFoundry.Reviews.Matrix

  defdelegate high_risk_ticket?(ticket), to: Matrix
  defdelegate derive_reviewer_profile(ticket, model_policy), to: Matrix

  defdelegate validate_artifact(review, ticket, assignment, opts \\ []),
    to: Artifact,
    as: :validate
end
