defmodule PramanaFoundry.Workflow.Kernel.Software.Dispositions do
  @moduledoc """
  Software workflow: `attempt_settled`, the single terminalising event, and the source
  row each disposition (integrated, rejected, needs_correction, ...) must come from.
  """

  import PramanaFoundry.Workflow.Kernel.Cancellation, only: [require_cancel_requested: 1]

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [active_attempt: 1, require_active_attempt: 2, require_attempt_phase: 2]

  import PramanaFoundry.Workflow.Kernel.Software.Developer, only: [seal_developer_result: 3]
  alias PramanaFoundry.Workflow.Kernel.State

  # R4: "Attempt disposition | Set once on terminal". The single terminalising event: it
  # seals the active attempt, moves it to prior_attempt_ids so its executions, candidate
  # and review evidence are retained rather than replaced, and clears the active slot.
  def do_transition("attempt_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_disposition(payload["disposition"]),
         :ok <- require_receipt_for_integration(ticket, payload["disposition"]),
         :ok <- require_settlement_source(ticket, payload["disposition"]) do
      attempt_id = payload["attempt_id"]

      ticket =
        ticket
        |> update_in(["attempts", attempt_id], fn attempt ->
          attempt
          |> Map.put("phase", "terminal")
          |> Map.put("disposition", payload["disposition"])
          |> Map.put("reason_code", payload["reason_code"])
        end)
        |> Map.put("active_attempt_id", nil)
        |> Map.update!("prior_attempt_ids", &(&1 ++ [attempt_id]))

      ticket =
        if payload["disposition"] in ~w(failed timed_out),
          do: seal_developer_result(ticket, attempt_id, "none"),
          else: ticket

      {:ok, apply_terminal_phase(ticket, payload["disposition"])}
    end
  end

  # Only the dispositions R4 makes terminal for the whole ticket move the ticket. A
  # needs_correction or failed attempt returns the ticket to queued for a fresh bounded
  # attempt; the row's drain and exhaustion alternatives are emitted as a second event.
  defp apply_terminal_phase(ticket, disposition) do
    case disposition do
      "integrated" ->
        Map.put(ticket, "phase", "integrated")

      "rejected" ->
        Map.put(ticket, "phase", "rejected")

      "cancelled" ->
        ticket

      "exhausted" ->
        Map.put(ticket, "phase", "exhausted")

      # R4: "Terminal blocked attempt, blocked ticket; **Resume/rescope requires explicit
      # command and fresh attempt**". The row makes the *settlement* block the ticket; the
      # first correction here only cleared the resume target and relied on artifact_blocked
      # having already blocked the ticket. Exhaustive search found the five-event sequence
      # where it had not: admit, launch, artifact_blocked, **ticket_unblocked**, settle -
      # leaving a `developing` ticket with no attempt and no cancel, which nothing can move.
      # Leaving `resume_phase: developing` set meant ticket_unblocked returned the ticket
      # to `developing` with no attempt at all, the state the requeue branch below was
      # corrected to avoid. The correction was applied to that branch and not to this one,
      # which is the third time in this subcommit a right rule reached one sibling only.
      "blocked" ->
        ticket
        |> Map.put("phase", "blocked")
        |> Map.put("resume_phase", "queued")

      # R4: "queue fresh bounded attempt". A ticket requeued after a terminal attempt is
      # not blocked any more, so keeping the previous block's reason and resume target left
      # a queued ticket carrying a stale promise - which a later park could then honour,
      # producing a developing ticket with no attempt at all.
      _ ->
        ticket
        |> Map.put("phase", "queued")
        |> Map.put("reason", nil)
        |> Map.put("resume_phase", nil)
    end
  end

  # R4: "no Git success inferred". An attempt may only claim the integrated disposition
  # when the integration row actually recorded a ref receipt for it.
  defp require_receipt_for_integration(ticket, "integrated") do
    if is_binary(active_attempt(ticket)["ref_receipt_id"]),
      do: :ok,
      else: {:error, :no_ref_receipt}
  end

  # The converse, and the other half of R4's integration row. Splitting the row into
  # integration_recorded and attempt_settled stopped it contradicting itself but left the
  # two halves independent, so an attempt that had just created a ref could still settle
  # `failed` — a ref on the accepted branch with a domain that says the attempt failed.
  # "Exit notifications cannot overwrite this": once a receipt exists the disposition is
  # determined.
  defp require_receipt_for_integration(ticket, disposition) do
    if is_binary(active_attempt(ticket)["ref_receipt_id"]) and disposition != "integrated",
      do: {:error, :ref_receipt_admits_only_integrated},
      else: :ok
  end

  # R4 gives every disposition a source row, and without these guards a terminal state was
  # reachable without its lifecycle: a developing ticket settled `rejected` with no verdict
  # recorded at all, and `cancelled` with nothing ever having requested cancellation. That
  # is B1's premise ("terminal states reachable only through their lifecycle") and this
  # module's own stated property 3 ("every event names the phase it may apply to"), both
  # broken in the one event that makes states terminal.
  #
  # The rows, in R4's words:
  #   integrated       "integrating; successful ref receipt and prior workers closed"
  #   superseded_base  "ready_to_integrate/integrating; accepted base moved before issuance"
  #   rejected         "reviewing; rejected verdict"
  #   needs_correction "checking; actual check assertion fails" or "reviewing; correction verdict"
  #   failed/timed_out "developing; sealed stream has no valid candidate, verified exit/timeout"
  #   blocked          "developing; valid blocked/partial result"
  #   cancelled        "cancel_requested; every owned claim terminal"
  #
  # `timed_out` is deliberately confined to the developing row. R4's reviewer crash/timeout
  # row says "Preserve candidate, close reviewer then bounded new reviewer execution" — it
  # must not terminalise the attempt, and before this guard it did.
  #
  # `exhausted` carries no source guard. R4 seals the current attempt with it from several
  # phases, and every one of them turns on allocation, which is protected policy the kernel
  # may not restate. Recorded rather than silently permissive.
  defp require_settlement_source(ticket, disposition) do
    attempt = active_attempt(ticket)
    verdict = attempt["review"]["verdict"]

    case disposition do
      "integrated" ->
        require_attempt_phase(ticket, ~w(integrating))

      # R4: "ready_to_integrate/integrating; accepted base moved **before issuance**". The
      # clause is about issuance, so the guard asks about issuance and nothing else. It used
      # to be qualified by `attempt["phase"] == "integrating"`, on the stated premise that
      # "from ready_to_integrate no integration effect exists yet" - a premise an attempt
      # parked at `ready_to_integrate` while holding a live integration execution falsifies,
      # and the trap the `infrastructure_failed` resume target had to be steered around.
      # Under the in-flight predicate below the qualifier is redundant rather than merely
      # false: attempt phase `ready_to_integrate` has two writers, `reviewer_closed` on an
      # approved verdict (no integration execution exists yet) and `integration_settled`
      # (which closes the execution on the way), so no reachable state distinguishes the two
      # forms. The induction has a second half the first version of this comment left out,
      # supplied by the review: `reviewer_closed` needs the attempt in `reviewing`, and no
      # transition returns an attempt from `ready_to_integrate` or `integrating` to
      # `reviewing`, so no integration execution can exist at that writer at all.
      # Unwitnessed by construction per rule 3: the deletion has no red control and cannot
      # have one until such a state is reachable. It ships because the qualifier was an
      # EXEMPTION - deleting it can only add refusals, never remove one - and rule 3's
      # instruction for an unwitnessed guard is prove it inductively or delete it.
      "superseded_base" ->
        with :ok <- require_attempt_phase(ticket, ~w(ready_to_integrate integrating)) do
          if integration_issued?(attempt),
            do: {:error, :integration_already_issued},
            else: :ok
        end

      "rejected" ->
        if verdict == "rejected",
          do: require_attempt_phase(ticket, ~w(reviewing)),
          else: {:error, :no_rejected_verdict}

      "needs_correction" ->
        cond do
          attempt["phase"] == "checking" and failed_check?(attempt) -> :ok
          attempt["phase"] == "reviewing" and verdict == "correction" -> :ok
          true -> {:error, :no_correction_evidence}
        end

      d when d in ~w(failed timed_out) ->
        with :ok <- require_attempt_phase(ticket, ~w(active)),
             :ok <- require_no_candidate(attempt) do
          require_developer_stream_sealed(attempt)
        end

      # R4 row 9 is "developing; **valid blocked/partial result**". Requiring only an
      # active attempt let a freshly launched one settle `blocked` with no result at all,
      # leaving the ticket `developing` with no active attempt - a state R4 does not have
      # and nothing can move. The sealed execution result is what makes the result a fact.
      "blocked" ->
        with :ok <- require_attempt_phase(ticket, ~w(active)) do
          require_developer_result(attempt, ~w(blocked partial))
        end

      "cancelled" ->
        require_cancel_requested(ticket)

      # R4 and R4a place exhaustion in four phases: developer allocation (active), the
      # check rows' "blocked(check_infrastructure)/exhausted" and "blocked(drain)/exhausted"
      # (checking), and the reviewer rows' "exhaust if unavailable" and "blocked(reviewer_
      # budget) or exhausted" (awaiting_review and reviewing). `candidate_frozen` has only
      # the cleanup-observation row, which says "no attempt failure", and the integrating
      # phases have their own terminal rows - so exhausting from those was a terminal state
      # without a lifecycle, the one hole the allocation argument left open.
      "exhausted" ->
        require_attempt_phase(ticket, ~w(active checking awaiting_review reviewing))
    end
  end

  # R4 row :484 asks whether the attempt holds an issued integration effect *now*, not
  # whether it has ever held one. Scanning for any execution whose lifecycle was not
  # `pending` answered the second question, and was already wrong before any phase change:
  # after a bounded retry - I1 `closed`, I2 `pending`, reachable by `no_ref_change` →
  # `worker_closed` → `integration_planned` - it refused `:integration_already_issued`
  # although the current effect is unissued, which made the row unexpressible for a retried
  # integration.
  #
  # "Newest execution is pending" was the remedy the log first proposed and is not
  # buildable: an execution record is `execution_id role lifecycle result sealed_sequence`
  # (`State.@execution_keys`) with no sequence, timestamp or ordering field, so "newest" is
  # not expressible without a state-shape change subcommit 2 would then inherit. The
  # lifecycle answers it directly and phase-independently.
  #
  # `pending` is claimed but not issued. **`closed` is not safe on its own, and the first
  # version of this comment claimed it was.** An integration execution reaches `closed`
  # through two call sites - `integration_settled` (the non-start settlement) and
  # `worker_closed` - and only the first is behind `require_no_ref_receipt`.
  # `worker_closed` (:613) carries one guard, `require_attempt`, so an integration effect
  # that LANDED can be closed, and this predicate then reads false on an attempt holding a
  # ref receipt. Three events from the suite's own `integrating_with_receipt` fixture; an
  # independent review drove it after the claim shipped.
  #
  # That state is refused, but not here. `require_receipt_for_integration` (:1531) sits
  # earlier in `attempt_settled`'s `with` chain than `require_settlement_source` and
  # refuses it `:ref_receipt_admits_only_integrated`. **That ordering is the guarantee.**
  # Reordering the chain, or narrowing that guard, opens the hole - so the control for it
  # is pinned to that atom, not to this predicate. This predicate is only ever the second
  # line of defence for a landed effect.
  #
  # `unknown` is deliberately on the issued side. The warrant is R4's integration row,
  # "unknown blocks reconciliation" (contract :486). R1's `reserved → issued_unknown`
  # ledger row (:573-576) is an analogy and is labelled one: it says issued things become
  # unknown at the issued commit, not that unknown things were issued, and an execution
  # can reach lifecycle `unknown` from `pending` with no start ever observed. Refusing is
  # the conservative direction there. R1 still owns the real issuance boundary; this is
  # the kernel's proxy for it, recorded as an interpretation rather than as the contract's
  # own words.
  @issued_lifecycles ~w(starting running closing unknown)

  defp integration_issued?(attempt),
    do:
      Elixir.Enum.any?(attempt["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "integration" and execution["lifecycle"] in @issued_lifecycles
      end)

  # R4 row 12 is "checking; **actual check assertion fails**", and its outcome is terminal.
  # Counting a timeout as an assertion failure terminalised an attempt row 13 says to
  # preserve, which is the row this kernel was misreading as that one. (This comment sat on
  # `integration_issued?` above until now; blame shows it was authored over `failed_check?`
  # and `integration_issued?` was later inserted between the two.)
  defp failed_check?(attempt),
    do:
      Elixir.Enum.any?(attempt["checks"] || %{}, fn {_id, check} ->
        check["status"] == "failed" and check["reason_code"] == "assertion_failed"
      end)

  defp require_developer_result(attempt, results) do
    sealed? =
      Elixir.Enum.any?(attempt["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "developer" and execution["result"] in results
      end)

    if sealed?, do: :ok, else: {:error, :no_blocked_result}
  end

  defp require_no_candidate(attempt),
    do: if(is_nil(attempt["candidate_id"]), do: :ok, else: {:error, :candidate_frozen})

  # R4: "sealed stream has no valid candidate" — the seal is what makes "no valid candidate"
  # a fact rather than an absence, since "unknown stream completeness blocks reconciliation;
  # it is not a failed attempt".
  # R4's left cell is "sealed stream has no valid candidate, **verified exit/timeout**", so
  # both halves are required: the seal makes "no valid candidate" a fact rather than an
  # absence, and the verified exit is a closed execution. Requiring only the seal let an
  # attempt settle `failed` with its developer still `pending` - never started, never
  # closed - which is the "no crash/timeout/result is synthesized" rule R4a states for the
  # non-start path, broken on the ordinary path.
  defp require_developer_stream_sealed(attempt) do
    exited? =
      Elixir.Enum.any?(attempt["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "developer" and is_integer(execution["sealed_sequence"]) and
          execution["lifecycle"] == "closed"
      end)

    if exited?, do: :ok, else: {:error, :exit_not_verified}
  end

  defp require_disposition(disposition),
    do: if(disposition in State.dispositions(), do: :ok, else: {:error, :invalid_disposition})
end
