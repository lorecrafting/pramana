defmodule PramanaFoundry.Scheduler.Policy do
  @moduledoc """
  Scheduling policy, ranking, scope overlap detection, and parallel conflict rules.
  """

  @shared_resource_keys ~w(corpus database gpu other service_ports)
  @required_env_keys ~w(MIX_TEST_PARTITION MIX_BUILD_PATH PORT)

  @spec scopes_may_overlap?(list(String.t()), list(String.t())) :: boolean()
  def scopes_may_overlap?([], _second), do: true
  def scopes_may_overlap?(_first, []), do: true

  def scopes_may_overlap?(first, second) when is_list(first) and is_list(second) do
    Enum.any?(first, fn left ->
      Enum.any?(second, fn right ->
        paths_overlap?(left, right)
      end)
    end)
  end

  defp paths_overlap?(left, right) do
    case {scope_shape(left), scope_shape(right)} do
      {nil, _} ->
        true

      {_, nil} ->
        true

      {{_left_pat, "", _}, _} ->
        true

      {_, {_right_pat, "", _}} ->
        true

      {{left_pat, _left_prefix, false}, {right_pat, _right_prefix, false}} ->
        left_pat == right_pat or
          String.starts_with?(left_pat, right_pat <> "/") or
          String.starts_with?(right_pat, left_pat <> "/")

      {{left_pat, left_prefix, left_wild}, {right_pat, right_prefix, right_wild}} ->
        common = common_prefix(left_prefix, right_prefix)
        min_prefix_len = min(byte_size(left_prefix), byte_size(right_prefix))

        cond do
          byte_size(common) < min_prefix_len ->
            false

          not left_wild and String.starts_with?(right_prefix, left_pat) and
              boundary_char?(right_prefix, byte_size(left_pat)) ->
            false

          not right_wild and String.starts_with?(left_prefix, right_pat) and
              boundary_char?(left_prefix, byte_size(right_pat)) ->
            false

          true ->
            true
        end
    end
  end

  defp boundary_char?(string, offset) do
    case binary_part(string, offset, min(1, byte_size(string) - offset)) do
      "" -> false
      "/" -> false
      _other -> true
    end
  end

  defp scope_shape(pattern) when is_binary(pattern) do
    if Path.type(pattern) == :absolute or String.contains?(pattern, "..") do
      nil
    else
      normalized = Path.relative_to(pattern, ".")

      if normalized in [".", ""] do
        {"", "", false}
      else
        first_wildcard = find_first_wildcard(normalized)
        prefix = binary_part(normalized, 0, first_wildcard)
        has_wild = first_wildcard < byte_size(normalized)
        {normalized, prefix, has_wild}
      end
    end
  end

  defp scope_shape(_), do: nil

  defp find_first_wildcard(string) do
    string
    |> :binary.bin_to_list()
    |> Enum.find_index(&(&1 in [?*, ?[, ??]))
    |> case do
      nil -> byte_size(string)
      idx -> idx
    end
  end

  defp common_prefix(a, b) do
    common_prefix_bytes(:binary.bin_to_list(a), :binary.bin_to_list(b), [])
    |> :binary.list_to_bin()
  end

  defp common_prefix_bytes([h | t1], [h | t2], acc), do: common_prefix_bytes(t1, t2, [h | acc])
  defp common_prefix_bytes(_l1, _l2, acc), do: Enum.reverse(acc)

  @spec parallel_conflict(map(), map()) :: String.t() | nil
  def parallel_conflict(candidate, active) when is_map(candidate) and is_map(active) do
    first = Map.get(candidate, "ticket", candidate)
    second = Map.get(active, "ticket", active)

    cond do
      first["base_revision"] != second["base_revision"] ->
        "stale-base: parallel assignments require the same exact base revision"

      first["checkout"] == second["checkout"] ->
        "serialized: parallel assignments require separate checkouts"

      Map.get(active, "status") != "queued" and not has_run_id?(active) ->
        "serialized: active assignment has no distinct run ID"

      first["task_id"] in Map.get(second, "dependencies", []) or
          second["task_id"] in Map.get(first, "dependencies", []) ->
        "dependency-blocked: dependent assignments cannot run together"

      scopes_may_overlap?(Map.get(first, "scope", []), Map.get(second, "scope", [])) ->
        "scope-conflicting: normalized path scopes overlap"

      true ->
        check_environment_and_resources(first, second)
    end
  end

  defp has_run_id?(assignment) do
    is_binary(Map.get(assignment, "run_id")) and Map.get(assignment, "run_id") != ""
  end

  defp check_environment_and_resources(first, second) do
    first_env = Map.get(first, "environment", %{})
    second_env = Map.get(second, "environment", %{})

    cond do
      not valid_env?(first_env) or not valid_env?(second_env) ->
        "resource-conflicting: build, test, and port resources must be explicit"

      Enum.any?(@required_env_keys, fn key ->
        Map.get(first_env, key) == Map.get(second_env, key)
      end) ->
        "resource-conflicting: build, test, and port resources must be distinct"

      true ->
        check_shared_resources(first, second, first_env, second_env)
    end
  end

  defp valid_env?(env) when is_map(env) do
    Enum.all?(@required_env_keys, fn key ->
      is_binary(Map.get(env, key)) and Map.get(env, key) != ""
    end)
  end

  defp valid_env?(_), do: false

  defp check_shared_resources(first, second, first_env, second_env) do
    first_res = Map.get(first, "shared_resources")
    second_res = Map.get(second, "shared_resources")

    cond do
      not valid_shared_resources?(first_res) or not valid_shared_resources?(second_res) ->
        "resource-conflicting: shared resources are absent or ambiguous"

      first_env["PORT"] not in Map.get(first_res, "service_ports", []) or
          second_env["PORT"] not in Map.get(second_res, "service_ports", []) ->
        "resource-conflicting: service port declarations are ambiguous"

      true ->
        find_shared_resource_conflict(first_res, second_res)
    end
  end

  defp valid_shared_resources?(res) when is_map(res) do
    keys = Map.keys(res) |> Enum.sort()
    keys == @shared_resource_keys and Enum.all?(Map.values(res), &is_list/1)
  end

  defp valid_shared_resources?(_), do: false

  defp find_shared_resource_conflict(first_res, second_res) do
    Enum.find_value(@shared_resource_keys, fn resource ->
      first_items = MapSet.new(Map.get(first_res, resource, []))
      second_items = MapSet.new(Map.get(second_res, resource, []))

      conflicts =
        MapSet.intersection(first_items, second_items) |> MapSet.to_list() |> Enum.sort()

      case conflicts do
        [item | _] ->
          "resource-conflicting: exclusive #{resource} resource #{item} is already in use"

        [] ->
          nil
      end
    end)
  end

  @spec ranking(map()) :: {integer(), integer(), String.t(), String.t()}
  def ranking(assignment_or_ticket) do
    ticket = Map.get(assignment_or_ticket, "ticket", assignment_or_ticket)
    priority_num = parse_priority(Map.get(ticket, "priority", "P2"))
    dep_count = length(Map.get(ticket, "dependencies", []))
    created_at = Map.get(assignment_or_ticket, "queued_at", Map.get(ticket, "created_at", ""))
    task_id = Map.get(ticket, "task_id", "")
    {priority_num, dep_count, created_at, task_id}
  end

  defp parse_priority("P0"), do: 0
  defp parse_priority("p0"), do: 0
  defp parse_priority("P1"), do: 1
  defp parse_priority("p1"), do: 1
  defp parse_priority("P2"), do: 2
  defp parse_priority("p2"), do: 2
  defp parse_priority("P" <> num), do: String.to_integer(num)
  defp parse_priority("p" <> num), do: String.to_integer(num)
  defp parse_priority(_), do: 99
end
