defmodule PramanaFoundry.Workflow.Kernel.State do
  @moduledoc """
  Versioned, pure domain state for the FR-08B workflow reducer.

  Root authority is deliberately absent. Identifiers and revisions appear here; policy,
  control, claim, receipt and ledger truth remain owned by the protected store, and the
  kernel may not restate them.

  `valid?/1` is **total over what the reducer reads**. The reviewed candidate's validator
  checked the outer containers and four control fields, so a ticket whose value was an
  integer passed it and then raised inside a source guard — the public decision function
  was not total over the state its own validator declared valid. That was blocker B1's
  second half. Every nested value the reducer touches is therefore validated here, against
  the closed vocabularies R4 defines, and a map's key must equal the identifier its own
  value carries so that addressing one entity cannot mutate another.
  """

  # R4 "Entity | States / terminal boundary".
  @ticket_phases ~w(draft queued developing awaiting_review reviewing ready_to_integrate
                    integrating integrated blocked exhausted rejected cancelled)
  @attempt_phases ~w(active candidate_frozen checking awaiting_review reviewing
                     ready_to_integrate integrating terminal)
  @dispositions ~w(integrated needs_correction failed timed_out blocked exhausted rejected
                   cancelled superseded_base)
  @execution_lifecycles ~w(pending starting running closing closed unknown)
  @execution_results ~w(valid blocked partial invalid none)
  @check_statuses ~w(pending running passed failed timed_out unknown cancelled)
  @stop_statuses ~w(running stop_requested stop_blocked stop_completed)
  @verdicts ~w(approved correction rejected)
  @roles ~w(developer reviewer pm check build integration)

  @state_keys ~w(schema_version control objectives tickets last_sequence last_event_id)
  @control_keys ~w(paused draining stop_status generation control_id control_revision
                   revision last_event_id)
  @objective_keys ~w(objective_id planning_owner_id proposals revision last_event_id)
  @proposal_keys ~w(proposal_id operation)
  @ticket_keys ~w(ticket_id objective_id spec_revision_id spec phase reason resume_phase
                  cancel_requested attempts active_attempt_id prior_attempt_ids
                  infrastructure revision last_event_id)
  @infrastructure_keys ~w(ordinal generation)
  @attempt_keys ~w(attempt_id phase disposition reason_code candidate_id sealed_generation
                   ref_receipt_id executions checks review)
  @execution_keys ~w(execution_id role lifecycle result sealed_sequence)
  @check_keys ~w(check_id status reason_code)
  @review_keys ~w(candidate_id verdict execution_id)

  def ticket_phases, do: @ticket_phases
  def attempt_phases, do: @attempt_phases
  def dispositions, do: @dispositions
  def execution_lifecycles, do: @execution_lifecycles
  def execution_results, do: @execution_results
  def check_statuses, do: @check_statuses
  def verdicts, do: @verdicts
  def roles, do: @roles

  @spec new() :: map()
  def new do
    %{
      "schema_version" => 1,
      "control" => %{
        "paused" => false,
        "draining" => false,
        "stop_status" => "running",
        "generation" => 0,
        "control_id" => nil,
        "control_revision" => 0,
        "revision" => 0,
        "last_event_id" => nil
      },
      "objectives" => %{},
      "tickets" => %{},
      "last_sequence" => nil,
      "last_event_id" => nil
    }
  end

  @spec valid?(term()) :: boolean()
  def valid?(state) do
    plain_map?(state) and exact_keys?(state, @state_keys) and state["schema_version"] == 1 and
      valid_control?(state["control"]) and
      valid_collection?(state["objectives"], "objective_id", &valid_objective?/1) and
      valid_collection?(state["tickets"], "ticket_id", &valid_ticket?/1) and
      optional_nonnegative_integer?(state["last_sequence"]) and
      optional_identifier?(state["last_event_id"])
  rescue
    _ -> false
  end

  # Every entity map is keyed by the identifier its own value carries. Without this an
  # event naming one identifier could be applied under another key, and replay would
  # reconstruct a different entity than the live path mutated.
  defp valid_collection?(collection, id_key, valid?) do
    plain_map?(collection) and
      Enum.all?(collection, fn {key, value} ->
        is_binary(key) and plain_map?(value) and value[id_key] == key and valid?.(value)
      end)
  end

  defp valid_control?(control) do
    plain_map?(control) and exact_keys?(control, @control_keys) and
      is_boolean(control["paused"]) and is_boolean(control["draining"]) and
      control["stop_status"] in @stop_statuses and
      nonnegative_integer?(control["generation"]) and
      optional_identifier?(control["control_id"]) and
      nonnegative_integer?(control["control_revision"]) and
      nonnegative_integer?(control["revision"]) and
      optional_identifier?(control["last_event_id"])
  end

  defp valid_objective?(objective) do
    exact_keys?(objective, @objective_keys) and identifier?(objective["objective_id"]) and
      identifier?(objective["planning_owner_id"]) and
      valid_collection?(objective["proposals"], "proposal_id", &valid_proposal?/1) and
      nonnegative_integer?(objective["revision"]) and
      optional_identifier?(objective["last_event_id"])
  end

  defp valid_proposal?(proposal) do
    exact_keys?(proposal, @proposal_keys) and identifier?(proposal["proposal_id"]) and
      identifier?(proposal["operation"])
  end

  defp valid_ticket?(ticket) do
    exact_keys?(ticket, @ticket_keys) and identifier?(ticket["ticket_id"]) and
      optional_identifier?(ticket["objective_id"]) and
      identifier?(ticket["spec_revision_id"]) and plain_map?(ticket["spec"]) and
      ticket["phase"] in @ticket_phases and optional_identifier?(ticket["reason"]) and
      (is_nil(ticket["resume_phase"]) or ticket["resume_phase"] in @ticket_phases) and
      is_boolean(ticket["cancel_requested"]) and
      valid_collection?(ticket["attempts"], "attempt_id", &valid_attempt?/1) and
      optional_identifier?(ticket["active_attempt_id"]) and
      valid_attempt_order?(ticket) and
      valid_infrastructure?(ticket["infrastructure"]) and
      nonnegative_integer?(ticket["revision"]) and
      optional_identifier?(ticket["last_event_id"])
  end

  # R4a keeps the same nonterminal attempt across a proved non-start, and R4 requires
  # prior attempts to be retained rather than replaced. Both are only meaningful if every
  # named attempt exists, the active one is nonterminal, and the two sets are disjoint —
  # the reviewed candidate lost reviewer executions and terminal evidence precisely by
  # replacing an attempt that nothing else still referenced.
  defp valid_attempt_order?(ticket) do
    attempts = ticket["attempts"]
    prior = ticket["prior_attempt_ids"]
    active = ticket["active_attempt_id"]

    is_list(prior) and Enum.all?(prior, &identifier?/1) and
      length(Enum.uniq(prior)) == length(prior) and
      Enum.all?(prior, &Map.has_key?(attempts, &1)) and
      active not in prior and
      (is_nil(active) or
         (Map.has_key?(attempts, active) and attempts[active]["phase"] != "terminal"))
  end

  defp valid_infrastructure?(infrastructure) do
    plain_map?(infrastructure) and exact_keys?(infrastructure, @infrastructure_keys) and
      nonnegative_integer?(infrastructure["ordinal"]) and
      nonnegative_integer?(infrastructure["generation"])
  end

  defp valid_attempt?(attempt) do
    exact_keys?(attempt, @attempt_keys) and identifier?(attempt["attempt_id"]) and
      attempt["phase"] in @attempt_phases and valid_disposition?(attempt) and
      optional_identifier?(attempt["reason_code"]) and
      optional_identifier?(attempt["candidate_id"]) and
      optional_identifier?(attempt["sealed_generation"]) and
      optional_identifier?(attempt["ref_receipt_id"]) and
      valid_collection?(attempt["executions"], "execution_id", &valid_execution?/1) and
      valid_collection?(attempt["checks"], "check_id", &valid_check?/1) and
      (is_nil(attempt["review"]) or valid_review?(attempt["review"]))
  end

  # R4: "Attempt disposition | Set once on terminal". A disposition on a nonterminal
  # attempt, or a terminal attempt without one, is not a state the reducer may produce, so
  # it is not one the validator may accept either.
  defp valid_disposition?(%{"phase" => "terminal"} = attempt),
    do: attempt["disposition"] in @dispositions

  defp valid_disposition?(attempt), do: is_nil(attempt["disposition"])

  defp valid_execution?(execution) do
    exact_keys?(execution, @execution_keys) and identifier?(execution["execution_id"]) and
      execution["role"] in @roles and
      execution["lifecycle"] in @execution_lifecycles and
      (is_nil(execution["result"]) or execution["result"] in @execution_results) and
      optional_nonnegative_integer?(execution["sealed_sequence"])
  end

  defp valid_check?(check) do
    exact_keys?(check, @check_keys) and identifier?(check["check_id"]) and
      check["status"] in @check_statuses and optional_identifier?(check["reason_code"])
  end

  defp valid_review?(review) do
    plain_map?(review) and exact_keys?(review, @review_keys) and
      identifier?(review["candidate_id"]) and
      (is_nil(review["verdict"]) or review["verdict"] in @verdicts) and
      optional_identifier?(review["execution_id"])
  end

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp identifier?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp optional_identifier?(value), do: is_nil(value) or identifier?(value)
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
  defp optional_nonnegative_integer?(value), do: is_nil(value) or nonnegative_integer?(value)
end
