Code.require_file("../herdr/support/fake_runner.exs", __DIR__)

defmodule PramanaFoundry.Effects.PromptDeliveryTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Effects.{Checkpoint, PromptDelivery}
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.Herdr.Test.FakeRunner

  @ready_agent %{
    "name" => "dev-1",
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "agent_status" => "idle",
    "agent_session" => "sess-1",
    "agent" => "claude"
  }

  @expected %{
    name: "dev-1",
    pane_id: "pane-1",
    terminal_id: "term-1",
    session: %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
  }

  setup do
    root = Path.join(System.tmp_dir!(), "prompt-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)
    %{log_path: Path.join(root, "events.jsonl"), adapter: Adapter.new(FakeRunner)}
  end

  test "a fresh prompt checkpoints intent, delivers once, then checkpoints delivered", %{
    log_path: log_path,
    adapter: adapter
  } do
    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @ready_agent})
      ["herdr", "agent", "prompt", "dev-1", "please continue"] -> FakeRunner.json(%{"ok" => true})
    end)

    assert {:ok, :delivered} =
             PromptDelivery.deliver(
               log_path,
               "T1",
               "R1",
               "developer",
               adapter,
               @expected,
               "please continue"
             )

    assert {:ok, events} = Checkpoint.events(log_path)
    assert Enum.map(events, & &1["event"]) == ["prompt_intent", "prompt_delivered"]
  end

  test "delivering twice for the same identity is a no-op the second time: no second `agent prompt` call",
       %{
         log_path: log_path,
         adapter: adapter
       } do
    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] -> FakeRunner.json(%{"agent" => @ready_agent})
      ["herdr", "agent", "prompt", "dev-1", "please continue"] -> FakeRunner.json(%{"ok" => true})
    end)

    assert {:ok, :delivered} =
             PromptDelivery.deliver(
               log_path,
               "T1",
               "R1",
               "developer",
               adapter,
               @expected,
               "please continue"
             )

    assert {:ok, :already_delivered} =
             PromptDelivery.deliver(
               log_path,
               "T1",
               "R1",
               "developer",
               adapter,
               @expected,
               "please continue"
             )

    prompt_calls = Enum.filter(FakeRunner.calls(), &match?(["herdr", "agent", "prompt" | _], &1))
    assert length(prompt_calls) == 1
  end

  test "a crash between intent and delivery never resends: it looks for the text in the recent transcript",
       %{
         log_path: log_path,
         adapter: adapter
       } do
    text = "please continue"
    {:ok, _intent} = Checkpoint.append(log_path, "prompt_intent", "T1", "R1", "developer", %{})

    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @ready_agent})

      ["herdr", "agent", "prompt" | _rest] ->
        raise "must never resend a possibly-delivered prompt"

      ["herdr", "agent", "read" | _rest] ->
        {:ok, %{stdout: "...\n> #{text}\nworking...\n", stderr: "", exit_status: 0}}
    end)

    assert {:ok, :delivered} =
             PromptDelivery.deliver(log_path, "T1", "R1", "developer", adapter, @expected, text)

    assert {:ok, delivered} =
             Checkpoint.matching(log_path, "prompt_delivered", "T1", "R1", "developer")

    assert delivered["attributes"]["evidence"] == "confirmed_via_transcript"
  end

  test "ambiguous delivery with no transcript evidence parks rather than guessing either way", %{
    log_path: log_path,
    adapter: adapter
  } do
    {:ok, _intent} = Checkpoint.append(log_path, "prompt_intent", "T1", "R1", "developer", %{})

    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @ready_agent})

      ["herdr", "agent", "prompt" | _rest] ->
        raise "must never resend"

      ["herdr", "agent", "read" | _rest] ->
        {:ok, %{stdout: "nothing relevant here", stderr: "", exit_status: 0}}
    end)

    assert {:error, {:ambiguous_prompt_delivery, :not_found_in_recent_output}} =
             PromptDelivery.deliver(
               log_path,
               "T1",
               "R1",
               "developer",
               adapter,
               @expected,
               "please continue"
             )

    assert {:ok, events} = Checkpoint.events(log_path)
    assert Enum.map(events, & &1["event"]) == ["prompt_intent"]
  end
end
