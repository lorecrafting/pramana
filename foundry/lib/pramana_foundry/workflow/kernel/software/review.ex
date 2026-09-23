defmodule PramanaFoundry.Workflow.Kernel.Software.Review do
  @moduledoc """
  Software workflow: reviewer planning, non-start settlement, verdict and close.
  """

  import PramanaFoundry.Workflow.Kernel.Control,
    only: [require_no_pending_cancel: 1, require_not_paused: 1]

  import PramanaFoundry.Workflow.Kernel.Executions,
    only: [
      add_execution: 3,
      close_execution: 4,
      consume_infrastructure_ordinal: 2,
      execution: 2,
      executions: 1,
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

  alias PramanaFoundry.Workflow.Kernel.{Execution, Plan, State}

  # ── decide/3 ────────────────────────────────────────────────────────────────────
  #
  # The reviewer's commands: the role-free command types the developer claims, with role
  # `reviewer` in the payload (FR08B-SUBCOMMIT3-DESIGN-2026-09-23.md).

  def decides?(%{"type" => type, "payload" => %{"role" => "reviewer"}})
      when type in ~w(plan_launch settle_nonstart submit_review),
      do: true

  def decides?(_command), do: false

  # R4.16-R4.18: the verdict the adapter validated from the reviewer's sealed stream.
  # `approved` records it and nothing more: R4.16 makes ready_to_integrate follow the
  # *verified close*, which is `reviewer_closed` evidence, not a decision. `correction` and
  # `rejected` terminalise the attempt through the protected close_attempt in the same
  # plan, review_recorded first, so attempt_settled carries a bound terminal_settlement_v1.
  # The reviewer's own close stays separate cleanup evidence ("cleanup pending
  # separately"), and the developer successor after a correction is the developer's next
  # plan_launch, which requires that cleanup first. Every source condition - reviewing,
  # sealed stream, exact candidate, write-once verdict - is the reducer's.
  #
  # R4.15.o1's "independent reviewer" is enforced by Core, not here
  # (docs/fr-08/FR08B-REVIEWER-INDEPENDENCE-DESIGN-2026-09-23.md): the policy's
  # `independent_of_roles` makes create_effect refuse a reviewer whose principal the
  # attempt's developer holds. The adapter must launch the reviewer under a distinct
  # principal and treat `principal_not_independent` as a pre-intent denial (R4a).
  @terminal_verdicts %{
    "correction" => {"needs_correction", "correction_verdict"},
    "rejected" => {"rejected", "rejected_verdict"}
  }

  def decide(state, %{"type" => "submit_review"} = command, _facts) do
    ticket_id = command["target_ids"]["ticket_id"]
    attempt_id = (state["tickets"][ticket_id] || %{})["active_attempt_id"]

    recorded = %{
      "ticket_id" => ticket_id,
      "attempt_id" => attempt_id,
      "candidate_id" => command["payload"]["candidate_id"],
      "verdict" => command["payload"]["verdict"]
    }

    case @terminal_verdicts[command["payload"]["verdict"]] do
      {disposition, reason_code} ->
        Plan.close_attempt(state, command["command_id"], %{
          "ticket_id" => ticket_id,
          "attempt_id" => attempt_id,
          "disposition" => disposition,
          "reason_code" => reason_code,
          "before" => [{"review_recorded", recorded}]
        })

      nil ->
        Plan.unconditional(state, command["command_id"], %{
          "events" => [{"review_recorded", ticket_id, recorded}]
        })
    end
    |> Plan.decision(command)
  end

  # R4a.02: a proved reviewer non-start settles the claim and closes the reviewer execution
  # the review is bound to; the protected infrastructure limit selects between the reviewer
  # queue (awaiting_review, same attempt and candidate) and
  # `blocked(reviewer_launch_infrastructure)` resuming to awaiting_review. Unconditional
  # with respect to control, as the developer's is: control is decided on the next launch.
  def decide(state, %{"type" => "settle_nonstart"} = command, facts) do
    ticket_id = command["target_ids"]["ticket_id"]
    ticket = state["tickets"][ticket_id] || %{}

    state
    |> Plan.nonstart(command["command_id"], %{
      "settled" => "review_settled",
      "operation" => is_map(facts) && facts["settle_claim"],
      "ticket_id" => ticket_id,
      "attempt_id" => ticket["active_attempt_id"],
      "execution_id" => (active_attempt(ticket)["review"] || %{})["execution_id"],
      "reason" => "reviewer_launch_infrastructure",
      "resume_phase" => "awaiting_review"
    })
    |> Plan.decision(command)
  end

  # R4.15 and R4a's control sentences, under D1: control is evaluated before any successor
  # launch, the reviewer's included. The steps run in order and the first that decides ends
  # it:
  #
  #   1. pending cancel - reject; cancel "never retries".
  #   2. pause - reject; pause "forbids issue until resume", for every role.
  #   3. drain - not a step. The contract's drain list is "developer and PM replacement
  #      launches"; "reviewer ... retries remain eligible under the existing drain rule".
  #   4. allocation - R4.15.f3 "reviewer capacity available": short current allocation is a
  #      pre-intent denial and the ticket stays awaiting_review.
  #   5. otherwise the launch plan on the active attempt.
  #
  # Eligibility (awaiting_review, check receipts valid) is the reducer's, and comes out of
  # the dry run as a rejection. The control singleton is a declared read of the plan.
  def decide(state, %{"type" => "plan_launch"} = command, facts) do
    ticket = state["tickets"][command["target_ids"]["ticket_id"]]

    with {:ok, facts} <- Plan.launch_facts(facts),
         :ok <- rejected(require_no_pending_cancel(ticket)),
         :ok <- rejected(require_not_paused(state["control"])),
         :ok <- allocation(require_allocation(facts), state, command, ticket) do
      launch(state, command, ticket, facts)
    end
  end

  # Short current reviewer allocation, by what this attempt's reviewers already did:
  #
  #   - one ran and ended with no verdict (its stream was sealed): R4.19.o3 "exhaust if
  #     unavailable" - attempt and ticket exhausted through close_attempt.
  #   - one never started: R4a.02.o10 "blocked(reviewer_budget) or exhausted under protected
  #     policy, without discarding or approving the candidate" - blocked, candidate
  #     resumable. The kernel cannot read which the policy prefers, so it takes the
  #     recoverable one.
  #   - none: nothing spent, so R4.15.f3's pre-intent denial.
  #
  # Neither plan stages an operation that reads the ledger; `Plan.bind_allocation/2` binds
  # the allocation this chose on, in decide/3.
  defp allocation(:ok, _state, _command, _ticket), do: :ok

  defp allocation({:reject, _reason} = rejection, state, command, ticket) do
    reads = [{"control", "control"}]

    cond do
      Enum.any?(reviewers(ticket), &is_integer(&1.sealed_sequence)) ->
        state
        |> Plan.close_attempt(command["command_id"], %{
          "ticket_id" => ticket["ticket_id"],
          "attempt_id" => ticket["active_attempt_id"],
          "disposition" => "exhausted",
          "reason_code" => "reviewer_budget",
          "reads" => reads
        })
        |> Plan.decision(command)

      reviewers(ticket) != [] ->
        state
        |> Plan.block(command["command_id"], %{
          "ticket_id" => ticket["ticket_id"],
          "reason" => "reviewer_budget",
          "resume_phase" => "awaiting_review",
          "reads" => reads
        })
        |> Plan.decision(command)

      true ->
        rejection
    end
  end

  defp reviewers(ticket) do
    for {_id, %Execution{role: "reviewer"} = e} <- executions(active_attempt(ticket || %{})),
        do: e
  end

  @launch_units 1

  defp rejected(:ok), do: :ok
  defp rejected({:error, reason}), do: {:reject, reason}

  defp require_allocation(facts) do
    if facts["allocation"]["available"] >= @launch_units,
      do: :ok,
      else: {:reject, :allocation_unavailable}
  end

  # The ordinal is the attempt's reviewer launches so far, each of which opened one
  # reviewer execution; the predecessor is the adapter's.
  defp launch(state, command, ticket, facts) do
    operations =
      Plan.launch_operations(command["command_id"], %{
        "ticket_id" => command["target_ids"]["ticket_id"],
        "attempt_id" => (ticket || %{})["active_attempt_id"],
        "role" => "reviewer",
        "ordinal" => length(reviewers(ticket)),
        "units" => @launch_units,
        "facts" => facts
      })

    state
    |> Plan.launch(command["command_id"], %{
      "planned" => "review_planned",
      "operations" => operations
    })
    |> Plan.decision(command)
  end

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

    if match?(
         %Execution{sealed_sequence: sequence} when is_integer(sequence),
         execution(attempt, execution_id)
       ),
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

    if match?(
         %Execution{lifecycle: "closed"},
         execution(active_attempt(ticket), review["execution_id"])
       ),
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
