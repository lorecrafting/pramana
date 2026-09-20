defmodule PramanaFoundry.Workflow.Kernel.State do
  @moduledoc false

  @ticket_phases ~w(draft queued developing awaiting_review reviewing ready_to_integrate integrating integrated blocked exhausted rejected cancelled)
  @attempt_phases ~w(active candidate_frozen checking awaiting_review reviewing ready_to_integrate integrating terminal)
  @attempt_dispositions ~w(integrated needs_correction failed timed_out blocked exhausted rejected cancelled superseded_base)
  @execution_states ~w(pending starting running closing closed unknown)
  @execution_results ~w(valid blocked partial invalid none succeeded failed non_started)

  def new do
    %{
      "schema_version" => 1,
      "revision" => 0,
      "last_event_id" => nil,
      "control" => %{
        "revision" => 0,
        "paused" => false,
        "draining" => false,
        "stop_status" => "running"
      },
      "objectives" => %{},
      "tickets" => %{},
      "pm" => %{}
    }
  end

  def valid?(state) do
    plain_map?(state) and
      exact_keys?(state, ~w(schema_version revision last_event_id control objectives tickets pm)) and
      state["schema_version"] == 1 and nonnegative?(state["revision"]) and
      optional_string?(state["last_event_id"]) and
      valid_control?(state["control"]) and map_values?(state["objectives"], &valid_objective?/1) and
      map_values?(state["tickets"], &valid_ticket?/1) and map_values?(state["pm"], &valid_pm?/1)
  rescue
    _ -> false
  end

  def valid_ticket?(ticket) do
    plain_map?(ticket) and
      exact_keys?(
        ticket,
        ~w(ticket_id objective_id phase resume_phase reason spec_revision_id spec attempts current_attempt_id cancel_status revision)
      ) and
      identities?(ticket, ~w(ticket_id objective_id spec_revision_id)) and
      ticket["phase"] in @ticket_phases and
      optional_enum?(ticket["resume_phase"], @ticket_phases) and
      optional_string?(ticket["reason"]) and
      plain_map?(ticket["spec"]) and plain_map?(ticket["attempts"]) and
      nonnegative?(ticket["revision"]) and
      optional_enum?(ticket["cancel_status"], ~w(cancel_requested cancel_finalized)) and
      Enum.all?(ticket["attempts"], fn {id, attempt} ->
        id == attempt["attempt_id"] and valid_attempt?(attempt)
      end) and
      current_attempt_valid?(ticket)
  rescue
    _ -> false
  end

  def valid_attempt?(attempt) do
    plain_map?(attempt) and
      exact_keys?(
        attempt,
        ~w(attempt_id phase disposition lineage candidate_id developer_closed checks review executions infrastructure revision)
      ) and
      identity?(attempt["attempt_id"]) and attempt["phase"] in @attempt_phases and
      optional_enum?(attempt["disposition"], @attempt_dispositions) and
      plain_map?(attempt["lineage"]) and
      optional_string?(attempt["candidate_id"]) and is_boolean(attempt["developer_closed"]) and
      plain_map?(attempt["checks"]) and
      (is_nil(attempt["review"]) or valid_review?(attempt["review"])) and
      plain_map?(attempt["executions"]) and plain_map?(attempt["infrastructure"]) and
      nonnegative?(attempt["revision"]) and
      Enum.all?(attempt["checks"], fn {id, check} ->
        id == check["check_id"] and valid_check?(check)
      end) and
      Enum.all?(attempt["executions"], fn {id, execution} ->
        id == execution["execution_id"] and valid_execution?(execution)
      end)
  rescue
    _ -> false
  end

  def valid_execution?(execution) do
    plain_map?(execution) and
      exact_keys?(
        execution,
        ~w(execution_id effect_id reservation_id role owner_id attempt_id predecessor_effect_id policy_id policy_revision control_id control_revision ledger_id ledger_generation infrastructure_generation status result stream_status verified_closed revision)
      ) and
      identities?(
        execution,
        ~w(execution_id effect_id reservation_id role owner_id policy_id control_id ledger_id)
      ) and
      optional_string?(execution["attempt_id"]) and
      optional_string?(execution["predecessor_effect_id"]) and
      execution["role"] in ~w(developer reviewer pm check integration) and
      nonnegative?(execution["policy_revision"]) and
      nonnegative?(execution["control_revision"]) and nonnegative?(execution["ledger_generation"]) and
      nonnegative?(execution["infrastructure_generation"]) and
      execution["status"] in @execution_states and
      optional_enum?(execution["result"], @execution_results) and
      execution["stream_status"] in ~w(open sealed unknown) and
      is_boolean(execution["verified_closed"]) and nonnegative?(execution["revision"])
  rescue
    _ -> false
  end

  defp valid_control?(c),
    do:
      plain_map?(c) and exact_keys?(c, ~w(revision paused draining stop_status)) and
        nonnegative?(c["revision"]) and is_boolean(c["paused"]) and is_boolean(c["draining"]) and
        c["stop_status"] in ~w(running stop_requested stop_blocked stop_completed)

  defp valid_objective?(o),
    do:
      plain_map?(o) and exact_keys?(o, ~w(objective_id phase planning_owner_id revision)) and
        identities?(o, ~w(objective_id planning_owner_id)) and o["phase"] in ~w(draft planning) and
        nonnegative?(o["revision"])

  defp valid_pm?(p),
    do:
      plain_map?(p) and
        exact_keys?(
          p,
          ~w(objective_id planning_owner_id execution infrastructure status revision)
        ) and identities?(p, ~w(objective_id planning_owner_id)) and
        (is_nil(p["execution"]) or valid_execution?(p["execution"])) and
        plain_map?(p["infrastructure"]) and
        p["status"] in ~w(queued pending running unknown blocked exhausted closed) and
        nonnegative?(p["revision"])

  defp valid_check?(c),
    do:
      plain_map?(c) and exact_keys?(c, ~w(check_id candidate_id execution_id status revision)) and
        identities?(c, ~w(check_id candidate_id execution_id)) and
        c["status"] in ~w(pending running passed failed timed_out unknown cancelled) and
        nonnegative?(c["revision"])

  defp valid_review?(r),
    do:
      plain_map?(r) and
        exact_keys?(
          r,
          ~w(review_id candidate_id check_set_id execution_id verdict stream_status verified_closed revision)
        ) and identities?(r, ~w(review_id candidate_id check_set_id execution_id)) and
        optional_enum?(r["verdict"], ~w(approved changes_requested rejected none)) and
        r["stream_status"] in ~w(open sealed unknown) and is_boolean(r["verified_closed"]) and
        nonnegative?(r["revision"])

  defp current_attempt_valid?(%{"current_attempt_id" => nil}), do: true
  defp current_attempt_valid?(t), do: Map.has_key?(t["attempts"], t["current_attempt_id"])
  defp map_values?(m, f), do: plain_map?(m) and Enum.all?(m, fn {_k, v} -> f.(v) end)
  defp exact_keys?(m, keys), do: Enum.sort(Map.keys(m)) == Enum.sort(keys)
  defp identities?(m, keys), do: Enum.all?(keys, &identity?(m[&1]))
  defp identity?(v), do: is_binary(v) and v != "" and String.valid?(v)
  defp optional_string?(nil), do: true
  defp optional_string?(v), do: identity?(v)
  defp optional_enum?(nil, _), do: true
  defp optional_enum?(v, values), do: v in values
  defp nonnegative?(v), do: is_integer(v) and v >= 0
  defp plain_map?(v), do: is_map(v) and not is_struct(v)
end
