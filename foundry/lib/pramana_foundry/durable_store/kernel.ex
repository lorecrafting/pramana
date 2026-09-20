defmodule PramanaFoundry.DurableStore.Kernel do
  @moduledoc "Pure, independently updatable workflow policy above the fixed record codec."

  alias PramanaFoundry.DurableStore.{Encoding, RecordCodec}

  @callback decide(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply(map(), map()) :: {:ok, map()} | {:error, term()}

  @event_types ~w(legacy_event ticket_created ticket_enqueued ticket_steered ticket_paused ticket_resumed ticket_cancelled effect_requested receipt_recorded)
  @intent_types ~w(launch prompt check freeze build integrate activate cleanup git_update)

  def validate_bundle(bundle) do
    with {:ok, _normalized} <- normalize_bundle(bundle), do: :ok
  end

  def normalize_bundle(bundle) do
    with {:ok, normalized} <- RecordCodec.normalize_bundle(bundle),
         :ok <- allowed_events(normalized["events"]),
         :ok <- allowed_intents(normalized["intents"]),
         :ok <- disposition_consistency(normalized) do
      {:ok, normalized}
    end
  end

  defp allowed_events(events) do
    if Enum.all?(events, &(&1["type"] in @event_types)),
      do: :ok,
      else: {:error, :unsupported_event_type}
  end

  defp allowed_intents(intents) do
    Enum.reduce_while(intents, :ok, fn intent, :ok ->
      operation = intent["value"]["operation"]

      with true <- operation in @intent_types,
           {:ok, expected} <-
             Encoding.semantic_digest("pramana-foundry-effect-request-v1", %{
               "effect_id" => intent["effect_id"],
               "operation" => intent["value"]
             }),
           true <- intent["request_digest"] == expected do
        {:cont, :ok}
      else
        _ -> {:halt, {:error, :unsupported_intent}}
      end
    end)
  end

  defp disposition_consistency(bundle) do
    if bundle["result"]["disposition"] in ["rejected", "blocked"] and
         Enum.any?(~w(events projections intents), &(bundle[&1] != [])),
      do: {:error, :rejected_result_has_domain_mutation},
      else: :ok
  end
end
