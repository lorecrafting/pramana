defmodule PramanaFoundry.Integration do
  @moduledoc """
  Top-level candidate integration pipeline and serial owner management.
  """

  alias PramanaFoundry.Integration.Pipeline

  defdelegate acquire_owner(state, task_id, commit), to: Pipeline
  defdelegate release_owner(state, task_id), to: Pipeline
  defdelegate validate_readiness(state, assignment, opts \\ []), to: Pipeline
  defdelegate run_gate_checks(candidate_path, checks, runner_fn \\ nil), to: Pipeline
  defdelegate promote_candidate(state, assignment, opts \\ []), to: Pipeline
  defdelegate fail_integration(state, assignment, reason), to: Pipeline
end
