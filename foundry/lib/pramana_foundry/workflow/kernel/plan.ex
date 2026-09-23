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
  # with entity id `control`. Gateway keeps the authoritative copy
  # (`Gateway.domain_read_namespaces/0`); domain_read_check_test asserts the two agree.
  @namespaces %{
    "ticket" => "foundry.ticket.v1",
    "objective" => "foundry.objective.v1",
    "state" => "foundry.state.v1"
  }
  @read_kind_of %{"ticket" => "ticket", "objective" => "objective", "control" => "state"}

  @launch_operations ~w(reserve create_effect claim_effect issue_claim)

  @type result :: {:ok, map()} | {:reject, atom()} | {:error, atom()}

  @doc "The namespace each domain read kind is projected under."
  @spec namespaces() :: %{String.t() => String.t()}
  def namespaces, do: @namespaces

  @doc "An identifier derived from the command, so a retry rebuilds the same plan."
  @spec id(String.t(), String.t()) :: String.t()
  def id(command_id, tag), do: command_id <> "/" <> tag

  @doc """
  The command-level `expected_revisions` key of a root ledger generation:
  `root_ledger/<base64url ledger_id>/<generation>`. Gateway reads it from `root_ledgers`;
  the legacy `ledger/` key reads `ledger_generations` instead.
  """
  @spec root_ledger_key(String.t(), non_neg_integer()) :: String.t()
  def root_ledger_key(ledger_id, generation),
    do: "root_ledger/" <> encode(ledger_id) <> "/" <> Integer.to_string(generation)

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
  The four operations `launch/3` stages, for one role's launch.

  `spec`: `ticket_id`, `attempt_id`, `role`, `ordinal` (the role's launches on this attempt
  so far, one past the adapter's `predecessor_effect_id`, as `create_effect`'s predecessor
  guard requires), `units`, and the `facts` `launch_facts/1` accepted. Every identifier
  derives from `command_id`.
  """
  @spec launch_operations(String.t(), map()) :: [map()]
  def launch_operations(command_id, spec) do
    id = &id(command_id, &1)
    facts = spec["facts"]

    [
      %{
        "type" => "reserve",
        "reservation_id" => id.("reservation"),
        "ledger_id" => facts["allocation"]["ledger_id"],
        "generation" => facts["allocation"]["generation"],
        "owner_kind" => "effect",
        "owner_id" => id.("effect"),
        "units" => spec["units"]
      },
      %{
        "type" => "create_effect",
        "effect_id" => id.("effect"),
        "operation" => "launch",
        "scope" => "ticket:" <> to_string(spec["ticket_id"]),
        "ticket_id" => spec["ticket_id"],
        "attempt_id" => spec["attempt_id"],
        "execution_id" => id.("execution"),
        "policy_id" => facts["policy"]["policy_id"],
        "policy_revision" => facts["policy"]["revision"],
        "control_id" => facts["control"]["control_id"],
        "control_revision" => facts["control"]["revision"],
        "request" => %{
          "request_id" => id.("request"),
          "role" => spec["role"],
          "phase_generation" => 0,
          "operation_ordinal" => spec["ordinal"],
          "predecessor_effect_id" => facts["predecessor_effect_id"]
        },
        "reservation_ids" => [id.("reservation")],
        "leases" => []
      },
      %{
        "type" => "claim_effect",
        "effect_id" => id.("effect"),
        "claim_id" => id.("claim"),
        "writer_epoch" => facts["writer_epoch"]
      },
      %{
        "type" => "issue_claim",
        "claim_id" => id.("claim"),
        "writer_epoch" => facts["writer_epoch"]
      }
    ]
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
  ticket, such as `cancellation_finalized`. Optional `before` events come first, such as
  the `review_recorded` a verdict terminalises on.

  `spec`: `ticket_id`, `attempt_id`, `disposition`, `reason_code`, optional `before`,
  `then` and `reads` (as for `block/3`).
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

    before = for {type, payload} <- Map.get(spec, "before", []), do: {type, ticket_id, payload}
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
      alternatives: [{"unconditional", before ++ [settled | then]}],
      reads: Map.get(spec, "reads", [])
    })
  end

  @doc """
  Blocks a ticket with no protected operation: one `unconditional` `ticket_blocked`.

  `spec`: `ticket_id`, `reason`, `resume_phase`, optional `reads` (extra `{kind, id}`
  kernel entities the decision read, such as `{"control", "control"}` for a drain).
  """
  @spec block(map(), String.t(), map()) :: result()
  def block(state, command_id, spec) do
    unconditional(state, command_id, %{
      "events" => [blocked(spec["ticket_id"], spec["reason"], spec["resume_phase"])],
      "reads" => Map.get(spec, "reads", [])
    })
  end

  @doc """
  One `unconditional` alternative of `{type, entity_id, payload}` events on one entity.

  `spec`: `events`, and optionally `operations` (staged, in order), `bindings`
  (`{name, ordinal, output_kind, slot}`), `stand_ins` (a dry-run value per binding) and
  `reads`. With none of the optional keys it stages nothing, as a cancellation finalized
  after its attempt already settled does.
  """
  @spec unconditional(map(), String.t(), map()) :: result()
  def unconditional(state, command_id, spec) do
    build(state, command_id, %{
      operations: Map.get(spec, "operations", []),
      bindings: Map.get(spec, "bindings", []),
      stand_ins: Map.get(spec, "stand_ins", %{}),
      discriminator_kind: "unconditional_v1",
      alternatives: [{"unconditional", spec["events"]}],
      reads: Map.get(spec, "reads", [])
    })
  end

  @doc """
  A decider's result as `decide/3` returns it: the plan with its command, whose
  `expected_revisions` are derived from the plan's domain reads. The allocation a decision
  read is bound by `bind_allocation/2`, which `decide/3` applies to every decider's result,
  so no decider states it and none can omit it.

  Command-level `policy/`, `control/` and `ledger/` keys read the legacy authority tables
  (`Authority.read/2`), not the root rows, so policy and control are CAS-checked by the
  staged operations' own `expected_revisions` instead.
  """
  @spec decision(result(), map()) :: {:ok, map()} | {:reject, atom()} | {:error, atom()}
  def decision({:ok, plan}, command) do
    with {:ok, command} <- command(command, plan, %{}),
         do: {:ok, %{"command" => command, "plan" => plan}}
  end

  def decision(other, _command), do: other

  @doc """
  Binds the root ledger revision in `facts["allocation"]` to an accepted decision's command
  as `root_ledger_key/2`, so a unit returned or reserved before submit fails CAS instead of
  committing a decision made on a stale read (8c79ff03, 1a625549: twice omitted by hand).

  Skipped only when the plan stages a `reserve` on that ledger generation, which re-checks
  the allocation in Core. An allocation too malformed to bind is
  `{:error, :allocation_read_unbound}`. Rejections and errors pass through.
  """
  @spec bind_allocation(term(), term()) :: term()
  def bind_allocation({:ok, %{"command" => command, "plan" => plan}} = decision, %{
        "allocation" => allocation
      }) do
    with %{"ledger_id" => id, "generation" => gen, "revision" => revision}
         when is_binary(id) and is_integer(gen) and is_integer(revision) <- allocation do
      if reserves?(plan, id, gen) do
        decision
      else
        key = root_ledger_key(id, gen)

        {:ok,
         %{"command" => put_in(command, ["expected_revisions", key], revision), "plan" => plan}}
      end
    else
      _ -> {:error, :allocation_read_unbound}
    end
  end

  def bind_allocation(result, _facts), do: result

  defp reserves?(plan, ledger_id, generation) do
    Enum.any?(plan["protected_operations"], fn %{"input" => input} ->
      input["type"] == "reserve" and input["ledger_id"] == ledger_id and
        input["generation"] == generation
    end)
  end

  @doc """
  `{:ok, value}`, or `{:error, reason}` when `value` is nil or false: a `decide/3` input no
  decider can read, which is the caller's bug. Declared here with the planner's other input
  errors, which no event can trip, rather than in a reducer module.
  """
  @spec input(term(), atom()) :: {:ok, term()} | {:error, atom()}
  def input(value, reason) when value in [nil, false], do: {:error, reason}
  def input(value, _reason), do: {:ok, value}

  @doc """
  The protected facts a launch decision reads, each as the adapter queried it: `policy`
  and `control` (identity and `revision`), `allocation` (the start dimension's ledger
  generation and its `available` units), `writer_epoch`, and `predecessor_effect_id`
  (nil for a first launch).
  """
  @spec launch_facts(term()) :: {:ok, map()} | {:error, atom()}
  def launch_facts(facts) do
    input(
      is_map(facts) and fact?(facts["policy"], "policy_id") and
        fact?(facts["control"], "control_id") and fact?(facts["allocation"], "ledger_id") and
        is_integer(facts["allocation"]["generation"]) and
        is_integer(facts["allocation"]["available"]) and identifier?(facts["writer_epoch"]) and
        (is_nil(facts["predecessor_effect_id"]) or identifier?(facts["predecessor_effect_id"])) and
        facts,
      :invalid_facts
    )
  end

  defp fact?(fact, id_key),
    do: is_map(fact) and identifier?(fact[id_key]) and is_integer(fact["revision"])

  defp identifier?(value), do: is_binary(value) and value != ""

  @doc """
  The command's `expected_revisions`, derived from the plan rather than supplied beside it.

  Each domain read becomes `projection/` when some alternative writes that entity and
  `dependency/` when it is only read, at the read's durable revision. `protected` adds
  `root_ledger_key/2` revisions as given.
  """
  @spec expected_revisions(map(), map()) :: {:ok, map()} | {:error, atom()}
  def expected_revisions(plan, protected) do
    if Enum.all?(Map.keys(protected), &String.starts_with?(&1, "root_ledger/")) do
      written = written_keys(plan)

      reads =
        Map.new(plan["domain_reads"], fn read ->
          {ns, id} = {@namespaces[read["kind"]], read["entity_id"]}
          prefix = if {ns, id} in written, do: "projection/", else: "dependency/"
          {prefix <> encode(ns) <> "/" <> encode(id), read["revision"]}
        end)

      {:ok, Map.merge(reads, protected)}
    else
      {:error, :invalid_fact_key}
    end
  end

  @doc "`command` with its `expected_revisions` derived from `plan` and `protected`."
  @spec command(map(), map(), map()) :: {:ok, map()} | {:error, atom()}
  def command(command, plan, protected) do
    with {:ok, revisions} <- expected_revisions(plan, protected),
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

  defp encode(value), do: Base.url_encode64(value, padding: false)
end
