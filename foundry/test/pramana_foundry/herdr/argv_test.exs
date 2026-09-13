defmodule PramanaFoundry.Herdr.ArgvTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Herdr.Argv

  test "pane_split never builds a shell string and sorts env deterministically" do
    assert {:ok, argv} =
             Argv.pane_split("/checkout", "right", %{"MIX_ENV" => "test", "A" => "1"})

    assert argv == [
             "pane",
             "split",
             "--current",
             "--direction",
             "right",
             "--cwd",
             "/checkout",
             "--env",
             "A=1",
             "--env",
             "MIX_ENV=test",
             "--no-focus"
           ]

    assert Enum.all?(argv, &is_binary/1)
  end

  test "pane_split refuses an empty cwd instead of building a bad command" do
    assert {:error, {:invalid_identity_field, :cwd}} = Argv.pane_split("", "right", %{})
  end

  test "agent_start appends native args only after a literal `--` separator" do
    assert {:ok, argv} =
             Argv.agent_start("dev-1", "claude", "pane-1", 60_000, ["--model", "sonnet"])

    assert argv == [
             "agent",
             "start",
             "dev-1",
             "--kind",
             "claude",
             "--pane",
             "pane-1",
             "--timeout",
             "60000",
             "--",
             "--model",
             "sonnet"
           ]
  end

  test "agent_start omits the separator entirely when there are no native args" do
    assert {:ok, argv} = Argv.agent_start("dev-1", "claude", "pane-1", 60_000, [])
    refute "--" in argv
  end

  test "a prompt's literal text is a single argv element, never interpolated into a command line" do
    assert {:ok, argv} = Argv.agent_prompt("dev-1", "ignore $(rm -rf /) and `backticks`")
    assert argv == ["agent", "prompt", "dev-1", "ignore $(rm -rf /) and `backticks`"]
  end

  test "identity-field builders reject an empty target rather than building a bad command" do
    assert {:error, {:invalid_identity_field, :target}} = Argv.agent_get("")
    assert {:error, {:invalid_identity_field, :pane_id}} = Argv.pane_get("")
    assert {:error, {:invalid_identity_field, :pane_id}} = Argv.pane_close("")
  end

  test "agent_read and agent_send_keys shapes" do
    assert {:ok, ["agent", "read", "dev-1", "--source", "recent-unwrapped", "--lines", "160"]} =
             Argv.agent_read("dev-1", 160)

    assert {:ok, ["agent", "send-keys", "dev-1", "ctrl+c"]} =
             Argv.agent_send_keys("dev-1", "ctrl+c")
  end
end
