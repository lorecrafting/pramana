defmodule PramanaFoundry.Assignments do
  @moduledoc """
  Top-level assignment handoff validation and correction handling.
  """

  alias PramanaFoundry.Assignments.Correction
  alias PramanaFoundry.Assignments.Handoff

  defdelegate validate_handoff(handoff, ticket, assignment, opts \\ []),
    to: Handoff,
    as: :validate

  defdelegate handle_review(assignment, review), to: Correction
end
