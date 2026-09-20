defmodule PramanaFoundry.Workflow.KernelTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Workflow.Kernel

  @phases ~w(draft queued developing awaiting_review reviewing ready_to_integrate integrating integrated blocked exhausted rejected cancelled)

  defp command(type, targets \\ %{}, payload \\ %{}, id \\ nil) do
    %{
      "schema_version" => 1,
      "command_id" => id || "command-#{type}",
      "type" => type,
      "target_ids" => targets,
      "payload" => payload
    }
  end

  defp inputs(overrides \\ %{}) do
    base = %{
      "recorded_at" => "2026-09-20T12:00:00Z",
      "event_id" => "event-1",
      "ids" => %{},
      "observation" => %{},
      "protected" => %{}
    }

    Map.merge(base, overrides, fn _key, left, right ->
      if is_map(left) and is_map(right), do: Map.merge(left, right), else: right
    end)
  end

  defp accepted(state, command, inputs) do
    assert {:ok, %{"disposition" => "accepted", "events" => events} = decision} =
             Kernel.decide(state, command, inputs)

    next =
      Enum.reduce(events, state, fn event, acc ->
        {:ok, value} = Kernel.apply(acc, event)
        value
      end)

    {next, events, decision}
  end

  defp ticket(phase, extra \\ %{}) do
    base = %{
      "ticket_id" => "ticket-1",
      "objective_id" => "objective-1",
      "phase" => phase,
      "resume_phase" => nil,
      "reason" => nil,
      "spec_revision_id" => "spec-1",
      "spec" => %{"title" => "Ticket", "scope" => []},
      "attempt" => nil,
      "prior_attempts" => [],
      "cancel_status" => nil,
      "authority_bindings" => %{},
      "history" => []
    }

    Map.merge(base, extra)
  end

  defp attempt(phase \\ "active", extra \\ %{}) do
    base = %{
      "attempt_id" => "attempt-1",
      "phase" => phase,
      "disposition" => nil,
      "resume_phase" => nil,
      "lineage" => %{
        "spec_revision_id" => "spec-1",
        "policy_id" => "policy-1",
        "policy_revision" => 1
      },
      "candidate_id" => nil,
      "executions" => %{},
      "infrastructure" => %{}
    }

    Map.merge(base, extra)
  end

  defp state_with(ticket) do
    put_in(Kernel.new(), ["tickets", ticket["ticket_id"]], ticket)
  end

  defp launch_inputs(role, outcome \\ "admitted") do
    inputs(%{
      "event_id" => "event-launch-#{role}-#{outcome}",
      "ids" => %{
        "attempt_id" => "attempt-1",
        "execution_id" => "execution-#{role}",
        "effect_id" => "effect-#{role}",
        "reservation_id" => "reservation-#{role}"
      },
      "observation" => %{"outcome" => outcome, "reason" => "capacity"},
      "protected" => %{
        "reservation" => "reserved",
        "policy_id" => "policy-1",
        "policy_revision" => 1,
        "control_id" => "control-1",
        "control_revision" => 1,
        "ledger_id" => "ledger-#{role}",
        "ledger_generation" => 3,
        "dimension" => "starts.#{role}"
      }
    })
  end

  defp receipt_inputs(role, outcome, extra \\ %{}) do
    base = %{
      "event_id" => "event-receipt-#{role}-#{outcome}",
      "ids" => %{
        "execution_id" => "execution-#{role}",
        "claim_id" => "claim-#{role}",
        "receipt_id" => "receipt-#{role}-#{outcome}"
      },
      "protected" => %{
        "settlement" => outcome,
        "receipt_id" => "receipt-#{role}-#{outcome}",
        "claim_id" => "claim-#{role}",
        "allocation" => "eligible",
        "infrastructure_generation" => 2,
        "infrastructure_ordinal" => 1,
        "infrastructure_limit" => 3,
        "predecessor_effect_id" => "effect-prior",
        "failure_class" => "launcher_refused"
      }
    }

    inputs(
      Map.merge(base, extra, fn _key, left, right ->
        if is_map(left) and is_map(right), do: Map.merge(left, right), else: right
      end)
    )
  end

  test "fixed inputs produce byte-identical decisions and live apply equals replay" do
    state = Kernel.new()
    command = command("pause", %{}, %{})

    input =
      inputs(%{
        "protected" => %{"control" => "committed", "control_id" => "c1", "control_revision" => 2}
      })

    assert Kernel.decide(state, command, input) == Kernel.decide(state, command, input)
    {:ok, decision} = Kernel.decide(state, command, input)
    [event] = decision["events"]
    {:ok, live} = Kernel.apply(state, event)
    assert {:ok, ^live} = Kernel.rebuild([event])
    assert live["control"]["paused"]
  end

  test "published R4 guard matrix contains every normative row exactly once" do
    matrix = Kernel.guard_matrix()
    assert Enum.map(matrix, & &1.row) == Enum.to_list(1..28)
    assert Enum.all?(matrix, &(is_binary(&1.source) and is_binary(&1.command)))
  end

  test "all twelve canonical command types have an explicit verdict" do
    cases = [
      {"legacy_event_append", Kernel.new(), %{}, %{}, "rejected"},
      {"enqueue", Kernel.new(), %{"ticket_id" => "ticket-1", "objective_id" => "objective-1"},
       %{"spec" => %{"title" => "T", "scope" => []}}, "accepted"},
      {"steer", Kernel.new(), %{"objective_id" => "objective-1"},
       %{"operation" => "create_objective"}, "accepted"},
      {"pause", Kernel.new(), %{}, %{}, "accepted"},
      {"resume", Kernel.new(), %{}, %{"operation" => "workflow"}, "accepted"},
      {"cancel", state_with(ticket("queued")), %{"ticket_id" => "ticket-1"}, %{}, "accepted"},
      {"reset", state_with(ticket("exhausted")), %{"ticket_id" => "ticket-1"}, %{}, "accepted"},
      {"propose",
       put_in(Kernel.new(), ["objectives", "objective-1"], %{"objective_id" => "objective-1"}),
       %{"objective_id" => "objective-1"}, %{"operation" => "create"}, "accepted"},
      {"submit_artifact", state_with(ticket("developing", %{"attempt" => attempt()})),
       %{"ticket_id" => "ticket-1"}, %{"result" => "invalid"}, "rejected"},
      {"submit_review",
       state_with(
         ticket("reviewing", %{
           "attempt" => attempt("reviewing", %{"candidate_id" => "candidate-1"})
         })
       ), %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}, "accepted"},
      {"request_effect", state_with(ticket("queued")), %{"ticket_id" => "ticket-1"},
       %{"role" => "developer"}, "accepted"},
      {"record_receipt", launched_developer_state(), %{"ticket_id" => "ticket-1"},
       %{"role" => "developer", "outcome" => "unknown"}, "accepted"}
    ]

    Enum.with_index(cases, 1)
    |> Enum.each(fn {{type, state, targets, payload, disposition}, index} ->
      input = command_inputs(type, index)

      assert {:ok, %{"disposition" => ^disposition}} =
               Kernel.decide(state, command(type, targets, payload, "matrix-#{index}"), input)
    end)

    assert Kernel.supported_commands() |> Enum.sort() ==
             Enum.map(cases, &elem(&1, 0)) |> Enum.sort()
  end

  test "artifact and review verdict matrices preserve frozen candidate custody" do
    developing = state_with(ticket("developing", %{"attempt" => attempt()}))

    for verdict <- ~w(blocked partial) do
      input =
        inputs(%{
          "event_id" => "artifact-#{verdict}",
          "ids" => %{"observation_id" => "obs-#{verdict}"}
        })

      {next, _events, _decision} =
        accepted(
          developing,
          command(
            "submit_artifact",
            %{"ticket_id" => "ticket-1"},
            %{"result" => verdict},
            "artifact-#{verdict}"
          ),
          input
        )

      assert next["tickets"]["ticket-1"]["phase"] == "blocked"
      assert next["tickets"]["ticket-1"]["attempt"]["disposition"] == "blocked"
    end

    invalid = inputs(%{"ids" => %{"observation_id" => "obs-invalid"}})

    assert {:ok, %{"disposition" => "rejected", "events" => []}} =
             Kernel.decide(
               developing,
               command("submit_artifact", %{"ticket_id" => "ticket-1"}, %{"result" => "invalid"}),
               invalid
             )

    reviewing =
      state_with(
        ticket("reviewing", %{
          "attempt" => attempt("reviewing", %{"candidate_id" => "candidate-1"})
        })
      )

    for verdict <- ~w(approved changes_requested rejected) do
      input =
        inputs(%{
          "event_id" => "review-#{verdict}",
          "ids" => %{"review_id" => "review-#{verdict}"},
          "protected" => %{"candidate_id" => "candidate-1", "draining" => false}
        })

      {next, _events, _decision} =
        accepted(
          reviewing,
          command(
            "submit_review",
            %{"ticket_id" => "ticket-1"},
            %{"verdict" => verdict},
            "review-command-#{verdict}"
          ),
          input
        )

      expected =
        %{"approved" => "reviewing", "changes_requested" => "queued", "rejected" => "rejected"}[
          verdict
        ]

      assert next["tickets"]["ticket-1"]["phase"] == expected
      assert next["tickets"]["ticket-1"]["attempt"]["candidate_id"] == "candidate-1"
    end
  end

  test "approved review requires verified reviewer close and cannot be overwritten by completion" do
    reviewing =
      state_with(
        ticket("reviewing", %{
          "attempt" => attempt("reviewing", %{"candidate_id" => "candidate-1"})
        })
      )

    review_input =
      inputs(%{
        "ids" => %{"review_id" => "review-1"},
        "protected" => %{"candidate_id" => "candidate-1"}
      })

    {reviewed, _, _} =
      accepted(
        reviewing,
        command("submit_review", %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}),
        review_input
      )

    assert {:ok, %{"disposition" => "rejected"}} =
             Kernel.decide(
               reviewed,
               command("submit_artifact", %{"ticket_id" => "ticket-1"}, %{"result" => "none"}),
               inputs(%{"ids" => %{"observation_id" => "late"}})
             )

    close_input =
      inputs(%{
        "event_id" => "reviewer-close",
        "observation" => %{"termination" => "verified_closed"}
      })

    {ready, _, _} =
      accepted(
        reviewed,
        command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "reviewer_closed"}),
        close_input
      )

    assert ready["tickets"]["ticket-1"]["phase"] == "ready_to_integrate"
  end

  test "every guarded ticket command rejects all unlisted terminal source states without mutation" do
    guarded = [
      command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
      command("submit_artifact", %{"ticket_id" => "ticket-1"}, %{"result" => "valid"}),
      command("submit_review", %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}),
      command("cancel", %{"ticket_id" => "ticket-1"}, %{}),
      command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "block"})
    ]

    for phase <- ~w(integrated rejected cancelled), command <- guarded do
      state =
        state_with(ticket(phase, %{"attempt" => attempt("terminal", %{"disposition" => phase})}))

      assert {:ok, %{"disposition" => "rejected", "events" => []}} =
               Kernel.decide(state, command, command_inputs(command["type"], 90))

      assert state["tickets"]["ticket-1"]["phase"] == phase
    end
  end

  test "R4 source-state guards reject each known phase outside its listed row" do
    rows = [
      {command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
       ~w(queued blocked)},
      {command("submit_artifact", %{"ticket_id" => "ticket-1"}, %{"result" => "invalid"}),
       ~w(developing)},
      {command("submit_review", %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}),
       ~w(reviewing)},
      {command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "start_checks"}),
       ~w(awaiting_review)},
      {command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "base_moved"}),
       ~w(ready_to_integrate integrating)}
    ]

    for {command, listed} <- rows, phase <- @phases -- listed do
      state = state_with(ticket(phase, %{"attempt" => attempt_for_phase(phase)}))

      assert {:ok, %{"disposition" => "rejected", "events" => []}} =
               Kernel.decide(state, command, command_inputs(command["type"], 91))
    end
  end

  test "R4a developer pre-intent denial, non-start, unknown and exhaustion are deterministic" do
    queued = state_with(ticket("queued"))
    denial = launch_inputs("developer", "pre_intent_denied")

    assert {:ok, %{"disposition" => "blocked", "reason_code" => "capacity", "events" => []}} =
             Kernel.decide(
               queued,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
               denial
             )

    assert queued["tickets"]["ticket-1"]["attempt"] == nil

    launched = launched_developer_state()
    unknown = receipt_inputs("developer", "unknown")

    {unknown_state, unknown_events, _} =
      accepted(
        launched,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "developer",
          "outcome" => "unknown"
        }),
        unknown
      )

    assert get_in(unknown_state, [
             "tickets",
             "ticket-1",
             "attempt",
             "executions",
             "execution-developer",
             "status"
           ]) == "unknown"

    assert {:ok, ^unknown_state} = Kernel.rebuild(events_to_state(launched) ++ unknown_events)

    nonstart = receipt_inputs("developer", "non_started")

    {queued_again, events, _} =
      accepted(
        launched,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "developer",
          "outcome" => "non_started"
        }),
        nonstart
      )

    assert queued_again["tickets"]["ticket-1"]["phase"] == "queued"
    assert queued_again["tickets"]["ticket-1"]["attempt"]["attempt_id"] == "attempt-1"

    assert get_in(queued_again, [
             "tickets",
             "ticket-1",
             "attempt",
             "infrastructure",
             "developer",
             "ordinal"
           ]) == 1

    assert length(events) == 1

    exhausted =
      receipt_inputs("developer", "non_started", %{"protected" => %{"allocation" => "exhausted"}})

    {exhausted_state, _, _} =
      accepted(
        launched,
        command(
          "record_receipt",
          %{"ticket_id" => "ticket-1"},
          %{"role" => "developer", "outcome" => "non_started"},
          "exhausted"
        ),
        exhausted
      )

    assert exhausted_state["tickets"]["ticket-1"]["phase"] == "exhausted"
    assert exhausted_state["tickets"]["ticket-1"]["attempt"]["disposition"] == "exhausted"
  end

  test "R4a reviewer retains frozen candidate and PM retains planning owner" do
    reviewer_ticket =
      ticket("awaiting_review", %{
        "attempt" =>
          attempt("awaiting_review", %{
            "candidate_id" => "candidate-1",
            "check_set_id" => "checks-1"
          })
      })

    reviewer_state = state_with(reviewer_ticket)

    {reviewing, _, _} =
      accepted(
        reviewer_state,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "reviewer"}),
        launch_inputs("reviewer")
      )

    receipt = receipt_inputs("reviewer", "non_started")

    {after_nonstart, _, _} =
      accepted(
        reviewing,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "reviewer",
          "outcome" => "non_started"
        }),
        receipt
      )

    assert after_nonstart["tickets"]["ticket-1"]["phase"] == "awaiting_review"
    assert after_nonstart["tickets"]["ticket-1"]["attempt"]["candidate_id"] == "candidate-1"
    assert after_nonstart["tickets"]["ticket-1"]["attempt"]["check_set_id"] == "checks-1"

    objective = %{
      "objective_id" => "objective-1",
      "phase" => "draft",
      "planning_owner_id" => "planner-1",
      "authority_bindings" => %{}
    }

    pm_state = put_in(Kernel.new(), ["objectives", "objective-1"], objective)

    {planning, _, _} =
      accepted(
        pm_state,
        command("request_effect", %{"objective_id" => "objective-1"}, %{"role" => "pm"}),
        launch_inputs("pm")
      )

    {pm_after, _, _} =
      accepted(
        planning,
        command("record_receipt", %{"objective_id" => "objective-1"}, %{
          "role" => "pm",
          "outcome" => "non_started"
        }),
        receipt_inputs("pm", "non_started")
      )

    assert pm_after["pm"]["objective-1"]["owner_id"] == "objective-1"
    assert pm_after["pm"]["objective-1"]["status"] == "queued"
    assert pm_after["objectives"]["objective-1"]["planning_owner_id"] == "planner-1"
  end

  test "pause drain cancel and generation facts block launches without implicit refill" do
    queued = state_with(ticket("queued"))
    pause_input = inputs(%{"protected" => %{"control" => "committed"}})
    {paused, _, _} = accepted(queued, command("pause"), pause_input)

    assert {:ok, %{"disposition" => "blocked", "reason_code" => "paused"}} =
             Kernel.decide(
               paused,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
               launch_inputs("developer")
             )

    {draining, _, _} =
      accepted(queued, command("steer", %{}, %{"operation" => "drain"}), pause_input)

    assert {:ok, %{"disposition" => "blocked", "reason_code" => "draining"}} =
             Kernel.decide(
               draining,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
               launch_inputs("developer")
             )

    {cancelled, _, _} =
      accepted(queued, command("cancel", %{"ticket_id" => "ticket-1"}), inputs())

    assert {:ok, %{"disposition" => "blocked", "reason_code" => "cancel_requested"}} =
             Kernel.decide(
               cancelled,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
               launch_inputs("developer")
             )

    bindings_before = queued["tickets"]["ticket-1"]["authority_bindings"]

    assert {:error, :invalid_decision_inputs} =
             Kernel.decide(
               queued,
               command("steer", %{"ticket_id" => "ticket-1"}, %{
                 "operation" => "amend",
                 "spec" => %{"title" => "new", "scope" => []}
               }),
               inputs(%{
                 "ids" => %{"spec_revision_id" => "spec-2"},
                 "protected" => %{"ledger_balance" => 999}
               })
             )

    assert bindings_before == queued["tickets"]["ticket-1"]["authority_bindings"]
  end

  test "public block reaches blocked while terminal tickets refuse overwrite" do
    queued = state_with(ticket("queued"))

    {blocked, _, _} =
      accepted(
        queued,
        command("steer", %{"ticket_id" => "ticket-1"}, %{
          "operation" => "block",
          "reason" => "operator reason"
        }),
        inputs()
      )

    assert blocked["tickets"]["ticket-1"]["phase"] == "blocked"
    assert blocked["tickets"]["ticket-1"]["reason"] == "operator reason"

    integrated =
      state_with(
        ticket("integrated", %{"attempt" => attempt("terminal", %{"disposition" => "integrated"})})
      )

    assert {:ok, %{"disposition" => "rejected", "events" => []}} =
             Kernel.decide(
               integrated,
               command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "block"}),
               inputs()
             )
  end

  test "root facts are unforgeable by command payload or replay event" do
    forged_command =
      command("enqueue", %{"ticket_id" => "ticket-1", "objective_id" => "objective-1"}, %{
        "spec" => %{"title" => "T", "scope" => []},
        "root_facts" => %{"ledger_balance" => 999}
      })

    assert {:error, :invalid_domain_input} =
             Kernel.decide(Kernel.new(), forged_command, command_inputs("enqueue", 1))

    forged_event = %{
      "schema_version" => 1,
      "event_id" => "forged-event",
      "type" => "ticket_admitted",
      "recorded_at" => "2026-09-20T12:00:00Z",
      "changes" => [
        %{
          "kind" => "ticket",
          "id" => "ticket-1",
          "value" => Map.put(ticket("queued"), "root_facts", %{"accepted_ref" => "forged"})
        }
      ]
    }

    assert {:error, :invalid_domain_event} = Kernel.apply(Kernel.new(), forged_event)
  end

  test "missing explicit time IDs observation and protected settlement refuse" do
    base = inputs()

    for missing <- ~w(recorded_at event_id ids observation protected) do
      assert {:error, :invalid_decision_inputs} =
               Kernel.decide(Kernel.new(), command("pause"), Map.delete(base, missing))
    end

    assert {:ok, %{"disposition" => "rejected", "reason_code" => "missing_effect_identity"}} =
             Kernel.decide(
               state_with(ticket("queued")),
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
               inputs(%{
                 "observation" => %{"outcome" => "admitted"},
                 "protected" => %{"reservation" => "reserved"}
               })
             )

    assert {:ok, %{"disposition" => "rejected", "reason_code" => "receipt_not_root_verified"}} =
             Kernel.decide(
               launched_developer_state(),
               command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
                 "role" => "developer",
                 "outcome" => "unknown"
               }),
               receipt_inputs("developer", "unknown", %{
                 "protected" => %{"settlement" => "failed"}
               })
             )
  end

  test "complete accepted lifecycle has identical live and replay state" do
    {state, events, _} =
      accepted(
        Kernel.new(),
        command("enqueue", %{"ticket_id" => "ticket-1", "objective_id" => "objective-1"}, %{
          "spec" => %{"title" => "T", "scope" => ["lib/"]}
        }),
        command_inputs("enqueue", 101)
      )

    {state, more, _} =
      accepted(
        state,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer") |> Map.put("event_id", "event-102")
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "developer",
          "outcome" => "succeeded"
        }),
        receipt_inputs("developer", "succeeded") |> Map.put("event_id", "event-103")
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("submit_artifact", %{"ticket_id" => "ticket-1"}, %{"result" => "valid"}),
        inputs(%{
          "event_id" => "event-104",
          "ids" => %{"observation_id" => "observation-1", "candidate_id" => "candidate-1"},
          "protected" => %{"candidate" => "frozen", "candidate_id" => "candidate-1"}
        })
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "start_checks"}),
        inputs(%{"event_id" => "event-105", "protected" => %{"candidate_id" => "candidate-1"}})
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("steer", %{"ticket_id" => "ticket-1"}, %{
          "operation" => "check_result",
          "verdict" => "passed"
        }),
        inputs(%{
          "event_id" => "event-106",
          "protected" => %{"checks" => "complete", "check_set_id" => "checks-1"}
        })
      )

    events = events ++ more

    reviewer_launch =
      launch_inputs("reviewer")
      |> Map.put("event_id", "event-107")
      |> put_in(["protected", "candidate_id"], "candidate-1")
      |> put_in(["protected", "check_set_id"], "checks-1")

    {state, more, _} =
      accepted(
        state,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "reviewer"}),
        reviewer_launch
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "reviewer",
          "outcome" => "succeeded"
        }),
        receipt_inputs("reviewer", "succeeded") |> Map.put("event_id", "event-108")
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("submit_review", %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}),
        inputs(%{
          "event_id" => "event-109",
          "ids" => %{"review_id" => "review-1"},
          "protected" => %{"candidate_id" => "candidate-1", "review_id" => "review-1"}
        })
      )

    events = events ++ more

    {state, more, _} =
      accepted(
        state,
        command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "reviewer_closed"}),
        inputs(%{
          "event_id" => "event-110",
          "observation" => %{"termination" => "verified_closed"}
        })
      )

    events = events ++ more

    integration_launch =
      launch_inputs("integration")
      |> Map.put("event_id", "event-111")
      |> put_in(["ids", "execution_id"], "execution-integration")
      |> put_in(["ids", "effect_id"], "effect-integration")
      |> put_in(["ids", "reservation_id"], "reservation-integration")

    {state, more, _} =
      accepted(
        state,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "integration"}),
        integration_launch
      )

    events = events ++ more

    integration_receipt =
      receipt_inputs("integration", "succeeded", %{
        "event_id" => "event-112",
        "protected" => %{"ref_update" => "succeeded", "prior_workers" => "closed"}
      })

    {live, more, _} =
      accepted(
        state,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "integration",
          "outcome" => "succeeded"
        }),
        integration_receipt
      )

    events = events ++ more
    assert live["tickets"]["ticket-1"]["phase"] == "integrated"
    assert live["tickets"]["ticket-1"]["attempt"]["disposition"] == "integrated"
    assert {:ok, ^live} = Kernel.rebuild(events)
  end

  test "all receipt verdicts are explicit and root-bound" do
    for outcome <- ~w(succeeded failed non_started unknown) do
      state = launched_developer_state()

      input =
        receipt_inputs("developer", outcome) |> Map.put("event_id", "receipt-event-#{outcome}")

      assert {:ok, %{"disposition" => "accepted", "events" => [_event]}} =
               Kernel.decide(
                 state,
                 command(
                   "record_receipt",
                   %{"ticket_id" => "ticket-1"},
                   %{"role" => "developer", "outcome" => outcome},
                   "receipt-command-#{outcome}"
                 ),
                 input
               )
    end
  end

  test "R4a pre-intent denial and unknown preserve each scheduling owner" do
    reviewer =
      state_with(
        ticket("awaiting_review", %{
          "attempt" =>
            attempt("awaiting_review", %{
              "candidate_id" => "candidate-1",
              "check_set_id" => "checks-1"
            })
        })
      )

    assert {:ok, %{"disposition" => "blocked", "events" => []}} =
             Kernel.decide(
               reviewer,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "reviewer"}),
               launch_inputs("reviewer", "pre_intent_denied")
             )

    assert reviewer["tickets"]["ticket-1"]["attempt"]["candidate_id"] == "candidate-1"

    {reviewing, _, _} =
      accepted(
        reviewer,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "reviewer"}),
        launch_inputs("reviewer")
      )

    {unknown, _, _} =
      accepted(
        reviewing,
        command("record_receipt", %{"ticket_id" => "ticket-1"}, %{
          "role" => "reviewer",
          "outcome" => "unknown"
        }),
        receipt_inputs("reviewer", "unknown")
      )

    assert unknown["tickets"]["ticket-1"]["phase"] == "reviewing"
    assert unknown["tickets"]["ticket-1"]["attempt"]["candidate_id"] == "candidate-1"

    objective = %{
      "objective_id" => "objective-1",
      "phase" => "draft",
      "planning_owner_id" => "planner-1",
      "authority_bindings" => %{}
    }

    pm_state = put_in(Kernel.new(), ["objectives", "objective-1"], objective)

    assert {:ok, %{"disposition" => "blocked", "events" => []}} =
             Kernel.decide(
               pm_state,
               command("request_effect", %{"objective_id" => "objective-1"}, %{"role" => "pm"}),
               launch_inputs("pm", "pre_intent_denied")
             )

    assert pm_state["objectives"]["objective-1"]["planning_owner_id"] == "planner-1"
  end

  test "generation reset keeps the exhausted attempt terminal and does not copy balances" do
    old_attempt = attempt("terminal", %{"disposition" => "exhausted"})
    exhausted = state_with(ticket("exhausted", %{"attempt" => old_attempt}))

    {reset, events, _} =
      accepted(
        exhausted,
        command("reset", %{"ticket_id" => "ticket-1"}),
        inputs(%{
          "ids" => %{},
          "protected" => %{
            "generation_change" => "granted",
            "ledger_id" => "ledger-1",
            "ledger_generation" => 2
          }
        })
      )

    assert reset["tickets"]["ticket-1"]["phase"] == "queued"
    assert reset["tickets"]["ticket-1"]["attempt"] == nil
    assert reset["tickets"]["ticket-1"]["prior_attempts"] == [old_attempt]
    refute Map.has_key?(reset["tickets"]["ticket-1"]["authority_bindings"], "available")
    [event] = events
    refute inspect(event) =~ "authorized"
    refute inspect(event) =~ "available"
  end

  defp command_inputs("enqueue", index),
    do:
      inputs(%{
        "event_id" => "event-#{index}",
        "ids" => %{"spec_revision_id" => "spec-1"},
        "protected" => %{"admission" => "eligible"}
      })

  defp command_inputs("steer", index),
    do:
      inputs(%{
        "event_id" => "event-#{index}",
        "ids" => %{"planning_owner_id" => "planner-1"},
        "protected" => %{"pm_reservation" => "reserved", "developer_allocation" => "eligible"},
        "observation" => %{"termination" => "verified_closed"}
      })

  defp command_inputs(type, index) when type in ~w(pause resume),
    do: inputs(%{"event_id" => "event-#{index}", "protected" => %{"control" => "committed"}})

  defp command_inputs("reset", index),
    do:
      inputs(%{
        "event_id" => "event-#{index}",
        "ids" => %{"attempt_id" => "attempt-2"},
        "protected" => %{
          "generation_change" => "granted",
          "ledger_generation" => 4,
          "ledger_id" => "ledger-new"
        }
      })

  defp command_inputs("propose", index),
    do: inputs(%{"event_id" => "event-#{index}", "ids" => %{"proposal_id" => "proposal-1"}})

  defp command_inputs("submit_artifact", index),
    do: inputs(%{"event_id" => "event-#{index}", "ids" => %{"observation_id" => "observation-1"}})

  defp command_inputs("submit_review", index),
    do:
      inputs(%{
        "event_id" => "event-#{index}",
        "ids" => %{"review_id" => "review-1"},
        "protected" => %{"candidate_id" => "candidate-1"}
      })

  defp command_inputs("request_effect", _index), do: launch_inputs("developer")
  defp command_inputs("record_receipt", _index), do: receipt_inputs("developer", "unknown")
  defp command_inputs(_type, index), do: inputs(%{"event_id" => "event-#{index}"})

  defp launched_developer_state do
    queued = state_with(ticket("queued"))

    {launched, _events, _decision} =
      accepted(
        queued,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer")
      )

    launched
  end

  defp attempt_for_phase("developing"), do: attempt()

  defp attempt_for_phase("awaiting_review"),
    do: attempt("candidate_frozen", %{"candidate_id" => "candidate-1"})

  defp attempt_for_phase("reviewing"),
    do: attempt("reviewing", %{"candidate_id" => "candidate-1"})

  defp attempt_for_phase("ready_to_integrate"),
    do: attempt("ready_to_integrate", %{"candidate_id" => "candidate-1"})

  defp attempt_for_phase("integrating"),
    do: attempt("integrating", %{"candidate_id" => "candidate-1"})

  defp attempt_for_phase(phase) when phase in ~w(integrated rejected cancelled exhausted),
    do: attempt("terminal", %{"disposition" => phase})

  defp attempt_for_phase(_phase), do: nil

  # A synthetic replay prefix for the state produced by the public kernel. This helper
  # intentionally uses only semantic events, never a state snapshot or external read.
  defp events_to_state(_state) do
    enqueue_input = command_inputs("enqueue", 1)

    {:ok, enqueue_decision} =
      Kernel.decide(
        Kernel.new(),
        command("enqueue", %{"ticket_id" => "ticket-1", "objective_id" => "objective-1"}, %{
          "spec" => %{"title" => "Ticket", "scope" => []}
        }),
        enqueue_input
      )

    {:ok, queued} = Kernel.rebuild(enqueue_decision["events"])

    {:ok, launch_decision} =
      Kernel.decide(
        queued,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer")
      )

    enqueue_decision["events"] ++ launch_decision["events"]
  end
end
