defmodule PramanaFoundry.PM do
  @moduledoc """
  PM planning lifecycle, proposal transactions, and attempt cap management.
  """

  alias PramanaFoundry.PM.AttemptCap
  alias PramanaFoundry.PM.Proposal

  defdelegate apply_proposals(state, proposals, opts \\ []), to: Proposal, as: :apply_batch

  defdelegate record_disposition(pm_state, disposition, reason, opts \\ []), to: AttemptCap
  defdelegate increment_attempt(pm_state, accepted_revision), to: AttemptCap
  defdelegate halt_reason(pm_state, accepted_revision, config \\ %{}), to: AttemptCap
  defdelegate reset_attempts(pm_state, payload, current_accepted_revision), to: AttemptCap
  defdelegate normalize_reason(reason), to: AttemptCap
end
