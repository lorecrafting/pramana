Code.require_file("agent_server_fake_runner.ex", __DIR__)

alias PramanaFoundry.AgentServer
alias PramanaFoundry.AgentServerTest.FakeRunner
alias PramanaFoundry.Coordinator
alias PramanaFoundry.Effects.Checkpoint
alias PramanaFoundry.Herdr.Adapter
alias PramanaFoundry.Transition

mode = System.fetch_env!("FR04_TWO_RESOURCE_MODE")
runtime_root = System.fetch_env!("PRAMANA_RUNTIME_ROOT")
event_path = Path.join(runtime_root, "state/current/events.jsonl")
fixture_pid = self()

{:ok, _apps} = Application.ensure_all_started(:pramana_foundry)
accepted_revision = Coordinator.state()["accepted_revision"]

ticket = %{
  "task_id" => "T-TWO-RESOURCES",
  "base_revision" => accepted_revision,
  "scope" => ["foundry/lib/**"],
  "exclusions" => [],
  "required_checks" => [["mix", "test"]],
  "review_required_checks" => [["mix", "test"]],
  "checkout" => nil
}

:ok = Coordinator.enqueue_ticket(ticket)
{:ok, _assignment} = Coordinator.admit_assignment("T-TWO-RESOURCES", "RUN-DEV", "developer")

dev_table = :fr04_two_resource_developer
review_table = :fr04_two_resource_reviewer
:ets.new(dev_table, [:set, :public, :named_table])
:ets.new(review_table, [:set, :public, :named_table])
:ets.new(:agent_server_test_default, [:set, :public, :named_table])

profile = %{
  "provider" => "fixture-provider",
  "account" => "fixture-account",
  "billing_class" => "subscription",
  "subscription_authorized" => true,
  "automatic_roles" => ["developer", "reviewer"],
  "quota_status" => "available",
  "model" => "fixture/model",
  "allowed_models" => ["fixture/model"],
  "approval_mode" => "write",
  "reasoning" => "medium"
}

fixture = fn role ->
  prefix = if role == :developer, do: "dev", else: "review"
  run_id = if role == :developer, do: "RUN-DEV", else: "RUN-REVIEW"
  agent_name = if role == :developer, do: "pramana-dev-run-dev", else: "pramana-review-run-revi"
  pane_id = "pane-#{prefix}"
  terminal_id = "terminal-#{prefix}"

  agent = %{
    "name" => agent_name,
    "pane_id" => pane_id,
    "terminal_id" => terminal_id,
    "agent_status" => "idle",
    "agent_session" => "session-#{prefix}",
    "agent" => "omp"
  }

  process_info = %{
    "pane_id" => pane_id,
    "terminal_id" => terminal_id,
    "shell_pid" => if(role == :developer, do: 101, else: 301),
    "started_at" => "shell-generation-#{prefix}",
    "foreground_pid" => if(role == :developer, do: 202, else: 402),
    "foreground_started_at" => "foreground-generation-#{prefix}"
  }

  %{
    role: role,
    run_id: run_id,
    agent_name: agent_name,
    pane_id: pane_id,
    terminal_id: terminal_id,
    agent: agent,
    process_info: process_info
  }
end

developer = fixture.(:developer)
reviewer = fixture.(:reviewer)

install = fn table, resource ->
  script = fn
    ["herdr", "pane", "split" | _] ->
      FakeRunner.json(%{
        "result" => %{
          "pane" => %{"pane_id" => resource.pane_id, "terminal_id" => resource.terminal_id}
        }
      })

    ["herdr", "pane", "get", pane_id] when pane_id == resource.pane_id ->
      FakeRunner.json(%{"pane" => %{"pane_id" => pane_id, "terminal_id" => resource.terminal_id}})

    ["herdr", "pane", "process-info", "--pane", pane_id] when pane_id == resource.pane_id ->
      FakeRunner.json(%{"process_info" => resource.process_info})

    ["herdr", "agent", "start" | _] ->
      FakeRunner.json(%{"result" => %{"agent" => resource.agent}})

    ["herdr", "agent", "get", agent_name] when agent_name == resource.agent_name ->
      FakeRunner.json(%{"agent" => resource.agent})

    ["herdr", "agent", "prompt" | _] ->
      if resource.role == :developer and :ets.member(dev_table, :block_correction) do
        send(fixture_pid, :developer_correction_entered)

        receive do
          :release_developer -> FakeRunner.json(%{"ok" => true})
        end
      else
        FakeRunner.json(%{"ok" => true})
      end

    ["herdr", "pane", "close", pane_id] when pane_id == resource.pane_id ->
      FakeRunner.json(%{"ok" => true})
  end

  FakeRunner.install(table, script)
  script
