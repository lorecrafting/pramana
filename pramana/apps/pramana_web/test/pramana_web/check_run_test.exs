defmodule PramanaWeb.CheckRunTest do
  use ExUnit.Case, async: true

  alias PramanaWeb.CheckAdmission
  alias PramanaWeb.CheckRun

  test "the budget is finite and cannot be extended through server options" do
    assert CheckRun.timeout_ms() == 60_000
    assert CheckRun.timeout_ms(timeout_ms: 1) == 1
    assert_raise ArgumentError, fn -> CheckRun.timeout_ms(timeot_ms: 1) end

    for invalid <- [0, -1, :infinity, 60_001, "1000", nil] do
      assert_raise ArgumentError, fn -> CheckRun.timeout_ms(timeout_ms: invalid) end
    end
  end

  test "MCP callers can reuse the coordinator without retaining worker messages" do
    parent = self()
    original_flags = Process.info(self(), :trap_exit)
    marker = make_ref()
    send(self(), {:unrelated, marker})

    for _ <- 1..10 do
      outcome =
        CheckRun.run("report",
          verify: fn _ ->
            send(parent, {:used_worker, self()})
            %{status: :verified}
          end,
          repair: fn _ -> %{edits: []} end
        )

      assert outcome.execution == :completed
      assert outcome.result == %{status: :verified}
      assert_received {:used_worker, worker}
      refute Process.alive?(worker)
      refute_received {:EXIT, ^worker, _}
      refute_received {:verification, ^worker, _}
      refute_received {:check_verified, _, _}
      assert Process.info(self(), :trap_exit) == original_flags
    end

    assert_received {:unrelated, ^marker}
  end

  test "reader and MCP checks share one capacity and refused work never invokes callbacks" do
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
    assert CheckAdmission.stats(admission).active == 1

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

  test "capacity remains reserved across admission-server restart until the old permit releases" do
    admission = start_admission(1)
    parent = self()

    holder =
      spawn(fn ->
        Process.flag(:trap_exit, true)
        {:ok, permit} = CheckAdmission.acquire(admission)
        send(parent, {:permit, permit})

        receive do
          {:EXIT, _server, _reason} -> send(parent, :admission_restarted)
        end

        receive do
          :release -> CheckAdmission.release(admission, permit)
        end
      end)

    holder_ref = Process.monitor(holder)
    assert_receive {:permit, _permit}
    old_server = admission_pid(admission)
    old_ref = Process.monitor(old_server)
    Process.exit(old_server, :kill)
    assert_receive {:DOWN, ^old_ref, :process, ^old_server, :killed}
    assert_receive :admission_restarted

    assert eventually(fn ->
             pid = admission_pid(admission)
             is_pid(pid) and pid != old_server
           end)

    assert CheckAdmission.stats(admission) == %{active: 1, max_active: 1}
    assert CheckAdmission.acquire(admission) == {:error, :busy}

    send(holder, :release)
    assert_receive {:DOWN, ^holder_ref, :process, ^holder, :normal}
    assert eventually(fn -> CheckAdmission.stats(admission).active == 0 end)
  end

  test "completed verification and repair return only after the worker is gone" do
    parent = self()

    verify = fn _ ->
      send(parent, {:worker, self()})
      %{status: :failed}
    end

    {_runner, id} = start_run(verify: verify, repair: fn _ -> %{edits: []} end)
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    assert_receive {:check_verified, ^id, %{status: :failed}}

    assert_receive {:finished, ^id,
                    %{execution: :completed, result: %{status: :failed}, repair: %{edits: []}}}

    assert_receive {:DOWN, ^worker_ref, :process, ^worker, _}
  end

  test "a blocked verifier is killed at the deadline, not called false" do
    parent = self()
    verify = blocked(parent)

    {_runner, id} =
      start_run([verify: verify, repair: fn _ -> send(parent, :unexpected_repair) end], 1_000)

    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 3_000
    assert_receive {:finished, ^id, %{execution: :timed_out, result: nil, repair: nil}}, 1_000
    refute_received :unexpected_repair
  end

  test "repair shares the deadline and retains the completed failed verdict" do
    parent = self()
    verify = fn _ -> %{status: :failed, marker: :unchanged} end
    {_runner, id} = start_run([verify: verify, repair: blocked(parent)], 1_000)
    assert_receive {:check_verified, ^id, %{status: :failed}}
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}, 3_000

    assert_receive {:finished, ^id,
                    %{
                      execution: :timed_out,
                      result: %{status: :failed, marker: :unchanged},
                      repair: nil
                    }}
  end

  test "repair gets the remaining budget, never a fresh timeout" do
    parent = self()

    verify = fn _ ->
      send(parent, {:worker, self()})

      receive do
        :continue -> %{status: :verified}
      end
    end

    repair = fn _ ->
      send(parent, :repair_started)

      receive do
        :never_sent -> %{}
      end
    end

    {_runner, id} = start_run([verify: verify, repair: repair], 2_000)
    assert_receive {:worker, worker}
    # Deliberately consume most of the absolute budget, with a mailbox timer rather
    # than sleeping or racing a completion. A fresh 2 s repair timer would fail.
    Process.send_after(worker, :continue, 1_200)
    assert_receive :repair_started, 1_800
    assert_receive {:finished, ^id, %{execution: :timed_out, result: %{status: :verified}}}, 1_200
  end

  test "owner death with an abnormal reason also stops exit-trapping work" do
    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :never -> :ok
           end
         end}
      )

    owner_ref = Process.monitor(owner)
    {_runner, id} = start_run([verify: blocked(self()), repair: fn _ -> %{} end], 5_000, owner)
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    Process.exit(owner, :kill)
    assert_receive {:DOWN, ^owner_ref, :process, ^owner, :killed}
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}
    assert_receive {:finished, ^id, %{execution: :cancelled, result: nil}}
  end

  test "an expired admission does not invoke either callback" do
    parent = self()
    callback = fn _ -> send(parent, :unexpected_work) end
    {_runner, id} = start_run([verify: callback, repair: callback], -1)
    assert_receive {:finished, ^id, %{execution: :timed_out, result: nil}}
    refute_received :unexpected_work
  end

  test "cancel signal kills even an exit-trapping worker before completion is reported" do
    parent = self()
    {runner, id} = start_run(verify: blocked(parent), repair: fn _ -> %{} end)
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    Process.exit(runner, {:shutdown, :cancel})
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}
    assert_receive {:finished, ^id, %{execution: :cancelled, result: nil, repair: nil}}
  end

  test "an unlinked owner exiting normally still stops its worker" do
    owner =
      start_supervised!(
        {Task,
         fn ->
           receive do
             :leave -> :ok
           end
         end}
      )

    parent = self()
    {_runner, id} = start_run([verify: blocked(parent), repair: fn _ -> %{} end], 5_000, owner)
    assert_receive {:worker, worker}
    worker_ref = Process.monitor(worker)
    send(owner, :leave)
    assert_receive {:DOWN, ^worker_ref, :process, ^worker, :killed}
    assert_receive {:finished, ^id, %{execution: :cancelled, result: nil}}
  end

  test "worker exceptions, throws and exits are execution errors, not report verdicts" do
    for failing <- [
          fn _ -> raise "private report" end,
          fn _ -> throw(:private_report) end,
          fn _ -> exit(:private_report) end
        ] do
      {_runner, id} = start_run(verify: failing, repair: fn _ -> %{} end)
      assert_receive {:finished, ^id, %{execution: :error, result: nil, repair: nil}}
    end
  end

  test "repair failure cannot overwrite an already completed verdict" do
    {_runner, id} =
      start_run(
        verify: fn _ -> %{status: :verified} end,
        repair: fn _ -> raise "private report" end
      )

    assert_receive {:check_verified, ^id, %{status: :verified}}

    assert_receive {:finished, ^id,
                    %{execution: :error, result: %{status: :verified}, repair: nil}}
  end

  test "untrappable worker death is contained by the coordinator" do
    parent = self()
    {_runner, id} = start_run(verify: blocked(parent), repair: fn _ -> %{} end)
    assert_receive {:worker, worker}
    Process.exit(worker, :kill)
    assert_receive {:finished, ^id, %{execution: :error, result: nil, repair: nil}}
  end

  defp blocked(parent) do
    fn _ ->
      Process.flag(:trap_exit, true)
      send(parent, {:worker, self()})

      receive do
        :continue -> %{}
      end
    end
  end

  defp start_admission(max_active) do
    key = make_ref()
    name = {:global, {__MODULE__, key}}

    spec =
      Supervisor.child_spec(
        {CheckAdmission, name: name, counter_key: {__MODULE__, key}, max_active: max_active},
        id: key
      )

    start_supervised!(spec)
    name
  end

  defp admission_pid({:global, name}), do: :global.whereis_name(name)

  defp eventually(fun, attempts \\ 50)
  defp eventually(fun, 0), do: fun.()

  defp eventually(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(10)
      eventually(fun, attempts - 1)
    end
  end

  defp start_run(opts, budget \\ 5_000, owner \\ self()) do
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
