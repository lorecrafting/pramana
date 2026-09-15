defmodule PramanaFoundry.PM.Proposal do
  @moduledoc """
  Transactional PM proposal validation and all-or-none batch application.
  """

  alias PramanaFoundry.Scheduler.Policy

  @max_proposals 3
  @developer_owner_states ~w(dispatched prompting working queued_correction)

  @spec apply_batch(map(), list(map()), keyword()) :: {:ok, map()} | {:error, String.t()}
  def apply_batch(state, proposals, opts \\ []) do
    max_count = Keyword.get(opts, :max_proposals, @max_proposals)

    cond do
      not is_list(proposals) ->
        {:error, "proposals must be a list"}

      length(proposals) == 0 or length(proposals) > max_count ->
        {:error, "proposals must contain 1 through #{max_count} items"}

      true ->
        orig_assignments = Map.get(state, "assignments", %{})
        orig_queue = Map.get(state, "queue", [])
        orig_scheduler = Map.get(state, "scheduler", %{})

        try do
          case apply_proposals_loop(proposals, state) do
            {:ok, new_state} ->
              with :ok <- validate_dependency_graph(new_state["assignments"]),
                   :ok <- validate_conflicts(new_state, orig_assignments) do
                {:ok, new_state}
              else
                {:error, reason} ->
                  rollback(state, orig_assignments, orig_queue, orig_scheduler, reason)
              end

            {:error, reason} ->
              rollback(state, orig_assignments, orig_queue, orig_scheduler, reason)
          end
        rescue
          e ->
            rollback(state, orig_assignments, orig_queue, orig_scheduler, Exception.message(e))
        end
    end
  end

  defp rollback(state, orig_assignments, orig_queue, orig_scheduler, reason) do
    _restored_state =
      state
      |> Map.put("assignments", orig_assignments)
      |> Map.put("queue", orig_queue)
      |> Map.put("scheduler", orig_scheduler)

    {:error, reason}
  end

  defp apply_proposals_loop([], state), do: {:ok, state}

  defp apply_proposals_loop([prop | rest], state) do
    case apply_one(state, prop) do
      {:ok, next_state} -> apply_proposals_loop(rest, next_state)
      {:error, reason} -> {:error, reason}
    end
  end

  defp apply_one(state, %{"operation" => op} = prop) when op in ["create", "split"] do
    required = ~w(operation ticket reason)
    keys = Map.keys(prop) |> Enum.sort()

    if keys != Enum.sort(required) do
      {:error, "#{op} proposal fields must be operation, ticket, reason"}
    else
      ticket = prop["ticket"]
      reason = prop["reason"]

      cond do
        not is_binary(reason) or String.trim(reason) == "" ->
          {:error, "#{op} proposal requires a reason"}

        not is_map(ticket) ->
          {:error, "#{op} ticket must be an object"}

        Map.has_key?(ticket, "auto_approve") ->
          {:error, "#{op} ticket auto_approve is forbidden; independent review is mandatory"}

        ticket["base_revision"] != state["accepted_revision"] ->
          {:error, "#{op} ticket base does not equal accepted revision"}

        true ->
          task_id = ticket["task_id"]
          assignments = Map.get(state, "assignments", %{})
          queue = Map.get(state, "queue", [])

          if Map.has_key?(assignments, task_id) do
            {:error, "assignment #{task_id} already exists"}
          else
            new_assignment = %{
              "ticket" => ticket,
              "status" => "queued",
              "queued_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
              "scheduling_decision" => %{"status" => "queued", "reason" => "pm_created"}
            }

            next_state =
              state
              |> Map.put("assignments", Map.put(assignments, task_id, new_assignment))
              |> Map.put("queue", queue ++ [task_id])

            {:ok, next_state}
          end
      end
    end
  end

  defp apply_one(state, %{"operation" => "amend"} = prop) do
    required = ~w(operation task_id ticket reason)
    keys = Map.keys(prop) |> Enum.sort()

    if keys != Enum.sort(required) do
      {:error, "amend proposal fields must be operation, task_id, ticket, reason"}
    else
      task_id = prop["task_id"]
      ticket = prop["ticket"]
      existing = get_in(state, ["assignments", task_id])

      cond do
        not is_map(existing) or existing["status"] != "queued" ->
          {:error, "PM may amend only a queued assignment"}

        not is_map(ticket) ->
          {:error, "amended ticket must be an object"}

        Map.has_key?(ticket, "auto_approve") ->
          {:error, "amended ticket auto_approve is forbidden; independent review is mandatory"}

        ticket["task_id"] != task_id ->
          {:error, "amended ticket must retain its task ID"}

        ticket["base_revision"] != state["accepted_revision"] ->
          {:error, "amended ticket base does not equal accepted revision"}

        true ->
          updated_assignment =
            existing
            |> Map.put("ticket", ticket)
            |> Map.put("scheduling_decision", %{"status" => "queued", "reason" => "pm_amended"})

          next_state = put_in(state, ["assignments", task_id], updated_assignment)
          {:ok, next_state}
      end
    end
  end

  defp apply_one(state, %{"operation" => "reprioritize"} = prop) do
    required = ~w(operation task_id priority reason)
    keys = Map.keys(prop) |> Enum.sort()

    if keys != Enum.sort(required) do
      {:error, "reprioritize proposal fields must be operation, task_id, priority, reason"}
    else
      task_id = prop["task_id"]
      priority = prop["priority"]
      existing = get_in(state, ["assignments", task_id])

      cond do
        not is_map(existing) or existing["status"] != "queued" ->
          {:error, "PM may reprioritize only a queued assignment"}

        not is_binary(priority) or not Regex.match?(~r/^[Pp]\d+$/, priority) ->
          {:error, "reprioritized priority must be P<number>"}

        true ->
          num = Regex.run(~r/^[Pp](\d+)$/, priority) |> Enum.at(1) |> String.to_integer()
          normalized_priority = "P#{num}"

          updated_ticket = Map.put(existing["ticket"], "priority", normalized_priority)
          updated_assignment = Map.put(existing, "ticket", updated_ticket)
          next_state = put_in(state, ["assignments", task_id], updated_assignment)
          {:ok, next_state}
      end
    end
  end

  defp apply_one(state, %{"operation" => "park"} = prop) do
    required = ~w(operation task_id reason)
    keys = Map.keys(prop) |> Enum.sort()

    if keys != Enum.sort(required) do
      {:error, "park proposal fields must be operation, task_id, reason"}
    else
      task_id = prop["task_id"]
      reason = prop["reason"]
      existing = get_in(state, ["assignments", task_id])

      cond do
        not is_map(existing) or existing["status"] != "queued" ->
          {:error, "PM may park only a queued assignment"}

        not is_binary(reason) or String.trim(reason) == "" ->
          {:error, "park proposal requires a reason"}

        true ->
          updated_assignment =
            existing
            |> Map.put("status", "parked")
            |> Map.put("blocker", String.slice(reason, 0, 2000))

          queue = List.delete(state["queue"], task_id)

          next_state =
            state
            |> put_in(["assignments", task_id], updated_assignment)
            |> Map.put("queue", queue)

          {:ok, next_state}
      end
    end
  end

  defp apply_one(_state, %{"operation" => op}) do
    {:error, "unsupported PM proposal operation: #{op}"}
  end

  defp apply_one(_state, _prop) do
    {:error, "PM proposal must be an object with an operation"}
  end

  defp validate_dependency_graph(assignments) do
    for {task_id, assignment} <- assignments do
      deps = get_in(assignment, ["ticket", "dependencies"]) || []

      for dep <- deps do
        if dep == task_id do
          throw({:error, "ticket #{task_id} cannot depend on itself"})
        end

        if not Map.has_key?(assignments, dep) do
          throw({:error, "ticket #{task_id} names unknown dependency #{dep}"})
        end
      end
    end

    # Check cycles
    visited = MapSet.new()
    visiting = MapSet.new()

    Enum.reduce(Map.keys(assignments), {visited, visiting}, fn task_id, acc ->
      visit_node(task_id, assignments, acc)
    end)

    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  defp visit_node(task_id, assignments, {visited, visiting}) do
    cond do
      MapSet.member?(visiting, task_id) ->
        throw({:error, "ticket dependency graph contains a cycle"})

      MapSet.member?(visited, task_id) ->
        {visited, visiting}

      true ->
        visiting = MapSet.put(visiting, task_id)
        deps = get_in(assignments, [task_id, "ticket", "dependencies"]) || []

        {visited, visiting} =
          Enum.reduce(deps, {visited, visiting}, fn dep, acc ->
            visit_node(dep, assignments, acc)
          end)

        visiting = MapSet.delete(visiting, task_id)
        visited = MapSet.put(visited, task_id)
        {visited, visiting}
    end
  end

  defp validate_conflicts(new_state, orig_assignments) do
    assignments = new_state["assignments"]

    # proposed: newly created or changed queued tickets
    proposed =
      assignments
      |> Map.values()
      |> Enum.filter(fn a ->
        task_id = a["ticket"]["task_id"]

        a["status"] == "queued" and
          (not Map.has_key?(orig_assignments, task_id) or a != Map.get(orig_assignments, task_id))
      end)

    # active workers from before
    active =
      orig_assignments
      |> Map.values()
      |> Enum.filter(fn a -> a["status"] in @developer_owner_states end)

    # Check proposed against active
    for candidate <- proposed, owner <- active do
      case Policy.parallel_conflict(candidate, owner) do
        nil -> :ok
        conflict -> throw({:error, "PM proposal conflicts with a live assignment: #{conflict}"})
      end
    end

    # Check proposed against each other
    proposed_list = proposed
    len = length(proposed_list)

    if len > 1 do
      for i <- 0..(len - 2), j <- (i + 1)..(len - 1) do
        c1 = Enum.at(proposed_list, i)
        c2 = Enum.at(proposed_list, j)

        conflict = Policy.parallel_conflict(c1, c2)

        if conflict != nil and not depends_on?(c1, c2, assignments) and
             not depends_on?(c2, c1, assignments) do
          throw(
            {:error, "PM proposals contain an unordered scope/resource conflict: #{conflict}"}
          )
        end
      end
    end

    :ok
  catch
    {:error, reason} -> {:error, reason}
  end

  defp depends_on?(candidate, predecessor, assignments) do
    target_id = predecessor["ticket"]["task_id"]
    pending = get_in(candidate, ["ticket", "dependencies"]) || []
    seen = MapSet.new()
    check_depends(pending, target_id, seen, assignments)
  end

  defp check_depends([], _target, _seen, _assignments), do: false

  defp check_depends([dep | rest], target, seen, assignments) do
    cond do
      dep == target ->
        true

      MapSet.member?(seen, dep) ->
        check_depends(rest, target, seen, assignments)

      true ->
        seen = MapSet.put(seen, dep)
        next_deps = get_in(assignments, [dep, "ticket", "dependencies"]) || []
        check_depends(rest ++ next_deps, target, seen, assignments)
    end
  end
end
