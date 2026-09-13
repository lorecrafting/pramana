defmodule PramanaFoundry.PM.AttemptCap do
  @moduledoc """
  Planning-attempt-cap tracking with reason fingerprinting and human-only reset escape hatch.
  """

  @default_max_consecutive_rejections 3
  @default_max_total_attempts 10
  @max_total_attempts_ceiling 30
  @max_reason_chars 2000
  @volatile_hex_token ~r/\b[0-9a-f]{8,}\b/i

  @spec normalize_reason(String.t()) :: String.t()
  def normalize_reason(reason) when is_binary(reason) do
    reason
    |> String.replace(@volatile_hex_token, "<hex>")
    |> String.slice(0, @max_reason_chars)
  end

  def normalize_reason(_), do: ""

  @spec record_disposition(map(), String.t(), String.t(), keyword()) :: map()
  def record_disposition(pm_state, disposition, reason, opts \\ []) do
    current_accepted = Keyword.get(opts, :current_accepted_revision, "")
    launched_for = Map.get(pm_state, "accepted_revision", current_accepted)
    streaks = Map.get(pm_state, "consecutive_rejections_by_revision", %{})

    case disposition do
      "accepted" ->
        updated_streaks = Map.delete(streaks, launched_for)

        pm_state
        |> Map.put("consecutive_rejections_by_revision", updated_streaks)
        |> Map.put("last_disposition", %{"disposition" => "accepted", "reason" => reason})

      disp when disp in ["rejected", "stale"] ->
        fingerprint = normalize_reason(reason)
        current = Map.get(streaks, launched_for, %{})
        repeated? = is_map(current) and Map.get(current, "fingerprint") == fingerprint

        new_count = if repeated?, do: Map.get(current, "count", 0) + 1, else: 1

        new_streak = %{
          "fingerprint" => fingerprint,
          "count" => new_count,
          "reason" => String.slice(reason, 0, @max_reason_chars),
          "at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }

        updated_streaks = Map.put(streaks, launched_for, new_streak)

        pm_state
        |> Map.put("consecutive_rejections_by_revision", updated_streaks)
        |> Map.put("last_disposition", %{
          "disposition" => disp,
          "reason" => String.slice(reason, 0, @max_reason_chars)
        })

      "suspended" ->
        # A suspension is a halt, not a verdict, and neither extends nor breaks the count
        Map.put(pm_state, "last_disposition", %{"disposition" => "suspended", "reason" => reason})

      _other ->
        pm_state
    end
  end

  @spec increment_attempt(map(), String.t()) :: map()
  def increment_attempt(pm_state, accepted_revision) when is_binary(accepted_revision) do
    attempts = Map.get(pm_state, "attempts_by_revision", %{})
    current_count = Map.get(attempts, accepted_revision, 0)
    updated_attempts = Map.put(attempts, accepted_revision, current_count + 1)
    Map.put(pm_state, "attempts_by_revision", updated_attempts)
  end

  @spec halt_reason(map(), String.t(), map() | keyword()) :: map() | nil
  def halt_reason(pm_state, accepted_revision, config \\ %{}) do
    max_consecutive =
      cfg_val(config, :max_attempts_per_revision, @default_max_consecutive_rejections)

    max_total =
      cfg_val(config, :max_total_attempts_per_revision, @default_max_total_attempts)
      |> min(@max_total_attempts_ceiling)

    streaks = Map.get(pm_state, "consecutive_rejections_by_revision", %{})
    streak = Map.get(streaks, accepted_revision, %{})
    repeated = Map.get(streak, "count", 0)

    cond do
      repeated >= max_consecutive ->
        %{
          "revision" => accepted_revision,
          "counter" => "consecutive_rejections",
          "count" => repeated,
          "limit" => max_consecutive,
          "last_reason" => Map.get(streak, "reason"),
          "clears_with" => "reset-pm-attempts"
        }

      true ->
        attempts = Map.get(pm_state, "attempts_by_revision", %{})
        total = Map.get(attempts, accepted_revision, 0)

        if total >= max_total do
          last_disp = Map.get(pm_state, "last_disposition", %{})

          %{
            "revision" => accepted_revision,
            "counter" => "total_attempts",
            "count" => total,
            "limit" => max_total,
            "last_reason" => Map.get(last_disp, "reason"),
            "last_disposition" => Map.get(last_disp, "disposition"),
            "clears_with" => "reset-pm-attempts"
          }
        else
          nil
        end
    end
  end

  defp cfg_val(config, key, default) when is_map(config) do
    Map.get(config, to_string(key), Map.get(config, key, default))
  end

  defp cfg_val(config, key, default) when is_list(config) do
    Keyword.get(config, key, default)
  end

  @spec reset_attempts(map(), map(), String.t()) :: {:ok, map(), map()} | {:error, String.t()}
  def reset_attempts(pm_state, payload, current_accepted_revision) when is_map(payload) do
    with :ok <- validate_human_authority(payload),
         :ok <- validate_issued_fields(payload),
         :ok <- validate_revision_matches(payload, current_accepted_revision) do
      attempts = Map.get(pm_state, "attempts_by_revision", %{})
      streaks = Map.get(pm_state, "consecutive_rejections_by_revision", %{})

      streak = Map.get(streaks, current_accepted_revision, %{})
      prev_streak_count = Map.get(streak, "count", 0)
      prev_streak_reason = Map.get(streak, "reason")
      prev_attempts = Map.get(attempts, current_accepted_revision, 0)

      updated_attempts = Map.delete(attempts, current_accepted_revision)
      updated_streaks = Map.delete(streaks, current_accepted_revision)

      reset_record = %{
        "revision" => current_accepted_revision,
        "previous_attempts" => prev_attempts,
        "previous_consecutive_rejections" => prev_streak_count,
        "previous_rejection_reason" => prev_streak_reason,
        "issued_by" => payload["issued_by"],
        "issued_at" => payload["issued_at"],
        "reset_at" => DateTime.utc_now() |> DateTime.to_iso8601()
      }

      updated_pm =
        pm_state
        |> Map.put("attempts_by_revision", updated_attempts)
        |> Map.put("consecutive_rejections_by_revision", updated_streaks)
        |> Map.put("last_attempt_reset", reset_record)
        |> Map.delete("planning_attempt_halt")

      {:ok, reset_record, updated_pm}
    end
  end

  def reset_attempts(_pm_state, _payload, _current), do: {:error, "invalid payload"}

  defp validate_human_authority(%{"authority" => "human"}), do: :ok

  defp validate_human_authority(_),
    do: {:error, "reset_pm_attempts requires an explicit human authority"}

  defp validate_issued_fields(%{"issued_by" => by, "issued_at" => at})
       when is_binary(by) and by != "" and is_binary(at) and at != "",
       do: :ok

  defp validate_issued_fields(_),
    do: {:error, "reset_pm_attempts requires issued_by and issued_at"}

  defp validate_revision_matches(%{"revision" => rev}, current)
       when rev == current and is_binary(current),
       do: :ok

  defp validate_revision_matches(_, _),
    do: {:error, "reset_pm_attempts must name the current accepted revision"}
end
