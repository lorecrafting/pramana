defmodule PramanaFoundry.CI.FR19ASyncEIOOrchestration do
  @moduledoc false

  @default_entered_timeout 10_000
  @default_observation_ms 250
  @default_completion_timeout 10_000

  def start_pwrite_holder(path, byte_count \\ 4096, timeout \\ @default_entered_timeout)
      when is_binary(path) and is_integer(byte_count) and byte_count > 0 do
    controller = self()
    token = make_ref()
    worker = spawn(fn -> pwrite_holder(controller, token, path, byte_count) end)
    monitor = Process.monitor(worker)

    result =
      receive do
        {:fr19a_pwrite_ready, ^token, ^worker} -> {:ok, %{pid: worker, token: token}}
        {:fr19a_pwrite_open_failed, ^token, ^worker, reason} -> {:error, {:open_failed, reason}}
        {:DOWN, ^monitor, :process, ^worker, reason} -> {:error, {:worker_down, reason}}
      after
        timeout -> {:error, :holder_ready_timeout}
      end

    Process.demonitor(monitor, [:flush])

    if match?({:error, _reason}, result) and Process.alive?(worker) do
      Process.exit(worker, :kill)
    end

    result
  end

  def start_pwrite(%{pid: worker, token: token}, reply_to \\ self()) do
    send(worker, {:fr19a_pwrite_start, token, reply_to})
    :ok
  end

  def stop_pwrite_holder(%{pid: worker, token: token}, timeout \\ 3_000) do
    monitor = Process.monitor(worker)
    send(worker, {:fr19a_pwrite_close, token, self()})

    result =
      receive do
        {:fr19a_pwrite_closed, ^token, ^worker, :ok} ->
          await_holder_down(worker, monitor)

        {:fr19a_pwrite_closed, ^token, ^worker, other} ->
          _ = terminate_holder(worker, monitor)
          {:error, {:close_failed, other}}

        {:DOWN, ^monitor, :process, ^worker, _reason} ->
          :ok
      after
        timeout ->
          _ = terminate_holder(worker, monitor)
          {:error, :holder_close_timeout}
      end

    Process.demonitor(monitor, [:flush])
    result
  end

  defp await_holder_down(worker, monitor) do
    receive do
      {:DOWN, ^monitor, :process, ^worker, _reason} -> :ok
    after
      2_000 ->
        _ = terminate_holder(worker, monitor)
        {:error, :holder_exit_timeout}
    end
  end

  defp terminate_holder(worker, monitor) do
    Process.exit(worker, :kill)

    receive do
      {:DOWN, ^monitor, :process, ^worker, _reason} -> :ok
    after
      2_000 -> {:error, :holder_kill_timeout}
    end
  end

  def resume_before_await(worker, token, resume, opts \\ [])
      when is_pid(worker) and is_reference(token) and is_function(resume, 0) do
    entered_timeout = Keyword.get(opts, :entered_timeout, @default_entered_timeout)
    observation_ms = Keyword.get(opts, :observation_ms, @default_observation_ms)
    completion_timeout = Keyword.get(opts, :completion_timeout, @default_completion_timeout)
    monitor = Process.monitor(worker)

    try do
      pending_result =
        case await_entered(worker, token, monitor, entered_timeout) do
          :ok -> observe_suspended(worker, token, monitor, observation_ms)
          {:error, reason} -> {:entry_failed, reason}
        end

      case resume.() do
        :ok -> collect_after_resume(pending_result, worker, token, monitor, completion_timeout)
        other -> {:error, {:resume_failed, other}}
      end
    after
      Process.demonitor(monitor, [:flush])
    end
  end

  defp await_entered(worker, token, monitor, timeout) do
    receive do
      {:fr19a_pwrite_entered, ^token, ^worker} ->
        :ok

      {:DOWN, ^monitor, :process, ^worker, reason} ->
        {:error, {:worker_down_before_entry, reason}}
    after
      timeout -> {:error, :worker_entry_timeout}
    end
  end

  defp observe_suspended(worker, token, monitor, timeout) do
    receive do
      {:fr19a_pwrite_finished, ^token, ^worker, result} -> {:completed, result}
      {:DOWN, ^monitor, :process, ^worker, reason} -> {:worker_down, reason}
    after
      timeout -> :pending
    end
  end

  defp collect_after_resume({:completed, result}, _worker, _token, _monitor, _timeout),
    do: {:error, {:completed_while_suspended, result}}

  defp collect_after_resume({:worker_down, reason}, _worker, _token, _monitor, _timeout),
    do: {:error, {:worker_down_while_suspended, reason}}

  defp collect_after_resume({:entry_failed, reason}, _worker, _token, _monitor, _timeout),
    do: {:error, reason}

  defp collect_after_resume(:pending, worker, token, monitor, timeout) do
    receive do
      {:fr19a_pwrite_finished, ^token, ^worker, result} ->
        {:ok, result}

      {:DOWN, ^monitor, :process, ^worker, reason} ->
        {:error, {:worker_down_after_resume, reason}}
    after
      timeout -> {:error, :worker_completion_timeout}
    end
  end

  defp pwrite_holder(controller, token, path, byte_count) do
    case :file.open(String.to_charlist(path), [:read, :write, :binary, :raw]) do
      {:ok, file} ->
        case :file.pread(file, 0, byte_count) do
          {:ok, bytes} when byte_size(bytes) == byte_count ->
            send(controller, {:fr19a_pwrite_ready, token, self()})

            receive do
              {:fr19a_pwrite_start, ^token, reply_to} ->
                send(reply_to, {:fr19a_pwrite_entered, token, self()})
                result = :file.pwrite(file, 0, bytes)
                send(reply_to, {:fr19a_pwrite_finished, token, self(), result})
            end

            receive do
              {:fr19a_pwrite_close, ^token, reply_to} ->
                result = :file.close(file)
                send(reply_to, {:fr19a_pwrite_closed, token, self(), result})
            end

          other ->
            _ = :file.close(file)
            send(controller, {:fr19a_pwrite_open_failed, token, self(), {:pread, other}})
        end

      other ->
        send(controller, {:fr19a_pwrite_open_failed, token, self(), other})
    end
  end
end
