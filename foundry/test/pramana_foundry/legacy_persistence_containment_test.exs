Code.require_file("../support/agent_server_fake_runner.ex", __DIR__)

defmodule PramanaFoundry.LegacyPersistenceContainmentTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Coordinator
  alias PramanaFoundry.Coordinator.{State, Tick}
  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.EventLog
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.AgentServerTest.FakeRunner

  @base "d83f8f0cedc34780d25cba452545ce9883d416a5"

  setup do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    root = Path.join(System.tmp_dir!(), "fr03-persistence-#{suffix}")
    File.mkdir!(root)
    original = :sys.get_state(Coordinator)

    on_exit(fn ->
      :sys.replace_state(Coordinator, fn _state -> original end)
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "public enqueue fails closed and enters visible recovery mode", %{root: root} do
    log_path = Path.join(root, "events.jsonl")
    File.mkdir_p!(log_path)

    :sys.replace_state(Coordinator, fn data ->
      %{
        data
        | state: State.new(accepted_revision: @base),
          event_log_path: log_path,
          recovery_error: nil,
          tick_ref: nil,
          require_runtime_owner: false
      }
    end)

    assert {:error, {:recovery_required, _reason}} = Coordinator.enqueue_ticket(ticket())
    state = Coordinator.state()
    assert state["status"] == "recovery_required"
    assert state["assignments"] == %{}
    assert File.dir?(log_path)
  end

  test "malformed, unsupported, oversized, and I/O-invalid logs preserve bytes and recover no work",
       %{root: root} do
    cases = [
      {"malformed.jsonl", "{broken\n"},
      {"unsupported.jsonl",
       IO.iodata_to_binary(
         :json.encode(%{
           "schema_version" => 2,
           "event" => "x",
           "at" => "now",
           "attributes" => %{},
           "evidence" => %{}
         })
       ) <> "\n"},
      {"oversized.jsonl", String.duplicate("\n", PramanaFoundry.Schema.max_bytes() + 1)}
    ]

    Enum.each(cases, fn {name, bytes} ->
      path = Path.join(root, name)
      File.write!(path, bytes)
      before = sha(path)

      assert {:ok, data} = Coordinator.init(event_log_path: path, enable_tick: true)
      assert data.state["status"] == "recovery_required"
      assert data.state["assignments"] == %{}
      assert data.tick_ref == nil
      assert data.recovery_error != nil
      assert sha(path) == before
    end)

    directory_path = Path.join(root, "directory-as-log")
    File.mkdir_p!(directory_path)
    assert {:ok, data} = Coordinator.init(event_log_path: directory_path, enable_tick: true)
    assert data.state["status"] == "recovery_required"
    assert data.tick_ref == nil
    assert File.dir?(directory_path)
  end

  test "unterminated history is preserved and rejected before replay or append", %{root: root} do
    prefix_path = Path.join(root, "prefix-incomplete.jsonl")

    assert {:ok, _} =
             Checkpoint.append(prefix_path, "ticket_enqueued", "T-PREFIX", "pending", "system", %{
               "ticket" => ticket("T-PREFIX")
             })

    File.write!(prefix_path, "{\"schema_version\":1", [:append])
    prefix_before = sha(prefix_path)

    assert {:ok, prefix_data} = Coordinator.init(event_log_path: prefix_path)
    assert prefix_data.state["status"] == "recovery_required"
    assert inspect(prefix_data.recovery_error) =~ "unterminated_jsonl"
    assert sha(prefix_path) == prefix_before

    complete_path = Path.join(root, "prefix-complete-no-delimiter.jsonl")

    assert {:ok, _} =
             Checkpoint.append(
               complete_path,
               "ticket_enqueued",
               "T-COMPLETE",
               "pending",
               "system",
               %{"ticket" => ticket("T-COMPLETE")}
             )

    complete =
      event("tick_processed", "tick", "tick", "system", %{})
      |> :json.encode()
      |> IO.iodata_to_binary()

    File.write!(complete_path, complete, [:append])
    complete_before = sha(complete_path)

    assert {:ok, complete_data} = Coordinator.init(event_log_path: complete_path)
    assert complete_data.state["status"] == "recovery_required"
    assert inspect(complete_data.recovery_error) =~ "unterminated_jsonl"

    assert {:error, :unterminated_jsonl} =
             EventLog.append(
               complete_path,
               event("tick_processed", "tick", "tick", "system", %{})
             )

    assert sha(complete_path) == complete_before
  end

  test "strict replay enters recovery for an unprojectable authoritative record", %{root: root} do
    path = Path.join(root, "unprojectable.jsonl")
    record = event("prompt_intent", "T-UNKNOWN", "run-unknown", "developer", %{})
    File.write!(path, IO.iodata_to_binary([:json.encode(record), "\n"]))
    before = sha(path)

    assert {:ok, data} = Coordinator.init(event_log_path: path, enable_tick: true)
    assert data.state["status"] == "recovery_required"
    assert inspect(data.recovery_error) =~ "invalid_replay"
    assert data.tick_ref == nil
    assert sha(path) == before
  end

  test "public status and health expose recovery status and reason", %{root: root} do
    install_state(
      State.new(accepted_revision: @base),
      fn _, _, _, _, _, _ ->
        {:error, :injected_status_failure}
      end,
      root
    )

    assert {:error, {:recovery_required, :injected_status_failure}} =
             Coordinator.enqueue_ticket(ticket("T-STATUS"))

    assert %{"status" => "recovery_required", "recovery_error" => reason} = Coordinator.status()
    assert reason =~ "injected_status_failure"
    assert %{status: "recovery_required", recovery_error: ^reason} = Coordinator.health()
  end

  test "handoff, review, and PM persistence failures do not acknowledge or notify", %{root: root} do
    reject = fn _, _, _, _, _, _ -> {:error, :injected_append_failure} end
    task_id = "T-FR03-BRANCHES"
    {:ok, queued} = State.enqueue_ticket(State.new(accepted_revision: @base), ticket(task_id))

    {:ok, _assignment, dispatched} =
      State.admit_assignment(queued, task_id, "run-fr03", "developer")

    handoff = handoff(task_id)

    install_state(dispatched, reject, root, %{task_id => self()})

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.receive_handoff(task_id, handoff, skip_git_checks: true)

    assert Coordinator.state() == recovery_view(dispatched, :injected_append_failure)
    refute_receive _message

    install_state(dispatched, reject, root, %{task_id => self()})

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.receive_handoff(task_id, %{}, skip_git_checks: true)

    assert Coordinator.state() == recovery_view(dispatched, :injected_append_failure)
    refute_receive _message

    {:ok, _assignment, handed_off} =
      State.receive_handoff(dispatched, task_id, handoff, skip_git_checks: true)

    install_state(handed_off, reject, root, %{task_id => self()})

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.receive_review(task_id, review(task_id), skip_git_checks: true)

    assert Coordinator.state() == recovery_view(handed_off, :injected_append_failure)
    refute_receive _message

    install_state(handed_off, reject, root, %{task_id => self()})

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.receive_review(task_id, %{}, skip_git_checks: true)

    assert Coordinator.state() == recovery_view(handed_off, :injected_append_failure)
    refute_receive _message

    pm_state = State.new(accepted_revision: @base)
    install_state(pm_state, reject, root)

    proposal = %{
      "operation" => "create",
      "ticket" => %{"task_id" => "T-PM", "base_revision" => @base, "dependencies" => []},
      "reason" => "fixture"
    }

    assert {:error, {:recovery_required, :injected_append_failure}} =
             Coordinator.apply_pm_proposals([proposal])

    assert Coordinator.state() == recovery_view(pm_state, :injected_append_failure)
  end

  test "legacy integration is suspended before Git or persistence effects", %{root: root} do
    caller = self()

    append = fn _, _, _, _, _, _ ->
      send(caller, :append_called)
      {:ok, %{}}
    end

    install_state(State.new(accepted_revision: @base), append, root)

    assert {:error, {:suspended_until_transactional_integration, _reason}} =
             Coordinator.integrate("T-NOT-RUN",
               runner_fn: fn _, _ -> send(caller, :git_called) end
             )

    refute_receive :append_called
    refute_receive :git_called
  end

  test "tick persistence failure starts no child and performs no backend call", %{root: root} do
    task_id = "T-FR03-TICK"
    {:ok, state} = State.enqueue_ticket(State.new(accepted_revision: @base), ticket(task_id))
    bad_log = Path.join(root, "events-as-directory")
    File.mkdir_p!(bad_log)
    table = :fr03_persistence_fake_runner
    FakeRunner.create_table(table)
    on_exit(fn -> if :ets.whereis(table) != :undefined, do: :ets.delete(table) end)
    adapter = Adapter.new(FakeRunner)
    policy = FakeRunner.launch_policy()

    assert catch_throw(
             Tick.process_queue(
               [task_id],
               state,
               %{},
               adapter,
               1_000,
               self(),
               bad_log,
               nil,
               3,
               profiles: policy.profiles,
               role_profiles: policy.role_profiles,
               now: 1,
               herdr_opts: [ets_table: table]
             )
           )
           |> elem(0) == :persistence_failed

    assert FakeRunner.calls(table) == []
  end

  test "later prelaunch append failure exposes recovery boundary before any child effect", %{
    root: root
  } do
    task_id = "T-FR03-LATER-TICK"
    {:ok, state} = State.enqueue_ticket(State.new(accepted_revision: @base), ticket(task_id))
    table = :fr03_later_tick_fake_runner
    FakeRunner.create_table(table)
    on_exit(fn -> if :ets.whereis(table) != :undefined, do: :ets.delete(table) end)
    adapter = Adapter.new(FakeRunner)
    policy = FakeRunner.launch_policy()
    counter = start_supervised!({Agent, fn -> 0 end})

    append = fn _path, _event, _task_id, _run_id, _role, _attributes ->
      case Agent.get_and_update(counter, fn count -> {count, count + 1} end) do
        0 -> {:ok, %{}}
        _ -> {:error, :injected_later_append_failure}
      end
    end

    assert catch_throw(
             Tick.process_queue(
               [task_id],
               state,
               %{},
               adapter,
               1_000,
               self(),
               Path.join(root, "unused.jsonl"),
               nil,
               3,
               profiles: policy.profiles,
               role_profiles: policy.role_profiles,
               now: 1,
               herdr_opts: [ets_table: table],
               append_fn: append
             )
           ) == {:persistence_failed, :injected_later_append_failure}

    assert Agent.get(counter, & &1) == 2
    assert FakeRunner.calls(table) == []
  end

  test "Coordinator and Tick contain every checkpoint append behind the checked helpers" do
    coordinator = File.read!(Path.expand("../../lib/pramana_foundry/coordinator.ex", __DIR__))
    tick = File.read!(Path.expand("../../lib/pramana_foundry/coordinator/tick.ex", __DIR__))

    assert length(Regex.scan(~r/Checkpoint\.append\(/, coordinator)) == 1
    assert coordinator =~ "defp checked_append"
    assert coordinator =~ "defp startup_append_or_halt"
    assert length(Regex.scan(~r/Checkpoint\.append\(/, tick)) == 0
    assert tick =~ "defp persist_or_halt"
  end

  defp ticket(task_id \\ "T-FR03-PUBLIC") do
    %{
      "task_id" => task_id,
      "base_revision" => @base,
      "scope" => ["foundry/lib/**"],
      "exclusions" => [],
      "required_checks" => [["sh", "-c", "true"]],
      "review_required_checks" => [["sh", "-c", "true"]],
      "checkout" => "/tmp/fr03-checkout",
      "profile" => "test-subscription"
    }
  end

  defp event(name, task_id, run_id, role, attributes) do
    %{
      "schema_version" => 1,
      "event" => name,
      "at" => "2026-09-13T00:00:00Z",
      "task_id" => task_id,
      "run_id" => run_id,
      "role" => role,
      "attributes" => attributes,
      "evidence" => %{}
    }
  end

  defp handoff(task_id) do
    %{
      "schema_version" => 1,
      "task_id" => task_id,
      "run_id" => "run-fr03",
      "assigned_base" => @base,
      "commit" => "2222333344445555666677778888999900001111",
      "changed_files" => ["foundry/lib/pramana_foundry/coordinator.ex"],
      "reproduction_evidence" => %{"before" => "fail", "after" => "pass"},
      "checks" => [%{"command" => ["sh", "-c", "true"], "exit_code" => 0}],
      "remaining_risks" => [],
      "status" => "completed",
      "outcome" => "fixture"
    }
  end

  defp review(task_id) do
    %{
      "schema_version" => 1,
      "run_id" => "run-fr03",
      "task_id" => task_id,
      "commit" => "2222333344445555666677778888999900001111",
      "verdict" => "approved",
      "findings" => [],
      "remaining_risks" => [],
      "checks" => [%{"command" => ["sh", "-c", "true"], "exit_code" => 0}]
    }
  end

  defp install_state(state, append_fn, root, registry \\ %{}) do
    :sys.replace_state(Coordinator, fn data ->
      %{
        data
        | state: state,
          event_log_path: Path.join(root, "injected.jsonl"),
          checkpoint_append_fn: append_fn,
          agent_registry: registry,
          recovery_error: nil,
          tick_ref: nil,
          require_runtime_owner: false
      }
    end)
  end

  defp recovery_view(state, reason) do
    state
    |> Map.put("status", "recovery_required")
    |> Map.put("recovery_error", inspect(reason))
  end

  defp sha(path) do
    path |> File.read!() |> then(&:crypto.hash(:sha256, &1))
  end
end
