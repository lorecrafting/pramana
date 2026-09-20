Code.require_file("fr19a_sync_eio_orchestration.exs", __DIR__)

defmodule PramanaFoundry.CI.FR19ARawSyncEIO do
  @moduledoc false

  alias PramanaFoundry.CI.FR19ASyncEIOOrchestration, as: Orchestration

  def main([path, host_script, state_dir, artifact_dir]) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :binary, :raw])
    {:ok, dirty_file} = :file.open(String.to_charlist(path), [:read, :write, :binary, :raw])

    try do
      block = :binary.copy("R", 4096)
      :ok = :file.write(file, block)
      :ok = :file.sync(file)
      {:ok, ^block} = :file.pread(file, 0, byte_size(block))
      {:ok, ^block} = :file.pread(dirty_file, 0, byte_size(block))

      :ok = host!(host_script, "suspend", state_dir, artifact_dir)
      parent = self()
      token = make_ref()

      dirty_worker =
        spawn(fn ->
          send(parent, {:fr19a_pwrite_entered, token, self()})
          result = :file.pwrite(dirty_file, 0, block)
          send(parent, {:fr19a_pwrite_finished, token, self(), result})
        end)

      Process.put(:fr19a_dirty_worker, dirty_worker)

      dirty_result =
        Orchestration.resume_before_await(dirty_worker, token, fn ->
          host!(host_script, "error-resume", state_dir, artifact_dir)
        end)

      case dirty_result do
        {:ok, result} -> IO.puts("RAW_DIRTY_PWRITE=#{format_result(result)}")
        {:error, reason} -> raise "raw dirty pwrite orchestration failed: #{inspect(reason)}"
      end

      case :file.sync(file) do
        {:error, :eio} ->
          IO.puts("RAW_FSYNC_ERRNO=5")
          IO.puts("RAW_SYNC_EIO=pass")
          0

        other ->
          IO.puts(:stderr, "raw fsync did not return EIO: #{inspect(other)}")
          2
      end
    after
      _ = host!(host_script, "restore", state_dir, artifact_dir)
      stop_dirty_worker()
      _ = :file.close(dirty_file)
      _ = :file.close(file)
    end
  end

  def main(_args), do: 64

  defp format_result(:ok), do: "ok"
  defp format_result({:error, reason}), do: "error:#{inspect(reason)}"
  defp format_result(other), do: inspect(other)

  defp stop_dirty_worker do
    case Process.delete(:fr19a_dirty_worker) do
      pid when is_pid(pid) ->
        monitor = Process.monitor(pid)

        unless receive_down(monitor, pid, 1_000) do
          Process.exit(pid, :kill)
          _ = receive_down(monitor, pid, 2_000)
        end

        Process.demonitor(monitor, [:flush])

      _other ->
        :ok
    end
  end

  defp receive_down(monitor, pid, timeout) do
    receive do
      {:DOWN, ^monitor, :process, ^pid, _reason} -> true
    after
      timeout -> false
    end
  end

  defp host!(script, mode, state, artifacts) do
    case System.cmd("/usr/bin/bash", [script, mode, state, artifacts], stderr_to_stdout: true) do
      {output, 0} ->
        IO.write(output)
        :ok

      {output, status} ->
        raise "host helper #{mode} failed with #{status}: #{output}"
    end
  end
end

System.halt(PramanaFoundry.CI.FR19ARawSyncEIO.main(System.argv()))
