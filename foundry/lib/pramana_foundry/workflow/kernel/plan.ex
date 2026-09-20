defmodule PramanaFoundry.Workflow.Kernel.Plan do
  @moduledoc false
  alias PramanaFoundry.Workflow.Kernel.Event
  @ops ~w(set_control reserve create_effect settle_claim consume_validation reset_generation)
  @kinds ~w(launch_authority_v1 nonstart_settlement_v1 terminal_settlement_v1 control_fact_v1 reset_fact_v1)
  @slots ~w(launch_planned.authority check_planned.authority review_planned.authority integration_planned.authority pm_launch_planned.authority launch_settled.settlement integration_settled.settlement pm_launch_settled.settlement control_changed.control ticket_reset.generation)
  def validate(p) do
    if plain?(p) and
         exact?(
           p,
           ~w(schema_version command_id disposition reason_code expected_domain_revision domain_reads protected_operations bindings alternatives)
         ) and p["schema_version"] == 1 and id?(p["command_id"]) and
         p["disposition"] in ~w(accepted rejected blocked) and
         (is_nil(p["reason_code"]) or id?(p["reason_code"])) and
         nn?(p["expected_domain_revision"]) and list?(p["domain_reads"], &read?/1) and
         operations?(p["protected_operations"]) and
         bindings?(p["bindings"], p["protected_operations"]) and alternatives?(p),
       do: :ok,
       else: {:error, :invalid_transition_plan}
  rescue
    _ -> {:error, :invalid_transition_plan}
  end

  def bind(p, discriminator, outputs) do
    with :ok <- validate(p),
         true <- plain?(outputs),
         [alt] <- Enum.filter(p["alternatives"], &(&1["discriminator"] == discriminator)),
         :ok <- outputs?(p["bindings"], outputs),
         events <- Enum.map(alt["events"], &sub(&1, outputs)),
         true <- Enum.all?(events, &(Event.validate(&1) == :ok)) do
      {:ok, events}
    else
      false -> {:error, :invalid_binding_outputs}
      [] -> {:error, :unknown_discriminator}
      {:error, _} = error -> error
      _ -> {:error, :invalid_bound_plan}
    end
  rescue
    _ -> {:error, :invalid_bound_plan}
  end

  defp read?(r),
    do:
      plain?(r) and exact?(r, ~w(kind entity_id revision)) and
        r["kind"] in ~w(state ticket objective pm) and id?(r["entity_id"]) and
        (r["revision"] == "absent" or nn?(r["revision"]))

  defp operations?(ops),
    do:
      is_list(ops) and
        Enum.with_index(ops)
        |> Enum.all?(fn {o, i} ->
          plain?(o) and exact?(o, ~w(schema_version ordinal type input)) and
            o["schema_version"] == 1 and o["ordinal"] == i and o["type"] in @ops and
            plain?(o["input"])
        end)

  defp bindings?(bs, ops) do
    is_list(bs) and
      length(Enum.map(bs, & &1["name"])) == length(Enum.uniq(Enum.map(bs, & &1["name"]))) and
      Enum.all?(bs, fn b ->
        plain?(b) and exact?(b, ~w(name operation_ordinal output_kind destination_slot)) and
          id?(b["name"]) and is_integer(b["operation_ordinal"]) and b["operation_ordinal"] >= 0 and
          b["operation_ordinal"] < length(ops) and b["output_kind"] in @kinds and
          b["destination_slot"] in @slots
      end)
  end

  defp alternatives?(%{"disposition" => d, "alternatives" => as}) when d in ~w(rejected blocked),
    do: as == []

  defp alternatives?(%{"alternatives" => as}) do
    is_list(as) and as != [] and
      length(Enum.map(as, & &1["discriminator"])) ==
        length(Enum.uniq(Enum.map(as, & &1["discriminator"]))) and
      Enum.all?(as, fn a ->
        plain?(a) and exact?(a, ~w(discriminator events)) and id?(a["discriminator"]) and
          list?(a["events"], &(Event.validate(&1, template: true) == :ok)) and a["events"] != []
      end)
  end

  defp outputs?(bs, out) do
    if Enum.sort(Map.keys(out)) == Enum.sort(Enum.map(bs, & &1["name"])) and
         Enum.all?(bs, &output?(&1["output_kind"], out[&1["name"]])),
       do: :ok,
       else: {:error, :invalid_binding_outputs}
  end

  defp output?("launch_authority_v1", v),
    do:
      shape?(
        v,
        ~w(role owner_id attempt_id execution_id effect_id reservation_id predecessor_effect_id policy_id policy_revision control_id control_revision ledger_id ledger_generation infrastructure_generation),
        ~w(policy_revision control_revision ledger_generation infrastructure_generation)
      )

  defp output?(k, v) when k in ~w(nonstart_settlement_v1 terminal_settlement_v1),
    do:
      shape?(
        v,
        ~w(role owner_id attempt_id execution_id effect_id claim_id receipt_id reservation_id predecessor_effect_id infrastructure_generation infrastructure_ordinal failure_class ledger_id ledger_generation outcome),
        ~w(infrastructure_generation infrastructure_ordinal ledger_generation)
      ) and v["infrastructure_ordinal"] > 0 and
        v["outcome"] in ~w(non_started succeeded failed unknown)

  defp output?("control_fact_v1", v),
    do:
      plain?(v) and exact?(v, ~w(control_id control_revision)) and id?(v["control_id"]) and
        nn?(v["control_revision"])

  defp output?("reset_fact_v1", v),
    do:
      plain?(v) and exact?(v, ~w(ledger_id ledger_generation)) and id?(v["ledger_id"]) and
        nn?(v["ledger_generation"])

  defp output?(_, _), do: false

  defp shape?(v, fields, ints),
    do:
      plain?(v) and exact?(v, fields) and
        Enum.all?(fields -- ints, &(is_nil(v[&1]) or id?(v[&1]))) and Enum.all?(ints, &nn?(v[&1]))

  defp sub(%{"binding" => n} = v, out) when map_size(v) == 1, do: Map.fetch!(out, n)
  defp sub(v, out) when is_map(v), do: Map.new(v, fn {k, x} -> {k, sub(x, out)} end)
  defp sub(v, out) when is_list(v), do: Enum.map(v, &sub(&1, out))
  defp sub(v, _), do: v
  defp list?(v, f), do: is_list(v) and Enum.all?(v, f)
  defp exact?(m, k), do: Enum.sort(Map.keys(m)) == Enum.sort(k)
  defp id?(v), do: is_binary(v) and v != "" and String.valid?(v)
  defp nn?(v), do: is_integer(v) and v >= 0
  defp plain?(v), do: is_map(v) and not is_struct(v)
end
