defmodule PramanaFoundry.CLI do
  @moduledoc "Local command shell for validation and effect-free shadow inspection."

  alias PramanaFoundry.CLI.Validators
  alias PramanaFoundry.{Import, Parity}
  alias PramanaFoundry.Exports.TelemetryExport
  alias PramanaFoundry.Projections.{Benchmark, Projection}
  alias PramanaFoundry.Status.TelemetryStatus
  alias PramanaFoundry.Telemetry.Store

  @ticket_create_options ~w(--title --priority --scope --acceptance)

  def main(["validate", kind, path]) do
    case validate(kind, path) do
      {:ok, value} -> IO.puts(:json.format(value))
      {:error, error} -> abort(error)
    end
  end

  def main(["shadow", path]) do
    with {:ok, bytes} <- File.read(path),
         {:ok, result} <- Parity.shadow(bytes) do
      IO.puts(:json.format(result))
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["runtime-root"]),
    do: IO.puts(Application.fetch_env!(:pramana_foundry, :runtime_root))

  def main(["project-assignment", path]) do
    with {:ok, canonical} <- Import.read(path, :assignment),
         {:ok, projection} <- Projection.assignment(canonical) do
      IO.puts(:json.format(projection))
    else
      {:error, reason} -> abort(reason)
    end
  end

  def main(["telemetry-status", path]) do
    with {:ok, records} <- Store.read(path) do
      IO.puts(:json.format(TelemetryStatus.aggregate(records)))
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["telemetry-export", format, input, output]) when format in ["jsonl", "csv"] do
    with {:ok, records} <- Store.read(input),
         contents <-
           if(format == "jsonl",
             do: TelemetryExport.jsonl(records),
             else: TelemetryExport.csv(records)
           ),
         :ok <- File.write(output, contents) do
      :ok
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["benchmark-projections", input, output]) do
    with {:ok, bytes} <- File.read(input),
         cases <- :json.decode(bytes),
         result <- Benchmark.run(cases),
         :ok <- File.write(output, IO.iodata_to_binary([:json.encode(result), "\n"])) do
      :ok
    else
      {:error, reason} -> abort(%{reason: reason})
    end
  end

  def main(["board" | _args]) do
    # Board needs OWL for LiveScreen, but NOT the full supervision tree
    # (coordinator, improver, etc.) since those run in the daemon.
    # Start only OWL and the board process.
    :ok = PramanaFoundry.Board.ensure_owl_started()

    # Use event-log fallback coordinator module (not a full GenServer)
    PramanaFoundry.Board.run(coordinator: :event_log)
  end

  def main(["health"]) do
    case PramanaFoundry.Coordinator.health() do
      %{} = report ->
        IO.puts(:json.format(report))

      _ ->
        IO.puts("coordinator not available")
    end
  end

  def main(["agents"]) do
    agents = PramanaFoundry.SystemMetrics.agent_servers()
    IO.puts("Active agents: #{agents["count"]}")

    Enum.each(agents["agents"], fn agent ->
      IO.puts(
        "  PID: #{agent["pid"]}  Memory: #{div(agent["memory_bytes"], 1024)}KB  Mailbox: #{agent["mailbox_depth"]}  Reductions: #{agent["reductions"]}"
      )
    end)
  end

  def main(["metrics"]) do
    system = PramanaFoundry.SystemMetrics.system()
    per_proc = PramanaFoundry.SystemMetrics.per_process()

    IO.puts("=== System ===")

    IO.puts(
      "Memory: #{div(system["total_memory_bytes"], 1_048_576)}MB total / #{div(system["processes_memory_bytes"], 1_048_576)}MB processes"
    )

    IO.puts(
      "Processes: #{system["process_count"]}/#{system["process_limit"]}  Atoms: #{system["atom_count"]}/#{system["atom_limit"]}"
    )

    IO.puts("Run queue: #{system["run_queue_length"]}  ETS tables: #{system["ets_table_count"]}")

    IO.puts(
      "Uptime: #{div(system["uptime_seconds"], 86_400)}d #{div(rem(system["uptime_seconds"], 86_400), 3600)}h"
    )

    IO.puts("\n=== Per-Process ===")

    Enum.each(per_proc, fn {name, metrics} ->
      IO.puts(
        "  #{inspect(name)}: #{div(metrics["memory_bytes"], 1024)}KB  Mailbox: #{metrics["mailbox_depth"]}  Reductions: #{metrics["reductions"]}"
      )
    end)
  end

  def main(["logs", "tail", count]) do
    n = String.to_integer(count)

    PramanaFoundry.ConsolidatedLog.tail(n)
    |> Enum.each(fn r ->
      at = Map.get(r, "at", "?") |> String.slice(0, 19)
      source = Map.get(r, "source", "?")
      event = Map.get(r, "event", Map.get(r, "phase", "?"))
      task = Map.get(r, "task_id", "-") |> String.slice(0, 12)
      IO.puts("#{at} [#{source}] #{event} #{task}")
    end)
  end

  def main(["logs", "summary"]) do
    IO.puts(:json.format(PramanaFoundry.ConsolidatedLog.summary()))
  end

  def main(["logs" | _args]) do
    PramanaFoundry.ConsolidatedLog.tail(20)
    |> Enum.each(fn r ->
      at = Map.get(r, "at", "?") |> String.slice(0, 19)
      source = Map.get(r, "source", "?")
      event = Map.get(r, "event", Map.get(r, "phase", "?"))
      task = Map.get(r, "task_id", "-") |> String.slice(0, 12)
      IO.puts("#{at} [#{source}] #{event} #{task}")
    end)
  end

  def main(["handoff", "submit", task_id, "--handoff-path", path]) do
    with {:ok, data} <- Validators.validate_json_file(path),
         :ok <- Validators.validate_task_id(task_id) do
      coord_state = PramanaFoundry.Coordinator.state()
      assignment = get_in(coord_state, ["assignments", task_id])

      if is_nil(assignment) do
        abort(%{
          error: "handoff_submit_failed",
          task_id: task_id,
          reason: "unknown assignment. Create the ticket first with: pramana ticket create",
          fix: "Use pramana ticket create to create the ticket, then submit the handoff"
        })
      else
        # If the developer AgentServer is still alive, route through it so it
        # transitions to :pending_review and waits for review outcome.
        # Otherwise fall back to direct coordinator call (agent already exited).
        agent_pid = PramanaFoundry.Coordinator.agent_pid(task_id)

        result =
          if is_pid(agent_pid) and Process.alive?(agent_pid) do
            IO.puts("Routing handoff through AgentServer #{inspect(agent_pid)} for #{task_id}")
            PramanaFoundry.AgentServer.handoff(agent_pid, data)
          else
            PramanaFoundry.Coordinator.receive_handoff(task_id, data)
          end

        case result do
          :ok ->
            IO.puts("Handoff accepted for #{task_id}")
            IO.puts("")
            IO.puts("Waiting for review verdict. The agent will be notified when the")
            IO.puts("review is complete. Status: pramana ticket status #{task_id}")

          {:ok, _assignment} ->
            IO.puts("Handoff accepted for #{task_id}")
            IO.puts("")

            IO.puts(
              "Next step: the agent has exited. Use pramana ticket status #{task_id} to check on review"
            )

          {:error, reason, _new_state} ->
            abort(%{
              error: "handoff_rejected",
              task_id: task_id,
              reason: reason,
              fix:
                "Correct the issues above and resubmit with: pramana handoff submit #{task_id} --handoff-path #{path}"
            })

          {:error, reason} ->
            abort(%{
              error: "handoff_rejected",
              task_id: task_id,
              reason: reason,
              fix:
                "Correct the issues above and resubmit with: pramana handoff submit #{task_id} --handoff-path #{path}"
            })
        end
      end
    else
      {:error, message} when is_binary(message) ->
        IO.puts(message)

        abort(%{
          error: "handoff_validation_failed",
          task_id: task_id,
          fix:
            "Fix the issue above and resubmit with: pramana handoff submit #{task_id} --handoff-path #{path}"
        })
    end
  end

  def main(["handoff", "submit", _task_id | _args]) do
    IO.puts("usage: pramana handoff submit TASK_ID --handoff-path PATH")
    IO.puts("")
    IO.puts("Example:")
    IO.puts("  pramana handoff submit FIX-42 --handoff-path ./handoff.json")
    raise "usage error"
  end

  def main(["handoff", "block", task_id, "--reason" | reason_parts]) do
    reason = Enum.join(reason_parts, " ")

    with :ok <- Validators.validate_task_id(task_id),
         false <- reason == "" do
      handoff = %{
        "outcome" => "blocked",
        "summary" => reason,
        "task_id" => task_id
      }

      case PramanaFoundry.Coordinator.receive_handoff(task_id, handoff) do
        {:ok, _assignment} ->
          IO.puts("Task #{task_id} blocked")
          IO.puts("Reason: #{reason}")

        {:error, reason} ->
          abort(%{error: "block_failed", task_id: task_id, reason: reason})
      end
    else
      true ->
        IO.puts("usage: pramana handoff block TASK_ID --reason 'why blocked'")
        raise "usage error"
    end
  end

  def main(["handoff", subcmd | _]) do
    IO.puts("Unknown handoff command: #{subcmd}")
    IO.puts("Available: submit, block")
    raise "usage error"
  end

  def main(["review", "submit", task_id, "--review-path", path]) do
    with {:ok, data} <- Validators.validate_json_file(path),
         :ok <- Validators.validate_task_id(task_id) do
      coord_state = PramanaFoundry.Coordinator.state()
      assignment = get_in(coord_state, ["assignments", task_id])

      if is_nil(assignment) do
        abort(%{
          error: "review_submit_failed",
          task_id: task_id,
          reason: "unknown assignment. The task must exist and have a handoff first",
          fix: "Use pramana handoff submit first, then submit the review"
        })
      else
        case PramanaFoundry.Coordinator.receive_review(task_id, data) do
          {:ok, _assignment} ->
            IO.puts("Review accepted for #{task_id}")
            verdict = Map.get(data, "verdict", "unknown")

            case verdict do
              "approved" ->
                IO.puts("")

                IO.puts(
                  "Promotion is suspended until FR-13/FR-14 provide verified evidence and Git integration"
                )

              "changes_requested" ->
                IO.puts("")
                IO.puts("Next step: developer corrects findings and resubmits handoff")

              "rejected" ->
                IO.puts("")
                IO.puts("Task was rejected — escalate to project manager")
            end

          {:error, reason, _new_state} ->
            abort(%{
              error: "review_rejected",
              task_id: task_id,
              reason: reason,
              fix: "Correct the review issues and resubmit"
            })

          {:error, reason} ->
            abort(%{
              error: "review_rejected",
              task_id: task_id,
              reason: reason,
              fix: "Correct the review issues and resubmit"
            })
        end
      end
    else
      {:error, message} when is_binary(message) ->
        IO.puts(message)

        abort(%{
          error: "review_validation_failed",
          task_id: task_id,
          fix:
            "Fix the issue above and resubmit with: pramana review submit #{task_id} --review-path #{path}"
        })
    end
  end

  def main(["review", "submit", _task_id | _args]) do
    IO.puts("usage: pramana review submit TASK_ID --review-path PATH")
    IO.puts("")
    IO.puts("Example:")
    IO.puts("  pramana review submit FIX-42 --review-path ./review.json")
    raise "usage error"
  end

  def main(["review", subcmd | _]) do
    IO.puts("Unknown review command: #{subcmd}")
    IO.puts("Available: submit")
    raise "usage error"
  end

  def main(["ticket", "create" | args]) do
    with {:ok, options} <- parse_ticket_create_options(args),
         {:ok, title} <- fetch_ticket_create_option(options, "--title"),
         {:ok, priority} <- fetch_ticket_create_option(options, "--priority") do
      coord_state = PramanaFoundry.Coordinator.state()

      accepted_revision =
        Map.get(coord_state, "accepted_revision", "c8ede6a17323c080124aa4512a83494b537648a5")

      scope = Map.get(options, "--scope", "**")
      acceptance = Map.get(options, "--acceptance", "verify handoff meets criteria")
      suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
      task_id = "T-#{:os.system_time(:second)}-#{suffix}"

      ticket = %{
        "task_id" => task_id,
        "title" => title,
        "priority" => priority,
        "base_revision" => accepted_revision,
        "scope" => String.split(scope, ",") |> Enum.map(&String.trim/1),
        "acceptance_criteria" => [acceptance]
      }

      case PramanaFoundry.Coordinator.enqueue_ticket(ticket) do
        :ok ->
          IO.puts("Ticket created: #{task_id}")
          IO.puts("  Title: #{title}")
          IO.puts("  Priority: #{priority}")
          IO.puts("  Task ID: #{task_id}")
          IO.puts("")
          IO.puts("Next step: the coordinator will dispatch this ticket to a developer")

        {:error, reason} ->
          abort(%{error: "ticket_create_failed", reason: reason})
      end
    else
      {:error, reason} ->
        abort(%{error: "ticket_create_failed", reason: reason})
    end
  end

  def main(["ticket", "status", task_id]) do
    with :ok <- Validators.validate_task_id(task_id) do
      state = PramanaFoundry.Coordinator.state()
      assignments = Map.get(state, "assignments", %{})

      case Map.get(assignments, task_id) do
        nil ->
          # Check queue
          queue = Map.get(state, "queue", [])

          if task_id in queue do
            IO.puts("Task #{task_id}: queued (waiting for dispatch)")
          else
            IO.puts("Task #{task_id}: not found")
            IO.puts("")
            IO.puts("To list all tasks: pramana ticket list")
          end

        assignment ->
          status = Map.get(assignment, "status", "unknown")
          error = Map.get(assignment, "error")
          handoff = Map.get(assignment, "handoff")
          _review = Map.get(assignment, "review")

          IO.puts("Task #{task_id}: #{status}")
          IO.puts("")

          case status do
            "queued" ->
              IO.puts("  Waiting in queue for dispatch")

            "dispatched" ->
              pane = Map.get(assignment, "pane_id", "?")
              agent = Map.get(assignment, "agent_name", "?")
              IO.puts("  Agent: #{agent}")
              IO.puts("  Pane: #{pane}")

            "handoff_received" ->
              IO.puts("  Handoff received, awaiting review")

              if is_map(handoff) do
                IO.puts("  Outcome: #{Map.get(handoff, "outcome", "?")}")
              end

            "review" ->
              IO.puts("  Under review")

            "review_approved" ->
              IO.puts("  Review approved!")
              IO.puts("  Next: integrate with: pramana ticket integrate #{task_id}")

            "completed" ->
              IO.puts("  Completed!")

            "parked" ->
              IO.puts("  Parked (needs manual intervention)")
              if error, do: IO.puts("  Error: #{error}")

            "crashed" ->
              IO.puts("  Crashed (agent failed)")
              if error, do: IO.puts("  Error: #{error}")

            "failed" ->
              IO.puts("  Failed")
              if error, do: IO.puts("  Error: #{error}")

            "blocked" ->
              IO.puts("  Blocked")
              if is_map(handoff), do: IO.puts("  Reason: #{Map.get(handoff, "summary", "?")}")

            _ ->
              if error, do: IO.puts("  Error: #{error}")
          end
      end
    else
      {:error, msg} ->
        IO.puts(msg)
        raise "usage error"
    end
  end

  def main(["ticket", "list"]) do
    state = PramanaFoundry.Coordinator.state()
    assignments = Map.get(state, "assignments", %{})
    queue = Map.get(state, "queue", [])

    if assignments == %{} and queue == [] do
      IO.puts("No tickets found")
    else
      IO.puts("Active tickets:")
      IO.puts("")

      Enum.each(queue, fn task_id ->
        IO.puts("  #{task_id}: queued")
      end)

      Enum.each(assignments, fn {task_id, assignment} ->
        status = Map.get(assignment, "status", "unknown")
        IO.puts("  #{task_id}: #{status}")
      end)
    end
  end

  def main(["ticket", "integrate", task_id]) do
    with :ok <- Validators.validate_task_id(task_id) do
      case PramanaFoundry.Coordinator.integrate(task_id) do
        {:ok, _assignment} ->
          IO.puts("Integration completed for #{task_id}")

        {:error, reason} ->
          abort(%{error: "integration_failed", task_id: task_id, reason: reason})
      end
    else
      {:error, msg} ->
        IO.puts(msg)
        raise "usage error"
    end
  end

  def main(["ticket", "unblock", task_id]) do
    with :ok <- Validators.validate_task_id(task_id) do
      case PramanaFoundry.Coordinator.unblock_ticket(task_id) do
        :ok ->
          IO.puts("Task #{task_id}: unblocked — re-queued for dispatch")

        {:error, reason} ->
          abort(%{error: "unblock_failed", task_id: task_id, reason: reason})
      end
    else
      {:error, msg} ->
        IO.puts( msg)
        raise "usage error"
    end
  end

  def main(["ticket", subcmd | _]) do
    IO.puts("Unknown ticket command: #{subcmd}")
    IO.puts("Available: create, status, list, integrate, unblock")
    raise "usage error"
  end

  def main(["handoff" | _args]) do
    IO.puts("usage: pramana handoff submit|block ...")
    IO.puts("")
    IO.puts("Commands:")
    IO.puts("  handoff submit TASK_ID --handoff-path PATH   Submit a completed handoff")
    IO.puts("  handoff block TASK_ID --reason TEXT           Block a task")
    raise "usage error"
  end

  def main(["review" | _args]) do
    IO.puts("usage: pramana review submit TASK_ID --review-path PATH")
    raise "usage error"
  end

  def main(["ticket" | _args]) do
    IO.puts("usage: pramana ticket create|status|list|integrate ...")
    IO.puts("")
    IO.puts("Commands:")
    IO.puts("  ticket create --title TITLE --priority P0|P1|P2|P3  Create a new ticket")
    IO.puts("  ticket status TASK_ID                                Show ticket status")
    IO.puts("  ticket list                                          List all tickets")
    IO.puts("  ticket integrate TASK_ID                             Integrate approved work")
    raise "usage error"
  end

  @spec validate(binary(), Path.t()) :: {:ok, map()} | {:error, map()}
  def validate(kind, path) when is_binary(kind) and is_binary(path) do
    Import.read(path, String.to_existing_atom(kind))
  rescue
    ArgumentError -> {:error, %{reason: :unsupported_schema}}
  end

  defp abort(error) do
    detail = error[:reason] || error[:fix] || :json.encode(error)
    detail = if is_binary(detail), do: detail, else: inspect(detail)
    raise "CLI error (#{error[:error] || "unknown"}): #{detail}"
  end

  defp parse_ticket_create_options(args), do: parse_ticket_create_options(args, %{})

  defp parse_ticket_create_options([], options), do: {:ok, options}

  defp parse_ticket_create_options([option, value | rest], options) do
    cond do
      auto_approve_option?(option) ->
        {:error, "auto_approve is forbidden; independent review is mandatory"}

      option not in @ticket_create_options ->
        {:error, "unknown ticket create option: #{inspect(option)}"}

      Map.has_key?(options, option) ->
        {:error, "duplicate ticket create option: #{option}"}

      String.starts_with?(value, "--") ->
        {:error, "missing value for ticket create option: #{option}"}

      true ->
        parse_ticket_create_options(rest, Map.put(options, option, value))
    end
  end

  defp parse_ticket_create_options([option], _options) do
    if auto_approve_option?(option) do
      {:error, "auto_approve is forbidden; independent review is mandatory"}
    else
      {:error, "missing value for ticket create option: #{inspect(option)}"}
    end
  end

  defp fetch_ticket_create_option(options, option) do
    case Map.fetch(options, option) do
      {:ok, value} when is_binary(value) ->
        if String.trim(value) == "" do
          {:error, "ticket create option #{option} cannot be empty"}
        else
          {:ok, value}
        end

      :error ->
        {:error, "missing required ticket create option: #{option}"}
    end
  end

  defp auto_approve_option?(option) when is_binary(option) do
    option
    |> String.split("=", parts: 2)
    |> List.first()
    |> String.trim_leading("-")
    |> String.downcase()
    |> String.replace(["-", "_"], "")
    |> Kernel.==("autoapprove")
  end
end
