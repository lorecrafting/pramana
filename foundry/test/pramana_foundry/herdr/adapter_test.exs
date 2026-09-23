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

  @expected %{
    name: "dev-1",
    pane_id: "pane-1",
    terminal_id: "term-1",
    session: %{
      source: :agent_session,
      value: "sess-1",
      terminal_id: "term-1",
      agent: "claude"
    }
  }

  @pane %{
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "foreground_cwd" => "/private/tmp/shared-with-foreign-pane"
  }
  @process_info %{
    "pane_id" => "pane-1",
    "terminal_id" => "term-1",
    "shell_pid" => 101,
    "started_at" => "fixture-generation-1",
    "foreground_pid" => 202,
    "foreground_started_at" => "fixture-foreground-generation-1"
  }
  @presentation %{
    pane_id: "pane-1",
    terminal_id: "term-1",
    process_identity: %{
      pane_id: "pane-1",
      terminal_id: "term-1",
      shell_pid: 101,
      started_at: "fixture-generation-1",
      foreground_pid: 202,
      foreground_started_at: "fixture-foreground-generation-1"
    }
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

    assert {:error, {:not_an_object, "Herdr agent identity"}} =
             Adapter.inspect_agent(adapter, "dev-1")
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
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @agent})

      ["herdr", "pane", "get", "pane-1"] ->
        FakeRunner.json(%{"pane" => drifted_pane})

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        FakeRunner.json(%{"process_info" => %{"shell_pid" => 1}})
    end)

    assert {:error, :pane_identity_changed} =
             Adapter.close_pane(adapter, @expected, @presentation)

    refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "pane", "close" | _], &1))
  end

  test "close_pane closes only after exact agent, session, pane and terminal reinspection", %{
    adapter: adapter
  } do
    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @agent})

      ["herdr", "pane", "get", "pane-1"] ->
        FakeRunner.json(%{"pane" => @pane})

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        FakeRunner.json(%{"process_info" => @process_info})

      ["herdr", "pane", "close", "pane-1"] ->
        FakeRunner.json(%{"ok" => true})
    end)

    assert {:ok, _} = Adapter.close_pane(adapter, @expected, @presentation)
    assert List.last(FakeRunner.calls()) == ["herdr", "pane", "close", "pane-1"]
  end

  test "missing cleanup identity preserves the pane without inspection or close", %{
    adapter: adapter
  } do
    FakeRunner.install(fn _argv -> raise "backend must not be called" end)

    assert {:error, :missing_cleanup_identity} =
             Adapter.close_pane(
               adapter,
               %{
                 name: "dev-1",
                 pane_id: "pane-1",
                 terminal_id: "term-1",
                 session: nil
               },
               @presentation
             )

    assert FakeRunner.calls() == []
  end

  test "destructive cleanup rejects the non-native terminal fallback without backend calls", %{
    adapter: adapter
  } do
    terminal_fallback =
      put_in(@expected, [:session], %{
        source: :terminal,
        value: "term-1",
        terminal_id: "term-1",
        agent: "claude"
      })

    FakeRunner.install(fn _argv -> raise "backend must not be called" end)

    assert {:error, :missing_cleanup_identity} =
             Adapter.close_pane(adapter, terminal_fallback, @presentation)

    assert FakeRunner.calls() == []
  end

  test "fresh pane capture rejects pid-only, null, cwd-only, and malformed incarnation evidence",
       %{
         adapter: adapter
       } do
    for process_info <- [
          %{"shell_pid" => 101},
          %{"pane_id" => "pane-1", "terminal_id" => "term-1", "shell_pid" => nil},
          %{"pane_id" => "pane-1", "terminal_id" => "term-1", "foreground_cwd" => "/tmp/same"},
          %{
            "pane_id" => "pane-other",
            "terminal_id" => "term-1",
            "shell_pid" => 101,
            "started_at" => "fixture-generation-1"
          }
        ] do
      FakeRunner.install(fn
        ["herdr", "pane", "get", "pane-1"] ->
          FakeRunner.json(%{"pane" => @pane})

        ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
          FakeRunner.json(%{"process_info" => process_info})
      end)

      assert {:error, :missing_process_incarnation} =
               Adapter.capture_presentation(adapter, %{pane_id: "pane-1", terminal_id: "term-1"})
    end
  end

  test "recycled pane occupant with a replacement session survives cleanup", %{adapter: adapter} do
    replacement = %{@agent | "agent_session" => "sess-replacement"}

    FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
      FakeRunner.json(%{"agent" => replacement})
    end)

    assert {:error, :session_mismatch} = Adapter.close_pane(adapter, @expected, @presentation)
    refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "pane", "close" | _], &1))
  end

  test "name, pane, and terminal mismatches all preserve the resource", %{adapter: adapter} do
    for changed <- [
          %{@agent | "name" => "foreign"},
          %{@agent | "pane_id" => "pane-recycled"},
          %{@agent | "terminal_id" => "term-recycled"}
        ] do
      FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => changed})
      end)

      assert {:error, :identity_mismatch} =
               Adapter.close_pane(adapter, @expected, @presentation)

      refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "pane", "close" | _], &1))
    end
  end

  test "foreign pane in the same cwd is never enumerated or closed", %{adapter: adapter} do
    FakeRunner.install(fn ["herdr", "agent", "get", "dev-1"] ->
      FakeRunner.json(%{"agent" => %{@agent | "pane_id" => "foreign-pane"}})
    end)

    assert {:error, :identity_mismatch} = Adapter.close_pane(adapter, @expected, @presentation)
    calls = FakeRunner.calls()
    refute Enum.any?(calls, &match?(["herdr", "pane", "list" | _], &1))
    refute Enum.any?(calls, &match?(["herdr", "pane", "close" | _], &1))
  end

  test "replacement process behind the same pane and terminal survives cleanup", %{
    adapter: adapter
  } do
    replacement = %{@process_info | "started_at" => "fixture-generation-2"}

    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @agent})

      ["herdr", "pane", "get", "pane-1"] ->
        FakeRunner.json(%{"pane" => @pane})

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        FakeRunner.json(%{"process_info" => replacement})
    end)

    assert {:error, :pane_process_identity_changed} =
             Adapter.close_pane(adapter, @expected, @presentation)

    refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "pane", "close" | _], &1))
  end

  test "replacement foreground occupant under the same shell incarnation survives cleanup", %{
    adapter: adapter
  } do
    replacement = %{
      @process_info
      | "foreground_pid" => 303,
        "foreground_started_at" => "fixture-foreground-generation-2"
    }

    FakeRunner.install(fn
      ["herdr", "agent", "get", "dev-1"] ->
        FakeRunner.json(%{"agent" => @agent})

      ["herdr", "pane", "get", "pane-1"] ->
        FakeRunner.json(%{"pane" => @pane})

      ["herdr", "pane", "process-info", "--pane", "pane-1"] ->
        FakeRunner.json(%{"process_info" => replacement})
    end)

    assert {:error, :pane_process_identity_changed} =
             Adapter.close_pane(adapter, @expected, @presentation)

    refute Enum.any?(FakeRunner.calls(), &match?(["herdr", "pane", "close" | _], &1))
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
