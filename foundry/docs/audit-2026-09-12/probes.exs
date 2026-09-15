# Characterization probes for the September 12 audit. These assert observed defects,
# not desired behavior. Keep outside test/; delete/replace assertions as fixes land.
# Run from foundry/: HERDR_ENV=0 COORDINATOR_TICK=0 MIX_ENV=test mise exec -- 
#   mix run --no-start docs/audit-2026-09-12/probes.exs
System.put_env("HERDR_ENV", "0")
System.put_env("COORDINATOR_TICK", "0")
ExUnit.start(seed: 12_092_026)

defmodule PramanaFoundry.AuditSeptember12 do
  use ExUnit.Case, async: false
  alias PramanaFoundry.{Coordinator, Transition, CLI, Scheduler}
  alias PramanaFoundry.Coordinator.State
  alias PramanaFoundry.Effects.Checkpoint

  @base String.duplicate("a", 40)
  @commit String.duplicate("b", 40)

  setup do
    root =
      Path.join(
        System.tmp_dir!(),
        "foundry-audit-" <> Base.encode16(:crypto.strong_rand_bytes(8))
      )

    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{root: root, log: Path.join(root, "events.jsonl")}
  end

  defp boot(ctx) do
    start_supervised!(
      {Coordinator,
       accepted_revision: @base,
       event_log_path: ctx.log,
       coordinator_log_path: Path.join(ctx.root, "coord.jsonl"),
       telemetry_log_path: Path.join(ctx.root, "telemetry.jsonl"),
       enable_tick: false}
    )
  end

  defp ticket(extra \\ %{}) do
    Map.merge(
      %{
        "task_id" => "AUDIT-1",
        "base_revision" => @base,
        "scope" => ["allowed/**"],
        "required_checks" => [],
        "review_required_checks" => []
      },
      extra
    )
  end

  defp handoff do
    %{
      "schema_version" => 1,
      "task_id" => "AUDIT-1",
      "run_id" => "new-run",
      "assigned_base" => @base,
      "commit" => @commit,
      "changed_files" => ["allowed/file"],
      "reproduction_evidence" => %{},
      "checks" => [],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "completed"
    }
  end

  defp review(verdict \\ "approved") do
    %{
      "schema_version" => 1,
      "task_id" => "AUDIT-1",
      "run_id" => "new-run",
      "commit" => @commit,
      "verdict" => verdict,
      "findings" => [],
      "checks" => [],
      "remaining_risks" => []
    }
  end

  defp admit(ctx) do
    boot(ctx)
    :ok = Coordinator.enqueue_ticket(ticket())
    {:ok, _} = Coordinator.admit_assignment("AUDIT-1", "new-run", "developer")
  end

  defp rebuilt(ctx) do
    {:ok, events} = Checkpoint.events(ctx.log)
    {:ok, result} = Transition.rebuild(events, accepted_revision: @base)
    result.state
  end

  test "A01: enqueue acknowledges an event append failure", ctx do
    File.mkdir_p!(ctx.log)
    boot(ctx)
    assert :ok = Coordinator.enqueue_ticket(ticket())
    assert Coordinator.state()["queue"] == ["AUDIT-1"]
    assert {:error, _} = Checkpoint.events(ctx.log)
  end

  test "A02: one malformed trailing line discards valid history at startup", ctx do
    {:ok, _} =
      Checkpoint.append(ctx.log, "ticket_enqueued", "AUDIT-1", "pending", "system", %{
        "ticket" => ticket()
      })

    File.write!(ctx.log, "{broken\n", [:append])
    boot(ctx)
    assert Coordinator.state()["assignments"] == %{}
  end

  test "A03: pause stop and public admission are absent from replay", ctx do
    admit(ctx)
    assert :ok = Coordinator.pause()
    assert :ok = Coordinator.request_stop()
    assert Coordinator.state()["paused"]
    replay = rebuilt(ctx)
    refute replay["paused"]
    refute replay["stop_requested"]
    assert replay["assignments"]["AUDIT-1"]["status"] == "queued"
  end

  test "A04: exhausted handoff retry becomes queued on replay", ctx do
    admit(ctx)
    assert {:error, _} = Coordinator.receive_handoff("AUDIT-1", %{}, max_handoff_retries: 0)
    assert Coordinator.state()["assignments"]["AUDIT-1"]["status"] == "parked"
    assert rebuilt(ctx)["assignments"]["AUDIT-1"]["status"] == "queued"
  end

  test "A05: valid approved review artifact is lost during replay", ctx do
    admit(ctx)
    assert {:ok, _} = Coordinator.receive_handoff("AUDIT-1", handoff())
    assert {:ok, _} = Coordinator.receive_review("AUDIT-1", review())
    assert is_map(Coordinator.state()["assignments"]["AUDIT-1"]["review"])
    replay = rebuilt(ctx)
    assert replay["assignments"]["AUDIT-1"]["status"] == "review_approved"
    assert replay["assignments"]["AUDIT-1"]["review"] == nil
  end

  test "A06: an accepted rejected verdict crashes replay", ctx do
    admit(ctx)
    assert {:ok, _} = Coordinator.receive_handoff("AUDIT-1", handoff())
    assert {:ok, _} = Coordinator.receive_review("AUDIT-1", review("rejected"))
    assert_raise CaseClauseError, fn -> rebuilt(ctx) end
  end

  test "A07: PM-created work disappears during replay", ctx do
    boot(ctx)

    assert {:ok, _} =
             Coordinator.apply_pm_proposals([
               %{"operation" => "create", "ticket" => ticket(), "reason" => "audit"}
             ])

    assert Coordinator.state()["queue"] == ["AUDIT-1"]
    assert rebuilt(ctx)["queue"] == []
  end

  test "A08: an old run timeout completes the current attempt", ctx do
    admit(ctx)

    send(
      Process.whereis(Coordinator),
      {:agent_completed, "AUDIT-1", "obsolete-run", :timeout, %{}}
    )

    assert Coordinator.state()["assignments"]["AUDIT-1"]["status"] == "completed"
  end

  test "A09: reviewer launch overwrites developer pane", ctx do
    admit(ctx)

    send(
      Process.whereis(Coordinator),
      {:agent_launched, "AUDIT-1", :ok, %{pane_id: "dev-pane", agent_name: "dev"}}
    )

    send(
      Process.whereis(Coordinator),
      {:agent_launched, "AUDIT-1", :ok, %{pane_id: "review-pane", agent_name: "review"}}
    )

    assert Coordinator.state()["assignments"]["AUDIT-1"]["pane_id"] == "review-pane"
    {:ok, events} = Checkpoint.events(ctx.log)
    pane = List.last(events)
    assert pane["role"] == "developer"
    assert pane["run_id"] == "new-run"
    refute File.exists?(Path.join(ctx.root, "telemetry.jsonl"))
  end

  test "A10: CLI rewrites stale review identity and accepts a nonexistent candidate", ctx do
    admit(ctx)
    assert {:ok, _} = Coordinator.receive_handoff("AUDIT-1", handoff())
    path = Path.join(ctx.root, "review.json")

    File.write!(
      path,
      :json.encode(
        Map.merge(review(), %{"run_id" => "obsolete-run", "commit" => @base, "checks" => %{}})
      )
    )

    CLI.main(["review", "submit", "AUDIT-1", "--review-path", path])
    stored = Coordinator.state()["assignments"]["AUDIT-1"]["review"]
    assert stored["run_id"] == "new-run"
    assert stored["commit"] == @commit
    assert {:ok, _} = Coordinator.integrate("AUDIT-1")
    assert Coordinator.state()["accepted_revision"] == @commit
    refute File.exists?(Path.join(ctx.root, "candidate"))
  end

  test "A11: ticket auto_approve manufactures independent approval", ctx do
    boot(ctx)
    :ok = Coordinator.enqueue_ticket(ticket(%{"auto_approve" => true}))
    {:ok, _} = Coordinator.admit_assignment("AUDIT-1", "new-run", "developer")
    assert {:ok, assignment} = Coordinator.receive_handoff("AUDIT-1", handoff())
    assert assignment["review"]["auto_approved"]
    assert assignment["status"] == "review_approved"
  end

  test "A12: CLI block produces a malformed handoff and requeues work", ctx do
    admit(ctx)

    assert_raise RuntimeError, fn ->
      CLI.main(["handoff", "block", "AUDIT-1", "--reason", "missing input"])
    end

    assert Coordinator.state()["assignments"]["AUDIT-1"]["status"] == "queued"
  end

  test "A13: tick admits a dependency-blocked ticket rejected by scheduler", ctx do
    {:ok, state} =
      State.enqueue_ticket(
        State.new(accepted_revision: @base),
        ticket(%{"dependencies" => ["NOT-DONE"]})
      )

    assert {:ok, []} = Scheduler.plan_dispatch(state)

    {state, _, _} =
      PramanaFoundry.Coordinator.Tick.process_queue(
        state["queue"],
        state,
        %{},
        nil,
        1,
        self(),
        ctx.log
      )

    assert state["assignments"]["AUDIT-1"]["launch_retries"] == 1
    {:ok, events} = Checkpoint.events(ctx.log)
    assert Enum.any?(events, &(&1["event"] == "assignment_admitted"))
  end

  test "A14: default execution model is paid OpenRouter", ctx do
    {:ok, state} =
      PramanaFoundry.AgentServer.init(
        task_id: "AUDIT-1",
        run_id: "new-run",
        checkout: ctx.root,
        adapter: nil,
        coordinator_pid: self()
      )

    assert state.model == "openrouter/deepseek/deepseek-v4-flash"
    assert_receive :launch
  end

  test "A15: startup requeues dispatched work before inflight reconciliation", ctx do
    {:ok, _} =
      Checkpoint.append(ctx.log, "ticket_enqueued", "AUDIT-1", "pending", "system", %{
        "ticket" => ticket()
      })

    {:ok, _} =
      Checkpoint.append(ctx.log, "assignment_admitted", "AUDIT-1", "old-run", "developer")

    {:ok, _} =
      Checkpoint.append(ctx.log, "pane_created", "AUDIT-1", "old-run", "developer", %{
        "pane_id" => "still-live"
      })

    boot(ctx)
    state = Coordinator.state()
    assert state["queue"] == ["AUDIT-1"]
    assert state["assignments"]["AUDIT-1"]["pane_id"] == "still-live"
    assert Coordinator.agent_pid("AUDIT-1") == nil
  end

  test "A16: board event-log mode loses recovered tickets", ctx do
    previous = Application.get_env(:pramana_foundry, :runtime_root)
    Application.put_env(:pramana_foundry, :runtime_root, ctx.root)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:pramana_foundry, :runtime_root, previous),
        else: Application.delete_env(:pramana_foundry, :runtime_root)
    end)

    path = Path.join(ctx.root, "state/current/events.jsonl")

    {:ok, _} =
      Checkpoint.append(path, "ticket_enqueued", "AUDIT-1", "pending", "system", %{
        "ticket" => ticket()
      })

    assert PramanaFoundry.Board.load_data(:event_log).tickets == []
  end

  test "A17: wrapper JSON encoding permits Elixir interpolation" do
    payload = "literal " <> <<35>> <> "{1 + 1}"

    {encoded, 0} =
      System.cmd("python3", ["-c", "import json,sys; print(json.dumps(sys.argv[1:]))", payload])

    {decoded, _} = Code.eval_string(encoded)
    assert decoded == ["literal 2"]
    refute decoded == [payload]
  end

  test "A18: valid history above read limit starts empty", ctx do
    {:ok, _} =
      Checkpoint.append(ctx.log, "ticket_enqueued", "AUDIT-1", "pending", "system", %{
        "ticket" => ticket()
      })

    File.write!(ctx.log, String.duplicate("\n", PramanaFoundry.Schema.max_bytes()), [:append])
    assert {:error, %{reason: :oversized}} = Checkpoint.events(ctx.log)
    boot(ctx)
    assert Coordinator.state()["assignments"] == %{}
  end

  test "A19: real Git checkout passes handoff despite an omitted out-of-scope change", ctx do
    git = fn args ->
      {output, 0} = System.cmd("git", args, cd: ctx.root, stderr_to_stdout: true)
      String.trim(output)
    end

    git.(["init"])
    git.(["config", "user.name", "Foundry Audit"])
    git.(["config", "user.email", "audit@example.invalid"])
    File.write!(Path.join(ctx.root, "base"), "base")
    git.(["add", "."])
    git.(["-c", "commit.gpgsign=false", "commit", "-m", "base"])
    base = git.(["rev-parse", "HEAD"])
    File.mkdir_p!(Path.join(ctx.root, "allowed"))
    File.write!(Path.join(ctx.root, "allowed/file"), "in scope")
    File.write!(Path.join(ctx.root, "forbidden-policy"), "out of scope")
    git.(["add", "."])
    git.(["-c", "commit.gpgsign=false", "commit", "-m", "candidate"])
    commit = git.(["rev-parse", "HEAD"])
    artifact = Map.merge(handoff(), %{"assigned_base" => base, "commit" => commit})
    assignment_ticket = ticket(%{"checkout" => ctx.root, "base_revision" => base})

    assert {:ok, _} =
             PramanaFoundry.Assignments.Handoff.validate(artifact, assignment_ticket, %{
               "run_id" => "new-run"
             })

    assert git.(["diff", "--name-only", base, commit]) =~ "forbidden-policy"
  end
end
