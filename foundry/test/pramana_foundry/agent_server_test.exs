Code.require_file("../../test/support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.AgentServerTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.AgentServer
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
    "name" => "dev-1",
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
        :ets.delete(table_name)
      rescue
        _ -> :ok
      end
      try do
        Supervisor.stop(sup_pid, :shutdown)
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
      start: {AgentServer, :start_link, [[
        task_id: opts[:task_id] || "T-TEST",
        run_id: opts[:run_id] || "RUNTEST",
        checkout: "/tmp/test-checkout",
        adapter: adapter,
        coordinator_pid: opts[:coordinator_pid] || self(),
        herdr_timeout_ms: opts[:herdr_timeout_ms] || 1000,
        work_timeout_ms: opts[:work_timeout_ms] || 600_000,
        herdr_opts: [ets_table: table]
      ]]},
      restart: :temporary
    })
  end

  describe "launch" do
    test "successful launch sends {:agent_launched, task_id, :ok} and agent info", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)
        ["herdr", "agent", "get", "dev-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})
        ["herdr", "agent", "prompt" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-LAUNCH-OK"))

      assert_receive {:agent_launched, "T-LAUNCH-OK", :ok, info}, 2000
      assert info[:pane_id] == "pane-1"
      assert info[:agent_name] == "dev-1"

      status = AgentServer.status(pid)
      assert status[:launched] == true
      assert status[:pane_id] == "pane-1"

      calls = PramanaFoundry.AgentServerTest.FakeRunner.calls(ctx.table)
      assert Enum.any?(calls, &match?(["herdr", "pane", "split" | _], &1))
      assert Enum.any?(calls, &match?(["herdr", "agent", "start" | _], &1))
      assert Enum.any?(calls, &match?(["herdr", "agent", "prompt" | _], &1))
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
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> {:error, :start_failed}
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-AGENT-FAIL"))

      assert_receive {:agent_launched, "T-AGENT-FAIL", {:error, stage, _reason}, _info}, 2000
      assert stage == :agent_start_failed

      ref = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1000
    end

    test "failed prompt sends error and cleans up pane", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)
        ["herdr", "agent", "get", "dev-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})
        ["herdr", "agent", "prompt" | _] -> {:error, :prompt_rejected}
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
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)
        ["herdr", "agent", "get", "dev-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})
        ["herdr", "agent", "prompt" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
        ["herdr", "pane", "close", "pane-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, _pid} =
        start_agent(%{
          supervisor: ctx.supervisor,
          adapter: ctx.adapter,
          table: ctx.table,
          task_id: "T-TIMEOUT",
          run_id: "RUNTIMEOUT",
          coordinator_pid: self(),
          work_timeout_ms: 10
        })

      assert_receive {:agent_launched, "T-TIMEOUT", :ok, _}, 2000
      assert_receive {:agent_completed, "T-TIMEOUT", _, :timeout, _info}, 3000
    end

    test "status returns current agent state and :gone after death", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)
        ["herdr", "agent", "get", "dev-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})
        ["herdr", "agent", "prompt" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-STATUS"))

      assert_receive {:agent_launched, "T-STATUS", :ok, _}, 2000

      status = AgentServer.status(pid)
      assert status[:task_id] == "T-STATUS"
      assert status[:agent_name] == "dev-1"
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
    test "abnormal exit sends crash notification to coordinator", ctx do
      PramanaFoundry.AgentServerTest.FakeRunner.install(ctx.table, fn
        ["herdr", "pane", "split" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@pane_split_result)
        ["herdr", "agent", "start" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(@agent_start_result)
        ["herdr", "agent", "get", "dev-1"] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"agent" => @ready_agent})
        ["herdr", "agent", "prompt" | _] -> PramanaFoundry.AgentServerTest.FakeRunner.json(%{"ok" => true})
      end)

      {:ok, pid} = start_agent(Map.put(ctx, :task_id, "T-CLEANUP"))

      assert_receive {:agent_launched, "T-CLEANUP", :ok, _}, 2000

      # Terminate the AgentServer via DynamicSupervisor
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(ctx.sup_pid, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2000
    end
  end
end