defmodule PramanaFoundry.Herdr.Test.FakeRunner do
  @moduledoc """
  A scripted `PramanaFoundry.Herdr.Runner` for tests, so the adapter is proved
  against fixture JSON without ever shelling out to a real `herdr`. State lives in
  the calling test process's dictionary, which is safe because every adapter call in
  these tests runs synchronously in that same process.
  """

  @behaviour PramanaFoundry.Herdr.Runner

  @script_key {__MODULE__, :script}
  @calls_key {__MODULE__, :calls}

  @spec install((PramanaFoundry.Herdr.Runner.argv() -> {:ok, term()} | {:error, term()})) :: :ok
  def install(script) when is_function(script, 1) do
    Process.put(@script_key, script)
    Process.put(@calls_key, [])
    :ok
  end

  @spec calls() :: [PramanaFoundry.Herdr.Runner.argv()]
  def calls, do: Process.get(@calls_key, []) |> Enum.reverse()

  @spec json(map()) :: {:ok, PramanaFoundry.Herdr.Runner.result()}
  def json(value) do
    {:ok, %{stdout: IO.iodata_to_binary(:json.encode(value)), stderr: "", exit_status: 0}}
  end

  @impl true
  def run(argv, _opts) do
    Process.put(@calls_key, [argv | Process.get(@calls_key, [])])

    case Process.get(@script_key) do
      nil -> {:error, :no_script_installed}
      script -> script.(argv)
    end
  end
end
