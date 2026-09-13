Code.require_file("../herdr/support/fake_runner.exs", __DIR__)

defmodule PramanaFoundry.Effects.LaunchTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Effects.{Checkpoint, Launch}
  alias PramanaFoundry.Herdr.{Adapter, Test.FakeRunner}

  @ready_agent %{
    "name" => "dev-1",
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "agent_status" => "idle",
    "agent_session" => "sess-1",
    "agent" => "claude"
  }

  @request %{name: "dev-1", kind: "claude", pane_id: "pane-1", timeout_ms: 60_000}

  setup do
    root = Path.join(System.tmp_dir!(), "launch-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{log_path: Path.join(root, "events.jsonl"), adapter: Adapter.new(FakeRunner)}
  end

  test "a fresh launch checkpoints intent, starts the agent, then checkpoints completion", %{
    log_path: log_path,
    adapter: adapter
  } do
    FakeRunner.install(fn
      ["herdr", "agent", "start" | _rest] -> FakeRunner.json(%{"ok" => true})
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @ready_agent})
    end)

    assert {:ok, identity} = Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)
    assert identity["pane_id"] == "pane-1"

    assert {:ok, events} = Checkpoint.events(log_path)
    assert Enum.map(events, & &1["event"]) == ["launch_intent", "launch_completed"]
    assert Enum.any?(FakeRunner.calls(), &match?(["herdr", "agent", "start" | _], &1))
  end

  test "crash after the intent checkpoint but before completion never re-runs `agent start`", %{
    log_path: log_path,
    adapter: adapter
  } do
    {:ok, _intent} = Checkpoint.append(log_path, "launch_intent", "T1", "R1", "developer", %{})

    FakeRunner.install(fn
      ["herdr", "agent", "start" | _rest] ->
        raise "agent start must never be called during reconciliation"

      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @ready_agent})
    end)

    assert {:ok, identity} = Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)
    assert identity["pane_id"] == "pane-1"

    assert {:ok, events} = Checkpoint.events(log_path)
    assert Enum.map(events, & &1["event"]) == ["launch_intent", "launch_completed"]
    refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "agent", "start" | _], &1))
  end

  test "an uncertain launch (agent absent after a crash) fails explicitly and is never rerun", %{
    log_path: log_path,
    adapter: adapter
  } do
    {:ok, _intent} = Checkpoint.append(log_path, "launch_intent", "T1", "R1", "developer", %{})

    FakeRunner.install(fn
      ["herdr", "agent", "start" | _rest] ->
        raise "agent start must never be called for uncertain evidence"

      ["herdr", "agent", "get", "dev-1"] ->
        {:error, :not_found}
    end)

    assert {:error, :ambiguous_launch} =
             Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)

    assert {:ok, events} = Checkpoint.events(log_path)
    assert Enum.map(events, & &1["event"]) == ["launch_intent"]
  end

  test "calling launch again after completion is a pure re-read: no further Herdr calls", %{
    log_path: log_path,
    adapter: adapter
  } do
    FakeRunner.install(fn
      ["herdr", "agent", "start" | _rest] -> FakeRunner.json(%{"ok" => true})
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @ready_agent})
    end)

    assert {:ok, _identity} = Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)
    calls_after_first = length(FakeRunner.calls())

    assert {:ok, _identity_again} =
             Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)

    assert length(FakeRunner.calls()) == calls_after_first
  end

  test "to_expected_identity round-trips a persisted native session for later prompt/stop calls",
       %{
         log_path: log_path,
         adapter: adapter
       } do
    FakeRunner.install(fn
      ["herdr", "agent", "start" | _rest] -> FakeRunner.json(%{"ok" => true})
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @ready_agent})
    end)

    {:ok, identity} = Launch.launch(log_path, "T1", "R1", "developer", adapter, @request)
    expected = Launch.to_expected_identity(identity)

    assert expected.name == "dev-1"

    assert expected.session == %{
             source: :agent_session,
             value: "sess-1",
             agent: "claude",
             terminal_id: "term-1"
           }
  end
end
