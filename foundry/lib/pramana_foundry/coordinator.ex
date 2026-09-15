defmodule PramanaFoundry.Coordinator do
  @moduledoc """
  Sole in-VM coordinator boundary. Its state is a rebuildable projection indexed from
  the durable event log. Every state mutation emits a checkpoint event through
  `Checkpoint.append/6` before the in-memory update, making the event log the source
  of truth and in-memory state a disposable cache.
  """
  use GenServer

  alias PramanaFoundry.Coordinator.State, as: CoordState
  alias PramanaFoundry.PM
  alias PramanaFoundry.Scheduler
  alias PramanaFoundry.Herdr.Adapter
  alias PramanaFoundry.Herdr.Runner
  alias PramanaFoundry.Transition
  alias PramanaFoundry.Status
  alias PramanaFoundry.Effects.Checkpoint
  alias PramanaFoundry.Coordinator.Tick
  alias PramanaFoundry.LogStore
  alias PramanaFoundry.LaunchEligibility
  alias PramanaFoundry.RuntimeRoot
  alias PramanaFoundry.RuntimeLease
  alias PramanaFoundry.Cleanup

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Foundation compatibility
  def transition(command), do: GenServer.call(__MODULE__, {:transition, command})
  def replace_projection(records), do: GenServer.call(__MODULE__, {:replace_projection, records})
  def projection, do: GenServer.call(__MODULE__, :projection)

  # State inspection and lifecycle
  def state, do: GenServer.call(__MODULE__, :state)
  def status(opts \\ []), do: GenServer.call(__MODULE__, {:status, opts})
  def pause, do: GenServer.call(__MODULE__, :pause)
  def resume, do: GenServer.call(__MODULE__, :resume)
  def request_stop, do: GenServer.call(__MODULE__, :request_stop)
  def reset(opts \\ []), do: GenServer.call(__MODULE__, {:reset, opts})

  # Workflow operations
  def unblock_ticket(task_id),
    do: GenServer.call(__MODULE__, {:unblock_ticket, task_id})

  def enqueue_ticket(ticket), do: GenServer.call(__MODULE__, {:enqueue_ticket, ticket})
  def plan_dispatch(opts \\ []), do: GenServer.call(__MODULE__, {:plan_dispatch, opts})

  def admit_assignment(task_id, run_id, role, opts \\ %{}),
    do: GenServer.call(__MODULE__, {:admit_assignment, task_id, run_id, role, opts})

  def receive_handoff(task_id, handoff, opts \\ []),
    do: GenServer.call(__MODULE__, {:receive_handoff, task_id, handoff, opts})

  def receive_review(task_id, review, opts \\ []),
    do: GenServer.call(__MODULE__, {:receive_review, task_id, review, opts})

  def integrate(task_id, opts \\ []),
    do: GenServer.call(__MODULE__, {:integrate, task_id, opts})

  def apply_pm_proposals(proposals, opts \\ []),
    do: GenServer.call(__MODULE__, {:apply_pm_proposals, proposals, opts})

  def reset_pm_attempts(payload),
    do: GenServer.call(__MODULE__, {:reset_pm_attempts, payload})

  def health do
    GenServer.call(__MODULE__, :health)
  end

  def record_cleanup(phase, attributes),
    do: GenServer.call(__MODULE__, {:record_cleanup, phase, attributes})

  @doc "Look up the AgentServer PID for a running agent by task_id."
  def agent_pid(task_id) do
    GenServer.call(__MODULE__, {:agent_pid, task_id})
  end

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)

    accepted_rev =
      Keyword.get(opts, :accepted_revision, "c8ede6a17323c080124aa4512a83494b537648a5")

    poll_ms = Keyword.get(opts, :poll_ms, 15_000)
    herdr_command = Keyword.get(opts, :herdr_command, "herdr")
    herdr_timeout = Keyword.get(opts, :herdr_timeout_ms, 30_000)
    enable_tick = Keyword.get(opts, :enable_tick, false)
    require_runtime_owner = Keyword.get(opts, :require_runtime_owner, false)
    max_launch_retries = Keyword.get(opts, :max_launch_retries, 3)
    max_work_retries = Keyword.get(opts, :max_work_retries, 2)

    launch_profiles =
      Keyword.get(
        opts,
        :launch_profiles,
        Application.get_env(:pramana_foundry, :launch_profiles, %{})
      )

    launch_now_fn = Keyword.get(opts, :launch_now_fn, fn -> System.system_time(:second) end)

    launch_role_profiles =
      Keyword.get(
        opts,
        :launch_role_profiles,
        Application.get_env(:pramana_foundry, :launch_role_profiles, %{})
      )

    herdr_opts = Keyword.get(opts, :herdr_opts, [])

    telemetry_path =
      Keyword.get(opts, :telemetry_log_path) ||
        Path.join(
          RuntimeRoot.fetch!(),
          "state/current/telemetry.jsonl"
        )

    event_log_path =
      Keyword.get(opts, :event_log_path) ||
        Path.join(
          RuntimeRoot.fetch!(),
          "state/current/events.jsonl"
        )

    coordinator_log_path =
      Keyword.get(opts, :coordinator_log_path) ||
        Path.join(
          RuntimeRoot.fetch!(),
          "state/current/coordinator.jsonl"
        )

    adapter = Adapter.new(Runner.System, herdr_command)

    case Checkpoint.events(event_log_path) do
      {:error, reason} ->
        recovery_state = recovery_state(accepted_rev, reason)

        {:ok,
         coordinator_data(recovery_state, nil, nil, adapter, opts,
           poll_ms: poll_ms,
           herdr_timeout: herdr_timeout,
           max_launch_retries: max_launch_retries,
           max_work_retries: max_work_retries,
           telemetry_path: telemetry_path,
           event_log_path: event_log_path,
           coordinator_log_path: coordinator_log_path,
           launch_profiles: launch_profiles,
           launch_role_profiles: launch_role_profiles,
           launch_now_fn: launch_now_fn,
           herdr_opts: herdr_opts,
           require_runtime_owner: require_runtime_owner,
           recovery_error: reason
         )}

      {:ok, events} ->
        try do
          with {:ok, %{projection: projection, state: recovered_state}} <-
                 Transition.rebuild(events, accepted_revision: accepted_rev) do
            if startup_reconciliation_required?(recovered_state) do
              throw(
                {:persistence_failed_with_state,
                 {:legacy_startup_reconciliation_suspended,
                  "FR-03 containment requires FR-07/FR-08 recovery transactions"},
                 recovered_state, projection}
              )
            end

            recovered_state = reenqueue_stale_dispatched(recovered_state, events, event_log_path)

            IO.puts(
              "  event log: #{length(events)} events, #{map_size(Map.get(recovered_state, "assignments", %{}))} assignments recovered"
            )

            tick_ref = if enable_tick, do: Process.send_after(self(), :tick, poll_ms), else: nil

            cond do
              enable_tick and not process_has_herdr_env?() ->
                IO.puts(
                  "WARN: Coordinator tick enabled but HERDR_ENV is not set — agent dispatch will fail"
                )

              enable_tick ->
                IO.puts(
                  "Coordinator init: tick=#{enable_tick} poll=#{poll_ms}ms (COORDINATOR_TICK=1 via env)"
                )

              true ->
                IO.puts(
                  "Coordinator init: tick disabled (set COORDINATOR_TICK=1 in daemon env to enable)"
                )
            end

            IO.puts("  herdr_command=#{herdr_command} herdr_timeout=#{herdr_timeout}ms")

            {:ok,
             coordinator_data(recovered_state, projection, tick_ref, adapter, opts,
               poll_ms: poll_ms,
               herdr_timeout: herdr_timeout,
               max_launch_retries: max_launch_retries,
               max_work_retries: max_work_retries,
               telemetry_path: telemetry_path,
               event_log_path: event_log_path,
               coordinator_log_path: coordinator_log_path,
               launch_profiles: launch_profiles,
               launch_role_profiles: launch_role_profiles,
               launch_now_fn: launch_now_fn,
               herdr_opts: herdr_opts,
               require_runtime_owner: require_runtime_owner,
               recovery_error: nil
             )}
          else
            {:error, reason} -> throw({:persistence_failed, {:invalid_replay, reason}})
          end
        catch
          :throw, {:persistence_failed_with_state, reason, recovered_state, projection} ->
            recovery_state =
              recovered_state
              |> Map.put("status", "recovery_required")
              |> Map.put("recovery_error", inspect(reason))

            {:ok,
             coordinator_data(recovery_state, projection, nil, adapter, opts,
               poll_ms: poll_ms,
               herdr_timeout: herdr_timeout,
               max_launch_retries: max_launch_retries,
               max_work_retries: max_work_retries,
               telemetry_path: telemetry_path,
               event_log_path: event_log_path,
               coordinator_log_path: coordinator_log_path,
               launch_profiles: launch_profiles,
               launch_role_profiles: launch_role_profiles,
               launch_now_fn: launch_now_fn,
               herdr_opts: herdr_opts,
               require_runtime_owner: require_runtime_owner,
               recovery_error: reason
             )}

          :throw, {:persistence_failed, reason} ->
            recovery_state = recovery_state(accepted_rev, reason)

            {:ok,
             coordinator_data(recovery_state, nil, nil, adapter, opts,
               poll_ms: poll_ms,
               herdr_timeout: herdr_timeout,
               max_launch_retries: max_launch_retries,
               max_work_retries: max_work_retries,
               telemetry_path: telemetry_path,
               event_log_path: event_log_path,
               coordinator_log_path: coordinator_log_path,
               launch_profiles: launch_profiles,
               launch_role_profiles: launch_role_profiles,
               launch_now_fn: launch_now_fn,
               herdr_opts: herdr_opts,
               require_runtime_owner: require_runtime_owner,
               recovery_error: reason
             )}
        end
    end
  end

  # ── handle_call ──

  @impl true
  def handle_call({:status, _opts}, _from, %{recovery_error: reason, state: state} = data)
      when not is_nil(reason) do
    {:reply, Status.status(state), data}
  end

  def handle_call({:agent_pid, task_id}, _from, %{recovery_error: reason} = data)
      when not is_nil(reason) do
    {:reply, Map.get(data.agent_registry, task_id), data}
  end

  def handle_call(message, _from, %{recovery_error: reason} = data)
      when not is_nil(reason) and message not in [:state, :projection, :health] do
    {:reply, {:error, {:recovery_required, reason}}, data}
  end

  def handle_call({:transition, command}, _from, %{projection: projection} = data) do
    case Transition.plan(projection, command) do
      {:ok, intent} -> {:reply, {:ok, intent}, data}
      {:error, _reason} = error -> {:reply, error, data}
    end
  end

  def handle_call({:reset, opts}, _from, data) do
    accepted_rev =
      Keyword.get(opts, :accepted_revision, "c8ede6a17323c080124aa4512a83494b537648a5")

    with {:ok, %{projection: projection, state: new_state}} <-
           Transition.rebuild([], accepted_revision: accepted_rev) do
      extra = Map.drop(data, [:projection, :state])
      {:reply, :ok, Map.merge(%{projection: projection, state: new_state}, extra)}
    end
  end

  def handle_call(:projection, _from, %{projection: projection} = data) do
    {:reply, projection, data}
  end

  def handle_call(:state, _from, %{state: state} = data) do
    {:reply, state, data}
  end

  def handle_call({:status, _opts}, _from, %{state: coord_state} = data) do
    {:reply, Status.status(coord_state), data}
  end

  def handle_call(:pause, _from, %{state: state} = data) do
    {:reply, :ok, %{data | state: CoordState.pause(state)}}
  end

  def handle_call(:resume, _from, %{state: state} = data) do
    {:reply, :ok, %{data | state: CoordState.resume(state)}}
  end

  def handle_call(:request_stop, _from, %{state: state} = data) do
    {:reply, :ok, %{data | state: CoordState.request_stop(state)}}
  end

  def handle_call(
        {:unblock_ticket, task_id},
        _from,
        %{state: state} = data
      ) do
    assignment = get_in(state, ["assignments", task_id])

    cond do
      is_nil(assignment) ->
        {:reply, {:error, "unknown assignment: #{task_id}"}, data}

      assignment["status"] != "parked" ->
        {:reply, {:error, "task #{task_id} is not parked (status: #{assignment["status"]})"},
         data}

      true ->
        run_id = Map.get(assignment, "run_id", "pending")

        updated =
          assignment
          |> Map.put("status", "queued")
          |> Map.put("launch_retries", 0)
          |> Map.put("error", nil)
          |> Map.put("blocker", nil)

        updated_queue = state["queue"] ++ [task_id]

        new_state =
          state
          |> Map.put("assignments", Map.put(state["assignments"], task_id, updated))
          |> Map.put("queue", updated_queue)

        persist_call(
          data,
          "ticket_re_enqueued",
          task_id,
          run_id,
          "system",
          %{
            "reason" => "manual_unblock",
            "previous_status" => "parked"
          },
          fn -> {:reply, :ok, %{data | state: new_state}} end
        )
    end
  end

  def handle_call({:enqueue_ticket, ticket}, _from, %{state: state} = data) do
    # Validate first, then write event, then update state.
    # This prevents a failed validation from leaving orphan events in the log.
    case CoordState.enqueue_ticket(state, ticket) do
      {:ok, new_state} ->
        task_id = Map.get(ticket, "task_id")

        persist_call(
          data,
          "ticket_enqueued",
          task_id,
          "pending",
          "system",
          %{
            "ticket" => ticket,
            "priority" => Map.get(ticket, "priority", "P3")
          },
          fn -> {:reply, :ok, %{data | state: new_state}} end
        )

      {:error, reason} ->
        {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:plan_dispatch, opts}, _from, %{state: state} = data) do
    {:reply, Scheduler.plan_dispatch(state, opts), data}
  end

  def handle_call({:admit_assignment, task_id, run_id, role, opts}, _from, %{state: state} = data) do
    case CoordState.admit_assignment(state, task_id, run_id, role, opts) do
      {:ok, assign, new_state} -> {:reply, {:ok, assign}, %{data | state: new_state}}
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:receive_handoff, task_id, handoff, opts}, _from, %{state: state} = data) do
    run_id = get_in(state, ["assignments", task_id, "run_id"]) || "pending"

    case CoordState.receive_handoff(state, task_id, handoff, opts) do
      {:ok, assignment, new_state} ->
        attrs = %{"handoff" => handoff}

        persist_call(data, "handoff_received", task_id, run_id, "developer", attrs, fn ->
          new_run_id = :crypto.strong_rand_bytes(8) |> :binary.encode_hex()

          supervisor = Process.whereis(PramanaFoundry.AssignmentSupervisor)
          checkout = get_in(state, ["assignments", task_id, "ticket", "checkout"])
          profile_result = resolve_reviewer_profile(data, new_state, task_id)

          {final_state, final_registry} =
            if is_pid(supervisor) and is_binary(checkout) and Tick.herdr_available?() and
                 match?({:ok, _}, profile_result) do
              {:ok, profile} = profile_result

              child_spec = %{
                id: "#{task_id}-review",
                start:
                  {PramanaFoundry.AgentServer, :start_link,
                   [
                     [
                       task_id: task_id,
                       run_id: new_run_id,
                       role: :reviewer,
                       checkout: checkout,
                       adapter: data.herdr_adapter,
                       coordinator_pid: self(),
                       profile: profile.name,
                       launch_profiles: data.launch_profiles,
                       launch_state: new_state,
                       launch_now: data.launch_now_fn.(),
                       handoff_data: handoff,
                       herdr_timeout_ms: data.herdr_timeout,
                       telemetry_path: data.telemetry_path,
                       herdr_opts: data.herdr_opts
                     ]
                   ]},
                restart: :temporary
              }

              case DynamicSupervisor.start_child(supervisor, child_spec) do
                {:ok, pid} when is_pid(pid) ->
                  IO.puts("  Launched reviewer #{new_run_id} for #{task_id} (#{inspect(pid)})")
                  # Store reviewer's run_id on the assignment so review validation
                  # can accept the reviewer's identity
                  state_with_run_id =
                    put_in(new_state, ["assignments", task_id, "reviewer_run_id"], new_run_id)

                  {state_with_run_id, Map.put(data.agent_registry, "#{task_id}-review", pid)}

                {:error, reason} ->
                  IO.puts("  Failed to launch reviewer for #{task_id}: #{inspect(reason)}")
                  {new_state, data.agent_registry}
              end
            else
              block_reviewer_if_ineligible(data, new_state, task_id, profile_result)
            end

          {:reply, {:ok, assignment},
           %{data | state: final_state, agent_registry: final_registry}}
        end)

      {:error, reason, new_state} ->
        persist_call(
          data,
          "handoff_received",
          task_id,
          run_id,
          "developer",
          %{
            "handoff" => handoff,
            "rejected" => true,
            "reason" => reason
          },
          fn -> {:reply, {:error, reason}, %{data | state: new_state}} end
        )

      {:error, reason} ->
        {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:receive_review, task_id, review, opts}, _from, %{state: state} = data) do
    run_id = get_in(state, ["assignments", task_id, "run_id"]) || "pending"
    verdict = Map.get(review, "verdict", "unknown")
    correction_count = get_in(state, ["assignments", task_id, "correction_count"]) || 0

    case CoordState.receive_review(state, task_id, review, opts) do
      {:ok, assignment, new_state} ->
        persist_call(
          data,
          "review_received",
          task_id,
          run_id,
          "reviewer",
          %{
            "review" => review,
            "verdict" => verdict,
            "correction_count" => correction_count
          },
          fn ->
            # Forward review outcome to the AgentServer if it's still alive
            agent_pid = data.agent_registry[task_id]
            new_status = Map.get(assignment, "status", "")

            cond do
              new_status == "queued" and is_pid(agent_pid) ->
                # Correction needed — tell the running agent
                send(agent_pid, {:apply_correction, review})

              new_status == "review_approved" and is_pid(agent_pid) ->
                # Approved — agent can clean up
                send(agent_pid, :review_approved)

              true ->
                :ok
            end

            {:reply, {:ok, assignment}, %{data | state: new_state}}
          end
        )

      {:error, reason, new_state} ->
        # Determine if this is a review retry (handoff_received indicates retry)
        new_status = get_in(new_state, ["assignments", task_id, "status"])
        review_retries = get_in(new_state, ["assignments", task_id, "review_retries"]) || 0

        attrs = %{
          "review" => review,
          "verdict" => verdict,
          "correction_count" => correction_count,
          "rejected" => true,
          "reason" => reason,
          "review_retry_count" => review_retries
        }

        persist_call(data, "review_received", task_id, run_id, "reviewer", attrs, fn ->
          # If the task was returned to handoff_received (review retry), launch a new reviewer
          {new_data, final_state} =
            if new_status == "handoff_received" and review_retries > 0 do
              maybe_launch_reviewer_retry(data, task_id, new_state)
            else
              {data, new_state}
            end

          {:reply, {:error, reason}, %{new_data | state: final_state}}
        end)

      {:error, reason} ->
        {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:integrate, _task_id, _opts}, _from, data) do
    {:reply,
     {:error,
      {:suspended_until_transactional_integration,
       "FR-05 containment: no intent, check, Git effect, or accepted-state change; FR-13/FR-14 restore verified promotion"}},
     data}
  end

  def handle_call({:apply_pm_proposals, proposals, opts}, _from, %{state: state} = data) do
    case PM.apply_proposals(state, proposals, opts) do
      {:ok, new_state} ->
        task_id = Map.get(List.first(proposals) || %{}, "task_id", "pm-batch")
        run_id = :crypto.strong_rand_bytes(8) |> :binary.encode_hex()

        persist_call(
          data,
          "pm_proposal_created",
          task_id,
          run_id,
          "pm",
          %{
            "proposals" => proposals
          },
          fn -> {:reply, {:ok, new_state}, %{data | state: new_state}} end
        )

      {:error, reason} ->
        {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:reset_pm_attempts, payload}, _from, %{state: state} = data) do
    case CoordState.reset_pm_attempts(state, payload) do
      {:ok, record, new_state} -> {:reply, {:ok, record}, %{data | state: new_state}}
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  def handle_call(:health, _from, %{state: state, agent_registry: reg} = data) do
    queue = Map.get(state, "queue", [])
    assignments = Map.get(state, "assignments", %{})

    health = %{
      status: Map.get(state, "status", "running"),
      recovery_error: Map.get(state, "recovery_error"),
      queue_depth: length(queue),
      active_assignments: map_size(assignments),
      running_agents: map_size(reg)
    }

    {:reply, health, data}
  end

  def handle_call({:agent_pid, task_id}, _from, %{agent_registry: reg} = data) do
    {:reply, Map.get(reg, task_id), data}
  end

  def handle_call({:record_cleanup, phase, attributes}, _from, data)
      when phase in [:pending, :result] and is_map(attributes) do
    event = if phase == :pending, do: "cleanup_pending", else: "cleanup_result"
    task_id = Map.get(attributes, "task_id", "")
    run_id = Map.get(attributes, "execution_id", "")
    role = Map.get(attributes, "role", "")

    apply_cleanup =
      if phase == :pending,
        do: &Cleanup.apply_pending/2,
        else: &Cleanup.apply_result/2

    with {:ok, next_state} <- apply_cleanup.(data.state, attributes) do
      persist_call(
        data,
        event,
        task_id,
        run_id,
        role,
        durable_cleanup_attributes(attributes),
        fn ->
          {:reply, :ok, %{data | state: next_state}}
        end
      )
    else
      {:error, reason} -> {:reply, {:error, reason}, data}
    end
  end

  def handle_call({:record_cleanup, :resource, attributes}, _from, data)
      when is_map(attributes) do
    attributes = ensure_resource_id(attributes)
    task_id = Map.get(attributes, "task_id", "")
    run_id = Map.get(attributes, "execution_id", "")
    role = Map.get(attributes, "role", "")

    with {:ok, registered_state} <- Cleanup.register_resource(data.state, attributes) do
      next_state = project_resource_compatibility(registered_state, attributes)

      persist_call(
        data,
        "pane_created",
        task_id,
        run_id,
        role,
        pane_created_attributes(attributes),
        fn -> {:reply, :ok, %{data | state: next_state}} end
      )
    else
      {:error, reason} ->
        {:reply, {:error, {:recovery_required, reason}}, enter_recovery(data, reason)}
    end
  end

  # ── handle_info ──

  @impl true
  def handle_info(:tick, %{recovery_error: reason} = data) when not is_nil(reason),
    do: {:noreply, data}

  def handle_info({event, task_id, _run_id, _reason, info}, %{recovery_error: reason} = data)
      when event in [:agent_completed, :agent_crashed] and not is_nil(reason),
      do: {:noreply, maybe_drop_after_cleanup(data, task_id, info)}

  def handle_info({:agent_launched, task_id, _result, info}, %{recovery_error: reason} = data)
      when not is_nil(reason) do
    data = preserve_unregistered_launch_resource(data, info)
    {:noreply, maybe_drop_after_cleanup(data, task_id, info)}
  end

  def handle_info(
        :tick,
        %{
          state: state,
          poll_ms: poll_ms,
          agent_registry: agent_registry,
          event_log_path: event_log_path,
          max_launch_retries: max_launch_retries
        } = data
      ) do
    case ensure_runtime_owner(data) do
      {:error, reason} ->
        {:noreply, enter_recovery(data, reason)}

      :ok ->
        tick_ref = Process.send_after(self(), :tick, poll_ms)
        data = %{data | tick_ref: tick_ref}

        LogStore.append(Map.get(data, :coordinator_log_path), %{
          "event" => "tick_start",
          "source" => "coordinator",
          "queue_size" => length(Map.get(state, "queue", [])),
          "assignments" => map_size(Map.get(state, "assignments", %{})),
          "paused" => Map.get(state, "paused", false)
        })

        if Map.get(state, "paused", false) || Map.get(state, "stop_requested", false) do
          {:noreply, data}
        else
          queue = Map.get(state, "queue", [])

          try do
            {new_state, new_registry, log} =
              Tick.process_queue(
                queue,
                state,
                agent_registry,
                data.herdr_adapter,
                data.herdr_timeout,
                self(),
                event_log_path,
                data.telemetry_path,
                max_launch_retries,
                profiles: data.launch_profiles,
                role_profiles: data.launch_role_profiles,
                now: data.launch_now_fn.(),
                append_fn: checkpoint_append_fn(data),
                herdr_opts: data.herdr_opts
              )

            # The old post-effect tick summary append is suspended until FR-07/FR-08
            # can commit it atomically with admission. It remains diagnostic only.
            LogStore.append(Map.get(data, :coordinator_log_path), %{
              "event" => "tick_processed",
              "source" => "coordinator",
              "queue_size" => length(queue),
              "active_assignments" => map_size(Map.get(new_state, "assignments", %{}))
            })

            log
            |> Enum.reverse()
            |> Enum.each(fn
              {:skipped, _id, _status} ->
                :ok

              {:admission_suspended, :cleanup_outstanding} ->
                LogStore.append(Map.get(data, :coordinator_log_path), %{
                  "event" => "tick_admission_suspended",
                  "source" => "coordinator",
                  "reason" => "cleanup_outstanding",
                  "queue_size" => length(Map.get(new_state, "queue", []))
                })

              {:admitted, id} ->
                IO.puts("  tick: admitted #{id}")

              {:launch_failed, id, reason} ->
                IO.puts("  tick: launch failed #{id}: #{inspect(reason)}")

                emit_telemetry(Map.get(data, :telemetry_path), "agent_launch", %{
                  "task_id" => id,
                  "phase" => "agent_launch",
                  "outcome" => "launch_failed",
                  "reason" => inspect(reason)
                })

              {:launch_blocked, id, reason} ->
                IO.puts("  tick: launch blocked #{id}: #{reason}")

                emit_telemetry(Map.get(data, :telemetry_path), "agent_launch", %{
                  "task_id" => id,
                  "phase" => "agent_launch",
                  "outcome" => "blocked",
                  "reason" => reason
                })

              {:error, id, reason} ->
                IO.puts("  tick: error #{id}: #{inspect(reason)}")

              {:no_assignment, _id} ->
                :ok

              {:launched, id} ->
                IO.puts("  tick: launched #{id}")
            end)

            {:noreply, %{data | state: new_state, agent_registry: new_registry}}
          catch
            :throw, {:persistence_failed, reason} ->
              {:noreply, enter_recovery(data, reason)}

            kind, error ->
              clp = Map.get(data, :coordinator_log_path)

              LogStore.append(clp, %{
                "event" => "tick_error",
                "source" => "coordinator",
                "kind" => kind,
                "error" => inspect(error),
                "queue_size" => length(queue)
              })

              IO.puts("  tick CRASHED: #{kind} #{inspect(error)}")
              {:noreply, %{data | state: state}}
          end
        end
    end
  end

  def handle_info({:agent_launched, task_id, _result, _info} = message, data) do
    if reviewer_launch_blocked?(data.state, task_id) do
      {:noreply, drop_agent_registry(data, task_id)}
    else
      handle_agent_launched(message, data)
    end
  end

  def handle_info({:agent_completed, task_id, _run_id, _reason, _info} = message, data) do
    if reviewer_launch_blocked?(data.state, task_id) do
      {:noreply, drop_agent_registry(data, task_id)}
    else
      handle_agent_completed(message, data)
    end
  end

  def handle_info({:agent_crashed, task_id, _run_id, _reason, _info} = message, data) do
    if reviewer_launch_blocked?(data.state, task_id) do
      {:noreply, drop_agent_registry(data, task_id)}
    else
      handle_agent_crashed(message, data)
    end
  end

  def handle_info(msg, data) do
    IO.puts("  coordinator unexpected msg: #{inspect(msg)}")
    {:noreply, data}
  end

  @impl true
  def terminate(reason, data) do
    if Map.get(data, :require_runtime_owner, false) and clean_shutdown?(reason) and
         safe_clean_shutdown_state?(data.state) do
      try do
        RuntimeLease.allow_clean_release()
      catch
        :exit, _reason -> :ok
      end
    end

    :ok
  end

  defp handle_agent_launched({:agent_launched, task_id, :ok, info}, %{state: state} = data) do
    IO.puts("  Agent launched for #{task_id}: pane=#{info[:pane_id]} name=#{info[:agent_name]}")

    LogStore.append(Map.get(data, :coordinator_log_path), %{
      "event" => "agent_launched",
      "source" => "coordinator",
      "task_id" => task_id,
      "pane" => info[:pane_id],
      "agent" => info[:agent_name]
    })

    emit_telemetry(Map.get(data, :telemetry_path), "agent_launch", %{
      "task_id" => task_id,
      "phase" => "launch",
      "outcome" => "dispatched",
      "agent" => info[:agent_name],
      "pane" => info[:pane_id]
    })

    new_state = put_in(state, ["assignments", task_id, "dispatched_at"], formatted_now())
    {:noreply, %{data | state: new_state}}
  end

  defp handle_agent_launched(
         {:agent_launched, task_id, {:error, stage, reason}, info},
         %{state: state, max_launch_retries: max_retries} = data
       ) do
    IO.puts("  Agent launch failed for #{task_id} at #{stage}: #{inspect(reason)}")

    current_retries = get_in(state, ["assignments", task_id, "launch_retries"]) || 0
    new_retries = current_retries + 1
    run_id = get_in(state, ["assignments", task_id, "run_id"]) || "pending"

    cond do
      cleanup_outstanding?(state, task_id) or unresolved_cleanup_receipt?(info) ->
        persist_info(
          data,
          "launch_parked",
          task_id,
          run_id,
          "developer",
          Map.merge(
            %{
              "retry_count" => current_retries,
              "max_retries" => max_retries,
              "stage" => to_string(stage),
              "error_reason" => "cleanup unresolved after launch failure: #{inspect(reason)}"
            },
            cleanup_attributes(info)
          ),
          fn ->
            new_state =
              state
              |> Cleanup.preserve_work_status(task_id, "launch_failed")
              |> put_in(
                ["assignments", task_id, "error"],
                "cleanup unresolved after launch failure: #{inspect(reason)}"
              )

            {:noreply, %{data | state: new_state}}
          end
        )

      new_retries <= max_retries ->
        IO.puts("  Re-enqueueing #{task_id} for retry #{new_retries}/#{max_retries}")

        # Write-ahead: record retry event before state mutation
        persist_info(
          data,
          "launch_retried",
          task_id,
          run_id,
          "developer",
          Map.merge(
            %{
              "retry_count" => new_retries,
              "max_retries" => max_retries,
              "stage" => to_string(stage),
              "error_reason" => "launch_failed: #{stage}: #{inspect(reason)}"
            },
            cleanup_attributes(info)
          ),
          fn ->
            new_state =
              state
              |> put_in(["assignments", task_id, "status"], "queued")
              |> put_in(["assignments", task_id, "launch_retries"], new_retries)
              |> put_in(
                ["assignments", task_id, "error"],
                "launch_failed: #{stage}: #{inspect(reason)}"
              )
              |> Map.update!("queue", fn q -> q ++ [task_id] end)

            LogStore.append(Map.get(data, :coordinator_log_path), %{
              "event" => "agent_launch_retry",
              "source" => "coordinator",
              "task_id" => task_id,
              "stage" => stage,
              "reason" => inspect(reason),
              "retry" => new_retries,
              "max" => max_retries
            })

            emit_telemetry(Map.get(data, :telemetry_path), "agent_launch", %{
              "task_id" => task_id,
              "phase" => "launch",
              "outcome" => "retry",
              "stage" => to_string(stage),
              "reason" => inspect(reason),
              "retry" => new_retries
            })

            new_registry =
              data.agent_registry
              |> Map.drop([task_id])
              |> Map.delete("#{task_id}-review")

            {:noreply, %{data | state: new_state, agent_registry: new_registry}}
          end
        )

      true ->
        IO.puts(
          "  Parking #{task_id} after #{new_retries} failed launch attempts (max #{max_retries})"
        )

        # Write-ahead: record park event before state mutation
        persist_info(
          data,
          "launch_parked",
          task_id,
          run_id,
          "developer",
          Map.merge(
            %{
              "retry_count" => new_retries,
              "max_retries" => max_retries,
              "stage" => to_string(stage),
              "error_reason" => "max_launch_retries(#{max_retries}): #{stage}: #{inspect(reason)}"
            },
            cleanup_attributes(info)
          ),
          fn ->
            new_state =
              state
              |> put_in(["assignments", task_id, "status"], "parked")
              |> put_in(["assignments", task_id, "launch_retries"], new_retries)
              |> put_in(
                ["assignments", task_id, "error"],
                "max_launch_retries(#{max_retries}): #{stage}: #{inspect(reason)}"
              )

            LogStore.append(Map.get(data, :coordinator_log_path), %{
              "event" => "agent_launch_parked",
              "source" => "coordinator",
              "task_id" => task_id,
              "stage" => stage,
              "reason" => inspect(reason),
              "retries" => new_retries,
              "max" => max_retries
            })

            emit_telemetry(Map.get(data, :telemetry_path), "agent_launch", %{
              "task_id" => task_id,
              "phase" => "launch",
              "outcome" => "parked",
              "stage" => to_string(stage),
              "reason" => inspect(reason),
              "retries" => new_retries
            })

            new_registry =
              data.agent_registry
              |> Map.drop([task_id])
              |> Map.delete("#{task_id}-review")

            {:noreply, %{data | state: new_state, agent_registry: new_registry}}
          end
        )
    end
  end

  defp handle_agent_completed(
         {:agent_completed, task_id, run_id, reason, info},
         %{state: state, telemetry_path: telemetry_path} = data
       ) do
    IO.puts("  Agent completed #{task_id}: #{inspect(reason)}")

    # Write-ahead: record completion event before state mutation
    persist_info(
      data,
      "task_completed",
      task_id,
      run_id,
      "developer",
      Map.merge(%{"reason" => inspect(reason)}, cleanup_attributes(info)),
      fn ->
        work_status =
          case reason do
            {:handoff, :ok} ->
              # If status is already "review_approved" (from coordinator's receive_review),
              # don't overwrite — the review already went through.
              current = current_work_status(state, task_id)

              if current in ~w(review_approved review) do
                current
              else
                "review"
              end

            {:handoff, {:error, _}} ->
              # Handoff was rejected. If the task was already re-enqueued by the
              # handoff handler (auto-retry), don't overwrite that status.
              current = current_work_status(state, task_id)

              if current == "queued" do
                current
              else
                "handoff_rejected"
              end

            {:error, _r} ->
              "failed"

            _ ->
              "completed"
          end

        new_state = Cleanup.preserve_work_status(state, task_id, work_status)

        emit_telemetry(telemetry_path, "agent_completed", %{
          "task_id" => task_id,
          "run_id" => run_id,
          "phase" => "complete",
          "outcome" => "completed",
          "reason" => inspect(reason)
        })

        new_registry =
          if cleanup_outstanding?(new_state, task_id),
            do: data.agent_registry,
            else: drop_registry_entries(data.agent_registry, task_id)

        {:noreply, %{data | state: new_state, agent_registry: new_registry}}
      end
    )
  end

  defp handle_agent_crashed(
         {:agent_crashed, task_id, run_id, reason, info},
         %{state: state} = data
       ) do
    IO.puts("  Agent crashed #{task_id}: #{inspect(reason)}")

    # Write-ahead: record crash event before state mutation
    persist_info(
      data,
      "task_crashed",
      task_id,
      run_id,
      "developer",
      Map.merge(
        %{
          "reason" => inspect(reason),
          "pane" => Map.get(info, :pane_id, "")
        },
        cleanup_attributes(info)
      ),
      fn ->
        current_work_retries = get_in(state, ["assignments", task_id, "work_retries"]) || 0
        new_retries = current_work_retries + 1
        max_work_retries = Map.get(data, :max_work_retries, 2)

        if cleanup_outstanding?(state, task_id) or unresolved_cleanup_receipt?(info) do
          new_state =
            state
            |> Cleanup.preserve_work_status(task_id, "crashed")
            |> put_in(["assignments", task_id, "error"], "cleanup unresolved: #{inspect(reason)}")

          {:noreply, %{data | state: new_state}}
        else
          if new_retries <= max_work_retries do
            IO.puts(
              "  Re-enqueueing #{task_id} after crash (work retry #{new_retries}/#{max_work_retries})"
            )

            new_state =
              state
              |> put_in(["assignments", task_id, "status"], "queued")
              |> put_in(["assignments", task_id, "work_retries"], new_retries)
              |> put_in(["assignments", task_id, "error"], "agent_crashed: #{inspect(reason)}")
              |> Map.update!("queue", fn q -> q ++ [task_id] end)

            emit_telemetry(Map.get(data, :telemetry_path), "agent_crash", %{
              "task_id" => task_id,
              "run_id" => run_id,
              "phase" => "crash",
              "outcome" => "retry",
              "reason" => inspect(reason)
            })

            new_registry =
              data.agent_registry
              |> Map.drop([task_id])
              |> Map.delete("#{task_id}-review")

            {:noreply, %{data | state: new_state, agent_registry: new_registry}}
          else
            IO.puts("  Parking #{task_id} after #{new_retries} crashes (max #{max_work_retries})")

            new_state =
              state
              |> put_in(["assignments", task_id, "status"], "crashed")
              |> put_in(["assignments", task_id, "work_retries"], new_retries)
              |> put_in(
                ["assignments", task_id, "error"],
                "agent_crashed(#{max_work_retries}): #{inspect(reason)}"
              )

            emit_telemetry(Map.get(data, :telemetry_path), "agent_crash", %{
              "task_id" => task_id,
              "run_id" => run_id,
              "phase" => "crash",
              "outcome" => "parked",
              "reason" => inspect(reason)
            })

            new_registry =
              data.agent_registry
              |> Map.drop([task_id])
              |> Map.delete("#{task_id}-review")

            {:noreply, %{data | state: new_state, agent_registry: new_registry}}
          end
        end
      end
    )
  end

  # ── Private helpers ──

  defp coordinator_data(state, projection, tick_ref, adapter, opts, values) do
    values
    |> Map.new()
    |> Map.merge(%{
      projection: projection,
      state: state,
      tick_ref: tick_ref,
      herdr_adapter: adapter,
      agent_registry: %{},
      checkpoint_append_fn: Keyword.get(opts, :checkpoint_append_fn, &Checkpoint.append/6)
    })
  end

  defp cleanup_attributes(%{cleanup: %{status: status} = cleanup}) do
    %{
      "cleanup_status" => to_string(status),
      "cleanup_reason" => cleanup_reason(cleanup)
    }
  end

  defp cleanup_attributes(_info),
    do: %{"cleanup_status" => "unresolved", "cleanup_reason" => ":missing_cleanup_receipt"}

  defp cleanup_reason(%{reason: reason}), do: inspect(reason)
  defp cleanup_reason(_cleanup), do: nil

  defp recovery_state(accepted_rev, reason) do
    CoordState.new(accepted_revision: accepted_rev)
    |> Map.put("status", "recovery_required")
    |> Map.put("recovery_error", inspect(reason))
  end

  defp startup_reconciliation_required?(state) do
    state
    |> Map.get("assignments", %{})
    |> Map.values()
    |> Enum.any?(fn assignment ->
      Map.get(assignment, "status") in ~w(dispatched crashed cleanup_pending cleanup_blocked)
    end)
  end

  defp persist_call(data, event, task_id, run_id, role, attributes, continuation) do
    case checked_append(data, event, task_id, run_id, role, attributes) do
      :ok ->
        continuation.()

      {:error, reason} ->
        {:reply, {:error, {:recovery_required, reason}}, enter_recovery(data, reason)}
    end
  end

  defp persist_info(data, event, task_id, run_id, role, attributes, continuation) do
    case checked_append(data, event, task_id, run_id, role, attributes) do
      :ok -> continuation.()
      {:error, reason} -> {:noreply, enter_recovery(data, reason)}
    end
  end

  defp checked_append(data, event, task_id, run_id, role, attributes) do
    with :ok <- ensure_runtime_owner(data),
         {:ok, _record} <-
           checkpoint_append_fn(data).(
             data.event_log_path,
             event,
             task_id,
             run_id,
             role,
             attributes
           ) do
      :ok
    end
  end

  defp project_resource_compatibility(state, attributes) do
    task_id = attributes["task_id"]

    state
    |> put_in(["assignments", task_id, "pane_id"], attributes["pane_id"])
    |> put_in(["assignments", task_id, "agent_name"], attributes["agent_name"])
    |> put_in(
      ["assignments", task_id, "cleanup_identity"],
      cleanup_identity_attributes(attributes)
    )
    |> put_in(
      ["assignments", task_id, "presentation_identity"],
      attributes["presentation_identity"]
    )
  end

  defp pane_created_attributes(attributes) do
    event_attributes = %{
      "execution_id" => attributes["execution_id"],
      "role" => attributes["role"],
      "resource_id" => attributes["resource_id"],
      "pane_id" => attributes["pane_id"],
      "agent_name" => attributes["agent_name"],
      "verification_status" =>
        if(is_map(attributes["presentation_identity"]), do: "verified", else: "unverified"),
      "cleanup_identity" => cleanup_identity_attributes(attributes),
      "presentation_identity" => attributes["presentation_identity"]
    }

    if is_nil(attributes["presentation_identity"]),
      do: Map.delete(event_attributes, "presentation_identity"),
      else: event_attributes
  end

  defp cleanup_identity_attributes(attributes) do
    identity = %{
      "name" => attributes["agent_name"],
      "pane_id" => attributes["pane_id"],
      "terminal_id" => attributes["terminal_id"],
      "session" => attributes["session"]
    }

    if is_nil(attributes["session"]), do: Map.delete(identity, "session"), else: identity
  end

  defp ensure_resource_id(%{"role" => role, "execution_id" => execution_id} = attributes)
       when is_binary(role) and is_binary(execution_id),
       do: Map.put_new(attributes, "resource_id", role <> ":" <> execution_id)

  defp ensure_resource_id(attributes), do: attributes

  defp durable_cleanup_attributes(attributes) do
    Enum.reduce(~w(session observed_session presentation_identity), attributes, fn field,
                                                                                   durable ->
      if is_nil(Map.get(durable, field)), do: Map.delete(durable, field), else: durable
    end)
  end

  defp startup_append_or_halt(path, event, task_id, run_id, role, attributes) do
    case Checkpoint.append(path, event, task_id, run_id, role, attributes) do
      {:ok, _record} -> :ok
      {:error, reason} -> throw({:persistence_failed, reason})
    end
  end

  defp checkpoint_append_fn(data),
    do: Map.get(data, :checkpoint_append_fn, &Checkpoint.append/6)

  defp ensure_runtime_owner(data) do
    if Map.get(data, :require_runtime_owner, false) do
      if PramanaFoundry.RuntimeOwner.owned?(), do: :ok, else: {:error, :runtime_fence_lost}
    else
      :ok
    end
  catch
    :exit, reason -> {:error, {:runtime_fence_unavailable, reason}}
  end

  defp enter_recovery(data, reason) do
    if is_reference(data.tick_ref), do: Process.cancel_timer(data.tick_ref)

    state =
      data.state
      |> Map.put("status", "recovery_required")
      |> Map.put("recovery_error", inspect(reason))

    if Map.get(data, :require_runtime_owner, false) do
      try do
        RuntimeLease.inhibit_clean_release(reason)
      catch
        :exit, _reason -> :ok
      end
    end

    %{data | state: state, recovery_error: reason, tick_ref: nil}
  end

  defp reviewer_launch_blocked?(state, task_id) do
    case get_in(state, ["assignments", task_id]) do
      %{"status" => "blocked", "blocked_role" => "reviewer"} -> true
      _ -> false
    end
  end

  defp drop_agent_registry(data, task_id) do
    new_registry = drop_registry_entries(data.agent_registry, task_id)

    %{data | agent_registry: new_registry}
  end

  defp maybe_drop_after_cleanup(data, task_id, info) do
    if cleanup_outstanding?(data.state, task_id) or unresolved_cleanup_receipt?(info),
      do: data,
      else: drop_agent_registry(data, task_id)
  end

  defp preserve_unregistered_launch_resource(data, %{
         resource_registered: false,
         resource: resource
       })
       when is_map(resource) do
    case Cleanup.register_resource(data.state, resource) do
      {:ok, state} -> %{data | state: state}
      {:error, _reason} -> data
    end
  end

  defp preserve_unregistered_launch_resource(data, _info), do: data

  defp drop_registry_entries(registry, task_id) do
    registry
    |> Map.drop([task_id])
    |> Map.delete("#{task_id}-review")
  end

  defp cleanup_outstanding?(state, task_id),
    do:
      state
      |> get_in(["assignments", task_id])
      |> Cleanup.assignment_outstanding?()

  defp current_work_status(state, task_id) do
    assignment = get_in(state, ["assignments", task_id]) || %{}

    if Cleanup.assignment_outstanding?(assignment),
      do: Map.get(assignment, "work_status", Map.get(assignment, "status")),
      else: Map.get(assignment, "status")
  end

  defp unresolved_cleanup_receipt?(%{cleanup: %{status: status}}),
    do: status not in [:closed, :not_required]

  defp unresolved_cleanup_receipt?(_info), do: true

  defp safe_clean_shutdown_state?(state) do
    Map.get(state, "status", "running") != "recovery_required" and
      Cleanup.all_owned_resources_terminal?(state)
  end

  defp clean_shutdown?(:shutdown), do: true
  defp clean_shutdown?({:shutdown, _reason}), do: true
  defp clean_shutdown?(_reason), do: false

  defp formatted_now do
    DateTime.utc_now() |> DateTime.to_iso8601()
  end

  defp process_has_herdr_env? do
    System.get_env("HERDR_ENV") == "1"
  end

  # ── Review retry: re-launch reviewer with previous_error context ──

  defp maybe_launch_reviewer_retry(data, task_id, new_state) do
    new_run_id = :crypto.strong_rand_bytes(8) |> :binary.encode_hex()
    checkout = get_in(new_state, ["assignments", task_id, "ticket", "checkout"])
    handoff = get_in(new_state, ["assignments", task_id, "handoff"])
    previous_error = get_in(new_state, ["assignments", task_id, "error"]) || "invalid review"

    supervisor = Process.whereis(PramanaFoundry.AssignmentSupervisor)
    profile_result = resolve_reviewer_profile(data, new_state, task_id)

    if is_pid(supervisor) and is_binary(checkout) and is_map(handoff) and
         Tick.herdr_available?() and match?({:ok, _}, profile_result) do
      {:ok, profile} = profile_result
      handoff_data = Map.put(handoff, "previous_error", previous_error)

      child_spec = %{
        id: "#{task_id}-review",
        start:
          {PramanaFoundry.AgentServer, :start_link,
           [
             [
               task_id: task_id,
               run_id: new_run_id,
               role: :reviewer,
               checkout: checkout,
               adapter: data.herdr_adapter,
               coordinator_pid: self(),
               profile: profile.name,
               launch_profiles: data.launch_profiles,
               launch_state: new_state,
               launch_now: data.launch_now_fn.(),
               handoff_data: handoff_data,
               herdr_timeout_ms: data.herdr_timeout,
               telemetry_path: data.telemetry_path,
               herdr_opts: data.herdr_opts
             ]
           ]},
        restart: :temporary
      }

      case DynamicSupervisor.start_child(supervisor, child_spec) do
        {:ok, pid} when is_pid(pid) ->
          IO.puts("  Launched reviewer (retry #{new_run_id}) for #{task_id} (#{inspect(pid)})")

          state_with_run_id =
            put_in(new_state, ["assignments", task_id, "reviewer_run_id"], new_run_id)

          {%{data | agent_registry: Map.put(data.agent_registry, "#{task_id}-review", pid)},
           state_with_run_id}

        {:error, reason} ->
          IO.puts("  Failed to launch reviewer retry for #{task_id}: #{inspect(reason)}")
          {data, new_state}
      end
    else
      case profile_result do
        {:error, _reason} ->
          {blocked_state, registry} =
            block_reviewer_if_ineligible(data, new_state, task_id, profile_result)

          {%{data | agent_registry: registry}, blocked_state}

        {:ok, _profile} ->
          reason =
            cond do
              not is_pid(supervisor) -> "no_assignment_supervisor"
              not is_binary(checkout) -> "no_checkout"
              not is_map(handoff) -> "no_handoff_data"
              true -> "herdr_unavailable(no_HERDR_ENV)"
            end

          IO.puts("  Cannot launch reviewer retry for #{task_id}: #{reason}")
          {data, new_state}
      end
    end
  end

  defp resolve_reviewer_profile(data, state, task_id) do
    with :ok <- Adapter.require_subscription_route(data.herdr_adapter, data.herdr_opts),
         {:ok, profile_name} <-
           LaunchEligibility.select_profile(
             get_in(state, ["assignments", task_id, "ticket", "reviewer_profile"]),
             data.launch_role_profiles,
             :reviewer
           ) do
      LaunchEligibility.resolve(data.launch_profiles, profile_name, :reviewer, state,
        now: data.launch_now_fn.()
      )
    end
  end

  defp block_reviewer_if_ineligible(data, state, task_id, {:error, reason}) do
    blocked_reason = LaunchEligibility.reason(reason)
    IO.puts("  Cannot launch reviewer for #{task_id}: #{blocked_reason}")
    {Tick.block_assignment(state, task_id, :reviewer, blocked_reason), data.agent_registry}
  end

  defp block_reviewer_if_ineligible(data, state, _task_id, {:ok, _profile}),
    do: {state, data.agent_registry}

  # ── Stale dispatch recovery ──

  defp reenqueue_stale_dispatched(state, _events, event_log_path) do
    assignments = Map.get(state, "assignments", %{})
    queue = Map.get(state, "queue", [])

    {stale, rest} =
      Enum.split_with(assignments, fn {_tid, a} -> Map.get(a, "status") == "dispatched" end)

    # Also recover crashed tasks with remaining work_retry budget
    {crashed_recoverable, _rest2} =
      Enum.split_with(rest, fn {_tid, a} ->
        status = Map.get(a, "status")
        work_retries = Map.get(a, "work_retries", 0)
        status == "crashed" and work_retries < 2
      end)

    all_recovered = stale ++ crashed_recoverable

    if all_recovered != [] do
      stale_ids = Enum.map(all_recovered, fn {tid, _a} -> tid end)

      IO.puts(
        "  re-enqueueing #{length(all_recovered)} recoverable ticket(s): #{inspect(stale_ids)}"
      )

      updated =
        Enum.reduce(all_recovered, assignments, fn {tid, a}, acc ->
          run_id = Map.get(a, "run_id", "pending")

          event_name =
            if Map.get(a, "status") == "crashed", do: "task_crashed", else: "ticket_re_enqueued"

          startup_append_or_halt(event_log_path, event_name, tid, run_id, "system", %{
            "reason" =>
              if(Map.get(a, "status") == "crashed",
                do: "crash_recovered",
                else: "stale_dispatch_recovered"
              ),
            "previous_status" => Map.get(a, "status")
          })

          a
          |> Map.put("status", "queued")
          |> Map.put("launch_retries", 0)
          |> Map.put(
            "error",
            if(Map.get(a, "status") == "crashed",
              do: "crash_recovered",
              else: "stale_dispatch_recovered"
            )
          )
          |> then(&Map.put(acc, tid, &1))
        end)

      state
      |> Map.put("assignments", updated)
      |> Map.put("queue", queue ++ stale_ids)
    else
      state
    end
  end

  # ── Telemetry ──

  defp emit_telemetry(log_path, record_type, attrs) when is_binary(log_path) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    record = %{
      "record_id" => :crypto.strong_rand_bytes(8) |> :binary.encode_hex(),
      "record_type" => record_type,
      "schema_version" => 1,
      "task_id" => Map.get(attrs, "task_id", "?"),
      "run_id" => Map.get(attrs, "run_id", "?"),
      "phase" => Map.get(attrs, "phase", record_type),
      "outcome" => Map.get(attrs, "outcome", "unknown"),
      "reason" => Map.get(attrs, "reason"),
      "agent" => Map.get(attrs, "agent"),
      "pane" => Map.get(attrs, "pane"),
      "duration_ms" => Map.get(attrs, "duration_ms"),
      "retry" => Map.get(attrs, "retry"),
      "retries" => Map.get(attrs, "retries"),
      "max" => Map.get(attrs, "max"),
      "stage" => Map.get(attrs, "stage"),
      "at" => now
    }

    PramanaFoundry.EventLog.append(log_path, record)
  end

  defp emit_telemetry(nil, _record_type, _attrs), do: :ok
  defp emit_telemetry(_path, _record_type, _attrs), do: :ok
end
