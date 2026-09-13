Code.require_file("../support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.CoordinatorTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.AgentServerTest.FakeRunner

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit "2222333344445555666677778888999900001111"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  setup do
    :ok = Coordinator.reset(accepted_revision: @base_rev)
    install_launch_fixture()
    :ok
  end

  defp install_launch_fixture do
    policy = FakeRunner.launch_policy()

    :sys.replace_state(Coordinator, fn data ->
      %{
        data
        | herdr_adapter: Adapter.new(FakeRunner),
          launch_profiles: policy.profiles,
          launch_role_profiles: policy.role_profiles
      }
    end)
  end

  test "coordinator handles pause, resume, and request_stop" do
    assert Coordinator.status()["paused"] == false
    assert :ok = Coordinator.pause()
    assert Coordinator.status()["paused"] == true

    assert :ok = Coordinator.resume()
    assert Coordinator.status()["paused"] == false

    assert :ok = Coordinator.request_stop()
    assert Coordinator.status()["stop_requested"] == true
  end

  test "coordinator lifecycle: enqueue -> admit -> handoff -> review -> integrate" do
    ticket = %{
      "task_id" => "T-COORD-1",
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)
    assert "T-COORD-1" in Coordinator.state()["queue"]

    assert {:ok, _} = Coordinator.admit_assignment("T-COORD-1", "run-c-1", "developer")
    refute "T-COORD-1" in Coordinator.state()["queue"]
    assert Coordinator.state()["assignments"]["T-COORD-1"]["status"] == "dispatched"

    # Receive handoff
    handoff = %{
      "schema_version" => 1,
      "task_id" => "T-COORD-1",
      "run_id" => "run-c-1",
      "assigned_base" => @base_rev,
      "commit" => @commit,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "Implemented scheduler"
    }

    assert {:ok, _} = Coordinator.receive_handoff("T-COORD-1", handoff, skip_git_checks: true)
    assert Coordinator.state()["assignments"]["T-COORD-1"]["status"] == "handoff_received"

    # Receive approved review
    review = %{
      "schema_version" => 1,
      "run_id" => "run-c-1",
      "task_id" => "T-COORD-1",
      "commit" => @commit,
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => @check, "exit_code" => 0}]
    }

    assert {:ok, _} = Coordinator.receive_review("T-COORD-1", review, skip_git_checks: true)
    assert Coordinator.state()["assignments"]["T-COORD-1"]["status"] == "review_approved"

    # Mock runner that succeeds
    mock_runner = fn _cmd, _path -> {"ok", 0} end

    assert {:ok, promoted} =
             Coordinator.integrate("T-COORD-1", runner_fn: mock_runner, skip_git_checks: true)

    assert promoted["status"] == "integrated"
    assert Coordinator.state()["accepted_revision"] == @commit
  end

  test "reset_pm_attempts clears PM halt via Coordinator GenServer" do
    reset_payload = %{
      "authority" => "human",
      "issued_by" => "operator_coord",
      "issued_at" => "2026-09-10T01:00:00Z",
      "revision" => @base_rev
    }

    assert {:ok, record} = Coordinator.reset_pm_attempts(reset_payload)
    assert record["issued_by"] == "operator_coord"
    assert record["revision"] == @base_rev
  end

  test "review validation failure triggers retry budget instead of parking" do
    ticket = %{
      "task_id" => "T-REVIEW-RETRY-1",
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)
    assert {:ok, _} = Coordinator.admit_assignment("T-REVIEW-RETRY-1", "run-rr-1", "developer")

    handoff = %{
      "schema_version" => 1,
      "task_id" => "T-REVIEW-RETRY-1",
      "run_id" => "run-rr-1",
      "assigned_base" => @base_rev,
      "commit" => @commit,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "Implemented scheduler"
    }

    assert {:ok, _} = Coordinator.receive_handoff("T-REVIEW-RETRY-1", handoff, skip_git_checks: true)
    assert Coordinator.state()["assignments"]["T-REVIEW-RETRY-1"]["status"] == "handoff_received"

    # Submit a malformed review with mismatched run_id
    bad_review = %{
      "schema_version" => 1,
      "run_id" => "wrong-run-id",
      "task_id" => "T-REVIEW-RETRY-1",
      "commit" => @commit,
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => @check, "exit_code" => 0}]
    }

    assert {:error, _reason} = Coordinator.receive_review("T-REVIEW-RETRY-1", bad_review, skip_git_checks: true)

    # Verify retry: task returns to handoff_received, not parked
    state = Coordinator.state()
    assignment = state["assignments"]["T-REVIEW-RETRY-1"]
    assert assignment["status"] == "handoff_received"
    assert assignment["review_retries"] == 1
    assert String.contains?(assignment["error"], "invalid review (retry 1/3")
  end

  test "review retry budget exhaustion parks the task" do
    ticket = %{
      "task_id" => "T-REVIEW-RETRY-2",
      "base_revision" => @base_rev,
      "scope" => ["workflow/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)
    assert {:ok, _} = Coordinator.admit_assignment("T-REVIEW-RETRY-2", "run-rr-2", "developer")

    handoff = %{
      "schema_version" => 1,
      "task_id" => "T-REVIEW-RETRY-2",
      "run_id" => "run-rr-2",
      "assigned_base" => @base_rev,
      "commit" => @commit,
      "changed_files" => ["workflow/lib/pramana_foundry/scheduler.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => @check, "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "Implemented scheduler"
    }

    assert {:ok, _} = Coordinator.receive_handoff("T-REVIEW-RETRY-2", handoff, skip_git_checks: true)

    bad_review = %{
      "schema_version" => 1,
      "run_id" => "wrong-run-id",
      "task_id" => "T-REVIEW-RETRY-2",
      "commit" => @commit,
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => @check, "exit_code" => 0}]
    }

    # Exhaust retry budget with low max_review_retries
    opts = [skip_git_checks: true, max_review_retries: 1]

    # First malformed review → retry (#1/2, under limit)
    assert {:error, _} = Coordinator.receive_review("T-REVIEW-RETRY-2", bad_review, opts)
    assert Coordinator.state()["assignments"]["T-REVIEW-RETRY-2"]["status"] == "handoff_received"
    assert Coordinator.state()["assignments"]["T-REVIEW-RETRY-2"]["review_retries"] == 1

    # Second malformed review → retry #2/2 → now exceeds limit → parked
    assert {:error, _} = Coordinator.receive_review("T-REVIEW-RETRY-2", bad_review, opts)
    assignment = Coordinator.state()["assignments"]["T-REVIEW-RETRY-2"]
    assert assignment["status"] == "parked"
    assert assignment["review_retries"] == 2
    assert String.contains?(assignment["blocker"], "invalid review artifact (retries exhausted)")
  end
end
