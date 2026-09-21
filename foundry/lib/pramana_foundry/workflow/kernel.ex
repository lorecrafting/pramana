defmodule PramanaFoundry.Workflow.Kernel do
  @moduledoc """
  The FR-08B pure domain reducer.

  `apply/2` folds one semantic event into domain state. It is pure: no I/O, clock, RNG,
  process, Git, configuration or provider call, and no external effect. Recorded time and
  identifiers arrive inside the event.

  This module answers blocker B1 of the pure-kernel review, which found the previous
  `apply/2` to be "an unrestricted snapshot installer, not a guarded event reducer": it
  accepted any nonempty event type and delegated to a generic `changes` merge, so an event
  could create an `integrated` ticket out of empty state and an older event applied after a
  newer one moved a ticket backwards. Five properties replace that.

  1. **Closed vocabulary.** `Event.validate/2` accepts only the enumerated types, each with
     an exact payload key set. An unknown type never reaches a merge.
  2. **Totality over the validator.** Every state `State.valid?/1` accepts is one `apply/2`
     returns from rather than raises on. The guard clauses read only fields that validator
     has already constrained, and the final `rescue` is a containment net, not the design.
  3. **Source-state guards.** Every event names the phase it may apply to. An event that
     does not match its source state is rejected; nothing is installed.
  4. **No entity creation by projection.** Only `ticket_admitted` and `objective_created`
     create an entity, and both refuse an identifier that already exists. Every other event
     requires its entity to exist, so a terminal state is reachable only through its
     lifecycle.
  5. **Ordering and duplicates.** Events apply in strictly increasing durable sequence
     against an exact entity revision. A redelivery of the event an entity last applied is
     an idempotent no-op; anything else out of order is rejected rather than applied.

  ### Why an event never carries a phase

  A phase in a payload is a snapshot to install, which is the defect above. Phase is
  derived here from the event under its source guard. The two exceptions are
  `ticket_admitted`, whose phase is the admission outcome R4's own row names ("queued or
  blocked with reason"), and `ticket_unblocked`, whose phase must equal the `resume_phase`
  already stored on the ticket — checked, not trusted.

  ### Why one settlement event does not decide a ticket's fate

  R4a's developer row has three outcomes below, at and beyond the infrastructure limit, but
  `launch_settled` has one fixed effect: close the execution, consume one infrastructure
  ordinal, and return the ticket to `queued` retaining the same nonterminal attempt. The
  other two outcomes are expressed by emitting a second event in the same bundle —
  `ticket_parked` at the limit, `attempt_settled` on exhaustion — which the protected
  discriminator selects between as plan alternatives. Keeping each event's effect fixed is
  what lets a bound projection equal the result of applying its bound event, and it is why
  the discriminator selects among alternatives rather than among payload values.
  """

  import Kernel, except: [apply: 2]

  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  @terminal_ticket_phases ~w(integrated rejected cancelled)

  # Every phase in which R4a can block work at its infrastructure limit. `blocked` is
  # absent: a ticket already blocked is not blocked again, and `exhausted` has its own
  # reset row.
  @blockable_phases ~w(queued developing awaiting_review reviewing ready_to_integrate
                       integrating)

  # Cleanup evidence about an already-terminal ticket's processes. Each records a fact
  # about an execution and none moves the ticket, so none can resurrect a terminal one.
  @terminal_cleanup_events ~w(stream_sealed execution_observed developer_closed
                              worker_closed reviewer_closed)
  @creating_types ~w(ticket_admitted objective_created)

  @doc """
  Folds one validated event into `state`.

  Returns the unchanged state for an idempotent redelivery, and an error for an invalid
  state, an invalid event, an out-of-order or stale event, or an event whose source-state
  guard does not hold.
  """
  @spec apply(term(), term()) :: {:ok, map()} | {:error, atom()}
  def apply(state, event) do
    with :ok <- check_state(state),
         :ok <- Event.validate(event),
         :ok <- check_entity_addressing(event),
         {:ok, kind} <- Event.entity_kind(event["type"]) |> ok_or(:unknown_entity_kind),
         :duplicate <- classify(state, event, kind) do
      {:ok, state}
    else
      :fresh -> advance(state, event)
      {:error, _reason} = error -> error
    end
  rescue
    _ -> {:error, :kernel_raised}
  end

  defp check_state(state), do: if(State.valid?(state), do: :ok, else: {:error, :invalid_state})

  # The control entity is a singleton, so its identifier is fixed rather than caller-chosen.
  # A per-command control identifier would let two commands each advance "the" control.
  defp check_entity_addressing(%{"entity_kind" => "control", "entity_id" => "control"}), do: :ok

  defp check_entity_addressing(%{"entity_kind" => "control"}),
    do: {:error, :invalid_control_entity}

  defp check_entity_addressing(event) do
    {:ok, keys} = Event.payload_keys(event["type"])
    id_key = if event["entity_kind"] == "ticket", do: "ticket_id", else: "objective_id"

    cond do
      id_key not in keys -> :ok
      event["payload"][id_key] == event["entity_id"] -> :ok
      true -> {:error, :entity_id_disagrees_with_payload}
    end
  end

  # A redelivery of the event this entity last applied changes nothing, which is what
  # "duplicate event identity is idempotent" requires. Detecting it per entity rather than
  # by remembering every event id keeps the check O(1) in state size: a genuine duplicate
  # is a redelivery of the most recent event on that entity, and a repeat that arrives
  # after a later event on the same entity is stale, which the revision check rejects.
  defp classify(state, event, kind) do
    if fetch_entity(state, event, kind)["last_event_id"] == event["event_id"] or
         state["last_event_id"] == event["event_id"],
       do: :duplicate,
       else: :fresh
  end

  defp fetch_entity(state, _event, "control"), do: state["control"]
  defp fetch_entity(state, event, "ticket"), do: state["tickets"][event["entity_id"]] || %{}
  defp fetch_entity(state, event, "objective"), do: state["objectives"][event["entity_id"]] || %{}

  defp advance(state, event) do
    {:ok, kind} = Event.entity_kind(event["type"])

    with :ok <- check_sequence(state, event),
         {:ok, entity} <- resolve_entity(state, event, kind),
         :ok <- check_revision(entity, event),
         {:ok, updated} <- transition(entity, event, state) do
      {:ok, commit(state, event, kind, updated)}
    end
  end

  defp check_sequence(%{"last_sequence" => nil}, _event), do: :ok

  defp check_sequence(%{"last_sequence" => last}, event),
    do: if(event["sequence"] > last, do: :ok, else: {:error, :out_of_order_event})

  # Creation is the only way an entity enters state, and it cannot overwrite one.
  defp resolve_entity(state, event, kind) do
    existing = existing_entity(state, event, kind)

    case {event["type"] in @creating_types, existing} do
      {true, nil} -> {:ok, :absent}
      {true, _} -> {:error, :entity_already_exists}
      {false, nil} -> {:error, :unknown_entity}
      {false, entity} -> {:ok, entity}
    end
  end

  defp existing_entity(state, _event, "control"), do: state["control"]
  defp existing_entity(state, event, "ticket"), do: state["tickets"][event["entity_id"]]
  defp existing_entity(state, event, "objective"), do: state["objectives"][event["entity_id"]]

  defp check_revision(:absent, event),
    do: if(event["entity_revision"] == 0, do: :ok, else: {:error, :stale_entity_revision})

  defp check_revision(entity, event),
    do:
      if(event["entity_revision"] == entity["revision"],
        do: :ok,
        else: {:error, :stale_entity_revision}
      )

  defp commit(state, event, kind, entity) do
    entity =
      entity
      |> Map.put("revision", event["entity_revision"] + 1)
      |> Map.put("last_event_id", event["event_id"])

    state
    |> put_entity(kind, event["entity_id"], entity)
    |> Map.put("last_sequence", event["sequence"])
    |> Map.put("last_event_id", event["event_id"])
  end

  defp put_entity(state, "control", _id, entity), do: Map.put(state, "control", entity)
  defp put_entity(state, "ticket", id, entity), do: put_in(state, ["tickets", id], entity)
  defp put_entity(state, "objective", id, entity), do: put_in(state, ["objectives", id], entity)

  # ── Transitions ────────────────────────────────────────────────────────────────────
  #
  # Each clause states the source state its R4 row names and rejects anything else. No
  # clause writes "revision" or "last_event_id": commit/4 owns those, so a transition
  # cannot silently decline to advance an entity it mutated.

  defp transition(entity, event, state) do
    with :ok <- refuse_terminal_ticket(entity, event) do
      do_transition(event["type"], entity, event, state)
    end
  end

  # R4: "integrated/rejected/cancelled; ordinary launch/result/completion command | Reject
  # transition; preserve terminal facts. New work requires explicit admission linked to
  # predecessor". Enforced once here rather than per row, because a row that forgets it is
  # indistinguishable from one that has no opinion.
  #
  # Found by a seeded reachability walk: without it a cancelled ticket accepted
  # cancellation_finalized 97 times in one walk, advancing its revision each time. Note
  # `exhausted` is deliberately absent - R4's reset row makes it recoverable.
  #
  # R4 rejects a terminal *transition* and preserves terminal facts. Recording that a
  # process terminated preserves such a fact rather than overwriting one, so cleanup
  # evidence is not a transition and is not refused. Refusing it was over-broad: an
  # integrated ticket could never close its integration execution and so reported a live
  # execution forever, contradicting R4a's "reconstructs ... no live execution".
  defp refuse_terminal_ticket(entity, event) do
    if event["entity_kind"] == "ticket" and is_map(entity) and
         entity["phase"] in @terminal_ticket_phases and
         event["type"] not in @terminal_cleanup_events and
         not finalizing_integrated_cancel?(entity, event),
       do: {:error, :ticket_terminal},
       else: :ok
  end

  # R4: "Objective without admitted spec; broad steering".
  defp do_transition("objective_created", :absent, event, _state) do
    payload = event["payload"]

    {:ok,
     %{
       "objective_id" => payload["objective_id"],
       "planning_owner_id" => payload["planning_owner_id"],
       "proposals" => %{},
       "infrastructure" => State.infrastructure(State.objective_roles())
     }}
  end

  # R4: "PM proposal is evidence, not authority" — recorded, never admitting a ticket.
  defp do_transition("pm_proposal_recorded", objective, event, _state) do
    payload = event["payload"]

    if Map.has_key?(objective["proposals"], payload["proposal_id"]) do
      {:error, :duplicate_proposal}
    else
      proposal = %{"proposal_id" => payload["proposal_id"], "operation" => payload["operation"]}
      {:ok, put_in(objective, ["proposals", payload["proposal_id"]], proposal)}
    end
  end

  # R4a PM planning row. The planning owner is kept and no proposal is inferred; the
  # objective carries no phase to move.
  defp do_transition(type, objective, _event, _state)
       when type == "pm_launch_planned",
       do: {:ok, objective}

  # R4a's PM row: "Below the PM limit, return to its PM queue; at the limit or without
  # current allocation, block as pm_launch_infrastructure or pm_budget." The limit is the
  # objective's own, which is why the objective carries infrastructure at all.
  defp do_transition("pm_launch_settled", objective, _event, _state),
    do: {:ok, consume_infrastructure_ordinal(objective, "pm")}

  # R4: "draft; specific spec or valid PM create" — admission yields queued or blocked.
  defp do_transition("ticket_admitted", :absent, event, _state) do
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
  defp do_transition("ticket_amended", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(queued blocked)),
         :ok <- require_no_active_attempt(ticket) do
      {:ok,
       ticket
       |> Map.put("spec_revision_id", event["payload"]["spec_revision_id"])
       |> Map.put("spec", event["payload"]["spec"])}
    end
  end

  # R4: "queued/blocked; PM amend/park" — explicit blocked state with a resume phase.
  defp do_transition("ticket_parked", ticket, event, _state) do
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
  defp do_transition("ticket_blocked", ticket, event, _state) do
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
  defp do_transition("ticket_unblocked", ticket, event, _state) do
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
  defp do_transition("ticket_reset", ticket, _event, _state) do
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
         :ok <- require_no_active_attempt(ticket) do
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

  # R4: "nonterminal ticket; cancel requested" — an orthogonal control that holds phase and
  # evidence while issued effects reconcile. It is not a ticket phase.
  defp do_transition("cancellation_requested", ticket, _event, _state) do
    if ticket["phase"] in @terminal_ticket_phases do
      {:error, :ticket_terminal}
    else
      {:ok, Map.put(ticket, "cancel_requested", true)}
    end
  end

  # R4: "cancel_requested; every owned session AND non-session claim terminal, cleanup
  # reconciled". Finalisation does not itself terminalise the attempt — attempt_settled
  # does — so it requires that to have happened already.
  defp do_transition("cancellation_finalized", ticket, event, _state) do
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

  # R4: "queued; dependencies/resources/profile/reservation eligible" — a fresh attempt
  # unless R4a retained a resumable one, then its launch intent, then developing.
  defp do_transition("launch_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(queued developing)),
         :ok <- require_no_open_developer(ticket),
         :ok <- require_cleanup_complete(ticket),
         {:ok, ticket} <- open_attempt(ticket, payload["attempt_id"]),
         {:ok, ticket} <- add_execution(ticket, payload, "developer") do
      {:ok, Map.put(ticket, "phase", "developing")}
    end
  end

  # R4a developer row: keep the same nonterminal attempt, return developing → queued with
  # resume_phase developing, close the execution, consume one infrastructure ordinal.
  defp do_transition("launch_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         {:ok, ticket} <-
           close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(developer)) do
      {:ok,
       ticket
       |> Map.put("phase", "queued")
       |> Map.put("resume_phase", "developing")
       |> Map.put("reason", "developer_launch_non_started")
       |> consume_infrastructure_ordinal("developer")}
    end
  end

  # R4: "developing; success artifact validates and freezes" — attempt candidate_frozen,
  # ticket awaiting_review, productive generation sealed.
  defp do_transition("artifact_frozen", ticket, event, _state) do
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
  defp do_transition("artifact_blocked", ticket, event, _state) do
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
  defp do_transition("freeze_failed", ticket, event, _state) do
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

  # R4: "any open submission phase; malformed result" — a durable rejected submission. It
  # charges a validation action in the R5 ledger, which is not the kernel's to write, and
  # it moves no phase.
  # R4: "any open submission phase; malformed result | **Durable rejected submission, charge
  # one validation action**; further submission allowed only while **stream open** and
  # budget remains; exhaustion closes execution and exhausts ticket."
  #
  # This accepted the event and changed nothing, so there was no durable record to charge
  # against and the row was unimplementable - the enumeration created the event for exactly
  # this reason and then the reducer dropped it. The charge is recorded on the attempt; the
  # budget it is charged against is protected allocation, so exhaustion arrives as
  # attempt_settled(exhausted) rather than being derived here.
  defp do_transition("submission_rejected", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing reviewing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_open_submission_stream(ticket) do
      {:ok,
       update_active_attempt(ticket, &Map.update!(&1, "rejected_submissions", fn n -> n + 1 end))}
    end
  end

  # R4: "candidate_frozen; developer exit/timeout/abnormal exit" — cleanup observation
  # only. The frozen candidate is preserved and no attempt fails, which is the custody rule
  # the reviewed candidate broke.
  defp do_transition("execution_observed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_not_closed(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_open_lifecycle(payload["lifecycle"]) do
      {:ok,
       update_attempt(ticket, payload["attempt_id"], fn attempt ->
         put_in(
           attempt,
           ["executions", payload["execution_id"], "lifecycle"],
           payload["lifecycle"]
         )
       end)}
    end
  end

  # R4a: "On exit, the broker seals that execution's input stream with its last accepted
  # sequence." Sealing is once-only, so a second seal is refused rather than overwriting.
  defp do_transition("stream_sealed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_unsealed(ticket, payload["attempt_id"], payload["execution_id"]) do
      {:ok,
       update_attempt(ticket, payload["attempt_id"], fn attempt ->
         put_in(
           attempt,
           ["executions", payload["execution_id"], "sealed_sequence"],
           payload["last_accepted_sequence"]
         )
       end)}
    end
  end

  # R4: "kernel requests developer close through broker immediately". Closure is a durable
  # fact about a sealed execution, not an event carrying the unchanged ticket — B2's first
  # named defect. What R4 conditions closure on is the sealed stream, not the phase: rows 8
  # and 9 close the developer after a valid blocked/partial result and after a sealed
  # stream with no candidate at all, and a candidate_frozen guard made both unexpressible.
  defp do_transition("developer_closed", ticket, event, _state) do
    payload = event["payload"]

    # The role check below is redone by close_execution; require_execution is not
    # redundant, because require_sealed indexes into the execution and would raise on one
    # that is absent.
    with :ok <- require_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["attempt_id"], payload["execution_id"]),
         :ok <- require_sealed(ticket, payload["attempt_id"], payload["execution_id"]) do
      close_execution(ticket, payload["attempt_id"], payload["execution_id"], ~w(developer))
    end
  end

  # R4 rows 11, 13 and 22 all require worker closure: "queue fresh developer after all
  # check workers close", "bounded new check-run reservation after cleanup", and
  # "successful ref receipt and prior role/check workers closed". Nothing could express it
  # until now — the enumeration named closure events for the developer and the reviewer and
  # missed the check, build and integration workers, which `require_workers_closed/1` then
  # caught by making the integration row unreachable.
  #
  # The kernel records this closure rather than verifying it. R4 requires verified process
  # or session termination, which is a protected reconciliation fact owned by FR-10; the
  # link from a check execution to its receipt that would let the kernel demand a recorded
  # status first belongs with subcommit 4's check/build/integration workers.
  defp do_transition("worker_closed", ticket, event, _state) do
    payload = event["payload"]

    # `close_execution/4` checks the execution exists and holds one of the roles it is
    # given, so repeating both here was two guards deep enough to look like defence and
    # shallow enough to prove nothing - the mutation sweep reported require_worker_role as
    # surviving even with a test aimed squarely at it, because its sibling caught the same
    # case.
    with :ok <- require_attempt(ticket, payload["attempt_id"]) do
      close_execution(
        ticket,
        payload["attempt_id"],
        payload["execution_id"],
        ~w(check build integration)
      )
    end
  end

  # R4: "candidate_frozen; developer closed, check capacity eligible" — checking attempt,
  # awaiting_review ticket, immutable candidate retained. Requiring developer closure is
  # B2's second named defect: without it the row-11 check route was unschedulable.
  defp do_transition("checks_started", ticket, event, _state) do
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

  defp do_transition("check_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(checking)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         {:ok, ticket} <- add_check(ticket, payload["check_id"]),
         {:ok, ticket} <- add_execution(ticket, payload, "check") do
      {:ok, ticket}
    end
  end

  # R4a check-worker row: preserve the candidate and its phase, infer no check receipt.
  defp do_transition("check_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(checking)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_check(ticket, payload["check_id"]),
         # A check receipt is a write-once sealed result, and R4's integration row wants
         # "all mandatory check receipts passed". Deleting a check that had already
         # recorded `passed` let the attempt reach awaiting_review with a mandatory check
         # simply absent - which `require_checks_passed` cannot see, since it folds over
         # the checks that are still there.
         :ok <- require_check_unsettled(ticket, payload["check_id"]) do
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
  defp do_transition("check_recorded", ticket, event, _state) do
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

  # R4: "awaiting_review; check receipts valid and reviewer capacity available".
  defp do_transition("review_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(awaiting_review)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(awaiting_review)),
         :ok <- require_checks_passed(ticket),
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
  defp do_transition("review_settled", ticket, event, _state) do
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
  defp do_transition("review_recorded", ticket, event, _state) do
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
  defp do_transition("reviewer_closed", ticket, event, _state) do
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

  # R4: "ready_to_integrate; current base/evidence/policy valid".
  defp do_transition("integration_planned", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(ready_to_integrate integrating)),
         :ok <- require_no_ref_receipt(ticket),
         :ok <- require_issuer_terminated(ticket),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         {:ok, ticket} <- add_execution(ticket, event["payload"], "integration") do
      {:ok,
       ticket
       |> Map.put("phase", "integrating")
       |> update_active_attempt(&Map.put(&1, "phase", "integrating"))}
    end
  end

  # R4a integration-worker row: preserve the phase and verified inputs, infer no ref
  # receipt.
  defp do_transition("integration_settled", ticket, event, _state) do
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
  defp do_transition("integration_recorded", ticket, event, _state) do
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
        "infrastructure_failed" ->
          {:ok,
           ticket
           |> Map.put("phase", "blocked")
           |> Map.put("reason", "integration_failure")
           |> Map.put("resume_phase", "ready_to_integrate")}

        _ ->
          {:error, :invalid_integration_outcome}
      end
    end
  end

  # R4: "Attempt disposition | Set once on terminal". The single terminalising event: it
  # seals the active attempt, moves it to prior_attempt_ids so its executions, candidate
  # and review evidence are retained rather than replaced, and clears the active slot.
  defp do_transition("attempt_settled", ticket, event, _state) do
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

  # R4 Control entity: orthogonal pause/drain flags and a stop status, never ticket phases.
  defp do_transition("control_changed", control, event, _state) do
    payload = event["payload"]

    with :ok <- require_boolean(payload["paused"]),
         :ok <- require_boolean(payload["draining"]),
         :ok <- require_stop_status(payload["stop_status"]),
         :ok <- require_control_fact(payload["control"]) do
      {:ok,
       control
       |> Map.put("paused", payload["paused"])
       |> Map.put("draining", payload["draining"])
       |> Map.put("stop_status", payload["stop_status"])
       |> Map.put("control_id", payload["control"]["control_id"])
       |> Map.put("control_revision", payload["control"]["control_revision"])}
    end
  end

  defp do_transition("build_planned", ticket, event, _state) do
    with :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         {:ok, ticket} <- add_execution(ticket, event["payload"], "build") do
      {:ok, ticket}
    end
  end

  defp do_transition("build_settled", ticket, event, _state) do
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

  # ── Attempt and execution helpers ──────────────────────────────────────────────────

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

  # R4a: "Create a fresh attempt unless R4a retained a resumable developer attempt". A
  # retained attempt is reused; an identifier that already names a *different* attempt is
  # refused rather than overwriting one, which is how the reviewed candidate lost evidence.
  # R4: "Create a fresh attempt **unless R4a retained a resumable developer attempt**", and
  # R4a: "Keep the **same** nonterminal attempt". A launch naming a new id while one was
  # retained left the old attempt nonterminal, absent from prior_attempt_ids and owned by
  # nothing - the validator permits that shape, and the prober always reused the active id,
  # so neither could see it.
  defp open_attempt(ticket, attempt_id) do
    cond do
      ticket["active_attempt_id"] == attempt_id and not is_nil(attempt_id) ->
        {:ok, ticket}

      not is_nil(ticket["active_attempt_id"]) ->
        {:error, :retained_attempt_must_be_reused}

      Map.has_key?(ticket["attempts"], attempt_id) ->
        {:error, :attempt_already_exists}

      true ->
        attempt = %{
          "attempt_id" => attempt_id,
          "phase" => "active",
          "disposition" => nil,
          "reason_code" => nil,
          "candidate_id" => nil,
          "sealed_generation" => nil,
          "ref_receipt_id" => nil,
          "executions" => %{},
          "checks" => %{},
          "review" => nil,
          "policy_empty_checks" => false,
          "rejected_submissions" => 0
        }

        {:ok,
         ticket
         |> put_in(["attempts", attempt_id], attempt)
         |> Map.put("active_attempt_id", attempt_id)}
    end
  end

  defp add_execution(ticket, payload, role) do
    execution_id = payload["authority"]["execution_id"]

    cond do
      not is_binary(execution_id) or execution_id == "" ->
        {:error, :invalid_execution_identity}

      Map.has_key?(active_attempt(ticket)["executions"], execution_id) ->
        {:error, :execution_already_exists}

      true ->
        execution = %{
          "execution_id" => execution_id,
          "role" => role,
          "lifecycle" => "pending",
          "result" => nil,
          "sealed_sequence" => nil
        }

        {:ok, update_active_attempt(ticket, &put_in(&1, ["executions", execution_id], execution))}
    end
  end

  # R4a: a proved non-start "closes the execution". Every *_settled row calls this, which
  # is why each carries an execution_id. Only launch_settled did before, so reviewer,
  # check, build and integration executions stayed open with nothing able to close them -
  # reviewer_closed requires the reviewing phase, so a settled reviewer execution was
  # unclosable forever, and R4's "prior role/check workers closed" could never hold.
  defp close_execution(ticket, attempt_id, execution_id, roles) do
    with :ok <- require_execution(ticket, attempt_id, execution_id),
         :ok <- require_execution_role(ticket, attempt_id, execution_id, roles),
         :ok <- require_not_closed(ticket, attempt_id, execution_id) do
      {:ok,
       update_attempt(
         ticket,
         attempt_id,
         &put_in(&1, ["executions", execution_id, "lifecycle"], "closed")
       )}
    end
  end

  # R4a: "The durable infrastructure ordinal consumes that allowance even though a proved
  # non-start refunds the process-start unit." The allowance is per role and work owner, so
  # a reviewer non-start must not spend the developer's. One counter per ticket was the
  # state-shape defect behind finding 12: decide/3 cannot evaluate "below the infrastructure
  # limit" for a role whose consumption it cannot see.
  defp consume_infrastructure_ordinal(owner, role),
    do: update_in(owner, ["infrastructure", "ordinals", role], &(&1 + 1))

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
  defp add_check(ticket, check_id) do
    case active_attempt(ticket)["checks"][check_id] do
      nil ->
        {:ok,
         update_active_attempt(ticket, &put_in(&1, ["checks", check_id], fresh_check(check_id)))}

      check ->
        if retryable_check?(check),
          do:
            {:ok,
             update_active_attempt(
               ticket,
               &put_in(&1, ["checks", check_id], fresh_check(check_id))
             )},
          else: {:error, :check_already_exists}
    end
  end

  defp fresh_check(check_id),
    do: %{"check_id" => check_id, "status" => "pending", "reason_code" => nil}

  defp retryable_check?(%{"status" => "timed_out"}), do: true

  defp retryable_check?(%{"status" => "failed", "reason_code" => "infrastructure_failed"}),
    do: true

  defp retryable_check?(_check), do: false

  defp active_attempt(ticket), do: ticket["attempts"][ticket["active_attempt_id"]] || %{}

  # R4 orders closure *after* settlement in four rows - "close developer, then queue
  # fresh", "queue fresh developer after all check workers close", "close/seal reviewer,
  # then queued fresh developer", "bounded new check-run reservation after cleanup" - and
  # R4a's restart sentence requires reconstructing "no live execution". Addressing an
  # execution through the active-attempt pointer made every one of them unreachable the
  # instant attempt_settled cleared it, so every integrated ticket reported a live
  # execution forever. An execution belongs to the attempt that created it, whether or not
  # that attempt is still active.
  defp attempt(ticket, attempt_id), do: ticket["attempts"][attempt_id] || %{}

  # R4: "Execution result | Separate write-once sealed result: valid, blocked, partial,
  # invalid, none". The field was declared in the state and never written by any event, so
  # a declared entity state had no producer — the same class of gap as the codec's
  # unproduced output kinds, one level up. Each submission-evidence row seals the
  # developer execution's result, and the seal is write-once because R4 says so.
  defp seal_developer_result(ticket, attempt_id, result) do
    executions = attempt(ticket, attempt_id)["executions"] || %{}

    case Elixir.Enum.find(executions, fn {_id, execution} ->
           execution["role"] == "developer" and is_nil(execution["result"])
         end) do
      {execution_id, _execution} ->
        update_attempt(
          ticket,
          attempt_id,
          &put_in(&1, ["executions", execution_id, "result"], result)
        )

      nil ->
        ticket
    end
  end

  defp update_attempt(ticket, attempt_id, fun),
    do: update_in(ticket, ["attempts", attempt_id], fun)

  defp require_attempt(ticket, attempt_id),
    do:
      if(is_binary(attempt_id) and is_map(ticket["attempts"][attempt_id]),
        do: :ok,
        else: {:error, :unknown_attempt}
      )

  defp update_active_attempt(ticket, fun),
    do: update_in(ticket, ["attempts", ticket["active_attempt_id"]], fun)

  # ── Guards ─────────────────────────────────────────────────────────────────────────

  defp require_phase(ticket, phases),
    do: if(ticket["phase"] in phases, do: :ok, else: {:error, :wrong_source_phase})

  defp require_attempt_phase(ticket, phases),
    do:
      if(active_attempt(ticket)["phase"] in phases,
        do: :ok,
        else: {:error, :wrong_attempt_phase}
      )

  defp require_active_attempt(ticket, attempt_id) do
    if is_binary(attempt_id) and ticket["active_attempt_id"] == attempt_id,
      do: :ok,
      else: {:error, :not_the_active_attempt}
  end

  defp require_no_active_attempt(ticket),
    do: if(is_nil(ticket["active_attempt_id"]), do: :ok, else: {:error, :attempt_still_active})

  # R4's cancel row concludes a cancel that raced an integration: "If integration occurred:
  # integrated and cancel_finalized(after_integration); suppress deployment". By the time
  # that finalisation arrives the attempt has already settled `integrated` and the ticket is
  # already terminal, so a blanket terminal refusal made R4's own second branch unreachable
  # - the branch exists precisely for the case where the ticket is integrated. It preserves
  # the terminal fact rather than overwriting it, which is what R4's terminal row protects.
  defp finalizing_integrated_cancel?(ticket, event),
    do:
      event["type"] == "cancellation_finalized" and ticket["phase"] == "integrated" and
        ticket["cancel_requested"]

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
    open? =
      Elixir.Enum.any?(ticket["attempts"], fn {_id, attempt} ->
        Elixir.Enum.any?(attempt["executions"] || %{}, fn {_id, execution} ->
          execution["lifecycle"] != "closed"
        end)
      end)

    if open?, do: {:error, :executions_not_closed}, else: :ok
  end

  defp require_cancel_requested(ticket),
    do: if(ticket["cancel_requested"], do: :ok, else: {:error, :cancel_not_requested})

  defp require_execution(ticket, attempt_id, execution_id),
    do:
      if(Map.has_key?(attempt(ticket, attempt_id)["executions"] || %{}, execution_id),
        do: :ok,
        else: {:error, :unknown_execution}
      )

  defp require_check(ticket, check_id),
    do:
      if(Map.has_key?(active_attempt(ticket)["checks"] || %{}, check_id),
        do: :ok,
        else: {:error, :unknown_check}
      )

  defp require_sealed(ticket, attempt_id, execution_id) do
    if is_integer(attempt(ticket, attempt_id)["executions"][execution_id]["sealed_sequence"]),
      do: :ok,
      else: {:error, :stream_not_sealed}
  end

  defp require_unsealed(ticket, attempt_id, execution_id) do
    if is_nil(attempt(ticket, attempt_id)["executions"][execution_id]["sealed_sequence"]),
      do: :ok,
      else: {:error, :stream_already_sealed}
  end

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
      Elixir.Enum.any?(active_attempt(ticket)["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "integration" and execution["lifecycle"] != "closed"
      end)

    if open?, do: {:error, :issuer_not_terminated}, else: :ok
  end

  # R4: "successful ref receipt and prior role/check workers closed".
  defp require_workers_closed(ticket) do
    executions = active_attempt(ticket)["executions"] || %{}

    closed? =
      Elixir.Enum.all?(executions, fn {_id, execution} ->
        execution["role"] == "integration" or execution["lifecycle"] == "closed"
      end)

    if closed?, do: :ok, else: {:error, :workers_not_closed}
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

  # R4a binds every settlement and closure to the execution it names: "Close **only the
  # failed reviewer execution**". Correction 8 of 202b8e4 applied that to reviewer_closed
  # and not to review_settled, which is why the latter could close a check execution and
  # leak the reviewer's. The binding is therefore one rule over the vocabulary rather than
  # a guard attached to whichever event a walk happened to reach.
  defp require_execution_role(ticket, attempt_id, execution_id, roles) do
    if attempt(ticket, attempt_id)["executions"][execution_id]["role"] in roles,
      do: :ok,
      else: {:error, :wrong_execution_role}
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

      # R4: "ready_to_integrate/integrating; accepted base moved **before issuance**". From
      # ready_to_integrate no integration effect exists yet, so the clause is satisfied by
      # the phase. From `integrating` one does, and the clause is only satisfied while it
      # has not been issued - which in this state is an execution still `pending`. R1 owns
      # the real issuance boundary; `pending` is the kernel's faithful proxy for it, and is
      # recorded as an interpretation rather than presented as the contract's own words.
      "superseded_base" ->
        with :ok <- require_attempt_phase(ticket, ~w(ready_to_integrate integrating)) do
          if attempt["phase"] == "integrating" and integration_issued?(attempt),
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

  # R4 row 12 is "checking; **actual check assertion fails**", and its outcome is terminal.
  # Counting a timeout as an assertion failure terminalised an attempt row 13 says to
  # preserve, which is the row this kernel was misreading as that one.
  defp integration_issued?(attempt),
    do:
      Elixir.Enum.any?(attempt["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "integration" and execution["lifecycle"] != "pending"
      end)

  defp failed_check?(attempt),
    do:
      Elixir.Enum.any?(attempt["checks"] || %{}, fn {_id, check} ->
        check["status"] == "failed" and check["reason_code"] == "assertion_failed"
      end)

  # "further submission allowed only while stream **open**". Once the broker has sealed the
  # stream, a later arrival is late evidence: R4a says messages after sealing are "never
  # silently attached to a new attempt", so they cannot be charged as a fresh submission
  # either.
  defp require_open_submission_stream(ticket) do
    open? =
      Elixir.Enum.any?(active_attempt(ticket)["executions"] || %{}, fn {_id, execution} ->
        execution["role"] in ~w(developer reviewer) and is_nil(execution["sealed_sequence"]) and
          execution["lifecycle"] != "closed"
      end)

    if open?, do: :ok, else: {:error, :submission_stream_sealed}
  end

  # R4a returns a developer non-start to `queued` with `resume_phase: developing` and keeps
  # the attempt. Resuming therefore lands the ticket in `developing` holding an attempt
  # whose only developer execution is the closed non-start, and a retry could not be
  # launched from there - the ticket was stranded, and artifact_frozen was then accepted
  # for a developer that had never run. A launch is legal from either phase, so long as no
  # developer is already running: that is what "bounded developer retry" needs, and what
  # stops a second developer being launched beside a live one.
  defp require_no_open_developer(ticket) do
    open? =
      Elixir.Enum.any?(active_attempt(ticket)["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "developer" and execution["lifecycle"] != "closed"
      end)

    if open?, do: {:error, :developer_already_running}, else: :ok
  end

  # Three R4 rows order a fresh developer after cleanup, in three phrasings of one rule:
  # "after cleanup queue fresh bounded attempt", "queue fresh developer **after all check
  # workers close**", and "close/seal reviewer, **then** queued fresh developer". None was
  # a guard, and `require_no_open_developer/1` reads only the active attempt, so its stated
  # purpose held within one attempt while a new attempt could launch beside a live reviewer
  # or check worker of the attempt just settled.
  #
  # `unknown` blocks too, per R4: "If cleanup is unknown, block affected work and retain
  # capacity". Only `closed` is cleanup.
  defp require_cleanup_complete(ticket) do
    open =
      for {_aid, attempt} <- ticket["attempts"],
          {execution_id, execution} <- attempt["executions"] || %{},
          execution["lifecycle"] != "closed",
          do: execution_id

    if open == [], do: :ok, else: {:error, :cleanup_incomplete}
  end

  # R4's freeze row is "developing; success artifact validates and freezes" - a developer
  # must actually have been running to produce one. Without this a ticket resumed to
  # developing could freeze a candidate with no developer execution open at all.
  defp require_running_developer(ticket) do
    running? =
      Elixir.Enum.any?(active_attempt(ticket)["executions"] || %{}, fn {_id, execution} ->
        execution["role"] == "developer" and execution["lifecycle"] != "closed"
      end)

    if running?, do: :ok, else: {:error, :no_running_developer}
  end

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

  # Closure is terminal for an execution. Refusing only a `closed` *target* was not
  # enough: an observation could reopen an execution that developer_closed or
  # reviewer_closed had already closed, which undoes exactly the custody B2 asks for and
  # left R4's integration row unsatisfiable, since "prior role/check workers closed" could
  # be falsified after the fact. Found by a seeded reachability walk, which kept arriving
  # at `integrating` with a developer and reviewer execution back in `running`.
  defp require_not_closed(ticket, attempt_id, execution_id) do
    if attempt(ticket, attempt_id)["executions"][execution_id]["lifecycle"] == "closed",
      do: {:error, :execution_already_closed},
      else: :ok
  end

  # R4: "closed requires verified process/session termination or proved non-start". An
  # ordinary observation is neither, so `execution_observed` may move an execution through
  # every lifecycle except the one that ends it. Closure has its own guarded events, which
  # is the generalisation of B2's finding that `reviewer_closed` trusted an observation
  # string.
  defp require_open_lifecycle(lifecycle) do
    if lifecycle in (State.execution_lifecycles() -- ["closed"]),
      do: :ok,
      else: {:error, :invalid_execution_lifecycle}
  end

  defp require_check_status(status),
    do: if(status in State.check_statuses(), do: :ok, else: {:error, :invalid_check_status})

  defp require_verdict(verdict),
    do: if(verdict in State.verdicts(), do: :ok, else: {:error, :invalid_verdict})

  # R4's row is "valid blocked/partial result", which are two of the five sealed result
  # values; the other three are produced by their own rows.
  defp require_blocked_result(result),
    do: if(result in ~w(blocked partial), do: :ok, else: {:error, :invalid_blocked_result})

  defp require_disposition(disposition),
    do: if(disposition in State.dispositions(), do: :ok, else: {:error, :invalid_disposition})

  defp require_boolean(value),
    do: if(is_boolean(value), do: :ok, else: {:error, :invalid_control_flag})

  defp require_stop_status(status) do
    if status in ~w(running stop_requested stop_blocked stop_completed),
      do: :ok,
      else: {:error, :invalid_stop_status}
  end

  # control_fact_v1 is a protected derivation. The kernel checks its shape and copies its
  # identity; it never invents one, and a plain caller map cannot stand in for it.
  defp require_control_fact(control) do
    if is_map(control) and not is_struct(control) and control["schema_version"] == 1 and
         is_binary(control["control_id"]) and control["control_id"] != "" and
         is_integer(control["control_revision"]) and control["control_revision"] >= 0,
       do: :ok,
       else: {:error, :invalid_control_fact}
  end

  defp ok_or({:ok, value}, _reason), do: {:ok, value}
  defp ok_or(:error, reason), do: {:error, reason}
end
