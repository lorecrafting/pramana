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

  # The effect the same settle_claim result carries; B3 item 4 binds the settlement to it.
  defp settled_effect do
    %{
      "effect_id" => "effect-1",
      "ticket_id" => "ticket-1",
      "attempt_id" => "attempt-1",
      "execution_id" => "execution-1"
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
          "ticket_id" => "ticket-1",
          "attempt_id" => "attempt-1",
          "execution_id" => "execution-1",
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
        ],
        "discriminator_kind" => "infrastructure_limit_v1"
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
          "alternatives" => [],
          "discriminator_kind" => nil
        })

      assert {:ok, _plan} = TransitionPlan.validate(terminal)
    end

    test "rejects a terminal plan that still carries alternatives" do
      # discriminator_kind is nil so this isolates the alternatives failure rather than
      # tripping the earlier check that a terminal plan names no derivation.
      terminal =
        plan(%{
          "disposition" => "blocked",
          "reason_code" => "capacity_denied",
          "discriminator_kind" => nil
        })

      assert {:error, :invalid_terminal_plan} = TransitionPlan.validate(terminal)
    end

    test "rejects a terminal plan that still names a discriminator" do
      terminal =
        plan(%{
          "disposition" => "blocked",
          "reason_code" => "capacity_denied",
          "bindings" => [],
          "alternatives" => []
        })

      assert {:error, :invalid_transition_plan} = TransitionPlan.validate(terminal)
    end

    test "rejects an accepted plan naming an unknown derivation" do
      assert {:error, :invalid_transition_plan} =
               TransitionPlan.validate(plan(%{"discriminator_kind" => "arbitrary_code_v1"}))
    end
  end

  # Quint core_boundary F1: a slot-typed event's slot is an authoritative fact, so only a
  # declared binding may fill it. Before the fix this plan validated and bound, committing a
  # settlement the controller wrote for an execution the staged settle_claim never touched.
  describe "a slot-typed event without a binding is refused (core_boundary F1)" do
    test "an unbound non-start under unconditional_v1 carrying a literal settlement" do
      forged = %{settlement() | "effect_id" => "effect-FORGED"}

      literal =
        proposal(
          [
            event("launch_settled", %{
              "ticket_id" => "ticket-1",
              "attempt_id" => "attempt-1",
              "execution_id" => "execution-B",
              "settlement" => forged,
              "projection" => %{
                "namespace" => "atomic-v2",
                "entity_id" => "ticket-1",
                "revision" => 0,
                "value" => %{"phase" => "queued", "settlement" => forged}
              }
            })
          ],
          [projection(%{"phase" => "queued", "settlement" => forged})]
        )

      forged_plan =
        plan(%{
          "bindings" => [],
          "discriminator_kind" => "unconditional_v1",
          "alternatives" => [%{"discriminator" => "unconditional", "proposal" => literal}]
        })

      assert {:error, :slot_value_unbound} = TransitionPlan.validate(forged_plan)
      assert {:error, :slot_value_unbound} = TransitionPlan.bind(forged_plan, "unconditional", [])
    end

    test "every slot-owning event type refuses a literal slot value" do
      for type <- TransitionPlan.slot_event_types() do
        literal = proposal([event(type, %{"authority" => %{}, "settlement" => %{}})], [])

        assert {:error, :slot_value_unbound} =
                 TransitionPlan.validate(
                   plan(%{
                     "bindings" => [],
                     "discriminator_kind" => "unconditional_v1",
                     "alternatives" => [
                       %{"discriminator" => "unconditional", "proposal" => literal}
                     ]
                   })
                 ),
               type
      end
    end

    test "an unselected alternative with a literal slot is refused at ingress" do
      literal = proposal([event("launch_settled", %{"settlement" => settlement()})], [])

      assert {:error, :slot_value_unbound} =
               TransitionPlan.validate(
                 plan(%{
                   "alternatives" => [
                     %{
                       "discriminator" => "below_infrastructure_limit",
                       "proposal" => settled_proposal()
                     },
                     %{"discriminator" => "infrastructure_limit_reached", "proposal" => literal}
                   ]
                 })
               )
    end

    test "the bound form of the same plan still validates" do
      assert {:ok, _plan} = TransitionPlan.validate(plan())
    end
  end

  describe "bind/3 selection" do
    test "rejects an unknown discriminator" do
      assert {:error, :unknown_discriminator} =
               TransitionPlan.bind(plan(), "no_such_branch", [staged()])
    end

    test "rejects a staged result at an ordinal no binding names" do
      # Previously this asserted that an outputs map with the wrong keys was refused.
      # That is no longer representable: bind/3 derives outputs from staged results, so a
      # caller cannot present a differently-keyed map. The reachable failure is a staged
      # result whose ordinal no binding refers to.
      assert {:error, :staged_operation_absent} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [
                 staged(%{"ordinal" => 7})
               ])
    end

    test "rejects binding a terminal plan" do
      terminal =
        plan(%{
          "disposition" => "blocked",
          "reason_code" => "capacity_denied",
          "bindings" => [],
          "alternatives" => [],
          "discriminator_kind" => nil
        })

      assert {:error, :invalid_bound_plan} =
               TransitionPlan.bind(terminal, "below_infrastructure_limit", %{})
    end
  end

  describe "bind/3 enforces the declared destination slot" do
    test "rejects a plan whose alternative never carries the declared marker" do
      bare = proposal([], [])

      assert {:error, :binding_slot_absent} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => bare}
                   ]
                 }),
                 "below_infrastructure_limit",
                 [staged()]
               )
    end

    test "rejects a marker carried by an event of another type" do
      wrong =
        proposal([event("check_recorded", %{"settlement" => %{"binding" => "settled"}})], [])

      assert {:error, :binding_slot_absent} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => wrong}
                   ]
                 }),
                 "below_infrastructure_limit",
                 [staged()]
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
                 [staged()]
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
                 [staged()]
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
                 [staged()]
               )
    end
  end

  describe "bind/3 end to end and output validation" do
    # Subcommit 0 landed the lifecycle event vocabulary, so the plan that was previously
    # refused by RecordCodec now binds through to a normalized proposal. This replaces the
    # pinned prerequisite assertion that recorded the block.
    test "a valid plan binds its authoritative fact into a normalized proposal" do
      assert {:ok, proposal} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [staged()])

      assert [event] = proposal["events"]
      assert event["type"] == "launch_settled"
      assert event["payload"]["settlement"] == settlement()

      # The codec's carrier duality holds after substitution.
      assert [projection] = proposal["projections"]
      assert projection["last_event_id"] == event["event_id"]
      assert projection["value"]["settlement"] == settlement()

      # No unsubstituted marker survives anywhere in the bound proposal.
      refute inspect(proposal) =~ ~s("binding")
    end

    # B3 item 4: a settlement for one execution cannot close another.
    test "a settlement offered to a different execution's event is refused" do
      other =
        staged(%{
          "result" => %{
            "facts" => %{
              "infrastructure_settlement" => settlement(),
              "effect" => Map.put(settled_effect(), "execution_id", "execution-2")
            }
          }
        })

      assert {:error, :settlement_execution_mismatch} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [other])
    end

    test "a settlement whose result carries no effect is refused" do
      bare = staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => settlement()}}})

      assert {:error, :settlement_execution_mismatch} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [bare])
    end

    test "binding is refused when no staged result is present" do
      assert {:error, :staged_operation_absent} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [])
    end

    test "a marker naming a binding the plan never declared rejects" do
      marker = %{"binding" => "settled"}
      stray = %{"binding" => "never_declared"}

      undeclared =
        proposal(
          [event("launch_settled", %{"settlement" => marker, "note" => stray})],
          []
        )

      assert {:error, :binding_undeclared} =
               TransitionPlan.bind(
                 plan(%{
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => undeclared}
                   ]
                 }),
                 "below_infrastructure_limit",
                 [staged()]
               )
    end

    for {label, name} <- [{"integer", 42}, {"nil", nil}, {"list", ["settled"]}] do
      @marker_name name

      test "a marker named by a #{label} rejects instead of raising" do
        marker = %{"binding" => "settled"}
        stray = %{"binding" => @marker_name}

        hostile =
          proposal([event("launch_settled", %{"settlement" => marker, "note" => stray})], [])

        assert {:error, :binding_undeclared} =
                 TransitionPlan.bind(
                   plan(%{
                     "alternatives" => [
                       %{"discriminator" => "below_infrastructure_limit", "proposal" => hostile}
                     ]
                   }),
                   "below_infrastructure_limit",
                   [staged()]
                 )
      end
    end

    test "a staged fact that is not a map rejects" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => "nope"}}})
               ])
    end

    test "an authoritative settlement missing a field rejects" do
      fact = Map.delete(settlement(), "receipt_id")

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => fact}}})
               ])
    end

    test "a caller cannot supply a fact at all" do
      # The interface offers nowhere to put one. bind/3 takes staged protected results,
      # so the forgery this codec was hardened against is now unrepresentable rather
      # than rejected. Passing anything that is not a staged result list fails.
      assert {:error, :invalid_operation_results} =
               TransitionPlan.bind(plan(), "below_infrastructure_limit", %{
                 "settled" => settlement()
               })
    end
  end

  describe "derive_outputs/2 uses only authoritative staged facts" do
    defp staged(overrides \\ %{}) do
      Map.merge(
        %{
          "ordinal" => 0,
          "operation_kind" => "protected",
          "operation_type" => "settle_claim",
          "execution_status" => "committed",
          "request" => %{},
          "result" => %{
            "facts" => %{
              "infrastructure_settlement" => settlement(),
              "effect" => settled_effect()
            }
          }
        },
        overrides
      )
    end

    defp settlement_binding do
      [
        %{
          "name" => "settled",
          "operation_ordinal" => 0,
          "output_kind" => "nonstart_settlement_v1",
          "destination_slot" => "launch_settled.settlement"
        }
      ]
    end

    test "derives a settlement from a committed settle_claim result" do
      assert {:ok, %{"settled" => derived}} =
               TransitionPlan.derive_outputs(settlement_binding(), [staged()])

      assert derived["ordinal"] == 1
      assert derived["effect_id"] == "effect-1"
      assert derived["schema_version"] == 1
    end

    test "rejects a binding naming an absent operation ordinal" do
      assert {:error, :staged_operation_absent} =
               TransitionPlan.derive_outputs(settlement_binding(), [staged(%{"ordinal" => 4})])
    end

    test "rejects duplicated staged ordinals" do
      assert {:error, :staged_operation_not_unique} =
               TransitionPlan.derive_outputs(settlement_binding(), [staged(), staged()])
    end

    test "rejects a rolled-back operation" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"execution_status" => "rolled_back"})
               ])
    end

    test "rejects an operation of the wrong type" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"operation_type" => "set_control"})
               ])
    end

    test "rejects a non-protected operation" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"operation_kind" => "domain"})
               ])
    end

    test "rejects a result carrying no settlement fact" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"result" => %{"facts" => %{}}})
               ])
    end

    test "rejects a settlement whose ordinal is not positive" do
      fact = Map.put(settlement(), "ordinal", 0)

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => fact}}})
               ])
    end

    test "rejects a settlement carrying an unexpected field" do
      fact = Map.put(settlement(), "smuggled", true)

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => fact}}})
               ])
    end

    test "rejects a settlement missing a required field" do
      fact = Map.delete(settlement(), "role")

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => fact}}})
               ])
    end

    test "projects a control fact into its declared shape" do
      bindings = [
        %{
          "name" => "control",
          "operation_ordinal" => 0,
          "output_kind" => "control_fact_v1",
          "destination_slot" => "control_changed.control"
        }
      ]

      state = %{
        "schema_version" => 1,
        "control_id" => "control-1",
        "revision" => 3,
        "value" => %{"status" => "active"}
      }

      result =
        staged(%{
          "operation_type" => "set_control",
          "result" => %{"facts" => %{"root_control" => state}}
        })

      assert {:ok, %{"control" => derived}} = TransitionPlan.derive_outputs(bindings, [result])

      assert derived == %{
               "schema_version" => 1,
               "control_id" => "control-1",
               "control_revision" => 3
             }
    end

    test "rejects a fact that is present but not a map" do
      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(settlement_binding(), [
                 staged(%{"result" => %{"facts" => %{"infrastructure_settlement" => "nope"}}})
               ])
    end

    test "every output kind has a producer, and only its producer's result binds" do
      # All five kinds are derivable since close_attempt produced terminal_settlement_v1.
      # A kind pointed at another operation's result must still refuse rather than
      # default to whatever fact that result happens to carry.
      assert Enum.sort(Enum.map(TransitionPlan.producer_operations(), &elem(&1, 0))) ==
               Enum.sort(TransitionPlan.output_kinds())

      bindings = [
        %{
          "name" => "terminal",
          "operation_ordinal" => 0,
          "output_kind" => "terminal_settlement_v1",
          "destination_slot" => "attempt_settled.settlement"
        }
      ]

      assert {:error, :unbindable_operation_result} =
               TransitionPlan.derive_outputs(bindings, [staged()])
    end
  end

  # Item 2 of the FR-08B protected items spec: one ticket reset binds one reset_generation
  # fact per dimension, as a list in ticket_reset.generation.
  describe "reset facts bind as a list" do
    defp reset_staged(ordinal, dimension) do
      %{
        "ordinal" => ordinal,
        "operation_kind" => "protected",
        "operation_type" => "reset_generation",
        "execution_status" => "committed",
        "request" => %{},
        "result" => %{
          "facts" => %{
            "new_generation" => %{
              "schema_version" => 1,
              "ledger_id" => "ledger-#{dimension}",
              "dimension" => dimension,
              "generation" => 1,
              "authorized" => 2,
              "available" => 2,
              "status" => "open"
            }
          }
        }
      }
    end

    defp reset_plan(generation_field) do
      marker = fn name -> %{"binding" => name} end

      plan(%{
        "protected_operations" => [
          %{"schema_version" => 1, "ordinal" => 0, "type" => "reset_generation", "input" => %{}},
          %{"schema_version" => 1, "ordinal" => 1, "type" => "reset_generation", "input" => %{}}
        ],
        "bindings" =>
          for {name, ordinal} <- [{"starts", 0}, {"requests", 1}] do
            %{
              "name" => name,
              "operation_ordinal" => ordinal,
              "output_kind" => "reset_fact_v1",
              "destination_slot" => "ticket_reset.generation"
            }
          end,
        "discriminator_kind" => "unconditional_v1",
        "alternatives" => [
          %{
            "discriminator" => "unconditional",
            "proposal" =>
              proposal(
                [
                  event("ticket_reset", %{
                    "ticket_id" => "ticket-1",
                    "generation" => generation_field.(marker)
                  })
                ],
                []
              )
          }
        ]
      })
    end

    test "an unconditional plan has exactly one alternative, named unconditional" do
      plan = reset_plan(fn m -> [m.("starts"), m.("requests")] end)
      [only] = plan["alternatives"]

      assert {:ok, _} = TransitionPlan.validate(plan)

      assert {:error, :invalid_plan_alternatives} =
               TransitionPlan.validate(%{
                 plan
                 | "alternatives" => [only, %{only | "discriminator" => "other"}]
               })

      assert {:error, :invalid_plan_alternatives} =
               TransitionPlan.validate(%{
                 plan
                 | "alternatives" => [%{only | "discriminator" => "other"}]
               })
    end

    # Review of 03aff5db, blocker: an unconditional plan binding a non-start settlement let
    # the controller pick the below-limit branch past the limit.
    test "a non-start settlement cannot be bound by an unconditional plan" do
      [below | _] = plan()["alternatives"]

      bypass =
        plan(%{
          "discriminator_kind" => "unconditional_v1",
          "alternatives" => [%{below | "discriminator" => "unconditional"}]
        })

      assert {:error, :nonstart_requires_infrastructure_discriminator} =
               TransitionPlan.validate(bypass)

      assert {:error, :nonstart_requires_infrastructure_discriminator} =
               TransitionPlan.bind(bypass, "unconditional", [staged()])
    end

    test "two list-slot bindings from one operation are refused" do
      plan = reset_plan(fn m -> [m.("starts"), m.("requests")] end)

      plan =
        update_in(plan["bindings"], fn bs ->
          Enum.map(bs, &Map.put(&1, "operation_ordinal", 0))
        end)

      assert {:error, :list_slot_operation_repeated} = TransitionPlan.validate(plan)
    end

    test "both dimensions' reset facts land in the one ticket_reset" do
      plan = reset_plan(fn m -> [m.("starts"), m.("requests")] end)

      assert {:ok, proposal} =
               TransitionPlan.bind(plan, "unconditional", [
                 reset_staged(0, "starts.developer"),
                 reset_staged(1, "model_requests")
               ])

      assert [event] = proposal["events"]

      assert [%{"dimension" => "starts.developer"}, %{"dimension" => "model_requests"}] =
               event["payload"]["generation"]

      assert Enum.all?(event["payload"]["generation"], &(&1["generation"] == 1))
    end

    test "a literal element beside the bound facts is refused" do
      forged = %{
        "schema_version" => 1,
        "ledger_id" => "x",
        "dimension" => "d",
        "generation" => 9,
        "authorized" => 99
      }

      plan = reset_plan(fn m -> [m.("starts"), m.("requests"), forged] end)

      assert {:error, :slot_value_unbound} =
               TransitionPlan.bind(plan, "unconditional", [
                 reset_staged(0, "starts.developer"),
                 reset_staged(1, "model_requests")
               ])
    end

    test "a single marker where the list slot expects a list is refused" do
      plan = reset_plan(fn m -> m.("starts") end)

      assert {:error, :slot_value_unbound} =
               TransitionPlan.bind(plan, "unconditional", [
                 reset_staged(0, "starts.developer"),
                 reset_staged(1, "model_requests")
               ])
    end
  end

  describe "R4a coverage of the slot and producer vocabulary" do
    # This is the assertion whose absence let two independent reviews pass a codec that
    # could not express two of R4a's four domain-owner rows. It checks coverage of the
    # contract, not mechanics.
    test "every R4a domain owner has a settlement destination slot" do
      for owner <- ~w(launch check build review integration pm_launch) do
        slot = "#{owner}_settled.settlement"

        assert {:ok, {_type, "settlement", "nonstart_settlement_v1"}} =
                 TransitionPlan.slot(slot),
               "R4a domain owner #{owner} has no settlement slot"
      end
    end

    test "every declared admission slot can actually bind an authority fact" do
      for owner <- ~w(launch check build review integration pm_launch) do
        slot = "#{owner}_planned.authority"
        assert {:ok, {_type, "authority", kind}} = TransitionPlan.slot(slot)

        # Declarable is not enough; the kind must have a producer or the slot is inert.
        assert kind in TransitionPlan.output_kinds()

        assert {:ok, %{"settled" => _}} =
                 TransitionPlan.derive_outputs(
                   [
                     %{
                       "name" => "settled",
                       "operation_ordinal" => 0,
                       "output_kind" => kind,
                       "destination_slot" => slot
                     }
                   ],
                   [issued_effect_result()]
                 ),
               "admission slot #{slot} declares #{kind}, which has no producer"
      end
    end
  end

  describe "launch_authority_v1 derivation" do
    test "projects the authoritative issued effect into the declared shape" do
      assert {:ok, %{"authority" => authority}} =
               TransitionPlan.derive_outputs(
                 [
                   %{
                     "name" => "authority",
                     "operation_ordinal" => 0,
                     "output_kind" => "launch_authority_v1",
                     "destination_slot" => "launch_planned.authority"
                   }
                 ],
                 [issued_effect_result()]
               )

      # The projection renames: the effect's assignment_id is the work owner and its
      # phase_generation is the infrastructure generation.
      assert authority["work_owner"] == "owner-1"
      assert authority["infrastructure_generation"] == 0
      assert authority["effect_id"] == "effect-1"
      refute Map.has_key?(authority, "assignment_id")
      refute Map.has_key?(authority, "phase_generation")

      # Nothing not authoritatively carried by one operation leaks in.
      refute Map.has_key?(authority, "reservation_id")
      refute Map.has_key?(authority, "ledger_id")
    end

    test "an effect missing an authoritative field fails closed" do
      broken = put_in(issued_effect_result(), ["result", "facts", "effect", "role"], nil)

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.derive_outputs(
                 [
                   %{
                     "name" => "authority",
                     "operation_ordinal" => 0,
                     "output_kind" => "launch_authority_v1",
                     "destination_slot" => "launch_planned.authority"
                   }
                 ],
                 [issued_effect_result()]
                 |> List.replace_at(0, broken)
               )
    end

    test "a forged authority output is refused by bind/3's shape gate" do
      bindings = [
        %{
          "name" => "authority",
          "operation_ordinal" => 0,
          "output_kind" => "launch_authority_v1",
          "destination_slot" => "launch_planned.authority"
        }
      ]

      planned =
        proposal([event("launch_planned", %{"authority" => %{"binding" => "authority"}})], [])

      assert {:error, :invalid_authoritative_fact} =
               TransitionPlan.bind(
                 plan(%{
                   "bindings" => bindings,
                   "alternatives" => [
                     %{"discriminator" => "below_infrastructure_limit", "proposal" => planned}
                   ]
                 }),
                 "below_infrastructure_limit",
                 [
                   %{
                     issued_effect_result()
                     | "result" => %{"facts" => %{"effect" => %{"effect_id" => "only-one"}}}
                   }
                 ]
               )
    end
  end

  defp issued_effect_result do
    %{
      "ordinal" => 0,
      "operation_kind" => "protected",
      "operation_type" => "issue_claim",
      "execution_status" => "committed",
      "request" => %{},
      "result" => %{
        "facts" => %{
          "effect" => %{
            "schema_version" => 1,
            "effect_id" => "effect-1",
            "role" => "developer",
            "assignment_id" => "owner-1",
            "ticket_id" => "T1",
            "attempt_id" => "A1",
            "execution_id" => "execution-1",
            "policy_id" => "policy-1",
            "policy_revision" => 0,
            "control_id" => "control-1",
            "control_revision" => 0,
            "predecessor_effect_id" => nil,
            "phase_generation" => 0,
            "request_digest" => "digest",
            "operation" => "launch",
            "scope" => "ticket:T1"
          }
        }
      }
    }
  end

  describe "vocabulary agreement with the protected layer" do
    # These two directions were both violated at once: consume_validation was declarable
    # but is not a protected operation, and issue_claim is required by @producers but was
    # not declarable — which silently disabled every admission slot as soon as the
    # declared-versus-staged coherence check made the list load-bearing.
    test "every declarable operation is a real protected operation" do
      for type <- TransitionPlan.operation_types() do
        assert PramanaFoundry.DurableStore.ProtectedPrimitives.supported_operation_type?(type),
               "#{type} is declarable in a plan but is not a protected operation"
      end
    end

    test "every producing operation is declarable" do
      for {kind, type} <- TransitionPlan.producer_operations() do
        assert type in TransitionPlan.operation_types(),
               "#{kind} is produced by #{type}, which no plan can declare"
      end
    end
  end
end
