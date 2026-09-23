defmodule PramanaFoundry.Workflow.Kernel.Plan do
  @moduledoc """
  Role-generic builders of closed transition plans for `decide/3` (FR-08B subcommit 2,
  `docs/fr-08/FR08B-SUBCOMMIT2-DECIDE-DESIGN-2026-09-23.md`).

  This is the candidate-side producer that `DurableStore.TransitionPlan` names. It is pure:
  it never queries, never calls Gateway, and never calls `TransitionPlan` either — that
  module is the authoritative validator, and the tests use it as the oracle.

  Four builders, one per plan shape the developer and reviewer rows need: `launch/3`,
  `nonstart/3`, `close_attempt/3` and `block/3`. Each names the protected operations its
  shape stages, the binding each authoritative fact fills, and the discriminator that
  selects among its alternatives. Role vocabulary — which `*_planned`/`*_settled` type,
  which block reason — arrives as an argument, so nothing here names a role.

  **Projections are the reducer's.** Every alternative is dry-run through `Kernel.apply/2`
  on the prestate, each binding marker replaced by a stand-in for the dry run only. The
  written entity's post-state becomes the projection value, and a reducer refusal becomes
  `{:reject, reason}`, so no plan the reducer would refuse is emitted and no guard is
  written twice.

  **Identifiers derive from `command_id`** (`id/2`), so a retry rebuilds the same plan.

  **Revisions are durable.** A kernel entity at revision *r* ≥ 1 is projection revision
  *r* − 1; kernel revision 0 is `"absent"`. `expected_domain_revision` is the kernel
  revision of the entity the projections write, not of `domain_reads[0]`.
  """

  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.Event

  # One fixed namespace per domain read kind. The control singleton is read kind `state`
  # with entity id `control`. TransitionPlan keeps its own copy (commit 1); a test asserts
  # the two agree once it exists.
  @namespaces %{
    "ticket" => "foundry.ticket.v1",
    "objective" => "foundry.objective.v1",
    "state" => "foundry.state.v1"
  }
  @read_kind_of %{"ticket" => "ticket", "objective" => "objective", "control" => "state"}
  @protected_kinds ~w(policy control ledger)

  @launch_operations ~w(reserve create_effect claim_effect issue_claim)

  @type result :: {:ok, map()} | {:reject, atom()} | {:error, atom()}

  @doc "The namespace each domain read kind is projected under."
  @spec namespaces() :: %{String.t() => String.t()}
  def namespaces, do: @namespaces

  @doc "An identifier derived from the command, so a retry rebuilds the same plan."
  @spec id(String.t(), String.t()) :: String.t()
  def id(command_id, tag), do: command_id <> "/" <> tag

  @doc """
  The `expected_revisions` key of a protected fact: `policy/`, `control/` or `ledger/`
  followed by the base64url identity the adapter queried it by.
  """
  @spec protected_key(String.t(), String.t()) :: String.t()
  def protected_key(kind, id) when kind in @protected_kinds, do: kind <> "/" <> encode(id)

  @doc """
  A launch: `reserve`, `create_effect`, `claim_effect`, `issue_claim`, and one
  `unconditional` alternative whose `planned` event carries the issued authority.

  `spec`: `planned` (the `*_planned` type) and `operations`, the four staged operations in
  that order. Ticket, attempt and execution come from the `create_effect` operation. The
  control singleton is declared as a read, so a pause or drain committed before the plan
  fails CAS.
  """
  @spec launch(map(), String.t(), map()) :: result()
  def launch(state, command_id, %{"planned" => planned, "operations" => operations}) do
    with :ok <- require_operation_types(operations, @launch_operations) do
      effect = Enum.at(operations, 1)
      ticket_id = effect["ticket_id"]

      event =
        {planned, ticket_id,
         %{
           "ticket_id" => ticket_id,
           "attempt_id" => effect["attempt_id"],
           "authority" => marker("authority")
         }}

      build(state, command_id, %{
        operations: operations,
        bindings: [{"authority", 3, "launch_authority_v1", planned <> ".authority"}],
        stand_ins: %{"authority" => %{"execution_id" => effect["execution_id"]}},
        discriminator_kind: "unconditional_v1",
        alternatives: [{"unconditional", [event]}],
        reads: [{"control", "control"}]
      })
    end
  end

  @doc """
  A proved non-start: `settle_claim`, selected by the protected infrastructure limit.
  Below the limit the `settled` event alone; at the limit it and `ticket_blocked`.

  `spec`: `settled`, `operation` (the staged `settle_claim`), `ticket_id`, `attempt_id`,
  `execution_id`, and the at-limit `reason` and `resume_phase`.
  """
  @spec nonstart(map(), String.t(), map()) :: result()
  def nonstart(state, command_id, spec) do
    with :ok <- require_operation_types([spec["operation"]], ~w(settle_claim)) do
      ticket_id = spec["ticket_id"]

      settled =
        {spec["settled"], ticket_id,
         %{
           "ticket_id" => ticket_id,
           "attempt_id" => spec["attempt_id"],
           "execution_id" => spec["execution_id"],
           "settlement" => marker("settlement")
         }}

      build(state, command_id, %{
        operations: [spec["operation"]],
        bindings: [
          {"settlement", 0, "nonstart_settlement_v1", spec["settled"] <> ".settlement"}
        ],
        stand_ins: %{"settlement" => %{"schema_version" => 1}},
        discriminator_kind: "infrastructure_limit_v1",
        alternatives: [
          {"below_infrastructure_limit", [settled]},
          {"infrastructure_limit_reached",
           [settled, blocked(ticket_id, spec["reason"], spec["resume_phase"])]}
        ],
        reads: []
      })
    end
  end

  @doc """
  Terminates the active attempt: `close_attempt`, then `attempt_settled` carrying the
  protected terminal settlement, then any `then` events (as `{type, payload}`) on the same
  ticket, such as `cancellation_finalized`.

  `spec`: `ticket_id`, `attempt_id`, `disposition`, `reason_code`, optional `then`.
  """
  @spec close_attempt(map(), String.t(), map()) :: result()
  def close_attempt(state, command_id, spec) do
    ticket_id = spec["ticket_id"]
    attempt_id = spec["attempt_id"]
    scope = "ticket:" <> ticket_id

    settled =
      {"attempt_settled", ticket_id,
       %{
         "ticket_id" => ticket_id,
         "attempt_id" => attempt_id,
         "disposition" => spec["disposition"],
         "reason_code" => spec["reason_code"],
         "settlement" => marker("settlement")
       }}

    then = for {type, payload} <- Map.get(spec, "then", []), do: {type, ticket_id, payload}

    build(state, command_id, %{
      operations: [
        %{
          "type" => "close_attempt",
          "scope" => scope,
          "ticket_id" => ticket_id,
          "attempt_id" => attempt_id
        }
      ],
      bindings: [{"settlement", 0, "terminal_settlement_v1", "attempt_settled.settlement"}],
      stand_ins: %{
        "settlement" => %{
          "schema_version" => 1,
          "scope" => scope,
          "ticket_id" => ticket_id,
          "attempt_id" => attempt_id,
          "effect_ids" => [],
          "settled_units" => %{}
        }
      },
      discriminator_kind: "unconditional_v1",
      alternatives: [{"unconditional", [settled | then]}],
      reads: []
    })
  end

  @doc """
  Blocks a ticket with no protected operation: one `unconditional` `ticket_blocked`.

  `spec`: `ticket_id`, `reason`, `resume_phase`, optional `reads` (extra `{kind, id}`
  kernel entities the decision read, such as `{"control", "control"}` for a drain).
  """
  @spec block(map(), String.t(), map()) :: result()
  def block(state, command_id, spec) do
    build(state, command_id, %{
      operations: [],
      bindings: [],
      stand_ins: %{},
      discriminator_kind: "unconditional_v1",
      alternatives: [
        {"unconditional", [blocked(spec["ticket_id"], spec["reason"], spec["resume_phase"])]}
      ],
      reads: Map.get(spec, "reads", [])
    })
  end

  @doc """
  The command's `expected_revisions`, derived from the plan rather than supplied beside it.

  Each domain read becomes `projection/` when some alternative writes that entity and
  `dependency/` when it is only read, at the read's durable revision. Each protected fact,
  keyed by `protected_key/2`, adds its own revision.
  """
  @spec expected_revisions(map(), map()) :: {:ok, map()} | {:error, atom()}
  def expected_revisions(plan, facts) do
    if Enum.all?(Map.keys(facts), &protected_key?/1) do
      written = written_keys(plan)

      reads =
        Map.new(plan["domain_reads"], fn read ->
          {ns, id} = {@namespaces[read["kind"]], read["entity_id"]}
          prefix = if {ns, id} in written, do: "projection/", else: "dependency/"
          {prefix <> encode(ns) <> "/" <> encode(id), read["revision"]}
        end)

      {:ok, Map.merge(reads, Map.new(facts, fn {key, fact} -> {key, fact["revision"]} end))}
    else
      {:error, :invalid_fact_key}
    end
  end

  @doc "`command` with its `expected_revisions` derived from `plan` and `facts`."
  @spec command(map(), map(), map()) :: {:ok, map()} | {:error, atom()}
  def command(command, plan, facts) do
    with {:ok, revisions} <- expected_revisions(plan, facts),
         do: {:ok, Map.put(command, "expected_revisions", revisions)}
  end

  # ── Assembly ──────────────────────────────────────────────────────────────────────

  defp build(state, command_id, spec) do
    with {:ok, alternatives} <- dry_run_all(state, command_id, spec) do
      [{kind, entity_id}] = written_entities(spec.alternatives)

      reads =
        Enum.uniq([{kind, entity_id} | spec.reads])
        |> Enum.map(fn {kind, id} ->
          %{
            "kind" => @read_kind_of[kind],
            "entity_id" => id,
            "revision" => durable_revision(kernel_revision(state, kind, id))
          }
        end)

      {:ok,
       %{
         "schema_version" => 1,
         "command_id" => command_id,
         "disposition" => "accepted",
         "reason_code" => nil,
         "expected_domain_revision" => kernel_revision(state, kind, entity_id),
         "domain_reads" => reads,
         "protected_operations" =>
           spec.operations
           |> Enum.with_index()
           |> Enum.map(fn {operation, ordinal} ->
             %{
               "schema_version" => 1,
               "ordinal" => ordinal,
               "type" => operation["type"],
               "input" => operation
             }
           end),
         "bindings" =>
           Enum.map(spec.bindings, fn {name, ordinal, kind, slot} ->
             %{
               "name" => name,
               "operation_ordinal" => ordinal,
               "output_kind" => kind,
               "destination_slot" => slot
             }
           end),
         "discriminator_kind" => spec.discriminator_kind,
         "alternatives" => alternatives
       }}
    end
  end

  defp dry_run_all(state, command_id, spec) do
    Enum.reduce_while(spec.alternatives, {:ok, []}, fn {discriminator, events}, {:ok, acc} ->
      case dry_run(state, command_id, events, spec.stand_ins) do
        {:ok, proposal} ->
          {:cont, {:ok, acc ++ [%{"discriminator" => discriminator, "proposal" => proposal}]}}

        # Malformed state or event is the caller's bug; anything else the reducer refused.
        {:error, reason} when reason in [:invalid_state, :invalid_semantic_event] ->
          {:halt, {:error, reason}}

        {:error, reason} ->
          {:halt, {:reject, reason}}
      end
    end)
  end

  # Folds the alternative's events through the reducer. The kernel envelope carries the
  # stand-ins; the durable event carries the markers and the post-state as its projection.
  defp dry_run(state, command_id, events, stand_ins) do
    events
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, state, [], []}, fn {{type, entity_id, payload}, index},
                                                  {:ok, state, durable, projections} ->
      {:ok, entity_kind} = Event.entity_kind(type)
      event_id = id(command_id, "e#{index}")
      revision = kernel_revision(state, entity_kind, entity_id)

      envelope = %{
        "schema_version" => 1,
        "event_id" => event_id,
        "type" => type,
        "sequence" => (state["last_sequence"] || 0) + 1,
        "entity_kind" => entity_kind,
        "entity_id" => entity_id,
        "entity_revision" => revision,
        "payload" => substitute(payload, stand_ins)
      }

      case WorkflowKernel.apply(state, envelope) do
        {:ok, next} ->
          namespace = @namespaces[@read_kind_of[entity_kind]]
          value = next |> entity(entity_kind, entity_id) |> JSON.encode!() |> JSON.decode!()

          transition = %{
            "namespace" => namespace,
            "entity_id" => entity_id,
            "revision" => revision,
            "value" => value
          }

          event = %{
            "schema_version" => 1,
            "event_id" => event_id,
            "type" => type,
            "payload" => Map.put(payload, "projection", transition)
          }

          projection =
            transition
            |> Map.merge(%{
              "schema_version" => 1,
              "expected_revision" => revision - 1,
              "last_event_id" => event_id
            })

          {:cont, {:ok, next, durable ++ [event], projections ++ [projection]}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, _state, events, projections} ->
        {:ok,
         %{
           "schema_version" => 1,
           "result" => %{"schema_version" => 1, "disposition" => "accepted"},
           "events" => events,
           "projections" => projections,
           "intents" => []
         }}

      error ->
        error
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────────

  # Every builder writes exactly one entity; `build/3` matches on that.
  defp written_entities(alternatives) do
    for {_discriminator, events} <- alternatives,
        {type, entity_id, _payload} <- events,
        {:ok, kind} = Event.entity_kind(type),
        uniq: true,
        do: {kind, entity_id}
  end

  defp written_keys(plan) do
    for alternative <- plan["alternatives"],
        projection <- alternative["proposal"]["projections"],
        uniq: true,
        do: {projection["namespace"], projection["entity_id"]}
  end

  # A staged operation list whose types are not exactly the shape's is a caller bug.
  defp require_operation_types(operations, types) do
    if is_list(operations) and Enum.all?(operations, &is_map/1) and
         Enum.map(operations, & &1["type"]) == types,
       do: :ok,
       else: {:error, :invalid_operations}
  end

  defp blocked(ticket_id, reason, resume_phase),
    do:
      {"ticket_blocked", ticket_id,
       %{"ticket_id" => ticket_id, "reason" => reason, "resume_phase" => resume_phase}}

  defp marker(name), do: %{"binding" => name}

  defp substitute(payload, stand_ins) do
    Map.new(payload, fn
      {key, %{"binding" => name} = value} when map_size(value) == 1 ->
        {key, Map.fetch!(stand_ins, name)}

      pair ->
        pair
    end)
  end

  defp entity(state, "control", _id), do: state["control"]
  defp entity(state, "ticket", id), do: state["tickets"][id]
  defp entity(state, "objective", id), do: state["objectives"][id]

  defp kernel_revision(state, kind, id), do: (entity(state, kind, id) || %{})["revision"] || 0

  defp durable_revision(0), do: "absent"
  defp durable_revision(revision), do: revision - 1

  defp protected_key?(key) do
    case String.split(key, "/", parts: 2) do
      [kind, encoded] when kind in @protected_kinds -> match?({:ok, _}, decode(encoded))
      _ -> false
    end
  end

  defp encode(value), do: Base.url_encode64(value, padding: false)
  defp decode(value), do: Base.url_decode64(value, padding: false)
end
