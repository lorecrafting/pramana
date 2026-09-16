defmodule PramanaFoundry.Effects.ProcessGroupTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Effects.ProcessGroup

  @moduletag :process_group

  @doc false
  # Real termination and descendant-cleanup behaviour is exercised in
  # `PramanaFoundry.Checks.RunnerTest` against a process this suite itself spawned
  # into its own session. Nothing here ever signals a live pid: a raw `ps`-reported
  # process group for an arbitrary process could be shared with the test runner's own
  # BEAM VM, and blindly signalling it would be able to kill the test run itself.

  test "identity/1 resolves the current OS process" do
    self_pid = self_os_pid()
    assert {:ok, identity} = ProcessGroup.identity(self_pid)
    assert identity.pid == self_pid
    assert is_integer(identity.parent_pid)
    assert is_integer(identity.process_group_id)
    assert is_binary(identity.started_at) and identity.started_at != ""
    assert is_binary(identity.command) and identity.command != ""
  end

  test "identity/1 reports :not_found for a pid nothing occupies" do
    assert {:error, :not_found} = ProcessGroup.identity(unused_pid())
  end

  test "identity/1 refuses a non-positive pid" do
    assert {:error, :invalid_pid} = ProcessGroup.identity(0)
    assert {:error, :invalid_pid} = ProcessGroup.identity(-1)
  end

  test "same_process?/2 requires pid, process group, start time, and command to all agree" do
    identity = %{pid: 1, parent_pid: 0, process_group_id: 1, started_at: "a", command: "x"}
    assert ProcessGroup.same_process?(identity, identity)

    for {field, changed} <- [pid: 2, process_group_id: 2, started_at: "b", command: "y"] do
      refute ProcessGroup.same_process?(identity, Map.put(identity, field, changed)),
             "#{field} mismatch was accepted"
    end
  end

  test "same_process?/2 is false for anything that is not two identity maps" do
    refute ProcessGroup.same_process?(nil, %{pid: 1})
    refute ProcessGroup.same_process?(%{pid: 1}, nil)
  end

  defp self_os_pid, do: System.pid() |> String.to_integer()

  defp unused_pid do
    # Comfortably above any real pid space but still a plausible-looking integer.
    99_999_999
  end
end
