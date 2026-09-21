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
  blocked with reason"), and `ticket_resumed`, whose phase must equal the `resume_phase`
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

  defp transition(entity, event, state), do: do_transition(event["type"], entity, event, state)

  # R4: "Objective without admitted spec; broad steering".
  defp do_transition("objective_created", :absent, event, _state) do
    payload = event["payload"]

    {:ok,
     %{
       "objective_id" => payload["objective_id"],
       "planning_owner_id" => payload["planning_owner_id"],
       "proposals" => %{}
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
       when type in ~w(pm_launch_planned pm_launch_settled),
       do: {:ok, objective}

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
         "resume_phase" => nil,
         "cancel_requested" => false,
         "attempts" => %{},
         "active_attempt_id" => nil,
         "prior_attempt_ids" => [],
         "infrastructure" => %{"ordinal" => 0, "generation" => 0}
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

    with :ok <- require_phase(ticket, ~w(queued blocked developing awaiting_review)),
         :ok <- require_resume_phase(payload["resume_phase"]) do
      {:ok,
       ticket
       |> Map.put("phase", "blocked")
       |> Map.put("reason", payload["reason"])
       |> Map.put("resume_phase", payload["resume_phase"])}
    end
  end

  # R4: "blocked; explicit resume or recorded dependency/resource recovery" — returns to
  # the stored resume_phase. The event's phase is checked against it, never trusted.
  defp do_transition("ticket_resumed", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(blocked)) do
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
    with :ok <- require_phase(ticket, ~w(exhausted)),
         :ok <- require_no_active_attempt(ticket) do
      {:ok,
       ticket
       |> Map.put("phase", "queued")
       |> Map.put("reason", nil)
       |> Map.put("resume_phase", nil)
       |> update_in(["infrastructure", "generation"], &(&1 + 1))
       |> put_in(["infrastructure", "ordinal"], 0)}
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
         :ok <- require_no_active_attempt(ticket) do
      case event["payload"]["disposition"] do
        "cancelled" -> {:ok, Map.put(ticket, "phase", "cancelled")}
        "after_integration" -> {:ok, Map.put(ticket, "phase", "integrated")}
        _ -> {:error, :invalid_cancellation_disposition}
      end
    end
  end

  # R4: "queued; dependencies/resources/profile/reservation eligible" — a fresh attempt
  # unless R4a retained a resumable one, then its launch intent, then developing.
  defp do_transition("launch_planned", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(queued)),
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
         {:ok, ticket} <- close_execution(ticket, payload["execution_id"]) do
      {:ok,
       ticket
       |> Map.put("phase", "queued")
       |> Map.put("resume_phase", "developing")
       |> Map.put("reason", "developer_launch_non_started")
       |> update_in(["infrastructure", "ordinal"], &(&1 + 1))}
    end
  end

  # R4: "developing; success artifact validates and freezes" — attempt candidate_frozen,
  # ticket awaiting_review, productive generation sealed.
  defp do_transition("artifact_frozen", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(active)) do
      {:ok,
       ticket
       |> Map.put("phase", "awaiting_review")
       |> update_active_attempt(fn attempt ->
         attempt
         |> Map.put("phase", "candidate_frozen")
         |> Map.put("candidate_id", payload["candidate_id"])
         |> Map.put("sealed_generation", payload["sealed_generation"])
       end)}
    end
  end

  # R4: "developing; valid blocked/partial result" — blocked ticket, no review. The attempt
  # is terminalised by attempt_settled, not here.
  defp do_transition("artifact_blocked", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(developing)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(active)) do
      {:ok,
       ticket
       |> Map.put("phase", "blocked")
       |> Map.put("reason", event["payload"]["reason"])
       |> Map.put("resume_phase", "developing")}
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
  defp do_transition("submission_rejected", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(developing reviewing)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]) do
      {:ok, ticket}
    end
  end

  # R4: "candidate_frozen; developer exit/timeout/abnormal exit" — cleanup observation
  # only. The frozen candidate is preserved and no attempt fails, which is the custody rule
  # the reviewed candidate broke.
  defp do_transition("execution_observed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_open_lifecycle(payload["lifecycle"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
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

    with :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_unsealed(ticket, payload["execution_id"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
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
  # named defect. It requires the candidate frozen and the stream sealed first.
  defp do_transition("developer_closed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(candidate_frozen)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_sealed(ticket, payload["execution_id"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
         put_in(attempt, ["executions", payload["execution_id"], "lifecycle"], "closed")
       end)}
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

    with :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_worker_role(ticket, payload["execution_id"]) do
      {:ok,
       update_active_attempt(ticket, fn attempt ->
         put_in(attempt, ["executions", payload["execution_id"], "lifecycle"], "closed")
       end)}
    end
  end

  # R4: "candidate_frozen; developer closed, check capacity eligible" — checking attempt,
  # awaiting_review ticket, immutable candidate retained. Requiring developer closure is
  # B2's second named defect: without it the row-11 check route was unschedulable.
  defp do_transition("checks_started", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(awaiting_review)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]),
         :ok <- require_attempt_phase(ticket, ~w(candidate_frozen)),
         :ok <- require_developer_closed(ticket) do
      {:ok, update_active_attempt(ticket, &Map.put(&1, "phase", "checking"))}
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
         :ok <- require_check(ticket, payload["check_id"]) do
      {:ok,
       ticket
       |> update_active_attempt(fn attempt ->
         put_in(attempt, ["checks", payload["check_id"], "status"], "cancelled")
       end)
       |> update_in(["infrastructure", "ordinal"], &(&1 + 1))}
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
         :ok <- require_check_status(payload["status"]) do
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
    with :ok <- require_phase(ticket, ~w(reviewing)),
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]) do
      {:ok,
       ticket
       |> Map.put("phase", "awaiting_review")
       |> Map.put("resume_phase", "awaiting_review")
       |> update_active_attempt(fn attempt ->
         attempt |> Map.put("phase", "awaiting_review") |> Map.put("review", nil)
       end)
       |> update_in(["infrastructure", "ordinal"], &(&1 + 1))}
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
  defp do_transition("reviewer_closed", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_attempt_phase(ticket, ~w(reviewing)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_sealed(ticket, payload["execution_id"]),
         {:ok, verdict} <- fetch_verdict(ticket) do
      ticket =
        update_active_attempt(ticket, fn attempt ->
          put_in(attempt, ["executions", payload["execution_id"], "lifecycle"], "closed")
        end)

      case verdict do
        "approved" ->
          {:ok,
           ticket
           |> Map.put("phase", "ready_to_integrate")
           |> update_active_attempt(&Map.put(&1, "phase", "ready_to_integrate"))}

        _ ->
          {:ok, ticket}
      end
    end
  end

  # R4: "ready_to_integrate; current base/evidence/policy valid".
  defp do_transition("integration_planned", ticket, event, _state) do
    with :ok <- require_phase(ticket, ~w(ready_to_integrate)),
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
         :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]) do
      {:ok,
       ticket
       |> Map.put("phase", "ready_to_integrate")
       |> update_active_attempt(&Map.put(&1, "phase", "ready_to_integrate"))
       |> update_in(["infrastructure", "ordinal"], &(&1 + 1))}
    end
  end

  # R4: "integrating; successful ref receipt and prior role/check workers closed" →
  # integrated ticket. The terminal integrated attempt is set by attempt_settled.
  defp do_transition("integration_recorded", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_phase(ticket, ~w(integrating)),
         :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_execution(ticket, payload["execution_id"]),
         :ok <- require_workers_closed(ticket) do
      case payload["outcome"] do
        "ref_created" -> {:ok, Map.put(ticket, "phase", "integrated")}
        "no_ref_change" -> {:ok, ticket}
        _ -> {:error, :invalid_integration_outcome}
      end
    end
  end

  # R4: "Attempt disposition | Set once on terminal". The single terminalising event: it
  # seals the active attempt, moves it to prior_attempt_ids so its executions, candidate
  # and review evidence are retained rather than replaced, and clears the active slot.
  defp do_transition("attempt_settled", ticket, event, _state) do
    payload = event["payload"]

    with :ok <- require_active_attempt(ticket, payload["attempt_id"]),
         :ok <- require_disposition(payload["disposition"]) do
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
    with :ok <- require_active_attempt(ticket, event["payload"]["attempt_id"]) do
      {:ok, update_in(ticket, ["infrastructure", "ordinal"], &(&1 + 1))}
    end
  end

  # ── Attempt and execution helpers ──────────────────────────────────────────────────

  # R4: "checking; all mandatory check receipts passed" → awaiting_review attempt. An
  # explicit policy-empty set follows the same guarded transition.
  defp maybe_finish_checks(attempt) do
    statuses = Elixir.Enum.map(attempt["checks"], fn {_id, check} -> check["status"] end)

    if statuses != [] and Elixir.Enum.all?(statuses, &(&1 == "passed")),
      do: Map.put(attempt, "phase", "awaiting_review"),
      else: attempt
  end

  # Only the dispositions R4 makes terminal for the whole ticket move the ticket. A
  # needs_correction or failed attempt returns the ticket to queued for a fresh bounded
  # attempt; the row's drain and exhaustion alternatives are emitted as a second event.
  defp apply_terminal_phase(ticket, disposition) do
    case disposition do
      "integrated" -> Map.put(ticket, "phase", "integrated")
      "rejected" -> Map.put(ticket, "phase", "rejected")
      "cancelled" -> ticket
      "exhausted" -> Map.put(ticket, "phase", "exhausted")
      "blocked" -> ticket
      _ -> Map.put(ticket, "phase", "queued")
    end
  end

  # R4a: "Create a fresh attempt unless R4a retained a resumable developer attempt". A
  # retained attempt is reused; an identifier that already names a *different* attempt is
  # refused rather than overwriting one, which is how the reviewed candidate lost evidence.
  defp open_attempt(ticket, attempt_id) do
    cond do
      ticket["active_attempt_id"] == attempt_id and not is_nil(attempt_id) ->
        {:ok, ticket}

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
          "executions" => %{},
          "checks" => %{},
          "review" => nil
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

  defp close_execution(ticket, execution_id) do
    with :ok <- require_execution(ticket, execution_id) do
      {:ok,
       update_active_attempt(
         ticket,
         &put_in(&1, ["executions", execution_id, "lifecycle"], "closed")
       )}
    end
  end

  defp add_check(ticket, check_id) do
    if Map.has_key?(active_attempt(ticket)["checks"], check_id) do
      {:error, :check_already_exists}
    else
      check = %{"check_id" => check_id, "status" => "pending", "reason_code" => nil}
      {:ok, update_active_attempt(ticket, &put_in(&1, ["checks", check_id], check))}
    end
  end

  defp active_attempt(ticket), do: ticket["attempts"][ticket["active_attempt_id"]] || %{}

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

  defp require_cancel_requested(ticket),
    do: if(ticket["cancel_requested"], do: :ok, else: {:error, :cancel_not_requested})

  defp require_execution(ticket, execution_id),
    do:
      if(Map.has_key?(active_attempt(ticket)["executions"] || %{}, execution_id),
        do: :ok,
        else: {:error, :unknown_execution}
      )

  defp require_check(ticket, check_id),
    do:
      if(Map.has_key?(active_attempt(ticket)["checks"] || %{}, check_id),
        do: :ok,
        else: {:error, :unknown_check}
      )

  defp require_sealed(ticket, execution_id) do
    if is_integer(active_attempt(ticket)["executions"][execution_id]["sealed_sequence"]),
      do: :ok,
      else: {:error, :stream_not_sealed}
  end

  defp require_unsealed(ticket, execution_id) do
    if is_nil(active_attempt(ticket)["executions"][execution_id]["sealed_sequence"]),
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

  defp fetch_verdict(ticket) do
    case active_attempt(ticket)["review"] do
      %{"verdict" => verdict} when is_binary(verdict) -> {:ok, verdict}
      _ -> {:error, :no_recorded_verdict}
    end
  end

  # R4: "successful ref receipt and prior role/check workers closed".
  defp require_workers_closed(ticket) do
    executions = active_attempt(ticket)["executions"] || %{}

    closed? =
      Elixir.Enum.all?(executions, fn {_id, execution} ->
        execution["role"] == "integration" or execution["lifecycle"] in ~w(closed unknown)
      end)

    if closed?, do: :ok, else: {:error, :workers_not_closed}
  end

  defp require_worker_role(ticket, execution_id) do
    role = active_attempt(ticket)["executions"][execution_id]["role"]

    if role in ~w(check build integration),
      do: :ok,
      else: {:error, :not_a_worker_execution}
  end

  defp require_resume_phase(phase),
    do: if(phase in State.ticket_phases(), do: :ok, else: {:error, :invalid_resume_phase})

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
