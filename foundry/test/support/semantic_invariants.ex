defmodule PramanaFoundry.Test.SemanticInvariants do
  @moduledoc """
  Relations that must hold between facts in an accepted state, as distinct from the shapes
  `State.valid?/1` checks.

  Both independent reviewers of subcommit 1 arrived at this separately, from opposite
  directions, and it is the one thing neither of the five existing mechanisms could do.

  The demonstration is the stale-resume defect. The exhaustive search **reached the bad
  state** — a `developing` ticket whose attempt had already frozen its candidate, seven
  events from empty, three such states at depth 7. It did exactly its job. Nothing then
  called the state illegal, because every oracle in the suite answers a question about one
  transition:

      was this event admitted, or refused, and with which atom?

  and no oracle answered

      are the facts in the resulting state mutually coherent?

  `State.valid?/1` does not close that gap: it is a well-formedness validator — shapes,
  exact key sets, enum membership, reference integrity — and it accepted the bad state
  without complaint, correctly, because nothing about it is malformed.

  This also catches a class the guard mutation sweep **structurally cannot**. The sweep
  neutralises conditions. A transition can have every guard perfectly exercised and still
  write the wrong phase, fail to clear stale metadata, overwrite evidence, or keep a
  pointer it should have dropped — all in the effect body, which no mutation of a guard
  will ever perturb.

  ## What this is not

  It is not a proof. Asserting these over every state a bounded search reaches says they
  were not falsified within the bound, using a proposal set that is itself hand-written.
  The stronger form each of these wants is inductive — true of `State.new/0`, and preserved
  by every accepted transition — at which point the search stops being the argument. Where
  an invariant has that argument available, it is written beside it.

  Kept in `test/support` rather than promoted to `State`, deliberately. Making the kernel
  enforce these would let a transition that violates one be *refused* rather than
  *reported*, which converts a visible defect into a silent one, and the decision about
  which of these are contract obligations rather than current behaviour belongs to review.
  """

  @doc """
  Every violation in `state`, as human-readable strings. `[]` means all hold.

  Returns all of them rather than the first: a transition that corrupts one relation often
  corrupts several, and the set is the diagnosis.
  """
  def violations(state) do
    for {_ticket_id, ticket} <- state["tickets"] || %{},
        violation <- ticket_violations(ticket),
        do: violation
  end

  def ok?(state), do: violations(state) == []

  defp ticket_violations(ticket) do
    id = ticket["ticket_id"]
    active = ticket["attempts"][ticket["active_attempt_id"]]

    List.flatten([
      phase_agreement(id, ticket, active),
      resume_target(id, ticket),
      candidate_custody(id, ticket),
      receipt_custody(id, ticket),
      terminal_custody(id, ticket)
    ])
  end

  # The invariant the stale-resume defect broke, and the one that makes three
  # `require_attempt_phase(~w(active))` sites redundant.
  #
  # Inductive argument, which is why this is more than an enumeration: `launch_planned` is
  # the only transition that sets a ticket to `developing`, and it does so with the attempt
  # `active`; `artifact_frozen`, `artifact_blocked` and the settlements all move the ticket
  # off `developing` in the same step that they move the attempt off `active`; and
  # `ticket_unblocked` returns the ticket to its stored resume target, which since the
  # honesty fix can only be a phase the ticket actually occupied while holding that attempt.
  @legal_pairs %{
    "developing" => ~w(active),
    "awaiting_review" => ~w(candidate_frozen checking awaiting_review),
    "reviewing" => ~w(reviewing),
    "ready_to_integrate" => ~w(ready_to_integrate),
    "integrating" => ~w(integrating)
  }

  # A working phase with no active attempt is a ticket nothing can move — UNLESS a cancel is
  # pending, which is R4's own exception and not a weakening of this invariant.
  #
  # `WORKFLOW-CONTRACT.md:490`: "nonterminal ticket; cancel requested | Set orthogonal
  # control, cancel pending/unissued effects, request owned interrupts; **hold
  # phase/evidence while issued effects reconcile**". So `apply_terminal_phase` returning the
  # ticket unchanged for `cancelled` (`kernel.ex:1042-1043`) is the row being obeyed: the
  # ticket holds its working phase until row :491's `cancellation_finalized` moves it.
  #
  # This clause shipped without the exception and was therefore wrong on every state it ever
  # judged. Measured at depth 7 from empty: **1,002 of 58,324 reachable states** held its
  # precondition and **all 1,002 violated it** — it was never once satisfied. All 1,002 have
  # `cancel_requested` set and every attempt terminal-cancelled; 0 have no pending cancel.
  # The claim "a ticket nothing can move" was falsified directly rather than argued: none of
  # the 1,002 is stuck. Each admits at least 4 accepted successors, the reason the other 186
  # of 190 at depth 6 cannot finalise immediately is `:executions_not_closed` /
  # `:cleanup_incomplete` — row :491's "every owned session AND non-session claim terminal,
  # cleanup reconciled" — and every one reaches a terminal ticket phase within 5 more events.
  #
  # `receipt_custody/2` below already encodes the same cancel exception (`cancelled` is a
  # licensed terminal disposition there), so the two halves of this oracle disagreed until now.
  defp phase_agreement(id, ticket, nil) do
    if ticket["phase"] in Map.keys(@legal_pairs) and not ticket["cancel_requested"],
      do: ["#{id}: ticket is #{ticket["phase"]} with no active attempt and no pending cancel"],
      else: []
  end

  defp phase_agreement(id, ticket, attempt) do
    case Map.fetch(@legal_pairs, ticket["phase"]) do
      {:ok, legal} ->
        if attempt["phase"] in legal,
          do: [],
          else: [
            "#{id}: ticket #{ticket["phase"]} with attempt #{attempt["phase"]} " <>
              "(legal: #{Enum.join(legal, ", ")})"
          ]

      :error ->
        []
    end
  end

  # `blocked` must hold a target it can resume to. The converse — that no other phase may
  # hold one — is deliberately NOT asserted, and the reason is worth more than the check.
  #
  # `artifact_frozen` advances the ticket to `awaiting_review` and leaves the `developing`
  # target that `launch_settled` stored. That residue is real, and it is half of what
  # produced the livelock: before the honesty guard was scoped by phase, a block could name
  # the stale value and the unblock would act on it. The fix chosen by both reviewers was
  # the single guard, because clearing the target at every advancing transition is N edits
  # over a vocabulary and partial generalisation across a vocabulary is the defect shape
  # this subcommit has now produced six times.
  #
  # So the stale value still exists and is now inert. Asserting it away here would be this
  # oracle inventing an obligation neither the contract nor the review states, and would
  # fail against the kernel as it stands. Clearing on advance is the stronger fix and is
  # recorded for review rather than smuggled in as an invariant.
  defp resume_target(id, ticket) do
    if ticket["phase"] == "blocked" and is_nil(ticket["resume_phase"]),
      do: ["#{id}: blocked with no resume target"],
      else: []
  end

  # R4 makes a frozen candidate immutable and retained. An attempt that has one may not go
  # back to a phase that would produce another.
  defp candidate_custody(id, ticket) do
    for {attempt_id, attempt} <- ticket["attempts"] || %{},
        not is_nil(attempt["candidate_id"]),
        attempt["phase"] == "active",
        do: "#{id}/#{attempt_id}: holds candidate #{attempt["candidate_id"]} while active"
  end

  # R4's integration row: "Exit notifications cannot overwrite this." A ref receipt decides
  # the disposition, so an attempt holding one may not be terminal as anything else.
  defp receipt_custody(id, ticket) do
    for {attempt_id, attempt} <- ticket["attempts"] || %{},
        is_binary(attempt["ref_receipt_id"]),
        attempt["phase"] == "terminal",
        attempt["disposition"] not in ~w(integrated cancelled),
        do: "#{id}/#{attempt_id}: holds a ref receipt but settled #{attempt["disposition"]}"
  end

  # A terminal attempt is settled evidence: it carries a disposition and is not the active
  # one. Both halves have been broken separately in this subcommit.
  defp terminal_custody(id, ticket) do
    for {attempt_id, attempt} <- ticket["attempts"] || %{},
        attempt["phase"] == "terminal",
        reason <-
          [
            if(is_nil(attempt["disposition"]), do: "terminal with no disposition"),
            if(ticket["active_attempt_id"] == attempt_id, do: "terminal but still active")
          ]
          |> Enum.reject(&is_nil/1),
        do: "#{id}/#{attempt_id}: #{reason}"
  end
end
