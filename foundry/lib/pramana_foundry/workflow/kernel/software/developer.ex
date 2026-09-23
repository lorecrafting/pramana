defmodule PramanaFoundry.Workflow.Kernel.Software.Developer do
  @moduledoc """
  Software workflow: the developer's result - frozen candidate, blocked or partial
  result, freeze failure, rejected submission - and its write-once sealed result.
  """

  alias PramanaFoundry.Workflow.Kernel.{Execution, Plan}

  import PramanaFoundry.Workflow.Kernel.Executions,
    only: [executions: 1, open_role_executions: 2]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [
      active_attempt: 1,
      attempt: 2,
      require_active_attempt: 2,
      require_attempt_phase: 2,
      require_phase: 2,
      update_active_attempt: 2,
      update_attempt: 3
    ]

  # ── decide/3 ────────────────────────────────────────────────────────────────────
  #
  # The developer's commands. The role travels in the payload of a role-free command type,
  # so subcommit 3's reviewer claims the same types with its own role.

  def decides?(%{"type" => type, "payload" => %{"role" => "developer"}})
      when type in ~w(settle_nonstart),
      do: true

  def decides?(_command), do: false

  # R4a.01: a proved non-start settles the claim and closes the execution it names, and the
  # protected infrastructure limit - never read here - selects between a bounded retry
  # (queued, attempt retained) and `blocked(developer_launch_infrastructure)`. Unconditional
  # with respect to control: under Q1 the successor is the next launch, not this settle, so
  # pause, drain and cancel are decided there. The settled execution is the active attempt's
  # open developer, the only one `launch_planned` lets exist; with none, the reducer's
  # refusal comes out of the dry run.
  def decide(state, %{"type" => "settle_nonstart"} = command, facts) do
    ticket_id = command["target_ids"]["ticket_id"]
    ticket = state["tickets"][ticket_id]

    state
    |> Plan.nonstart(command["command_id"], %{
      "settled" => "launch_settled",
      "operation" => is_map(facts) && facts["settle_claim"],
      "ticket_id" => ticket_id,
      "attempt_id" => ticket["active_attempt_id"],
      "execution_id" => List.first(open_role_executions(ticket, "developer")),
      "reason" => "developer_launch_infrastructure",
      "resume_phase" => "developing"
    })
    |> Plan.decision(command)
  end

  # R4: "developing; success artifact validates and freezes" — attempt candidate_frozen,
  # ticket awaiting_review, productive generation sealed.
  def do_transition("artifact_frozen", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(active)),
         :ok <- require_running_developer(ticket) do
      {:ok,
       ticket
       |> Map.put("phase", "awaiting_review")
       |> update_active_attempt(fn attempt ->
         attempt
         |> Map.put("phase", "candidate_frozen")
         |> Map.put("candidate_id", payload["candidate_id"])
         |> Map.put("sealed_generation", payload["sealed_generation"])
       end)
       |> seal_developer_result(payload["attempt_id"], "valid")}
    end
  end

  # R4: "developing; valid blocked/partial result" — blocked ticket, no review. The attempt
  # is terminalised by attempt_settled, not here.
  def do_transition("artifact_blocked", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(active)),
         :ok <- require_blocked_result(payload["result"]) do
      {:ok,
       ticket
       |> Map.put("phase", "blocked")
       |> Map.put("reason", payload["reason"])
       |> Map.put("resume_phase", "developing")
       |> seal_developer_result(payload["attempt_id"], payload["result"])}
    end
  end

  # R4: "developing; freeze/import infrastructure failure before valid candidate" —
  # submitted bytes are retained and no frozen result is inferred, so the candidate stays
  # absent and the attempt stays active.
  def do_transition("freeze_failed", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(active)) do
      case event["payload"]["disposition"] do
        "retry" ->
          {:ok, ticket}

        "blocked" ->
          {:ok,
           ticket
           |> Map.put("phase", "blocked")
           |> Map.put("reason", event["payload"]["reason"])
           |> Map.put("resume_phase", "developing")}

        "unknown" ->
          {:ok, ticket}

        _ ->
          {:error, :invalid_freeze_disposition}
      end
    end
  end

  # R4: "any open submission phase; malformed result | **Durable rejected submission, charge
  # one validation action**; further submission allowed only while **stream open** and
  # budget remains; exhaustion closes execution and exhausts ticket." The validation action
  # itself is charged in the R5 ledger, which is not the kernel's to write; the event moves
  # no ticket phase.
  #
  # This once accepted the event and changed nothing, so there was no durable record to
  # charge against and the row was unimplementable - the enumeration created the event for
  # exactly this reason and then the reducer dropped it. The charge is recorded on the
  # attempt (`rejected_submissions`); the budget it is charged against is protected
  # allocation, so exhaustion arrives as attempt_settled(exhausted) rather than being derived
  # here.
  def do_transition("submission_rejected", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing reviewing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_open_submission_stream(ticket) do
      {:ok,
       update_active_attempt(ticket, &Map.update!(&1, "rejected_submissions", fn n -> n + 1 end))}
    end
  end

  # R4: "Execution result | Separate write-once sealed result: valid, blocked, partial,
  # invalid, none". The field was declared in the state and never written by any event, so
  # a declared entity state had no producer — the same class of gap as the codec's
  # unproduced output kinds, one level up. Each submission-evidence row seals the
  # developer execution's result, and the seal is write-once because R4 says so.
  def seal_developer_result(ticket, attempt_id, result) do
    executions = executions(attempt(ticket, attempt_id))

    case Elixir.Enum.find(executions, fn {_id, %Execution{} = execution} ->
           execution.role == "developer" and is_nil(execution.result)
         end) do
      {execution_id, _execution} ->
        update_attempt(
          ticket,
          attempt_id,
          fn a -> update_in(a, ["executions", execution_id], &%{&1 | result: result}) end
        )

      nil ->
        ticket
    end
  end

  # "further submission allowed only while stream **open**". Once the broker has sealed the
  # stream, a later arrival is late evidence: R4a says messages after sealing are "never
  # silently attached to a new attempt", so they cannot be charged as a fresh submission
  # either.
  defp require_open_submission_stream(ticket) do
    open? =
      Elixir.Enum.any?(executions(active_attempt(ticket)), fn {_id, %Execution{} = execution} ->
        execution.role in ~w(developer reviewer) and is_nil(execution.sealed_sequence) and
          execution.lifecycle != "closed"
      end)

    if open?, do: :ok, else: {:error, :submission_stream_sealed}
  end

  # R4's freeze row is "developing; success artifact validates and freezes" - a developer
  # must actually have been running to produce one. Without this a ticket resumed to
  # developing could freeze a candidate with no developer execution open at all.
  defp require_running_developer(ticket) do
    running? =
      Elixir.Enum.any?(executions(active_attempt(ticket)), fn {_id, %Execution{} = execution} ->
        execution.role == "developer" and execution.lifecycle != "closed"
      end)

    if running?, do: :ok, else: {:error, :no_running_developer}
  end

  # R4's row is "valid blocked/partial result", which are two of the five sealed result
  # values; the other three are produced by their own rows.
  defp require_blocked_result(result),
    do: if(result in ~w(blocked partial), do: :ok, else: {:error, :invalid_blocked_result})
end
