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

  @doc "Look up the AgentServer PID for a running agent by task_id."
  def agent_pid(task_id) do
    GenServer.call(__MODULE__, {:agent_pid, task_id})
  end

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
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
                {:persistence_failed,
                 {:legacy_startup_reconciliation_suspended,
                  "FR-03 containment requires FR-07/FR-08 recovery transactions"}}
              )
            end

            recovered_state = reenqueue_stale_dispatched(recovered_state, events, event_log_path)

            recovered_state =
              recover_inflight_agents(
                recovered_state,
                events,
                event_log_path,
                adapter,
                herdr_timeout
              )

            IO.puts(
              "  event log: #{length(events)} events, #{map_size(Map.get(recovered_state, "assignments", %{}))} assignments recovered"
            )

            if process_has_herdr_env?() do
              cleanup_orphan_panes(adapter, recovered_state, herdr_timeout)
            end

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
        auto_approve = get_in(state, ["assignments", task_id, "ticket", "auto_approve"]) || false
        attrs = %{"handoff" => handoff}
        attrs = if auto_approve, do: Map.put(attrs, "auto_approved", true), else: attrs

        persist_call(data, "handoff_received", task_id, run_id, "developer", attrs, fn ->
          # Launch reviewer if not auto_approve
          {final_state, final_registry} =
            if not auto_approve do
              new_run_id = :crypto.strong_rand_bytes(8) |> :binary.encode_hex()
              supervisor = Process.whereis(PramanaFoundry.AssignmentSupervisor)
              checkout = get_in(state, ["assignments", task_id, "ticket", "checkout"])
              profile_result = resolve_reviewer_profile(data, new_state, task_id)

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
            else
              {new_state, data.agent_registry}
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
       "FR-03 containment; FR-05/FR-07/FR-08 own truthful Git result settlement"}}, data}
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

  # ── handle_info ──

  @impl true
  def handle_info(:tick, %{recovery_error: reason} = data) when not is_nil(reason),
    do: {:noreply, data}

  def handle_info({event, task_id, _run_id, _reason, _info}, %{recovery_error: reason} = data)
      when event in [:agent_completed, :agent_crashed] and not is_nil(reason),
      do: {:noreply, drop_agent_registry(data, task_id)}

  def handle_info({:agent_launched, task_id, _result, _info}, %{recovery_error: reason} = data)
      when not is_nil(reason),
      do: {:noreply, drop_agent_registry(data, task_id)}

  def handle_info(
        :tick,
        %{
          state: state,
          poll_ms: poll_ms,
          agent_registry: agent_registry,
          event_log_path: event_log_path,
          max_launch_retries: max_launch_retries,
          herdr_adapter: adapter,
          herdr_timeout: herdr_timeout
        } = data
      ) do
    case ensure_runtime_owner(data) do
      {:error, reason} ->
        {:noreply, enter_recovery(data, reason)}

      :ok ->
        tick_ref = Process.send_after(self(), :tick, poll_ms)
        data = %{data | tick_ref: tick_ref}

        # Periodic orphan pane cleanup: every ~16 ticks (~4 minutes at 15s poll)
        # Scans Herdr panes and closes any not tracked by current assignments.
        tick_count = data[:tick_count] || 0
        data = put_in(data, [:tick_count], tick_count + 1)

        if rem(tick_count, 16) == 0 and Map.get(state, "paused", false) == false do
          cleanup_orphan_panes(adapter, state, herdr_timeout)
        end

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

  defp handle_agent_launched({:agent_launched, task_id, :ok, info}, %{state: state} = data) do
    IO.puts("  Agent launched for #{task_id}: pane=#{info[:pane_id]} name=#{info[:agent_name]}")

    new_state =
      state
      |> put_in(["assignments", task_id, "dispatched_at"], formatted_now())
      |> put_in(["assignments", task_id, "pane_id"], info[:pane_id])
      |> put_in(["assignments", task_id, "agent_name"], info[:agent_name])

    run_id = get_in(state, ["assignments", task_id, "run_id"]) || "pending"

    persist_info(
      data,
      "pane_created",
      task_id,
      run_id,
      "developer",
      %{"pane_id" => info[:pane_id], "agent_name" => info[:agent_name]},
      fn ->
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

        {:noreply, %{data | state: new_state}}
      end
    )
  end

  defp handle_agent_launched(
         {:agent_launched, task_id, {:error, stage, reason}, _info},
         %{state: state, max_launch_retries: max_retries} = data
       ) do
    IO.puts("  Agent launch failed for #{task_id} at #{stage}: #{inspect(reason)}")

    current_retries = get_in(state, ["assignments", task_id, "launch_retries"]) || 0
    new_retries = current_retries + 1
    run_id = get_in(state, ["assignments", task_id, "run_id"]) || "pending"

    cond do
      new_retries <= max_retries ->
        IO.puts("  Re-enqueueing #{task_id} for retry #{new_retries}/#{max_retries}")

        # Write-ahead: record retry event before state mutation
        persist_info(
          data,
          "launch_retried",
          task_id,
          run_id,
          "developer",
          %{
            "retry_count" => new_retries,
            "max_retries" => max_retries,
            "stage" => to_string(stage),
            "error_reason" => "launch_failed: #{stage}: #{inspect(reason)}"
          },
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
          %{
            "retry_count" => new_retries,
            "max_retries" => max_retries,
            "stage" => to_string(stage),
            "error_reason" => "max_launch_retries(#{max_retries}): #{stage}: #{inspect(reason)}"
          },
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
         {:agent_completed, task_id, run_id, reason, _info},
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
      %{
        "reason" => inspect(reason)
      },
      fn ->
        new_state =
          case reason do
            {:handoff, :ok} ->
              # If status is already "review_approved" (from coordinator's receive_review),
              # don't overwrite — the review already went through.
              current = get_in(state, ["assignments", task_id, "status"])

              if current in ~w(review_approved review) do
                state
              else
                put_in(state, ["assignments", task_id, "status"], "review")
              end

            {:handoff, {:error, _}} ->
              # Handoff was rejected. If the task was already re-enqueued by the
              # handoff handler (auto-retry), don't overwrite that status.
              current = get_in(state, ["assignments", task_id, "status"])

              if current == "queued" do
                state
              else
                put_in(state, ["assignments", task_id, "status"], "handoff_rejected")
              end

            {:error, _r} ->
              put_in(state, ["assignments", task_id, "status"], "failed")

            _ ->
              put_in(state, ["assignments", task_id, "status"], "completed")
          end

        emit_telemetry(telemetry_path, "agent_completed", %{
          "task_id" => task_id,
          "run_id" => run_id,
          "phase" => "complete",
          "outcome" => "completed",
          "reason" => inspect(reason)
        })

        new_registry =
          data.agent_registry
          |> Map.drop([task_id])
          |> Map.delete("#{task_id}-review")

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
      %{
        "reason" => inspect(reason),
        "pane" => Map.get(info, :pane_id, "")
      },
      fn ->
        current_work_retries = get_in(state, ["assignments", task_id, "work_retries"]) || 0
        new_retries = current_work_retries + 1
        max_work_retries = Map.get(data, :max_work_retries, 2)

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

  defp recovery_state(accepted_rev, reason) do
    CoordState.new(accepted_revision: accepted_rev)
    |> Map.put("status", "recovery_required")
    |> Map.put("recovery_error", inspect(reason))
  end

  defp startup_reconciliation_required?(state) do
    state
    |> Map.get("assignments", %{})
    |> Map.values()
    |> Enum.any?(fn assignment -> Map.get(assignment, "status") in ~w(dispatched crashed) end)
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

    %{data | state: state, recovery_error: reason, tick_ref: nil}
  end

  defp reviewer_launch_blocked?(state, task_id) do
    case get_in(state, ["assignments", task_id]) do
      %{"status" => "blocked", "blocked_role" => "reviewer"} -> true
      _ -> false
    end
  end

  defp drop_agent_registry(data, task_id) do
    new_registry =
      data.agent_registry
      |> Map.drop([task_id])
      |> Map.delete("#{task_id}-review")

    %{data | agent_registry: new_registry}
  end

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

  # ── Orphan pane cleanup ──

  defp cleanup_orphan_panes(adapter, state, timeout_ms) do
    tracked_panes =
      Map.get(state, "assignments", %{})
      |> Map.values()
      |> Enum.map(&Map.get(&1, "pane_id", ""))
      |> Enum.reject(&(&1 == ""))
      |> MapSet.new()

    case PramanaFoundry.Herdr.Runner.System.run(
           [adapter.command, "pane", "list"],
           timeout_ms: timeout_ms
         ) do
      {:ok, %{stdout: stdout}} ->
        case :json.decode(stdout) do
          %{"result" => %{"panes" => panes}} when is_list(panes) ->
            orphans =
              Enum.filter(panes, fn p ->
                pane_id = Map.get(p, "pane_id", "")
                cwd = Map.get(p, "foreground_cwd", "")
                tracked = MapSet.member?(tracked_panes, pane_id)

                not tracked and
                  pane_id not in ~w(w3:p1 w3:p0) and
                  String.starts_with?(cwd, "/private/tmp")
              end)

            if orphans != [] do
              ids = Enum.map(orphans, & &1["pane_id"])
              IO.puts("  cleanup: closing #{length(orphans)} orphaned pane(s): #{inspect(ids)}")

              Enum.each(orphans, fn p ->
                PramanaFoundry.Herdr.Runner.System.run(
                  [adapter.command, "pane", "close", p["pane_id"]],
                  timeout_ms: timeout_ms
                )
              end)
            end

          _ ->
            IO.puts("  cleanup: could not parse pane list")
        end

      {:error, reason} ->
        IO.puts("  cleanup: pane list failed: #{inspect(reason)}")
    end
  end

  # ── Inflight agent recovery ──

  defp recover_inflight_agents(state, events, event_log_path, adapter, timeout_ms) do
    pane_created = Enum.filter(events, fn e -> Map.get(e, "event") == "pane_created" end)

    if pane_created == [] do
      state
    else
      IO.puts("  inflight: checking #{length(pane_created)} pane(s) for recoverable handoffs")

      Enum.reduce(pane_created, state, fn event, acc_state ->
        task_id = Map.get(event, "task_id", "")
        pane_id = get_in(event, ["attributes", "pane_id"]) || ""
        run_id = Map.get(event, "run_id", "pending")
        assignment = get_in(acc_state, ["assignments", task_id])
        status = Map.get(assignment, "status", "")

        if status not in ~w(dispatched) do
          acc_state
        else
          case PramanaFoundry.Herdr.Runner.System.run(
                 [adapter.command, "pane", "get", pane_id],
                 timeout_ms: timeout_ms
               ) do
            {:ok, %{stdout: stdout}} ->
              case :json.decode(stdout) do
                %{"result" => %{"pane" => _pane}} ->
                  read_inflight_pane(
                    acc_state,
                    event_log_path,
                    task_id,
                    run_id,
                    pane_id,
                    adapter,
                    timeout_ms
                  )

                _ ->
                  IO.puts("    inflight: pane #{pane_id} (#{task_id}) gone")
                  acc_state
              end

            {:error, _} ->
              IO.puts("    inflight: pane #{pane_id} (#{task_id}) unreachable")
              acc_state
          end
        end
      end)
    end
  end

  defp read_inflight_pane(state, event_log_path, task_id, run_id, pane_id, adapter, timeout_ms) do
    IO.puts("    inflight: reading pane #{pane_id} (#{task_id})")

    case PramanaFoundry.Herdr.Runner.System.run(
           [adapter.command, "pane", "read", pane_id],
           timeout_ms: timeout_ms
         ) do
      {:ok, %{stdout: output}} when is_binary(output) and output != "" ->
        handoff_data = find_handoff_in_output(output)

        case handoff_data do
          nil ->
            IO.puts("    inflight: no handoff found in pane #{pane_id} (#{task_id})")
            state

          handoff ->
            IO.puts("    inflight: recovered handoff for #{task_id}")

            case PramanaFoundry.Coordinator.State.receive_handoff(state, task_id, handoff, []) do
              {:ok, _assignment, new_state} ->
                IO.puts("    inflight: handoff accepted for #{task_id}")

                startup_append_or_halt(
                  event_log_path,
                  "handoff_recovered",
                  task_id,
                  run_id,
                  "developer",
                  %{"pane_id" => pane_id, "handoff" => handoff}
                )

                new_state

              {:error, reason, _new_state} ->
                IO.puts("    inflight: handoff rejected for #{task_id}: #{inspect(reason)}")
                state
            end
        end

      _ ->
        IO.puts("    inflight: could not read pane #{pane_id} (#{task_id})")
        state
    end
  end

  defp find_handoff_in_output(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(:none, fn line ->
      trimmed = String.trim(line)

      if String.starts_with?(trimmed, "{") and String.ends_with?(trimmed, "}") do
        decoded = safe_json_decode(trimmed)

        if is_map(decoded) and
             (Map.has_key?(decoded, "outcome") or Map.has_key?(decoded, "commit")) do
          decoded
        else
          :none
        end
      end
    end)
    |> case do
      :none -> nil
      found -> found
    end
  end

  defp safe_json_decode(line) do
    :json.decode(line)
  rescue
    _ -> nil
  end

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
