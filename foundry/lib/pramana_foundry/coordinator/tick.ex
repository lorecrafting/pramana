defmodule PramanaFoundry.Coordinator.Tick do
  @moduledoc """
  Pure tick lifecycle functions for the coordinator.

  Handles queue processing by starting AgentServer children under the
  AssignmentSupervisor DynamicSupervisor. Each agent runs in its own
  GenServer that manages the full Herdr lifecycle.
  """

  alias PramanaFoundry.Coordinator.State, as: CoordState
  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.LaunchEligibility

  @doc """
  Process the queue: admit queued assignments and start AgentServer children.
  Returns `{new_state, new_registry, log}`.
  """
  def process_queue(
        queue,
        state,
        agent_registry,
        adapter,
        timeout_ms,
        coordinator_pid,
        event_log_path,
        telemetry_path \\ nil,
        max_launch_retries \\ 3,
        launch_opts \\ []
      ) do
    Enum.reduce(queue, {state, agent_registry, []}, fn task_id, {s, reg, log} ->
      existing = get_in(s, ["assignments", task_id])

      cond do
        existing && existing["status"] != "queued" ->
          {s, reg, [{:skipped, task_id, existing["status"]} | log]}

        existing && existing["status"] == "queued" ->
          run_id = :crypto.strong_rand_bytes(8) |> :binary.encode_hex()
          checkout = get_in(existing, ["ticket", "checkout"])
          profiles = Keyword.get(launch_opts, :profiles, %{})
          role_profiles = Keyword.get(launch_opts, :role_profiles, %{})
          now = Keyword.get(launch_opts, :now, System.system_time(:second))

          herdr_opts = Keyword.get(launch_opts, :herdr_opts, [])

          with :ok <- Adapter.require_subscription_route(adapter, herdr_opts),
               {:ok, profile_name} <-
                 LaunchEligibility.select_profile(
                   get_in(existing, ["ticket", "profile"]),
                   role_profiles,
                   :developer
                 ),
               {:ok, profile} <-
                 LaunchEligibility.resolve(profiles, profile_name, :developer, s, now: now),
               {:ok, _assign, ns} <-
                 CoordState.admit_assignment(s, task_id, run_id, "developer", %{
                   "profile" => profile.name
                 }) do
              Checkpoint.append(event_log_path, "assignment_admitted", task_id, run_id,
                "developer", %{"checkout" => checkout, "profile" => profile.name})

              supervisor = Process.whereis(PramanaFoundry.AssignmentSupervisor)

              if is_pid(supervisor) and is_binary(checkout) and herdr_available?() do
                prev_error = get_in(ns, ["assignments", task_id, "error"]) || ""

                child_spec = %{
                  id: task_id,
                  start: {PramanaFoundry.AgentServer, :start_link, [[
                    task_id: task_id,
                    run_id: run_id,
                    checkout: checkout,
                    adapter: adapter,
                    coordinator_pid: coordinator_pid,
                    role: :developer,
                    profile: profile.name,
                    launch_profiles: profiles,
                    launch_state: s,
                    launch_now: now,
                    herdr_timeout_ms: timeout_ms,
                    telemetry_path: telemetry_path,
                    handoff_data: %{"previous_error" => prev_error},
                    herdr_opts: herdr_opts
                  ]]},
                  restart: :temporary
                }

                case DynamicSupervisor.start_child(supervisor, child_spec) do
                  {:ok, pid} when is_pid(pid) ->
                    IO.puts("  tick: started AgentServer #{task_id} (#{inspect(pid)})")
                    {ns, Map.put(reg, task_id, pid), [{:launched, task_id} | log]}

                  {:error, {:already_started, _}} ->
                    IO.puts("  tick: agent already started for #{task_id}")
                    {ns, reg, [{:skipped, task_id, "already_started"} | log]}

                  {:error, reason} ->
                    IO.puts("  tick: DynamicSupervisor failed for #{task_id}: #{inspect(reason)}")
                    current_retries = get_in(ns, ["assignments", task_id, "launch_retries"]) || 0
                    next_retries = current_retries + 1

                    event_name = if next_retries <= max_launch_retries, do: "launch_retried", else: "launch_parked"

                    Checkpoint.append(event_log_path, event_name, task_id, run_id,
                      "developer", %{
                        "retry_count" => next_retries,
                        "max_retries" => max_launch_retries,
                        "stage" => "dynamic_supervisor",
                        "error_reason" => "DynamicSupervisor: #{inspect(reason)}"
                      })

                    retried = apply_launch_retry(task_id, ns, max_launch_retries)
                    {retried, reg, [{:launch_failed, task_id, :dynamic_supervisor_error} | log]}
                end
              else
                reason = cond do
                  not is_pid(supervisor) -> "no_assignment_supervisor"
                  not is_binary(checkout) -> "no_checkout"
                  true -> "herdr_unavailable(no_HERDR_ENV)"
                end
                IO.puts("  Cannot launch #{task_id}: #{reason}")
                current_retries = get_in(ns, ["assignments", task_id, "launch_retries"]) || 0
                next_retries = current_retries + 1

                event_name = if next_retries <= max_launch_retries, do: "launch_retried", else: "launch_parked"

                Checkpoint.append(event_log_path, event_name, task_id, run_id,
                  "developer", %{
                    "retry_count" => next_retries,
                    "max_retries" => max_launch_retries,
                    "stage" => "pre_launch",
                    "error_reason" => reason
                  })

                retried = apply_launch_retry(task_id, ns, max_launch_retries)
                {retried, reg, [{:launch_failed, task_id, reason} | log]}
              end

          else
            {:error, reason} ->
              blocked_reason = LaunchEligibility.reason(reason)
              blocked = block_assignment(s, task_id, :developer, blocked_reason)
              {blocked, reg, [{:launch_blocked, task_id, blocked_reason} | log]}
          end

        true ->
          {s, reg, [{:no_assignment, task_id} | log]}
      end
    end)
  end

  @doc "Check if Herdr is available in the running environment."
  def herdr_available? do
    System.get_env("HERDR_ENV") == "1"
  end

  @doc """
  On launch failure, either re-enqueue (if retries remain) or park permanently.
  Returns the modified state.
  """
  def apply_launch_retry(task_id, state, max_retries \\ 3) do
    current = get_in(state, ["assignments", task_id, "launch_retries"]) || 0
    next = current + 1

    if next <= max_retries do
      IO.puts("    retry #{next}/#{max_retries} for #{task_id}")

      state
      |> put_in(["assignments", task_id, "status"], "queued")
      |> put_in(["assignments", task_id, "launch_retries"], next)
      |> put_in(["assignments", task_id, "error"], "launch_retry(#{next}/#{max_retries})")
      |> Map.update!("queue", fn q -> q ++ [task_id] end)
    else
      IO.puts("    parking #{task_id} after #{next} failed launches (max #{max_retries})")

      state
      |> put_in(["assignments", task_id, "status"], "parked")
      |> put_in(["assignments", task_id, "launch_retries"], next)
      |> put_in(
        ["assignments", task_id, "error"],
        "max_launch_retries(#{max_retries})"
      )
    end
  end

  @doc false
  def block_assignment(state, task_id, role, reason) do
    message = "automatic #{role} launch blocked: #{reason}"

    state
    |> put_in(["assignments", task_id, "status"], "blocked")
    |> put_in(["assignments", task_id, "blocked_role"], to_string(role))
    |> put_in(["assignments", task_id, "blocker"], message)
    |> put_in(["assignments", task_id, "error"], message)
    |> Map.update!("queue", &List.delete(&1, task_id))
  end
end