Code.require_file("herdr/support/fake_runner.exs", __DIR__)

defmodule PramanaFoundry.DaemonRecoveryTest do
  @moduledoc """
  Isolated, model-free recovery cleanup fixtures.

  FR-03 suspends legacy startup reconciliation, so this file does not pretend to
  exercise a live daemon restart. It proves the FR-04 ownership boundary without a
  real Herdr backend, live pane, provider, credential, release, or fixed state root.
  """

  use ExUnit.Case, async: true

  alias PramanaFoundry.Herdr.{Adapter, Test.FakeRunner}
  alias PramanaFoundry.RuntimeRoot

  @agent %{
    "name" => "owned-agent",
    "pane_id" => "owned-pane",
    "terminal_id" => "owned-terminal",
    "agent_status" => "idle",
    "agent_session" => "owned-session",
    "agent" => "omp"
  }
  @pane %{"pane_id" => "owned-pane", "terminal_id" => "owned-terminal"}
  @process_info %{
    "pane_id" => "owned-pane",
    "terminal_id" => "owned-terminal",
    "shell_pid" => 101,
    "started_at" => "fixture-1",
    "foreground_pid" => 202,
    "foreground_started_at" => "foreground-fixture-1"
  }
  @identity %{
    name: "owned-agent",
    pane_id: "owned-pane",
    terminal_id: "owned-terminal",
    session: %{
      source: :agent_session,
      value: "owned-session",
      terminal_id: "owned-terminal",
      agent: "omp"
    }
  }
  @presentation %{
    pane_id: "owned-pane",
    terminal_id: "owned-terminal",
    process_identity: %{
      pane_id: "owned-pane",
      terminal_id: "owned-terminal",
      shell_pid: 101,
      started_at: "fixture-1",
      foreground_pid: 202,
      foreground_started_at: "foreground-fixture-1"
    }
  }

  test "owned cleanup closes only the exact fixture resource and preserves unrelated logs" do
    fixture_root =
      Path.join(RuntimeRoot.fetch!(), "fr04-#{System.unique_integer([:positive, :monotonic])}")

    state_root = Path.join(fixture_root, "state/current")
    File.mkdir_p!(state_root)
    unrelated_log = Path.join(state_root, "unrelated.jsonl")
    unrelated_bytes = ~s({"owner":"foreign","must_survive":true}\n)
    File.write!(unrelated_log, unrelated_bytes, [:binary])
    before_hash = :crypto.hash(:sha256, unrelated_bytes)

    FakeRunner.install(fn
      ["herdr", "agent", "get", "owned-agent"] ->
        FakeRunner.json(%{"agent" => @agent})

      ["herdr", "pane", "get", "owned-pane"] ->
        FakeRunner.json(%{"pane" => @pane})

      ["herdr", "pane", "process-info", "--pane", "owned-pane"] ->
        FakeRunner.json(%{"process_info" => @process_info})

      ["herdr", "pane", "close", "owned-pane"] ->
        FakeRunner.json(%{"ok" => true})
    end)

    assert {:ok, _} = Adapter.close_pane(Adapter.new(FakeRunner), @identity, @presentation)
    assert File.read!(unrelated_log) == unrelated_bytes
    assert :crypto.hash(:sha256, File.read!(unrelated_log)) == before_hash

    calls = FakeRunner.calls()
    assert List.last(calls) == ["herdr", "pane", "close", "owned-pane"]
    refute Enum.any?(calls, &match?(["herdr", "pane", "list" | _], &1))
  end
end
