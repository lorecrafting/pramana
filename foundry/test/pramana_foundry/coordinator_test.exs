Code.require_file("../support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.CoordinatorTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Coordinator.Tick
  alias PramanaFoundry.{Cleanup, Transition}
  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.AgentServerTest.FakeRunner

  @base_rev "d83f8f0cedc34780d25cba452545ce9883d416a5"
  @commit "2222333344445555666677778888999900001111"
  @check ["sh", "-c", "cd workflow && exec mise exec -- mix test"]

  setup do
    previous = :sys.get_state(Coordinator)
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    root = Path.join(System.tmp_dir!(), "audit-coordinator-#{suffix}")
    File.mkdir!(root)

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn current ->
        if current.tick_ref, do: Process.cancel_timer(current.tick_ref)
        %{previous | tick_ref: nil}
      end)

      File.rm_rf!(root)
    end)

    :sys.replace_state(Coordinator, fn data ->
      if data.tick_ref, do: Process.cancel_timer(data.tick_ref)

      %{
        data
        | checkpoint_append_fn: &Checkpoint.append/6,
          recovery_error: nil,
          tick_ref: nil,
          event_log_path: Path.join(root, "events.jsonl"),
          telemetry_path: Path.join(root, "telemetry.jsonl"),
          coordinator_log_path: Path.join(root, "coordinator.jsonl")
      }
    end)

    :ok = Coordinator.reset(accepted_revision: @base_rev)
    install_launch_fixture()
    %{fixture_root: root}
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

  test "unresolved cleanup receipt is durably appended before completion is acknowledged" do
    ticket = %{
      "task_id" => "T-CLEANUP-UNRESOLVED",
      "base_revision" => @base_rev,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)

    assert {:ok, _} =
             Coordinator.admit_assignment(
               "T-CLEANUP-UNRESOLVED",
               "run-cleanup-unresolved",
               "developer"
             )

    cleanup = cleanup_attributes("T-CLEANUP-UNRESOLVED", "run-cleanup-unresolved")
    register_cleanup_resource(cleanup)

    assert :ok = Coordinator.record_cleanup(:pending, cleanup)

    assert :ok =
             Coordinator.record_cleanup(
               :result,
               Map.merge(cleanup, %{"status" => "unresolved", "reason" => ":session_mismatch"})
             )

    slot_owner = self()

    :sys.replace_state(Coordinator, fn data ->
      %{data | agent_registry: Map.put(data.agent_registry, "T-CLEANUP-UNRESOLVED", slot_owner)}
    end)

    send(
      Coordinator,
      {:agent_completed, "T-CLEANUP-UNRESOLVED", "run-cleanup-unresolved", :timeout,
       %{
         pane_id: "pane-preserved",
         cleanup: %{status: :unresolved, reason: :session_mismatch}
       }}
    )

    Process.monitor(Process.whereis(Coordinator))

    assert Coordinator.state()["assignments"]["T-CLEANUP-UNRESOLVED"]["status"] ==
             "cleanup_blocked"

    assert Coordinator.state()["assignments"]["T-CLEANUP-UNRESOLVED"]["work_status"] ==
             "completed"

    assert Coordinator.agent_pid("T-CLEANUP-UNRESOLVED") == slot_owner
    refute "T-CLEANUP-UNRESOLVED" in Coordinator.state()["queue"]

    event_log_path = :sys.get_state(Coordinator).event_log_path
    assert {:ok, records} = Checkpoint.events(event_log_path)

    assert Enum.any?(records, fn record ->
             record["event"] == "cleanup_pending" and
               record["attributes"]["pane_id"] == "pane-preserved"
           end)

    assert Enum.any?(records, fn record ->
             record["event"] == "cleanup_result" and
               record["attributes"]["status"] == "unresolved"
           end)
  end

  test "cleanup pending append failure enters recovery without an in-memory obligation" do
    ticket = %{
      "task_id" => "T-CLEANUP-APPEND-FAIL",
      "base_revision" => @base_rev,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)

    assert {:ok, _} =
             Coordinator.admit_assignment("T-CLEANUP-APPEND-FAIL", "run-fail", "developer")

    register_cleanup_resource(cleanup_attributes("T-CLEANUP-APPEND-FAIL", "run-fail"))

    original_append_fn = :sys.get_state(Coordinator).checkpoint_append_fn

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn data ->
        %{data | checkpoint_append_fn: original_append_fn, recovery_error: nil}
      end)
    end)

    :sys.replace_state(Coordinator, fn data ->
      Map.put(data, :checkpoint_append_fn, fn _path, _event, _task, _run, _role, _attrs ->
        {:error, :injected_append_failure}
      end)
    end)

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.record_cleanup(
               :pending,
               cleanup_attributes("T-CLEANUP-APPEND-FAIL", "run-fail")
             )

    state = Coordinator.state()
    assert state["status"] == "recovery_required"
    assert get_in(state, ["assignments", "T-CLEANUP-APPEND-FAIL", "cleanup_outstanding"])
  end

  test "startup read-back retains unresolved cleanup assignment while FR-03 reconciliation stays suspended" do
    fixture_root =
      Path.join(
        System.tmp_dir!(),
        "fr04-replay-#{System.unique_integer([:positive, :monotonic])}"
      )

    event_log_path = Path.join(fixture_root, "events.jsonl")
    File.mkdir_p!(fixture_root)

    on_exit(fn -> File.rm_rf!(fixture_root) end)

    assert {:ok, _} =
             Checkpoint.append(
               event_log_path,
               "assignment_admitted",
               "T-CLEANUP-REPLAY",
               "run-replay",
               "developer",
               %{}
             )

    cleanup = cleanup_attributes("T-CLEANUP-REPLAY", "run-replay")

    assert {:ok, _} =
             Checkpoint.append(
               event_log_path,
               "pane_created",
               "T-CLEANUP-REPLAY",
               "run-replay",
               "developer",
               pane_created_attributes(cleanup)
             )

    assert {:ok, _} =
             Checkpoint.append(
               event_log_path,
               "cleanup_pending",
               "T-CLEANUP-REPLAY",
               "run-replay",
               "developer",
               cleanup
             )

    assert {:ok, _} =
             Checkpoint.append(
               event_log_path,
               "cleanup_result",
               "T-CLEANUP-REPLAY",
               "run-replay",
               "developer",
               Map.merge(cleanup, %{"status" => "unresolved", "reason" => ":replacement"})
             )

    assert {:ok, data} =
             Coordinator.init(
               event_log_path: event_log_path,
               telemetry_log_path: Path.join(fixture_root, "telemetry.jsonl"),
               coordinator_log_path: Path.join(fixture_root, "coordinator.jsonl"),
               enable_tick: false
             )

    assignment = data.state["assignments"]["T-CLEANUP-REPLAY"]
    assert data.state["status"] == "recovery_required"
    assert assignment["status"] == "cleanup_blocked"
    assert assignment["cleanup_outstanding"] == true

    assert assignment["cleanup_obligations"]["developer:run-replay"]["pane_id"] ==
             "pane-preserved"
  end

  test "unresolved launch failure and crash retain capacity without ordinary retry" do
    for {task_id, run_id, lifecycle} <- [
          {"T-CLEANUP-LAUNCH-BLOCK", "run-launch-block", :launch},
          {"T-CLEANUP-CRASH-BLOCK", "run-crash-block", :crash}
        ] do
      ticket = %{
        "task_id" => task_id,
        "base_revision" => @base_rev,
        "scope" => ["foundry/lib/**"],
        "exclusions" => [],
        "required_checks" => [@check],
        "review_required_checks" => [@check],
        "checkout" => nil
      }

      assert :ok = Coordinator.enqueue_ticket(ticket)
      assert {:ok, _} = Coordinator.admit_assignment(task_id, run_id, "developer")
      cleanup = cleanup_attributes(task_id, run_id)
      register_cleanup_resource(cleanup)
      assert :ok = Coordinator.record_cleanup(:pending, cleanup)

      assert :ok =
               Coordinator.record_cleanup(
                 :result,
                 Map.merge(cleanup, %{"status" => "unresolved", "reason" => ":replacement"})
               )

      slot_owner = self()

      :sys.replace_state(Coordinator, fn data ->
        %{data | agent_registry: Map.put(data.agent_registry, task_id, slot_owner)}
      end)

      case lifecycle do
        :launch ->
          send(
            Coordinator,
            {:agent_launched, task_id, {:error, :agent_start_failed, :timeout},
             %{cleanup: %{status: :unresolved, reason: :replacement}}}
          )

        :crash ->
          send(
            Coordinator,
            {:agent_crashed, task_id, run_id, :boom,
             %{pane_id: "pane-preserved", cleanup: %{status: :unresolved, reason: :replacement}}}
          )
      end

      state = Coordinator.state()
      assignment = state["assignments"][task_id]
      assert assignment["status"] == "cleanup_blocked"
      assert Coordinator.agent_pid(task_id) == slot_owner
      refute task_id in state["queue"]
    end

    assert Coordinator.state()["assignments"]["T-CLEANUP-LAUNCH-BLOCK"]["launch_retries"] == nil
    assert Coordinator.state()["assignments"]["T-CLEANUP-CRASH-BLOCK"]["work_retries"] == nil
  end

  test "actual Tick admission suspends a competing ticket while cleanup retains capacity" do
    event_path =
      Path.join(
        System.tmp_dir!(),
        "fr04-no-admission-#{System.unique_integer([:positive])}.jsonl"
      )

    state = %{
      "assignments" => %{
        "T-BLOCKED" => %{"status" => "cleanup_blocked", "cleanup_outstanding" => true},
        "T-COMPETING" => %{"status" => "queued", "ticket" => %{"checkout" => "/tmp/none"}}
      },
      "queue" => ["T-BLOCKED", "T-COMPETING"]
    }

    {next_state, registry, log} =
      Tick.process_queue(
        state["queue"],
        state,
        %{},
        nil,
        100,
        self(),
        event_path
      )

    assert next_state["queue"] == ["T-COMPETING"]
    assert next_state["assignments"]["T-COMPETING"]["status"] == "queued"
    assert registry == %{}
    assert log == [{:admission_suspended, :cleanup_outstanding}]
    refute File.exists?(event_path)
  end

  test "unverified developer fences a later closed reviewer through gateway and replay" do
    assert_sibling_cleanup_fence(:developer_first, "T-CLEANUP-SIBLING-DEV-FIRST")
  end

  test "unverified developer fences an earlier closed reviewer through gateway and replay" do
    assert_sibling_cleanup_fence(:reviewer_first, "T-CLEANUP-SIBLING-REVIEW-FIRST")
  end

  test "Coordinator handles cleanup admission suspension as an ordinary tick", %{
    fixture_root: parent
  } do
    fixture_root = Path.join(parent, "suspension")

    log_path = Path.join(fixture_root, "coordinator.jsonl")
    event_path = Path.join(fixture_root, "events.jsonl")
    caller = self()

    on_exit(fn -> File.rm_rf!(fixture_root) end)

    state = %{
      "assignments" => %{
        "T-BLOCKED" => %{"status" => "cleanup_blocked", "cleanup_outstanding" => true},
        "T-COMPETING" => %{"status" => "queued", "ticket" => %{"checkout" => "/tmp/none"}}
      },
      "queue" => ["T-BLOCKED", "T-COMPETING"],
      "status" => "running",
      "paused" => false,
      "stop_requested" => false
    }

    :sys.replace_state(Coordinator, fn data ->
      if is_reference(data.tick_ref), do: Process.cancel_timer(data.tick_ref)

      %{
        data
        | state: state,
          agent_registry: %{"T-BLOCKED" => caller},
          tick_ref: nil,
          poll_ms: 60_000,
          coordinator_log_path: log_path,
          event_log_path: event_path,
          checkpoint_append_fn: fn _path, _event, _task, _run, _role, _attributes ->
            send(caller, :unexpected_tick_append)
            {:error, :unexpected_tick_append}
          end
      }
    end)

    send(Coordinator, :tick)
    next_state = Coordinator.state()
    runtime = :sys.get_state(Coordinator)

    assert next_state["queue"] == ["T-COMPETING"]
    assert next_state["assignments"]["T-COMPETING"]["status"] == "queued"
    assert is_reference(runtime.tick_ref)
    assert runtime.agent_registry == %{"T-BLOCKED" => caller}
    refute_receive :unexpected_tick_append
    refute File.exists?(event_path)

    assert {:ok, diagnostics} = PramanaFoundry.LogStore.read(log_path)
    assert Enum.any?(diagnostics, &(&1["event"] == "tick_admission_suspended"))
    refute Enum.any?(diagnostics, &(&1["event"] == "tick_error"))

    Process.cancel_timer(runtime.tick_ref)

    :sys.replace_state(Coordinator, fn data ->
      %{data | tick_ref: nil, checkpoint_append_fn: &Checkpoint.append/6}
    end)
  end

  test "Coordinator rejects a pending identity that conflicts with its registered execution" do
    task_id = "T-PENDING-CONFLICT"
    run_id = "run-pending-conflict"

    ticket = %{
      "task_id" => task_id,
      "base_revision" => @base_rev,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)
    assert {:ok, _} = Coordinator.admit_assignment(task_id, run_id, "developer")
    original = cleanup_attributes(task_id, run_id)

    :sys.replace_state(Coordinator, fn data ->
      {:ok, state} = Cleanup.register_resource(data.state, original)
      %{data | state: state}
    end)

    before_state = Coordinator.state()
    event_path = :sys.get_state(Coordinator).event_log_path
    {:ok, before_events} = Checkpoint.events(event_path)
    replacement = replace_resource_identity(original, "replacement")

    assert {:error, :cleanup_pending_resource_identity_mismatch} =
             Coordinator.record_cleanup(:pending, replacement)

    assert Coordinator.state() == before_state
    assert {:ok, after_events} = Checkpoint.events(event_path)
    assert after_events == before_events
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

    :sys.replace_state(Coordinator, fn data ->
      put_in(data, [:state, "assignments", "T-COORD-1", "reviewer_run_id"], "review-c-1")
    end)

    # Receive approved review
    review = %{
      "schema_version" => 1,
      "run_id" => "review-c-1",
      "task_id" => "T-COORD-1",
      "commit" => @commit,
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => @check, "exit_code" => 0}]
    }

    assert {:ok, _} = Coordinator.receive_review("T-COORD-1", review, skip_git_checks: true)
    assert Coordinator.state()["assignments"]["T-COORD-1"]["status"] == "review_approved"

    # FR-03 containment suspends the legacy two-write Git path until its outcome
    # can be represented transactionally by FR-05/FR-07/FR-08.
    caller = self()
    mock_runner = fn _cmd, _path -> send(caller, :git_called) end

    assert {:error, {:suspended_until_transactional_integration, _reason}} =
             Coordinator.integrate("T-COORD-1",
               runner_fn: mock_runner,
               skip_git_checks: true
             )

    refute_receive :git_called
    assert Coordinator.state()["accepted_revision"] == @base_rev
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

    assert {:ok, _} =
             Coordinator.receive_handoff("T-REVIEW-RETRY-1", handoff, skip_git_checks: true)

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

    assert {:error, _reason} =
             Coordinator.receive_review("T-REVIEW-RETRY-1", bad_review, skip_git_checks: true)

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

    assert {:ok, _} =
             Coordinator.receive_handoff("T-REVIEW-RETRY-2", handoff, skip_git_checks: true)

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

  defp cleanup_attributes(task_id, execution_id) do
    %{
      "task_id" => task_id,
      "execution_id" => execution_id,
      "role" => "developer",
      "pane_id" => "pane-preserved",
      "terminal_id" => "terminal-preserved",
      "session" => %{
        "source" => "agent_session",
        "value" => "session-preserved",
        "terminal_id" => "terminal-preserved",
        "agent" => "omp"
      },
      "agent_name" => "agent-preserved",
      "presentation_identity" => %{
        "pane_id" => "pane-preserved",
        "terminal_id" => "terminal-preserved",
        "process_identity" => %{
          "pane_id" => "pane-preserved",
          "terminal_id" => "terminal-preserved",
          "shell_pid" => 4242,
          "started_at" => "fixture-generation-1",
          "foreground_pid" => 4343,
          "foreground_started_at" => "fixture-foreground-generation-1"
        }
      }
    }
  end

  defp register_cleanup_resource(attributes) do
    :sys.replace_state(Coordinator, fn data ->
      {:ok, state} = Cleanup.register_resource(data.state, attributes)
      %{data | state: state}
    end)
  end

  defp pane_created_attributes(attributes) do
    %{
      "execution_id" => attributes["execution_id"],
      "role" => attributes["role"],
      "pane_id" => attributes["pane_id"],
      "agent_name" => attributes["agent_name"],
      "cleanup_identity" => %{
        "name" => attributes["agent_name"],
        "pane_id" => attributes["pane_id"],
        "terminal_id" => attributes["terminal_id"],
        "session" => attributes["session"]
      },
      "presentation_identity" => attributes["presentation_identity"]
    }
  end

  defp assert_sibling_cleanup_fence(order, task_id) do
    developer_run = "run-developer"
    reviewer_run = "run-reviewer"

    ticket = %{
      "task_id" => task_id,
      "base_revision" => @base_rev,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [@check],
      "review_required_checks" => [@check],
      "checkout" => nil
    }

    assert :ok = Coordinator.enqueue_ticket(ticket)
    assert {:ok, _} = Coordinator.admit_assignment(task_id, developer_run, "developer")

    developer_verified = cleanup_attributes(task_id, developer_run)

    developer_unverified =
      developer_verified
      |> Map.put("session", nil)
      |> Map.put("presentation_identity", nil)
      |> Map.put("verification_status", "unverified")

    reviewer =
      cleanup_attributes(task_id, reviewer_run)
      |> Map.put("role", "reviewer")
      |> replace_resource_identity("reviewer")

    case order do
      :developer_first ->
        assert :ok = Coordinator.record_cleanup(:resource, developer_unverified)
        assert :ok = Coordinator.record_cleanup(:resource, reviewer)

      :reviewer_first ->
        assert :ok = Coordinator.record_cleanup(:resource, reviewer)
    end

    assert :ok = Coordinator.record_cleanup(:pending, reviewer)

    assert :ok =
             Coordinator.record_cleanup(
               :result,
               Map.merge(reviewer, %{"status" => "closed", "reason" => nil})
             )

    if order == :reviewer_first do
      assert :ok = Coordinator.record_cleanup(:resource, developer_unverified)
    end

    state = Coordinator.state()
    assignment = state["assignments"][task_id]
    assert assignment["cleanup_outstanding"]
    assert assignment["cleanup_resources"]["developer:run-developer"]["status"] == "unverified"
    assert assignment["cleanup_resources"]["reviewer:run-reviewer"]["status"] == "closed"
    refute Cleanup.all_owned_resources_terminal?(state)

    public = Coordinator.status()
    assert map_size(public["cleanup_resources"][task_id]) == 2

    competing = "#{task_id}-COMPETING"

    tick_state =
      state
      |> put_in(["assignments", competing], %{
        "status" => "queued",
        "ticket" => %{"checkout" => "/tmp/none"}
      })
      |> Map.put("queue", [competing])

    {after_tick, %{}, log} =
      Tick.process_queue(
        tick_state["queue"],
        tick_state,
        %{},
        nil,
        100,
        self(),
        Path.join(System.tmp_dir!(), "#{task_id}-tick.jsonl")
      )

    assert log == [{:admission_suspended, :cleanup_outstanding}]
    assert after_tick["assignments"][competing]["status"] == "queued"

    event_log_path = :sys.get_state(Coordinator).event_log_path
    assert {:ok, records} = Checkpoint.events(event_log_path)
    task_records = Enum.filter(records, &(&1["task_id"] == task_id))
    assert {:ok, %{state: replayed}} = Transition.rebuild(task_records)
    replayed_assignment = replayed["assignments"][task_id]
    assert replayed_assignment["cleanup_outstanding"]

    assert replayed_assignment["cleanup_resources"]["developer:run-developer"]["status"] ==
             "unverified"

    assert :ok =
             Coordinator.record_cleanup(:resource, Map.put(developer_verified, "session", nil))

    assert :ok = Coordinator.record_cleanup(:resource, developer_verified)
    assert :ok = Coordinator.record_cleanup(:pending, developer_verified)

    assert :ok =
             Coordinator.record_cleanup(
               :result,
               Map.merge(developer_verified, %{"status" => "closed", "reason" => nil})
             )

    terminal = Coordinator.state()
    refute terminal["assignments"][task_id]["cleanup_outstanding"]
    assert Cleanup.all_owned_resources_terminal?(terminal)
  end

  defp replace_resource_identity(attributes, suffix) do
    pane_id = "pane-#{suffix}"
    terminal_id = "terminal-#{suffix}"

    attributes
    |> Map.put("pane_id", pane_id)
    |> Map.put("terminal_id", terminal_id)
    |> Map.put("agent_name", "agent-#{suffix}")
    |> Map.put("session", %{
      "source" => "agent_session",
      "value" => "session-#{suffix}",
      "terminal_id" => terminal_id,
      "agent" => "omp"
    })
    |> Map.put("presentation_identity", %{
      "pane_id" => pane_id,
      "terminal_id" => terminal_id,
      "process_identity" => %{
        "pane_id" => pane_id,
        "terminal_id" => terminal_id,
        "shell_pid" => 5252,
        "started_at" => "shell-#{suffix}",
        "foreground_pid" => 5353,
        "foreground_started_at" => "foreground-#{suffix}"
      }
    })
  end
end
