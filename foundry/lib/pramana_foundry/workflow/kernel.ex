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
  newer one moved a ticket backwards. Six properties replace that.

  1. **Closed vocabulary.** `Event.validate/2` accepts only the enumerated types, each with
     an exact payload key set. An unknown type never reaches a merge.
  2. **Totality over the validator.** Every state `State.well_formed?/1` accepts is one `apply/2`
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
  6. **Closure over the validator.** Every state `apply/2` produces is one it would accept as
     input: `advance/2` runs `State.well_formed?/1` over the committed post-state and refuses
     with `:malformed_post_state` rather than return it. Property 2 alone let a handler copy
     a payload value into state under whatever `Event.validate/2` allowed — any string,
     integer, boolean, nil, list or map — and `bin/closure_probe.exs` found at least 20
     `(type, key)` pairs that wrote a state `check_state/1` then refused forever. Checking
     the output closes all of them, the pairs the probe cannot see, and every future handler,
     without typing each payload key; the post-state validator is the same predicate every
     input already passes, so nothing legitimate is refused that was not already broken.

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
  other two outcomes are expressed by emitting a second event — `ticket_blocked` at the
  limit, which the protected discriminator selects as a plan alternative of the same bundle,
  and `attempt_settled(exhausted)`, which `decide/3` plans on the next launch when current
  allocation is short. Keeping each event's effect fixed is
  what lets a bound projection equal the result of applying its bound event, and it is why
  the discriminator selects among alternatives rather than among payload values.
  """

  import Kernel, except: [apply: 2]

  alias PramanaFoundry.Workflow.Kernel.{
    Cancellation,
    Control,
    Event,
    Executions,
    Plan,
    State,
    Tickets
  }

  alias PramanaFoundry.Workflow.Kernel.Software.{
    Checks,
    Developer,
    Dispositions,
    Integration,
    Planning,
    Review
  }

  import PramanaFoundry.Workflow.Kernel.Shared, only: [terminal_ticket_phases: 0]

  # Each event type's family. The reducer is split by event family, not by kind: a guard
  # lives in the module whose transitions it serves, so one read holds everything needed to
  # change a row safely. Generic families first, then the software workflow's.
  @families [
    {Tickets, ~w(ticket_admitted ticket_amended ticket_parked ticket_blocked ticket_unblocked
        ticket_reset)},
    {Cancellation, ~w(cancellation_requested cancellation_finalized)},
    {Control, ~w(control_changed)},
    {Executions,
     ~w(launch_planned launch_settled execution_observed stream_sealed developer_closed
        worker_closed)},
    {Planning, ~w(objective_created pm_proposal_recorded pm_launch_planned pm_launch_settled)},
    {Developer, ~w(artifact_frozen artifact_blocked freeze_failed submission_rejected)},
    {Checks, ~w(checks_started check_planned check_settled check_recorded build_planned
        build_settled)},
    {Review, ~w(review_planned review_settled review_recorded reviewer_closed)},
    {Integration, ~w(integration_planned integration_settled integration_recorded)},
    {Dispositions, ~w(attempt_settled)}
  ]
  @family_of for {family, types} <- @families, type <- types, into: %{}, do: {type, family}

  if Enum.sort(Map.keys(@family_of)) != Enum.sort(Event.types()) do
    raise CompileError,
      description: "kernel families do not cover Event.types/0 exactly: #{inspect(@families)}"
  end

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

  @doc """
  Plans one command as a closed transition plan (FR-08B subcommit 2,
  `docs/fr-08/FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md`).

  Pure like `apply/2`: `facts` are the protected facts the adapter already queried, and
  nothing here reads the store. `{:ok, %{"command" => ..., "plan" => ...}}` is an accepted
  plan whose command carries the `expected_revisions` it derives; `{:reject, reason}` is a
  decision to plan nothing, which creates no event; `{:error, reason}` is malformed input.
  """
  @spec decide(term(), term(), term()) ::
          {:ok, %{String.t() => map()}} | {:reject, atom()} | {:error, atom()}
  def decide(state, command, facts) do
    with :ok <- check_state(state),
         {:ok, _command} <- Plan.input(command?(command) and command, :invalid_command),
         {:ok, decider} <- Plan.input(decider(command), :unsupported_command) do
      decider.decide(state, command, facts)
    end
  end

  defp command?(command) do
    is_map(command) and not is_struct(command) and is_binary(command["command_id"]) and
      command["command_id"] != "" and is_map(command["target_ids"]) and
      is_map(command["payload"])
  end

  # Deciders are found through `@families`, the one table rule 4 lets this module name a
  # `kernel/software` module in, so the dispatcher gains no second site: a family module
  # decides the commands its `decides?/1` claims. A role-free command type carries its role
  # in the payload, so the claim is on the command rather than on its type alone.
  defp decider(command) do
    for({family, _types} <- @families, uniq: true, do: family)
    |> Enum.find(fn family ->
      Code.ensure_loaded?(family) and function_exported?(family, :decides?, 1) and
        family.decides?(command)
    end)
  end

  defp check_state(state),
    do: if(State.well_formed?(state), do: :ok, else: {:error, :invalid_state})

  # Property 6. The same predicate as `check_state/1` under a second atom, deliberately: the
  # two refusals mean opposite things to a caller. `:invalid_state` says the log is already
  # broken and nothing will apply; `:malformed_post_state` says this event was refused and
  # the log is fine. Spelled `require_*` so `bin/guard_mutation_sweep.exs` can neutralise it;
  # the red control is the fixture in `r4_exhaustive_test.exs`, which goes red when the sweep
  # neutralises this call (verified 2026-09-22: caught).
  defp require_well_formed(state),
    do: if(State.well_formed?(state), do: :ok, else: {:error, :malformed_post_state})

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
         {:ok, updated} <- transition(entity, event, state),
         next = commit(state, event, kind, updated),
         :ok <- require_well_formed(next) do
      {:ok, next}
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
         entity["phase"] in terminal_ticket_phases() and
         event["type"] not in @terminal_cleanup_events and
         not finalizing_integrated_cancel?(entity, event),
       do: {:error, :ticket_terminal},
       else: :ok
  end

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

  defp do_transition(type, entity, event, state),
    do: Map.fetch!(@family_of, type).do_transition(type, entity, event, state)

  defp ok_or({:ok, value}, _reason), do: {:ok, value}
  defp ok_or(:error, reason), do: {:error, reason}
end
