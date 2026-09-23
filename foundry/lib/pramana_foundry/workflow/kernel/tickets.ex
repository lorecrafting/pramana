defmodule PramanaFoundry.Workflow.Kernel.Tickets do
  @moduledoc """
  Ticket admission, amendment, park, block, unblock and reset, with the resume-target
  guards those rows share. Generic: no row here names a software outcome.
  """

  import PramanaFoundry.Workflow.Kernel.Shared,
    only: [require_no_active_attempt: 1, require_phase: 2]

  alias PramanaFoundry.Workflow.Kernel.State

  # Every phase in which R4a can block work at its infrastructure limit. `blocked` is
  # absent: a ticket already blocked is not blocked again, and `exhausted` has its own
  # reset row.
  @blockable_phases ~w(queued developing awaiting_review reviewing ready_to_integrate
                       integrating)

  # R4: "draft; specific spec or valid PM create" — admission yields queued or blocked.
  def do_transition("ticket_admitted", :absent, event, _state) do
    payload = event["payload"]

    if payload["phase"] in ~w(queued blocked) do
      {:ok,
       %{
         "ticket_id" => payload["ticket_id"],
         "objective_id" => payload["objective_id"],
         "spec_revision_id" => payload["spec_revision_id"],
         "spec" => payload["spec"],
         "phase" => payload["phase"],
         "reason" => payload["reason"],
         # A ticket admitted straight to blocked has never been anywhere, so R4's resume
         # row ("return to stored resume_phase") would have no target. Its target is the
         # phase admission would have reached, which keeps resume total rather than
         # leaving a nil no later event can repair.
         "resume_phase" => if(payload["phase"] == "blocked", do: "queued", else: nil),
         "cancel_requested" => false,
         "attempts" => %{},
         "active_attempt_id" => nil,
         "prior_attempt_ids" => [],
         "infrastructure" => State.infrastructure(State.ticket_roles())
       }}
    else
      {:error, :invalid_admission_phase}
    end
  end

  # R4: "queued/blocked; PM amend/park" — a new future spec revision. Active assignments
  # are never edited, so an amendment is refused once an attempt is running.
  def do_transition("ticket_amended", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(queued blocked)),
         :ok <- require_no_active_attempt(ticket) do
      {:ok,
       ticket
       |> Map.put("spec_revision_id", event["payload"]["spec_revision_id"])
       |> Map.put("spec", event["payload"]["spec"])}
    end
  end

  # R4: "queued/blocked; PM amend/park" — explicit blocked state with a resume phase.
  def do_transition("ticket_parked", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(queued blocked)),
         :ok <- require_resume_phase(payload["resume_phase"]),
         :ok <- require_honest_resume_target(ticket, payload["resume_phase"]) do
      {:ok,
       ticket
       |> Map.put("phase", "blocked")
       |> Map.put("reason", payload["reason"])
       |> Map.put("resume_phase", payload["resume_phase"])}
    end
  end

  # R4a: "At the limit, ticket becomes `blocked(<role>_launch_infrastructure)`", and R4 row
  # 13's "or blocked(check_infrastructure)". Unlike R4's PM park this applies from whatever
  # phase the work was in, because R4a blocks each role where it stands and keeps its
  # attempt resumable - the reviewer row is explicit that the candidate and checks survive.
  # The resume target is held to the same honesty rule as a park: it is where the ticket is
  # now, or the target it already stored.
  def do_transition("ticket_blocked", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, @blockable_phases),
         :ok <- require_resume_phase(payload["resume_phase"]),
         :ok <- require_honest_resume_target(ticket, payload["resume_phase"]) do
      {:ok,
       ticket
       |> Map.put("phase", "blocked")
       |> Map.put("reason", payload["reason"])
       |> Map.put("resume_phase", payload["resume_phase"])}
    end
  end

  # R4: "blocked; explicit resume or recorded dependency/resource recovery" — returns to
  # the stored resume_phase. The event's phase is checked against it, never trusted.
  def do_transition("ticket_unblocked", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(blocked)),
         :ok <- require_resume_target(ticket) do
      if ticket["resume_phase"] == event["payload"]["phase"] do
        {:ok,
         ticket
         |> Map.put("phase", ticket["resume_phase"])
         |> Map.put("reason", nil)
         |> Map.put("resume_phase", nil)}
      else
        {:error, :resume_phase_disagrees}
      end
    end
  end

  # R4: "exhausted; authenticated reset grants eligible units and explicitly resumes".
  # The old attempt stays terminal, so a reset with work still active is refused.
  def do_transition("ticket_reset", ticket, event, _state) do
    # The second guard here cannot fire, unlike its twins in `ticket_amended` and
    # `cancellation_finalized`, which both can. `attempt_settled(exhausted)` is the only
    # route into the exhausted phase and it clears the active slot in the same step, so an
    # exhausted ticket never has an active attempt. Measured rather than argued, and
    # bounded so the answer is not an artefact of depth: 10,024 reachable states hold an
    # exhausted ticket at depth 7 and none of them holds an active attempt.
    #
    # Kept, because the rule R4 states is right. Noted because `@unreachable` in the
    # guard-reachability suite is keyed by error ATOM and this is a property of one CALL
    # SITE — `:attempt_still_active` is reachable, just not from here — so that ratchet
    # cannot hold this fact and only the per-occurrence mutation sweep can see it.
    with :ok <- require_phase(ticket, ~w(exhausted)),
         :ok <- require_no_active_attempt(ticket),
         :ok <- require_reset_facts(event["payload"]["generation"]) do
      {:ok,
       ticket
       |> Map.put("phase", "queued")
       |> Map.put("reason", nil)
       |> Map.put("resume_phase", nil)
       # R4a reads two ways here and the choice is recorded rather than left implied.
       # "Restart, new execution IDs, profile changes, attempt resumption and duplicate
       # receipts do not reset the ordinal" - none of which is a policy reset. "A policy
       # reset may create a new infrastructure generation with an explicit finite
       # allowance; it never erases predecessor records." A new generation carries its own
       # allowance, so its count starts at zero; the predecessor records it must not erase
       # are the durable non-start records in the protected layer, not this counter. If a
       # reviewer reads that sentence as binding on the counter itself, this is the line to
       # challenge.
       |> update_in(["infrastructure", "generation"], &(&1 + 1))
       |> put_in(
         ["infrastructure", "ordinals"],
         State.infrastructure(State.ticket_roles())["ordinals"]
       )}
    end
  end

  # A park may only promise to return the ticket where it actually is, or where it was
  # already recorded as resumable. A caller-chosen target let a walk park an
  # awaiting_review ticket with resume_phase "queued" and then resume it to queued,
  # abandoning the frozen candidate R4 requires it to keep custody of.
  defp require_honest_resume_target(ticket, resume_phase) do
    honest =
      case ticket["phase"] do
        # An already-blocked ticket has no current phase to promise; its only honest target
        # is the one it already stored.
        "blocked" ->
          [ticket["resume_phase"]]

        # R4a's developer row retains `developing` across a non-start, which lands the
        # ticket in `queued`; an at-limit park that overwrote the target with `queued`
        # would lose the attempt the same row calls resumable. This is the one working
        # phase whose stored target is still a promise about where the work is.
        "queued" ->
          [ticket["phase"], ticket["resume_phase"]]

        # Every other phase names itself and nothing else. Accepting the stored value from
        # anywhere resurrected an obsolete recovery point: `launch_settled` stores
        # `developing`, the retry succeeds, `artifact_frozen` advances the ticket to
        # awaiting_review without clearing it, and a later block could then name
        # `developing` — returning a candidate_frozen attempt to `developing`, where no
        # productive event is accepted and `launch_planned` opens a third developer on an
        # attempt that has already frozen its candidate. Seven events from empty, found by
        # exhaustive search and reproduced independently by two reviewers.
        #
        # The fix is here rather than at every advancing transition because one guard is
        # smaller than N writers and cannot be partially applied, which is how the sibling
        # defects above were introduced.
        phase ->
          [phase]
      end

    if resume_phase in honest,
      do: :ok,
      else: {:error, :resume_target_not_current_phase}
  end

  # Without this a ticket whose resume_phase is nil resumed to nil: the payload's nil
  # equalled the stored nil, the comparison passed, and apply/2 produced a state its own
  # validator rejects. Found by a seeded reachability walk, not by the table tests.
  defp require_resume_target(ticket),
    do:
      if(ticket["resume_phase"] in State.ticket_phases(),
        do: :ok,
        else: {:error, :no_stored_resume_phase}
      )

  # R4: "blocked; explicit resume ... | return to stored resume_phase". A resume target is
  # a phase the ticket can be returned *to*, so `blocked` itself and the terminal phases
  # are not candidates. Accepting `blocked` produced a ticket blocked with no reason and no
  # resume target, from which resume failed forever — and the prober proposed exactly that,
  # because it derived the target from the ticket's current phase rather than from R4. Both
  # sides agreeing on an illegal state is the circularity the design forbids.
  @resume_phases ~w(queued developing awaiting_review reviewing ready_to_integrate
                    integrating)

  defp require_resume_phase(phase),
    do: if(phase in @resume_phases, do: :ok, else: {:error, :invalid_resume_phase})

  # R4's reset row is one ticket transition; R5 resets one ledger generation per dimension.
  # So the bound `generation` is a non-empty list of reset_fact_v1 facts, one per dimension,
  # which TransitionPlan fills from the protected reset_generation results. The kernel holds
  # no ledger ids, so it checks shape and that no dimension is reset twice, nothing more.
  defp require_reset_facts([_ | _] = facts) do
    shaped? =
      Enum.all?(facts, fn fact ->
        is_map(fact) and not is_struct(fact) and fact["schema_version"] == 1 and
          is_binary(fact["ledger_id"]) and fact["ledger_id"] != "" and
          is_binary(fact["dimension"]) and fact["dimension"] != "" and
          is_integer(fact["generation"]) and fact["generation"] >= 0 and
          is_integer(fact["authorized"]) and fact["authorized"] >= 0
      end)

    dimensions = Enum.map(facts, & &1["dimension"])

    if shaped? and dimensions == Enum.uniq(dimensions),
      do: :ok,
      else: {:error, :invalid_reset_facts}
  end

  defp require_reset_facts(_facts), do: {:error, :invalid_reset_facts}
end
