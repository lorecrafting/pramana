Code.require_file("fr19a_sync_eio_orchestration.exs", __DIR__)

defmodule PramanaFoundry.CI.FR19ARawSyncEIO do
  @moduledoc false

  alias PramanaFoundry.CI.FR19ASyncEIOOrchestration, as: Orchestration

  def main([path, host_script, state_dir, artifact_dir]) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :binary, :raw])

    try do
      block = :binary.copy("R", 4096)
      :ok = :file.write(file, block)
      :ok = :file.sync(file)
      {:ok, ^block} = :file.pread(file, 0, byte_size(block))
      {:ok, dirty_holder} = Orchestration.start_pwrite_holder(path, byte_size(block))
      Process.put(:fr19a_dirty_holder, dirty_holder)

      :ok = host!(host_script, "suspend", state_dir, artifact_dir)
      :ok = Orchestration.start_pwrite(dirty_holder)

      dirty_result =
        Orchestration.resume_before_await(dirty_holder.pid, dirty_holder.token, fn ->
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
      restore_result = safe_restore(host_script, state_dir, artifact_dir)
      stop_dirty_holder()
      _ = :file.close(file)

      case restore_result do
        :ok -> :ok
        {:error, error, stacktrace} -> reraise error, stacktrace
      end
    end
  end

  def main(_args), do: 64

  defp format_result(:ok), do: "ok"
  defp format_result({:error, reason}), do: "error:#{inspect(reason)}"
  defp format_result(other), do: inspect(other)

  defp stop_dirty_holder do
    case Process.delete(:fr19a_dirty_holder) do
      %{pid: _pid, token: _token} = holder -> Orchestration.stop_pwrite_holder(holder)
      _other -> :ok
    end
  end

  defp safe_restore(host_script, state_dir, artifact_dir) do
    host!(host_script, "restore", state_dir, artifact_dir)
  rescue
    error -> {:error, error, __STACKTRACE__}
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
