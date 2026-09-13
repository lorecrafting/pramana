defmodule PramanaFoundry.HardeningPM do
  @moduledoc """
  Dedicated PM for self-healing tickets. Runs on a timer, reads the coordinator queue,
  picks up IMPRV-* tickets, validates/elaborates them, and submits amendments or
  parking proposals.

  This is the second PM instance — it handles only hardening work while the main PM
  (or the Improver's direct proposal flow) handles feature work. It uses a restricted
  role file (`roles/hardening_pm.md`) and a cheaper model profile since hardening
  tickets are mechanically simpler.
  """

  use GenServer

  alias PramanaFoundry.Coordinator

  # 10 minutes
  @default_interval_ms 600_000
  @hardening_prefix "IMPRV-"

  # ── Public API ──

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name] || __MODULE__)
  end

  @doc "Trigger an immediate review cycle."
  def review(pid \\ __MODULE__), do: GenServer.cast(pid, :review)

  # ── GenServer callbacks ──

  @impl true
  def init(opts) do
    interval_ms = Keyword.get(opts, :interval_ms, @default_interval_ms)

    IO.puts("HardeningPM init: interval=#{interval_ms}ms")

    timer_ref = Process.send_after(self(), :review, interval_ms)

    {:ok,
     %{
       interval_ms: interval_ms,
       timer_ref: timer_ref,
       cycle_count: 0
     }}
  end

  @impl true
  def handle_cast(:review, state) do
    state = do_review(state)
    {:noreply, state}
  end

  @impl true
  def handle_info(:review, state) do
    state = do_review(state)
    timer_ref = Process.send_after(self(), :review, state.interval_ms)
    {:noreply, %{state | timer_ref: timer_ref}}
  end

  # ── Review cycle ──

  defp do_review(state) do
    cycle = state.cycle_count + 1
    IO.puts("\n=== HardeningPM cycle #{cycle} ===")

    coord = Process.whereis(Coordinator)

    if coord == nil do
      IO.puts("  coordinator not available")
      %{state | cycle_count: cycle}
    else
      coord_state = :sys.get_state(coord)
      assignments = Map.get(coord_state.state, "assignments", %{})
      queue = Map.get(coord_state.state, "queue", [])

      IO.puts("  queue: #{inspect(queue)}")

      # Find IMPRV- tickets in the queue
      hardening_in_queue = Enum.filter(queue, &String.starts_with?(&1, @hardening_prefix))

      # Find IMPRV- assignments already admitted
      {hardening_assigned, _other_assignments} =
        Map.split(
          assignments,
          Map.keys(assignments) |> Enum.filter(&String.starts_with?(&1, @hardening_prefix))
        )

      IO.puts("  hardening tickets in queue: #{length(hardening_in_queue)}")
      IO.puts("  hardening assignments: #{map_size(hardening_assigned)}")

      # 1. Validate and elaborate queued hardening tickets
      elaborated =
        hardening_in_queue
        |> Enum.map(fn task_id -> get_in(assignments, [task_id, "ticket"]) end)
        |> Enum.reject(&is_nil/1)
        |> Enum.flat_map(&elaborate_ticket/1)

      with :ok <- validate_no_scope_leak(elaborated),
           {:ok, amended} <- apply_elaborations(elaborated, coord) do
        IO.puts("  elaborated #{length(amended)} ticket(s)")
      else
        {:error, reason} ->
          IO.puts("  elaboration error: #{inspect(reason)}")
      end

      # 2. Check if any IMPRV- tickets in queue lack matching proposals
      queued_ids = MapSet.new(hardening_in_queue)
      proposed_ids = MapSet.new(elaborated, & &1["task_id"])
      stale = MapSet.difference(queued_ids, proposed_ids)

      if MapSet.size(stale) > 0 do
        IO.puts("  stale IMPRV- tickets (no longer relevant): #{inspect(MapSet.to_list(stale))}")

        park_proposals =
          stale
          |> MapSet.to_list()
          |> Enum.map(fn task_id ->
            %{
              "operation" => "park",
              "task_id" => task_id,
              "reason" =>
                "Stale: ticket no longer relevant (elaboration cycle found no matching finding)"
            }
          end)

        case Coordinator.apply_pm_proposals(park_proposals) do
          {:ok, _} ->
            IO.puts("  parked #{length(park_proposals)} stale ticket(s)")

          {:error, reason} ->
            IO.puts("  park error: #{inspect(reason)}")
        end
      end

      %{state | cycle_count: cycle}
    end
  end

  # ── Ticket elaboration ──

  defp elaborate_ticket(nil), do: []

  defp elaborate_ticket(%{"task_id" => tid} = ticket) when is_binary(tid) do
    task_id = tid

    # Check which fields need elaboration
    amendments = build_amendments(ticket)

    if amendments == [] do
      IO.puts("  #{task_id}: no elaboration needed")
      []
    else
      IO.puts("  #{task_id}: elaborating #{length(amendments)} field(s)")

      [
        %{
          "operation" => "amend",
          "task_id" => task_id,
          "ticket" => Map.merge(ticket, Map.new(amendments)),
          "reason" =>
            "HardeningPM elaboration: #{Enum.join(amendments |> Enum.map(fn {k, _} -> k end), ", ")}"
        }
      ]
    end
  end

  defp elaborate_ticket(_ticket), do: []

  defp build_amendments(ticket) do
    []
    |> maybe_add_field(ticket, "scope", ["workflow/lib/pramana_foundry/**"])
    |> maybe_add_field(ticket, "exclusions", ["No changes outside workflow/"])
    |> maybe_add_field(ticket, "work_class", "p0_high_risk")
    |> maybe_add_field(ticket, "risk", "workflow_recovery")
    |> maybe_add_field(ticket, "profile", "omp_gemini_developer")
    |> maybe_add_field(ticket, "model", "omp-google-gemini-3.8-flash-developer")
    |> maybe_add_field(ticket, "reasoning", "medium")
    |> maybe_add_field(ticket, "workload", "lightweight")
    |> maybe_add_field(ticket, "required_checks", [
      ["sh", "-c", "cd workflow && exec mise exec -- mix format --check-formatted"],
      ["sh", "-c", "cd workflow && exec mise exec -- mix compile --warnings-as-errors"],
      ["sh", "-c", "cd workflow && exec mise exec -- mix test"]
    ])
    |> maybe_add_field(ticket, "integration_only_checks", [
      ["mise", "exec", "--", "mix", "precommit"]
    ])
    |> maybe_add_field(ticket, "shared_resources", %{
      "corpus" => [],
      "database" => [],
      "gpu" => [],
      "other" => ["workflow-improver"],
      "service_ports" => []
    })
    |> ensure_acceptance_criteria(ticket)
  end

  defp maybe_add_field(acc, ticket, key, default) do
    if is_nil(Map.get(ticket, key)) or Map.get(ticket, key) == [] or
         (is_binary(Map.get(ticket, key)) and String.trim(Map.get(ticket, key, "")) == "") do
      [{key, default} | acc]
    else
      acc
    end
  end

  defp ensure_acceptance_criteria(acc, ticket) do
    criteria = Map.get(ticket, "acceptance_criteria", [])

    if length(criteria) < 2 do
      summary = Map.get(ticket, "outcome", "Hardening improvement")

      [
        {:acceptance_criteria,
         [
           "Implement: #{summary}",
           "Add regression detection to Improver classifiers",
           "Verify fix with existing test suite"
         ]}
        | acc
      ]
    else
      acc
    end
  end

  # ── Validation ──

  defp validate_no_scope_leak(elaborated) do
    leaks =
      elaborated
      |> Enum.flat_map(fn e -> Map.get(e["ticket"], "scope", []) end)
      |> Enum.reject(fn s -> String.starts_with?(s, "workflow/") end)

    if leaks == [] do
      :ok
    else
      {:error, "scope leak: tickets reference paths outside workflow/: #{inspect(leaks)}"}
    end
  end

  defp apply_elaborations([], _coord), do: {:ok, []}

  defp apply_elaborations(elaborated, coord) do
    case GenServer.call(coord, {:apply_pm_proposals, elaborated, []}, :infinity) do
      {:ok, _new_state} ->
        {:ok, elaborated}

      {:error, reason} ->
        {:error, reason}

      other ->
        IO.puts("  apply_pm_proposals returned unexpected: #{inspect(other)}")
        {:ok, elaborated}
    end
  end
end
