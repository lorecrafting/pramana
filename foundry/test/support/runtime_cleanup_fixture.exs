Code.require_file("agent_server_fake_runner.ex", __DIR__)

alias PramanaFoundry.AgentServer
alias PramanaFoundry.AgentServerTest.FakeRunner
alias PramanaFoundry.Coordinator
alias PramanaFoundry.Effects.Checkpoint
alias PramanaFoundry.Herdr.Adapter
alias PramanaFoundry.Transition

mode = System.fetch_env!("FR04_SHUTDOWN_MODE")
runtime_root = System.fetch_env!("PRAMANA_RUNTIME_ROOT")
event_path = Path.join(runtime_root, "state/current/events.jsonl")
fixture_pid = self()

{:ok, _apps} = Application.ensure_all_started(:pramana_foundry)

accepted_revision = Coordinator.state()["accepted_revision"]

ticket = %{
  "task_id" => "T-RUNTIME-CLEANUP",
  "base_revision" => accepted_revision,
  "scope" => ["foundry/lib/**"],
  "exclusions" => [],
  "required_checks" => [["mix", "test"]],
  "review_required_checks" => [["mix", "test"]],
  "checkout" => nil
}

:ok = Coordinator.enqueue_ticket(ticket)
{:ok, _assignment} = Coordinator.admit_assignment("T-RUNTIME-CLEANUP", "RUN-RUNTIME", "developer")

if mode != "success" do
  :sys.replace_state(Coordinator, fn data ->
    append = fn path, event, task_id, run_id, role, attributes ->
      case {mode, event} do
        {"registration_failure", "pane_created"} ->
          {:error, :injected_registration_failure}

        {"pending_failure", "cleanup_pending"} ->
          {:error, :injected_pending_failure}

        {"result_failure", "cleanup_result"} ->
          {:error, :injected_result_failure}

        {"deadline", "cleanup_pending"} ->
          receive do
          after
            300 -> Checkpoint.append(path, event, task_id, run_id, role, attributes)
          end

        _other ->
          Checkpoint.append(path, event, task_id, run_id, role, attributes)
      end
    end

    %{data | checkpoint_append_fn: append}
  end)
end

table = :fr04_runtime_cleanup_fixture
:ets.new(table, [:set, :public, :named_table])
:ets.new(:agent_server_test_default, [:set, :public, :named_table])

pane = %{
  "result" => %{"pane" => %{"pane_id" => "pane-runtime", "terminal_id" => "term-runtime"}}
}

agent = %{
  "name" => "pramana-dev-run-runt",
  "pane_id" => "pane-runtime",
  "terminal_id" => "term-runtime",
  "agent_status" => "idle",
  "agent_session" => "session-runtime",
  "agent" => "omp"
}

process_info = %{
  "pane_id" => "pane-runtime",
  "terminal_id" => "term-runtime",
  "shell_pid" => 100,
  "started_at" => "shell-generation-runtime",
  "foreground_pid" => 200,
  "foreground_started_at" => "foreground-generation-runtime"
}

runner_script = fn
  ["herdr", "pane", "split" | _] ->
    FakeRunner.json(pane)

  ["herdr", "pane", "get", "pane-runtime"] ->
    FakeRunner.json(%{"pane" => pane["result"]["pane"]})

  ["herdr", "pane", "process-info", "--pane", "pane-runtime"] ->
    observed_process =
      case mode do
        "capture_pid_only" ->
          %{"shell_pid" => 100}

        "capture_missing_generation" ->
          Map.drop(process_info, ~w(started_at foreground_started_at))

        _other ->
          case :ets.lookup(table, :replacement_after_start) do
            [] ->
              process_info

            _replacement ->
              Map.merge(process_info, %{
                "foreground_pid" => 201,
                "foreground_started_at" => "foreground-replacement-runtime"
              })
          end
      end

    FakeRunner.json(%{"process_info" => observed_process})

  ["herdr", "agent", "start" | _] ->
    case mode do
      "start_timeout_unchanged" ->
        {:error, :start_timeout}

      "start_timeout_replaced" ->
        :ets.insert(table, {:replacement_after_start, true})
        {:error, :start_timeout}

      _other ->
        FakeRunner.json(%{"result" => %{"agent" => agent}})
    end

  ["herdr", "agent", "get", "pramana-dev-run-runt"] ->
    FakeRunner.json(%{"agent" => agent})

  ["herdr", "agent", "prompt" | _] ->
    case :ets.lookup(table, :block_correction) do
      [] ->
        FakeRunner.json(%{"ok" => true})

      _blocked ->
        send(fixture_pid, :correction_prompt_entered)

        receive do
          :release_correction_prompt -> FakeRunner.json(%{"ok" => true})
        end
    end

  ["herdr", "pane", "close", "pane-runtime"] ->
    FakeRunner.json(%{"ok" => true})
end

FakeRunner.install(table, runner_script)
FakeRunner.install(:agent_server_test_default, runner_script)

profile = %{
  "provider" => "fixture-provider",
  "account" => "fixture-account",
  "billing_class" => "subscription",
  "subscription_authorized" => true,
  "automatic_roles" => ["developer"],
  "quota_status" => "available",
  "model" => "fixture/model",
  "allowed_models" => ["fixture/model"],
  "approval_mode" => "write",
  "reasoning" => "medium"
}

