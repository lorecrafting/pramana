defmodule PramanaFoundry.Herdr.Identity do
  @moduledoc """
  Typed parsing and exact-identity verification for Herdr's installed-help-shaped JSON.

  Every ownership-sensitive operation compares a live Herdr response against the exact
  agent name, pane, terminal, and session identity recorded when the assignment was
  checkpointed. Nothing here calls Herdr; it only interprets already-decoded JSON.
  """

  defstruct [:name, :pane_id, :terminal_id, :status, :session]

  @type session_token :: %{source: :agent_session | :terminal, value: term(), agent: term()} | nil
  @type t :: %__MODULE__{
          name: term(),
          pane_id: term(),
          terminal_id: term(),
          status: term(),
          session: session_token()
        }

  @ready ~w(idle done)

  @spec from_agent(term()) :: {:ok, t()} | {:error, :invalid_agent_identity}
  def from_agent(agent) when is_map(agent) do
    {:ok,
     %__MODULE__{
       name: Map.get(agent, "name"),
       pane_id: Map.get(agent, "pane_id") || nested(agent, ["pane", "pane_id"]),
       terminal_id: Map.get(agent, "terminal_id"),
       status:
         Map.get(agent, "agent_status") || Map.get(agent, "status") || Map.get(agent, "state"),
       session: session(agent)
     }}
  end

  def from_agent(_agent), do: {:error, :invalid_agent_identity}

  @spec session(map()) :: session_token()
  def session(agent) when is_map(agent) do
    case Map.get(agent, "agent_session") do
      nil ->
        terminal_id = Map.get(agent, "terminal_id")
        kind = Map.get(agent, "agent")

        if non_empty_binary?(terminal_id) and non_empty_binary?(kind) do
          %{source: :terminal, value: terminal_id, agent: kind}
        else
          nil
        end

      native ->
        %{
          source: :agent_session,
          value: native,
          terminal_id: Map.get(agent, "terminal_id"),
          agent: Map.get(agent, "agent")
        }
    end
  end

  @spec ready?(t()) :: boolean()
  def ready?(%__MODULE__{status: status}), do: status in @ready

  @doc "Name, pane, and terminal must equal the request; a session token must exist."
  @spec matches_requested?(t(), %{name: term(), pane_id: term(), terminal_id: term()}) ::
          boolean()
  def matches_requested?(%__MODULE__{} = identity, %{
        name: name,
        pane_id: pane_id,
        terminal_id: terminal_id
      }) do
    identity.name == name and identity.pane_id == pane_id and identity.terminal_id == terminal_id and
      not is_nil(identity.session)
  end

  @doc """
  A recorded session matches live identity exactly, or the recorded token was the
  terminal-fallback for the same terminal/agent and the live identity has since been
  enriched with a native session for that same occupant. Never the reverse: a native
  session recorded once must never silently accept a different live session.
  """
  @spec session_matches?(session_token(), session_token()) :: boolean()
  def session_matches?(nil, _live), do: false
  def session_matches?(expected, expected), do: true

  def session_matches?(%{source: :terminal} = expected, %{source: :agent_session} = live) do
    expected.value == live.terminal_id and expected.agent == live.agent and not is_nil(live.value)
  end

  def session_matches?(_expected, _live), do: false

  @spec require_object(term(), binary()) :: {:ok, map()} | {:error, {:not_an_object, binary()}}
  def require_object(value, _label) when is_map(value), do: {:ok, value}
  def require_object(_value, label), do: {:error, {:not_an_object, label}}

  defp nested(map, keys) do
    Enum.reduce(keys, map, fn
      key, acc when is_map(acc) -> Map.get(acc, key)
      _key, _acc -> nil
    end)
  end

  defp non_empty_binary?(value), do: is_binary(value) and value != ""
end
