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
    assert is_binary(identity.state) and identity.state != ""
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
    identity = sample_identity()
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

  test "a live process whose argv contains defunct is not gone" do
    {port, identity} = marker_process("defunct-live-argv")
    on_exit(fn -> close_port(port) end)

    assert identity.command =~ "defunct-live-argv"
    refute String.starts_with?(identity.state, "Z")
    assert ProcessGroup.presence(identity) == :present
    refute ProcessGroup.gone?(identity)
  end

  test "a bound process observed in real zombie state is gone where fork is supported" do
    root =
      Path.join(System.tmp_dir!(), "process-group-zombie-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    exit_path = Path.join(root, "exit")
    reap_path = Path.join(root, "reap")

    script = """
    import os, sys, time
    child = os.fork()
    if child == 0:
        while not os.path.exists(sys.argv[1]):
            time.sleep(0.01)
        os._exit(0)
    print(child, flush=True)
    while not os.path.exists(sys.argv[2]):
        time.sleep(0.01)
    os.waitpid(child, 0)
    """

    port =
      Port.open({:spawn_executable, python_executable!()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-c", script, exit_path, reap_path]
      ])

    on_exit(fn ->
      File.touch(reap_path)
      close_port(port)
      File.rm_rf!(root)
    end)

    child_pid = receive_child_pid(port)
    assert {:ok, expected} = ProcessGroup.identity(child_pid)
    File.touch!(exit_path)

    assert await_gone(expected, 2_000)
    assert {:ok, zombie} = ProcessGroup.identity(child_pid)
    assert String.starts_with?(zombie.state, "Z")
    assert ProcessGroup.presence(expected) == :gone
  end

  test "an absent bound process is gone" do
    expected = %{sample_identity() | pid: unused_pid()}
    assert ProcessGroup.presence(expected) == :gone
    assert ProcessGroup.gone?(expected)
  end

  test "a recycled or mismatched identity is unknown and not gone" do
    expected = sample_identity()
    recycled = %{expected | started_at: "later", state: "Z", command: "[old] <defunct>"}

    identity_reader = fn _pid -> {:ok, recycled} end
    assert ProcessGroup.presence(expected, identity_reader) == :unknown
    refute ProcessGroup.gone?(expected, identity_reader)
  end

  test "an observation failure is unknown and not gone" do
    identity_reader = fn _pid -> {:error, :ps_unavailable} end
    assert ProcessGroup.presence(sample_identity(), identity_reader) == :unknown
    refute ProcessGroup.gone?(sample_identity(), identity_reader)
  end

  test "a failed signal against a live marker process remains a failure" do
    {port, identity} = marker_process("defunct-failed-signal")
    on_exit(fn -> close_port(port) end)

    command_runner = fn "kill", _args, _opts -> {"permission denied", 1} end

    assert {:error, {:kill_failed, 1}} =
             ProcessGroup.signal(identity, :sigterm, &ProcessGroup.identity/1, command_runner)

    assert {:ok, actual} = ProcessGroup.identity(identity.pid)

    assert Map.take(actual, [:pid, :process_group_id, :started_at]) ==
             Map.take(identity, [:pid, :process_group_id, :started_at])
  end

  defp self_os_pid, do: System.pid() |> String.to_integer()

  defp sample_identity do
    %{
      pid: 123,
      parent_pid: 1,
      process_group_id: 123,
      started_at: "Mon Sep 19 00:00:00 2026",
      state: "S",
      command: "sample"
    }
  end

  defp marker_process(marker) do
    port =
      Port.open({:spawn_executable, python_executable!()}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: ["-c", "import time; time.sleep(30)", marker]
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    identity = stable_identity(pid, 2_000)
    {port, identity}
  end

  defp stable_identity(pid, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    assert {:ok, identity} = ProcessGroup.identity(pid)
    await_stable_identity(pid, identity, deadline)
  end

  defp await_stable_identity(pid, previous, deadline) do
    assert {:ok, current} = ProcessGroup.identity(pid)

    cond do
      ProcessGroup.same_process?(previous, current) ->
        current

      System.monotonic_time(:millisecond) >= deadline ->
        flunk("process identity did not stabilize")

      true ->
        Process.sleep(10)
        await_stable_identity(pid, current, deadline)
    end
  end

  defp receive_child_pid(port) do
    receive do
      {^port, {:data, output}} -> output |> String.trim() |> String.to_integer()
    after
      2_000 -> flunk("zombie fixture did not publish its child pid")
    end
  end

  defp await_gone(expected, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    await_gone_until(expected, deadline)
  end

  defp await_gone_until(expected, deadline) do
    if ProcessGroup.gone?(expected) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(10)
        await_gone_until(expected, deadline)
      end
    end
  end

  defp python_executable!, do: System.find_executable("python3") || flunk("python3 unavailable")

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
  end

  defp unused_pid do
    # Near the Darwin pid ceiling and within Linux's accepted pid range.
    99_999
  end
end
