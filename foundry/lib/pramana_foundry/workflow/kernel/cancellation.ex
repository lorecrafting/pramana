defmodule PramanaFoundry.Workflow.Kernel.Cancellation do
  @moduledoc """
  Cancellation request and finalisation. Generic: the one software word here,
  `after_integration`, is R4's own cancel row, which names integration as the effect
  a cancel may have raced.
  """

  import PramanaFoundry.Workflow.Kernel.Executions, only: [open_executions: 1]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [require_no_active_attempt: 1, terminal_ticket_phases: 0]

  # R4: "nonterminal ticket; cancel requested" — an orthogonal control that holds phase and
  # evidence while issued effects reconcile. It is not a ticket phase.
  def do_transition("cancellation_requested", ticket, _event, _state) do
    if ticket["phase"] in terminal_ticket_phases() do
      {:error, :ticket_terminal}
    else
      {:ok, Map.put(ticket, "cancel_requested", true)}
    end
  end

  # R4: "cancel_requested; every owned session AND non-session claim terminal, cleanup
  # reconciled". Finalisation does not itself terminalise the attempt — attempt_settled
  # does — so it requires that to have happened already.
  def do_transition("cancellation_finalized", ticket, event, _state) do
    with :ok <- require_cancel_requested(ticket),
         :ok <- require_no_active_attempt(ticket),
         :ok <- require_all_executions_closed(ticket) do
      case event["payload"]["disposition"] do
        "cancelled" ->
          if integration_occurred?(ticket),
            do: {:error, :integration_occurred},
            else: {:ok, Map.put(ticket, "phase", "cancelled")}

        "after_integration" ->
          if integration_occurred?(ticket),
            do: {:ok, Map.put(ticket, "phase", "integrated")},
            else: {:error, :no_integration_to_finalize}

        _ ->
          {:error, :invalid_cancellation_disposition}
      end
    end
  end

  # R4's cancel row is a conditional, and the kernel read only its second half: "If no
  # integration occurred: cancelled ticket ...; If integration occurred: integrated and
  # cancel_finalized(after_integration)". Nothing tested the condition, so
  # after_integration produced an integrated ticket with no attempt, candidate, check,
  # review or ref receipt at all — blocker B1's headline counterexample, reachable in
  # three events from an empty state. No walk could see it: the prober proposes only the
  # `cancelled` disposition, which is finding 17's type-level blind spot.
  defp integration_occurred?(ticket),
    do:
      Elixir.Enum.any?(ticket["attempts"], fn {_id, attempt} ->
        is_binary(attempt["ref_receipt_id"])
      end)

  # R4: "every owned session AND non-session claim terminal, cleanup reconciled". Only
  # expressible now that an execution can be closed after its attempt settles.
  defp require_all_executions_closed(ticket) do
    if open_executions(ticket) == [], do: :ok, else: {:error, :executions_not_closed}
  end

  def require_cancel_requested(ticket),
    do: if(ticket["cancel_requested"], do: :ok, else: {:error, :cancel_not_requested})
end
