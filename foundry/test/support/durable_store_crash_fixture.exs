alias PramanaFoundry.DurableStore.Gateway

[path, boundary] = System.argv()
fault = if boundary == "before", do: {:halt, :before_commit}, else: {:halt, :after_commit}
capability = make_ref()

build = fn command_id ->
  projection_key =
    "projection/" <>
      Base.url_encode64("kernel-v1", padding: false) <>
      "/" <> Base.url_encode64("ticket-" <> command_id, padding: false)

  command = %{
    "schema_version" => 1,
    "command_id" => command_id,
    "expected_revisions" => %{projection_key => "absent"},
    "type" => "request_effect",
    "target_ids" => %{},
    "payload" => %{}
  }

  projection = %{
    "namespace" => "kernel-v1",
    "entity_id" => "ticket-" <> command_id,
    "revision" => 0,
    "value" => %{}
  }

  proposal = %{
    schema_version: 1,
    result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
    events: [
      %{
        schema_version: 1,
        event_id: "event-" <> command_id,
        type: "effect_requested",
        payload: %{"projection" => projection}
      }
    ],
    projections: [
      %{
        schema_version: 1,
        namespace: projection["namespace"],
        entity_id: projection["entity_id"],
        expected_revision: -1,
        revision: 0,
        last_event_id: "event-" <> command_id,
        value: %{}
      }
    ],
    intents: [
      %{
        schema_version: 1,
        effect_id: "effect-" <> command_id,
        request_digest:
          elem(
            PramanaFoundry.DurableStore.Encoding.semantic_digest(
              "pramana-foundry-effect-request-v1",
              %{"effect_id" => "effect-" <> command_id, "operation" => %{"operation" => "check"}}
            ),
            1
          ),
        status: "pending",
        value: %{"operation" => "check"}
      }
    ]
  }

  protected = %{
    writer_epoch: "fixture-epoch",
    required_revisions: %{projection_key => "absent"},
    ledger_generations: [
      %{
        schema_version: 1,
        generation_id: "generation-" <> command_id,
        parent_generation_id: nil,
        allocation: 1,
        consumed: 0
      }
    ],
    effect_authorizations: [
      %{
        effect_id: "effect-" <> command_id,
        claim_id: "claim-" <> command_id,
        generation_id: "generation-" <> command_id,
        reservation_id: "reservation-" <> command_id,
        dimension: "starts.developer",
        units: 1
      }
    ]
  }

  {command, proposal, protected}
end

:ok = Gateway.initialize(path)
{:ok, baseline_gateway} = Gateway.start_link(path: path, protected_capability: capability)
{baseline_command, baseline_proposal, baseline_protected} = build.("crash-baseline")

{:ok, _result, :committed} =
  Gateway.transact_verified(
    baseline_gateway,
    capability,
    "fixture",
    baseline_command,
    baseline_proposal,
    baseline_protected
  )

:ok = GenServer.stop(baseline_gateway)
{:ok, gateway} = Gateway.start_link(path: path, fault: fault, protected_capability: capability)
{command, proposal, protected} = build.("crash-" <> boundary)
Gateway.transact_verified(gateway, capability, "fixture", command, proposal, protected)
System.halt(70)
