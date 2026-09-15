defmodule PramanaFoundry.Transition do
  @moduledoc """
  Pure policy transitions from durable records to validated checkpoint-first intents.

  Rebuilds full coordinator state from event records, providing both a projection
  (for duplicate-prevention checks via `plan/2`) and the complete CoordState-compatible
  state map. This makes the event log the sole source of truth — in-memory state becomes
  a disposable cache rebuilt from the event stream.
  """

  alias PramanaFoundry.Coordinator.State, as: CoordState
  alias PramanaFoundry.Cleanup
  alias PramanaFoundry.Schema

  @roles ~w(developer reviewer pm)
  @authority_events ~w(assignment_admitted prompt_intent)

  @type assignment_identity :: {binary(), binary()}
  @type prompt_identity :: {binary(), binary(), binary()}

  @type projection :: %{
          assignments: %{optional(binary()) => assignment_identity()},
          prompt_intents: MapSet.t(prompt_identity()),
          events: [map()]
        }

  @type full_state :: %{projection: projection(), state: map()}
  @type intent :: %{checkpoint: map(), effects: [map()]}

  @doc """
  Rebuilds the full coordinator state (projection + CoordState-compatible map) from
  an ordered list of event records. Returns an error if any record is invalid or
  structurally inconsistent — for example, a `prompt_intent` for a never-admitted
  assignment.

  ## Events handled

  | Event | Effect on state |
  |---|---|
  | `ticket_enqueued` | Adds ticket to assignments (status: queued) and appends to queue |
  | `assignment_admitted` | Sets assignment status to dispatched, removes from queue |
  | `pane_created` | Records pane_id and agent_name on the assignment |
  | `launch_retried` | Re-enqueues and increments retry count |
  | `launch_parked` | Sets assignment status to parked with max retries reason |
  | `handoff_received` | Sets assignment status to handoff_received; auto approval is rejected |
  | `handoff_recovered` | Same as handoff_received (recovery-time alternative) |
  | `review_received` | Updates assignment to review_approved or re-queues for correction |
  | `integration_started` | Acquires integration owner lock |
  | `integration_completed` | Releases a legacy lock; success is retained only as an unverified claim |
  | `task_completed` | Updates assignment status based on outcome (completed/review/handoff_rejected/failed) |
  | `task_crashed` | Sets assignment status to crashed |
  | `cleanup_pending` | Retains an attributable outstanding cleanup obligation and capacity |
  | `cleanup_result` | Resolves only an exact obligation identity; otherwise keeps cleanup blocked |
  | `pm_proposal_created` | Records PM proposal state |
  | `prompt_intent` | Records prompt delivery identity (for idempotency) |
  """
  @spec rebuild([map()], keyword()) :: {:ok, full_state()} | {:error, map()}
  def rebuild(records, opts \\ [])

  def rebuild(records, opts) when is_list(records) do
    default_rev = Keyword.get(opts, :accepted_revision)
    initial_state = CoordState.new(accepted_revision: default_rev)

    initial = %{projection: empty_projection(), state: initial_state}

    with {:ok, result} <-
           Enum.reduce_while(records, {:ok, initial}, &apply_record/2) do
      state = touch_state(result.state)
      projection = %{result.projection | events: Enum.reverse(result.projection.events)}
      {:ok, %{projection: projection, state: state}}
    end
  end

  def rebuild(value, _opts), do: {:error, %{reason: :records_not_a_list, evidence: value}}

  @doc """
  Plans a side-effect (admit or prompt) against a projection, returning a
  checkpoint-first intent. The caller MUST persist the intent's checkpoint event
  before executing any effect.

  ## Actions

  - `{:admit, task_id, run_id, role, at}` — admits a queued assignment into dispatch
  - `{:prompt, task_id, run_id, role, at}` — delivers or reconciles a prompt

  Returns `{:ok, %{checkpoint: event, effects: [effect]}}` where effects may be
  `:deliver_prompt` (first time) or `:reconcile_prompt` (duplicate, replay-safe).
  """
  @spec plan(projection(), map()) :: {:ok, intent()} | {:error, term()}
  def plan(
        projection,
        %{action: :admit, task_id: task_id, run_id: run_id, role: role, at: at}
      )
      when is_binary(task_id) and is_binary(run_id) and role in @roles and is_binary(at) do
    identity = {run_id, role}

    case Map.get(projection.assignments, task_id) do
      ^identity ->
        {:error, :duplicate_assignment}

      nil ->
        checkpoint_intent("assignment_admitted", task_id, run_id, role, at, [])

      _other_identity ->
        {:error, :task_identity_mismatch}
    end
  end

  def plan(
        projection,
        %{action: :prompt, task_id: task_id, run_id: run_id, role: role, at: at}
      )
      when is_binary(task_id) and is_binary(run_id) and role in @roles and is_binary(at) do
    identity = {run_id, role}

    case Map.get(projection.assignments, task_id) do
      ^identity ->
        prompt_identity = {task_id, run_id, role}

        effects =
          if MapSet.member?(projection.prompt_intents, prompt_identity) do
            [%{type: :reconcile_prompt, task_id: task_id, run_id: run_id, role: role}]
          else
            [%{type: :deliver_prompt, task_id: task_id, run_id: run_id, role: role}]
          end

        checkpoint_intent("prompt_intent", task_id, run_id, role, at, effects)

      {^run_id, _admitted_role} ->
        {:error, :role_identity_mismatch}

      nil ->
        {:error, :unknown_assignment}

      _other_identity ->
        {:error, :run_identity_mismatch}
    end
  end

  def plan(_projection, _command), do: {:error, :invalid_command}

  # ── Internal ──

  defp empty_projection do
    %{assignments: %{}, prompt_intents: MapSet.new(), events: []}
  end

  defp apply_record(record, {:ok, result}) do
    try do
      with {:ok, validated} <- Schema.validate(:event, record),
           {:ok, projected} <- project(validated, result) do
        {:cont, {:ok, projected}}
      else
        {:error, reason} -> {:halt, {:error, %{reason: reason, evidence: record}}}
      end
    rescue
      error ->
        {:halt,
         {:error, %{reason: {:projection_exception, Exception.message(error)}, evidence: record}}}
    catch
      kind, reason ->
        {:halt,
         {:error, %{reason: {:projection_failure, kind, inspect(reason)}, evidence: record}}}
    end
  end

  # ── Event projection ──

  # Each `project/2` function updates BOTH the projection (for plan/2 idempotency)
  # and the state map (for full coordinator state recovery).

  defp project(
         %{
           "event" => "assignment_admitted",
           "task_id" => task_id,
           "run_id" => run_id,
           "role" => role
         } = event,
         result
       ) do
    identity = {run_id, role}

    with {:ok, proj} <- project_assignment(event, result.projection, identity) do
      state = result.state
      now = Map.get(event, "at", iso_now())
      checkout = get_in(event, ["attributes", "checkout"])
      assignment = get_in(state, ["assignments", task_id]) || %{}

      updated_assignment =
        assignment
        |> Map.put("task_id", task_id)
        |> Map.put("run_id", run_id)
        |> Map.put("role", role)
        |> Map.put("status", "dispatched")
        |> Map.put("dispatched_at", now)
        |> Map.put("launch_retries", 0)
        |> Map.put("error", nil)

      updated_assignment =
        if is_binary(checkout) do
          Map.put(updated_assignment, "pane_checkout", checkout)
        else
          updated_assignment
        end

      updated_queue = List.delete(state["queue"], task_id)
      updated_assignments = Map.put(state["assignments"], task_id, updated_assignment)

      new_state =
        state
        |> Map.put("assignments", updated_assignments)
        |> Map.put("queue", updated_queue)

      {:ok, %{result | projection: proj, state: new_state}}
    end
  end

  defp project(
         %{"event" => "prompt_intent", "task_id" => task_id, "run_id" => run_id, "role" => role} =
           event,
         result
       ) do
    identity = {run_id, role}

    case Map.get(result.projection.assignments, task_id) do
      ^identity ->
        proj = %{
          result.projection
          | prompt_intents: MapSet.put(result.projection.prompt_intents, {task_id, run_id, role}),
            events: [event | result.projection.events]
        }

        state =
          put_in(result.state, ["assignments", task_id, "status"], "prompting") ||
            result.state

        {:ok, %{result | projection: proj, state: state}}

      {^run_id, _admitted_role} ->
        projection_error(:role_identity_mismatch, event)

      nil ->
        projection_error(:unknown_assignment, event)

      _other_identity ->
        projection_error(:run_identity_mismatch, event)
    end
  end

  defp project(
         %{"event" => "ticket_enqueued", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    ticket = get_in(event, ["attributes", "ticket"]) || %{}
    now = Map.get(event, "at", iso_now())

    cond do
      Map.has_key?(ticket, "auto_approve") ->
        projection_error(:forbidden_auto_approve, event)

      Map.has_key?(state["assignments"], task_id) ->
        existing = state["assignments"][task_id]
        updated_assignment = Map.put(existing, "ticket", ticket)
        new_assignments = Map.put(state["assignments"], task_id, updated_assignment)
        new_state = Map.put(state, "assignments", new_assignments)

        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}

      true ->
        assignment = %{
          "ticket" => ticket,
          "task_id" => task_id,
          "status" => "queued",
          "queued_at" => now,
          "launch_retries" => 0,
          "error" => nil
        }

        updated_assignments = Map.put(state["assignments"], task_id, assignment)
        updated_queue = state["queue"] ++ [task_id]

        new_state =
          state
          |> Map.put("assignments", updated_assignments)
          |> Map.put("queue", updated_queue)

        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
    end
  end

  defp project(
         %{"event" => "ticket_re_enqueued", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])

    if is_map(assignment) do
      updated =
        assignment
        |> Map.put("status", "queued")
        |> Map.put("launch_retries", 0)
        |> Map.put("error", "stale_dispatch_recovered")

      updated_queue = state["queue"] ++ [task_id]

      new_state =
        state
        |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
        |> Map.put("queue", updated_queue)

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "pane_created", "task_id" => task_id} = event,
         result
       ) do
    pane_id = get_in(event, ["attributes", "pane_id"])
    agent_name = get_in(event, ["attributes", "agent_name"])
    cleanup_identity = get_in(event, ["attributes", "cleanup_identity"])
    presentation_identity = get_in(event, ["attributes", "presentation_identity"])
    execution_id = get_in(event, ["attributes", "execution_id"]) || event["run_id"]
    role = get_in(event, ["attributes", "role"]) || event["role"]

    state = result.state
    assignment = get_in(state, ["assignments", task_id])

    if is_map(assignment) do
      updated =
        assignment
        |> Map.put("pane_id", pane_id)
        |> Map.put("agent_name", agent_name)
        |> Map.put("cleanup_identity", cleanup_identity)
        |> Map.put("presentation_identity", presentation_identity)

      state_with_latest = put_in(state, ["assignments", task_id], updated)

      resource = %{
        "task_id" => task_id,
        "execution_id" => execution_id,
        "role" => role,
        "pane_id" => pane_id,
        "terminal_id" => get_in(cleanup_identity, ["terminal_id"]),
        "session" => get_in(cleanup_identity, ["session"]),
        "observed_session" => nil,
        "agent_name" => agent_name,
        "presentation_identity" => presentation_identity
      }

      resource =
        case get_in(event, ["attributes", "resource_id"]) do
          resource_id when is_binary(resource_id) -> Map.put(resource, "resource_id", resource_id)
          _missing -> resource
        end

      resource =
        case get_in(event, ["attributes", "verification_status"]) do
          status when is_binary(status) -> Map.put(resource, "verification_status", status)
          _missing -> resource
        end

      with {:ok, new_state} <- Cleanup.register_resource(state_with_latest, resource) do
        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      end
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "launch_retried", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    retries = get_in(event, ["attributes", "retry_count"]) || 1
    error = get_in(event, ["attributes", "error_reason"]) || "launch_retried"

    if is_map(assignment) do
      new_state =
        if Cleanup.assignment_outstanding?(assignment) do
          state
          |> Cleanup.preserve_work_status(task_id, "queued")
          |> put_in(["assignments", task_id, "error"], error)
        else
          updated =
            assignment
            |> Map.put("status", "queued")
            |> Map.put("launch_retries", retries)
            |> Map.put("error", error)

          state
          |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
          |> Map.put("queue", state["queue"] ++ [task_id])
        end

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "launch_parked", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    retries = get_in(event, ["attributes", "retry_count"]) || 1
    error = get_in(event, ["attributes", "error_reason"]) || "max_launch_retries"

    if is_map(assignment) do
      new_state =
        state
        |> Cleanup.preserve_work_status(task_id, "parked")
        |> put_in(["assignments", task_id, "launch_retries"], retries)
        |> put_in(["assignments", task_id, "error"], error)

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "handoff_received", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    handoff = get_in(event, ["attributes", "handoff"])
    rejected = get_in(event, ["attributes", "rejected"]) || false

    if get_in(event, ["attributes", "auto_approved"]) do
      projection_error(:forbidden_auto_approve, event)
    else
      project_handoff(event, result, state, assignment, handoff, rejected, task_id)
    end
  end

  defp project(
         %{"event" => "handoff_recovered", "task_id" => _task_id} = event,
         result
       ) do
    # Same semantics as handoff_received
    project(Map.put(event, "event", "handoff_received"), result)
  end

  defp project(
         %{"event" => "review_received", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    verdict = get_in(event, ["attributes", "verdict"]) || "correction_needed"
    correction_count = get_in(event, ["attributes", "correction_count"]) || 0
    rejected = get_in(event, ["attributes", "rejected"]) || false
    now = Map.get(event, "at", iso_now())

    if is_map(assignment) do
      if rejected do
        # Review was rejected at runtime — restore retry or parked state
        reason = get_in(event, ["attributes", "reason"]) || "invalid_review"
        review_retry = get_in(event, ["attributes", "review_retry_count"]) || 0

        updated =
          if review_retry > 0 do
            # Review retry: return to handoff_received, keep handoff intact
            assignment
            |> Map.put("status", "handoff_received")
            |> Map.put("review_retries", review_retry)
            |> Map.put(
              "error",
              "invalid review (retry #{review_retry}/X): #{reason}"
            )
          else
            assignment
            |> Map.put("status", "parked")
            |> Map.put("blocker", "invalid review artifact: #{reason}")
          end

        new_state = put_in(state, ["assignments", task_id], updated)
        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      else
        updated =
          case verdict do
            "approved" ->
              assignment
              |> Map.put("status", "review_approved")
              |> Map.put("review_received_at", now)
              |> Map.put("correction_count", correction_count)

            "correction_needed" ->
              correction_history = Map.get(assignment, "correction_history", [])

              record = %{
                "round" => correction_count + 1,
                "at" => now
              }

              assignment
              |> Map.put("status", "queued")
              |> Map.put("correction_count", correction_count + 1)
              |> Map.put("correction_history", correction_history ++ [record])

            "changes_requested" ->
              correction_history = Map.get(assignment, "correction_history", [])

              record = %{
                "round" => correction_count + 1,
                "at" => now
              }

              assignment
              |> Map.put("status", "queued")
              |> Map.put("correction_count", correction_count + 1)
              |> Map.put("correction_history", correction_history ++ [record])
          end

        new_state =
          if verdict == "correction_needed" or verdict == "changes_requested" do
            updated_queue = state["queue"] ++ [task_id]

            state
            |> put_in(["assignments", task_id], updated)
            |> Map.put("queue", updated_queue)
          else
            put_in(state, ["assignments", task_id], updated)
          end

        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      end
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "integration_started", "task_id" => task_id} = event,
         result
       ) do
    commit = get_in(event, ["attributes", "commit"])

    new_state =
      put_in(result.state, ["integration"], %{"owner" => task_id, "candidate" => commit})

    proj = %{result.projection | events: [event | result.projection.events]}
    {:ok, %{result | projection: proj, state: new_state}}
  end

  defp project(
         %{"event" => "integration_completed", "task_id" => task_id} = event,
         result
       ) do
    outcome = get_in(event, ["attributes", "outcome"]) || "failed"
    state = result.state
    assignment = get_in(state, ["assignments", task_id])

    integration = Map.get(state, "integration", %{})

    new_state =
      put_in(
        state,
        ["integration"],
        Map.merge(integration, %{"owner" => nil, "candidate" => nil})
      )

    new_state =
      if outcome == "succeeded" do
        commit = get_in(event, ["attributes", "commit"])

        claim = %{
          "task_id" => task_id,
          "commit" => commit || get_in(assignment, ["candidate_commit"]),
          "at" => Map.get(event, "at"),
          "outcome" => "succeeded",
          "verification" => "legacy_unverified"
        }

        claims = Map.get(integration, "legacy_unverified_claims", [])

        new_state
        |> put_in(["integration", "legacy_unverified_claims"], claims ++ [claim])
        |> put_in(["assignments", task_id, "status"], "integration_unverified")
        |> put_in(["assignments", task_id, "legacy_unverified_integration_claim"], claim)
      else
        reason = get_in(event, ["attributes", "reason"]) || "integration_failed"

        new_state
        |> put_in(["assignments", task_id, "status"], "parked")
        |> put_in(["assignments", task_id, "error"], reason)
      end

    proj = %{result.projection | events: [event | result.projection.events]}
    {:ok, %{result | projection: proj, state: new_state}}
  end

  defp project(
         %{"event" => "task_completed", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    reason = get_in(event, ["attributes", "reason"]) || inspect(:normal)

    if is_map(assignment) do
      status = infer_completed_status(reason)
      new_state = Cleanup.preserve_work_status(state, task_id, status)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "task_crashed", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    reason = get_in(event, ["attributes", "reason"]) || "unknown"

    if is_map(assignment) do
      new_state =
        state
        |> Cleanup.preserve_work_status(task_id, "crashed")
        |> put_in(["assignments", task_id, "error"], "agent_crashed: #{reason}")

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "assignment_parked", "task_id" => task_id} = event,
         result
       ) do
    state = result.state
    assignment = get_in(state, ["assignments", task_id])
    reason = get_in(event, ["attributes", "reason"]) || "parked"
    error_reason = get_in(event, ["attributes", "error_reason"]) || reason

    if is_map(assignment) do
      updated =
        assignment
        |> Map.put("status", "parked")
        |> Map.put("blocker", reason)
        |> Map.put("error", error_reason)

      new_state = put_in(state, ["assignments", task_id], updated)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(%{"event" => "tick_processed"} = event, result) do
    proj = %{result.projection | events: [event | result.projection.events]}
    {:ok, %{result | projection: proj}}
  end

  defp project(%{"event" => "cleanup_pending"} = event, result) do
    with {:ok, state} <- Cleanup.apply_pending(result.state, event["attributes"] || %{}) do
      projection = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: projection, state: state}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp project(%{"event" => "cleanup_result"} = event, result) do
    with {:ok, state} <- Cleanup.apply_result(result.state, event["attributes"] || %{}) do
      projection = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: projection, state: state}}
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp project(
         %{"event" => "pm_proposal_created", "task_id" => _task_id} = event,
         result
       ) do
    state = result.state
    proposals = get_in(event, ["attributes", "proposals"]) || []
    pm_state = Map.get(state, "pm", %{}) |> Map.put("last_proposal", proposals)
    new_state = Map.put(state, "pm", pm_state)
    proj = %{result.projection | events: [event | result.projection.events]}
    {:ok, %{result | projection: proj, state: new_state}}
  end

  # Events that require authority identity but lack it — checked before catch-all
  defp project(%{"event" => event} = record, _result) when event in @authority_events,
    do: projection_error(:missing_authority_identity, record)

  defp project(%{"event" => _event} = event, _result),
    do: projection_error(:unknown_event_type, event)

  # ── Helpers ──

  defp project_handoff(event, result, state, assignment, handoff, rejected, task_id) do
    if is_map(assignment) do
      if rejected do
        reason = get_in(event, ["attributes", "reason"]) || "invalid_handoff"
        retries = Map.get(assignment, "handoff_retries", 0)

        updated =
          assignment
          |> Map.put("status", "queued")
          |> Map.put("handoff_retries", retries + 1)
          |> Map.put("error", "invalid handoff: #{reason}")

        new_state =
          state
          |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
          |> Map.put("queue", state["queue"] ++ [task_id])

        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      else
        now = Map.get(event, "at", iso_now())

        commit =
          case handoff do
            %{"commit" => candidate} when is_binary(candidate) -> candidate
            _ -> assignment["candidate_commit"]
          end

        status =
          if is_map(handoff) && Map.get(handoff, "status") == "blocked",
            do: "blocked",
            else: "handoff_received"

        updated =
          assignment
          |> Map.put("handoff", handoff || %{})
          |> Map.put("candidate_commit", commit)
          |> Map.put("status", status)
          |> Map.put("handoff_received_at", now)

        new_state = put_in(state, ["assignments", task_id], updated)
        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      end
    else
      {:ok,
       %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project_assignment(event, projection, identity) do
    case Map.get(projection.assignments, event["task_id"]) do
      nil ->
        {:ok,
         %{
           projection
           | assignments: Map.put(projection.assignments, event["task_id"], identity),
             events: [event | projection.events]
         }}

      ^identity ->
        # Same-identity admission is idempotently projectable. Preserve the
        # authoritative record while retaining the already-established identity.
        {:ok, %{projection | events: [event | projection.events]}}

      _other_identity ->
        # Different identity: supersede with the new identity.
        # This happens when a task is re-enqueued after a launch failure and
        # gets admitted again with a fresh run_id. The latest admit wins.
        {:ok,
         %{
           projection
           | assignments: Map.put(projection.assignments, event["task_id"], identity),
             events: [event | projection.events]
         }}
    end
  end

  defp infer_completed_status(reason) when is_binary(reason) do
    cond do
      String.contains?(reason, "handoff") and String.contains?(reason, ":ok") ->
        "review"

      String.contains?(reason, "handoff") and String.contains?(reason, "error") ->
        "handoff_rejected"

      String.contains?(reason, ":timeout") or String.contains?(reason, "timeout") ->
        "timed_out"

      true ->
        "completed"
    end
  end

  defp infer_completed_status(_reason), do: "completed"

  defp projection_error(reason, event), do: {:error, %{reason: reason, evidence: event}}

  defp checkpoint_intent(event, task_id, run_id, role, at, effects) do
    checkpoint = %{
      "schema_version" => 1,
      "event" => event,
      "at" => at,
      "task_id" => task_id,
      "run_id" => run_id,
      "role" => role,
      "attributes" => %{},
      "evidence" => %{}
    }

    with {:ok, validated} <-
           Schema.validate(:event, checkpoint, task_id: task_id, run_id: run_id, role: role) do
      {:ok, %{checkpoint: validated, effects: effects}}
    end
  end

  defp touch_state(state) do
    state
    |> Map.update("generation", 1, &(&1 + 1))
    |> Map.put("updated_at", iso_now())
  end

  defp iso_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end
end
