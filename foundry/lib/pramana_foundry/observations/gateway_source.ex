defmodule PramanaFoundry.Observations.GatewaySource do
  @moduledoc """
  Read-only observation adapter for the FR-08A protected Gateway APIs.

  Storage and process failures are deliberately collapsed to typed availability or
  corruption codes. Raw exceptions and storage reasons never enter a public DTO.
  """

  @behaviour PramanaFoundry.Observations.Source

  alias PramanaFoundry.DurableStore.Gateway

  @sqlite_corruption_reasons MapSet.new([
                               "database disk image is malformed",
                               "file is not a database"
                             ])

  @impl true
  def snapshot(%{gateway: gateway, capability: capability}) do
    read(fn -> Gateway.protected_snapshot(gateway, capability) end)
  end

  @impl true
  def fact(%{gateway: gateway, capability: capability}, query) do
    read(fn -> Gateway.protected_query(gateway, capability, query) end)
  end

  defp read(fun) do
    observed_at = DateTime.utc_now()

    try do
      case fun.() do
        {:ok, value} when is_map(value) -> {:ok, value, observed_at}
        {:error, :not_found} -> {:error, :not_found}
        {:error, {:recovery_mode, reason}} -> classify_recovery(reason)
        {:error, {:storage_unavailable, _reason}} -> {:error, :unavailable}
        {:error, :unauthorized_protected_operation} -> {:error, :unavailable}
        {:error, _reason} -> {:error, :corrupt}
        _other -> {:error, :corrupt}
      end
    catch
      :exit, _reason -> {:error, :unavailable}
    end
  end

  defp classify_recovery({:authority_corrupt, _table, _identity, _reason}),
    do: {:error, :corrupt}

  defp classify_recovery({:protected_corrupt, _table, _identity}), do: {:error, :corrupt}
  defp classify_recovery({:protected_corrupt, _table, _identity, _reason}), do: {:error, :corrupt}

  defp classify_recovery(reason) when is_binary(reason) do
    if MapSet.member?(@sqlite_corruption_reasons, reason),
      do: {:error, :corrupt},
      else: {:error, :unavailable}
  end

  defp classify_recovery(_reason), do: {:error, :unavailable}
end
