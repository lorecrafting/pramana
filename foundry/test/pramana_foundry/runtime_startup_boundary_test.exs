defmodule PramanaFoundry.RuntimeStartupBoundaryTest do
  use ExUnit.Case, async: false

  setup do
    parent = exclusive_parent!()
    on_exit(fn -> File.rm_rf!(parent) end)
    %{root: Path.join(parent, "runtime")}
  end

  test "actual application startup admits one OS owner and recovers after owner exit", %{
    root: root
  } do
    owner = start_owner(root)
    assert await_output(owner, "FR03_READY") =~ "FR03_READY"

    {blocked_output, blocked_status} = run_once(root, "daemon")
    assert blocked_status == 23
    assert blocked_output =~ "runtime_fence_unavailable"

    true = Port.command(owner, "stop\n")
    assert_receive {^owner, {:exit_status, 0}}, 5_000

    {successor_output, successor_status} = run_once(root, "daemon")
    assert successor_status == 0
    assert successor_output =~ "FR03_READY"
  end

  test "stale owner text is not authority and a held lock with bogus PID remains exclusive", %{
    root: root
  } do
    lock = Path.join(root, "supervisor.lock")
    {initial_output, initial_status} = run_once(root, "daemon", true)
    assert initial_status == 0
    assert initial_output =~ "FR03_READY"
    File.write!(lock, "999999:stale")

    {output, status} = run_once(root, "daemon")
    assert status == 0
    assert output =~ "FR03_READY"

    holder = start_bogus_lock_holder(root)
    assert await_output(holder, "BOGUS_READY") =~ "BOGUS_READY"

    {blocked_output, blocked_status} = run_once(root, "daemon")
    assert blocked_status == 23
    assert blocked_output =~ "runtime_fence_unavailable"
    assert File.read!(lock) == "999999:bogus"

    true = Port.command(holder, "stop\n")
    assert_receive {^holder, {:exit_status, 0}}, 5_000
  end

  test "clean release waits for the effect subtree to quiesce", %{root: root} do
    test_pid = self()
    quiesced = Path.join(Path.dirname(root), "effect-quiesced")

    effect_child = %{
      id: :fr03_effect_child,
      restart: :temporary,
      shutdown: 5_000,
      start:
        {Task, :start_link,
         [
           fn ->
             Process.flag(:trap_exit, true)
             send(test_pid, :effect_ready)

             receive do
               {:EXIT, _from, :shutdown} -> File.write!(quiesced, "quiesced")
             end
           end
         ]}
    }

    owner =
      start_supervised!(%{
        id: :fr03_runtime_owner,
        restart: :temporary,
        start:
          {PramanaFoundry.RuntimeOwner, :start_link,
           [[name: :fr03_runtime_owner, runtime_root: root, children: [effect_child]]]}
      })

    assert_receive :effect_ready
    GenServer.stop(owner, :shutdown, :infinity)
    assert File.read!(quiesced) == "quiesced"
    assert {:ok, successor} = PramanaFoundry.Fence.acquire(root, "supervisor")
    assert :ok = PramanaFoundry.Fence.release(successor)
  end

  test "killing the owning BEAM leaves fail-closed takeover evidence", %{root: root} do
    owner = start_owner(root)
    assert await_output(owner, "FR03_READY") =~ "FR03_READY"
    {:os_pid, os_pid} = Port.info(owner, :os_pid)
    {_output, 0} = System.cmd("kill", ["-KILL", Integer.to_string(os_pid)])
    assert_receive {^owner, {:exit_status, _status}}, 5_000

    {blocked_output, blocked_status} = run_once(root, "daemon")
    assert blocked_status == 23
    assert blocked_output =~ "unclean_runtime_owner"
    assert File.exists?(Path.join(root, "runtime-owner.unclean"))
    refute File.exists?(Path.join(root, "old-effect-quiesced"))
  end

  test "bridge loss quiesces the runtime and refuses automatic takeover", %{root: root} do
    owner = start_owner(root)
    assert await_output(owner, "FR03_READY") =~ "FR03_READY"
    true = Port.command(owner, "bridge\n")
    assert await_output(owner, "FR03_OWNER_DOWN") =~ "FR03_OWNER_DOWN"
    assert File.read!(Path.join(root, "old-effect-quiesced")) == "quiesced"

    {blocked_output, blocked_status} = run_once(root, "daemon")
    assert blocked_status == 23
    assert blocked_output =~ "unclean_runtime_owner"
    true = Port.command(owner, "stop\n")
    assert_receive {^owner, {:exit_status, 0}}, 5_000
  end

  test "actual client startup is effect-free", %{root: root} do
    {output, status} = run_once(root, "client", true)
    assert status == 0
    assert output =~ "FR03_CLIENT"
    assert output =~ "{nil, nil, nil}"
    refute File.exists?(Path.join(root, "supervisor.lock"))
    refute File.exists?(Path.join(root, "state/current/events.jsonl"))
  end

  test "actual application exposes recovery for retained prefix plus torn tail", %{root: root} do
    log = Path.join(root, "state/current/events.jsonl")
    File.mkdir_p!(Path.dirname(log))

    assert {:ok, _record} =
             PramanaFoundry.Effects.Checkpoint.append(
               log,
               "ticket_enqueued",
               "T-RETAINED",
               "pending",
               "system",
               %{
                 "ticket" => %{
                   "task_id" => "T-RETAINED",
                   "base_revision" => "d83f8f0cedc34780d25cba452545ce9883d416a5"
                 }
               }
             )

    File.write!(log, "{\"schema_version\":1", [:append])
    before = File.read!(log)
    {output, status} = run_recovery_once(root)

    assert status == 0
    assert output =~ "recovery_required"
    assert output =~ "unterminated_jsonl"
    assert File.read!(log) == before
  end

  test "production topology drains checked cleanup before releasing its fence", %{root: root} do
    {output, status} = run_cleanup_fixture(root <> "-success", "success")

    assert status == 0
    assert output =~ ~s(mode: "success")
    assert output =~ ~s(cleanup_events: ["cleanup_pending", "cleanup_result"])
    assert output =~ "close_called: true"
    assert output =~ "unclean_marker: false"
  end

  test "production launch boundary registers split ownership before start and resolves by exact evidence",
       %{root: root} do
    {unchanged, unchanged_status} =
      run_cleanup_fixture(root <> "-start-timeout-unchanged", "start_timeout_unchanged")

    assert unchanged_status == 0, unchanged
    assert unchanged =~ ~s(mode: "start_timeout_unchanged")
    assert unchanged =~ ~s(cleanup_events: ["cleanup_pending", "cleanup_result"])
    assert unchanged =~ "resource_events: 2"
    assert unchanged =~ ~s(resource_status: "closed")
    assert unchanged =~ ~s(durable_resource_status: "closed")
    assert unchanged =~ "start_called: true"
    assert unchanged =~ "close_called: true"
    assert unchanged =~ "unclean_marker: false"

    {replaced, replaced_status} =
      run_cleanup_fixture(root <> "-start-timeout-replaced", "start_timeout_replaced")

    assert replaced_status == 0, replaced
    assert replaced =~ ~s(mode: "start_timeout_replaced")
    assert replaced =~ ~s(cleanup_events: ["cleanup_pending", "cleanup_result"])
    assert replaced =~ "resource_events: 2"
    assert replaced =~ ~s(resource_status: "unresolved")
    assert replaced =~ ~s(durable_resource_status: "unresolved")
    assert replaced =~ "start_called: true"
    assert replaced =~ "close_called: false"
    assert replaced =~ "unclean_marker: true"
  end

  test "unverified split receipt survives malformed initial process capture", %{root: root} do
    for mode <- ~w(capture_pid_only capture_missing_generation) do
      {output, status} = run_cleanup_fixture(root <> "-" <> mode, mode)

      assert status == 0, output
      assert output =~ ~s(mode: "#{mode}")
      assert output =~ ~s(cleanup_events: ["cleanup_pending", "cleanup_result"])
      assert output =~ "resource_events: 1"
      assert output =~ ~s(resource_status: "unresolved")
      assert output =~ ~s(verification_status: "unverified")
      assert output =~ ~s(durable_resource_status: "unresolved")
      assert output =~ ~s(durable_verification_status: "unverified")
      assert output =~ "cleanup_outstanding: true"
      assert output =~ "durable_cleanup_outstanding: true"
      assert output =~ "start_called: false"
      assert output =~ "close_called: false"
      assert output =~ "unclean_marker: true"
    end
  end

  test "checked split registration failure prevents start and retains the fence", %{root: root} do
    {output, status} =
      run_cleanup_fixture(root <> "-registration-failure", "registration_failure")

    assert status == 0, output
    assert output =~ ~s(mode: "registration_failure")
    assert output =~ "cleanup_events: []"
    assert output =~ "resource_events: 0"
    assert output =~ ~s(resource_status: "unverified")
    assert output =~ ~s(verification_status: "unverified")
    assert output =~ "durable_resource_status: nil"
    assert output =~ "start_called: false"
    assert output =~ "close_called: false"
    assert output =~ "unclean_marker: true"
  end

  test "production topology preserves fail-closed evidence across cleanup failures and deadline",
       %{
         root: root
       } do
    for {mode, expected_events, close_called} <- [
          {"pending_failure", "cleanup_events: []", false},
          {"result_failure", ~s(cleanup_events: ["cleanup_pending"]), true},
          {"deadline", ~s(cleanup_events: ["cleanup_pending"]), false}
        ] do
      {output, status} = run_cleanup_fixture(root <> "-" <> mode, mode)

      assert status == 0, output
      assert output =~ ~s(mode: "#{mode}")
      assert output =~ expected_events
      assert output =~ "close_called: #{close_called}"
      assert output =~ "unclean_marker: true"
      assert [elapsed] = Regex.run(~r/elapsed_ms: (\d+)/, output, capture: :all_but_first)
      assert String.to_integer(elapsed) < 2_000
    end
  end

  test "pre-pending AgentServer deadline retains unclean evidence for a non-dispatched verdict",
       %{
         root: root
       } do
    {output, status} =
      run_cleanup_fixture(root <> "-pre-pending-deadline", "pre_pending_deadline")

    assert status == 0, output
    assert output =~ ~s(mode: "pre_pending_deadline")
    assert output =~ "cleanup_events: []"
    assert output =~ "close_called: false"
    assert output =~ "unclean_marker: true"
    assert [elapsed] = Regex.run(~r/elapsed_ms: (\d+)/, output, capture: :all_but_first)
    assert String.to_integer(elapsed) < 2_000
  end

  test "a reviewer close cannot hide a developer killed before its cleanup receipt", %{root: root} do
    {output, status} =
      run_two_resource_fixture(root <> "-two-resource-deadline", "developer_deadline")

    assert status == 0, output
    assert output =~ ~s(mode: "developer_deadline")
    assert output =~ ~s(developer_status: "owned")
    assert output =~ ~s(reviewer_status: "closed")
    assert output =~ "developer_closed: false"
    assert output =~ "reviewer_closed: true"
    assert output =~ "unclean_marker: true"
  end

  test "both role close orders permit clean release only after both terminal receipts", %{
    root: root
  } do
    for mode <- ~w(developer_first reviewer_first) do
      {output, status} = run_two_resource_fixture(root <> "-" <> mode, mode)

      assert status == 0, output
      assert output =~ ~s(mode: "#{mode}")
      assert output =~ ~s(developer_status: "closed")
      assert output =~ ~s(reviewer_status: "closed")
      assert output =~ "developer_closed: true"
      assert output =~ "reviewer_closed: true"
      assert output =~ "unclean_marker: false"
    end
  end

  defp start_owner(root) do
    Port.open(
      {:spawn_executable, mix_executable!()},
      port_options(root, "daemon", owner_code(), true)
    )
  end

  defp start_bogus_lock_holder(root) do
    code = """
    {:ok, fence} = PramanaFoundry.Fence.acquire(System.fetch_env!("PRAMANA_RUNTIME_ROOT"), "supervisor")
    File.write!(fence.path, "999999:bogus")
    IO.puts("BOGUS_READY")
    IO.read(:line)
    """

    Port.open(
      {:spawn_executable, mix_executable!()},
      port_options(root, "client", code, false)
    )
  end

  defp run_once(root, mode, fresh? \\ false) do
    code = if mode == "client", do: client_code(), else: once_code()

    System.cmd(mix_executable!(), ["run", "--no-start", "-e", code],
      cd: File.cwd!(),
      env: env(root, mode, fresh?),
      stderr_to_stdout: true
    )
  end

  defp run_recovery_once(root) do
    code = """
    {:ok, _} = Application.ensure_all_started(:pramana_foundry)
    IO.inspect(PramanaFoundry.Coordinator.status(), label: "FR03_RECOVERY_STATUS")
    IO.inspect(PramanaFoundry.Coordinator.health(), label: "FR03_RECOVERY_HEALTH")
    Application.stop(:pramana_foundry)
    """

    System.cmd(mix_executable!(), ["run", "--no-start", "-e", code],
      cd: File.cwd!(),
      env: env(root, "daemon", false),
      stderr_to_stdout: true
    )
  end

  defp run_cleanup_fixture(root, mode) do
    System.cmd(
      mix_executable!(),
      ["run", "--no-start", "test/support/runtime_cleanup_fixture.exs"],
      cd: File.cwd!(),
      env: [{"FR04_SHUTDOWN_MODE", mode} | env(root, "daemon", true)],
      stderr_to_stdout: true
    )
  end

  defp run_two_resource_fixture(root, mode) do
    System.cmd(
      mix_executable!(),
      ["run", "--no-start", "test/support/runtime_two_resource_fixture.exs"],
      cd: File.cwd!(),
      env: [{"FR04_TWO_RESOURCE_MODE", mode} | env(root, "daemon", true)],
      stderr_to_stdout: true
    )
  end

  defp port_options(root, mode, code, fresh?) do
    [
      :binary,
      :exit_status,
      :stderr_to_stdout,
      cd: File.cwd!(),
      env:
        Enum.map(env(root, mode, fresh?), fn
          {key, nil} -> {to_charlist(key), false}
          {key, value} -> {to_charlist(key), to_charlist(value)}
        end),
      args: ["run", "--no-start", "-e", code]
    ]
  end

  defp env(root, mode, fresh?) do
    [
      {"PRAMANA_OPERATOR_RUNTIME_ROOT", Path.join(Path.dirname(root), "operator-state")},
      {"PRAMANA_RUNTIME_ROOT", root},
      {"PRAMANA_RUNTIME_ROOT_FRESH", if(fresh?, do: "1", else: nil)},
      {"PRAMANA_STARTUP_MODE", mode},
      {"MIX_ENV", "dev"},
      {"HERDR_ENV", nil},
      {"COORDINATOR_TICK", nil},
      {"PATH", Path.dirname(mix_executable!()) <> ":" <> System.fetch_env!("PATH")}
    ]
  end

  defp exclusive_parent! do
    suffix = 16 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    parent = Path.join(System.tmp_dir!(), "fr03-runtime-parent-#{suffix}")

    case File.mkdir(parent) do
      :ok ->
        parent

      {:error, :eexist} ->
        exclusive_parent!()

      {:error, reason} ->
        raise File.Error, reason: reason, action: "create fixture root", path: parent
    end
  end

  defp owner_code do
    """
    case Application.ensure_all_started(:pramana_foundry) do
      {:ok, _} ->
        effect_file = Path.join(System.fetch_env!("PRAMANA_RUNTIME_ROOT"), "old-effect-quiesced")
        effect_child = %{
          id: :fr03_old_effect,
          restart: :temporary,
          shutdown: 5_000,
          start: {Task, :start_link, [fn ->
            Process.flag(:trap_exit, true)
            receive do
              {:EXIT, _from, :shutdown} -> File.write!(effect_file, "quiesced")
            end
          end]}
        }
        {:ok, _effect} = DynamicSupervisor.start_child(PramanaFoundry.AssignmentSupervisor, effect_child)
        IO.puts("FR03_READY")
        case IO.read(:line) do
          "bridge\n" ->
            owner = Process.whereis(PramanaFoundry.RuntimeOwner)
            ref = Process.monitor(owner)
            Port.close(PramanaFoundry.RuntimeOwner.bridge_port(owner))
            receive do
              {:DOWN, ^ref, :process, ^owner, _reason} -> IO.puts("FR03_OWNER_DOWN")
            end
            IO.read(:line)
          _ -> :ok
        end
        Application.stop(:pramana_foundry)
      {:error, reason} -> IO.inspect(reason); System.halt(23)
    end
    """
  end

  defp once_code do
    """
    case Application.ensure_all_started(:pramana_foundry) do
      {:ok, _} -> IO.puts("FR03_READY"); Application.stop(:pramana_foundry)
      {:error, reason} -> IO.inspect(reason); System.halt(23)
    end
    """
  end

  defp client_code do
    """
    {:ok, _} = Application.ensure_all_started(:pramana_foundry)
    IO.inspect({Process.whereis(PramanaFoundry.Coordinator), Process.whereis(PramanaFoundry.Improver), Process.whereis(PramanaFoundry.HardeningPM)}, label: "FR03_CLIENT")
    Application.stop(:pramana_foundry)
    """
  end

  defp await_output(port, marker, output \\ "") do
    receive do
      {^port, {:data, bytes}} ->
        accumulated = output <> bytes

        if String.contains?(accumulated, marker),
          do: accumulated,
          else: await_output(port, marker, accumulated)

      {^port, {:exit_status, status}} ->
        flunk("process exited #{status} before #{marker}: #{output}")
    after
      5_000 -> flunk("timed out waiting for #{marker}: #{output}")
    end
  end

  defp mix_executable! do
    path = System.get_env("FR03_MIX_EXECUTABLE") || System.find_executable("mix")

    case path && File.stat(path) do
      {:ok, %File.Stat{type: :regular, mode: mode}} when Bitwise.band(mode, 0o111) != 0 -> path
      _ -> raise "FR03_MIX_EXECUTABLE must name an executable pinned Mix binary"
    end
  end
end
