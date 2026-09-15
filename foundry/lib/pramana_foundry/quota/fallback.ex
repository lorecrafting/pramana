defmodule PramanaFoundry.Quota.Fallback do
  @moduledoc """
  Symmetric Codex ↔ Claude subscription cross-provider fallback policy and continuation management.
  """

  alias PramanaFoundry.Quota.Cooldown

  @cross_provider_fallback_signals ~w(provider_quota_reached usage_limit_reached weekly_limit_reached)
  @allowed_provider_pair MapSet.new(["anthropic", "openai-codex"])
  @reasoning_ranks %{"low" => 0, "medium" => 1, "high" => 2}

  @doc """
  Checks whether a signal is an authorized subscription quota exhaustion signal.
  """
  def subscription_quota_signal?(signal) when is_binary(signal) do
    signal in @cross_provider_fallback_signals
  end

  def subscription_quota_signal?(_), do: false

  @doc """
  Evaluates whether a profile can fall back given the quota signal and profiles config.
  """
  def can_fallback?(profile_config, signal, profiles_map) do
    if not subscription_quota_signal?(signal) do
      {:error, :unauthorized_signal}
    else
      fallbacks = Map.get(profile_config, "fallback_profiles", [])

      case fallbacks do
        [] ->
          {:error, :no_fallback_profiles_configured}

        [fallback_name | _] ->
          fallback_config = Map.get(profiles_map, fallback_name)

          cond do
            not is_map(fallback_config) ->
              {:error, :unknown_fallback_profile}

            Map.get(fallback_config, "subscription_authorized") != true ->
              {:error, :fallback_not_subscription_authorized}

            Map.get(fallback_config, "premium_authorized") == true ->
              {:error, :fallback_cannot_use_premium_model}

            true ->
              source_provider = profile_provider(profile_config)
              target_provider = profile_provider(fallback_config)
              pair = MapSet.new([source_provider, target_provider])

              cond do
                pair != @allowed_provider_pair ->
                  {:error, :fallback_must_be_cross_provider_codex_claude}

                not reasoning_maintained?(profile_config, fallback_config) ->
                  {:error, :fallback_cannot_use_weaker_reasoning}

                true ->
                  {:ok, fallback_name, fallback_config, source_provider, target_provider}
              end
          end
      end
    end
  end

  defp reasoning_maintained?(source, target) do
    src_rank = Map.get(@reasoning_ranks, Map.get(source, "reasoning", "medium"), 1)
    tgt_rank = Map.get(@reasoning_ranks, Map.get(target, "reasoning", "medium"), 1)
    tgt_rank >= src_rank
  end

  def profile_provider(profile) when is_map(profile) do
    model_id = String.downcase(to_string(Map.get(profile, "model_id", "")))

    cond do
      String.starts_with?(model_id, "anthropic") or String.contains?(model_id, "claude") ->
        "anthropic"

      String.starts_with?(model_id, "openai-codex") or String.contains?(model_id, "codex") ->
        "openai-codex"

      String.starts_with?(model_id, "google") or String.contains?(model_id, "gemini") ->
        "google"

      true ->
        "unknown"
    end
  end

  @doc """
  Initiates a cross-provider quota fallback continuation for an assignment or PM.
  """
  def begin_fallback(state, assignment, signal, profiles_map, opts \\ []) do
    ticket = Map.get(assignment, "ticket", assignment)
    role = Map.get(assignment, "role", "developer")
    profile_name = Map.get(ticket, "profile", Map.get(assignment, "profile"))
    profile_config = Map.get(profiles_map, profile_name, %{})

    case can_fallback?(profile_config, signal, profiles_map) do
      {:ok, fallback_name, fallback_config, source_provider, target_provider} ->
        intents = Map.get(state, "provider_fallback_intents", %{})

        if Map.has_key?(intents, source_provider) do
          # Already has an in-flight fallback intent! Suppress this provider.
          cooldown_duration = Keyword.get(opts, :cooldown_duration, 300)
          now = Keyword.get(opts, :now, System.system_time(:second))

          updated_state =
            Cooldown.record_cooldown(
              state,
              profile_name,
              source_provider,
              now + cooldown_duration,
              "provider already has an in-flight fallback intent"
            )

          {:error, :provider_in_flight_intent_exists, updated_state}
        else
          old_run_id = Map.get(assignment, "run_id", "run-prev")
          new_run_id = Keyword.get(opts, :new_run_id, generate_run_id())
          now = Keyword.get(opts, :now, System.system_time(:second))
          cooldown_until = Keyword.get(opts, :source_cooldown_until, now + 3600)

          intent = %{
            "task_id" => Map.get(ticket, "task_id", ""),
            "previous_run_id" => old_run_id,
            "current_run_id" => new_run_id,
            "source_provider" => source_provider,
            "target_provider" => target_provider,
            "source_profile" => profile_name,
            "target_profile" => fallback_name,
            "at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }

          continuation = %{
            "kind" => "cross_provider_quota_fallback",
            "role" => role,
            "previous_run_id" => old_run_id,
            "current_run_id" => new_run_id,
            "previous_profile" => profile_name,
            "profile" => fallback_name,
            "source_provider" => source_provider,
            "target_provider" => target_provider
          }

          updated_assignment =
            assignment
            |> Map.put("run_id", new_run_id)
            |> Map.put("status", "fallback_intent")
            |> Map.put("configured_profile", fallback_name)
            |> Map.put("configured_model", Map.get(fallback_config, "model", fallback_name))
            |> Map.put("configured_model_id", Map.get(fallback_config, "model_id", ""))
            |> Map.put("continuation", continuation)

          updated_intents =
            state
            |> Map.get("provider_fallback_intents", %{})
            |> Map.put(source_provider, intent)

          updated_state =
            state
            |> Map.put("provider_fallback_intents", updated_intents)
            |> Cooldown.record_cooldown(
              profile_name,
              source_provider,
              cooldown_until,
              "quota_fallback_initiated"
            )

          {:ok, updated_assignment, updated_state}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Releases the in-flight fallback intent for the specified provider once prompt is delivered.
  """
  def release_fallback_intent(state, provider) when is_binary(provider) do
    intents = Map.get(state, "provider_fallback_intents", %{})
    updated_intents = Map.delete(intents, provider)
    Map.put(state, "provider_fallback_intents", updated_intents)
  end

  defp generate_run_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
