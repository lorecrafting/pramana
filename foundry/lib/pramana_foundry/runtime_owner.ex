defmodule PramanaFoundry.RuntimeOwner do
  @moduledoc """
  Continuously owns the machine-wide runtime fence.

  This process owns both the OS fence and the complete effectful runtime subtree.
  Clean shutdown stops that subtree synchronously before releasing the fence. An
  abrupt owner or bridge loss leaves durable unclean-owner evidence, so a successor
  is refused until an operator-controlled recovery protocol clears it.
  """

  use GenServer

  alias PramanaFoundry.Fence

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec owned?(GenServer.server()) :: boolean()
  def owned?(server \\ __MODULE__), do: GenServer.call(server, :owned?)

  @doc false
  def bridge_port(server \\ __MODULE__), do: GenServer.call(server, :bridge_port)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    runtime_root = Keyword.fetch!(opts, :runtime_root)
    children = Keyword.get(opts, :children, [])
    marker_path = Path.join(runtime_root, "runtime-owner.unclean")

    with {:ok, fence} <- Fence.acquire(runtime_root, "supervisor"),
         :ok <- refuse_unclean(marker_path, fence),
         :ok <- mark_unclean(marker_path),
         {:ok, subtree} <-
           Supervisor.start_link(children,
             strategy: :rest_for_one,
             name: PramanaFoundry.RuntimeSupervisor
           ) do
      {:ok, %{fence: fence, marker_path: marker_path, subtree: subtree}}
    else
      {:error, {:unclean_runtime_owner, _path} = reason} ->
        {:stop, {:runtime_fence_unavailable, reason}}

      {:error, reason} ->
        {:stop, {:runtime_fence_unavailable, reason}}
    end
  end

  @impl true
  def handle_call(:owned?, _from, %{fence: fence} = state) do
    {:reply, Fence.owned?(fence), state}
  end

  def handle_call(:bridge_port, _from, %{fence: fence} = state) do
    {:reply, fence.port, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{fence: %{port: port}} = state) do
    {:stop, {:runtime_fence_lost, status}, state}
  end

  def handle_info({:EXIT, port, reason}, %{fence: %{port: port}} = state) do
    {:stop, {:runtime_fence_lost, reason}, state}
  end

  def handle_info({:EXIT, subtree, reason}, %{subtree: subtree} = state) do
    {:stop, {:runtime_subtree_lost, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, %{fence: fence, marker_path: marker_path, subtree: subtree}) do
    stop_subtree(subtree)

    if clean_shutdown?(reason) do
      _ = File.rm(marker_path)
    end

    _ = Fence.release(fence)
    :ok
  end

  defp refuse_unclean(marker_path, fence) do
    case File.lstat(marker_path) do
      {:error, :enoent} ->
        :ok

      {:ok, _stat} ->
        _ = Fence.release(fence)
        {:error, {:unclean_runtime_owner, marker_path}}

      {:error, reason} ->
        _ = Fence.release(fence)
        {:error, {:unclean_owner_check_failed, reason}}
    end
  end

  defp mark_unclean(marker_path) do
    with :ok <- File.mkdir_p(Path.dirname(marker_path)),
         {:ok, file} <- :file.open(String.to_charlist(marker_path), [:write, :binary, :raw]),
         result <- write_marker(file),
         :ok <- :file.close(file) do
      result
    end
  end

  defp write_marker(file) do
    with :ok <- :file.write(file, "unclean runtime owner; explicit recovery required\n"),
         do: :file.sync(file)
  end

  defp stop_subtree(subtree) do
    if Process.alive?(subtree) do
      try do
        Supervisor.stop(subtree, :shutdown, :infinity)
      catch
        :exit, _reason -> :ok
      end
    end
  end

  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(_reason), do: false
end
