defmodule PramanaFoundry.Fence do
  @moduledoc "Machine-wide advisory-file fence shared by Python and Elixir clients."

  @name_pattern ~r/\A[a-z0-9][a-z0-9_-]*\z/
  @bridge_timeout 5_000
  @python_bridge """
  import fcntl, os, sys
  path, owner = sys.argv[1], sys.argv[2]
  stream = open(path, "a+", encoding="utf-8")
  try:
      fcntl.flock(stream, fcntl.LOCK_EX | fcntl.LOCK_NB)
  except BlockingIOError:
      print("owned", flush=True)
      stream.close()
      sys.exit(2)
  os.chmod(path, 0o600)
  stream.seek(0)
  stream.truncate()
  stream.write(owner)
  stream.flush()
  os.fsync(stream.fileno())
  print("acquired", flush=True)
  sys.stdin.readline()
  fcntl.flock(stream, fcntl.LOCK_UN)
  stream.close()
  """

  defstruct [:path, :port, :owner]

  @type t :: %__MODULE__{path: Path.t(), port: port(), owner: binary()}

  @spec acquire(Path.t(), binary()) :: {:ok, t()} | {:error, term()}
  def acquire(runtime_root, name) when is_binary(runtime_root) and is_binary(name) do
    if Regex.match?(@name_pattern, name) do
      path = lock_path(runtime_root, name)
      owner = "#{System.pid()}:#{System.unique_integer([:positive, :monotonic])}"

      with :ok <- File.mkdir_p(runtime_root),
           {:ok, python} <- python_executable() do
        start_bridge(python, path, owner)
      end
    else
      {:error, :invalid_name}
    end
  end

  def acquire(_runtime_root, _name), do: {:error, :invalid_fence}

  @spec release(t()) :: :ok | {:error, term()}
  def release(%__MODULE__{path: path, port: port, owner: owner}) do
    ownership =
      case File.read(path) do
        {:ok, ^owner} -> :ok
        {:ok, _replacement} -> {:error, :replacement_owner}
        {:error, reason} -> {:error, reason}
      end

    released = release_bridge(port)

    with :ok <- ownership, :ok <- released do
      :ok
    end
  end

  defp lock_path(runtime_root, name) when name in ["coordinator", "supervisor"] do
    Path.join(runtime_root, "supervisor.lock")
  end

  defp lock_path(runtime_root, name), do: Path.join(runtime_root, name <> ".lock")

  defp python_executable do
    case System.find_executable("python3") do
      nil -> {:error, :python_not_found}
      path -> {:ok, path}
    end
  end

  defp start_bridge(python, path, owner) do
    port =
      Port.open(
        {:spawn_executable, python},
        [:binary, :exit_status, args: ["-c", @python_bridge, path, owner]]
      )

    receive do
      {^port, {:data, "acquired\n"}} ->
        {:ok, %__MODULE__{path: path, port: port, owner: owner}}

      {^port, {:data, "owned\n"}} ->
        await_exit(port)
        {:error, :owned}

      {^port, {:exit_status, status}} ->
        {:error, {:bridge_exit, status}}
    after
      @bridge_timeout ->
        close_port(port)
        {:error, :bridge_timeout}
    end
  end

  defp release_bridge(port) do
    if Port.info(port) do
      case Port.command(port, "\n") do
        true -> await_exit(port)
        false -> {:error, :bridge_closed}
      end
    else
      {:error, :bridge_closed}
    end
  end

  defp await_exit(port) do
    receive do
      {^port, {:exit_status, 0}} -> :ok
      {^port, {:exit_status, status}} -> {:error, {:bridge_exit, status}}
    after
      @bridge_timeout ->
        close_port(port)
        {:error, :bridge_timeout}
    end
  end

  defp close_port(port) do
    if Port.info(port), do: Port.close(port)
    :ok
  end
end