child = %{
  id: :fr04_runtime_agent,
  restart: :temporary,
  shutdown: if(mode in ~w(deadline pre_pending_deadline), do: 50, else: 2_000),
  start:
    {AgentServer, :start_link,
     [
       [
         task_id: "T-RUNTIME-CLEANUP",
         run_id: "RUN-RUNTIME",
         checkout: "/tmp/model-free",
         adapter: Adapter.new(FakeRunner),
         coordinator_pid: Coordinator,
         role: :developer,
         profile: "fixture",
         launch_profiles: %{"fixture" => profile},
         herdr_timeout_ms: 1_000,
         work_timeout_ms: 60_000,
         herdr_opts: [ets_table: table]
       ]
     ]}
}

{:ok, agent_pid} = DynamicSupervisor.start_child(PramanaFoundry.AssignmentSupervisor, child)

wait_for_launch = fn wait_for_launch, attempts ->
  if AgentServer.status(agent_pid)[:launched] do
    :ok
  else
    if attempts == 0, do: raise("agent did not launch")

    receive do
    after
      10 -> wait_for_launch.(wait_for_launch, attempts - 1)
    end
  end
end

if mode in ~w(start_timeout_unchanged start_timeout_replaced registration_failure capture_pid_only capture_missing_generation) do
  ref = Process.monitor(agent_pid)

  receive do
    {:DOWN, ^ref, :process, ^agent_pid, _reason} -> :ok
  after
    2_000 -> raise "failed launch agent did not terminate"
  end

  wait_for_failure = fn wait_for_failure, attempts ->
    state = Coordinator.state()
    status = get_in(state, ["assignments", "T-RUNTIME-CLEANUP", "status"])

    recovered_resource =
      get_in(state, [
        "assignments",
        "T-RUNTIME-CLEANUP",
        "cleanup_resources",
        "developer:RUN-RUNTIME"
      ])

    projected =
      if mode == "registration_failure" do
        state["status"] == "recovery_required" and is_map(recovered_resource)
      else
        status in ~w(launch_failed cleanup_blocked queued)
      end

    if projected do
      :ok
    else
      if attempts == 0, do: raise("failed launch was not projected")

      receive do
      after
        10 -> wait_for_failure.(wait_for_failure, attempts - 1)
      end
    end
  end

  :ok = wait_for_failure.(wait_for_failure, 100)
else
  :ok = wait_for_launch.(wait_for_launch, 100)
end

if mode == "pre_pending_deadline" do
  :sys.replace_state(Coordinator, fn data ->
    put_in(
      data,
      [:state, "assignments", "T-RUNTIME-CLEANUP", "status"],
      "handoff_received"
    )
  end)

  :ets.insert(table, {:block_correction, true})
  :ets.insert(:agent_server_test_default, {:block_correction, true})
  send(agent_pid, {:apply_correction, %{"findings" => []}})

  receive do
    :correction_prompt_entered -> :ok
  after
    1_000 -> raise "correction prompt did not block"
  end
end

assignment = get_in(Coordinator.state(), ["assignments", "T-RUNTIME-CLEANUP"]) || %{}

started = System.monotonic_time(:millisecond)
:ok = Application.stop(:pramana_foundry)
elapsed = System.monotonic_time(:millisecond) - started
{:ok, events} = Checkpoint.events(event_path)
{:ok, %{state: replayed}} = Transition.rebuild(events)

cleanup_events =
  events
  |> Enum.filter(&(&1["event"] in ~w(cleanup_pending cleanup_result)))
  |> Enum.map(& &1["event"])

calls = FakeRunner.calls(table)

resource_status =
  get_in(assignment, ["cleanup_resources", "developer:RUN-RUNTIME", "status"])

verification_status =
  get_in(assignment, ["cleanup_resources", "developer:RUN-RUNTIME", "verification_status"])

cleanup_outstanding = Map.get(assignment, "cleanup_outstanding", false)

durable_resource_status =
  get_in(replayed, [
    "assignments",
    "T-RUNTIME-CLEANUP",
    "cleanup_resources",
    "developer:RUN-RUNTIME",
    "status"
  ])

durable_verification_status =
  get_in(replayed, [
    "assignments",
    "T-RUNTIME-CLEANUP",
    "cleanup_resources",
    "developer:RUN-RUNTIME",
    "verification_status"
  ])

durable_cleanup_outstanding =
  get_in(replayed, ["assignments", "T-RUNTIME-CLEANUP", "cleanup_outstanding"])

IO.inspect(
  %{
    mode: mode,
    elapsed_ms: elapsed,
    cleanup_events: cleanup_events,
    resource_events: Enum.count(events, &(&1["event"] == "pane_created")),
    resource_status: resource_status,
    verification_status: verification_status,
    durable_resource_status: durable_resource_status,
    durable_verification_status: durable_verification_status,
    cleanup_outstanding: cleanup_outstanding,
    durable_cleanup_outstanding: durable_cleanup_outstanding,
    start_called: Enum.any?(calls, &match?(["herdr", "agent", "start" | _], &1)),
    close_called: Enum.any?(calls, &match?(["herdr", "pane", "close" | _], &1)),
    unclean_marker: File.exists?(Path.join(runtime_root, "runtime-owner.unclean"))
  },
  label: "FR04_RUNTIME_CLEANUP"
)
