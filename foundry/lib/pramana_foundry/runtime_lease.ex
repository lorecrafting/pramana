defmodule PramanaFoundry.RuntimeLease do
  @moduledoc """
  Responsive owner of the machine-wide runtime fence and unclean marker.

  It contains no effect subtree and never synchronously waits for one. The enclosing
  `RuntimeOwner` supervisor supplies ordering: this lease starts first and stops last.
  """

  use GenServer

  alias PramanaFoundry.Fence

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @spec owned?(GenServer.server()) :: boolean()
  def owned?(server \\ __MODULE__), do: GenServer.call(server, :owned?)

  @spec allow_clean_release(GenServer.server()) :: :ok
  def allow_clean_release(server \\ __MODULE__), do: GenServer.call(server, :allow_clean_release)

  @spec inhibit_clean_release(term(), GenServer.server()) :: :ok
  def inhibit_clean_release(reason, server \\ __MODULE__),
    do: GenServer.call(server, {:inhibit_clean_release, reason})

  @doc false
  def bridge_port(server \\ __MODULE__), do: GenServer.call(server, :bridge_port)

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    runtime_root = Keyword.fetch!(opts, :runtime_root)
    marker_path = Path.join(runtime_root, "runtime-owner.unclean")

    with {:ok, fence} <- Fence.acquire(runtime_root, "supervisor"),
         :ok <- refuse_unclean(marker_path, fence),
         :ok <- mark_unclean(marker_path) do
      {:ok,
       %{fence: fence, marker_path: marker_path, clean_release?: false, blocker: :not_drained}}
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

  def handle_call(:allow_clean_release, _from, state) do
    {:reply, :ok, %{state | clean_release?: true, blocker: nil}}
  end

  def handle_call({:inhibit_clean_release, reason}, _from, state) do
    {:reply, :ok, %{state | clean_release?: false, blocker: reason}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{fence: %{port: port}} = state) do
    {:stop, {:runtime_fence_lost, status}, state}
  end

  def handle_info({:EXIT, port, reason}, %{fence: %{port: port}} = state) do
    {:stop, {:runtime_fence_lost, reason}, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl true
  def terminate(reason, %{fence: fence, marker_path: marker_path} = state) do
    if clean_shutdown?(reason) and state.clean_release?, do: _ = File.rm(marker_path)
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

  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(_reason), do: false
end
