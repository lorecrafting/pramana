defmodule PramanaFoundry.Quota do
  @moduledoc """
  Top-level Quota and cross-provider fallback facade.
  """

  alias PramanaFoundry.Quota.Cooldown
  alias PramanaFoundry.Quota.Fallback

  defdelegate record_cooldown(
                state,
                profile_name,
                provider,
                until_epoch,
                reason \\ "quota_exhaustion"
              ),
              to: Cooldown

  defdelegate active_cooldown?(state, profile_name, current_epoch), to: Cooldown
  defdelegate cooled_profiles(state, current_epoch), to: Cooldown

  defdelegate subscription_quota_signal?(signal), to: Fallback
  defdelegate can_fallback?(profile_config, signal, profiles_map), to: Fallback
  defdelegate begin_fallback(state, assignment, signal, profiles_map, opts \\ []), to: Fallback
  defdelegate release_fallback_intent(state, provider), to: Fallback
  defdelegate profile_provider(profile), to: Fallback
end
