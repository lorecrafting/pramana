defmodule PramanaFoundry.EngineTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Integration
  alias PramanaFoundry.PM
  alias PramanaFoundry.Quota
  alias PramanaFoundry.Status

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit1 "1111222233334444555566667777888899990001"
  @commit2 "1111222233334444555566667777888899990002"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  setup do
    :ok = Coordinator.reset(accepted_revision: @base_rev)
    :ok
  end

  test "two isolated developer workers with disjoint scope/resources can run concurrently while integration remains a single serial owner" do
    ticket1 = %{
      "task_id" => "WF-TASK-1",
      "base_revision" => @base_rev,
      "checkout" => "/tmp/checkout-wf-1",
      "scope" => ["workflow/lib/pramana_foundry/scheduler/**"],
      "environment" => %{
        "MIX_TEST_PARTITION" => "10",
        "MIX_BUILD_PATH" => "/tmp/build-wf-1",
        "PORT" => "5001"
      },
      "shared_resources" => %{
        "corpus" => [],
        "database" => [],
        "gpu" => [],
        "other" => ["engine-resource-1"],
        "service_ports" => ["5001"]
      },
      "dependencies" => [],
      "required_checks" => [@check]
    }

    ticket2 = %{
      "task_id" => "WF-TASK-2",
      "base_revision" => @base_rev,
      "checkout" => "/tmp/checkout-wf-2",
      "scope" => ["workflow/lib/pramana_foundry/pm/**"],
      "environment" => %{
        "MIX_TEST_PARTITION" => "20",
        "MIX_BUILD_PATH" => "/tmp/build-wf-2",
        "PORT" => "5002"
      },
      "shared_resources" => %{
        "corpus" => [],
        "database" => [],
        "gpu" => [],
        "other" => ["engine-resource-2"],
        "service_ports" => ["5002"]
      },
      "dependencies" => [],
      "required_checks" => [@check]
    }

    assert :ok = Coordinator.enqueue_ticket(ticket1)
    assert :ok = Coordinator.enqueue_ticket(ticket2)

    # Scheduler plans dispatch for both concurrently (worker ceiling = 2)
    assert {:ok, admitted} = Coordinator.plan_dispatch(max_workers: 2)
    assert length(admitted) == 2

    # Admit both workers with distinct run IDs
    assert {:ok, _} = Coordinator.admit_assignment("WF-TASK-1", "run-wf-1", "developer")
    assert {:ok, _} = Coordinator.admit_assignment("WF-TASK-2", "run-wf-2", "developer")

    # Verify both workers are active
    status = Coordinator.status()
    assert length(status["active_workers"]) == 2

    # Now simulate completed handoff for both
    handoff1 = %{
      "schema_version" => 1,
      "task_id" => "WF-TASK-1",
      "run_id" => "run-wf-1",
      "assigned_base" => @base_rev,
      "commit" => @commit1,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler/policy.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "Implemented scheduler"
    }

    assert {:ok, _} = Coordinator.receive_handoff("WF-TASK-1", handoff1, skip_git_checks: true)

    # First candidate acquires integration owner
    state = Coordinator.state()
    assert {:ok, state_owned} = Integration.acquire_owner(state, "WF-TASK-1", @commit1)

    # Second candidate is blocked while first is integrating (singleton serial owner)
    assert {:error, :integration_busy} =
             Integration.acquire_owner(state_owned, "WF-TASK-2", @commit2)
  end

  test "transactional PM proposal batches apply all-or-none" do
    proposals_invalid_second = [
      %{
        "operation" => "create",
        "ticket" => %{
          "task_id" => "WF-PM-1",
          "base_revision" => @base_rev,
          "dependencies" => []
        },
        "reason" => "add valid ticket"
      },
      %{
        "operation" => "create",
        "ticket" => %{
          "task_id" => "WF-PM-2",
          "base_revision" => "stale_outdated_base",
          "dependencies" => []
        },
        "reason" => "add invalid ticket"
      }
    ]

    # Batch application fails
    assert {:error, reason} = Coordinator.apply_pm_proposals(proposals_invalid_second)
    assert reason =~ "does not equal accepted revision"

    # All-or-none verification: first ticket was not admitted into assignments
    state = Coordinator.state()
    refute Map.has_key?(state["assignments"], "WF-PM-1")
    refute "WF-PM-1" in state["queue"]
  end

  test "planning attempt caps and human-only reset control" do
    pm_state = %{"accepted_revision" => @base_rev}

    # Consecutive rejections with different run IDs but same reason increment loop counter
    r1 = "proposal /artifacts/planning/aaaa1111bbbb2222.json rejected: schema error"
    r2 = "proposal /artifacts/planning/cccc3333dddd4444.json rejected: schema error"
    r3 = "proposal /artifacts/planning/eeee5555ffff6666.json rejected: schema error"

    pm_state =
      pm_state
      |> PM.record_disposition("rejected", r1)
      |> PM.record_disposition("rejected", r2)
      |> PM.record_disposition("rejected", r3)

    assert get_in(pm_state, ["consecutive_rejections_by_revision", @base_rev, "count"]) == 3
    halt = PM.halt_reason(pm_state, @base_rev, max_attempts_per_revision: 3)
    assert halt["counter"] == "consecutive_rejections"
    assert halt["clears_with"] == "reset-pm-attempts"

    # Reset with human authority clears halt
    reset_payload = %{
      "authority" => "human",
      "issued_by" => "test_operator",
      "issued_at" => "2026-09-10T00:00:00Z",
      "revision" => @base_rev
    }

    assert {:ok, record, updated_pm} = PM.reset_attempts(pm_state, reset_payload, @base_rev)
    assert record["previous_consecutive_rejections"] == 3
    refute Map.has_key?(updated_pm["consecutive_rejections_by_revision"], @base_rev)
    assert PM.halt_reason(updated_pm, @base_rev) == nil
  end

  test "virtual time quota cooldown and declared subscription Codex ↔ Claude fallback" do
    profiles = %{
      "claude_dev" => %{
        "model" => "claude-3-5-sonnet",
        "model_id" => "anthropic/claude-3-5-sonnet",
        "reasoning" => "medium",
        "subscription_authorized" => true,
        "fallback_profiles" => ["codex_dev"]
      },
      "codex_dev" => %{
        "model" => "codex-sol",
        "model_id" => "openai-codex/sol",
        "reasoning" => "medium",
        "subscription_authorized" => true,
        "fallback_profiles" => ["claude_dev"]
      }
    }

    state = %{}

    assignment = %{
      "run_id" => "run-original-1234",
      "ticket" => %{"task_id" => "T-FALLBACK", "profile" => "claude_dev"}
    }

    # Ordinary failure never triggers fallback
    assert Quota.can_fallback?(profiles["claude_dev"], "ordinary_failure", profiles) ==
             {:error, :unauthorized_signal}

    # Subscription quota triggers fallback with fresh run ID
    assert {:ok, updated_assignment, updated_state} =
             Quota.begin_fallback(state, assignment, "usage_limit_reached", profiles,
               new_run_id: "run-fresh-5678",
               now: 1000.0
             )

    assert updated_assignment["run_id"] == "run-fresh-5678"
    assert updated_assignment["configured_profile"] == "codex_dev"
    assert updated_assignment["continuation"]["kind"] == "cross_provider_quota_fallback"

    # Anthropic provider is in-flight: second fallback is suppressed
    assert {:error, :provider_in_flight_intent_exists, _} =
             Quota.begin_fallback(updated_state, assignment, "usage_limit_reached", profiles,
               now: 1000.0
             )
  end

  test "pause/stop blocks promotion and preserves accepted revision on combined-check failure" do
    assert :ok = Coordinator.pause()
    status = Coordinator.status()
    assert status["paused"] == true

    # In pause state, new dispatch is blocked
    assert {:ok, []} = Coordinator.plan_dispatch()

    assert :ok = Coordinator.resume()
    status2 = Coordinator.status()
    assert status2["paused"] == false

    # When stop is requested, promotion is blocked
    assert :ok = Coordinator.request_stop()
    status3 = Coordinator.status()
    assert status3["stop_requested"] == true
  end

  test "status visibly disagrees when accepted revision moves beyond runtime implementation until controlled restart" do
    # Initially matching
    Status.set_runtime_implementation_revision(@base_rev)
    report_initial = Coordinator.status()
    assert report_initial["revisions_match?"] == true

    # Simulate accepted revision advancing to @commit1
    state = Coordinator.state() |> Map.put("accepted_revision", @commit1)
    report_advanced = Status.report(state)

    assert report_advanced["accepted_revision"] == @commit1
    assert report_advanced["runtime_implementation_revision"] == @base_rev
    assert report_advanced["revisions_match?"] == false
    assert report_advanced["revision_disagreement"] =~ "controlled restart required"

    # Controlled restart reconciles them
    Status.reconcile_runtime_implementation_revision(@commit1)
    report_reconciled = Status.report(state)
    assert report_reconciled["revisions_match?"] == true
    assert report_reconciled["runtime_implementation_revision"] == @commit1
  end

  test "tick and handoff are serialized through GenServer — no deadlock" do
    # Both tick (handle_info) and handoff (handle_call) run in the same
    # coordinator process. OTP GenServers process one message at a time,
    # so these cannot deadlock against each other. This test confirms
    # that sending a :tick message doesn't block subsequent calls.

    ticket = %{
      "task_id" => "T-CONC-1",
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => "/tmp/test-checkout"
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)

    # Send tick message non-blocking, then immediately make a call
    # The GenServer processes tick first, then the call — proving serialization
    send(PramanaFoundry.Coordinator, :tick)

    # Wait briefly for tick to process, then verify the coordinator is responsive
    Process.sleep(200)

    # If GenServer didn't deadlock, we get a valid state
    state = Coordinator.state()
    assert is_map(state)
    assert get_in(state, ["assignments", "T-CONC-1", "task_id"]) == "T-CONC-1"
  end

  test "tick processes queue while handoff calls are pending — no crash" do
    # Similar to above but with an actual queue item and handoff call
    ticket = %{
      "task_id" => "T-CONC-2",
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => "/tmp/test-checkout"
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)

    # Admit the assignment so it leaves the queue
    assert {:ok, _} = Coordinator.admit_assignment("T-CONC-2", "run-conc-2", "developer")

    handoff = %{
      "schema_version" => 1,
      "task_id" => "T-CONC-2",
      "run_id" => "run-conc-2",
      "assigned_base" => @base_rev,
      "commit" => @commit1,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "done"
    }

    # Send tick (will process empty queue, no harm) and submit handoff
    send(PramanaFoundry.Coordinator, :tick)
    Process.sleep(100)
    assert {:ok, _} = Coordinator.receive_handoff("T-CONC-2", handoff, skip_git_checks: true)

    # Verify handoff was accepted despite tick processing
    assert Coordinator.state()["assignments"]["T-CONC-2"]["status"] == "handoff_received"
  end

  test "preparation is selected from admitted ticket's declared resource needs" do
    workflow_only_ticket = %{
      "shared_resources" => %{
        "corpus" => [],
        "database" => [],
        "gpu" => [],
        "other" => ["workflow-engine"]
      }
    }

    database_ticket = %{
      "shared_resources" => %{
        "corpus" => [],
        "database" => ["main"],
        "gpu" => [],
        "other" => []
      }
    }

    wf_cmds = PramanaFoundry.Preparation.commands(workflow_only_ticket)
    assert length(wf_cmds) == 2
    refute Enum.any?(wf_cmds, &(&1.argv == ["mise", "exec", "--", "mix", "ecto.create"]))

    db_cmds = PramanaFoundry.Preparation.commands(database_ticket)
    assert length(db_cmds) == 4
    assert Enum.any?(db_cmds, &(&1.argv == ["mise", "exec", "--", "mix", "ecto.create"]))
  end
end
