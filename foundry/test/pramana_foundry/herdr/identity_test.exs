defmodule PramanaFoundry.Herdr.IdentityTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Herdr.Identity

  test "prefers a native agent_session over the terminal fallback" do
    agent = %{"agent_session" => "sess-1", "terminal_id" => "term-1", "agent" => "claude"}

    assert Identity.session(agent) == %{
             source: :agent_session,
             value: "sess-1",
             terminal_id: "term-1",
             agent: "claude"
           }
  end

  test "falls back to the terminal+agent pair when no native session exists" do
    agent = %{"terminal_id" => "term-1", "agent" => "claude"}
    assert Identity.session(agent) == %{source: :terminal, value: "term-1", agent: "claude"}
  end

  test "no usable session when neither field is a non-empty string" do
    assert Identity.session(%{"terminal_id" => "", "agent" => "claude"}) == nil
    assert Identity.session(%{}) == nil
  end

  test "from_agent parses the identity Herdr's `agent get` returns" do
    agent = %{
      "name" => "dev-1",
      "pane_id" => "pane-1",
      "terminal_id" => "term-1",
      "agent_status" => "idle",
      "agent_session" => "sess-1",
      "agent" => "claude"
    }

    assert {:ok, identity} = Identity.from_agent(agent)
    assert identity.name == "dev-1"
    assert identity.pane_id == "pane-1"
    assert identity.terminal_id == "term-1"
    assert identity.status == "idle"
    assert Identity.ready?(identity)
  end

  test "from_agent refuses a non-object" do
    assert {:error, :invalid_agent_identity} = Identity.from_agent("not-an-object")
    assert {:error, :invalid_agent_identity} = Identity.from_agent(nil)
  end

  test "ready? is exactly idle or done" do
    assert Identity.ready?(%Identity{status: "idle"})
    assert Identity.ready?(%Identity{status: "done"})
    refute Identity.ready?(%Identity{status: "busy"})
    refute Identity.ready?(%Identity{status: nil})
  end

  test "matches_requested? requires exact name/pane/terminal and a live session" do
    identity = %Identity{
      name: "dev-1",
      pane_id: "pane-1",
      terminal_id: "term-1",
      session: %{source: :terminal, value: "term-1", agent: "claude"}
    }

    expected = %{name: "dev-1", pane_id: "pane-1", terminal_id: "term-1"}
    assert Identity.matches_requested?(identity, expected)

    refute Identity.matches_requested?(identity, %{expected | pane_id: "pane-2"})
    refute Identity.matches_requested?(%{identity | session: nil}, expected)
  end

  test "session_matches? accepts exact equality" do
    session = %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
    assert Identity.session_matches?(session, session)
    refute Identity.session_matches?(session, %{session | value: "sess-2"})
    refute Identity.session_matches?(nil, session)
  end

  test "session_matches? allows the terminal-fallback -> native-session enrichment" do
    expected = %{source: :terminal, value: "term-1", agent: "claude"}
    live = %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
    assert Identity.session_matches?(expected, live)
  end

  test "session_matches? never accepts the reverse: a recorded native session cannot silently downgrade" do
    expected = %{source: :agent_session, value: "sess-1", terminal_id: "term-1", agent: "claude"}
    live = %{source: :terminal, value: "term-1", agent: "claude"}
    refute Identity.session_matches?(expected, live)
  end

  test "session_matches? refuses enrichment for a different terminal or agent kind" do
    expected = %{source: :terminal, value: "term-1", agent: "claude"}

    other_terminal = %{
      source: :agent_session,
      value: "sess-1",
      terminal_id: "term-2",
      agent: "claude"
    }

    other_agent = %{
      source: :agent_session,
      value: "sess-1",
      terminal_id: "term-1",
      agent: "codex"
    }

    refute Identity.session_matches?(expected, other_terminal)
    refute Identity.session_matches?(expected, other_agent)
  end
end
