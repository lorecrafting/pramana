defmodule PramanaFoundry.Quota.Cooldown do
  @moduledoc """
  Durable provider and profile cooldown tracking under virtual or real time.
  """

  @doc """
  Records a cooldown for a profile and its provider until until_epoch.
  """
  def record_cooldown(state, profile_name, provider, until_epoch, reason \\ "quota_exhaustion") do
    cooldowns = Map.get(state, "provider_cooldowns", %{})

    entry = %{
      "profile" => profile_name,
      "provider" => provider,
      "until_epoch" => until_epoch,
      "reason" => reason,
      "recorded_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    updated_cooldowns = Map.put(cooldowns, profile_name, entry)
    Map.put(state, "provider_cooldowns", updated_cooldowns)
  end

  @doc """
  Checks whether a profile is in an active cooldown at the given epoch time.
  """
  def active_cooldown?(state, profile_name, current_epoch) do
    case get_in(state, ["provider_cooldowns", profile_name]) do
      %{"until_epoch" => until_epoch} -> current_epoch < until_epoch
      _ -> false
    end
  end

  @doc """
  Returns all profiles currently under active cooldown at the given epoch time.
  """
  def cooled_profiles(state, current_epoch) do
    cooldowns = Map.get(state, "provider_cooldowns", %{})

    cooldowns
    |> Enum.filter(fn {_name, entry} -> Map.get(entry, "until_epoch", 0) > current_epoch end)
    |> Enum.map(&elem(&1, 0))
  end
end
