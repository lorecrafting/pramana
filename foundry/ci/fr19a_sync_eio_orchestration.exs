defmodule PramanaFoundry.CI.FR19ASyncEIOOrchestration do
  @moduledoc false

  @default_entered_timeout 10_000
  @default_observation_ms 250
  @default_completion_timeout 10_000

  def resume_before_await(worker, token, resume, opts \\ [])
      when is_pid(worker) and is_reference(token) and is_function(resume, 0) do
    entered_timeout = Keyword.get(opts, :entered_timeout, @default_entered_timeout)
    observation_ms = Keyword.get(opts, :observation_ms, @default_observation_ms)
    completion_timeout = Keyword.get(opts, :completion_timeout, @default_completion_timeout)
    monitor = Process.monitor(worker)

    try do
      with :ok <- await_entered(worker, token, monitor, entered_timeout) do
        early_result = observe_suspended(worker, token, monitor, observation_ms)

        case resume.() do
          :ok -> collect_after_resume(early_result, worker, token, monitor, completion_timeout)
          other -> {:error, {:resume_failed, other}}
        end
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
end
