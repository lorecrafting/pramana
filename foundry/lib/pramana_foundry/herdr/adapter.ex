defmodule PramanaFoundry.Herdr.Adapter do
  @moduledoc """
  Typed Herdr operations built from `Argv` and `Runner`. Every ownership-sensitive
  operation (prompt, interrupt/stop, close) re-inspects the live agent and refuses to
  act unless the exact name, pane, terminal, and session identity still match what the
  caller expects, mirroring the same guard the Python backend enforces before `stop`.
  """

  alias PramanaFoundry.Herdr.{Argv, Identity, Runner}

  defstruct [:runner_mod, :command]

  @type t :: %__MODULE__{runner_mod: module(), command: binary()}
  @type expected_identity :: %{
          name: binary(),
          pane_id: binary(),
          terminal_id: binary(),
          session: Identity.session_token()
        }

  @spec new(module(), binary()) :: t()
  def new(runner_mod, command \\ "herdr") when is_atom(runner_mod) and is_binary(command) do
    %__MODULE__{runner_mod: runner_mod, command: command}
  end

  @spec split_pane(t(), binary(), binary(), map(), keyword()) ::
          {:ok, %{pane_id: binary(), terminal_id: binary()}} | {:error, term()}
  def split_pane(adapter, cwd, direction, env, opts \\ []) do
    with {:ok, args} <- Argv.pane_split(cwd, direction, env),
         {:ok, decoded} <- call(adapter, args, opts),
         {:ok, pane} <- Identity.require_object(pane_result(decoded), "Herdr pane split result") do
      case pane do
        %{"pane_id" => pane_id, "terminal_id" => terminal_id}
        when is_binary(pane_id) and is_binary(terminal_id) ->
          {:ok, %{pane_id: pane_id, terminal_id: terminal_id}}

        _ ->
          {:error, :missing_pane_identity}
      end
    end
  end

  @spec start_agent(t(), binary(), binary(), binary(), pos_integer(), [binary()], keyword()) ::
          {:ok, term()} | {:error, term()}
  def start_agent(adapter, name, kind, pane_id, timeout_ms, native_args \\ [], opts \\ []) do
    with {:ok, args} <- Argv.agent_start(name, kind, pane_id, timeout_ms, native_args) do
      call(adapter, args, opts)
    end
  end

  @spec inspect_agent(t(), binary(), keyword()) :: {:ok, Identity.t()} | {:error, term()}
  def inspect_agent(adapter, target, opts \\ []) do
    with {:ok, args} <- Argv.agent_get(target),
         {:ok, decoded} <- call(adapter, args, opts),
         {:ok, agent} <- Identity.require_object(agent_result(decoded), "Herdr agent identity") do
      Identity.from_agent(agent)
    end
  end

  @spec inspect_pane(t(), binary(), keyword()) :: {:ok, map()} | {:error, term()}
  def inspect_pane(adapter, pane_id, opts \\ []) do
    with {:ok, args} <- Argv.pane_get(pane_id),
         {:ok, decoded} <- call(adapter, args, opts),
         {:ok, pane} <- Identity.require_object(pane_result(decoded), "Herdr pane identity"),
         {:ok, info_args} <- Argv.pane_process_info(pane_id),
         {:ok, info_decoded} <- call(adapter, info_args, opts),
         {:ok, process_info} <-
           Identity.require_object(
             process_info_result(info_decoded),
             "Herdr pane process info"
           ) do
      {:ok, %{pane: pane, process_info: process_info}}
    end
  end

  @spec read(t(), expected_identity(), pos_integer(), keyword()) ::
          {:ok, binary()} | {:error, term()}
  def read(adapter, expected, lines \\ 160, opts \\ []) do
    with :ok <- verify_identity(adapter, expected, opts),
         {:ok, args} <- Argv.agent_read(expected.name, lines),
         {:ok, result} <- adapter.runner_mod.run([adapter.command | args], opts) do
      {:ok, result.stdout}
    end
  end

  @spec prompt(t(), expected_identity(), binary(), keyword()) :: {:ok, term()} | {:error, term()}
  def prompt(adapter, expected, text, opts \\ []) do
    with :ok <- verify_identity(adapter, expected, opts),
         {:ok, args} <- Argv.agent_prompt(expected.name, text) do
      call(adapter, args, opts)
    end
  end

  @spec stop(t(), expected_identity(), keyword()) :: {:ok, term()} | {:error, term()}
  def stop(adapter, expected, opts \\ []) do
    with :ok <- verify_identity(adapter, expected, opts),
         {:ok, args} <- Argv.agent_send_keys(expected.name, "ctrl+c") do
      call(adapter, args, opts)
    end
  end

  @spec close_pane(t(), expected_identity(), keyword()) :: {:ok, term()} | {:error, term()}
  def close_pane(adapter, expected, opts \\ []) do
    with {:ok, pane} <- inspect_pane(adapter, expected.pane_id, opts),
         :ok <- pane_still_matches(pane, expected),
         {:ok, args} <- Argv.pane_close(expected.pane_id) do
      call(adapter, args, opts)
    end
  end

  defp pane_still_matches(
         %{pane: %{"pane_id" => pane_id, "terminal_id" => terminal_id}},
         expected
       ) do
    if pane_id == expected.pane_id and terminal_id == expected.terminal_id,
      do: :ok,
      else: {:error, :pane_identity_changed}
  end

  defp pane_still_matches(_pane, _expected), do: {:error, :pane_identity_changed}

  @doc "Re-inspects the live agent and confirms it still matches `expected` exactly."
  @spec verify_identity(t(), expected_identity(), keyword()) :: :ok | {:error, term()}
  def verify_identity(adapter, expected, opts \\ []) do
    with {:ok, identity} <- inspect_agent(adapter, expected.name, opts) do
      cond do
        not Identity.matches_requested?(identity, expected) ->
          {:error, :identity_mismatch}

        not Identity.session_matches?(expected.session, identity.session) ->
          {:error, :session_mismatch}

        true ->
          :ok
      end
    end
  end

  defp call(%__MODULE__{runner_mod: runner_mod, command: command}, args, opts) do
    with {:ok, result} <- runner_mod.run([command | args], opts),
         {:ok, decoded} <- Runner.decode_json(result) do
      {:ok, decoded}
    end
  end

  defp pane_result(decoded), do: nested(decoded, ["result", "pane"]) || get(decoded, "pane")
  defp agent_result(decoded), do: nested(decoded, ["result", "agent"]) || get(decoded, "agent")

  defp process_info_result(decoded),
    do: nested(decoded, ["result", "process_info"]) || get(decoded, "process_info")

  defp nested(map, keys), do: Enum.reduce(keys, map, fn key, acc -> get(acc, key) end)
  defp get(map, key) when is_map(map), do: Map.get(map, key)
  defp get(_map, _key), do: nil
end
