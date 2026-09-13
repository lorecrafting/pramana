defmodule PramanaFoundry.Herdr.Runner do
  @moduledoc """
  Executes an argv array and returns its decoded JSON. Every implementation must pass
  argv through to the OS without shell reinterpretation.
  """

  @type argv :: [binary()]
  @type result :: %{stdout: binary(), stderr: binary(), exit_status: non_neg_integer()}

  @callback run(argv(), keyword()) :: {:ok, result()} | {:error, term()}

  @spec decode_json(result()) :: {:ok, term()} | {:error, {:invalid_json, result()}}
  def decode_json(%{stdout: stdout} = result) do
    try do
      {:ok, :json.decode(stdout)}
    rescue
      _ -> {:error, {:invalid_json, result}}
    catch
      _, _ -> {:error, {:invalid_json, result}}
    end
  end
end

defmodule PramanaFoundry.Herdr.Runner.System do
  @moduledoc "Real Herdr runner. Requires HERDR_ENV=1, matching the Python backend."

  @behaviour PramanaFoundry.Herdr.Runner

  @impl true
  def run(argv, opts) when is_list(argv) and argv != [] do
    if System.get_env("HERDR_ENV") != "1" do
      {:error, :herdr_env_not_set}
    else
      [command | args] = argv

      case System.find_executable(command) do
        nil ->
          {:error, {:executable_not_found, command}}

        executable ->
          execute(executable, args, opts)
      end
    end
  end

  def run([], _opts), do: {:error, :empty_argv}

  defp execute(executable, args, opts) do
    timeout = Keyword.get(opts, :timeout_ms)
    port = Port.open({:spawn_executable, executable}, [:binary, :exit_status, args: args])
    collect(port, timeout, "")
  rescue
    error -> {:error, {:spawn_failed, Exception.message(error)}}
  end

  defp collect(port, timeout, acc) do
    receive do
      {^port, {:data, chunk}} ->
        collect(port, timeout, acc <> chunk)

      {^port, {:exit_status, status}} ->
        {:ok, %{stdout: acc, stderr: "", exit_status: status}}
    after
      timeout || :infinity ->
        Port.close(port)
        {:error, :timeout}
    end
  end
end