end

developer_script = install.(dev_table, developer)
_reviewer_script = install.(review_table, reviewer)
FakeRunner.install(:agent_server_test_default, developer_script)

start_agent = fn resource, table, shutdown ->
  DynamicSupervisor.start_child(PramanaFoundry.AssignmentSupervisor, %{
    id: {resource.role, resource.run_id},
    restart: :temporary,
    shutdown: shutdown,
    start:
      {AgentServer, :start_link,
       [
         [
           task_id: "T-TWO-RESOURCES",
           run_id: resource.run_id,
           checkout: "/tmp/model-free",
           adapter: Adapter.new(FakeRunner),
           coordinator_pid: Coordinator,
           role: resource.role,
           profile: "fixture",
           launch_profiles: %{"fixture" => profile},
           herdr_timeout_ms: 1_000,
           work_timeout_ms: 60_000,
           herdr_opts: [ets_table: table]
         ]
       ]}
  })
end

developer_shutdown = if mode == "developer_deadline", do: 50, else: 2_000
{:ok, developer_pid} = start_agent.(developer, dev_table, developer_shutdown)
{:ok, reviewer_pid} = start_agent.(reviewer, review_table, 2_000)

wait_for_resources = fn wait_for_resources, attempts ->
  resources =
    Coordinator.state()
    |> get_in(["assignments", "T-TWO-RESOURCES", "cleanup_resources"])
    |> case do
      value when is_map(value) -> value
      _other -> %{}
    end

  if map_size(resources) == 2 do
    :ok
  else
    if attempts == 0, do: raise("both resources were not registered")

    receive do
    after
      10 -> wait_for_resources.(wait_for_resources, attempts - 1)
    end
  end
end

:ok = wait_for_resources.(wait_for_resources, 100)

case mode do
  "developer_deadline" ->
    :sys.replace_state(Coordinator, fn data ->
      put_in(data, [:state, "assignments", "T-TWO-RESOURCES", "status"], "handoff_received")
    end)

    :ets.insert(dev_table, {:block_correction, true})
    send(developer_pid, {:apply_correction, %{"findings" => []}})

    receive do
      :developer_correction_entered -> :ok
    after
      1_000 -> raise "developer correction did not block"
    end

  "developer_first" ->
    :ok = DynamicSupervisor.terminate_child(PramanaFoundry.AssignmentSupervisor, developer_pid)
    :ok = DynamicSupervisor.terminate_child(PramanaFoundry.AssignmentSupervisor, reviewer_pid)

  "reviewer_first" ->
    :ok = DynamicSupervisor.terminate_child(PramanaFoundry.AssignmentSupervisor, reviewer_pid)
    :ok = DynamicSupervisor.terminate_child(PramanaFoundry.AssignmentSupervisor, developer_pid)
end

:ok = Application.stop(:pramana_foundry)
{:ok, events} = Checkpoint.events(event_path)
{:ok, %{state: replayed}} = Transition.rebuild(events)
resources = replayed["assignments"]["T-TWO-RESOURCES"]["cleanup_resources"]

IO.inspect(
  %{
    mode: mode,
    developer_status: resources["developer:RUN-DEV"]["status"],
    reviewer_status: resources["reviewer:RUN-REVIEW"]["status"],
    developer_closed:
      Enum.any?(FakeRunner.calls(dev_table), &match?(["herdr", "pane", "close" | _], &1)),
    reviewer_closed:
      Enum.any?(FakeRunner.calls(review_table), &match?(["herdr", "pane", "close" | _], &1)),
    unclean_marker: File.exists?(Path.join(runtime_root, "runtime-owner.unclean"))
  },
  label: "FR04_TWO_RESOURCES"
)
