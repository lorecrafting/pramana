defmodule PramanaFoundry.Projections.Projection do
  @moduledoc """
  Deterministic, versioned role projections derived only from validated canonical records.

  Projections reduce context cost; they are never durable authority and never replace the
  canonical record or its SHA-256 digest.
  """

  alias PramanaFoundry.Schema

  @ticket_fields ~w(task_id outcome priority evidence dependencies scope exclusions acceptance_criteria required_checks review_required_checks integration_only_checks checkout base_revision role model profile reasoning risk reviewer_profile work_class workload work_timeout_seconds check_timeout_seconds requested_operations handoff_path review_path environment shared_resources)
  @worker_fields ~w(task_id run_id role accepted_revision assignment_path proposal_path disabled_operations configured_model configured_model_id configured_profile configured_reasoning expected_checkout_head candidate_commit continuation correction handoff)
  @review_fields ~w(schema_version task_id run_id commit verdict findings checks remaining_risks)

  @spec assignment(map()) :: {:ok, map()} | {:error, map()}
  def assignment(canonical) do
    with {:ok, validated} <- Schema.validate(:assignment, canonical) do
      projected =
        case validated["role"] do
          "pm" -> project_pm(validated)
          _worker -> project_worker(validated)
        end

      {:ok, projected}
    end
  end

  @spec review(map()) :: {:ok, map()} | {:error, map()}
  def review(%{"schema_version" => 1} = canonical) do
    unknown = Map.keys(canonical) -- @review_fields

    cond do
      unknown != [] ->
        failure({:unknown_fields, Enum.sort(unknown)}, canonical)

      not Enum.all?(~w(task_id run_id), &non_empty?(canonical[&1])) ->
        failure(:missing_review_identity, canonical)

      not sha1?(canonical["commit"]) ->
        failure({:invalid_type, "commit"}, canonical)

      canonical["verdict"] not in ~w(approved rejected changes_requested) ->
        failure({:invalid_value, "verdict"}, canonical)

      not is_list(canonical["findings"]) or not is_list(canonical["remaining_risks"]) ->
        failure(:invalid_review_evidence, canonical)

      not valid_checks?(canonical["checks"]) ->
        failure(:invalid_review_checks, canonical)

      true ->
        {:ok, Map.put(canonical, "projection_version", 1)}
    end
  end

  def review(canonical), do: failure(:unsupported_version, canonical)

  @spec canonical_digest(binary()) :: binary()
  def canonical_digest(canonical_bytes) when is_binary(canonical_bytes) do
    canonical_bytes
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @spec authority_subset?(map(), map()) :: boolean()
  def authority_subset?(projection, canonical) do
    projection
    |> Map.drop(["projection_version", "ticket", "planning_context"])
    |> Enum.all?(fn {key, value} -> Map.get(canonical, key) == value end) and
      ticket_subset?(projection, canonical) and context_subset?(projection, canonical)
  end

  defp project_worker(canonical) do
    canonical
    |> Map.take(@worker_fields)
    |> Map.put("projection_version", 1)
    |> Map.put("ticket", Map.take(canonical["ticket"], @ticket_fields))
  end

  defp project_pm(canonical) do
    context = canonical["planning_context"]

    compact_context =
      context
      |> Map.drop(["assignments"])
      |> Map.put(
        "assignment_summaries",
        Enum.map(context["assignments"] || [], &assignment_summary/1)
      )

    canonical
    |> Map.take(
      ~w(task_id run_id role accepted_revision assignment_path proposal_path audit_path profile configured_model configured_model_id configured_reasoning max_proposals allowed_operations disabled_operations native_entrypoint)
    )
    |> Map.put("projection_version", 1)
    |> Map.put("planning_context", compact_context)
  end

  defp assignment_summary(assignment) do
    assignment
    |> Map.take(~w(task_id status run_id scheduling_decision blocker))
    |> Map.put("ticket", Map.take(assignment["ticket"] || %{}, @ticket_fields))
  end

  defp ticket_subset?(%{"ticket" => ticket}, %{"ticket" => canonical_ticket}) do
    Enum.all?(ticket, fn {key, value} -> Map.get(canonical_ticket, key) == value end)
  end

  defp ticket_subset?(projection, _canonical), do: not Map.has_key?(projection, "ticket")

  defp context_subset?(%{"planning_context" => projected}, %{"planning_context" => canonical}) do
    projected
    |> Map.drop(["assignment_summaries"])
    |> Enum.all?(fn {key, value} -> Map.get(canonical, key) == value end) and
      projected["assignment_summaries"] ==
        Enum.map(canonical["planning_context"]["assignments"] || [], &assignment_summary/1)
  end

  defp context_subset?(projection, _canonical),
    do: not Map.has_key?(projection, "planning_context")

  defp non_empty?(value), do: is_binary(value) and byte_size(value) > 0

  defp sha1?(value) do
    is_binary(value) and String.match?(value, ~r/^[0-9a-f]{40}$/)
  end

  defp valid_checks?(checks) when is_list(checks) do
    Enum.all?(checks, fn
      %{"command" => command, "exit_code" => exit_code} = check
      when map_size(check) == 2 and is_list(command) and command != [] and
             is_integer(exit_code) ->
        Enum.all?(command, &is_binary/1)

      _ ->
        false
    end)
  end

  defp valid_checks?(_checks), do: false
  defp failure(reason, evidence), do: {:error, %{reason: reason, evidence: evidence}}
end
