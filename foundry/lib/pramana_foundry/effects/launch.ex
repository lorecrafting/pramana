defmodule PramanaFoundry.Effects.Launch do
  @moduledoc """
  Checkpointed agent-launch lifecycle. `launch_intent` is durably appended before the
  Herdr `agent start` call runs; `launch_completed` is appended only after Herdr's own
  identity check succeeds. A crash between those two checkpoints leaves the effect
  uncertain rather than absent: restart never calls `agent start` again for the same
  task/run/role. It inspects the live agent instead, and either adopts a matching
  ready agent exactly once or fails explicitly without creating a replacement.
  """

  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.Herdr.{Adapter, Identity}

  @type request :: %{
          required(:name) => binary(),
          required(:kind) => binary(),
          required(:pane_id) => binary(),
          required(:timeout_ms) => pos_integer(),
          optional(:native_args) => [binary()],
          optional(:opts) => keyword()
        }

  @spec launch(Path.t(), binary(), binary(), binary(), Adapter.t(), request()) ::
          {:ok, map()} | {:error, term()}
  def launch(log_path, task_id, run_id, role, adapter, request) do
    with {:ok, state} <- status(log_path, task_id, run_id, role) do
      case state do
        :not_started -> start(log_path, task_id, run_id, role, adapter, request)
        {:intent_only, _intent} -> reconcile(log_path, task_id, run_id, role, adapter, request)
        {:completed, identity} -> {:ok, identity}
      end
    end
  end

  @spec status(Path.t(), binary(), binary(), binary()) ::
          {:ok, :not_started | {:intent_only, map()} | {:completed, map()}} | {:error, term()}
  def status(log_path, task_id, run_id, role) do
    with {:ok, completed} <-
           Checkpoint.matching(log_path, "launch_completed", task_id, run_id, role) do
      case completed do
        %{"attributes" => attributes} ->
          {:ok, {:completed, attributes}}

        nil ->
          with {:ok, intent} <-
                 Checkpoint.matching(log_path, "launch_intent", task_id, run_id, role) do
            if intent, do: {:ok, {:intent_only, intent}}, else: {:ok, :not_started}
          end
      end
    end
  end

  @doc "Build the expected-identity map `Adapter.prompt/3` and `Adapter.stop/2` require."
  @spec to_expected_identity(map()) :: Adapter.expected_identity()
  def to_expected_identity(
        %{"name" => name, "pane_id" => pane_id, "terminal_id" => terminal_id} = attrs
      ) do
    %{
      name: name,
      pane_id: pane_id,
      terminal_id: terminal_id,
      session: session_token(attrs["session"])
    }
  end

  defp start(log_path, task_id, run_id, role, adapter, request) do
    opts = Map.get(request, :opts, [])

    with {:ok, _intent} <-
           Checkpoint.append(log_path, "launch_intent", task_id, run_id, role, %{
             "name" => request.name,
             "kind" => request.kind,
             "pane_id" => request.pane_id
           }),
         {:ok, _started} <-
           Adapter.start_agent(
             adapter,
             request.name,
             request.kind,
             request.pane_id,
             request.timeout_ms,
             Map.get(request, :native_args, []),
             opts
           ),
         {:ok, identity} <- Adapter.inspect_agent(adapter, request.name, opts),
         :ok <- verify_started(identity, request) do
      persist_completed(log_path, task_id, run_id, role, identity)
    end
  end

  defp reconcile(log_path, task_id, run_id, role, adapter, request) do
    opts = Map.get(request, :opts, [])

    case Adapter.inspect_agent(adapter, request.name, opts) do
      {:ok, identity} ->
        case verify_started(identity, request) do
          :ok -> persist_completed(log_path, task_id, run_id, role, identity)
          {:error, _reason} = error -> error
        end

      {:error, _reason} ->
        {:error, :ambiguous_launch}
    end
  end

  defp verify_started(%Identity{} = identity, request) do
    cond do
      identity.name != request.name -> {:error, :identity_mismatch}
      identity.pane_id != request.pane_id -> {:error, :identity_mismatch}
      not Identity.ready?(identity) -> {:error, {:not_ready, identity.status}}
      is_nil(identity.session) -> {:error, :missing_session}
      true -> :ok
    end
  end

  defp persist_completed(log_path, task_id, run_id, role, %Identity{} = identity) do
    attributes = %{
      "name" => identity.name,
      "pane_id" => identity.pane_id,
      "terminal_id" => identity.terminal_id,
      "session" => encode_session(identity.session)
    }

    with {:ok, event} <-
           Checkpoint.append(log_path, "launch_completed", task_id, run_id, role, attributes) do
      {:ok, event["attributes"]}
    end
  end

  defp encode_session(nil), do: nil

  defp encode_session(%{source: source, value: value, agent: agent} = token) do
    %{
      "source" => Atom.to_string(source),
      "value" => value,
      "agent" => agent,
      "terminal_id" => Map.get(token, :terminal_id)
    }
  end

  defp session_token(nil), do: nil

  defp session_token(%{"source" => "agent_session", "value" => value} = attrs) do
    %{
      source: :agent_session,
      value: value,
      agent: attrs["agent"],
      terminal_id: attrs["terminal_id"]
    }
  end

  defp session_token(%{"source" => "terminal", "value" => value} = attrs) do
    %{source: :terminal, value: value, agent: attrs["agent"]}
  end
end
