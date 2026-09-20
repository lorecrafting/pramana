defmodule PramanaFoundry.Workflow.Kernel.Event do
  @moduledoc false
  @types ~w(objective_created ticket_admitted ticket_amended ticket_parked launch_planned launch_settled artifact_frozen artifact_blocked freeze_failed execution_observed developer_closed checks_started check_planned check_recorded review_planned review_recorded reviewer_closed integration_planned integration_settled ticket_resumed ticket_reset cancellation_requested cancellation_finalized control_changed pm_proposal_recorded pm_launch_planned pm_launch_settled)
  @payloads %{
    "objective_created" => ~w(objective_id planning_owner_id),
    "ticket_admitted" => ~w(ticket_id objective_id spec_revision_id spec phase reason),
    "ticket_amended" => ~w(ticket_id spec_revision_id spec),
    "ticket_parked" => ~w(ticket_id reason resume_phase),
    "launch_planned" => ~w(ticket_id attempt_id authority),
    "launch_settled" => ~w(ticket_id attempt_id execution_id outcome disposition settlement),
    "artifact_frozen" => ~w(ticket_id attempt_id candidate_id observation_id),
    "artifact_blocked" => ~w(ticket_id attempt_id observation_id result reason),
    "freeze_failed" => ~w(ticket_id attempt_id disposition reason),
    "execution_observed" =>
      ~w(ticket_id attempt_id execution_id observation stream_status result),
    "developer_closed" => ~w(ticket_id attempt_id execution_id),
    "checks_started" => ~w(ticket_id attempt_id),
    "check_planned" => ~w(ticket_id attempt_id check_id authority),
    "check_recorded" => ~w(ticket_id attempt_id check_id status disposition reason),
    "review_planned" => ~w(ticket_id attempt_id authority),
    "review_recorded" => ~w(ticket_id attempt_id review),
    "reviewer_closed" => ~w(ticket_id attempt_id execution_id disposition),
    "integration_planned" => ~w(ticket_id attempt_id authority),
    "integration_settled" => ~w(ticket_id attempt_id execution_id outcome disposition settlement),
    "ticket_resumed" => ~w(ticket_id phase),
    "ticket_reset" => ~w(ticket_id ledger_id ledger_generation),
    "cancellation_requested" => ~w(ticket_id),
    "cancellation_finalized" => ~w(ticket_id disposition),
    "control_changed" => ~w(paused draining stop_status control_id control_revision),
    "pm_proposal_recorded" => ~w(proposal_id objective_id operation),
    "pm_launch_planned" => ~w(objective_id planning_owner_id authority),
    "pm_launch_settled" => ~w(objective_id outcome disposition settlement)
  }
  def types, do: @types

  def validate(e, opts \\ []) do
    template? = Keyword.get(opts, :template, false)

    if plain?(e) and
         exact?(
           e,
           ~w(schema_version event_id type recorded_at expected_state_revision entity_revision payload)
         ) and e["schema_version"] == 1 and id?(e["event_id"]) and e["type"] in @types and
         id?(e["recorded_at"]) and nn?(e["expected_state_revision"]) and nn?(e["entity_revision"]) and
         valid_payload?(e["type"], e["payload"], template?),
       do: :ok,
       else: {:error, :invalid_semantic_event}
  rescue
    _ -> {:error, :invalid_semantic_event}
  end

  defp valid_payload?(t, p, template?),
    do: plain?(p) and exact?(p, Map.fetch!(@payloads, t)) and value?(p, template?)

  defp value?(%{"binding" => n} = v, true), do: exact?(v, ~w(binding)) and id?(n)

  defp value?(v, t) when is_map(v) and not is_struct(v),
    do: Enum.all?(v, fn {k, x} -> is_binary(k) and value?(x, t) end)

  defp value?(v, t) when is_list(v), do: proper?(v) and Enum.all?(v, &value?(&1, t))
  defp value?(v, _) when is_binary(v), do: String.valid?(v)
  defp value?(v, _) when is_integer(v) or is_boolean(v) or is_nil(v), do: true
  defp value?(_, _), do: false

  defp proper?(v) do
    _ = length(v)
    true
  rescue
    _ -> false
  end

  defp exact?(m, k), do: Enum.sort(Map.keys(m)) == Enum.sort(k)
  defp id?(v), do: is_binary(v) and v != "" and String.valid?(v)
  defp nn?(v), do: is_integer(v) and v >= 0
  defp plain?(v), do: is_map(v) and not is_struct(v)
end
