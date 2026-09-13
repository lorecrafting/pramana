defmodule PramanaFoundry.QuotaTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Quota

  @profiles %{
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
    },
    "claude_weak" => %{
      "model" => "claude-haiku",
      "model_id" => "anthropic/claude-haiku",
      "reasoning" => "low",
      "subscription_authorized" => true,
      "fallback_profiles" => []
    },
    "gemini_dev" => %{
      "model" => "gemini-flash",
      "model_id" => "google/gemini-flash",
      "reasoning" => "medium",
      "subscription_authorized" => true,
      "fallback_profiles" => []
    }
  }

  describe "cooldown in virtual time" do
    test "tracks active cooldown until epoch without sleeping" do
      state = %{}
      # Virtual time starts at 1000
      virtual_now = 1000.0

      # Set cooldown for 60 seconds -> until 1060.0
      state = Quota.record_cooldown(state, "claude_dev", "anthropic", virtual_now + 60)

      assert Quota.active_cooldown?(state, "claude_dev", virtual_now + 30)
      assert Quota.cooled_profiles(state, virtual_now + 30) == ["claude_dev"]

      # Advance virtual time past cooldown -> no longer active!
      refute Quota.active_cooldown?(state, "claude_dev", virtual_now + 61)
      assert Quota.cooled_profiles(state, virtual_now + 61) == []
    end
  end

  describe "cross-provider subscription fallback" do
    test "only positive subscription quota signals trigger fallback" do
      for valid_signal <- ~w(provider_quota_reached usage_limit_reached weekly_limit_reached) do
        assert Quota.subscription_quota_signal?(valid_signal)

        assert match?(
                 {:ok, _, _, _, _},
                 Quota.can_fallback?(@profiles["claude_dev"], valid_signal, @profiles)
               )
      end

      # Non-subscription or other errors NEVER select fallback
      for invalid_signal <-
            ~w(capacity rate_limit authentication permission ambiguous_delivery ordinary_failure) do
        refute Quota.subscription_quota_signal?(invalid_signal)

        assert Quota.can_fallback?(@profiles["claude_dev"], invalid_signal, @profiles) ==
                 {:error, :unauthorized_signal}
      end
    end

    test "exercises Codex ↔ Claude fallback with fresh run ID and continuation" do
      state = %{}

      assignment = %{
        "run_id" => "run-orig-1234",
        "ticket" => %{
          "task_id" => "T1",
          "profile" => "claude_dev"
        }
      }

      assert {:ok, updated_assignment, updated_state} =
               Quota.begin_fallback(state, assignment, "usage_limit_reached", @profiles,
                 new_run_id: "run-continuation-5678",
                 now: 2000.0
               )

      assert updated_assignment["run_id"] == "run-continuation-5678"
      assert updated_assignment["status"] == "fallback_intent"
      assert updated_assignment["configured_profile"] == "codex_dev"

      continuation = updated_assignment["continuation"]
      assert continuation["kind"] == "cross_provider_quota_fallback"
      assert continuation["previous_run_id"] == "run-orig-1234"
      assert continuation["current_run_id"] == "run-continuation-5678"
      assert continuation["source_provider"] == "anthropic"
      assert continuation["target_provider"] == "openai-codex"

      # In-flight fallback intent is recorded for anthropic
      assert Map.has_key?(updated_state["provider_fallback_intents"], "anthropic")

      # A second fallback attempt for anthropic while in-flight is suppressed
      second_assignment = %{
        "run_id" => "run-second-9999",
        "ticket" => %{"task_id" => "T2", "profile" => "claude_dev"}
      }

      assert {:error, :provider_in_flight_intent_exists, _} =
               Quota.begin_fallback(
                 updated_state,
                 second_assignment,
                 "usage_limit_reached",
                 @profiles,
                 now: 2000.0
               )

      # But unrelated providers (e.g. codex or gemini) remain eligible
      codex_assignment = %{
        "run_id" => "run-codex-1111",
        "ticket" => %{"task_id" => "T3", "profile" => "codex_dev"}
      }

      assert {:ok, _, _} =
               Quota.begin_fallback(
                 updated_state,
                 codex_assignment,
                 "usage_limit_reached",
                 @profiles,
                 now: 2000.0
               )

      # Once released, anthropic can fall back again
      cleared_state = Quota.release_fallback_intent(updated_state, "anthropic")
      refute Map.has_key?(cleared_state["provider_fallback_intents"], "anthropic")
    end
  end
end
