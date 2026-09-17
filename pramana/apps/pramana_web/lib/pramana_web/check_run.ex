defmodule PramanaWeb.CheckRun do
  @moduledoc """
  One short-lived report check, owned by its reader or MCP caller.

  The calling task coordinates a linked, monitored worker. Only the worker calls the
  existing verifier and repairer; the coordinator remains able to enforce a shared
  monotonic deadline and react to cancellation or owner death. It observes worker
  termination before returning, so a finished invocation cannot retain its report worker.

  This is not a durable job or a new evidence verdict. A completed verification is
  retained if subsequent repair fails. Killing the BEAM worker does not promise to
  recall work already dispatched to Postgres, a serving process or native code.
  """

  alias Pramana.Repair
  alias Pramana.Report
  alias PramanaWeb.MCP.ReplayExecutor

  # A reader resource policy, not a measured retrieval-quality threshold. Trusted
  # server configuration may shorten it; report/session parameters cannot extend it.
  @max_timeout_ms 60_000

  @type outcome :: %{
          execution: :completed | :cancelled | :timed_out | :error,
          result: map() | nil,
          repair: map() | nil
        }

  @doc "The finite page budget; invalid server configuration fails explicitly."
  @spec timeout_ms(keyword()) :: pos_integer()
  def timeout_ms(opts \\ []) do
    opts = Keyword.validate!(opts, [:timeout_ms, :verify, :repair])
    timeout = Keyword.get(opts, :timeout_ms, @max_timeout_ms)

    unless is_integer(timeout) and timeout > 0 and timeout <= @max_timeout_ms,
      do: raise(ArgumentError, "check timeout_ms must be between 1 and #{@max_timeout_ms}")

    timeout
  end

  @doc "Runs in an MCP request task without sending reader progress messages."
  @spec run(String.t(), keyword()) :: outcome()
  def run(markdown, opts) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms(opts)
    run(self(), nil, markdown, deadline, opts)
  end

  @doc "Runs in start_async, never in the LiveView callback. Options are server-owned."
  @spec run(pid(), reference() | nil, String.t(), integer(), keyword()) :: outcome()
  def run(owner, id, markdown, deadline, opts \\ []) do
    previous = Process.flag(:trap_exit, true)
    owner_ref = Process.monitor(owner)
    coordinator = self()
    verify = Keyword.get(opts, :verify, &verify/1)
    repair = Keyword.get(opts, :repair, &Repair.repair/1)

    task = Task.async(fn -> work(coordinator, markdown, deadline, verify, repair) end)

    try do
      await(%{
        owner: owner,
        owner_ref: owner_ref,
        id: id,
        task: task,
        deadline: deadline,
        result: nil
      })
    after
      # Untrappable termination, followed by a monitor acknowledgement. Do not make
      # the UI idle merely because an exit signal was sent. No persistent worker.
      Task.shutdown(task, :brutal_kill)
      Process.demonitor(owner_ref, [:flush])
      Process.flag(:trap_exit, previous)
    end
  end

  defp verify(markdown), do: Report.verify(markdown, executor: ReplayExecutor.executor())

  defp work(coordinator, markdown, deadline, verify, repair) do
    with true <- remaining(deadline) > 0,
         %{} = result <- verify.(markdown) do
      send(coordinator, {:verification, self(), result})

      receive do
        {:repair, ^coordinator} ->
          repair_within_budget(markdown, deadline, repair)
      end
    else
      false -> :timed_out
      _ -> :error
    end
  catch
    # Never publish exception text (which may contain pasted report data), nor
    # mistake an execution problem for a refuted claim. Untrappable exits are
    # handled by the task monitor in the coordinator.
    _, _ -> :error
  end

  defp repair_within_budget(markdown, deadline, repair) do
    if remaining(deadline) > 0 do
      case repair.(markdown) do
        %{} = repaired -> {:ok, repaired}
        _ -> :error
      end
    else
      :timed_out
    end
  end

  defp await(state) do
    if remaining(state.deadline) <= 0,
      do: outcome(state, :timed_out),
      else: receive_result(state)
  end

  defp receive_result(
         %{task: %{ref: ref, pid: worker}, owner: owner, owner_ref: owner_ref} = state
       ) do
    receive do
      {:verification, ^worker, result} ->
        if remaining(state.deadline) > 0 do
          if state.id, do: send(owner, {:check_verified, state.id, result})
          send(worker, {:repair, self()})
          await(%{state | result: result})
        else
          outcome(state, :timed_out)
        end

      {^ref, {:ok, repaired}} ->
        if remaining(state.deadline) > 0,
          do: %{outcome(state, :completed) | repair: repaired},
          else: outcome(state, :timed_out)

      {^ref, :timed_out} ->
        outcome(state, :timed_out)

      {^ref, :error} ->
        outcome(state, :error)

      {:DOWN, ^ref, :process, ^worker, _reason} ->
        outcome(state, :error)

      {:DOWN, ^owner_ref, :process, ^owner, _reason} ->
        outcome(state, :cancelled)

      {:EXIT, ^worker, _reason} ->
        # Task reply/DOWN is authoritative; linked EXIT is not a second result.
        await(state)

      {:EXIT, _parent, _reason} ->
        # Includes cancel_async's exit signal, normal LiveView shutdown and the
        # test supervisor's shutdown. Owner monitoring also covers an unlinked LV.
        outcome(state, :cancelled)
    after
      max(remaining(state.deadline), 0) -> outcome(state, :timed_out)
    end
  end

  defp remaining(deadline), do: deadline - System.monotonic_time(:millisecond)
  defp outcome(state, execution), do: %{execution: execution, result: state.result, repair: nil}
end
