ExUnit.start(seed: 92_041)

defmodule Fr08bPureKernelReviewProbes do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Workflow.Kernel
  alias PramanaFoundry.Workflow.Kernel.State

  defp command(type, targets \\ %{}, payload \\ %{}, id \\ "command-1") do
    %{
      "schema_version" => 1,
      "command_id" => id,
      "type" => type,
      "target_ids" => targets,
      "payload" => payload
    }
  end

  defp inputs(overrides) do
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

  defp ticket(phase, extra \\ %{}) do
    Map.merge(
      %{
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
      },
      extra
    )
  end

  defp attempt(phase \\ "active", extra \\ %{}) do
    Map.merge(
      %{
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
      },
      extra
    )
  end

  defp state_with(ticket), do: put_in(Kernel.new(), ["tickets", "ticket-1"], ticket)

  defp accepted(state, command, input) do
    assert {:ok, %{"disposition" => "accepted", "events" => events}} =
             Kernel.decide(state, command, input)

    Enum.reduce(events, state, fn event, acc ->
      assert {:ok, next} = Kernel.apply(acc, event)
      next
    end)
  end

  defp launch_inputs(role, ids \\ %{}) do
    inputs(%{
      "ids" =>
        Map.merge(
          %{
            "attempt_id" => "attempt-1",
            "execution_id" => "execution-#{role}",
            "effect_id" => "effect-#{role}",
            "reservation_id" => "reservation-#{role}"
          },
          ids
        ),
      "observation" => %{"outcome" => "admitted"},
      "protected" => %{
        "reservation" => "reserved",
        "policy_id" => "policy-1",
        "policy_revision" => 1
      }
    })
  end

  defp receipt_inputs(role, outcome, protected \\ %{}) do
    inputs(%{
      "ids" => %{
        "execution_id" => "execution-#{role}",
        "claim_id" => "claim-#{role}",
        "receipt_id" => "receipt-#{role}"
      },
      "protected" =>
        Map.merge(
          %{
            "settlement" => outcome,
            "allocation" => "eligible",
            "infrastructure_generation" => 1,
            "infrastructure_ordinal" => 1,
            "infrastructure_limit" => 3,
            "predecessor_effect_id" => "effect-prior",
            "failure_class" => "launcher_refused"
          },
          protected
        )
    })
  end

  defp event_for_ticket(id, value) do
    %{
      "schema_version" => 1,
      "event_id" => id,
      "type" => "ticket_state",
      "recorded_at" => "2026-09-20T12:00:00Z",
      "changes" => [%{"kind" => "ticket", "id" => "ticket-1", "value" => value}]
    }
  end

  test "unknown replay event creates an integrated ticket from empty state" do
    forged =
      event_for_ticket(
        "forged-event",
        %{"ticket_id" => "ticket-1", "phase" => "integrated"}
      )
      |> Map.put("type", "not_a_supported_event")

    assert {:ok, state} = Kernel.apply(Kernel.new(), forged)
    assert state["tickets"]["ticket-1"]["phase"] == "integrated"
  end

  test "out-of-order replay overwrites a newer lifecycle state" do
    queued = ticket("queued")
    developing = ticket("developing", %{"attempt" => attempt()})
    older = event_for_ticket("old", queued)
    newer = event_for_ticket("new", developing)

    assert {:ok, state} = Kernel.rebuild([older, newer, older])
    assert state["tickets"]["ticket-1"]["phase"] == "queued"
    assert state["last_event_id"] == "old"
  end

  test "top-level validation admits malformed nested state and decide raises" do
    malformed = put_in(Kernel.new(), ["tickets", "ticket-1"], 7)
    assert State.valid?(malformed)

    assert_raise FunctionClauseError, fn ->
      Kernel.decide(
        malformed,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer")
      )
    end
  end

  test "state validation permits additional protected-looking top-level facts" do
    state = Map.put(Kernel.new(), "ledger_balance", 999)
    assert State.valid?(state)

    assert {:ok, %{"disposition" => "accepted"}} =
             Kernel.decide(
               state,
               command("pause"),
               inputs(%{"protected" => %{"control" => "committed"}})
             )
  end

  test "checks start without verified developer close and leave no schedulable check path" do
    frozen =
      state_with(
        ticket("awaiting_review", %{
          "attempt" => attempt("candidate_frozen", %{"candidate_id" => "candidate-1"})
        })
      )

    checking =
      accepted(
        frozen,
        command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "start_checks"}),
        inputs(%{"protected" => %{"candidate_id" => "candidate-1"}})
      )

    assert checking["tickets"]["ticket-1"]["attempt"]["phase"] == "checking"

    assert {:ok, %{"disposition" => "rejected", "reason_code" => "source_state_guard"}} =
             Kernel.decide(
               checking,
               command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "check"}),
               launch_inputs("check")
             )
  end

  test "review approval and close need neither launch settlement nor protected close fact" do
    awaiting =
      state_with(
        ticket("awaiting_review", %{
          "attempt" =>
            attempt("awaiting_review", %{
              "candidate_id" => "candidate-1",
              "check_set_id" => "checks-1"
            })
        })
      )

    reviewing =
      accepted(
        awaiting,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "reviewer"}),
        launch_inputs("reviewer")
      )

    approved =
      accepted(
        reviewing,
        command("submit_review", %{"ticket_id" => "ticket-1"}, %{"verdict" => "approved"}),
        inputs(%{
          "ids" => %{"review_id" => "review-1"},
          "protected" => %{"candidate_id" => "candidate-1"}
        })
      )

    ready =
      accepted(
        approved,
        command("steer", %{"ticket_id" => "ticket-1"}, %{"operation" => "reviewer_closed"}),
        inputs(%{"observation" => %{"termination" => "verified_closed"}})
      )

    reviewer =
      ready["tickets"]["ticket-1"]["attempt"]["executions"]["execution-reviewer"]

    assert ready["tickets"]["ticket-1"]["phase"] == "ready_to_integrate"
    assert reviewer["status"] == "pending"
  end

  test "developer non-start ignores a drain committed after launch" do
    launched =
      state_with(ticket("queued"))
      |> accepted(
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer")
      )

    draining =
      accepted(
        launched,
        command("steer", %{}, %{"operation" => "drain"}),
        inputs(%{"event_id" => "drain", "protected" => %{"control" => "committed"}})
      )

    next =
      accepted(
        draining,
        command(
          "record_receipt",
          %{"ticket_id" => "ticket-1"},
          %{"role" => "developer", "outcome" => "non_started"}
        ),
        receipt_inputs("developer", "non_started")
      )

    assert next["control"]["draining"]
    assert next["tickets"]["ticket-1"]["phase"] == "queued"
  end

  test "PM non-start ignores exhausted allocation" do
    objective = %{
      "objective_id" => "objective-1",
      "phase" => "draft",
      "planning_owner_id" => "planner-1",
      "authority_bindings" => %{}
    }

    state = put_in(Kernel.new(), ["objectives", "objective-1"], objective)

    launched =
      accepted(
        state,
        command("request_effect", %{"objective_id" => "objective-1"}, %{"role" => "pm"}),
        launch_inputs("pm")
      )

    next =
      accepted(
        launched,
        command(
          "record_receipt",
          %{"objective_id" => "objective-1"},
          %{"role" => "pm", "outcome" => "non_started"}
        ),
        receipt_inputs("pm", "non_started", %{"allocation" => "exhausted"})
      )

    assert next["pm"]["objective-1"]["status"] == "queued"
  end

  test "correction queues before reviewer close and fresh launch loses terminal predecessor" do
    pending_reviewer = %{
      "execution-reviewer" => %{
        "execution_id" => "execution-reviewer",
        "effect_id" => "effect-reviewer",
        "reservation_id" => "reservation-reviewer",
        "role" => "reviewer",
        "owner_id" => "ticket-1",
        "attempt_id" => "attempt-1",
        "status" => "pending",
        "result" => nil,
        "recorded_at" => "2026-09-20T12:00:00Z",
        "authority_bindings" => %{}
      }
    }

    reviewing =
      state_with(
        ticket("reviewing", %{
          "attempt" =>
            attempt("reviewing", %{
              "candidate_id" => "candidate-1",
              "executions" => pending_reviewer
            })
        })
      )

    corrected =
      accepted(
        reviewing,
        command(
          "submit_review",
          %{"ticket_id" => "ticket-1"},
          %{"verdict" => "changes_requested"}
        ),
        inputs(%{
          "ids" => %{"review_id" => "review-1"},
          "protected" => %{"candidate_id" => "candidate-1", "draining" => false}
        })
      )

    assert corrected["tickets"]["ticket-1"]["phase"] == "queued"

    fresh =
      accepted(
        corrected,
        command("request_effect", %{"ticket_id" => "ticket-1"}, %{"role" => "developer"}),
        launch_inputs("developer", %{"attempt_id" => "attempt-2"})
      )

    assert fresh["tickets"]["ticket-1"]["attempt"]["attempt_id"] == "attempt-2"
    assert fresh["tickets"]["ticket-1"]["prior_attempts"] == []
    refute get_in(fresh, ["tickets", "ticket-1", "attempt", "executions", "execution-reviewer"])
  end

  test "unprotected public block overwrites an integrating attempt" do
    state =
      state_with(
        ticket("integrating", %{
          "attempt" => attempt("integrating", %{"candidate_id" => "candidate-1"})
        })
      )

    next =
      accepted(
        state,
        command("steer", %{"ticket_id" => "ticket-1"}, %{
          "operation" => "block",
          "reason" => "public"
        }),
        inputs(%{})
      )

    assert next["tickets"]["ticket-1"]["phase"] == "blocked"
    assert next["tickets"]["ticket-1"]["attempt"]["disposition"] == "blocked"
  end

  test "integrated atomic command shape is rejected because expected_revisions is extra" do
    canonical = command("pause") |> Map.put("expected_revisions", %{})

    assert {:error, :invalid_command} =
             Kernel.decide(
               Kernel.new(),
               canonical,
               inputs(%{"protected" => %{"control" => "committed"}})
             )
  end
end
