defmodule PramanaFoundry.Workflow.Kernel.Software.Checks do
  @moduledoc """
  Software workflow: check and build workers against a frozen candidate.
  """

  import PramanaFoundry.Workflow.Kernel.Control,
    only: [require_boolean: 1, require_no_pending_cancel: 1]

  import PramanaFoundry.Workflow.Kernel.Executions,
    only: [add_execution: 3, close_execution: 4, consume_infrastructure_ordinal: 2]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [
      active_attempt: 1,
      require_active_attempt: 2,
      require_attempt_phase: 2,
      require_phase: 2,
      update_active_attempt: 2
    ]

  alias PramanaFoundry.Workflow.Kernel.State

  # R4: "candidate_frozen; developer closed, check capacity eligible" — checking attempt,
  # awaiting_review ticket, immutable candidate retained. Requiring developer closure is
  # B2's second named defect: without it the row-11 check route was unschedulable.
  def do_transition("checks_started", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(awaiting_review)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(candidate_frozen)),
         :ok <- require_developer_closed(ticket),
         :ok <- require_boolean(event["payload"]["policy_empty"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
         attempt
         |> Map.put("phase", "checking")
         |> Map.put("policy_empty_checks", event["payload"]["policy_empty"])
         |> then(&maybe_finish_checks/1)
       end)}
    end
  end

  def do_transition("check_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(checking)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_no_pending_cancel(ticket),
         {:ok, ticket} <-
           add_check(ticket, payload["check_id"], payload["authority"]["execution_id"]),
         {:ok, ticket} <- add_execution(ticket, payload, "check") do
      {:ok, ticket}
    end
  end

  # R4a check-worker row: preserve the candidate and its phase, infer no check receipt.
  def do_transition("check_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(checking)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_check(ticket, payload["check_id"]),
         # A check receipt is a write-once sealed result, and R4's integration row wants
         # "all mandatory check receipts passed". Deleting a check that had already
         # recorded `passed` let the attempt reach awaiting_review with a mandatory check
         # simply absent - which `require_checks_passed` cannot see, since it folds over
         # the checks that are still there.
         :ok <- require_check_unsettled(ticket, payload["check_id"]),
         :ok <- require_check_execution(ticket, payload["check_id"], payload["execution_id"]) do
      with {:ok, ticket} <-
             close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(check)) do
        {:ok,
         ticket
         |> update_active_attempt(fn attempt ->
           update_in(attempt, ["checks"], &Map.delete(&1, payload["check_id"]))
         end)
         |> consume_infrastructure_ordinal("check")}
      end
    end
  end

  # R4 rows 11-13: receipts passed, assertion failed, or tool/infrastructure failure. The
  # status is the controller's reason_code, and a failing check never terminalises here —
  # attempt_settled does, so a failed candidate cannot reach approval by relabelling.
  def do_transition("check_recorded", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(checking)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_check(ticket, payload["check_id"]),
         :ok <- require_check_status(payload["status"]),
         :ok <- require_check_unsettled(ticket, payload["check_id"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
         attempt
         |> put_in(["checks", payload["check_id"], "status"], payload["status"])
         |> put_in(["checks", payload["check_id"], "reason_code"], payload["reason_code"])
         |> then(&maybe_finish_checks(&1))
       end)}
    end
  end

  def do_transition("build_planned", ticket, event, _state) do
    with :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_no_pending_cancel(ticket),
         {:ok, ticket} <- add_execution(ticket, event["payload"], "build") do
      {:ok, ticket}
    end
  end

  def do_transition("build_settled", ticket, event, _state) do
    with :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         {:ok, ticket} <-
           close_execution(
             ticket,
             event["payload"]["attempt_id"],
             event["payload"]["execution_id"],
             ~w(build)
           ) do
      {:ok, consume_infrastructure_ordinal(ticket, "build")}
    end
  end

  # R4: "checking; all mandatory check receipts passed" → awaiting_review attempt. An
  # explicit policy-empty set follows the same guarded transition.
  # R4: "checking; all mandatory check receipts passed | awaiting_review attempt ... checks
  # with explicit policy-empty set follow same guarded transition". The empty set cannot be
  # inferred from an empty map, because an attempt that has not planned its checks yet
  # looks exactly the same; it is carried on checks_started, which is where protected
  # policy states it. Without that, a policy-empty attempt stayed in `checking` forever.
  defp maybe_finish_checks(attempt) do
    statuses = Elixir.Enum.map(attempt["checks"], fn {_id, check} -> check["status"] end)

    finished? =
      if attempt["policy_empty_checks"],
        do: statuses == [],
        else: statuses != [] and Elixir.Enum.all?(statuses, &(&1 == "passed"))

    if finished?, do: Map.put(attempt, "phase", "awaiting_review"), else: attempt
  end

  # R4 row 13: "Preserve candidate, **bounded new check-run reservation after cleanup**;
  # pending same phase". A check_id names the check the root mandates; planning it reserves
  # a run. A run that failed for infrastructure reasons or timed out may be re-reserved,
  # which is what "new check-run reservation ... pending same phase" means - before this
  # the attempt sat in `checking` forever, because every run had to be `passed` and a
  # reused id was refused outright.
  #
  # An assertion failure may never be re-reserved: that is row 12, whose outcome is a
  # terminal needs_correction attempt, and "failed candidate never goes to approval". Nor
  # may `unknown`, because R4 says "Unknown check retains lease and blocks retry". The
  # distinction is the controller's reason_code, which R4 makes load-bearing: "A check
  # failure uses its controller exit/receipt reason_code (assertion_failed,
  # infrastructure_failed or timed_out), not an agent's assertion."
  defp add_check(ticket, check_id, execution_id) do
    case active_attempt(ticket)["checks"][check_id] do
      nil ->
        {:ok,
         update_active_attempt(
           ticket,
           &put_in(&1, ["checks", check_id], fresh_check(check_id, execution_id))
         )}

      check ->
        if retryable_check?(check),
          do:
            {:ok,
             update_active_attempt(
               ticket,
               &put_in(&1, ["checks", check_id], fresh_check(check_id, execution_id))
             )},
          else: {:error, :check_already_exists}
    end
  end

  # A re-plan rebinds the check to its new run's execution.
  defp fresh_check(check_id, execution_id),
    do: %{
      "check_id" => check_id,
      "execution_id" => execution_id,
      "status" => "pending",
      "reason_code" => nil
    }

  defp retryable_check?(%{"status" => "timed_out"}), do: true

  defp retryable_check?(%{"status" => "failed", "reason_code" => "infrastructure_failed"}),
    do: true

  defp retryable_check?(_check), do: false

  defp require_check(ticket, check_id),
    do:
      if(Map.has_key?(active_attempt(ticket)["checks"] || %{}, check_id),
        do: :ok,
        else: {:error, :unknown_check}
      )

  # R4 row 11 requires developer closure before checks. "Closed" means the execution
  # lifecycle says so, not that an observation mentioned an exit.
  defp require_developer_closed(ticket) do
    executions = active_attempt(ticket)["executions"] || %{}

    developer =
      Elixir.Enum.filter(executions, fn {_id, execution} -> execution["role"] == "developer" end)

    if developer != [] and
         Elixir.Enum.all?(developer, fn {_id, execution} -> execution["lifecycle"] == "closed" end),
       do: :ok,
       else: {:error, :developer_not_closed}
  end

  # R4: "Separate write-once sealed result", and "failed candidate never goes to approval".
  # Correction 7 of 202b8e4 made the reviewer's verdict write-once and left the check
  # receipt writable, so a failed check could be relabelled `passed` and reach review. It
  # was not a hypothetical: every one of the nine attempts that reached review_planned in
  # the property suite got there through this, which is what the @known_unreached ratchet
  # was resting on.
  @terminal_check_statuses ~w(passed failed timed_out cancelled)

  defp require_check_unsettled(ticket, check_id) do
    if active_attempt(ticket)["checks"][check_id]["status"] in @terminal_check_statuses,
      do: {:error, :check_already_settled},
      else: :ok
  end

  # A settlement closes the execution it names and deletes the check it names, so the two
  # must be one run. Checked independently, check_settled{C2, K1} closed C1's run as a
  # non-start and dropped C2's record while C2's worker was still live.
  defp require_check_execution(ticket, check_id, execution_id) do
    if active_attempt(ticket)["checks"][check_id]["execution_id"] == execution_id,
      do: :ok,
      else: {:error, :not_the_check_execution}
  end

  defp require_check_status(status),
    do: if(status in State.check_statuses(), do: :ok, else: {:error, :invalid_check_status})
end
