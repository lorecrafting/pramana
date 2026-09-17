defmodule PramanaWeb.CheckAdmissionTest do
  use ExUnit.Case, async: true

  alias PramanaWeb.CheckAdmission
  alias PramanaWeb.CheckRun

  test "reader and MCP-shaped checks share one capacity and refused work never invokes callbacks" do
    admission = start_admission(1)
    parent = self()

    verify = fn _ ->
      send(parent, {:worker, self()})

      receive do
        :continue -> %{status: :verified}
      end
    end

    {_runner, id} =
      start_run(
        [verify: verify, repair: fn _ -> %{edits: []} end, admission: admission],
        5_000
      )

    assert_receive {:worker, worker}
    assert CheckAdmission.stats(admission) == %{active: 1, max_active: 1}

    callback = fn _ -> send(parent, :unexpected_capacity_work) end

    assert CheckRun.run("mcp", admission: admission, verify: callback, repair: callback) == %{
             execution: :busy,
             result: nil,
             repair: nil
           }

    reader_id = make_ref()
    deadline = System.monotonic_time(:millisecond) + 5_000

    assert CheckRun.run(self(), reader_id, "reader", deadline,
             admission: admission,
             verify: callback,
             repair: callback
           ) == %{execution: :error, result: nil, repair: nil}

    refute_received :unexpected_capacity_work
    send(worker, :continue)

    assert_receive {:check_verified, ^id, %{status: :verified}}
    assert_receive {:finished, ^id, %{execution: :completed}}, 1_000
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)

    assert CheckRun.run("after capacity",
             admission: admission,
             verify: fn _ -> %{status: :verified} end,
             repair: fn _ -> %{edits: []} end
           ).execution == :completed
  end

  test "concurrent acquisition never exceeds the configured live-permit count" do
    admission = start_admission(3)
    parent = self()

    callers =
      for n <- 1..24 do
        spawn(fn ->
          result = CheckAdmission.acquire(admission)
          send(parent, {:acquired, n, result})

          receive do
            :release ->
              case result do
                {:ok, permit} -> CheckAdmission.release(permit)
                _ -> :ok
              end
          end
        end)
      end

    results =
      for _ <- callers do
        assert_receive {:acquired, n, result}, 2_000
        {n, result}
      end

    admitted = for {n, {:ok, _permit}} <- results, do: n
    assert length(admitted) == 3
    assert CheckAdmission.stats(admission) == %{active: 3, max_active: 3}

    Enum.each(callers, &send(&1, :release))
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  test "admission-server restart preserves live reservations without linking the caller" do
    admission = start_admission(1)
    {:ok, permit} = CheckAdmission.acquire(admission)
    old_server = admission_pid(admission)
    old_ref = Process.monitor(old_server)

    Process.exit(old_server, :kill)
    assert_receive {:DOWN, ^old_ref, :process, ^old_server, :killed}

    assert eventually(fn ->
             pid = admission_pid(admission)
             is_pid(pid) and pid != old_server
           end)

    assert CheckAdmission.stats(admission) == %{active: 1, max_active: 1}
    assert CheckAdmission.acquire(admission) == {:error, :busy}
    CheckAdmission.release(permit)
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  test "an untrappable coordinator death reclaims its permit after admission restart" do
    admission = start_admission(1)
    parent = self()

    holder =
      spawn(fn ->
        {:ok, permit} = CheckAdmission.acquire(admission)
        send(parent, {:held, permit})

        receive do
          :never -> :ok
        end
      end)

    holder_ref = Process.monitor(holder)
    assert_receive {:held, _permit}
    old_server = admission_pid(admission)
    Process.exit(old_server, :kill)

    assert eventually(fn ->
             pid = admission_pid(admission)
             is_pid(pid) and pid != old_server
           end)

    assert CheckAdmission.stats(admission).active == 1
    Process.exit(holder, :kill)
    assert_receive {:DOWN, ^holder_ref, :process, ^holder, :killed}
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  test "a pending permit disappears if its issuing admission process dies before activation" do
    permit_supervisor = start_permit_supervisor()
    issuer = spawn(fn -> Process.sleep(:infinity) end)

    assert {:ok, permit} =
             DynamicSupervisor.start_child(
               permit_supervisor,
               {CheckAdmission.Permit, {self(), issuer}}
             )

    permit_ref = Process.monitor(permit)
    assert %{active: 1} = DynamicSupervisor.count_children(permit_supervisor)
    Process.exit(issuer, :kill)
    assert_receive {:DOWN, ^permit_ref, :process, ^permit, :normal}
    assert %{active: 0} = DynamicSupervisor.count_children(permit_supervisor)
  end

  test "loss of the permit supervisor stops work and leaves admission failed closed" do
    {admission, permit_supervisor} = start_admission_with_supervisor(1)
    parent = self()

    {_runner, id} =
      start_run(
        [verify: blocked(parent), repair: fn _ -> %{} end, admission: admission],
        5_000
      )

    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    supervisor_pid = global_pid(permit_supervisor)
    Process.exit(supervisor_pid, :kill)

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 3_000
    assert_receive {:finished, ^id, %{execution: :error, result: nil, repair: nil}}, 1_000
    assert eventually(fn -> CheckAdmission.stats(admission) == {:error, :unavailable} end)
    assert CheckAdmission.acquire(admission) == {:error, :unavailable}
    assert global_pid(permit_supervisor) == :undefined
  end

  test "unknown and invalid trusted admission configuration fails closed" do
    assert_raise ArgumentError, fn -> CheckAdmission.init(unknown: true) end

    for invalid <- [0, -1, 65, :infinity, nil, "4"] do
      assert_raise ArgumentError, fn -> CheckAdmission.init(max_active: invalid) end
    end
  end

  defp start_admission(max_active) do
    {admission, _permit_supervisor} = start_admission_with_supervisor(max_active)
    admission
  end

  defp start_admission_with_supervisor(max_active) do
    permit_supervisor = start_permit_supervisor()
    admission = unique_name(:admission)

    start_supervised!(
      Supervisor.child_spec(
        {CheckAdmission,
         name: admission, permit_supervisor: permit_supervisor, max_active: max_active},
        id: make_ref()
      )
    )

    {admission, permit_supervisor}
  end

  defp start_permit_supervisor do
    permit_supervisor = unique_name(:permits)

    start_supervised!(
      Supervisor.child_spec(
        {DynamicSupervisor, strategy: :one_for_one, name: permit_supervisor},
        id: make_ref(),
        restart: :temporary
      )
    )

    permit_supervisor
  end

  defp unique_name(tag), do: {:global, {__MODULE__, tag, make_ref()}}
  defp admission_pid(name), do: global_pid(name)
  defp global_pid({:global, name}), do: :global.whereis_name(name)

  defp blocked(parent) do
    fn _ ->
      Process.flag(:trap_exit, true)
      send(parent, {:worker, self()})

      receive do
        :continue -> %{}
      end
    end
  end

  defp eventually(fun, attempts \\ 100)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp start_run(opts, budget, owner \\ self()) do
    parent = self()
    id = make_ref()
    deadline = System.monotonic_time(:millisecond) + budget

    spec =
      Supervisor.child_spec(
        {Task,
         fn ->
           result = CheckRun.run(owner, id, "report", deadline, opts)
           send(parent, {:finished, id, result})
         end},
        id: id
      )

    {start_supervised!(spec), id}
  end
end
