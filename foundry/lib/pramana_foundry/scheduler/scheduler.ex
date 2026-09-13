defmodule PramanaFoundry.Scheduler do
  @moduledoc """
  Deterministic scheduler managing queue ordering, worker capacity, and parallel admission.
  """

  alias PramanaFoundry.Scheduler.Policy

  @default_worker_ceiling 2
  @developer_owner_states ~w(dispatched prompting working queued_correction)

  @doc """
  Evaluates the queued assignments against active assignments, capacity, and pause/stop controls.
  Returns {:ok, list_of_admitted_assignments} or {:ok, []}.
  """
  def plan_dispatch(state, opts \\ []) do
    paused? = Map.get(state, "paused", false)
    stop_requested? = Map.get(state, "stop_requested", false)

    if paused? or stop_requested? do
      {:ok, []}
    else
      max_workers = Keyword.get(opts, :max_workers, @default_worker_ceiling)
      assignments = Map.get(state, "assignments", %{})
      queue = Map.get(state, "queue", [])

      active_workers =
        assignments
        |> Map.values()
        |> Enum.filter(fn a -> Map.get(a, "status") in @developer_owner_states end)

      available_slots = max(0, max_workers - length(active_workers))

      if available_slots == 0 do
        {:ok, []}
      else
        cooldowns = Map.get(state, "provider_cooldowns", %{})
        in_flight_fallbacks = Map.get(state, "provider_fallback_intents", %{})
        now = Keyword.get(opts, :now, System.system_time(:second))

        candidates =
          queue
          |> Enum.map(&Map.get(assignments, &1))
          |> Enum.filter(&is_map/1)
          |> Enum.filter(fn a -> Map.get(a, "status") == "queued" end)
          |> Enum.sort_by(&Policy.ranking/1)

        {selected, _} =
          Enum.reduce(candidates, {[], active_workers}, fn candidate, {acc, current_active} ->
            if length(acc) >= available_slots do
              {acc, current_active}
            else
              ticket = Map.get(candidate, "ticket", candidate)
              profile = Map.get(ticket, "profile", "")
              provider = Map.get(candidate, "provider", provider_from_profile(profile))

              provider_cooled? =
                case Map.get(cooldowns, profile) do
                  %{"until_epoch" => until_epoch} when until_epoch > now -> true
                  _ -> false
                end

              fallback_in_flight? = Map.has_key?(in_flight_fallbacks, provider)

              dependencies_met? =
                Enum.all?(Map.get(ticket, "dependencies", []), fn dep_id ->
                  case Map.get(assignments, dep_id) do
                    %{"status" => status} when status in ["integrated", "accepted"] -> true
                    _ -> false
                  end
                end)

              has_conflict? =
                Enum.any?(current_active, fn active ->
                  Policy.parallel_conflict(candidate, active) != nil
                end)

              if not provider_cooled? and not fallback_in_flight? and dependencies_met? and
                   not has_conflict? do
                {[candidate | acc], [candidate | current_active]}
              else
                {acc, current_active}
              end
            end
          end)

        {:ok, Enum.reverse(selected)}
      end
    end
  end

  defp provider_from_profile(profile) when is_binary(profile) do
    cond do
      String.contains?(profile, "claude") or String.contains?(profile, "anthropic") -> "anthropic"
      String.contains?(profile, "codex") or String.contains?(profile, "openai") -> "openai-codex"
      String.contains?(profile, "gemini") or String.contains?(profile, "google") -> "google"
      true -> "unknown"
    end
  end

  defp provider_from_profile(_), do: "unknown"
end
