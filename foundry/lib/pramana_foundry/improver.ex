defmodule PramanaFoundry.Improver do
  @moduledoc """
  Periodic self-healing loop: reads telemetry AND the durable event log, classifies
  issues, derives duration observations, forecasts anomalies, logs findings, and
  creates PM proposals for actionable hardening work.

  Runs on a configurable timer (default 5 min). Each cycle:
  1. Reads telemetry for crash/launch-failure/tick-crash signals
  2. Reads the event log for phase transitions (from coordinator)
  3. Derives observations via Observation.from_events/1
  4. Compares durations against Forecast estimates
  5. Detects stuck tickets (queued too long, no admission)
  6. Logs findings at WARN/CRITICAL/HIGH/MEDIUM levels
  7. For confirmed repeat issues, creates PM proposals
  """
  use GenServer

  alias PramanaFoundry.{Coordinator, LogStore}

  @default_interval_ms 300_000
  @max_records_to_scan 500
  @crash_threshold 3
  @launch_failure_rate 0.3
  @tick_crash_any true
  # Tickets stuck in queue longer than this (ms) → flag
  @stuck_queue_ms 120_000

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  def analyze(pid \\ __MODULE__), do: GenServer.cast(pid, :analyze)

  def last_findings(pid \\ __MODULE__), do: GenServer.call(pid, :last_findings)

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)
    enable_loop = Keyword.get(opts, :enable_loop, true)

    IO.puts("Improver init: interval=#{interval_ms}ms")

    timer_ref = if enable_loop, do: Process.send_after(self(), :analyze, interval_ms), else: nil

    findings_path = default_findings_path()

    {:ok,
     %{
       interval_ms: interval_ms,
       findings_path: findings_path,
       timer_ref: timer_ref,
       last_findings: [],
       proposed_fingerprints: MapSet.new(),
       cycle_count: 0,
       last_generation: 0,
       metrics_history: []
     }}
  end

  @impl true
  def handle_cast(:analyze, state) do
    state = do_analyze(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:analyze, state) do
    state = do_analyze(state)
    timer_ref = Process.send_after(self(), :analyze, state.interval_ms)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_call(:last_findings, _from, state) do
    {:reply, state.last_findings, state}
  end

  # ── Analysis ──

  defp do_analyze(state) do
    cycle = state.cycle_count + 1
    IO.puts("\n=== Improver cycle #{cycle} ===")

    # Read ALL records from ConsolidatedLog — single source for all classifiers
    all_records = PramanaFoundry.ConsolidatedLog.tail(@max_records_to_scan)
    IO.puts("  consolidated: #{length(all_records)} records")

    # Split by source for specialized processing
    telemetry = Enum.filter(all_records, &(&1["source"] == "telemetry"))
    events = Enum.filter(all_records, &(&1["source"] == "events"))
    IO.puts("  telemetry: #{length(telemetry)}  events: #{length(events)}")

    # Derive observations from phase events  
    {observations, _obs_err} =
      case PramanaFoundry.Telemetry.Observation.from_events(events) do
        {:ok, obs} -> {obs, nil}
        error -> {[], error}
      end

    IO.puts("  observations: #{length(observations)}")

    # Duration forecast
    forecast_targets = build_forecast_targets(events)

    forecasts =
      Enum.map(forecast_targets, fn t ->
        {t, PramanaFoundry.Telemetry.Forecast.estimate(observations, t)}
      end)

    IO.puts("  forecasts: #{length(forecasts)}")

    all_findings =
      classify_crashes(telemetry) ++
        classify_agent_crashes(telemetry) ++
        classify_agent_timeouts(telemetry) ++
        classify_launch_failures(telemetry) ++
        classify_slow_ticks(telemetry) ++
        classify_tick_crashes(telemetry) ++
        classify_stuck_tickets(events) ++
        classify_observation_anomalies(observations) ++
        classify_no_events(events) ++
        classify_coordinator_restart(state) ++
        classify_process_memory() ++
        classify_task_sup_capacity() ++
        classify_duplicate_run_ids() ++
        classify_assignment_consistency()

    {new_findings, updated_fingerprints} =
      filter_new(all_findings, state.proposed_fingerprints)

    log_findings(new_findings)

    # Write all findings to findings.jsonl for external consumption
    fp = state.findings_path
    Enum.each(all_findings, fn finding -> log_finding(fp, finding, cycle) end)

    # Record metrics for trend tracking
    state = log_metrics(state)

    # Track current generation for next cycle's comparison
    current_gen = get_coordinator_generation()

    updated_state = %{
      state
      | last_findings: all_findings,
        cycle_count: cycle,
        last_generation: current_gen
    }

    if new_findings == [] do
      IO.puts("  no new actionable findings")
      updated_state
    else
      IO.puts("  proposing #{length(new_findings)} hardening ticket(s)")
      gen = get_coordinator_generation()

      LogStore.append(fp, %{
        "event" => "proposal",
        "source" => "improver",
        "cycle" => cycle,
        "finding_count" => length(new_findings),
        "generation" => gen,
        "fingerprints" => Enum.map(new_findings, & &1.fingerprint)
      })

      propose_findings(new_findings)
      %{updated_state | proposed_fingerprints: updated_fingerprints}
    end
  end

  # ── Telemetry reader ──

  # ── Classifiers ──

  defp classify_crashes(records) do
    crashes = Enum.filter(records, &(&1["phase"] == "task_crash"))
    count = length(crashes)

    if count >= @crash_threshold do
      task_ids =
        crashes
        |> Enum.map(& &1["task_id"])
        |> Enum.uniq()
        |> Enum.reject(&is_nil/1)

      reasons =
        crashes
        |> Enum.map(& &1["reason"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      [
        %{
          severity: :critical,
          category: :task_crashes,
          count: count,
          summary: "#{count} task crash(es) across #{length(task_ids)} task(s)",
          details: "Crashed tasks: #{inspect(task_ids)}\nReasons: #{inspect(reasons)}",
          fingerprint: "crash/v1/#{Enum.sort(task_ids)}"
        }
      ]
    else
      []
    end
  end

  defp classify_agent_crashes(records) do
    crashes = Enum.filter(records, &(&1["phase"] == "crash"))
    count = length(crashes)

    if count >= @crash_threshold do
      task_ids =
        crashes
        |> Enum.map(& &1["task_id"])
        |> Enum.uniq()
        |> Enum.reject(&is_nil/1)

      reasons =
        crashes
        |> Enum.map(& &1["reason"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      [
        %{
          severity: :critical,
          category: :agent_crashes,
          count: count,
          summary: "#{count} agent crash(es) across #{length(task_ids)} agent(s)",
          details: "Crashed agents: #{inspect(task_ids)}\nReasons: #{inspect(reasons)}",
          fingerprint: "agent_crash/v1/#{Enum.sort(task_ids)}"
        }
      ]
    else
      []
    end
  end

  defp classify_agent_timeouts(records) do
    timeouts = Enum.filter(records, &(&1["phase"] == "timeout"))
    count = length(timeouts)

    if count > 0 do
      task_ids =
        timeouts
        |> Enum.map(& &1["task_id"])
        |> Enum.uniq()
        |> Enum.reject(&is_nil/1)

      durations =
        timeouts
        |> Enum.map(& &1["work_timeout_ms"])
        |> Enum.reject(&is_nil/1)

      max_duration = if durations != [], do: Enum.max(durations), else: 0

      [
        %{
          severity: :high,
          category: :agent_timeouts,
          count: count,
          summary: "#{count} agent timeout(s) across #{length(task_ids)} agent(s)",
          details: "Timed out agents: #{inspect(task_ids)}\nMax timeout: #{max_duration}ms",
          fingerprint: "agent_timeout/v1/#{Enum.sort(task_ids)}"
        }
      ]
    else
      []
    end
  end

  defp classify_launch_failures(records) do
    launches = Enum.filter(records, &(&1["phase"] == "agent_launch"))
    total = length(launches)
    failed = Enum.count(launches, &(&1["outcome"] != "dispatched"))

    if total > 0 and failed / total >= @launch_failure_rate do
      stages =
        launches
        |> Enum.filter(&(&1["outcome"] != "dispatched"))
        |> Enum.map(& &1["stage"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      reasons =
        launches
        |> Enum.filter(&(&1["outcome"] != "dispatched"))
        |> Enum.map(& &1["reason"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      [
        %{
          severity: :high,
          category: :launch_failures,
          count: failed,
          total: total,
          rate: Float.round(failed / total * 100, 1),
          summary:
            "#{failed}/#{total} agent launches failed (#{Float.round(failed / total * 100, 1)}%)",
          details: "Failing stages: #{inspect(stages)}\nReasons: #{inspect(reasons)}",
          fingerprint: "launch/v1/#{Enum.sort(stages)}"
        }
      ]
    else
      []
    end
  end

  defp classify_slow_ticks(records) do
    ticks = Enum.filter(records, &(&1["phase"] == "tick_cycle" and &1["outcome"] == "ok"))
    durations = Enum.map(ticks, & &1["duration_ms"]) |> Enum.reject(&is_nil/1)

    if length(durations) >= 3 do
      avg = div(Enum.sum(durations), length(durations))

      # 15s poll interval → 7500ms threshold (50%)
      if avg >= 7500 do
        max_dur = Enum.max(durations)

        [
          %{
            severity: :medium,
            category: :slow_ticks,
            avg_ms: avg,
            max_ms: max_dur,
            samples: length(durations),
            summary: "Tick avg #{avg}ms (max #{max_dur}ms) exceeds 50% of poll interval",
            details: "#{length(durations)} tick samples, avg=#{avg}ms max=#{max_dur}ms",
            fingerprint: "slow_ticks/v1"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  defp classify_tick_crashes(records) do
    crashes = Enum.filter(records, &(&1["phase"] == "tick_cycle" and &1["outcome"] == "crashed"))

    if length(crashes) > 0 and @tick_crash_any do
      reasons =
        crashes
        |> Enum.map(& &1["reason"])
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      [
        %{
          severity: :critical,
          category: :tick_crashes,
          count: length(crashes),
          summary: "#{length(crashes)} tick crash(es) detected",
          details: "Reasons: #{inspect(reasons)}",
          fingerprint: "tick_crash/v1"
        }
      ]
    else
      []
    end
  end

  # ── Dedup ──

  defp filter_new(findings, fingerprints) do
    {new, _rest} = Enum.split_with(findings, &(not MapSet.member?(fingerprints, &1.fingerprint)))
    updated = Enum.reduce(new, fingerprints, fn f, acc -> MapSet.put(acc, f.fingerprint) end)
    {new, updated}
  end

  # ── Logging ──

  defp log_findings([]), do: :ok

  defp log_findings(findings) do
    Enum.each(findings, fn finding ->
      tag =
        case finding.severity do
          :critical -> "CRITICAL"
          :high -> "HIGH"
          :medium -> "MEDIUM"
          :low -> "LOW"
        end

      IO.puts("  [#{tag}] #{finding.category}: #{finding.summary}")
      IO.puts("         #{finding.details}")
    end)
  end

  # ── Proposal creation ──

  defp propose_findings(findings) do
    accepted_rev = get_accepted_revision()

    proposals =
      findings
      |> Enum.take(3)
      |> Enum.with_index()
      |> Enum.map(fn {finding, idx} ->
        task_id = "IMPRV-#{pad_idx(idx)}"

        %{
          "operation" => "create",
          "ticket" => %{
            "task_id" => task_id,
            "base_revision" => accepted_rev,
            "priority" => "P1",
            "work_class" => "p0_high_risk",
            "risk" => "workflow_recovery",
            "role" => "developer",
            "profile" => "omp_gemini_developer",
            "model" => "omp-google-gemini-3.8-flash-developer",
            "reasoning" => "medium",
            "workload" => "lightweight",
            "work_timeout_seconds" => 14_400,
            "check_timeout_seconds" => 7_200,
            "scope" => ["workflow/lib/pramana_foundry/**"],
            "exclusions" => ["No changes outside workflow/"],
            "outcome" => "Self-healing: #{finding.summary}",
            "acceptance_criteria" => [
              "Investigate and resolve #{finding.category}: #{finding.summary}",
              "Add regression detection to Improver classifiers",
              "Update telemetry with resolution evidence"
            ],
            "dependencies" => [],
            "evidence" => [finding.details],
            "environment" => %{
              "MIX_ENV" => "test",
              "MIX_BUILD_PATH" => "/private/tmp/pramana-build-#{task_id}",
              "MIX_TEST_PARTITION" => "#{rem(idx + 1, 16)}",
              "PORT" => "#{4200 + idx}"
            },
            "required_checks" => [
              ["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"],
              ["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"],
              ["sh", "-c", "cd workflow && exec mise exec -- mix test"]
            ],
            "integration_only_checks" => [
              ["mise", "exec", "--", "mix", "precommit"]
            ],
            "shared_resources" => %{
              "corpus" => [],
              "database" => [],
              "gpu" => [],
              "other" => ["workflow-improver"],
              "service_ports" => ["#{4200 + idx}"]
            }
          },
          "reason" => "Self-healing: #{finding.category} - #{finding.summary}"
        }
      end)

    case Coordinator.apply_pm_proposals(proposals) do
      {:ok, _new_state} ->
        IO.puts("  proposed #{length(proposals)} ticket(s) accepted by PM")

        Enum.each(proposals, fn p ->
          IO.puts("    #{p["ticket"]["task_id"]}: #{p["reason"]}")
        end)

      {:error, reason} ->
        IO.puts("  PM proposal rejected: #{inspect(reason)}")
    end
  end

  # ── Helpers ──

  defp get_accepted_revision do
    case Process.whereis(PramanaFoundry.Coordinator) do
      nil ->
        Application.get_env(
          :pramana_foundry,
          :accepted_revision,
          "c8ede6a17323c080124aa4512a83494b537648a5"
        )

      pid ->
        state = :sys.get_state(pid)
        Map.get(state.state, "accepted_revision", "unknown")
    end
  rescue
    _ -> "c8ede6a17323c080124aa4512a83494b537648a5"
  end

  defp pad_idx(idx), do: idx |> to_string() |> String.pad_leading(3, "0")

  # ── Event log reader ──

  defp default_findings_path do
    root = PramanaFoundry.RuntimeRoot.fetch!()
    Path.join([root, "state", "current", "findings.jsonl"])
  end

  defp log_metrics(state) do
    # Full system snapshot: VM stats + per-process + agent server metrics
    system = PramanaFoundry.SystemMetrics.system()
    per_proc = PramanaFoundry.SystemMetrics.per_process()
    agents = PramanaFoundry.SystemMetrics.agent_servers()

    metric = %{
      "event" => "metrics_snapshot",
      "source" => "improver",
      "cycle" => state.cycle_count,
      "findings_count" => length(state.last_findings),
      "system" => system,
      "per_process" => per_proc,
      "agent_servers" => agents
    }

    LogStore.append(state.findings_path, metric)
    %{state | metrics_history: [metric | state.metrics_history] |> Enum.take(100)}
  end

  defp log_finding(fp, finding, cycle) do
    LogStore.append(
      fp,
      Map.merge(%{"event" => "finding", "source" => "improver", "cycle" => cycle}, finding)
    )
  end

  # ── Stuck-ticket classifier ──

  defp classify_stuck_tickets(events) do
    enqueued =
      events
      |> Enum.filter(&(&1["event"] == "ticket_enqueued"))
      |> Enum.map(fn e -> %{task_id: e["task_id"], at: e["at"]} end)

    admitted =
      events
      |> Enum.filter(&(&1["event"] == "assignment_admitted"))
      |> Enum.map(fn e -> e["task_id"] end)
      |> MapSet.new()

    stuck =
      enqueued
      |> Enum.reject(fn %{task_id: tid} -> MapSet.member?(admitted, tid) end)
      |> Enum.filter(fn %{at: at} ->
        case DateTime.from_iso8601(at) do
          {:ok, dt, _} ->
            DateTime.diff(DateTime.utc_now(), dt, :millisecond) > @stuck_queue_ms

          _ ->
            false
        end
      end)

    if stuck != [] do
      ids = Enum.map(stuck, & &1.task_id)

      [
        %{
          severity: :high,
          category: :stuck_tickets,
          count: length(ids),
          summary: "#{length(ids)} ticket(s) stuck in queue > #{div(@stuck_queue_ms, 1000)}s",
          details: "Stuck: #{inspect(ids)}",
          fingerprint: "stuck/v1/#{Enum.sort(ids)}"
        }
      ]
    else
      []
    end
  end

  # ── Observation anomaly classifier ──

  defp classify_observation_anomalies(observations) do
    censored = Enum.count(observations, & &1["right_censored"])
    completed = Enum.filter(observations, &(not &1["right_censored"]))

    slow =
      Enum.filter(completed, fn obs ->
        is_integer(obs["duration_ms"]) and obs["duration_ms"] > 60_000
      end)

    result =
      if censored > 3 do
        [
          %{
            severity: :medium,
            category: :running_observations,
            count: censored,
            summary: "#{censored} running phase(s) without completion event",
            details: "Phases started but not completed",
            fingerprint: "running_obs/v1"
          }
        ]
      else
        []
      end

    if slow != [] do
      ids = Enum.map(slow, & &1["task_id"]) |> Enum.uniq()
      avg_dur = div(Enum.sum(Enum.map(slow, & &1["duration_ms"])), length(slow))

      [
        %{
          severity: :low,
          category: :slow_phases,
          count: length(slow),
          summary: "#{length(slow)} phase(s) exceeded 60s (avg #{div(avg_dur, 1000)}s)",
          details: "Tasks: #{inspect(ids)}",
          fingerprint: "slow_phases/v1"
        }
        | result
      ]
    else
      result
    end
  end

  # ── No-events classifier ──

  defp classify_no_events([]) do
    [
      %{
        severity: :medium,
        category: :no_event_log,
        count: 0,
        summary: "Event log empty — phase tracking unavailable",
        details: "No events found in event log. Observation and Forecast cannot run.",
        fingerprint: "no_events/v1"
      }
    ]
  end

  defp classify_no_events(_events), do: []

  # ── Coordinator restart classifier ──

  defp classify_coordinator_restart(%{last_generation: 0, cycle_count: 0}), do: []

  defp classify_coordinator_restart(%{last_generation: prev, cycle_count: _}) do
    current = get_coordinator_generation()

    if current < prev do
      [
        %{
          severity: :critical,
          category: :coordinator_restart,
          count: 1,
          summary: "Coordinator restarted (generation #{prev} → #{current})",
          details:
            "The coordinator GenServer crashed and was restarted by the supervisor. Events were replayed.",
          fingerprint: "coord_restart/v1"
        }
      ]
    else
      []
    end
  end

  defp get_coordinator_generation do
    case Process.whereis(PramanaFoundry.Coordinator) do
      nil -> 0
      pid -> :sys.get_state(pid).state["generation"] || 0
    end
  rescue
    _ -> 0
  end

  # ── Forecast target builder ──

  defp build_forecast_targets(events) do
    # Build targets from the ticket_enqueued events
    events
    |> Enum.filter(&(&1["event"] == "ticket_enqueued"))
    |> Enum.map(fn e ->
      ticket = Map.get(e, "attributes", %{}) |> Map.get("ticket", %{})

      %{
        "workload" => Map.get(ticket, "workload", "standard"),
        "risk" => Map.get(ticket, "risk", "workflow_recovery"),
        "scope_profile" => "workflow",
        "check_profile" => "default"
      }
    end)
    |> Enum.uniq()
  end

  # ── Process memory growth classifier ──

  defp classify_process_memory do
    coord = Process.whereis(PramanaFoundry.Coordinator)

    if coord do
      mem = Process.info(coord, :memory)
      qlen = Process.info(coord, :message_queue_len)
      findings = []

      findings =
        if elem(mem, 1) > 50_000_000 do
          [
            %{
              severity: :low,
              category: :coordinator_memory,
              count: 1,
              summary: "Coordinator using #{div(elem(mem, 1), 1000)} KB memory",
              details: "Process memory exceeds 500KB threshold",
              fingerprint: "coord_mem/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings =
        if elem(qlen, 1) > 50 do
          [
            %{
              severity: :high,
              category: :mailbox_backlog,
              count: elem(qlen, 1),
              summary: "Coordinator mailbox has #{elem(qlen, 1)} pending messages",
              details: "Messages queued faster than processed",
              fingerprint: "mailbox_bl/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings
    else
      []
    end
  end

  # ── TaskSup capacity classifier ──

  defp classify_task_sup_capacity do
    sup = Process.whereis(PramanaFoundry.TaskSupervisor)

    if sup do
      counts = Supervisor.count_children(sup)
      active = counts[:active] || 0
      max = Application.get_env(:pramana_foundry, :max_tasks, 8)

      if active >= max - 1 do
        [
          %{
            severity: :medium,
            category: :task_sup_full,
            count: active,
            max: max,
            summary: "TaskSupervisor at #{active}/#{max} capacity",
            details: "Near capacity — new task launches may stall",
            fingerprint: "tasksup_cap/v1"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  # ── Duplicate run_id classifier ──

  defp classify_duplicate_run_ids do
    coord = Process.whereis(PramanaFoundry.Coordinator)

    if coord do
      s = :sys.get_state(coord)

      run_ids =
        s.state["assignments"]
        |> Map.values()
        |> Enum.map(&Map.get(&1, "run_id", ""))
        |> Enum.reject(&(&1 == ""))

      dups = run_ids |> Enum.frequencies() |> Enum.filter(fn {_id, count} -> count > 1 end)

      if dups != [] do
        [
          %{
            severity: :critical,
            category: :duplicate_run_ids,
            count: length(dups),
            summary: "#{length(dups)} duplicate run_id(s) detected",
            details: "Duplicate run_ids: #{inspect(dups)}",
            fingerprint: "dup_rid/v1"
          }
        ]
      else
        []
      end
    else
      []
    end
  end

  # ── Assignment consistency and lifecycle jank classifier ──

  defp classify_assignment_consistency do
    coord = Process.whereis(PramanaFoundry.Coordinator)

    if coord do
      s = :sys.get_state(coord)
      queue = Map.get(s.state, "queue", [])
      assignments = s.state["assignments"] || %{}
      launched = Map.get(s, :agent_registry) || %{}
      now = DateTime.utc_now()

      lifecycle =
        ~w(queued dispatched prompting working queued_correction review ready accepted parked crashed)

      # 1. Queue vs assignment status mismatch
      queue_assigns = Enum.filter(queue, &Map.has_key?(assignments, &1))

      inconsistent =
        Enum.filter(queue_assigns, fn tid ->
          status = get_in(assignments, [tid, "status"])
          status && status != "queued"
        end)

      # 2. Launched task refs pointing to missing assignments
      orphan_launches =
        Enum.filter(launched, fn {tid, _pid} ->
          not Map.has_key?(assignments, tid)
        end)

      # 3. Tickets stuck in dispatched for > 4 hours (work_timeout_seconds default)
      stuck_dispatched =
        Enum.filter(assignments, fn {_tid, a} ->
          a["status"] == "dispatched" and is_binary(Map.get(a, "dispatched_at")) and
            case DateTime.from_iso8601(a["dispatched_at"]) do
              {:ok, dt, _} -> DateTime.diff(now, dt, :second) > 300
              _ -> false
            end
        end)

      # 4. Invalid status values (not in lifecycle)
      invalid_status =
        Enum.filter(assignments, fn {_tid, a} ->
          Map.get(a, "status", "") not in lifecycle
        end)

      # 5. Skipped vital transitions (handoff/review without preceding status)
      skipped_transitions =
        Enum.filter(assignments, fn {_tid, a} ->
          has_handoff = is_map(Map.get(a, "handoff"))
          has_review = is_map(Map.get(a, "review"))

          was_dispatched =
            a["status"] in ~w(handoff_incoming review pending accepted) or
              (has_handoff and a["status"] == "accepted")

          (has_handoff or has_review) and not was_dispatched
        end)

      findings = []

      findings =
        if inconsistent != [] do
          [
            %{
              severity: :high,
              category: :inconsistent_state,
              count: length(inconsistent),
              summary: "#{length(inconsistent)} ticket(s) in queue but in non-queued status",
              details: "#{inspect(inconsistent)}",
              fingerprint: "inconsistent/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings =
        if orphan_launches != [] do
          ids = Enum.map(orphan_launches, fn {_ref, {tid, _rid}} -> tid end)

          [
            %{
              severity: :critical,
              category: :orphan_launches,
              count: length(ids),
              summary: "#{length(ids)} launched task(s) with missing assignment",
              details: "#{inspect(ids)}",
              fingerprint: "orphan/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings =
        if stuck_dispatched != [] do
          ids = Enum.map(stuck_dispatched, fn {tid, _a} -> tid end)

          [
            %{
              severity: :high,
              category: :stuck_dispatched,
              count: length(ids),
              summary: "#{length(ids)} ticket(s) dispatched >5m without handoff",
              details: "#{inspect(ids)}",
              fingerprint: "stuck_disp/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings =
        if invalid_status != [] do
          ids = Enum.map(invalid_status, fn {tid, a} -> "#{tid}=#{a["status"]}" end)

          [
            %{
              severity: :critical,
              category: :invalid_status,
              count: length(ids),
              summary: "#{length(ids)} ticket(s) with unrecognized status",
              details: "#{inspect(ids)}",
              fingerprint: "inv_status/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings =
        if skipped_transitions != [] do
          ids = Enum.map(skipped_transitions, fn {tid, _a} -> tid end)

          [
            %{
              severity: :critical,
              category: :skipped_transition,
              count: length(ids),
              summary: "#{length(ids)} ticket(s) with handoff/review but no dispatch",
              details: "#{inspect(ids)}",
              fingerprint: "skip_trans/v1"
            }
            | findings
          ]
        else
          findings
        end

      findings
    else
      []
    end
  end
end
