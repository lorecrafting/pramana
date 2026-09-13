defmodule PramanaFoundry.Transition do
  @moduledoc """
  Pure policy transitions from durable records to validated checkpoint-first intents.

  Rebuilds full coordinator state from event records, providing both a projection
  (for duplicate-prevention checks via `plan/2`) and the complete CoordState-compatible
  state map. This makes the event log the sole source of truth — in-memory state becomes
  a disposable cache rebuilt from the event stream.
  """

  alias PramanaFoundry.Coordinator.State, as: CoordState
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
  | `handoff_received` | Sets assignment status to handoff_received with candidate commit |
  | `handoff_recovered` | Same as handoff_received (recovery-time alternative) |
  | `review_received` | Updates assignment to review_approved or re-queues for correction |
  | `integration_started` | Acquires integration owner lock |
  | `integration_completed` | Releases integration lock; updates accepted_revision on success |
  | `task_completed` | Updates assignment status based on outcome (completed/review/handoff_rejected/failed) |
  | `task_crashed` | Sets assignment status to crashed |
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
    with {:ok, validated} <- Schema.validate(:event, record),
         {:ok, projected} <- project(validated, result) do
      {:cont, {:ok, projected}}
    else
      {:error, _reason} ->
        # Skip invalid or unprojectable events rather than halting rebuild.
        # This makes the system resilient to one-off corrupt events or events
        # from a future schema version that don't affect state recovery.
        {:cont, {:ok, result}}
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

    # If this task_id already exists, update the ticket data but don't re-queue
    if Map.has_key?(state["assignments"], task_id) do
      existing = state["assignments"][task_id]
      updated_assignment = Map.put(existing, "ticket", ticket)
      new_assignments = Map.put(state["assignments"], task_id, updated_assignment)
      new_state = Map.put(state, "assignments", new_assignments)

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
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
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "pane_created", "task_id" => task_id} = event,
         result
       ) do
    pane_id = get_in(event, ["attributes", "pane_id"])
    agent_name = get_in(event, ["attributes", "agent_name"])

    state = result.state
    assignment = get_in(state, ["assignments", task_id])

    if is_map(assignment) do
      updated =
        assignment
        |> Map.put("pane_id", pane_id)
        |> Map.put("agent_name", agent_name)

      new_state = put_in(state, ["assignments", task_id], updated)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
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
      updated =
        assignment
        |> Map.put("status", "queued")
        |> Map.put("launch_retries", retries)
        |> Map.put("error", error)

      updated_queue = state["queue"] ++ [task_id]

      new_state =
        state
        |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
        |> Map.put("queue", updated_queue)

      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
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
      updated =
        assignment
        |> Map.put("status", "parked")
        |> Map.put("launch_retries", retries)
        |> Map.put("error", error)

      new_state = put_in(state, ["assignments", task_id], updated)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
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

    if is_map(assignment) do
      if rejected do
        # Handoff was rejected at runtime — re-enqueue with retry budget
        reason = get_in(event, ["attributes", "reason"]) || "invalid_handoff"
        retries = Map.get(assignment, "handoff_retries", 0)
        updated =
          assignment
          |> Map.put("status", "queued")
          |> Map.put("handoff_retries", retries + 1)
          |> Map.put("error", "invalid handoff: #{reason}")

        updated_queue = state["queue"] ++ [task_id]
        new_state =
          state
          |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
          |> Map.put("queue", updated_queue)
        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      else
        # Handoff was accepted
        now = Map.get(event, "at", iso_now())
        commit = case handoff do
          %{"commit" => c} when is_binary(c) -> c
          _ -> assignment["candidate_commit"]
        end

        status = cond do
          is_map(handoff) && Map.get(handoff, "status") == "blocked" -> "blocked"
          get_in(event, ["attributes", "auto_approved"]) -> "review_approved"
          true -> "handoff_received"
        end

        updated =
          assignment
          |> Map.put("handoff", handoff || %{})
          |> Map.put("candidate_commit", commit)
          |> Map.put("status", status)
          |> Map.put("handoff_received_at", now)

        # Restore synthetic review for auto_approved handoffs
        updated = if get_in(event, ["attributes", "auto_approved"]) do
          Map.put(updated, "review", %{
            "verdict" => "approved",
            "findings" => [],
            "checks" => get_in(handoff, ["checks"]) || [],
            "remaining_risks" => get_in(handoff, ["remaining_risks"]) || [],
            "commit" => commit,
            "auto_approved" => true
          })
        else
          updated
        end

        new_state = put_in(state, ["assignments", task_id], updated)
        proj = %{result.projection | events: [event | result.projection.events]}
        {:ok, %{result | projection: proj, state: new_state}}
      end
    else
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
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
            |> Map.put("error",
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
          end

        new_state =
          if verdict == "correction_needed" do
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
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(
         %{"event" => "integration_started", "task_id" => task_id} = event,
         result
       ) do
    commit = get_in(event, ["attributes", "commit"])
    new_state = put_in(result.state, ["integration"], %{"owner" => task_id, "candidate" => commit})
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

    new_state =
      state
      |> put_in(["integration"], %{"owner" => nil, "candidate" => nil})

    new_state =
      if outcome == "succeeded" do
        commit = get_in(event, ["attributes", "commit"])
        revision = commit || get_in(assignment, ["candidate_commit"]) || state["accepted_revision"]

        new_state
        |> put_in(["accepted_revision"], revision)
        |> put_in(["assignments", task_id, "status"], "integrated")
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
      updated = Map.put(assignment, "status", status)
      new_state = put_in(state, ["assignments", task_id], updated)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
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
      updated =
        assignment
        |> Map.put("status", "crashed")
        |> Map.put("error", "agent_crashed: #{reason}")

      new_state = put_in(state, ["assignments", task_id], updated)
      proj = %{result.projection | events: [event | result.projection.events]}
      {:ok, %{result | projection: proj, state: new_state}}
    else
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
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
      {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
    end
  end

  defp project(%{"event" => "tick_processed"} = event, result) do
    proj = %{result.projection | events: [event | result.projection.events]}
    {:ok, %{result | projection: proj}}
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

  # Catch-all: unknown events are still recorded in the event list
  # but don't mutate the projection or state.
  defp project(%{"event" => _event} = event, result) do
    {:ok, %{result | projection: %{result.projection | events: [event | result.projection.events]}}}
  end

  # ── Helpers ──

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
        # Same identity is a true duplicate — return event duplication error
        projection_error(:duplicate_assignment, event)

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
      String.contains?(reason, "handoff") and String.contains?(reason, ":ok") -> "review"
      String.contains?(reason, "handoff") and String.contains?(reason, "error") -> "handoff_rejected"
      String.contains?(reason, ":timeout") or String.contains?(reason, "timeout") -> "timed_out"
      true -> "completed"
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