defmodule PramanaFoundry.Cleanup do
  @moduledoc """
  Legacy FR-04 projection for durable cleanup obligations.

  Cleanup is independent of the work verdict. Pending or unresolved resources keep
  the assignment blocked and retain their execution slot until a checked closed or
  not-required result exists.
  """

  @roles ~w(developer reviewer pm)
  @terminal_results ~w(closed not_required)
  @owned_identity_fields ~w(pane_id terminal_id agent_name cleanup_identity presentation_identity)
  @identity_fields ~w(task_id execution_id role resource_id pane_id terminal_id session observed_session agent_name presentation_identity)
  @resource_identity_fields ~w(task_id execution_id role resource_id pane_id terminal_id session agent_name presentation_identity)
  @stable_resource_identity_fields ~w(task_id execution_id role resource_id pane_id terminal_id agent_name presentation_identity)

  @spec apply_pending(map(), map()) :: {:ok, map()} | {:error, term()}
  def apply_pending(state, attributes) do
    attributes = normalize_optional_identity(attributes)

    with :ok <- validate_owner(attributes),
         :ok <- validate_resource_identity(attributes),
         {:ok, assignment} <- assignment(state, attributes["task_id"]),
         :ok <-
           identity_matches_registered(assignment, obligation_id(attributes), attributes) do
      obligation_id = obligation_id(attributes)
      work_status = retained_work_status(assignment)

      obligation =
        attributes
        |> Map.put("status", "pending")
        |> Map.put("work_status", work_status)

      updated =
        assignment
        |> update_registered_resource(obligation_id, obligation)
        |> Map.put("cleanup_last_result", Map.put(obligation, "status", "pending"))
        |> Map.put("cleanup_obligations", put_obligation(assignment, obligation_id, obligation))
        |> recompute_cleanup_outstanding()
        |> Map.put("work_status", work_status)
        |> Map.put("status", "cleanup_pending")

      new_state =
        state
        |> put_in(["assignments", attributes["task_id"]], updated)
        |> Map.update("queue", [], &List.delete(&1, attributes["task_id"]))

      {:ok, new_state}
    end
  end

  @spec apply_result(map(), map()) :: {:ok, map()} | {:error, term()}
  def apply_result(state, attributes) do
    attributes = normalize_optional_identity(attributes)

    with :ok <- validate_owner(attributes),
         :ok <- validate_resource_identity(attributes),
         :ok <- validate_result_identity(attributes),
         {:ok, assignment} <- assignment(state, attributes["task_id"]),
         {:ok, pending} <- pending_obligation(assignment, obligation_id(attributes)),
         :ok <- identity_matches_pending(pending, attributes),
         :ok <-
           identity_matches_registered(assignment, obligation_id(attributes), attributes) do
      status = attributes["status"]
      latest_work_status = Map.get(assignment, "work_status", pending["work_status"])

      if status in @terminal_results do
        obligations =
          assignment
          |> Map.get("cleanup_obligations", %{})
          |> Map.delete(obligation_id(attributes))

        updated =
          assignment
          |> update_registered_resource(obligation_id(attributes), attributes)
          |> Map.put("cleanup_obligations", obligations)
          |> Map.put("cleanup_last_result", attributes)
          |> Map.put("work_status", latest_work_status)
          |> recompute_cleanup_outstanding()
          |> maybe_restore_status(latest_work_status)

        {:ok, put_in(state, ["assignments", attributes["task_id"]], updated)}
      else
        obligation = Map.merge(pending, attributes)

        updated =
          assignment
          |> update_registered_resource(obligation_id(attributes), obligation)
          |> Map.put(
            "cleanup_obligations",
            put_obligation(assignment, obligation_id(attributes), obligation)
          )
          |> Map.put("cleanup_last_result", obligation)
          |> Map.put("work_status", latest_work_status)
          |> recompute_cleanup_outstanding()
          |> Map.put("status", "cleanup_blocked")

        {:ok, put_in(state, ["assignments", attributes["task_id"]], updated)}
      end
    end
  end

  @spec preserve_work_status(map(), binary(), binary()) :: map()
  def preserve_work_status(state, task_id, work_status) do
    assignment = get_in(state, ["assignments", task_id])

    if is_map(assignment) and assignment_outstanding?(assignment) do
      updated =
        assignment
        |> Map.put("work_status", work_status)
        |> Map.put("status", "cleanup_blocked")

      put_in(state, ["assignments", task_id], updated)
    else
      put_in(state, ["assignments", task_id, "status"], work_status)
    end
  end

  @doc false
  @spec register_resource(map(), map()) :: {:ok, map()} | {:error, term()}
  def register_resource(state, attributes) do
    attributes = normalize_recorded_resource(attributes)

    with :ok <- validate_owner(attributes),
         :ok <- validate_recorded_resource(attributes),
         {:ok, assignment} <- assignment(state, attributes["task_id"]),
         :ok <-
           registration_matches_existing(assignment, obligation_id(attributes), attributes) do
      resource = Map.put(attributes, "status", resource_status(attributes))
      updated = put_registered_resource(assignment, obligation_id(attributes), resource)
      updated = recompute_cleanup_outstanding(updated)
      {:ok, put_in(state, ["assignments", attributes["task_id"]], updated)}
    end
  end

  defp validate_recorded_resource(%{
         "verification_status" => "unverified",
         "pane_id" => pane_id,
         "terminal_id" => terminal_id,
         "agent_name" => agent_name
       })
       when is_binary(pane_id) and pane_id != "" and is_binary(terminal_id) and
              terminal_id != "" and is_binary(agent_name) and agent_name != "",
       do: :ok

  defp validate_recorded_resource(%{"verification_status" => "verified"} = attributes),
    do: validate_complete_resource_identity(attributes)

  defp validate_recorded_resource(_attributes), do: {:error, :invalid_recorded_resource}

  @doc false
  @spec all_owned_resources_terminal?(map()) :: boolean()
  def all_owned_resources_terminal?(state) do
    state
    |> Map.get("assignments", %{})
    |> Map.values()
    |> Enum.all?(fn assignment ->
      not assignment_outstanding?(assignment) and
        all_assignment_resources_terminal?(assignment)
    end)
  end

  @doc false
  @spec outstanding?(map()) :: boolean()
  def outstanding?(state) do
    state
    |> Map.get("assignments", %{})
    |> Map.values()
    |> Enum.any?(&assignment_outstanding?/1)
  end

  @doc false
  @spec assignment_outstanding?(map()) :: boolean()
  def assignment_outstanding?(assignment) when is_map(assignment) do
    obligations = Map.get(assignment, "cleanup_obligations", %{})
    resources = Map.get(assignment, "cleanup_resources", %{})

    obligations_outstanding? = is_map(obligations) and map_size(obligations) > 0

    case resources do
      resources when is_map(resources) and map_size(resources) > 0 ->
        obligations_outstanding? or
          Enum.any?(resources, fn {_id, resource} -> not terminal_resource?(resource) end)

      _none ->
        obligations_outstanding? or Map.get(assignment, "cleanup_outstanding", false)
    end
  end

  def assignment_outstanding?(_assignment), do: false

  defp all_assignment_resources_terminal?(assignment) do
    case Map.get(assignment, "cleanup_resources", %{}) do
      resources when is_map(resources) and map_size(resources) > 0 ->
        Enum.all?(resources, fn {_id, resource} -> terminal_resource?(resource) end)

      _none ->
        not owned_identity?(assignment) or terminal_result?(assignment)
    end
  end

  defp terminal_resource?(resource) when is_map(resource) do
    resource["status"] in @terminal_results and
      valid_terminal_resource_identity?(resource)
  end

  defp terminal_resource?(_resource), do: false

  defp valid_terminal_resource_identity?(resource) do
    case validate_complete_resource_identity(resource) do
      :ok -> true
      {:error, _reason} -> false
    end
  end

  defp owned_identity?(assignment) do
    Enum.any?(@owned_identity_fields, fn field ->
      value = Map.get(assignment, field)
      not is_nil(value) and value != "" and value != %{}
    end)
  end

  defp terminal_result?(assignment) do
    result = Map.get(assignment, "cleanup_last_result")

    is_map(result) and result["status"] in @terminal_results and
      same_if_present?(assignment, result, "pane_id") and
      same_if_present?(assignment, result, "terminal_id") and
      same_if_present?(assignment, result, "agent_name") and
      same_if_present?(assignment, result, "presentation_identity") and
      cleanup_identity_matches?(Map.get(assignment, "cleanup_identity"), result)
  end

  defp same_if_present?(assignment, result, field) do
    case Map.get(assignment, field) do
      nil -> true
      current -> current == Map.get(result, field)
    end
  end

  defp cleanup_identity_matches?(nil, _result), do: true

  defp cleanup_identity_matches?(identity, result) when is_map(identity) do
    identity["name"] == result["agent_name"] and
      identity["pane_id"] == result["pane_id"] and
      identity["terminal_id"] == result["terminal_id"] and
      identity["session"] == result["session"]
  end

  defp cleanup_identity_matches?(_identity, _result), do: false

  defp validate_owner(%{
         "task_id" => task_id,
         "execution_id" => execution_id,
         "role" => role,
         "resource_id" => resource_id
       })
       when is_binary(task_id) and task_id != "" and is_binary(execution_id) and
              execution_id != "" and role in @roles and is_binary(resource_id) do
    if resource_id == role <> ":" <> execution_id,
      do: :ok,
      else: {:error, :invalid_cleanup_owner}
  end

  defp validate_owner(_attributes), do: {:error, :invalid_cleanup_owner}

  defp validate_resource_identity(%{
         "agent_name" => agent_name,
         "pane_id" => nil,
         "terminal_id" => nil,
         "session" => nil,
         "presentation_identity" => nil
       })
       when is_binary(agent_name) and agent_name != "",
       do: :ok

  defp validate_resource_identity(%{
         "agent_name" => agent_name,
         "pane_id" => pane_id,
         "terminal_id" => terminal_id,
         "session" => session,
         "presentation_identity" => nil
       })
       when is_binary(agent_name) and agent_name != "" and is_binary(pane_id) and pane_id != "" and
              is_binary(terminal_id) and terminal_id != "" do
    if is_nil(session) or valid_native_session?(session, terminal_id),
      do: :ok,
      else: {:error, :invalid_cleanup_resource_identity}
  end

  defp validate_resource_identity(attributes), do: validate_complete_resource_identity(attributes)

  defp validate_complete_resource_identity(%{
         "agent_name" => agent_name,
         "pane_id" => pane_id,
         "terminal_id" => terminal_id,
         "session" => session,
         "presentation_identity" => %{
           "pane_id" => pane_id,
           "terminal_id" => terminal_id,
           "process_identity" => %{
             "pane_id" => pane_id,
             "terminal_id" => terminal_id,
             "shell_pid" => shell_pid,
             "started_at" => started_at,
             "foreground_pid" => foreground_pid,
             "foreground_started_at" => foreground_started_at
           }
         }
       })
       when is_binary(agent_name) and agent_name != "" and is_binary(pane_id) and pane_id != "" and
              is_binary(terminal_id) and terminal_id != "" and is_integer(shell_pid) and
              shell_pid > 0 and is_binary(started_at) and started_at != "" do
    if is_integer(foreground_pid) and foreground_pid > 0 and
         is_binary(foreground_started_at) and foreground_started_at != "" and
         (is_nil(session) or valid_native_session?(session, terminal_id)),
       do: :ok,
       else: {:error, :invalid_cleanup_resource_identity}
  end

  defp validate_complete_resource_identity(_attributes),
    do: {:error, :invalid_cleanup_resource_identity}

  defp validate_result_identity(%{"status" => "closed"} = attributes),
    do: validate_complete_resource_identity(attributes)

  defp validate_result_identity(%{
         "status" => "not_required",
         "pane_id" => nil,
         "terminal_id" => nil,
         "session" => nil,
         "presentation_identity" => nil
       }),
       do: :ok

  defp validate_result_identity(%{"status" => status})
       when is_binary(status) and status not in @terminal_results,
       do: :ok

  defp validate_result_identity(_attributes), do: {:error, :invalid_cleanup_result_identity}

  defp identity_matches_pending(pending, attributes) do
    if Map.take(pending, @identity_fields) == Map.take(attributes, @identity_fields),
      do: :ok,
      else: {:error, :cleanup_result_identity_mismatch}
  end

  defp identity_matches_registered(assignment, resource_id, attributes) do
    case get_in(assignment, ["cleanup_resources", resource_id]) do
      nil ->
        if unowned_resource_identity?(attributes),
          do: :ok,
          else: {:error, :cleanup_resource_not_registered}

      resource ->
        if same_resource_identity?(resource, attributes),
          do: :ok,
          else: {:error, :cleanup_pending_resource_identity_mismatch}
    end
  end

  defp registration_matches_existing(assignment, resource_id, attributes) do
    case get_in(assignment, ["cleanup_resources", resource_id]) do
      nil ->
        :ok

      resource ->
        cond do
          same_resource_identity?(resource, attributes) -> :ok
          valid_presentation_enrichment?(resource, attributes) -> :ok
          valid_session_enrichment?(resource, attributes) -> :ok
          true -> {:error, :cleanup_resource_registration_conflict}
        end
    end
  end

  defp same_resource_identity?(resource, attributes)
       when is_map(resource) and is_map(attributes) do
    Map.take(resource, @resource_identity_fields) ==
      Map.take(attributes, @resource_identity_fields)
  end

  defp same_resource_identity?(_resource, _attributes), do: false

  defp unowned_resource_identity?(attributes) do
    Enum.all?(~w(pane_id terminal_id session presentation_identity), fn field ->
      is_nil(Map.get(attributes, field))
    end)
  end

  defp normalize_optional_identity(attributes) when is_map(attributes) do
    attributes
    |> Map.put_new("session", nil)
    |> Map.put_new("observed_session", nil)
    |> Map.put_new("presentation_identity", nil)
    |> normalize_resource_id()
  end

  defp normalize_resource_id(%{"role" => role, "execution_id" => execution_id} = attributes)
       when is_binary(role) and is_binary(execution_id),
       do: Map.put_new(attributes, "resource_id", role <> ":" <> execution_id)

  defp normalize_resource_id(attributes), do: attributes

  defp normalize_recorded_resource(attributes) do
    normalized = normalize_optional_identity(attributes)

    Map.put_new(
      normalized,
      "verification_status",
      if(validate_complete_resource_identity(normalized) == :ok,
        do: "verified",
        else: "unverified"
      )
    )
  end

  defp valid_native_session?(
         %{
           "source" => "agent_session",
           "value" => value,
           "terminal_id" => terminal_id,
           "agent" => agent
         },
         terminal_id
       )
       when is_binary(value) and value != "" and is_binary(agent) and agent != "",
       do: true

  defp valid_native_session?(_session, _terminal_id), do: false

  defp assignment(state, task_id) do
    case get_in(state, ["assignments", task_id]) do
      assignment when is_map(assignment) -> {:ok, assignment}
      _ -> {:error, :cleanup_assignment_not_found}
    end
  end

  defp pending_obligation(assignment, obligation_id) do
    case get_in(assignment, ["cleanup_obligations", obligation_id]) do
      obligation when is_map(obligation) -> {:ok, obligation}
      _ -> {:error, :cleanup_pending_not_found}
    end
  end

  defp obligation_id(attributes), do: attributes["resource_id"]

  defp put_obligation(assignment, execution_id, obligation) do
    assignment
    |> Map.get("cleanup_obligations", %{})
    |> Map.put(execution_id, obligation)
  end

  defp put_registered_resource(assignment, resource_id, resource) do
    resources = Map.get(assignment, "cleanup_resources", %{})

    registered =
      case Map.get(resources, resource_id) do
        nil ->
          resource

        existing ->
          cond do
            valid_presentation_enrichment?(existing, resource) ->
              existing
              |> Map.merge(Map.take(resource, ~w(presentation_identity verification_status)))
              |> Map.put("status", "owned")

            valid_session_enrichment?(existing, resource) ->
              Map.merge(existing, Map.take(resource, ~w(session observed_session)))

            true ->
              existing
          end
      end

    Map.put(
      assignment,
      "cleanup_resources",
      Map.put(resources, resource_id, registered)
    )
  end

  defp valid_presentation_enrichment?(existing, attributes) do
    is_map(existing) and is_map(attributes) and
      existing["verification_status"] == "unverified" and
      attributes["verification_status"] == "verified" and
      is_nil(existing["session"]) and is_nil(existing["presentation_identity"]) and
      Map.take(existing, ~w(task_id execution_id role pane_id terminal_id agent_name)) ==
        Map.take(attributes, ~w(task_id execution_id role pane_id terminal_id agent_name)) and
      validate_complete_resource_identity(attributes) == :ok
  end

  defp valid_session_enrichment?(existing, attributes) do
    is_map(existing) and is_map(attributes) and is_nil(existing["session"]) and
      Map.take(existing, @stable_resource_identity_fields) ==
        Map.take(attributes, @stable_resource_identity_fields) and
      valid_native_session?(attributes["session"], attributes["terminal_id"])
  end

  defp resource_status(%{"verification_status" => "unverified"}), do: "unverified"
  defp resource_status(_attributes), do: "owned"

  defp recompute_cleanup_outstanding(assignment),
    do: Map.put(assignment, "cleanup_outstanding", assignment_outstanding?(assignment))

  defp update_registered_resource(assignment, resource_id, update) do
    resources = Map.get(assignment, "cleanup_resources", %{})

    case Map.get(resources, resource_id) do
      nil ->
        assignment

      resource ->
        mutable = Map.take(update, ~w(status reason work_status))

        Map.put(
          assignment,
          "cleanup_resources",
          Map.put(resources, resource_id, Map.merge(resource, mutable))
        )
    end
  end

  defp retained_work_status(assignment) do
    if Map.get(assignment, "status") in ~w(cleanup_pending cleanup_blocked),
      do: Map.get(assignment, "work_status", "dispatched"),
      else: Map.get(assignment, "status", "dispatched")
  end

  defp maybe_restore_status(assignment, work_status) do
    if assignment_outstanding?(assignment),
      do: Map.put(assignment, "status", "cleanup_blocked"),
      else: Map.put(assignment, "status", work_status)
  end
end
