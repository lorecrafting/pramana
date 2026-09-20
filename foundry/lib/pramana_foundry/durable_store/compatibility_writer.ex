defmodule PramanaFoundry.DurableStore.CompatibilityWriter do
  @moduledoc """
  Narrow migration boundary for checked legacy event publishers.

  Callers must provide an opaque command ID; this module does not manufacture identity.
  It preserves the validated legacy event as a versioned domain event and does not claim
  FR-08's complete mutation/replay migration.
  """

  alias PramanaFoundry.DurableStore.{Encoding, Gateway}
  alias PramanaFoundry.Schema

  def append(gateway, actor_id, command_id, record)
      when is_binary(actor_id) and actor_id != "" and is_binary(command_id) and command_id != "" do
    with {:ok, validated} <- Schema.validate(:event, record),
         {:ok, bytes} <- Encoding.json(validated),
         event_id <- "legacy:" <> command_id,
         command <- command(command_id, Encoding.digest(bytes)),
         proposal <- proposal(event_id, validated),
         {:ok, _result, disposition} <- Gateway.transact(gateway, actor_id, command, proposal) do
      {:ok, validated, disposition}
    end
  end

  def append(_gateway, _actor_id, _command_id, _record),
    do: {:error, :invalid_compatibility_identity}

  defp command(command_id, record_digest) do
    %{
      "schema_version" => 1,
      "command_id" => command_id,
      "expected_revisions" => %{},
      "type" => "legacy_event_append",
      "target_ids" => %{},
      "payload" => %{"record_digest" => record_digest}
    }
  end

  defp proposal(event_id, validated) do
    %{
      schema_version: 1,
      result: %{schema_version: 1, disposition: "accepted", reason_code: nil},
      events: [
        %{schema_version: 1, event_id: event_id, type: "legacy_event", payload: validated}
      ]
    }
  end
end
