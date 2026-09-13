defmodule PramanaFoundry.AgentServer do
  @moduledoc """
  GenServer per running Herdr agent. Lives for the agent's full lifecycle.

  Fully instrumented: every lifecycle transition emits a structured telemetry
  record to the coordinator's telemetry log, recording durations and outcomes
  for the Improver's self-healing loop and the board's dashboard.
  """

  use GenServer, restart: :temporary

  alias PramanaFoundry.Herdr.{Adapter, Identity}

  # ── Public API ──

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, [])
  end

  @doc """
  Submit a handoff result to a running agent server.
  """
  @spec handoff(pid(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def handoff(agent_pid, handoff_data, opts \\ []) do
    GenServer.call(agent_pid, {:handoff, handoff_data, opts}, :infinity)
  rescue
    _ -> {:error, :agent_gone}
  end

  @doc "Submit a review result to a running reviewer agent."
  @spec submit_review(pid(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def submit_review(reviewer_pid, review_data, opts \\ []) do
    GenServer.call(reviewer_pid, {:submit_review, review_data, opts}, :infinity)
  rescue
    _ -> {:error, :agent_gone}
  end

  @doc "Check the agent's current status."
  def status(agent_pid) do
    if Process.alive?(agent_pid) do
      GenServer.call(agent_pid, :status, 5000)
    else
      %{status: :gone}
    end
  rescue
    _ -> %{status: :gone}
  end

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
    task_id = Keyword.fetch!(opts, :task_id)
    run_id = Keyword.fetch!(opts, :run_id)
    checkout = Keyword.fetch!(opts, :checkout)
    adapter = Keyword.fetch!(opts, :adapter)
    coordinator_pid = Keyword.fetch!(opts, :coordinator_pid)
    role = Keyword.get(opts, :role, :developer)  # :developer or :reviewer
    model = Keyword.get(opts, :model, "openrouter/deepseek/deepseek-v4-flash")
    approval_mode = Keyword.get(opts, :approval_mode, "yolo")
    herdr_timeout_ms = Keyword.get(opts, :herdr_timeout_ms, 30_000)
    work_timeout_ms = Keyword.get(opts, :work_timeout_ms, :timer.minutes(30))
    telemetry_path = Keyword.get(opts, :telemetry_path)
    handoff_data = Keyword.get(opts, :handoff_data, %{})  # context for reviewer
    herdr_opts = Keyword.get(opts, :herdr_opts, [])

    prefix = if role == :reviewer, do: "pramana-review-", else: "pramana-dev-"
    agent_name = "#{prefix}#{String.slice(run_id, 0, 8) |> String.downcase()}"

    state = %{
      task_id: task_id,
      run_id: run_id,
      checkout: checkout,
      adapter: adapter,
      coordinator_pid: coordinator_pid,
      role: role,
      phase: :launching,
      pane_id: nil,
      terminal_id: nil,
      agent_name: agent_name,
      identity: nil,
      model: model,
      approval_mode: approval_mode,
      herdr_timeout_ms: herdr_timeout_ms,
      work_timeout_ms: work_timeout_ms,
      timeout_ref: nil,
      launched: false,
      herdr_opts: herdr_opts,
      telemetry_path: telemetry_path,
      handoff_data: handoff_data,
      # Per-step timing accumulators
      launch_start: nil,
      step_timings: %{},
      # Handoff tracking for review cycle
      handoff_artifact: nil,
      handoff_attempt: 0
    }

    send(self(), :launch)
    {:ok, state}
  end

  @impl true
  def handle_info(
        :launch,
        %{adapter: adapter, herdr_timeout_ms: herdr_timeout_ms} = state
      ) do
    state = %{state | launch_start: now_timestamp()}

    case do_launch(state) do
      {:ok, launched_state} ->
        launched_state = %{launched_state | agent_name: launched_state.identity.name}
        IO.puts("  Agent #{launched_state.agent_name} launched on pane #{launched_state.pane_id} for #{launched_state.task_id}")

        timeout_ref = Process.send_after(self(), :work_timeout, launched_state.work_timeout_ms)
        launched_state = %{launched_state | timeout_ref: timeout_ref, launched: true}

        duration_ms = elapsed_ms(launched_state.launch_start)
        emit_telemetry(launched_state.telemetry_path, "agent_launch", %{
          "task_id" => launched_state.task_id,
          "run_id" => launched_state.run_id,
          "phase" => "launch",
          "outcome" => "dispatched",
          "agent" => launched_state.agent_name,
          "pane" => launched_state.pane_id,
          "duration_ms" => duration_ms,
          "steps" => launched_state.step_timings
        })

        send(launched_state.coordinator_pid, {:agent_launched, launched_state.task_id, :ok, %{
          pane_id: launched_state.pane_id,
          agent_name: launched_state.agent_name
        }})

        {:noreply, launched_state}

      {:error, stage, reason, pane_id, state_after_failure} ->
        IO.puts("  Agent launch failed at #{stage} for #{state_after_failure.task_id}: #{inspect(reason)}")

        if is_binary(pane_id) do
          cleanup_pane(adapter, pane_id, herdr_timeout_ms)
        end

        duration_ms = elapsed_ms(state_after_failure.launch_start)
        emit_telemetry(state_after_failure.telemetry_path, "agent_launch", %{
          "task_id" => state_after_failure.task_id,
          "run_id" => state_after_failure.run_id,
          "phase" => "launch",
          "outcome" => "failed",
          "stage" => to_string(stage),
          "reason" => error_reason(reason),
          "duration_ms" => duration_ms
        })

        send(state_after_failure.coordinator_pid, {:agent_launched, state_after_failure.task_id, {:error, stage, reason}, %{}})

        {:stop, {:launch_failed, stage, reason}, state_after_failure}
    end
  end

  @impl true
  def handle_info(:work_timeout, state) do
    IO.puts("  Agent #{state.agent_name} timed out after #{state.work_timeout_ms}ms")

    if is_binary(state.pane_id) do
      cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
    end

    emit_telemetry(state.telemetry_path, "agent_timeout", %{
      "task_id" => state.task_id,
      "run_id" => state.run_id,
      "phase" => "timeout",
      "outcome" => "timeout",
      "agent" => state.agent_name,
      "pane" => state.pane_id,
      "work_timeout_ms" => state.work_timeout_ms
    })

    send(state.coordinator_pid, {:agent_completed, state.task_id, state.run_id, :timeout, %{pane_id: state.pane_id}})

    {:stop, :shutdown, state}
  end

  @impl true
  def handle_info(:review_timeout, state) do
    IO.puts("  Agent #{state.agent_name} review timeout for #{state.task_id} — no review received")

    if is_binary(state.pane_id) do
      cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
    end

    emit_telemetry(state.telemetry_path, "agent_review_timeout", %{
      "task_id" => state.task_id,
      "run_id" => state.run_id,
      "phase" => "review_timeout",
      "outcome" => "timeout",
      "agent" => state.agent_name,
      "pane" => state.pane_id
    })

    send(state.coordinator_pid, {:agent_completed, state.task_id, state.run_id, :review_timeout, %{pane_id: state.pane_id}})

    {:stop, :shutdown, state}
  end

  # Receive correction findings from reviewer and re-prompt the agent
  @impl true
  def handle_info({:apply_correction, review_artifact}, state) do
    IO.puts("  Agent #{state.agent_name} received correction for #{state.task_id}")

    _correction_context = Map.get(review_artifact, "correction_context", %{})
    findings = Map.get(review_artifact, "findings", [])

    correction_prompt = """
    The reviewer has requested corrections to your previous handoff.

    Findings to address:
    #{Enum.map_join(findings, "\n", &("- #{&1}"))}

    Review the findings above, fix each one in the checkout, then re-run checks.
    When all findings are addressed, submit an updated handoff with the new commit.
    """

    case Adapter.prompt(state.adapter, state.identity, correction_prompt,
           timeout_ms: state.herdr_timeout_ms, wait: false) do
      {:ok, _} ->
        IO.puts("    correction prompt sent to #{state.agent_name}")
        # Reset work timeout for the correction work
        timeout_ref = Process.send_after(self(), :work_timeout, state.work_timeout_ms)
        {:noreply, %{state | phase: :correcting, timeout_ref: timeout_ref}}

      {:error, reason} ->
        IO.puts("    correction prompt failed: #{inspect(reason)}")
        {:noreply, state}
    end
  end

  # Review approved — agent can clean up and stop
  @impl true
  def handle_info(:review_approved, state) do
    IO.puts("  Agent #{state.agent_name} review approved for #{state.task_id} — cleaning up")

    if is_binary(state.pane_id) do
      cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
    end

    send(state.coordinator_pid, {:agent_completed, state.task_id, state.run_id, {:handoff, :ok}, %{pane_id: state.pane_id}})

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    IO.puts("  AgentServer #{state.task_id} unexpected msg: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    reply = state |> Map.take([:task_id, :run_id, :agent_name, :pane_id, :launched, :phase])
    {:reply, Map.put(reply, :status, :running), state}
  end

  @impl true
  def handle_call({:submit_review, review_data, opts}, _from, state) do
    IO.puts("  Agent #{state.agent_name} review submitted for #{state.task_id} (role=#{state.role})")

    result =
      case apply(PramanaFoundry.Coordinator, :receive_review, [state.task_id, review_data, opts]) do
        {:ok, _} -> :ok
        {:error, _reason} -> :review_rejected
      end

    emit_telemetry(state.telemetry_path, "agent_review", %{
      "task_id" => state.task_id,
      "run_id" => state.run_id,
      "phase" => "review",
      "outcome" => if(result == :ok, do: "approved", else: "rejected"),
      "agent" => state.agent_name
    })

    case result do
      :ok ->
        # Review approved — both agents clean up
        # (the coordinator already updated state via receive_review)
        cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
        {:stop, :normal, :ok, state}

      :review_rejected ->
        # Review rejected (correction_needed) — keep reviewers alive for next cycle?
        # For now, just clean up and stop. Developer stays alive for corrections.
        cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
        {:stop, :normal, {:error, :review_rejected}, state}
    end
  end

  # For developer role: submit handoff
  @impl true
  def handle_call({:handoff, handoff_data, opts}, _from, state) do
    IO.puts("  Agent #{state.agent_name} handoff received for #{state.task_id}")

    result =
      case apply(PramanaFoundry.Coordinator, :receive_handoff, [state.task_id, handoff_data, opts]) do
        {:ok, _} -> :ok
        {:error, _reason} -> :handoff_rejected
      end

    emit_telemetry(state.telemetry_path, "agent_handoff", %{
      "task_id" => state.task_id,
      "run_id" => state.run_id,
      "phase" => "handoff",
      "outcome" => if(result == :ok, do: "accepted", else: "rejected"),
      "agent" => state.agent_name,
      "duration_ms" => 0
    })

    case result do
      :ok ->
        # Handoff accepted — stay alive, enter pending_review.
        # Don't clean up pane — correction may come back.
        # Cancel work timeout, set review timeout instead.
        Process.cancel_timer(state.timeout_ref)
        review_timeout = Process.send_after(self(), :review_timeout, :timer.minutes(10))

        {:reply, :ok,
         %{state | phase: :pending_review, timeout_ref: review_timeout,
           handoff_data: handoff_data, handoff_attempt: (state.handoff_attempt || 0) + 1}}

      :handoff_rejected ->
        # Handoff rejected — re-enqueue via coordinator, clean up pane, terminate.
        # The coordinator auto-re-enqueues with retry budget.
        if is_binary(state.pane_id) do
          cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)
        end

        send(state.coordinator_pid, {:agent_completed, state.task_id, state.run_id,
          {:handoff, {:error, :rejected}}, %{pane_id: state.pane_id}})

        {:stop, :normal, {:error, :handoff_rejected}, state}
    end
  end

  @impl true
  def terminate(reason, state) do
    if state.launched and is_binary(state.pane_id) do
      cond do
        reason == :normal ->
          # Normal stop — handler already cleaned up the pane, nothing to do
          :ok

        reason == :shutdown ->
          # Supervisor shutdown (e.g. terminal-state cleanup) — clean up leaky pane
          cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)

        true ->
          # Abnormal exit — clean up pane AND notify coordinator of crash
          cleanup_pane(state.adapter, state.pane_id, state.herdr_timeout_ms)

          emit_telemetry(state.telemetry_path, "agent_crash", %{
            "task_id" => state.task_id,
            "run_id" => state.run_id,
            "phase" => "crash",
            "outcome" => "crashed",
            "reason" => error_reason(reason),
            "pane" => state.pane_id
          })

          send(state.coordinator_pid, {:agent_crashed, state.task_id, state.run_id, reason,
            %{pane_id: state.pane_id}})
      end
    end

    :ok
  end

  # ── Launch sequence ──

  defp do_launch(state) do
    adapter = state.adapter
    checkout = state.checkout
    timeout_ms = state.herdr_timeout_ms
    herdr_opts = state.herdr_opts
    task_id = state.task_id
    run_id = state.run_id

    # Step 1: Split pane
    pane_start = now_timestamp()

    case Adapter.split_pane(adapter, checkout, "right", %{}, Keyword.merge([timeout_ms: timeout_ms], herdr_opts)) do
      {:ok, pane_info} ->
        pane_id = pane_info[:pane_id] || pane_info["pane_id"]
        terminal_id = pane_info[:terminal_id] || pane_info["terminal_id"]
        pane_duration = elapsed_ms(pane_start)
        IO.puts("    split pane: #{pane_id} (#{pane_duration}ms)")

        step_timings = Map.put(state.step_timings, :pane_split_ms, pane_duration)

        # Step 2: Start agent
        agent_start = now_timestamp()

        case Adapter.start_agent(adapter, state.agent_name, "omp", pane_id, timeout_ms, [
               "--model", state.model,
               "--approval-mode", state.approval_mode
             ], Keyword.merge([timeout_ms: timeout_ms + 5_000], herdr_opts)) do
          {:ok, result} ->
            agent_duration = elapsed_ms(agent_start)
            IO.puts("    agent started: #{state.agent_name} (#{agent_duration}ms)")
            step_timings = Map.put(step_timings, :agent_start_ms, agent_duration)
            agent_data = result["result"]["agent"] || result["agent"] || result

            case Identity.from_agent(agent_data) do
              {:ok, identity} ->
                prompt_start = now_timestamp()

                role_file = if state.role == :reviewer, do: "reviewer.md", else: "developer.md"

                prompt_text = cond do
                  state.role == :reviewer ->
                    handoff = state.handoff_data
                    files = Enum.join(Map.get(handoff, "changed_files", []), ", ")
                    outcome = Map.get(handoff, "outcome", "")
                    prev_error = Map.get(handoff, "previous_error", "")
                    error_block = if prev_error != "", do: "\nPrevious review attempt failed: #{prev_error}\nFix these issues before submitting.", else: ""
                    """
                    Read and follow foundry/roles/reviewer.md (role file).
                    Review the completed assignment #{task_id}.
                    RUN_ID: #{run_id}
                    Checkout: #{checkout}
                    Handoff commit: #{Map.get(handoff, "commit", "?")}
                    Changed files: #{files}
                    Outcome: #{outcome}
                    #{error_block}
                    When you have completed your review, submit the review artifact
                    (verdict, findings, checks, remaining_risks) to the coordinator.
                    """
                  true ->
                    prev_error = Map.get(state.handoff_data, "previous_error", "")
                    error_block = if prev_error != "", do: "\nPrevious attempt failed with: #{prev_error}\nAddress these issues before submitting handoff.", else: ""
                    """
                    Read and follow foundry/roles/#{role_file} (role file).
                    Execute assignment #{task_id}.
                    RUN_ID: #{run_id}
                    Work in checkout #{checkout}.
                    Complete the work, run required checks, then submit the handoff.#{error_block}
                    """
                end

                case Adapter.prompt(adapter, identity, prompt_text, Keyword.merge([timeout_ms: timeout_ms, wait: false], herdr_opts)) do
                  {:ok, _} ->
                    prompt_duration = elapsed_ms(prompt_start)
                    IO.puts("    prompted: #{task_id} (#{prompt_duration}ms)")
                    step_timings = Map.put(step_timings, :prompt_ms, prompt_duration)
                    {:ok, %{state | pane_id: pane_id, terminal_id: terminal_id, identity: identity, step_timings: step_timings}}

                  {:error, reason} ->
                    IO.puts("    prompt error: #{inspect(reason)}")
                    {:error, :prompt_failed, reason, pane_id, state}
                end

              {:error, reason} ->
                IO.puts("    identity parse error: #{inspect(reason)}")
                {:error, :identity_parse_failed, reason, pane_id, state}
            end

          {:error, reason} ->
            IO.puts("    agent start error: #{inspect(reason)}")
            {:error, :agent_start_failed, reason, pane_id, state}
        end

      {:error, reason} ->
        IO.puts("    pane split error: #{inspect(reason)}")
        {:error, :pane_split_failed, reason, nil, state}
    end
  catch
    kind, error ->
      IO.puts("    launch_agent CRASHED #{kind}: #{inspect(error)}")
      {:error, :launch_crashed, {kind, error}, nil, state}
  end

  # ── Pane cleanup ──

  defp cleanup_pane(adapter, pane_id, timeout_ms, _opts \\ []) do
    case PramanaFoundry.Herdr.Runner.System.run(
           [adapter.command, "pane", "close", pane_id],
           timeout_ms: timeout_ms
         ) do
      {:ok, _} -> IO.puts("    cleaned up pane #{pane_id}")
      {:error, {:not_found, _}} -> IO.puts("    pane #{pane_id} already gone")
      {:error, reason} -> IO.puts("    pane cleanup for #{pane_id} failed: #{inspect(reason)}")
    end
  end

  # ── Telemetry ──

  defp emit_telemetry(nil, _phase, _attrs), do: :ok

  defp emit_telemetry(log_path, phase, attrs) when is_binary(log_path) do
    now = DateTime.utc_now() |> DateTime.to_iso8601()
    record = %{
      "record_id" => :crypto.strong_rand_bytes(8) |> :binary.encode_hex(),
      "record_type" => "command",
      "phase" => phase,
      "task_id" => Map.get(attrs, "task_id", "agent"),
      "run_id" => Map.get(attrs, "run_id", :crypto.strong_rand_bytes(4) |> :binary.encode_hex()),
      "started_at" => now,
      "ended_at" => now,
      "duration_ms" => Map.get(attrs, "duration_ms", 0),
      "exit_code" => Map.get(attrs, "exit_code", 0),
      "outcome" => Map.get(attrs, "outcome", "unknown"),
      "reason" => Map.get(attrs, "reason"),
      "agent" => Map.get(attrs, "agent"),
      "pane" => Map.get(attrs, "pane"),
      "resource_class" => "workflow"
    }

    record = if steps = Map.get(attrs, "steps") do
      Map.put(record, "step_timings", steps)
    else
      record
    end

    case PramanaFoundry.Telemetry.Telemetry.validate(record) do
      {:ok, validated} ->
        case PramanaFoundry.Telemetry.Store.append(log_path, validated) do
          :ok -> :ok
          :duplicate -> :ok
          {:error, reason} -> IO.puts("  telemetry append error: #{inspect(reason)}")
        end
      {:error, reason} ->
        IO.puts("  telemetry validation error: #{inspect(reason)}")
    end
  end

  defp emit_telemetry(_path, _phase, _attrs), do: :ok

  # ── Helpers ──

  defp now_timestamp do
    DateTime.utc_now()
  end

  defp elapsed_ms(start) do
    DateTime.diff(DateTime.utc_now(), start, :millisecond)
  end

  # Convert arbitrary error terms to structured strings
  defp error_reason({kind, error}) when is_atom(kind) do
    "#{kind}:#{inspect(error)}"
  end

  defp error_reason(term) when is_atom(term) do
    Atom.to_string(term)
  end

  defp error_reason(term) when is_binary(term) do
    term
  end

  defp error_reason(term) do
    inspect(term)
  end
end