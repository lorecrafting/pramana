Code.require_file("support/fake_runner.exs", __DIR__)

defmodule PramanaFoundry.Herdr.AdapterTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.Herdr.Test.FakeRunner

  @agent %{
    "name" => "dev-1",
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "agent_status" => "idle",
    "agent_session" => "sess-1",
    "agent" => "claude"
  }

  setup do
    {:ok, adapter: Adapter.new(FakeRunner)}
  end

  test "inspect_agent parses Herdr's nested result shape", %{adapter: adapter} do
    FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
      FakeRunner.json(%{"result" => %{"agent" => @agent}})
    end)

    assert {:ok, identity} = Adapter.inspect_agent(adapter, "dev-1")
    assert identity.name == "dev-1"
    assert identity.pane_id == "pane-1"
  end

  test "inspect_agent refuses a response whose agent payload is not an object", %{
    adapter: adapter
  } do
    FakeRunner.install(fn _argv ->
      FakeRunner.json(%{"result" => %{"agent" => "not-an-object"}})
    end)

    assert {:error, {:not_an_object, _label}} = Adapter.inspect_agent(adapter, "dev-1")
  end

  test "argv is passed as an array; the prompt text is never concatenated into a shell string", %{
    adapter: adapter
  } do
    text = "run `id` and $(whoami)"

    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"result" => %{"agent" => @agent}})
      ["herdr", "agent", "prompt", "dev-1", ^text] -> FakeRunner.json(%{"ok" => true})
    end)

    expected = %{
      name: "dev-1",
      pane_id: "pane-1",
      terminal_id: "term-1",
      session: %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
    }

    assert {:ok, _} = Adapter.prompt(adapter, expected, text)
    assert ["herdr", "agent", "prompt", "dev-1", ^text] = List.last(FakeRunner.calls())
  end

  test "prompt refuses when the live pane no longer matches the expected identity", %{
    adapter: adapter
  } do
    drifted = %{@agent | "pane_id" => "pane-2"}

    FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
      FakeRunner.json(%{"agent" => drifted})
    end)

    expected = %{name: "dev-1", pane_id: "pane-1", terminal_id: "term-1", session: nil}
    assert {:error, :identity_mismatch} = Adapter.prompt(adapter, expected, "hello")
  end

  test "prompt refuses when the live session no longer matches the expected session", %{
    adapter: adapter
  } do
    FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
      FakeRunner.json(%{"agent" => @agent})
    end)

    expected = %{
      name: "dev-1",
      pane_id: "pane-1",
      terminal_id: "term-1",
      session: %{
        source: :agent_session,
        value: "sess-DIFFERENT",
        terminal_id: "term-1",
        agent: "claude"
      }
    }

    assert {:error, :session_mismatch} = Adapter.prompt(adapter, expected, "hello")
  end

  test "stop sends ctrl+c only after the identity check passes", %{adapter: adapter} do
    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @agent})
      ["herdr", "agent", "send-keys", "dev-1", "ctrl+c"] -> FakeRunner.json(%{"ok" => true})
    end)

    expected = %{
      name: "dev-1",
      pane_id: "pane-1",
      terminal_id: "term-1",
      session: %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
    }

    assert {:ok, _} = Adapter.stop(adapter, expected)
  end

  test "close_pane refuses when the returned pane no longer matches the requested one", %{
    adapter: adapter
  } do
    drifted_pane = %{"pane_id" => "pane-1", "terminal_id" => "term-2"}

    FakeRunner.install(fn
      ["herdr", "pane", "get", "pane-1"] ->
        FakeRunner.json(%{"pane" => drifted_pane})

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        FakeRunner.json(%{"process_info" => %{"shell_pid" => 1}})
    end)

    expected = %{name: "dev-1", pane_id: "pane-1", terminal_id: "term-1", session: nil}
    assert {:error, :pane_identity_changed} = Adapter.close_pane(adapter, expected)
  end

  test "requires HERDR_ENV=1 for the real System runner" do
    previous = System.get_env("HERDR_ENV")

    on_exit(fn ->
      if previous, do: System.put_env("HERDR_ENV", previous), else: System.delete_env("HERDR_ENV")
    end)

    System.delete_env("HERDR_ENV")

    assert {:error, :herdr_env_not_set} =
             PramanaFoundry.Herdr.Runner.System.run(["herdr", "agent", "get", "x"], [])
  end
end
