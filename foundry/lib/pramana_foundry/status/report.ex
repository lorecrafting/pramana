defmodule PramanaFoundry.Status.Report do
  @moduledoc """
  Generates presentation-only revision labels for operational inspection.

  These labels are not acceptance, build, deployment, or activation evidence. FR-17
  supplies the immutable accepted-build protocol.
  """

  @runtime_rev_key :pramana_runtime_implementation_revision
  @developer_owner_states ~w(dispatched prompting working queued_correction)

  @doc """
  Gets the currently loaded runtime implementation revision.
  """
  def runtime_implementation_revision do
    Application.get_env(:pramana_foundry, @runtime_rev_key) || resolve_initial_revision()
  end

  @doc """
  Sets the runtime implementation revision (e.g. at runtime boot or for tests).
  """
  def set_runtime_implementation_revision(revision) when is_binary(revision) do
    Application.put_env(:pramana_foundry, @runtime_rev_key, revision)
    revision
  end

  @doc """
  Updates the presentation label used by legacy restart tests. This does not activate,
  verify, or select code.
  """
  def reconcile_runtime_implementation_revision(accepted_revision)
      when is_binary(accepted_revision) do
    set_runtime_implementation_revision(accepted_revision)
  end

  @doc """
  Generates a comprehensive status report from the current state.
  """
  def generate(state, opts \\ []) do
    accepted_rev = Map.get(state, "accepted_revision")

    runtime_rev =
      Keyword.get_lazy(opts, :runtime_implementation_revision, &runtime_implementation_revision/0)

    revisions_match? = accepted_rev == runtime_rev

    assignments = Map.get(state, "assignments", %{})

    cleanup_resources =
      Map.new(assignments, fn {task_id, assignment} ->
        {task_id, Map.get(assignment, "cleanup_resources", %{})}
      end)

    active_workers =
      assignments
      |> Map.values()
      |> Enum.filter(fn a -> Map.get(a, "status") in @developer_owner_states end)
      |> Enum.map(fn a ->
        %{
          "task_id" => get_in(a, ["ticket", "task_id"]) || Map.get(a, "task_id"),
          "run_id" => Map.get(a, "run_id"),
          "role" => Map.get(a, "role", "developer"),
          "profile" => get_in(a, ["ticket", "profile"]) || Map.get(a, "configured_profile"),
          "status" => Map.get(a, "status")
        }
      end)

    integration = Map.get(state, "integration", %{})
    pm = Map.get(state, "pm", %{})

    report = %{
      "status" => Map.get(state, "status", "running"),
      "recovery_error" => Map.get(state, "recovery_error"),
      "accepted_revision" => accepted_rev,
      "runtime_implementation_revision" => runtime_rev,
      "revisions_match?" => revisions_match?,
      "revision_labels_authoritative?" => false,
      "paused" => Map.get(state, "paused", false),
      "stop_requested" => Map.get(state, "stop_requested", false),
      "queue" => Map.get(state, "queue", []),
      "active_workers" => active_workers,
      "cleanup_resources" => cleanup_resources,
      "integration" => %{
        "owner" => Map.get(integration, "owner"),
        "candidate" => Map.get(integration, "candidate")
      },
      "pm" => %{
        "status" => Map.get(pm, "status", "idle"),
        "planning_attempt_halt" => Map.get(pm, "planning_attempt_halt")
      }
    }

    if not revisions_match? and is_binary(accepted_rev) and is_binary(runtime_rev) do
      Map.put(
        report,
        "revision_disagreement",
        "running implementation #{runtime_rev} differs from accepted #{accepted_rev}; controlled restart required"
      )
    else
      report
    end
  end

  defp resolve_initial_revision do
    case System.cmd("git", ["rev-parse", "HEAD"], stderr_to_stdout: true) do
      {head, 0} ->
        rev = String.trim(head)
        set_runtime_implementation_revision(rev)
        rev

      _ ->
        "0000000000000000000000000000000000000000"
    end
  end
end
