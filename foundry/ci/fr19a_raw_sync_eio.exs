defmodule PramanaFoundry.CI.FR19ARawSyncEIO do
  @moduledoc false

  def main([path, host_script, state_dir, artifact_dir]) do
    {:ok, file} = :file.open(String.to_charlist(path), [:read, :write, :binary, :raw])

    try do
      block = :binary.copy("R", 4096)
      :ok = :file.write(file, block)
      :ok = :file.sync(file)
      {:ok, ^block} = :file.pread(file, 0, byte_size(block))

      :ok = host!(host_script, "suspend", state_dir, artifact_dir)
      :ok = :file.pwrite(file, 0, block)
      IO.puts("RAW_DIRTY_PWRITE=ok")
      :ok = host!(host_script, "error-resume", state_dir, artifact_dir)

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
      _ = :file.close(file)
    end
  end

  def main(_args), do: 64

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
