defmodule PramanaWeb.MCP.Reply do
  @moduledoc """
  Every tool response carries the call that produced it.

  Successful and error JSON bodies both include `bake_id`, `release_id` and
  `replay: %{tool: tool, arguments: arguments}`. Arguments retain the caller's supplied
  non-null values, not resolved defaults. MCP errors remain errors at the protocol level.

  ## Recorded provenance, not a frozen snapshot

  `bake_id` is the current source-input identity. `release_id` is the explicitly selected
  retrieval stamp. Version-2 releases digest the source identity, stable translation-row
  content/provenance and stable vector-row fields including the actual stored embedding
  bytes. Each id is `nil` until its corresponding record exists.

  Reading response metadata never creates or refreshes a stamp. If answer-producing rows
  change after selection, `Pramana.Release.drift/0` reports ordinary aggregate drift and
  can rehash a touched same-count layer when needed. The metadata lookup itself is still
  not a transactional snapshot of the tool execution, and the release does not fingerprint
  retrieval code, defaults or planner behaviour. Re-runnable is not identical historical
  replay.

  ## Stateless on purpose

  No session, trace table or accumulation. The MCP surface is read-only — tools read,
  the CLI writes. Success and error paths share one provenance helper so their metadata
  contract cannot diverge through separately maintained field lists.
  """

  alias Anubis.Server.Response

  @doc """
  Wraps a payload with the call that produced it and the recorded corpus identities.

  `arguments` is what the caller actually passed, not the tool's defaults. Metadata
  supplied by a payload is overwritten by the authoritative lookups below.
  """
  @spec json(String.t(), map(), map()) :: Response.t()
  def json(tool, arguments, payload) when is_binary(tool) and is_map(payload) do
    # A count of calls, not the duration of tool execution: the tool has already run.
    Pramana.Telemetry.emit([:pramana, :mcp, :tool], %{calls: 1}, %{tool: tool})

    payload
    |> with_provenance(tool, arguments)
    |> then(&Response.json(Response.tool(), &1))
  end

  @doc """
  An error a model can branch on, not only read.

  The JSON error body preserves the stable reason and human-readable message beside
  the same `bake_id`, `release_id` and replay metadata as a successful response.
  The MCP response retains its error flag; metadata does not turn failure into success.
  """
  @spec error(String.t(), map(), atom(), String.t()) :: Response.t()
  def error(tool, arguments, reason, message)
      when is_binary(tool) and is_atom(reason) and is_binary(message) do
    Pramana.Telemetry.emit([:pramana, :mcp, :tool], %{calls: 1}, %{tool: tool, error: reason})

    %{error: %{reason: reason, message: message}}
    |> with_provenance(tool, arguments)
    |> Jason.encode!()
    |> then(&Response.error(Response.tool(), &1))
  end

  defp with_provenance(payload, tool, arguments) do
    payload
    |> Map.put(:bake_id, Pramana.Bake.current_id())
    |> Map.put(:release_id, Pramana.Release.current_id())
    |> Map.put(:replay, %{tool: tool, arguments: normalize(arguments)})
  end

  # Struct-free and atom-keyed, so the record round-trips through JSON as what was sent.
  # A nil-valued option is dropped rather than recorded: it was not part of the call, and a
  # replay that re-sends it would pin a default that is free to change.
  defp normalize(arguments) do
    arguments
    |> Map.new(fn {k, v} -> {to_string(k), v} end)
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end
end
