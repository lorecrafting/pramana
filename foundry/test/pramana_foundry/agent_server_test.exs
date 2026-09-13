Code.require_file("../../test/support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.AgentServerTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.AgentServer
  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Herdr.Adapter

  @pane_split_result %{
    "result" => %{
      "pane" => %{
        "pane_id" => "pane-1",
        "terminal_id" => "term-1",
        "status" => "running"
      }
    }
  }

  @ready_agent %{
    "name" => "pramana-dev-runtest",
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "agent_status" => "idle",
    "agent_session" => "sess-1",
    "agent" => "claude"
  }

  @agent_start_result %{
    "result" => %{
      "agent" => @ready_agent
    }
  }

  @pane_get_result %{"pane" => %{"pane_id" => "pane-1", "terminal_id" => "term-1"}}
  @process_info_result %{
    "process_info" => %{
      "pane_id" => "pane-1",
      "terminal_id" => "term-1",
      "shell_pid" => 101,
      "started_at" => "fixture-generation-1",
      "foreground_pid" => 202,
      "foreground_started_at" => "fixture-foreground-generation-1"
    }
  }

  @launch_profiles %{
    "test-subscription" => %{
      "provider" => "test-provider",
      "account" => "test-account",
      "billing_class" => "subscription",
      "subscription_authorized" => true,
      "automatic_roles" => ["developer", "reviewer", "pm"],
      "quota_status" => "available",
      "model" => "subscription/test-model",
      "allowed_models" => ["subscription/test-model"],
      "approval_mode" => "write",
      "reasoning" => "medium"
    }
  }

  setup do
    # Unique ETS table per test (name based on test process pid)
    table_name = :"ets_#{System.unique_integer([:positive])}"
    :ets.new(table_name, [:set, :public, :named_table, write_concurrency: false])

    sup_name = :"agent_sup_#{System.unique_integer([:positive])}"

    {:ok, sup_pid} =
      DynamicSupervisor.start_link(
        name: sup_name,
        strategy: :one_for_one,
        max_children: 10
      )

    # Unlink so the supervisor survives the test process exiting
    Process.unlink(sup_pid)

    adapter = Adapter.new(PramanaFoundry.AgentServerTest.FakeRunner)

    on_exit(fn ->
      try do
        Supervisor.stop(sup_pid, :shutdown)
      rescue
        _ -> :ok
      end

      try do
        :ets.delete(table_name)
      rescue
        _ -> :ok
      end
    end)

    %{
      sup_pid: sup_pid,
      supervisor: sup_name,
      adapter: adapter,
      table: table_name
    }
  end

  defp start_agent(opts) do
    %{supervisor: sup, adapter: adapter, table: table} = opts

    DynamicSupervisor.start_child(sup, %{
      id: opts[:task_id] || "test-agent",
      start:
        {AgentServer, :start_link,
         [
           [
             task_id: opts[:task_id] || "T-TEST",
             run_id: opts[:run_id] || "RUNTEST",
             checkout: "/tmp/test-checkout",
             adapter: adapter,
             coordinator_pid: opts[:coordinator_pid] || self(),
             role: opts[:role] || :developer,
             handoff_data: opts[:handoff_data] || %{},
             profile: "test-subscription",
             launch_profiles: @launch_profiles,
             herdr_timeout_ms: opts[:herdr_timeout_ms] || 1000,
             work_timeout_ms: opts[:work_timeout_ms] || 600_000,
             telemetry_path: opts[:telemetry_path],
             cleanup_record_fn: opts[:cleanup_record_fn] || fn _phase, _attributes -> :ok end,
             herdr_opts: [ets_table: table]
           ]
         ]},
      restart: :temporary
    })
  end

  describe "launch" do
    test "successful launch sends {:agent_launched, task_id, :ok} and agent info", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-LAUNCH-OK"))

      assert_receive {:agent_launched, "T-LAUNCH-OK", :ok, info}, 2000
      assert info[:pane_id] == "pane-1"
      assert info[:agent_name] == "pramana-dev-runtest"

      status = AgentServer.status(pid)
      assert status[:launched] == true
      assert status[:pane_id] == "pane-1"

      calls = PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table)
      assert Enum.any?(calls, &match?(["herdr", "pane", "split" | _], &1))
      assert Enum.any?(calls, &match?(["herdr", "agent", "start" | _], &1))
      assert Enum.any?(calls, &match?(["herdr", "agent", "prompt" | _], &1))

      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(ctx.sup_pid, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
    end

    test "failed pane split sends {:agent_launched, task_id, {:error, ...}} and stops", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] -> {:error, :split_failed}
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-PANE-FAIL"))

      assert_receive {:agent_launched, "T-PANE-FAIL", {:error, stage, _reason}, _info}, 2000
      assert stage == :pane_split_failed

      # Wait for the GenServer to finish its stop sequence
      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end

    test "failed agent start sends error to coordinator and stops", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          {:error, :start_failed}

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-AGENT-FAIL"))

      assert_receive {:agent_launched, "T-AGENT-FAIL", {:error, stage, _reason}, _info}, 2000
      assert stage == :agent_start_failed

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end

    test "agent-start failure never adopts a replacement process after the pre-start baseline",
         ctx do
      table = ctx.table

      PramanaFoundry.AgentServerTest.FakeRunner.install(table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          {foreground_pid, foreground_generation} =
            case :ets.lookup(table, :replacement_started) do
              [] -> {202, "fixture-foreground-generation-1"}
              _ -> {303, "fixture-foreground-generation-replacement"}
            end

          result =
            @process_info_result
            |> put_in(["process_info", "foreground_pid"], foreground_pid)
            |> put_in(
              ["process_info", "foreground_started_at"],
              foreground_generation
            )

          PramanaFoundry.AgentServerTest.FakeRunner.json(result)

        ["herdr", "agent", "start" | _] ->
          :ets.insert(table, {:replacement_started, true})
          {:error, :start_timeout}
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-START-REPLACED"))

      assert_receive {:agent_launched, "T-START-REPLACED",
                      {:error, :agent_start_failed, :start_timeout},
                      %{cleanup: %{status: :unresolved, reason: :pane_process_identity_changed}}},
                     2_000

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000

      calls = PramanaFoundry.AgentServerTest.FakeRunner.calls(table)

      assert index_of(calls, ["herdr", "pane", "process-info", "--pane", "pane-1"]) <
               index_of_prefix(calls, ["herdr", "agent", "start"])

      refute Enum.any?(calls, &match?(["herdr", "pane", "close" | _], &1))
    end

    test "failed cleanup pending persistence preserves the exact pane without closing it", ctx do
      install_start_failure_fixture(ctx.table)
      caller = self()

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, "T-CLEANUP-PENDING-FAIL")
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:cleanup_record, phase, attributes})
            if phase == :pending, do: {:error, :injected_append_failure}, else: :ok
          end)
        )

      assert_receive {:cleanup_record, :pending, attributes}, 2_000
      assert attributes["execution_id"] == "RUNTEST"
      assert attributes["pane_id"] == "pane-1"
      assert attributes["terminal_id"] == "term-1"
      assert attributes["role"] == "developer"

      assert attributes["presentation_identity"]["process_identity"]["started_at"] ==
               "fixture-generation-1"

      assert_receive {:agent_launched, "T-CLEANUP-PENDING-FAIL", {:error, _, _},
                      %{cleanup: %{status: :unresolved, reason: reason}}},
                     2_000

      assert match?({:cleanup_pending_persistence_failed, :injected_append_failure}, reason)
      refute_receive {:cleanup_record, :result, _}

      refute Enum.any?(
               PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table),
               &match?(["herdr", "pane", "close" | _], &1)
             )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end

    test "split ownership registration failure prevents agent start and preserves the pane",
         ctx do
      install_start_failure_fixture(ctx.table)
      caller = self()

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, "T-RESOURCE-REGISTER-FAIL")
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:cleanup_record, phase, attributes})

            if phase == :resource,
              do: {:error, :injected_resource_append_failure},
              else: :ok
          end)
        )

      assert_receive {:cleanup_record, :resource, resource}, 2_000
      assert resource["session"] == nil
      assert resource["pane_id"] == "pane-1"

      assert_receive {:agent_launched, "T-RESOURCE-REGISTER-FAIL",
                      {:error, :cleanup_resource_registration_failed,
                       :injected_resource_append_failure},
                      %{cleanup: %{status: :unresolved, reason: :cleanup_resource_not_registered}}},
                     2_000

      calls = PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table)
      refute Enum.any?(calls, &match?(["herdr", "agent", "start" | _], &1))
      refute Enum.any?(calls, &match?(["herdr", "pane", "close" | _], &1))
      refute_receive {:cleanup_record, :pending, _}
      refute_receive {:cleanup_record, :result, _}

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end

    test "failed cleanup result persistence leaves pending evidence after an exact close", ctx do
      install_start_failure_fixture(ctx.table)
      caller = self()

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, "T-CLEANUP-RESULT-FAIL")
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:cleanup_record, phase, attributes})
            if phase == :result, do: {:error, :injected_readback_failure}, else: :ok
          end)
        )

      assert_receive {:cleanup_record, :pending, pending}, 2_000
      assert_receive {:cleanup_record, :result, result}, 2_000

      assert Map.take(pending, ~w(task_id execution_id role pane_id terminal_id session)) ==
               Map.take(result, ~w(task_id execution_id role pane_id terminal_id session))

      assert result["status"] == "closed"

      assert_receive {:agent_launched, "T-CLEANUP-RESULT-FAIL", {:error, _, _},
                      %{cleanup: %{status: :unresolved, reason: reason}}},
                     2_000

      assert match?({:cleanup_result_persistence_failed, :injected_readback_failure}, reason)

      assert Enum.any?(
               PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table),
               &match?(["herdr", "pane", "close" | _], &1)
             )

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000
    end

    test "failed prompt sends error and cleans up pane", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          {:error, :prompt_rejected}

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-PROMPT-FAIL"))

      assert_receive {:agent_launched, "T-PROMPT-FAIL", {:error, stage, _reason}, _info}, 2000
      assert stage == :prompt_failed

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end
  end

  describe "lifecycle" do
    test "work timeout sends {:agent_completed, task_id, ..., :timeout} and stops", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, _pid} =
        start_agent(%{
          supervisor: ctx.supervisor,
          adapter: ctx.adapter,
          table: ctx.table,
          task_id: "T-TIMEOUT",
          run_id: "RUNTEST",
          coordinator_pid: self(),
          work_timeout_ms: 10
        })

      assert_receive {:agent_launched, "T-TIMEOUT", :ok, _}, 2000
      assert_receive {:agent_completed, "T-TIMEOUT", _, :timeout, info}, 3000
      assert info.cleanup == %{status: :closed}

      calls = PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table)
      assert ["herdr", "pane", "close", "pane-1"] in calls
    end

    test "status returns current agent state and :gone after death", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-STATUS"))

      assert_receive {:agent_launched, "T-STATUS", :ok, _}, 2000

      status = AgentServer.status(pid)
      assert status[:task_id] == "T-STATUS"
      assert status[:agent_name] == "pramana-dev-runtest"
      assert status[:launched] == true

      # Kill via DynamicSupervisor termination
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(ctx.sup_pid, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000

      # Agent should be gone after termination
      gone = AgentServer.status(pid)
      assert gone == %{status: :gone}
    end
  end

  describe "pane cleanup" do
    test "accepted submit_review records pending and result before reviewer stops", ctx do
      base_revision = "d83f8f0cedc34780d25cba452545ce9883d416a5"
      commit = "2222333344445555666677778888999900001111"
      check = ["sh", "-c", "cd foundry && mix test"]
      task_id = "T-REVIEW-CLEANUP-ACCEPTED"
      :ok = Coordinator.reset(accepted_revision: base_revision)

      ticket = %{
        "task_id" => task_id,
        "base_revision" => base_revision,
        "scope" => ["foundry/lib/**"],
        "exclusions" => [],
        "required_checks" => [check],
        "review_required_checks" => [check],
        "checkout" => nil
      }

      assert :ok = Coordinator.enqueue_ticket(ticket)
      assert {:ok, _} = Coordinator.admit_assignment(task_id, "RUNTEST", "developer")

      handoff = %{
        "schema_version" => 1,
        "task_id" => task_id,
        "run_id" => "RUNTEST",
        "assigned_base" => base_revision,
        "commit" => commit,
        "changed_files" => ["foundry/lib/pramana_foundry/agent_server.ex"],
        "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
        "checks" => [%{"command" => check, "exit_code" => 0}],
        "remaining_risks" => [],
        "status" => "completed",
        "outcome" => "fixture"
      }

      assert {:ok, _} = Coordinator.receive_handoff(task_id, handoff, skip_git_checks: true)
      reviewer = %{@ready_agent | "name" => "pramana-review-runtest"}
      caller = self()
      install_reviewer_fixture(ctx.table, reviewer)

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, task_id)
          |> Map.put(:role, :reviewer)
          |> Map.put(:handoff_data, handoff)
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:accepted_review_cleanup, phase, attributes})
            :ok
          end)
        )

      assert_receive {:agent_launched, ^task_id, :ok, _}, 2_000

      review = %{
        "schema_version" => 1,
        "run_id" => "RUNTEST",
        "task_id" => task_id,
        "commit" => commit,
        "verdict" => "approved",
        "findings" => [],
        "remaining_risks" => [],
        "checks" => [%{"command" => check, "exit_code" => 0}]
      }

      assert :ok = AgentServer.submit_review(pid, review, skip_git_checks: true)
      assert_receive {:accepted_review_cleanup, :pending, pending}
      assert_receive {:accepted_review_cleanup, :result, result}
      assert pending["role"] == "reviewer"
      assert result["status"] == "closed"
    end

    test "rejected submit_review durably records pending and result identities", ctx do
      reviewer = %{@ready_agent | "name" => "pramana-review-runtest"}
      caller = self()
      install_reviewer_fixture(ctx.table, reviewer)

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, "T-REVIEW-CLEANUP-REJECTED")
          |> Map.put(:role, :reviewer)
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:review_cleanup_record, phase, attributes})
            :ok
          end)
        )

      assert_receive {:agent_launched, "T-REVIEW-CLEANUP-REJECTED", :ok, _}, 2_000
      assert {:error, :review_rejected} = AgentServer.submit_review(pid, %{})
      assert_receive {:review_cleanup_record, :pending, pending}
      assert_receive {:review_cleanup_record, :result, result}
      assert pending["role"] == "reviewer"
      assert pending["execution_id"] == "RUNTEST"
      assert result["status"] == "closed"
    end

    test "replacement session is preserved and unresolved cleanup is observable", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} =
        start_agent(Map.put(ctx, :task_id, "T-REPLACEMENT"))

      assert_receive {:agent_launched, "T-REPLACEMENT", :ok, _}, 2_000

      replacement = Map.put(@ready_agent, "agent_session", "replacement-session")

      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => replacement})
      end)

      send(pid, :work_timeout)

      assert_receive {:agent_completed, "T-REPLACEMENT", _, :timeout,
                      %{cleanup: %{status: :unresolved, reason: :session_mismatch}}},
                     2_000

      refute Enum.any?(
               PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table),
               &match?(["herdr", "pane", "close" | _], &1)
             )
    end

    test "fallback and malformed sessions persist as inert unresolved observations", ctx do
      for {suffix, session_value} <- [
            {"FALLBACK", nil},
            {"MALFORMED", %{"nested" => ["not", "authority"]}}
          ] do
        task_id = "T-UNTRUSTED-#{suffix}"
        :ok = Coordinator.reset(accepted_revision: String.duplicate("a", 40))

        ticket = %{
          "task_id" => task_id,
          "base_revision" => String.duplicate("a", 40),
          "scope" => ["foundry/lib/**"],
          "exclusions" => [],
          "required_checks" => [["mix", "test"]],
          "review_required_checks" => [["mix", "test"]],
          "checkout" => nil
        }

        assert :ok = Coordinator.enqueue_ticket(ticket)
        assert {:ok, _} = Coordinator.admit_assignment(task_id, "RUNTEST", "developer")

        agent =
          if is_nil(session_value),
            do: Map.delete(@ready_agent, "agent_session"),
            else: Map.put(@ready_agent, "agent_session", session_value)

        PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
          ["herdr", "pane", "split" | _] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

          ["herdr", "agent", "start" | _] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(%{"result" => %{"agent" => agent}})

          ["herdr", "pane", "get", "pane-1"] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

          ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

          ["herdr", "agent", "get", "pramana-dev-runtest"] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => agent})

          ["herdr", "agent", "prompt" | _] ->
            PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
        end)

        {:ok, pid} =
          start_agent(
            ctx
            |> Map.put(:task_id, task_id)
            |> Map.put(:coordinator_pid, Coordinator)
            |> Map.put(:cleanup_record_fn, &Coordinator.record_cleanup/2)
          )

        wait_for_launch = fn wait_for_launch, attempts ->
          if AgentServer.status(pid)[:launched] do
            :ok
          else
            if attempts == 0, do: flunk("agent did not launch")

            receive do
            after
              10 -> wait_for_launch.(wait_for_launch, attempts - 1)
            end
          end
        end

        assert :ok = wait_for_launch.(wait_for_launch, 100)
        send(pid, :work_timeout)

        ref = Process.monitor(pid)
        assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000

        assignment = Coordinator.state()["assignments"][task_id]
        obligation = assignment["cleanup_obligations"]["developer:RUNTEST"]
        assert assignment["status"] == "cleanup_blocked"
        assert obligation["session"] == nil
        assert is_binary(obligation["observed_session"])

        refute Enum.any?(
                 PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table),
                 &match?(["herdr", "pane", "close" | _], &1)
               )
      end
    end

    test "abnormal exit sends crash notification to coordinator", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

        ["herdr", "agent", "start" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)

        ["herdr", "pane", "get", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

        ["herdr", "agent", "get", "pramana-dev-runtest"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})

        ["herdr", "agent", "prompt" | _] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

        ["herdr", "pane", "close", "pane-1"] ->
          PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      caller = self()

      {:ok, pid} =
        start_agent(
          ctx
          |> Map.put(:task_id, "T-CLEANUP")
          |> Map.put(:cleanup_record_fn, fn phase, attributes ->
            send(caller, {:shutdown_cleanup_record, phase, attributes})
            :ok
          end)
        )

      assert_receive {:agent_launched, "T-CLEANUP", :ok, _}, 2000

      # Terminate the AgentServer via DynamicSupervisor
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(ctx.sup_pid, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000
      assert_receive {:shutdown_cleanup_record, :pending, pending}
      assert_receive {:shutdown_cleanup_record, :result, result}
      assert result["status"] == "closed"
      assert pending["agent_name"] == "pramana-dev-runtest"
      assert pending["session"]["value"] == "sess-1"

      refute Enum.any?(
               PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table),
               &match?(["herdr", "pane", "list" | _], &1)
             )
    end
  end

  defp install_start_failure_fixture(table) do
    PramanaFoundry.AgentServerTest.FakeRunner.install(table, fn
      ["herdr", "pane", "split" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

      ["herdr", "pane", "get", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

      ["herdr", "agent", "start" | _] ->
        {:error, :start_failed}

      ["herdr", "pane", "close", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
    end)
  end

  defp install_reviewer_fixture(table, reviewer) do
    PramanaFoundry.AgentServerTest.FakeRunner.install(table, fn
      ["herdr", "pane", "split" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)

      ["herdr", "pane", "get", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_get_result)

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(@process_info_result)

      ["herdr", "agent", "start" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"result" => %{"agent" => reviewer}})

      ["herdr", "agent", "get", "pramana-review-runtest"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => reviewer})

      ["herdr", "agent", "prompt" | _] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})

      ["herdr", "pane", "close", "pane-1"] ->
        PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
    end)
  end

  defp index_of(calls, expected), do: Enum.find_index(calls, &(&1 == expected))

  defp index_of_prefix(calls, prefix) do
    Enum.find_index(calls, fn call -> Enum.take(call, length(prefix)) == prefix end)
  end
end
