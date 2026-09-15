defmodule PramanaFoundry.Integration.Pipeline do
  @moduledoc """
  Containment boundary for the suspended legacy integration pipeline.

  FR-13 and FR-14 must replace these entry points with controller-custodied evidence
  and protected-ref promotion. Until then every public operation refuses before state,
  runner, filesystem or Git effects.
  """

  @suspended "legacy integration is suspended before effects; FR-13/FR-14 restore verified promotion"

  @doc """
  Attempts to acquire the singleton integration owner lock for a candidate.
  """
  def acquire_owner(state, task_id, commit) when is_binary(task_id) and is_binary(commit) do
    _ = {state, task_id, commit}
    {:error, @suspended}
  end

  @doc """
  Releases the singleton integration owner lock.
  """
  def release_owner(state, task_id) do
    _ = {state, task_id}
    {:error, @suspended}
  end

  @doc """
  Refuses legacy readiness validation before trusting any caller-supplied Git fact.
  """
  def validate_readiness(state, assignment, opts \\ []) do
    _ = {state, assignment, opts}
    {:error, @suspended}
  end

  @doc """
  Refuses legacy check execution before invoking a runner.
  """
  def run_gate_checks(candidate_path, checks, runner_fn \\ nil) do
    _ = {candidate_path, checks, runner_fn}
    {:error, @suspended}
  end

  @doc """
  Legacy memory-only promotion is suspended.

  FR-14 restores promotion using a protected accepted ref after FR-13 supplies verified
  evidence. This containment function deliberately leaves its input state unchanged.
  """
  def promote_candidate(state, assignment, opts \\ []) do
    _ = {state, assignment, opts}
    {:error, @suspended}
  end

  @doc """
  Refuses legacy failure mutation; authoritative integration state does not exist yet.
  """
  def fail_integration(state, assignment, reason) do
    _ = {state, assignment, reason}
    {:error, @suspended}
  end
end
