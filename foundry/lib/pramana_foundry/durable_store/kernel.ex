defmodule PramanaFoundry.DurableStore.Kernel do
  @moduledoc "Pure, independently updatable workflow policy above the fixed record codec."

  alias PramanaFoundry.DurableStore.RecordCodec

  @callback decide(map(), map()) :: {:ok, map()} | {:error, term()}
  @callback apply(map(), map()) :: {:ok, map()} | {:error, term()}

  def validate_bundle(bundle) do
    with {:ok, _normalized} <- normalize_bundle(bundle), do: :ok
  end

  def normalize_bundle(bundle) do
    with {:ok, normalized} <- RecordCodec.normalize_bundle(bundle),
         :ok <- disposition_consistency(normalized) do
      {:ok, normalized}
    end
  end

  defp disposition_consistency(bundle) do
    if bundle["result"]["disposition"] in ["rejected", "blocked"] and
         Enum.any?(~w(events projections intents), &(bundle[&1] != [])),
       do: {:error, :rejected_result_has_domain_mutation},
       else: :ok
  end
end
