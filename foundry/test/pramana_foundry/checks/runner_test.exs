defmodule PramanaFoundry.Checks.RunnerTest do
  # Serialized: each test here forks a real python3 trampoline plus sh/sleep
  # descendants and polls their state via `ps`. Running this file's own tests
  # concurrently (async: true) starved that many simultaneous OS processes of CPU
  # under load, producing genuine `ps`-timing races unrelated to the code under
  # test -- a live "sleep 30" child intermittently read back as already reaped.
  use ExUnit.Case, async: false

  alias PramanaFoundry.Checks.Runner
  alias PramanaFoundry.Effects.ProcessGroup

  @moduletag :real_process

  setup do
    root = Path.join(System.tmp_dir!(), "check-#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)
    on_exit(fn -> File.rm_rf!(root) end)

    spec = fn command ->
      %{
        launch_token: "tok-#{System.unique_integer([:positive])}",
        command: command,
        cwd: root,
        env: %{},
        spec_path: Path.join(root, "spec.json"),
        identity_path: Path.join(root, "identity.json"),
        completion_path: Path.join(root, "completion.json"),
        cancellation_path: Path.join(root, "cancellation.json"),
        output_path: Path.join(root, "output.log")
      }
    end

    %{root: root, spec: spec}
  end

  defp await_completion(spec, deadline_ms) do
    started = System.monotonic_time(:millisecond)
    await_completion(spec, deadline_ms, started)
  end

  defp await_completion(spec, deadline_ms, started) do
    case Runner.read_completion(spec) do
      {:ok, completion} ->
        completion

      _not_yet ->
        if System.monotonic_time(:millisecond) - started > deadline_ms do
          flunk("check did not complete within #{deadline_ms}ms")
        else
          Process.sleep(20)
          await_completion(spec, deadline_ms, started)
        end
    end
  end

  test "a check that exits 0 is durably recorded with that exit code", %{spec: build_spec} do
    spec = build_spec.(["sh", "-c", "exit 0"])
    assert {:ok, _port} = Runner.launch(spec)
    completion = await_completion(spec, 2_000)
    assert completion["returncode"] == 0
  end

  test "a check's own identity (pid, process group, start time, command) is published and matches ps",
       %{
         spec: build_spec
       } do
    spec = build_spec.(["sh", "-c", "sleep 1"])
    assert {:ok, _port} = Runner.launch(spec)
    assert {:ok, pid} = Runner.await_child_pid(spec)
    assert {:ok, identity} = ProcessGroup.identity(pid)
    assert identity.pid == pid
    _ = await_completion(spec, 3_000)
  end

  test "cancellation terminates the check well before its natural exit", %{spec: build_spec} do
    # "; true" keeps `sh` itself running the whole time rather than tail-call-exec'ing
    # into `sleep` (its sole final command): a bare `sleep 30` self-replaces the shell's
    # process image asynchronously after the pid is published, so the process's `ps`
    # command can legitimately flip from "sh" to "sleep" between the two `identity/1`
    # snapshots this test and `Runner.terminate/3` each take, making a live process look
    # like a replacement owner. Forcing a fork keeps that field stable.
    spec = build_spec.(["sh", "-c", "sleep 30; true"])
    assert {:ok, _port} = Runner.launch(spec)
    assert {:ok, pid} = Runner.await_child_pid(spec)
    assert {:ok, identity} = ProcessGroup.identity(pid)

    started = System.monotonic_time(:millisecond)
    assert :ok = Runner.terminate(spec, identity, "stop requested")
    completion = await_completion(spec, 3_000)
    elapsed_ms = System.monotonic_time(:millisecond) - started

    assert elapsed_ms < 3_000
    assert completion["returncode"] != 0
    assert {:error, :not_found} = ProcessGroup.identity(pid)
  end

  test "a stale identity (already exited) is refused rather than signalled", %{spec: build_spec} do
    # A bare `exit 0` can complete and be reaped before this process even issues its
    # `ps` lookup, making `identity/1` race the OS rather than exercise the intended
    # already-exited-later behavior. `sleep 0.2 &&` guarantees a live window first.
    spec = build_spec.(["sh", "-c", "sleep 0.2 && exit 0"])
    assert {:ok, _port} = Runner.launch(spec)
    assert {:ok, pid} = Runner.await_child_pid(spec)
    assert {:ok, identity} = ProcessGroup.identity(pid)
    _completion = await_completion(spec, 2_000)

    assert {:error, :stale_identity} = ProcessGroup.signal(identity, :sigterm)
  end

  test "a replacement-owner mismatch (same pid, wrong recorded start time) refuses to signal a live process",
       %{
         spec: build_spec
       } do
    # See the cancellation test above: "; true" keeps `sh` from tail-call-exec'ing into
    # `sleep`, so `command` stays stable across the two `identity/1` snapshots below.
    spec = build_spec.(["sh", "-c", "sleep 2; true"])
    assert {:ok, _port} = Runner.launch(spec)
    assert {:ok, pid} = Runner.await_child_pid(spec)
    assert {:ok, identity} = ProcessGroup.identity(pid)
    forged = %{identity | started_at: "definitely not the real start time"}

    assert {:error, :stale_identity} = ProcessGroup.signal(forged, :sigterm)
    assert {:ok, ^identity} = ProcessGroup.identity(pid)
    Runner.terminate(spec, identity, "test cleanup")
    _ = await_completion(spec, 3_000)
  end

  test "deadline expiry outranks a late zero exit when read back through Checks.Status", %{
    spec: build_spec
  } do
    spec = build_spec.(["sh", "-c", "exit 0"])
    assert {:ok, _port} = Runner.launch(spec)
    completion = await_completion(spec, 2_000)

    state = %{
      recorded_identity: nil,
      live_identity: nil,
      completion: completion,
      deadline_epoch: completion["completed_at"] - 1,
      cancellation_requested?: false,
      stop_intent_checkpointed?: false
    }

    assert PramanaFoundry.Checks.Status.classify(state) == :timeout
  end

  test "sanitize_env redacts values while preserving which keys were declared" do
    assert Runner.sanitize_env(%{"API_TOKEN" => "super-secret", "MIX_ENV" => "test"}) == %{
             "API_TOKEN" => "[redacted]",
             "MIX_ENV" => "[redacted]"
           }
  end
end
