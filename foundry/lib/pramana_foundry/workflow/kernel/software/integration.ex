defmodule PramanaFoundry.Workflow.Kernel.Software.Integration do
  @moduledoc """
  Software workflow: integration planning, non-start settlement and ref receipt.
  """

  alias PramanaFoundry.Workflow.Kernel.Execution

  import PramanaFoundry.Workflow.Kernel.Control, only: [require_no_pending_cancel: 1]

  import PramanaFoundry.Workflow.Kernel.Executions,
    only: [
      add_execution: 3,
      close_execution: 4,
      consume_infrastructure_ordinal: 2,
      executions: 1,
      require_execution: 3
    ]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [
      active_attempt: 1,
      require_active_attempt: 2,
      require_phase: 2,
      update_active_attempt: 2
    ]

  # R4: "ready_to_integrate; current base/evidence/policy valid".
  def do_transition("integration_planned", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(ready_to_integrate integrating)),
         :ok <- require_no_ref_receipt(ticket),
         :ok <- require_issuer_terminated(ticket),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_no_pending_cancel(ticket),
         {:ok, ticket} <- add_execution(ticket, event["payload"], "integration") do
      {:ok,
       ticket
       |> Map.put("phase", "integrating")
       |> update_active_attempt(&Map.put(&1, "phase", "integrating"))}
    end
  end

  # R4a integration-worker row: preserve the phase and verified inputs, infer no ref
  # receipt.
  def do_transition("integration_settled", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(integrating)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_no_ref_receipt(ticket) do
      with {:ok, ticket} <-
             close_execution(
               ticket,
               event["payload"]["attempt_id"],
               event["payload"]["execution_id"],
               ~w(integration)
             ) do
        {:ok,
         ticket
         |> Map.put("phase", "ready_to_integrate")
         |> update_active_attempt(&Map.put(&1, "phase", "ready_to_integrate"))
         |> consume_infrastructure_ordinal("integration")}
      end
    end
  end

  # R4: "integrating; successful ref receipt and prior role/check workers closed" →
  # integrated ticket. The terminal integrated attempt is set by attempt_settled.
  def do_transition("integration_recorded", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(integrating)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_no_ref_receipt(ticket),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_workers_closed(ticket) do
      # Records the receipt only. Setting the ticket integrated here was this module's own
      # rule ("evidence events never terminalise") broken in one place, and it made R4's
      # row unsatisfiable: the terminal-ticket guard then refused the attempt_settled that
      # the same row requires, so the ticket ended integrated with a live attempt. Found
      # by the reachability walk, which could never seal an integrated attempt.
      case payload["outcome"] do
        "ref_created" ->
          {:ok,
           update_active_attempt(
             ticket,
             &Map.put(&1, "ref_receipt_id", payload["ref_receipt_id"])
           )}

        # R4: "Same phase with bounded integration-effect retry after old issuer
        # termination". The ticket stays integrating; integration_planned accepts that
        # phase once the old issuer's execution is closed, which is what "after old issuer
        # termination" means. Before this the only exits from integrating were the
        # non-start settlement, which is semantically wrong once a start occurred, and
        # attempt_settled — so the row was unexpressible.
        "no_ref_change" ->
          {:ok, ticket}

        # R4: "or blocked(integration_failure)". Carried on the row's own event, the way
        # freeze_failed carries its blocked alternative, rather than borrowing the PM park.
        # The resume target is this row's own "Same phase ... after old issuer termination",
        # not `ready_to_integrate`. It stored `ready_to_integrate` while leaving the attempt
        # at `integrating`, so `ticket_unblocked` produced a pair `@legal_pairs` calls a
        # violation. Moving the attempt instead would have matched the pair and broken
        # something worse: `require_settlement_source`'s `superseded_base` branch tests
        # issuance only while the attempt is `integrating`, on the premise that from
        # `ready_to_integrate` no integration effect exists yet, and an attempt parked there
        # holding a running integration execution falsifies it. The block does not un-issue
        # the effect, so neither side of the pair should pretend it does.
        "infrastructure_failed" ->
          {:ok,
           ticket
           |> Map.put("phase", "blocked")
           |> Map.put("reason", "integration_failure")
           |> Map.put("resume_phase", "integrating")}

        _ ->
          {:error, :invalid_integration_outcome}
      end
    end
  end

  # R4: "integrated ticket; terminal integrated attempt ... **Exit notifications cannot
  # overwrite this**". The converse guard on attempt_settled was only half the row: it
  # stopped a ref-holding attempt settling `failed`, and left every other way to contradict
  # a recorded ref open. A second ref_created overwrote the first receipt; a non-start
  # settlement returned the ticket to ready_to_integrate still holding one, after which the
  # attempt could not settle at all; and infrastructure_failed blocked a ticket that had
  # already integrated. Once a receipt exists the row is decided, so no further integration
  # event may be recorded, planned or settled.
  defp require_no_ref_receipt(ticket),
    do:
      if(is_binary(active_attempt(ticket)["ref_receipt_id"]),
        do: {:error, :ref_receipt_recorded},
        else: :ok
      )

  # R4: "Same phase with bounded integration-effect retry **after old issuer termination**".
  # A retry from `integrating` may only be planned once the previous integration execution
  # is closed; from ready_to_integrate there is no previous issuer to terminate.
  defp require_issuer_terminated(ticket) do
    open? =
      Elixir.Enum.any?(executions(active_attempt(ticket)), fn {_id, %Execution{} = execution} ->
        execution.role == "integration" and execution.lifecycle != "closed"
      end)

    if open?, do: {:error, :issuer_not_terminated}, else: :ok
  end

  # R4: "successful ref receipt and prior role/check workers closed".
  defp require_workers_closed(ticket) do
    executions = executions(active_attempt(ticket))

    closed? =
      Elixir.Enum.all?(executions, fn {_id, %Execution{} = execution} ->
        execution.role == "integration" or execution.lifecycle == "closed"
      end)

    if closed?, do: :ok, else: {:error, :workers_not_closed}
  end
end
