defmodule PramanaFoundry.Workflow.Kernel.Event do
  @moduledoc """
  The closed semantic event vocabulary of the FR-08B domain kernel.

  Every type is justified by a row or entity state of
  [R4/R4a](../../../docs/WORKFLOW-CONTRACT.md#r4); the justification per name is recorded
  in `docs/fr-08/fr08b-event-vocabulary-enumeration.md`, which this module implements.

  Two properties make this a vocabulary rather than a shape check. The type list is
  closed, so an unknown type is rejected instead of reaching a generic merge. And each
  type has an **exact** payload key set, so an event can neither omit a field a guard
  reads nor smuggle an extra one past the reducer. Both are the answer to B1's
  unrestricted snapshot installer.

  `validate/2` in `template: true` mode additionally accepts `%{"binding" => name}` in
  place of any value. That lets one validator check both an unresolved transition plan's
  projected event and the concretely bound event it becomes, which is what makes the
  substitution law — binding a planned projection must equal applying its bound event to
  the same prestate — checkable without a second validator that could drift.
  """

  # Family 1, admission authority and R4a settlement. These fourteen already exist in the
  # durable codec, and each has a TransitionPlan destination slot, because FR-08A
  # subcommit 0 justified every name it seeded by a concrete binding.
  @authority_types ~w(
    launch_planned launch_settled
    check_planned check_settled
    build_planned build_settled
    review_planned review_settled
    integration_planned integration_settled
    pm_launch_planned pm_launch_settled
    control_changed ticket_reset
  )

  # Family 2, admission and steering. Durable operator or PM decisions carrying no
  # protected derivation: allocation and reservation truth stays in the R5 ledger and the
  # protected tables rather than being copied into an event payload.
  @steering_types ~w(
    objective_created ticket_admitted ticket_amended ticket_parked ticket_resumed
    cancellation_requested cancellation_finalized pm_proposal_recorded
  )

  # Family 3, sealed domain evidence. Established by sealed streams, receipts and verified
  # closure. The kernel must never infer a protected fact from one of these.
  @evidence_types ~w(
    artifact_frozen artifact_blocked freeze_failed submission_rejected
    execution_observed stream_sealed developer_closed worker_closed checks_started
    check_recorded review_recorded reviewer_closed integration_recorded attempt_settled
  )

  @types @authority_types ++ @steering_types ++ @evidence_types

  @envelope ~w(schema_version event_id type sequence entity_kind entity_id entity_revision payload)

  @payloads %{
    # Family 1. Every settlement names the execution it settles, because R4a requires a
    # proved non-start to close that execution; a settlement that cannot name one leaves
    # an execution open that no later event can close.
    #
    # The bound protected fact occupies the field named by the destination slot:
    # `authority` for launch_authority_v1, `settlement` for the settlement kinds,
    # `control` for control_fact_v1 and `generation` for reset_fact_v1.
    "launch_planned" => ~w(ticket_id attempt_id authority),
    "launch_settled" => ~w(ticket_id attempt_id execution_id settlement),
    "check_planned" => ~w(ticket_id attempt_id check_id authority),
    "check_settled" => ~w(ticket_id attempt_id check_id execution_id settlement),
    "build_planned" => ~w(ticket_id attempt_id build_id authority),
    "build_settled" => ~w(ticket_id attempt_id build_id execution_id settlement),
    "review_planned" => ~w(ticket_id attempt_id authority),
    "review_settled" => ~w(ticket_id attempt_id execution_id settlement),
    "integration_planned" => ~w(ticket_id attempt_id authority),
    "integration_settled" => ~w(ticket_id attempt_id execution_id settlement),
    "pm_launch_planned" => ~w(objective_id planning_owner_id authority),
    "pm_launch_settled" => ~w(objective_id settlement),
    # control_fact_v1 is an identity/revision fact only, so the flags R4 calls orthogonal
    # travel beside it rather than inside it.
    "control_changed" => ~w(control paused draining stop_status),
    "ticket_reset" => ~w(ticket_id generation),

    # Family 2.
    "objective_created" => ~w(objective_id planning_owner_id),
    "ticket_admitted" => ~w(ticket_id objective_id spec_revision_id spec phase reason),
    "ticket_amended" => ~w(ticket_id spec_revision_id spec),
    "ticket_parked" => ~w(ticket_id reason resume_phase),
    "ticket_resumed" => ~w(ticket_id phase),
    "cancellation_requested" => ~w(ticket_id),
    "cancellation_finalized" => ~w(ticket_id disposition),
    "pm_proposal_recorded" => ~w(proposal_id objective_id operation),

    # Family 3.
    "artifact_frozen" => ~w(ticket_id attempt_id candidate_id observation_id sealed_generation),
    "artifact_blocked" => ~w(ticket_id attempt_id observation_id result reason),
    "freeze_failed" => ~w(ticket_id attempt_id disposition reason),
    "submission_rejected" => ~w(ticket_id attempt_id observation_id reason),
    "execution_observed" => ~w(ticket_id attempt_id execution_id observation lifecycle),
    "stream_sealed" => ~w(ticket_id attempt_id execution_id last_accepted_sequence),
    "developer_closed" => ~w(ticket_id attempt_id execution_id),
    "worker_closed" => ~w(ticket_id attempt_id execution_id),
    "checks_started" => ~w(ticket_id attempt_id policy_empty),
    "check_recorded" => ~w(ticket_id attempt_id check_id status reason_code),
    "review_recorded" => ~w(ticket_id attempt_id candidate_id verdict),
    "reviewer_closed" => ~w(ticket_id attempt_id execution_id),
    "integration_recorded" => ~w(ticket_id attempt_id execution_id outcome ref_receipt_id),
    "attempt_settled" => ~w(ticket_id attempt_id disposition reason_code settlement)
  }

  # A missing or extra entry would leave a type whose payload cannot be validated, or a
  # payload no type can reach. Both fail the build rather than a later guard.
  @missing @types -- Map.keys(@payloads)
  @extra Map.keys(@payloads) -- @types
  if @missing != [] or @extra != [] do
    raise "event payload table must cover exactly the type list; " <>
            "missing: #{inspect(@missing)}, extra: #{inspect(@extra)}"
  end

  @entity_kinds ~w(ticket objective control)

  # Which entity's revision an event is checked and advanced against. Control and PM
  # planning events are not ticket events, and treating them as such is how a kernel ends
  # up advancing a ticket that the event never named.
  @entity_kind_of Map.new(@types, fn
                    type when type in ~w(control_changed) ->
                      {type, "control"}

                    type
                    when type in ~w(objective_created pm_proposal_recorded
                                    pm_launch_planned pm_launch_settled) ->
                      {type, "objective"}

                    type ->
                      {type, "ticket"}
                  end)

  @doc "The closed event vocabulary."
  @spec types() :: [String.t()]
  def types, do: @types

  @doc "The exact payload key set for `type`."
  @spec payload_keys(String.t()) :: {:ok, [String.t()]} | :error
  def payload_keys(type), do: Map.fetch(@payloads, type)

  @doc "The entity kind whose revision `type` is checked and advanced against."
  @spec entity_kind(String.t()) :: {:ok, String.t()} | :error
  def entity_kind(type), do: Map.fetch(@entity_kind_of, type)

  @doc """
  Validates one semantic event against the closed vocabulary.

  With `template: true`, any value may instead be `%{"binding" => name}`, the unresolved
  marker a transition plan carries before its protected fact is substituted.
  """
  @spec validate(term(), keyword()) :: :ok | {:error, atom()}
  def validate(event, opts \\ []) do
    template? = Keyword.get(opts, :template, false)

    with true <- plain_map?(event),
         true <- exact_keys?(event, @envelope),
         1 <- event["schema_version"],
         true <- identifier?(event["event_id"]),
         true <- event["type"] in @types,
         true <- nonnegative_integer?(event["sequence"]),
         true <- event["entity_kind"] in @entity_kinds,
         true <- event["entity_kind"] == @entity_kind_of[event["type"]],
         true <- identifier?(event["entity_id"]),
         true <- nonnegative_integer?(event["entity_revision"]),
         true <- valid_payload?(event["type"], event["payload"], template?) do
      :ok
    else
      _ -> {:error, :invalid_semantic_event}
    end
  rescue
    _ -> {:error, :invalid_semantic_event}
  end

  defp valid_payload?(type, payload, template?) do
    plain_map?(payload) and exact_keys?(payload, Map.fetch!(@payloads, type)) and
      Enum.all?(payload, fn {_key, value} -> value?(value, template?) end)
  end

  # A binding marker is only a marker when it is the whole value and nothing else, so a
  # concrete map cannot acquire marker meaning by carrying an extra key.
  defp value?(%{"binding" => name} = value, true),
    do: exact_keys?(value, ~w(binding)) and identifier?(name)

  # Outside template mode a bare marker is refused rather than passing as an ordinary map.
  # A marker that survived substitution would otherwise reach the durable event looking
  # like a bound protected fact, and no legitimate fact has this exact shape. The guard
  # keeps this to *bare* markers, so a map that merely happens to carry a "binding" key
  # alongside others still has all its values validated by the clause below.
  defp value?(%{"binding" => name} = value, false)
       when map_size(value) == 1 and is_binary(name) and name != "",
       do: false

  defp value?(value, template?) when is_map(value) and not is_struct(value),
    do: Enum.all?(value, fn {k, v} -> is_binary(k) and value?(v, template?) end)

  defp value?(value, template?) when is_list(value),
    do: proper_list?(value) and Enum.all?(value, &value?(&1, template?))

  defp value?(value, _template?) when is_binary(value), do: String.valid?(value)
  defp value?(value, _template?) when is_integer(value) or is_boolean(value), do: true
  defp value?(nil, _template?), do: true
  defp value?(_value, _template?), do: false

  # An improper list raises in length/1 rather than returning, so it is caught here rather
  # than escaping as an exception from a predicate.
  defp proper_list?(value) do
    _ = length(value)
    true
  rescue
    _ -> false
  end

  defp plain_map?(value), do: is_map(value) and not is_struct(value)
  defp exact_keys?(map, keys), do: Enum.sort(Map.keys(map)) == Enum.sort(keys)
  defp identifier?(value), do: is_binary(value) and value != "" and String.valid?(value)
  defp nonnegative_integer?(value), do: is_integer(value) and value >= 0
end
