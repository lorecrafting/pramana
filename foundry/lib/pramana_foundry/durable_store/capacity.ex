defmodule PramanaFoundry.DurableStore.Capacity do
  @moduledoc false

  @spec probe(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def probe(path) do
    with executable when is_binary(executable) <- System.find_executable("df"),
         {output, 0} <-
           System.cmd(executable, ["-Pk", Path.dirname(path)], stderr_to_stdout: true),
         [_filesystem, blocks, used, available, _capacity | _mount] <-
           output |> String.split("\n", trim: true) |> List.last() |> String.split(),
         {available_kib, ""} <- Integer.parse(available),
         {_blocks_kib, ""} <- Integer.parse(blocks),
         {_used_kib, ""} <- Integer.parse(used) do
      {:ok, available_kib * 1024}
    else
      nil -> {:error, :df_unavailable}
      {_output, status} -> {:error, {:df_failed, status}}
      _other -> {:error, :invalid_df_output}
    end
  rescue
    error -> {:error, {:capacity_probe_exception, error}}
  catch
    :exit, reason -> {:error, {:capacity_probe_exit, reason}}
  end
end
