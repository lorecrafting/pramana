defmodule PramanaFoundry.Workflow.Kernel.Software.Review do
  @moduledoc """
  Software workflow: reviewer planning, non-start settlement, verdict and close.
  """

  import PramanaFoundry.Workflow.Kernel.Control, only: [require_no_pending_cancel: 1]

  import PramanaFoundry.Workflow.Kernel.Executions,
    only: [
      add_execution: 3,
      close_execution: 4,
      consume_infrastructure_ordinal: 2,
      require_execution: 3,
      require_sealed: 3
    ]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [
      active_attempt: 1,
      attempt: 2,
      require_active_attempt: 2,
      require_attempt: 2,
      require_attempt_phase: 2,
      require_phase: 2,
      update_active_attempt: 2
    ]

  alias PramanaFoundry.Workflow.Kernel.State

  # R4: "awaiting_review; check receipts valid and reviewer capacity available".
  def do_transition("review_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(awaiting_review)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(awaiting_review)),
         :ok <- require_checks_passed(ticket),
         :ok <- require_no_pending_cancel(ticket),
         {:ok, ticket} <- add_execution(ticket, payload, "reviewer") do
      {:ok,
       ticket
       |> Map.put("phase", "reviewing")
       |> update_active_attempt(fn attempt ->
         attempt
         |> Map.put("phase", "reviewing")
         |> Map.put("review", %{
           "candidate_id" => attempt["candidate_id"],
           "verdict" => nil,
           "execution_id" => payload["authority"]["execution_id"]
         })
       end)}
    end
  end

  # R4a reviewer row: keep the attempt and ticket awaiting_review with the same frozen
  # candidate and reviewer ownership; never enter developer retry or correction.
  def do_transition("review_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(reviewing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_reviewer_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         # R4: "validated review result takes precedence over later execution exit status",
         # and R4a says a proved non-start is "not charged as a launch failure". This row
         # is for a reviewer that never ran; without the guard one event erased a recorded
         # verdict, returned the ticket to awaiting_review and charged the ordinal. The
         # developer and integration siblings were already guarded - the same partial
         # generalisation corrected after review three, one level further out.
         :ok <- require_no_recorded_verdict(ticket) do
      with {:ok, ticket} <-
             close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(reviewer)) do
        {:ok,
         ticket
         |> Map.put("phase", "awaiting_review")
         |> Map.put("resume_phase", "awaiting_review")
         |> update_active_attempt(fn attempt ->
           attempt |> Map.put("phase", "awaiting_review") |> Map.put("review", nil)
         end)
         |> consume_infrastructure_ordinal("reviewer")}
      end
    end
  end

  # R4 rows 14-16: approved exact-candidate, correction, or rejected verdict. The verdict
  # is recorded against the exact candidate; it does not advance the ticket, because R4
  # makes ready_to_integrate follow *verified reviewer close*, not the verdict. The
  # reviewed candidate accepted an approval immediately, which is B2's third defect.
  def do_transition("review_recorded", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(reviewing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_review_candidate(ticket, payload["candidate_id"]),
         :ok <- require_verdict(payload["verdict"]),
         :ok <- require_no_recorded_verdict(ticket),
         :ok <- require_reviewer_open(ticket),
         :ok <- require_reviewer_stream_sealed(ticket) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
         put_in(attempt, ["review", "verdict"], payload["verdict"])
       end)}
    end
  end

  # R4: "Close/seal reviewer; after verified close ready_to_integrate; no Git success
  # inferred." Only an approved verdict advances; correction and rejection terminalise
  # through attempt_settled instead.
  #
  # Closing the reviewer is cleanup evidence and must outlive settlement: R4's correction
  # and rejection rows both close the reviewer *after* the attempt terminalises, and
  # requiring the active attempt made those closures impossible, leaking the execution.
  # Only an active attempt carrying an approved verdict advances the ticket.
  def do_transition("reviewer_closed", ticket, event, _state) do
    payload = event["payload"]
    attempt_id = payload["attempt_id"]

    with :ok <- require_attempt(ticket, attempt_id),
         :ok <- require_execution(ticket, attempt_id, payload["execution_id"]),
         :ok <- require_reviewer_execution(ticket, attempt_id, payload["execution_id"]),
         :ok <- require_sealed(ticket, attempt_id, payload["execution_id"]),
         {:ok, ticket} <-
           close_execution(ticket, attempt_id, payload["execution_id"], ~w(reviewer)) do
      verdict = attempt(ticket, attempt_id)["review"]["verdict"]

      cond do
        ticket["active_attempt_id"] != attempt_id ->
          {:ok, ticket}

        # Unreachable, for the same reason `require_reviewer_open` is and recorded the same
        # way. Reaching it needs an approved verdict on an attempt whose phase is no longer
        # `reviewing`, while its reviewer execution is still sealed-and-open — but the only
        # thing that moves the attempt off `reviewing` after an approval is this very
        # branch, and it closes that execution on the way, so a second arrival is refused
        # by `require_not_closed`. Searched from a sealed reviewer rather than from empty,
        # because an unseeded search reaches zero recorded verdicts at depth 8 and would
        # have "proved" this vacuously: 164,648 seeded states, 13,846 holding an approved
        # verdict, none satisfying the precondition.
        #
        # A hand argument said the same thing and was wrong once already — the looser
        # predicate it suggested has 3,612 witnesses. The number above is the claim.
        verdict == "approved" ->
          with :ok <- require_attempt_phase(ticket, ~w(reviewing)) do
            {:ok,
             ticket
             |> Map.put("phase", "ready_to_integrate")
             |> update_active_attempt(&Map.put(&1, "phase", "ready_to_integrate"))}
          end

        # R4: "reviewing; sealed stream no valid verdict and reviewer crash/timeout |
        # Preserve candidate, **close reviewer then bounded new reviewer execution**". The
        # candidate and its check receipts survive; only the reviewer is discarded, so the
        # attempt returns to awaiting_review where a new reviewer can be planned. Before
        # this the honest sequence - seal, then close, with no verdict - stranded the
        # attempt in `reviewing` with no accepted exit but exhaustion or cancellation, and
        # the only alternative was to mislabel a reviewer that had started as a non-start,
        # which R4a forbids: "waiting or unknown ownership is visible, not charged as a
        # launch failure."
        is_nil(verdict) and attempt(ticket, attempt_id)["phase"] == "reviewing" ->
          {:ok,
           ticket
           |> Map.put("phase", "awaiting_review")
           |> Map.put("resume_phase", "awaiting_review")
           |> update_active_attempt(fn attempt ->
             attempt |> Map.put("phase", "awaiting_review") |> Map.put("review", nil)
           end)}

        true ->
          {:ok, ticket}
      end
    end
  end

  defp require_checks_passed(ticket) do
    statuses =
      Elixir.Enum.map(active_attempt(ticket)["checks"] || %{}, fn {_id, c} -> c["status"] end)

    if Elixir.Enum.all?(statuses, &(&1 == "passed")),
      do: :ok,
      else: {:error, :checks_not_passed}
  end

  # R4: a reviewer verdict is accepted only against a sealed reviewer stream. Without this
  # an approval could be believed before the inbox was processed through its last sequence.
  defp require_reviewer_stream_sealed(ticket) do
    attempt = active_attempt(ticket)
    execution_id = attempt["review"]["execution_id"]

    if is_integer(attempt["executions"][execution_id]["sealed_sequence"]),
      do: :ok,
      else: {:error, :reviewer_stream_not_sealed}
  end

  defp require_review_candidate(ticket, candidate_id) do
    attempt = active_attempt(ticket)

    if is_map(attempt["review"]) and attempt["review"]["candidate_id"] == candidate_id and
         attempt["candidate_id"] == candidate_id,
       do: :ok,
       else: {:error, :verdict_names_another_candidate}
  end

  # R4 makes the sealed result "write-once". Without this a second review_recorded
  # overwrote the first, so an approval could be replaced by a correction - or the reverse -
  # after the fact, and reviewer_closed would act on whichever verdict landed last.
  defp require_no_recorded_verdict(ticket) do
    case active_attempt(ticket)["review"] do
      %{"verdict" => nil} -> :ok
      _ -> {:error, :verdict_already_recorded}
    end
  end

  # A reviewer close may only close the execution the review is actually bound to.
  # Without this it could close the developer's execution and still advance the ticket to
  # ready_to_integrate, since the verdict is read from the review rather than the argument.
  # A verdict arriving after its reviewer is closed is late evidence, not authority: R4a
  # says messages after sealing "are late evidence, never silently attached".
  #
  # **This guard is currently unreachable**, and was claimed as a fix when it was not one.
  # Once `reviewer_closed` nils the review on the no-verdict branch, every route to a
  # closed reviewer on a `reviewing` attempt is refused earlier, by the recorded-verdict
  # guard or by phase. Exhaustive search confirms it across 88,777 states at depth eight,
  # and `r4_exhaustive_test.exs` asserts that unreachability so a future change that opens
  # a route fails rather than silently relying on a guard nothing has ever exercised. It is
  # kept because the rule is right, not because it is doing work today.
  defp require_reviewer_open(ticket) do
    review = active_attempt(ticket)["review"] || %{}
    execution = active_attempt(ticket)["executions"][review["execution_id"]] || %{}

    if execution["lifecycle"] == "closed",
      do: {:error, :reviewer_already_closed},
      else: :ok
  end

  defp require_reviewer_execution(ticket, attempt_id, execution_id) do
    case attempt(ticket, attempt_id)["review"] do
      %{"execution_id" => ^execution_id} -> :ok
      _ -> {:error, :not_the_reviewer_execution}
    end
  end

  defp require_verdict(verdict),
    do: if(verdict in State.verdicts(), do: :ok, else: {:error, :invalid_verdict})
end
