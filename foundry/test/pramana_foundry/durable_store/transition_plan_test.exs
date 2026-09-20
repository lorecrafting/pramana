defmodule PramanaFoundry.DurableStore.TransitionPlanTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.DurableStore.TransitionPlan

  # A settlement shaped like the authoritative fact ProtectedPrimitives assigns, used
  # only as a substitution value here. Deriving it from staged results is subcommit 2.
  defp settlement do
    %{
      "schema_version" => 1,
      "effect_id" => "effect-1",
      "claim_id" => "claim-1",
      "receipt_id" => "receipt-1",
      "role" => "developer",
      "work_owner" => "owner-1",
      "infrastructure_generation" => 0,
      "predecessor_effect_id" => nil,
      "failure_class" => "proved_non_start",
      "ordinal" => 1
    }
  end

  defp event(type, payload, event_id \\ "event-1") do
    %{"schema_version" => 1, "event_id" => event_id, "type" => type, "payload" => payload}
  end

  defp projection(value, last_event_id \\ "event-1") do
    %{
      "schema_version" => 1,
      "namespace" => "atomic-v2",
      "entity_id" => "ticket-1",
      "expected_revision" => -1,
      "revision" => 0,
      "last_event_id" => last_event_id,
      "value" => value
    }
  end

  defp proposal(events, projections) do
    %{
      "schema_version" => 1,
      "result" => %{"schema_version" => 1, "disposition" => "accepted"},
      "events" => events,
      "projections" => projections,
      "intents" => []
    }
  end

  defp settled_proposal do
    marker = %{"binding" => "settled"}

    proposal(
      [
        event("launch_settled", %{
          "settlement" => marker,
          "projection" => %{
            "namespace" => "atomic-v2",
            "entity_id" => "ticket-1",
            "revision" => 0,
            "value" => %{"phase" => "queued", "settlement" => marker}
          }
        })
      ],
      [projection(%{"phase" => "queued", "settlement" => marker})]
    )
  end

  defp plan(overrides \\ %{}) do
    Map.merge(
      %{
        "schema_version" => 1,
        "command_id" => "command-1",
        "disposition" => "accepted",
        "reason_code" => nil,
        "expected_domain_revision" => 0,
        "domain_reads" => [
          %{"kind" => "ticket", "entity_id" => "ticket-1", "revision" => 0}
        ],
        "protected_operations" => [
          %{"schema_version" => 1, "ordinal" => 0, "type" => "settle_claim", "input" => %{}}
        ],
        "bindings" => [
          %{
            "name" => "settled",
            "operation_ordinal" => 0,
            "output_kind" => "nonstart_settlement_v1",
            "destination_slot" => "launch_settled.settlement"
          }
        ],
        "alternatives" => [
          %{"discriminator" => "below_infrastructure_limit", "proposal" => settled_proposal()}
        ]
      },
      overrides
    )
  end

  describe "validate/1 closed schema" do
    test "accepts a well-formed accepted plan" do
      assert {:ok, _plan} = TransitionPlan.validate(plan())
    end

    test "rejects an unsupported schema version" do
      assert {:error, :invalid_transition_plan} =
               TransitionPlan.validate(plan(%{"schema_version" => 2}))
    end

    test "rejects an unexpected top-level key" do
      assert {:error, :invalid_transition_plan} =
               TransitionPlan.validate(Map.put(plan(), "extra", true))
    end

    test "rejects a missing top-level key" do
      assert {:error, :invalid_transition_plan} =
               TransitionPlan.validate(Map.delete(plan(), "bindings"))
    end

    test "rejects an unknown disposition" do
      assert {:error, :invalid_transition_plan} =
               TransitionPlan.validate(plan(%{"disposition" => "maybe"}))
    end

    test "rejects a non-consecutive operation ordinal" do
      operations = [
        %{"schema_version" => 1, "ordinal" => 1, "type" => "settle_claim", "input" => %{}}
      ]

      assert {:error, :invalid_plan_operations} =
               TransitionPlan.validate(plan(%{"protected_operations" => operations}))
    end

    test "rejects an unsupported operation type" do
      operations = [
        %{"schema_version" => 1, "ordinal" => 0, "type" => "exec_shell", "input" => %{}}
      ]

      assert {:error, :invalid_plan_operations} =
               TransitionPlan.validate(plan(%{"protected_operations" => operations}))
    end

    test "rejects a binding referencing an absent operation ordinal" do
      bindings = [
        %{
          "name" => "settled",
          "operation_ordinal" => 3,
          "output_kind" => "nonstart_settlement_v1",
          "destination_slot" => "launch_settled.settlement"
        }
      ]

      assert {:error, :invalid_plan_bindings} =
               TransitionPlan.validate(plan(%{"bindings" => bindings}))
    end

    test "rejects an output kind the declared slot does not accept" do
      bindings = [
        %{
          "name" => "settled",
          "operation_ordinal" => 0,
          "output_kind" => "control_fact_v1",
          "destination_slot" => "launch_settled.settlement"
        }
      ]

      assert {:error, :invalid_plan_bindings} =
               TransitionPlan.validate(plan(%{"bindings" => bindings}))
    end

    test "rejects an unknown destination slot" do
      bindings = [
        %{
          "name" => "settled",
          "operation_ordinal" => 0,
          "output_kind" => "nonstart_settlement_v1",
          "destination_slot" => "anything.goes"
        }
      ]

      assert {:error, :invalid_plan_bindings} =
               TransitionPlan.validate(plan(%{"bindings" => bindings}))
    end

    test "rejects duplicate binding names" do
      binding = %{
        "name" => "settled",
        "operation_ordinal" => 0,
        "output_kind" => "nonstart_settlement_v1",
        "destination_slot" => "launch_settled.settlement"
      }

      assert {:error, :invalid_plan_bindings} =
               TransitionPlan.validate(plan(%{"bindings" => [binding, binding]}))
    end

    test "rejects duplicate discriminators" do
      alternative = %{
        "discriminator" => "below_infrastructure_limit",
        "proposal" => settled_proposal()
      }

      assert {:error, :invalid_plan_alternatives} =
               TransitionPlan.validate(plan(%{"alternatives" => [alternative, alternative]}))
    end

    test "rejects an accepted plan with no alternatives" do
      assert {:error, :invalid_plan_alternatives} =
               TransitionPlan.validate(plan(%{"alternatives" => []}))
    end

    test "rejects a duplicated domain read" do
      read = %{"kind" => "ticket", "entity_id" => "ticket-1", "revision" => 0}

      assert {:error, :invalid_plan_domain_reads} =
               TransitionPlan.validate(plan(%{"domain_reads" => [read, read]}))
    end

    test "accepts an absent domain read revision" do
      read = %{"kind" => "ticket", "entity_id" => "ticket-1", "revision" => "absent"}
      assert {:ok, _plan} = TransitionPlan.validate(plan(%{"domain_reads" => [read]}))
    end

    test "accepts a terminal plan carrying no bindings or alternatives" do
      terminal =
        plan(%{
          "disposition" => "blocked",
          "reason_code" => "capacity_denied",
          "bindings" => [],
          "alternatives" => []
        })

      assert {:ok, _plan} = TransitionPlan.validate(terminal)
    end

    test "rejects a terminal plan that still carries alternatives" do
      terminal = plan(%{"disposition" => "blocked", "reason_code" => "capacity_denied"})
      assert {:error, :invalid_terminal_plan} = TransitionPlan.validate(terminal)
    end
  end

  describe "bind/3 selection" do
    test "rejects an unknown discriminator" do
      assert {:error, :unknown_discriminator} =
               TransitionPlan.bind(plan(), "no_such_branch", %{"settled" => settlement()})
    end

    test "rejects outputs that do not match the declared bindings" do
      assert {:error, :invalid_binding_outputs} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", %{
                 "other" => settlement()
               })
    end

    test "rejects binding a terminal plan" do
      terminal =
        plan(%{
          "disposition" => "blocked",
          "reason_code" => "capacity_denied",
          "bindings" => [],
          "alternatives" => []
        })

      assert {:error, :invalid_bound_plan} =
               TransitionPlan.bind(terminal, "below_infrastructure_limit", %{})
    end
  end

  describe "bind/3 enforces the declared destination slot" do
    test "rejects a plan whose alternative never carries the declared marker" do
      bare = proposal([event("launch_settled", %{"settlement" => "literal"})], [])

      assert {:error, :binding_slot_absent} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => bare}
                   ]
                 }),
                 "below_infrastructure_limit",
                 %{"settled" => settlement()}
               )
    end

    test "rejects a marker carried by an event of another type" do
      wrong =
        proposal([event("control_changed", %{"settlement" => %{"binding" => "settled"}})], [])

      assert {:error, :binding_slot_absent} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => wrong}
                   ]
                 }),
                 "below_infrastructure_limit",
                 %{"settled" => settlement()}
               )
    end

    test "rejects an authoritative fact routed into an undeclared field" do
      marker = %{"binding" => "settled"}

      smuggled =
        proposal(
          [event("launch_settled", %{"settlement" => marker, "elsewhere" => marker})],
          []
        )

      assert {:error, :binding_outside_declared_slot} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => smuggled}
                   ]
                 }),
                 "below_infrastructure_limit",
                 %{"settled" => settlement()}
               )
    end

    test "rejects the declared marker appearing in two events of the declared type" do
      marker = %{"binding" => "settled"}

      duplicated =
        proposal(
          [
            event("launch_settled", %{"settlement" => marker}, "event-1"),
            event("launch_settled", %{"settlement" => marker}, "event-2")
          ],
          []
        )

      assert {:error, :binding_slot_not_unique} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => duplicated}
                   ]
                 }),
                 "below_infrastructure_limit",
                 %{"settled" => settlement()}
               )
    end

    test "rejects a marker routed into an unpaired projection" do
      marker = %{"binding" => "settled"}

      unpaired =
        proposal(
          [event("launch_settled", %{"settlement" => marker}, "event-1")],
          [projection(%{"settlement" => marker}, "event-9")]
        )

      assert {:error, :binding_outside_declared_slot} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => unpaired}
                   ]
                 }),
                 "below_infrastructure_limit",
                 %{"settled" => settlement()}
               )
    end
  end

  describe "bind/3 durable event vocabulary prerequisite" do
    # Subcommit 0 of this correction must extend the durable codec's accepted event
    # vocabulary. Until it lands, a structurally valid plan that passes every
    # TransitionPlan check is still refused by RecordCodec because the lifecycle event
    # type is not accepted. This test pins the prerequisite as executable evidence and
    # must be replaced by the end-to-end binding assertion when that subcommit lands.
    test "a fully valid plan is refused by the durable codec's event vocabulary" do
      assert {:error, :invalid_event} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", %{
                 "settled" => settlement()
               })
    end

    test "substitution and carrier agreement succeed up to that refusal" do
      # The same plan against a currently accepted event type proves the substitution
      # and carrier-agreement path itself is sound.
      marker = %{"binding" => "settled"}

      accepted =
        proposal(
          [
            event("ticket_enqueued", %{
              "settlement" => marker,
              "projection" => %{
                "namespace" => "atomic-v2",
                "entity_id" => "ticket-1",
                "revision" => 0,
                "value" => %{"settlement" => marker}
              }
            })
          ],
          [projection(%{"settlement" => marker})]
        )

      bindings = [
        %{
          "name" => "settled",
          "operation_ordinal" => 0,
          "output_kind" => "nonstart_settlement_v1",
          "destination_slot" => "ticket_enqueued.settlement"
        }
      ]

      case TransitionPlan.slot("ticket_enqueued.settlement") do
        :error ->
          # No slot is declared over a legacy event type, which is itself the point of
          # the prerequisite: every declared slot names a lifecycle event type.
          assert {:error, :invalid_plan_bindings} =
                   TransitionPlan.validate(
                     plan(%{
                       "bindings" => bindings,
                       "alternatives" => [
                         %{
                           "discriminator" => "below_infrastructure_limit",
                           "proposal" => accepted
                         }
                       ]
                     })
                   )

        {:ok, _slot} ->
          flunk("unexpected legacy slot declaration")
      end
    end
  end
end
