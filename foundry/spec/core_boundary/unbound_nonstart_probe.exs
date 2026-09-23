# Probe for finding F1 in README.md: a plan-bearing bundle that stages a non-start
# settle_claim but declares NO binding passes TransitionPlan.validate/1 and bind/3 under
# unconditional_v1, committing a caller-written (forged) settlement for another execution.
# Before the fix this printed GAP REPRODUCED. Run from foundry/: MIX_ENV=test mix run --no-start spec/core_boundary/unbound_nonstart_probe.exs
alias PramanaFoundry.DurableStore.TransitionPlan

forged = %{
  "schema_version" => 1,
  "effect_id" => "effect-FORGED",
  "claim_id" => "claim-X",
  "receipt_id" => "receipt-X",
  "role" => "developer",
  "work_owner" => "owner-X",
  "infrastructure_generation" => 0,
  "predecessor_effect_id" => nil,
  "failure_class" => "proved_non_start",
  "ordinal" => 1
}

value = %{"phase" => "queued", "settlement" => forged}

proposal = %{
  "schema_version" => 1,
  "result" => %{"schema_version" => 1, "disposition" => "accepted"},
  "events" => [
    %{
      "schema_version" => 1,
      "event_id" => "event-1",
      "type" => "launch_settled",
      "payload" => %{
        "ticket_id" => "ticket-1",
        "attempt_id" => "attempt-1",
        "execution_id" => "execution-B",
        "settlement" => forged,
        "projection" => %{
          "namespace" => "atomic-v2",
          "entity_id" => "ticket-1",
          "revision" => 0,
          "value" => value
        }
      }
    }
  ],
  "projections" => [
    %{
      "schema_version" => 1,
      "namespace" => "atomic-v2",
      "entity_id" => "ticket-1",
      "expected_revision" => -1,
      "revision" => 0,
      "last_event_id" => "event-1",
      "value" => value
    }
  ],
  "intents" => []
}

plan = %{
  "schema_version" => 1,
  "command_id" => "command-1",
  "disposition" => "accepted",
  "reason_code" => nil,
  "expected_domain_revision" => 0,
  "domain_reads" => [%{"kind" => "ticket", "entity_id" => "ticket-1", "revision" => 0}],
  "protected_operations" => [
    %{"schema_version" => 1, "ordinal" => 0, "type" => "settle_claim", "input" => %{}}
  ],
  "bindings" => [],
  "alternatives" => [%{"discriminator" => "unconditional", "proposal" => proposal}],
  "discriminator_kind" => "unconditional_v1"
}

# The staged settle_claim really settled execution-A's effect-1.
staged = [
  %{
    "ordinal" => 0,
    "operation_kind" => "protected",
    "operation_type" => "settle_claim",
    "execution_status" => "committed",
    "request" => %{},
    "result" => %{
      "facts" => %{
        "infrastructure_settlement" => %{forged | "effect_id" => "effect-1"},
        "effect" => %{
          "effect_id" => "effect-1",
          "ticket_id" => "ticket-1",
          "attempt_id" => "attempt-1",
          "execution_id" => "execution-A"
        }
      }
    }
  }
]

# Fixed: every slot-typed event's slot must be filled by a declared binding.
case TransitionPlan.validate(plan) do
  {:error, :slot_value_unbound} ->
    IO.puts("GAP CLOSED: validate/1 refuses the unbound non-start (:slot_value_unbound)")

  {:ok, _} ->
    {:ok, bound} = TransitionPlan.bind(plan, "unconditional", staged)
    [event] = bound["events"]
    true = event["payload"]["execution_id"] == "execution-B"
    true = event["payload"]["settlement"]["effect_id"] == "effect-FORGED"
    IO.puts("GAP REPRODUCED: an unbound non-start under unconditional_v1 binds a forged settlement")
end
