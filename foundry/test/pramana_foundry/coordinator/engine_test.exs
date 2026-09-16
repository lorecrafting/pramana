Code.require_file("../../support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.EngineTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.AgentServerTest.FakeRunner

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit1 "1111222233334444555566667777888899990001"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  setup do
    previous = :sys.get_state(Coordinator)
    root = Path.join(System.tmp_dir!(), "audit-engine-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn current ->
        if current.tick_ref, do: Process.cancel_timer(current.tick_ref)
        previous
      end)

      File.rm_rf!(root)
    end)

    :ok = Coordinator.reset(accepted_revision: @base_rev)
    policy = FakeRunner.launch_policy()

    :sys.replace_state(Coordinator, fn data ->
      %{
        data
        | herdr_adapter: Adapter.new(FakeRunner),
          event_log_path: Path.join(root, "events.jsonl"),
          telemetry_path: Path.join(root, "telemetry.jsonl"),
          coordinator_log_path: Path.join(root, "coordinator.jsonl"),
          poll_ms: 3_600_000,
          launch_profiles: %{},
          launch_role_profiles: policy.role_profiles
      }
    end)

    :ok
  end

  test "two disjoint assignments are admitted and a handoff changes only its own assignment" do
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

    # One handoff must leave the other assignment dispatched.
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

    state = Coordinator.state()
    assert state["assignments"]["WF-TASK-1"]["status"] == "blocked"
    assert state["assignments"]["WF-TASK-1"]["blocked_role"] == "reviewer"
    assert state["assignments"]["WF-TASK-1"]["handoff"] == handoff1
    assert state["assignments"]["WF-TASK-2"]["status"] == "dispatched"
    assert state["accepted_revision"] == @base_rev
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

  test "pause and stop block an otherwise dispatchable queue without advancing revision" do
    assert :ok = Coordinator.enqueue_ticket(ticket("T-CONTROL"))
    assert {:ok, [_]} = Coordinator.plan_dispatch()

    assert :ok = Coordinator.pause()
    assert Coordinator.status()["paused"]
    assert {:ok, []} = Coordinator.plan_dispatch()
    assert :ok = Coordinator.resume()
    assert {:ok, [_]} = Coordinator.plan_dispatch()
    assert :ok = Coordinator.request_stop()
    assert Coordinator.status()["stop_requested"]
    assert {:ok, []} = Coordinator.plan_dispatch()
    assert Coordinator.state()["accepted_revision"] == @base_rev
  end

  test "queued tick and handoff complete in either mailbox order without losing the handoff" do
    for order <- [:tick_first, :handoff_first] do
      id = "T-#{order}"
      assert :ok = Coordinator.enqueue_ticket(ticket(id))
      assert {:ok, _} = Coordinator.admit_assignment(id, id <> "-run", "developer")
      handoff = handoff(id)
      pid = Process.whereis(Coordinator)
      :ok = :sys.suspend(pid)

      request =
        try do
          if order == :tick_first, do: send(pid, :tick)

          request =
            :gen_server.send_request(
              pid,
              {:receive_handoff, id, handoff, [skip_git_checks: true]}
            )

          if order == :handoff_first, do: send(pid, :tick)
          request
        after
          :ok = :sys.resume(pid)
        end

      assert {:reply, {:ok, _}} = :gen_server.wait_response(request, 2_000)
      state = Coordinator.state()
      assert state["assignments"][id]["status"] == "blocked"
      assert state["assignments"][id]["blocked_role"] == "reviewer"
      assert state["assignments"][id]["blocker"] =~ "automatic reviewer launch blocked"
      assert state["assignments"][id]["handoff"] == handoff
      assert state["accepted_revision"] == @base_rev

      %{event_log_path: log} = :sys.get_state(Coordinator)
      assert {:ok, events} = PramanaFoundry.Effects.Checkpoint.events(log)
      assert Enum.count(events, &(&1["task_id"] == id and &1["event"] == "handoff_received")) == 1
    end
  end

  defp ticket(id) do
    %{
      "task_id" => id,
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => "/tmp/test-checkout"
    }
  end

  defp handoff(id) do
    %{
      "schema_version" => 1,
      "task_id" => id,
      "run_id" => id <> "-run",
      "assigned_base" => @base_rev,
      "commit" => @commit1,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "done"
    }
  end
end
