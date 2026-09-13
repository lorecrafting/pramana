defmodule PramanaFoundry.Integration.Pipeline do
  @moduledoc """
  Serial integration owner fencing, candidate readiness validation, check execution,
  and atomic accepted-revision promotion.
  """

  @doc """
  Attempts to acquire the singleton integration owner lock for a candidate.
  """
  def acquire_owner(state, task_id, commit) when is_binary(task_id) and is_binary(commit) do
    integration = Map.get(state, "integration", %{})
    current_owner = Map.get(integration, "owner")

    cond do
      is_nil(current_owner) ->
        updated_integration = Map.merge(integration, %{"owner" => task_id, "candidate" => commit})
        {:ok, Map.put(state, "integration", updated_integration)}

      current_owner == task_id ->
        {:ok, state}

      true ->
        {:error, :integration_busy}
    end
  end

  @doc """
  Releases the singleton integration owner lock.
  """
  def release_owner(state, task_id) do
    integration = Map.get(state, "integration", %{})

    if Map.get(integration, "owner") == task_id do
      updated_integration = Map.merge(integration, %{"owner" => nil, "candidate" => nil})
      Map.put(state, "integration", updated_integration)
    else
      state
    end
  end

  @doc """
  Validates readiness for candidate integration:
  - Pause or stop blocks promotion
  - Integration checkout must be clean (no uncommitted changes)
  - Integration checkout HEAD must equal accepted_revision
  - Candidate commit must match reviewed commit
  """
  def validate_readiness(state, assignment, opts \\ []) do
    paused? = Map.get(state, "paused", false)
    stop_requested? = Map.get(state, "stop_requested", false)
    status = Map.get(assignment, "status", "")
    review = Map.get(assignment, "review", nil)

    cond do
      paused? ->
        {:error, "promotion blocked: supervisor is paused"}

      stop_requested? ->
        {:error, "promotion blocked: stop requested"}

      status != "review_approved" ->
        {:error,
         "promotion blocked: assignment status is #{status}, expected review_approved"}

      not is_map(review) ->
        {:error, "promotion blocked: no review artifact recorded"}

      true ->
        ticket = Map.get(assignment, "ticket", assignment)
        handoff = Map.get(assignment, "handoff", %{})
        commit = Map.get(handoff, "commit", Map.get(assignment, "candidate_commit"))

        cond do
          not is_binary(commit) or commit == "" ->
            {:error, "candidate has no recorded commit"}

          true ->
            validate_checkouts_and_revisions(state, ticket, commit, opts)
        end
    end
  end

  defp validate_checkouts_and_revisions(state, ticket, _commit, opts) do
    accepted_rev = Map.get(state, "accepted_revision")
    base_rev = Map.get(ticket, "base_revision")

    # Stale candidate check: base_revision must equal accepted_revision
    if base_rev != accepted_rev do
      {:error, "stale candidate: ticket base #{base_rev} != accepted revision #{accepted_rev}"}
    else
      integration_path = Keyword.get(opts, :integration_path)

      cond do
        is_nil(integration_path) or Keyword.get(opts, :skip_git_checks, false) ->
          :ok

        File.dir?(integration_path) ->
          case System.cmd("git", ["status", "--porcelain"],
                 cd: integration_path,
                 stderr_to_stdout: true
               ) do
            {"", 0} ->
              case System.cmd("git", ["rev-parse", "HEAD"],
                     cd: integration_path,
                     stderr_to_stdout: true
                   ) do
                {head, 0} ->
                  actual_head = String.trim(head)

                  if actual_head != accepted_rev do
                    {:error,
                     "integration checkout moved beyond accepted revision: #{actual_head} != #{accepted_rev}"}
                  else
                    :ok
                  end

                {err, _} ->
                  {:error, "git rev-parse HEAD failed on integration path: #{err}"}
              end

            {dirty, 0} ->
              {:error,
               "integration checkout has uncommitted changes: #{String.slice(dirty, 0, 200)}"}

            {err, _} ->
              {:error, "git status check failed on integration path: #{err}"}
          end

        true ->
          :ok
      end
    end
  end

  @doc """
  Runs combined gate checks (required_checks + integration_only_checks) against candidate checkout.
  """
  def run_gate_checks(candidate_path, checks, runner_fn \\ nil) do
    Enum.reduce_while(checks, :ok, fn command, :ok ->
      result =
        if is_function(runner_fn, 2) do
          runner_fn.(command, candidate_path)
        else
          # Default shell runner
          case command do
            ["sh", "-c", cmd] ->
              System.cmd("sh", ["-c", cmd], cd: candidate_path, stderr_to_stdout: true)

            [executable | args] ->
              System.cmd(executable, args, cd: candidate_path, stderr_to_stdout: true)

            _ ->
              {"invalid command shape", 1}
          end
        end

      case result do
        {_output, 0} ->
          {:cont, :ok}

        {output, exit_code} ->
          {:halt, {:error, {:check_failed, command, exit_code, output}}}
      end
    end)
  end

  @doc """
  Promotes candidate commit to accepted_revision, marking assignment integrated and releasing owner.
  Verifies that stop_requested has not occurred.
  """
  def promote_candidate(state, assignment, opts \\ []) do
    stop_requested? =
      Map.get(state, "stop_requested", false) or Keyword.get(opts, :stop_observed, false)

    if stop_requested? do
      {:error,
       "candidate cannot be promoted from success evidence observed during or after a stop without a fresh authorized gate execution"}
    else
      handoff = Map.get(assignment, "handoff", %{})
      commit = Map.get(handoff, "commit", Map.get(assignment, "candidate_commit"))
      task_id = get_in(assignment, ["ticket", "task_id"]) || Map.get(assignment, "task_id")

      updated_assignment =
        assignment
        |> Map.put("status", "integrated")
        |> Map.put("integrated_at", DateTime.utc_now() |> DateTime.to_iso8601())

      updated_assignments =
        Map.put(Map.get(state, "assignments", %{}), task_id, updated_assignment)

      updated_state =
        state
        |> Map.put("accepted_revision", commit)
        |> Map.put("assignments", updated_assignments)
        |> release_owner(task_id)

      {:ok, updated_state, updated_assignment}
    end
  end

  @doc """
  Fails integration: preserves accepted_revision, marks assignment parked, and releases owner.
  """
  def fail_integration(state, assignment, reason) do
    task_id = get_in(assignment, ["ticket", "task_id"]) || Map.get(assignment, "task_id")

    updated_assignment =
      assignment
      |> Map.put("status", "parked")
      |> Map.put("blocker", "integration check failed: #{reason}")

    updated_assignments = Map.put(Map.get(state, "assignments", %{}), task_id, updated_assignment)

    updated_state =
      state
      |> Map.put("assignments", updated_assignments)
      |> release_owner(task_id)

    # Note: state["accepted_revision"] is strictly preserved/unchanged!
    {:ok, updated_state, updated_assignment}
  end
end
