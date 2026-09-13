defmodule PramanaFoundry.Coordinator.State do
  @moduledoc """
  Pure functional state transformations for the workflow coordinator.
  """

  alias PramanaFoundry.Assignments
  alias PramanaFoundry.Integration
  alias PramanaFoundry.PM
  alias PramanaFoundry.Reviews

  @spec new(keyword()) :: map()
  def new(opts \\ []) do
    accepted_rev =
      Keyword.get(opts, :accepted_revision, "d83f8f0cedc34780d25cba452545ce9883d416a5")

    %{
      "schema_version" => 1,
      "generation" => 0,
      "status" => "running",
      "paused" => false,
      "stop_requested" => false,
      "accepted_revision" => accepted_rev,
      "supervisor" => %{},
      "assignments" => %{},
      "queue" => [],
      "steering" => [],
      "integration" => %{"owner" => nil, "candidate" => nil},
      "scheduler" => %{},
      "pm" => %{
        "status" => "idle",
        "attempts_by_revision" => %{},
        "consecutive_rejections_by_revision" => %{}
      },
      "provider_cooldowns" => %{},
      "provider_fallback_intents" => %{},
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  @spec pause(map()) :: map()
  def pause(state) do
    state
    |> Map.put("paused", true)
    |> touch()
  end

  @spec resume(map()) :: map()
  def resume(state) do
    state
    |> Map.put("paused", false)
    |> touch()
  end

  @spec request_stop(map()) :: map()
  def request_stop(state) do
    state
    |> Map.put("stop_requested", true)
    |> touch()
  end

  @spec enqueue_ticket(map(), map()) :: {:ok, map()} | {:error, String.t()}
  def enqueue_ticket(state, ticket) when is_map(ticket) do
    task_id = Map.get(ticket, "task_id")

    cond do
      not is_binary(task_id) or task_id == "" ->
        {:error, "ticket requires task_id"}

      Map.has_key?(state["assignments"], task_id) ->
        {:error, "ticket #{task_id} already exists"}

      ticket["base_revision"] != state["accepted_revision"] ->
        {:error,
         "ticket base #{ticket["base_revision"]} != accepted revision #{state["accepted_revision"]}"}

      # Structural validation — deterministic fence against malformed LLM output
      not validate_ticket_structure(ticket) ->
        {:error, "ticket has invalid structure: scope must be list, exclusions must be list, required_checks must be list of string lists"}

      true ->
        assignment = %{
          "ticket" => ticket,
          "task_id" => task_id,
          "status" => "queued",
          "queued_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        updated_assignments = Map.put(state["assignments"], task_id, assignment)
        updated_queue = state["queue"] ++ [task_id]

        new_state =
          state
          |> Map.put("assignments", updated_assignments)
          |> Map.put("queue", updated_queue)
          |> touch()

        {:ok, new_state}
    end
  end

  defp validate_ticket_structure(ticket) do
    scope_ok? = case ticket["scope"] do
      nil -> true
      list when is_list(list) -> Enum.all?(list, &is_binary/1)
      _ -> false
    end

    exclusions_ok? = case ticket["exclusions"] do
      nil -> true
      list when is_list(list) -> Enum.all?(list, &is_binary/1)
      _ -> false
    end

    required_checks_ok? = case ticket["required_checks"] do
      nil -> true
      list when is_list(list) -> Enum.all?(list, &validate_check_command/1)
      _ -> false
    end

    checkout_ok? = case ticket["checkout"] do
      nil -> true
      path when is_binary(path) -> true
      _ -> false
    end

    scope_ok? and exclusions_ok? and required_checks_ok? and checkout_ok?
  end

  defp validate_check_command(cmd) when is_list(cmd), do: Enum.all?(cmd, &is_binary/1)
  defp validate_check_command(_), do: false

  @spec admit_assignment(map(), String.t(), String.t(), String.t(), map()) ::
          {:ok, map(), map()} | {:error, String.t()}
  def admit_assignment(state, task_id, run_id, role, opts \\ %{}) do
    assignment = get_in(state, ["assignments", task_id])

    cond do
      is_nil(assignment) ->
        {:error, "unknown assignment: #{task_id}"}

      assignment["status"] != "queued" ->
        {:error, "assignment #{task_id} is not queued (current: #{assignment["status"]})"}

      true ->
        updated_assignment =
          assignment
          |> Map.put("run_id", run_id)
          |> Map.put("role", role)
          |> Map.put("status", "dispatched")
          |> Map.put(
            "configured_profile",
            Map.get(opts, "profile", get_in(assignment, ["ticket", "profile"]))
          )
          |> Map.put("dispatched_at", DateTime.utc_now() |> DateTime.to_iso8601())

        updated_queue = List.delete(state["queue"], task_id)
        updated_assignments = Map.put(state["assignments"], task_id, updated_assignment)

        new_state =
          state
          |> Map.put("assignments", updated_assignments)
          |> Map.put("queue", updated_queue)
          |> touch()

        {:ok, updated_assignment, new_state}
    end
  end

@spec receive_handoff(map(), String.t(), map(), keyword()) ::
          {:ok, map(), map()} | {:error, String.t(), map()} | {:error, String.t()}
  def receive_handoff(state, task_id, handoff, opts \\ []) do
    assignment = get_in(state, ["assignments", task_id])

    cond do
      is_nil(assignment) ->
        {:error, "unknown assignment: #{task_id}"}

      true ->
        ticket = assignment["ticket"]

        case Assignments.validate_handoff(handoff, ticket, assignment, opts) do
          {:ok, validated_handoff} ->
            # Check if the ticket has auto_approve — skip review step
            auto_approve = Map.get(ticket, "auto_approve", false)

            new_status =
              if auto_approve do
                "review_approved"
              else
                if validated_handoff["status"] == "blocked",
                  do: "blocked",
                  else: "handoff_received"
              end

            updated_assignment =
              assignment
              |> Map.put("handoff", validated_handoff)
              |> Map.put("candidate_commit", validated_handoff["commit"])
              |> Map.put("status", new_status)
              |> Map.put("handoff_received_at", DateTime.utc_now() |> DateTime.to_iso8601())

            # For auto_approve, create a synthetic review artifact so the
            # integration gate passes (requires is_map(review))
            updated_assignment =
              if auto_approve do
                Map.put(updated_assignment, "review", %{
                  "verdict" => "approved",
                  "findings" => [],
                  "checks" => validated_handoff["checks"],
                  "remaining_risks" => validated_handoff["remaining_risks"],
                  "commit" => validated_handoff["commit"],
                  "auto_approved" => true
                })
              else
                updated_assignment
              end

            updated_assignments = Map.put(state["assignments"], task_id, updated_assignment)
            new_state = Map.put(state, "assignments", updated_assignments) |> touch()
            {:ok, updated_assignment, new_state}

          {:error, reason} ->
            # Invalid handoff: re-enqueue with retry budget instead of parking permanently.
            # This makes the system self-healing — a bad handoff gets retried.
            max_handoff_retries = Keyword.get(opts, :max_handoff_retries, 3)
            current_retries = Map.get(assignment, "handoff_retries", 0)
            new_retries = current_retries + 1

            if new_retries <= max_handoff_retries do
              retried_assignment =
                assignment
                |> Map.put("status", "queued")
                |> Map.put("handoff_retries", new_retries)
                |> Map.put("error", "invalid handoff (retry #{new_retries}/#{max_handoff_retries}): #{reason}")

              updated_assignments = Map.put(state["assignments"], task_id, retried_assignment)
              updated_queue = state["queue"] ++ [task_id]

              new_state =
                state
                |> Map.put("assignments", updated_assignments)
                |> Map.put("queue", updated_queue)
                |> touch()

              {:error, reason, new_state}
            else
              parked_assignment =
                assignment
                |> Map.put("status", "parked")
                |> Map.put("handoff_retries", new_retries)
                |> Map.put("blocker", "invalid handoff artifact (retries exhausted): #{reason}")

              updated_assignments = Map.put(state["assignments"], task_id, parked_assignment)
              new_state = Map.put(state, "assignments", updated_assignments) |> touch()
              {:error, "maximum handoff retries (#{max_handoff_retries}) exceeded: #{reason}", new_state}
            end
        end
    end
  end

  @spec receive_review(map(), String.t(), map(), keyword()) ::
          {:ok, map(), map()} | {:error, String.t()}
  def receive_review(state, task_id, review, opts \\ []) do
    assignment = get_in(state, ["assignments", task_id])

    cond do
      is_nil(assignment) ->
        {:error, "unknown assignment: #{task_id}"}

      true ->
        ticket = assignment["ticket"]

        case Reviews.validate_artifact(review, ticket, assignment, opts) do
          {:ok, validated_review} ->
            case Assignments.handle_review(assignment, validated_review) do
              {:ok, :approved, approved_assignment} ->
                updated_assignment =
                  approved_assignment
                  |> Map.put("review", validated_review)
                  |> Map.put("status", "review_approved")
                  |> Map.put("review_received_at", DateTime.utc_now() |> DateTime.to_iso8601())

                updated_assignments = Map.put(state["assignments"], task_id, updated_assignment)
                new_state = Map.put(state, "assignments", updated_assignments) |> touch()

                {:ok, updated_assignment, new_state}

              {:ok, :correction_needed, correction_assignment} ->
                # Re-queue for correction — the task goes back with full context
                # (handoff, review findings) so the developer can address findings.
                updated_queue = state["queue"] ++ [task_id]

                updated_assignments =
                  Map.put(state["assignments"], task_id, correction_assignment)

                new_state =
                  state
                  |> Map.put("assignments", updated_assignments)
                  |> Map.put("queue", updated_queue)
                  |> touch()

                {:ok, correction_assignment, new_state}

              {:error, :max_corrections_exceeded, parked_assignment} ->
                updated_assignments = Map.put(state["assignments"], task_id, parked_assignment)
                new_state = Map.put(state, "assignments", updated_assignments) |> touch()
                {:error, "maximum corrections exceeded (2)", new_state}
            end

          {:error, reason} ->
            # Malformed review artifact: retry with budget instead of parking.
            # Reviewer re-launches with `previous_error` for self-correction.
            max_review_retries = Keyword.get(opts, :max_review_retries, 3)
            current_retries = Map.get(assignment, "review_retries", 0)
            new_retries = current_retries + 1

            if new_retries <= max_review_retries do
              retried_assignment =
                assignment
                |> Map.put("status", "handoff_received")
                |> Map.put("review_retries", new_retries)
                |> Map.put("error",
                     "invalid review (retry #{new_retries}/#{max_review_retries}): #{reason}"
                   )

              updated_assignments = Map.put(state["assignments"], task_id, retried_assignment)
              new_state = Map.put(state, "assignments", updated_assignments) |> touch()

              {:error, reason, new_state}
            else
              parked_assignment =
                assignment
                |> Map.put("status", "parked")
                |> Map.put("review_retries", new_retries)
                |> Map.put("blocker",
                     "invalid review artifact (retries exhausted): #{reason}"
                   )

              updated_assignments = Map.put(state["assignments"], task_id, parked_assignment)
              new_state = Map.put(state, "assignments", updated_assignments) |> touch()

              {:error, reason, new_state}
            end
        end
    end
  end

  @spec integrate_candidate(map(), String.t(), keyword()) ::
          {:ok, map(), map()} | {:error, String.t(), map()}
  def integrate_candidate(state, task_id, opts \\ []) do
    assignment = get_in(state, ["assignments", task_id])

    cond do
      is_nil(assignment) ->
        {:error, "unknown assignment: #{task_id}", state}

      true ->
        with {:ok, ready_state} <- check_integration_readiness(state, assignment, opts),
             commit = Map.get(assignment["handoff"], "commit", assignment["candidate_commit"]),
             {:ok, locked_state} <- Integration.acquire_owner(ready_state, task_id, commit) do
          # Check gate
          checks =
            Map.get(assignment["ticket"], "required_checks", []) ++
              Map.get(assignment["ticket"], "integration_only_checks", [])

          candidate_path = Keyword.get(opts, :candidate_path, "/tmp/candidate-#{task_id}")
          runner_fn = Keyword.get(opts, :runner_fn)

          case Integration.run_gate_checks(candidate_path, checks, runner_fn) do
            :ok ->
              case Integration.promote_candidate(locked_state, assignment, opts) do
                {:ok, promoted_state, promoted_assignment} ->
                  {:ok, promoted_assignment, touch(promoted_state)}

                {:error, reason} ->
                  {:ok, failed_state, _failed_assignment} =
                    Integration.fail_integration(locked_state, assignment, reason)

                  {:error, reason, touch(failed_state)}
              end

            {:error, {:check_failed, cmd, code, out}} ->
              reason =
                "check failed: #{inspect(cmd)} (exit #{code}): #{String.slice(to_string(out), 0, 200)}"

              {:ok, failed_state, _failed_assignment} =
                Integration.fail_integration(locked_state, assignment, reason)

              {:error, reason, touch(failed_state)}
          end
        else
          {:error, :integration_busy} ->
            {:error, "integration pipeline is busy with another candidate", state}

          {:error, reason} ->
            {:ok, failed_state, _failed_assignment} =
              Integration.fail_integration(state, assignment, reason)

            {:error, reason, touch(failed_state)}
        end
    end
  end

  defp check_integration_readiness(state, assignment, opts) do
    case Integration.validate_readiness(state, assignment, opts) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec reset_pm_attempts(map(), map()) :: {:ok, map(), map()} | {:error, String.t()}
  def reset_pm_attempts(state, payload) when is_map(payload) do
    pm_state = Map.get(state, "pm", %{})
    accepted_rev = Map.get(state, "accepted_revision")

    case PM.reset_attempts(pm_state, payload, accepted_rev) do
      {:ok, record, updated_pm} ->
        new_state =
          state
          |> Map.put("pm", updated_pm)
          |> touch()

        {:ok, record, new_state}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp touch(state) do
    state
    |> Map.update("generation", 1, &(&1 + 1))
    |> Map.put("updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
  end
end
