defmodule PramanaFoundry.Herdr.Adapter do
  @moduledoc """
  Typed Herdr operations built from `Argv` and `Runner`. Every ownership-sensitive
  operation (prompt, interrupt/stop, close) re-inspects the live agent and refuses to
  act unless the exact name, pane, terminal, and session identity still match what the
  caller expects, mirroring the same guard the Python backend enforces before `stop`.

  Destructive pane cleanup additionally requires a backend process-incarnation
  contract: `pane_id` and `terminal_id` linked to the inspected pane, a positive
  `shell_pid`, a non-empty opaque `started_at` shell generation, a positive
  `foreground_pid`, and a non-empty opaque `foreground_started_at` generation.
  PID-only or synthetic observation-time evidence is unsupported and therefore
  preserves the resource.
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
  @type presentation_identity :: %{
          pane_id: binary(),
          terminal_id: binary(),
          process_identity: map()
        }

  @spec new(module(), binary()) :: t()
  def new(runner_mod, command \\ "herdr") when is_atom(runner_mod) and is_binary(command) do
    %__MODULE__{runner_mod: runner_mod, command: command}
  end

  @doc "Whether this backend enforces the selected route as subscription-only."
  @spec subscription_route_enforced?(t(), keyword()) :: boolean()
  def subscription_route_enforced?(adapter, opts \\ [])

  def subscription_route_enforced?(%__MODULE__{runner_mod: runner_mod}, opts) do
    case Code.ensure_loaded(runner_mod) do
      {:module, ^runner_mod} ->
        function_exported?(runner_mod, :subscription_route_capability, 1) and
          runner_mod.subscription_route_capability(opts) == :enforced

      _ ->
        false
    end
  rescue
    _ -> false
  catch
    _, _ -> false
  end

  def subscription_route_enforced?(_adapter, _opts), do: false

  @spec require_subscription_route(t(), keyword()) ::
          :ok | {:error, :subscription_route_not_enforced}
  def require_subscription_route(adapter, opts \\ []) do
    if subscription_route_enforced?(adapter, opts),
      do: :ok,
      else: {:error, :subscription_route_not_enforced}
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

  @doc "Captures the pane/process identity that must still match before cleanup."
  @spec capture_presentation(t(), %{pane_id: binary(), terminal_id: binary()}, keyword()) ::
          {:ok, presentation_identity()} | {:error, term()}
  def capture_presentation(adapter, expected, opts \\ []) do
    with :ok <- require_fresh_pane_identity(expected),
         {:ok, inspected} <- inspect_pane(adapter, expected.pane_id, opts),
         :ok <- pane_still_matches(inspected, expected),
         {:ok, process_identity} <-
           process_identity(inspected.process_info, expected.pane_id, expected.terminal_id) do
      {:ok, Map.put(expected, :process_identity, process_identity)}
    end
  end

  @spec close_pane(t(), expected_identity(), presentation_identity(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def close_pane(adapter, expected, presentation, opts \\ []) do
    with :ok <- require_complete_identity(expected),
         :ok <- require_presentation_identity(presentation),
         :ok <- verify_cleanup_identity(adapter, expected, opts),
         {:ok, pane} <- inspect_pane(adapter, expected.pane_id, opts),
         :ok <- presentation_still_matches(pane, presentation),
         {:ok, args} <- Argv.pane_close(expected.pane_id) do
      call(adapter, args, opts)
    end
  end

  @doc "Closes only a still-matching pre-agent process incarnation captured immediately after split."
  @spec close_fresh_pane(t(), presentation_identity(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def close_fresh_pane(adapter, expected, opts \\ []) do
    with :ok <- require_presentation_identity(expected),
         {:ok, pane} <- inspect_pane(adapter, expected.pane_id, opts),
         :ok <- presentation_still_matches(pane, expected),
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

  defp presentation_still_matches(%{process_info: process_info} = inspected, expected) do
    with :ok <- pane_still_matches(inspected, expected),
         {:ok, live_identity} <-
           process_identity(process_info, expected.pane_id, expected.terminal_id) do
      if live_identity == expected.process_identity,
        do: :ok,
        else: {:error, :pane_process_identity_changed}
    end
  end

  defp require_complete_identity(%{
         name: name,
         pane_id: pane_id,
         terminal_id: terminal_id,
         session: session
       })
       when is_binary(name) and name != "" and is_binary(pane_id) and pane_id != "" and
              is_binary(terminal_id) and terminal_id != "" do
    if Identity.cleanup_session?(session), do: :ok, else: {:error, :missing_cleanup_identity}
  end

  defp require_complete_identity(_expected), do: {:error, :missing_cleanup_identity}

  defp require_fresh_pane_identity(%{pane_id: pane_id, terminal_id: terminal_id})
       when is_binary(pane_id) and pane_id != "" and is_binary(terminal_id) and
              terminal_id != "",
       do: :ok

  defp require_fresh_pane_identity(_expected), do: {:error, :missing_cleanup_identity}

  defp require_presentation_identity(%{
         pane_id: pane_id,
         terminal_id: terminal_id,
         process_identity: process_identity
       })
       when is_binary(pane_id) and pane_id != "" and is_binary(terminal_id) and
              terminal_id != "" and is_map(process_identity),
       do: :ok

  defp require_presentation_identity(_expected), do: {:error, :missing_cleanup_identity}

  defp process_identity(
         %{
           "pane_id" => pane_id,
           "terminal_id" => terminal_id,
           "shell_pid" => shell_pid,
           "started_at" => started_at,
           "foreground_pid" => foreground_pid,
           "foreground_started_at" => foreground_started_at
         },
         pane_id,
         terminal_id
       )
       when is_integer(shell_pid) and shell_pid > 0 and is_binary(started_at) and
              started_at != "" and is_integer(foreground_pid) and foreground_pid > 0 and
              is_binary(foreground_started_at) and foreground_started_at != "" do
    {:ok,
     %{
       pane_id: pane_id,
       terminal_id: terminal_id,
       shell_pid: shell_pid,
       started_at: started_at,
       foreground_pid: foreground_pid,
       foreground_started_at: foreground_started_at
     }}
  end

  defp process_identity(_process_info, _pane_id, _terminal_id),
    do: {:error, :missing_process_incarnation}

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

  defp verify_cleanup_identity(adapter, expected, opts) do
    with {:ok, identity} <- inspect_agent(adapter, expected.name, opts) do
      cond do
        not Identity.matches_requested?(identity, expected) ->
          {:error, :identity_mismatch}

        not Identity.cleanup_session_matches?(expected.session, identity.session) ->
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
