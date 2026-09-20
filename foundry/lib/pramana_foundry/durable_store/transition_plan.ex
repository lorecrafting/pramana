defmodule PramanaFoundry.DurableStore.TransitionPlan do
  @moduledoc false

  # Trusted protected-side codec for the closed transition plan described in
  # docs/fr-08/plan-binding-specification.md. Gateway uses it to bind authoritative
  # protected results into a concrete domain proposal by mechanical validated
  # selection and substitution.
  #
  # This module deliberately does not call, load or depend on
  # PramanaFoundry.Workflow.Kernel.Plan. The kernel's copy is the candidate-side
  # producer of conforming plans; this one is the authoritative validator and binder.
  # Gateway must never execute candidate code to decide what commits.
  #
  # There is no expression language, JSON path, callback or default branch. Every
  # fact-dependent decision is already exposed by the candidate as a finite set of
  # alternatives selected by a protected discriminator.

  alias PramanaFoundry.DurableStore.RecordCodec

  @plan ~w(schema_version command_id disposition reason_code expected_domain_revision domain_reads protected_operations bindings alternatives)
  @operation ~w(schema_version ordinal type input)
  @binding ~w(name operation_ordinal output_kind destination_slot)
  @alternative ~w(discriminator proposal)
  @domain_read ~w(kind entity_id revision)

  @operation_types ~w(set_control reserve create_effect settle_claim consume_validation reset_generation)
  @read_kinds ~w(state ticket objective pm)
  @dispositions ~w(accepted rejected blocked)
  @terminal_dispositions ~w(rejected blocked)

  @output_kinds ~w(launch_authority_v1 nonstart_settlement_v1 terminal_settlement_v1 control_fact_v1 reset_fact_v1)

  # A destination slot names the event type and the payload field the bound fact
  # occupies. The closed set is part of the codec, not caller-supplied text.
  @slots %{
    "launch_planned.authority" => {"launch_planned", "authority", "launch_authority_v1"},
    "check_planned.authority" => {"check_planned", "authority", "launch_authority_v1"},
    "review_planned.authority" => {"review_planned", "authority", "launch_authority_v1"},
    "integration_planned.authority" =>
      {"integration_planned", "authority", "launch_authority_v1"},
    "pm_launch_planned.authority" => {"pm_launch_planned", "authority", "launch_authority_v1"},
    "launch_settled.settlement" => {"launch_settled", "settlement", "nonstart_settlement_v1"},
    "integration_settled.settlement" =>
      {"integration_settled", "settlement", "nonstart_settlement_v1"},
    "pm_launch_settled.settlement" =>
      {"pm_launch_settled", "settlement", "nonstart_settlement_v1"},
    "control_changed.control" => {"control_changed", "control", "control_fact_v1"},
    "ticket_reset.generation" => {"ticket_reset", "generation", "reset_fact_v1"}
  }

  @doc """
  Validates the closed unresolved plan schema.

  Returns the plan unchanged on success. Validation is structural only: it proves the
  plan is a well-formed closed selection problem, never that its alternatives describe
  a legitimate transition.
  """
  @spec validate(term()) :: {:ok, map()} | {:error, atom()}
  def validate(plan) do
    with true <- plain_map?(plan),
         true <- exact_keys?(plan, @plan),
         1 <- plan["schema_version"],
         true <- identifier?(plan["command_id"]),
         true <- plan["disposition"] in @dispositions,
         true <- is_nil(plan["reason_code"]) or identifier?(plan["reason_code"]),
         true <- nonnegative_integer?(plan["expected_domain_revision"]),
         :ok <- validate_domain_reads(plan["domain_reads"]),
         :ok <- validate_operations(plan["protected_operations"]),
         :ok <- validate_bindings(plan["bindings"], plan["protected_operations"]),
         :ok <- validate_alternatives(plan) do
      {:ok, plan}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_transition_plan}
    end
  end

  @doc """
  Selects the alternative matching `discriminator` and substitutes `outputs`.

  `outputs` must already have been derived from authoritative staged protected results;
  this function never accepts a caller-supplied fact copy on its own authority. The
  returned proposal is normalized by `RecordCodec`, so the event/projection bijection is
  re-established after substitution rather than assumed.
  """
  @spec bind(map(), term(), map()) :: {:ok, map()} | {:error, atom()}
  def bind(plan, discriminator, outputs) do
    with {:ok, plan} <- validate(plan),
         true <- plan["disposition"] == "accepted",
         true <- identifier?(discriminator),
         true <- plain_map?(outputs),
         :ok <- outputs_match_bindings(plan["bindings"], outputs),
         {:ok, alternative} <- select(plan["alternatives"], discriminator),
         :ok <- markers_occupy_declared_slots(plan["bindings"], alternative["proposal"]),
         substituted <- substitute(alternative["proposal"], outputs),
         {:ok, proposal} <- RecordCodec.normalize_bundle(substituted),
         :ok <- bound_carriers_agree(plan["bindings"], outputs, proposal) do
      {:ok, proposal}
    else
      {:error, _reason} = error -> error
      _ -> {:error, :invalid_bound_plan}
    end
  end

  @doc """
  The closed set of output kinds a binding may name.
  """
  @spec output_kinds() :: [String.t()]
  def output_kinds, do: @output_kinds

  @doc """
  The event type and payload field a destination slot designates, with the output kind
  that slot accepts.
  """
  @spec slot(String.t()) :: {:ok, {String.t(), String.t(), String.t()}} | :error
  def slot(name), do: Map.fetch(@slots, name)

  # --- plan schema -----------------------------------------------------------------

  defp validate_domain_reads(reads) when is_list(reads) do
    if Enum.all?(reads, &domain_read?/1) and
         unique?(Enum.map(reads, &{&1["kind"], &1["entity_id"]})),
       do: :ok,
       else: {:error, :invalid_plan_domain_reads}
  end

  defp validate_domain_reads(_reads), do: {:error, :invalid_plan_domain_reads}

  defp domain_read?(read) do
    plain_map?(read) and exact_keys?(read, @domain_read) and read["kind"] in @read_kinds and
      identifier?(read["entity_id"]) and
      (read["revision"] == "absent" or nonnegative_integer?(read["revision"]))
  end

  defp validate_operations(operations) when is_list(operations) do
    valid? =
      operations
      |> Enum.with_index()
      |> Enum.all?(fn {operation, index} ->
        plain_map?(operation) and exact_keys?(operation, @operation) and
          operation["schema_version"] == 1 and operation["ordinal"] == index and
          operation["type"] in @operation_types and plain_map?(operation["input"])
      end)

    if valid?, do: :ok, else: {:error, :invalid_plan_operations}
  end

  defp validate_operations(_operations), do: {:error, :invalid_plan_operations}

  defp validate_bindings(bindings, operations) when is_list(bindings) and is_list(operations) do
    valid? =
      unique?(Enum.map(bindings, & &1["name"])) and
        Enum.all?(bindings, fn binding ->
          plain_map?(binding) and exact_keys?(binding, @binding) and
            identifier?(binding["name"]) and
            nonnegative_integer?(binding["operation_ordinal"]) and
            binding["operation_ordinal"] < length(operations) and
            binding["output_kind"] in @output_kinds and
            slot_accepts?(binding["destination_slot"], binding["output_kind"])
        end)

    if valid?, do: :ok, else: {:error, :invalid_plan_bindings}
  end

  defp validate_bindings(_bindings, _operations), do: {:error, :invalid_plan_bindings}

  defp slot_accepts?(name, output_kind) do
    case Map.fetch(@slots, name) do
      {:ok, {_type, _field, ^output_kind}} -> true
      _ -> false
    end
  end

  # A terminal plan decides nothing from a protected fact, so it carries no
  # alternatives and nothing to bind.
  defp validate_alternatives(%{
         "disposition" => disposition,
         "alternatives" => [],
         "bindings" => []
       })
       when disposition in @terminal_dispositions,
       do: :ok

  defp validate_alternatives(%{"disposition" => disposition})
       when disposition in @terminal_dispositions,
       do: {:error, :invalid_terminal_plan}

  defp validate_alternatives(%{"alternatives" => alternatives}) when is_list(alternatives) do
    valid? =
      alternatives != [] and
        unique?(Enum.map(alternatives, & &1["discriminator"])) and
        Enum.all?(alternatives, fn alternative ->
          plain_map?(alternative) and exact_keys?(alternative, @alternative) and
            identifier?(alternative["discriminator"]) and plain_map?(alternative["proposal"])
        end)

    if valid?, do: :ok, else: {:error, :invalid_plan_alternatives}
  end

  defp validate_alternatives(_plan), do: {:error, :invalid_plan_alternatives}

  # --- selection and substitution ---------------------------------------------------

  defp select(alternatives, discriminator) do
    case Enum.filter(alternatives, &(&1["discriminator"] == discriminator)) do
      [alternative] -> {:ok, alternative}
      [] -> {:error, :unknown_discriminator}
      _ -> {:error, :ambiguous_discriminator}
    end
  end

  defp outputs_match_bindings(bindings, outputs) do
    if Enum.sort(Map.keys(outputs)) == Enum.sort(Enum.map(bindings, & &1["name"])),
      do: :ok,
      else: {:error, :invalid_binding_outputs}
  end

  # The candidate declares where each authoritative fact lands. Enforce that declaration
  # rather than trusting it. A bound fact may occupy only three positions: the declared
  # payload field of exactly one event of the declared type, that same event's embedded
  # projection transition value, and the value of the projection paired with it. Those
  # last two exist so the codec's event/projection carrier duality can hold. Any other
  # position is an attempt to route an authoritative fact somewhere it was not declared.
  defp markers_occupy_declared_slots(bindings, proposal) do
    events = List.wrap(proposal["events"])
    projections = List.wrap(proposal["projections"])

    Enum.reduce_while(bindings, :ok, fn binding, :ok ->
      name = binding["name"]
      {type, field, _kind} = Map.fetch!(@slots, binding["destination_slot"])
      declared = for {event, index} <- Enum.with_index(events), event["type"] == type, do: index

      carrying =
        Enum.filter(declared, fn index ->
          events |> Enum.at(index) |> get_in(["payload", field]) == %{"binding" => name}
        end)

      case carrying do
        [index] ->
          event = Enum.at(events, index)

          permitted =
            [
              ["events", index, "payload", field],
              ["events", index, "payload", "projection", "value", field]
            ] ++
              for {projection, position} <- Enum.with_index(projections),
                  projection["last_event_id"] == event["event_id"],
                  do: ["projections", position, "value", field]

          if marker_positions(proposal, name, []) -- permitted == [],
            do: {:cont, :ok},
            else: {:halt, {:error, :binding_outside_declared_slot}}

        [] ->
          {:halt, {:error, :binding_slot_absent}}

        _ ->
          {:halt, {:error, :binding_slot_not_unique}}
      end
    end)
  end

  # Enumerates every path at which this binding's marker occurs, so occurrences can be
  # compared against the permitted set rather than merely counted.
  defp marker_positions(value, name, path)

  defp marker_positions(%{"binding" => candidate} = value, name, path)
       when map_size(value) == 1 do
    if candidate == name, do: [Enum.reverse(path)], else: []
  end

  defp marker_positions(value, name, path) when is_map(value) do
    Enum.flat_map(value, fn {key, nested} -> marker_positions(nested, name, [key | path]) end)
  end

  defp marker_positions(value, name, path) when is_list(value) do
    value
    |> Enum.with_index()
    |> Enum.flat_map(fn {nested, index} -> marker_positions(nested, name, [index | path]) end)
  end

  defp marker_positions(_value, _name, _path), do: []

  defp substitute(%{"binding" => name} = value, outputs) when map_size(value) == 1,
    do: Map.fetch!(outputs, name)

  defp substitute(value, outputs) when is_map(value),
    do: Map.new(value, fn {key, nested} -> {key, substitute(nested, outputs)} end)

  defp substitute(value, outputs) when is_list(value),
    do: Enum.map(value, &substitute(&1, outputs))

  defp substitute(value, _outputs), do: value

  # After normalization the bound fact must be present, unchanged, in the event it was
  # declared for, and identical in the paired projection when that projection carries it.
  defp bound_carriers_agree(bindings, outputs, proposal) do
    Enum.reduce_while(bindings, :ok, fn binding, :ok ->
      name = binding["name"]
      {type, field, _kind} = Map.fetch!(@slots, binding["destination_slot"])
      expected = Map.fetch!(outputs, name)

      carriers =
        for event <- List.wrap(proposal["events"]),
            event["type"] == type,
            get_in(event, ["payload", field]) == expected,
            do: event

      case carriers do
        [event] ->
          agreed? =
            List.wrap(proposal["projections"])
            |> Enum.filter(&(&1["last_event_id"] == event["event_id"]))
            |> Enum.all?(fn projection ->
              case get_in(projection, ["value", field]) do
                nil -> true
                value -> value == expected
              end
            end)

          if agreed?, do: {:cont, :ok}, else: {:halt, {:error, :bound_carriers_disagree}}

        _ ->
          {:halt, {:error, :bound_fact_missing}}
      end
    end)
  end

  # --- shared predicates ------------------------------------------------------------

  defp unique?(values), do: length(values) == length(Enum.uniq(values))
  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp identifier?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp plain_map?(value), do: is_map(value) and not is_struct(value)
end
