defmodule PramanaFoundry.Quota.SubscriptionLifecycleTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Quota

  test "virtual time quota cooldown and declared subscription Codex ↔ Claude fallback" do
    profiles = %{
      "claude_dev" => %{
        "model" => "claude-3-5-sonnet",
        "model_id" => "anthropic/claude-3-5-sonnet",
        "reasoning" => "medium",
        "subscription_authorized" => true,
        "fallback_profiles" => ["codex_dev"]
      },
      "codex_dev" => %{
        "model" => "codex-sol",
        "model_id" => "openai-codex/sol",
        "reasoning" => "medium",
        "subscription_authorized" => true,
        "fallback_profiles" => ["claude_dev"]
      }
    }

    state = %{}

    assignment = %{
      "run_id" => "run-original-1234",
      "ticket" => %{"task_id" => "T-FALLBACK", "profile" => "claude_dev"}
    }

    # Ordinary failure never triggers fallback
    assert Quota.can_fallback?(profiles["claude_dev"], "ordinary_failure", profiles) ==
             {:error, :unauthorized_signal}

    # Subscription quota triggers fallback with fresh run ID
    assert {:ok, updated_assignment, updated_state} =
             Quota.begin_fallback(state, assignment, "usage_limit_reached", profiles,
               new_run_id: "run-fresh-5678",
               now: 1000.0
             )

    assert updated_assignment["run_id"] == "run-fresh-5678"
    assert updated_assignment["configured_profile"] == "codex_dev"
    assert updated_assignment["continuation"]["kind"] == "cross_provider_quota_fallback"

    # Anthropic provider is in-flight: second fallback is suppressed
    assert {:error, :provider_in_flight_intent_exists, _} =
             Quota.begin_fallback(updated_state, assignment, "usage_limit_reached", profiles,
               now: 1000.0
             )
  end
end
