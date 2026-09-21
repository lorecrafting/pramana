defmodule PramanaFoundry.Test.KernelSearch do
  @moduledoc """
  Exhaustive bounded search over every state the kernel can reach.

  The seeded walks in `KernelWalk` sample the state space; this enumerates it. Within a
  bounded depth and a reduced alphabet, every accepted event sequence is explored, so an
  invariant asserted here is proved for that bound rather than sampled — and a violation
  comes back with the exact sequence that produced it.

  This exists because the defects that blocked this subcommit three times are precisely the
  ones exhaustive search finds mechanically: a transition the contract forbids being
  accepted, and a transition being accepted out of the order the contract requires. Every
  one of them was found instead by a human reading prose against code, at roughly 200,000
  tokens a round. `attempt_settled(rejected)` from `developing` sits two events from the
  empty state; `cancellation_finalized(after_integration)` sits three.

  Two things make the bound affordable. Most proposals are rejected, which prunes hard —
  13,518 accepted transitions at depth six out of far more attempted. And states are
  canonicalised before memoisation: revision counters, `last_event_id` and `last_sequence`
  differ on every path, so without stripping them no two paths would ever converge and the
  search would degenerate into a tree.
  """

  alias PramanaFoundry.Test.KernelWalk
  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  @default_depth 6

  @doc """
  Every state reachable within `depth` accepted events, each with the path that reached it.

  Returns `[{state, path}]`, `path` oldest first, including the initial state with an
  empty path. Each level expands only what the previous produced.
  """
  def search(depth \\ @default_depth, opts \\ []) do
    {states, _reasons} = explore(depth, opts)
    states
  end

  @doc """
  Every rejection reason the kernel produces within `depth`.

  A guard whose reason never appears cannot fire on any sequence within the bound, which
  makes it dead code rather than defence in depth — `require_reviewer_open` was exactly
  that, and was claimed in a commit message as a fix. Comparing this against the errors the
  module declares turns "is this guard reachable" from a question someone answers by
  reading into one the suite answers.
  """
  def rejection_reasons(depth \\ @default_depth, opts \\ []) do
    {_states, reasons} = explore(depth, opts)
    reasons
  end

  # One traversal. `search/2` already applies every proposal and threw the errors away,
  # so collecting reasons separately re-ran the whole search to recompute what the first
  # pass had in hand — which is most of why the guard-reachability suite cost a minute and
  # had to be kept out of the mutation sweep's fast phase.
  defp explore(depth, opts) do
    initial = State.new()

    {frontier, states, seen, reasons} =
      Enum.reduce(
        1..depth,
        {[{initial, []}], [{initial, []}], MapSet.new([key(initial)]), MapSet.new()},
        fn _level, {frontier, states, seen, reasons} ->
          {next, seen, reasons} = expand(frontier, seen, reasons, opts)
          {next, states ++ next, seen, reasons}
        end
      )

    # The deepest frontier is reached but never expanded, so nothing has yet proposed from
    # it. Its refusals are as real as any other's, and omitting them made two guards look
    # unreachable that are not. One more proposal pass, discarding the states.
    {_ignored, _seen, reasons} = expand(frontier, seen, reasons, opts)

    {states, reasons}
  end

  defp expand(frontier, seen, reasons, opts) do
    tickets = Keyword.get(opts, :tickets, ["T1"])

    Enum.reduce(frontier, {[], seen, reasons}, fn {state, path}, acc ->
      state
      |> proposals(tickets)
      |> Enum.reduce(acc, fn proposal, {acc, seen, reasons} ->
        event = build(state, proposal, length(path) + 1)

        case WorkflowKernel.apply(state, event) do
          {:ok, next} ->
            k = key(next)

            if MapSet.member?(seen, k),
              do: {acc, seen, reasons},
              else: {[{next, path ++ [event]} | acc], MapSet.put(seen, k), reasons}

          {:error, reason} ->
            {acc, seen, MapSet.put(reasons, unwrap(reason))}
        end
      end)
    end)
  end

  defp unwrap({reason, _detail}) when is_atom(reason), do: reason
  defp unwrap(reason), do: reason

  defp proposals(state, tickets) do
    KernelWalk.candidates(%{
      state: state,
      tickets: tickets,
      counter: 0,
      sequential: false,
      terminating_period: 1,
      background_period: 1
    })
  end

  defp build(state, {type, entity_id, payload}, sequence) do
    {:ok, kind} = Event.entity_kind(type)

    %{
      "schema_version" => 1,
      "event_id" => "search-#{sequence}-#{:erlang.phash2({type, entity_id, payload})}",
      "type" => type,
      "entity_kind" => kind,
      "entity_id" => entity_id,
      "entity_revision" => revision(state, kind, entity_id),
      "sequence" => sequence,
      "payload" => payload
    }
  end

  defp revision(state, "control", _id), do: state["control"]["revision"]
  defp revision(state, "objective", id), do: get_in(state, ["objectives", id, "revision"]) || 0
  defp revision(state, _kind, id), do: get_in(state, ["tickets", id, "revision"]) || 0

  # Bookkeeping is stripped so two paths reaching the same domain content converge. Without
  # this every path is distinct and the search never merges.
  defp key(state) do
    %{
      "control" => Map.drop(state["control"], ~w(revision last_event_id)),
      "objectives" => strip(state["objectives"]),
      "tickets" => strip(state["tickets"])
    }
  end

  defp strip(collection),
    do: Map.new(collection, fn {k, v} -> {k, Map.drop(v, ~w(revision last_event_id))} end)

  @doc "Every error atom the kernel module can return, read from its source."
  def declared_reasons do
    __ENV__.file
    |> Path.join("../../../lib/pramana_foundry/workflow/kernel.ex")
    |> Path.expand()
    |> File.read!()
    |> then(&Regex.scan(~r/\{:error, :([a-z_]+)\}/, &1))
    |> Enum.map(&List.last/1)
    |> Enum.map(&String.to_atom/1)
    |> MapSet.new()
  end

  @doc "Renders a path as a readable event list, for a counterexample message."
  def render(path) do
    path
    |> Enum.map(&KernelWalk.label/1)
    |> Enum.with_index(1)
    |> Enum.map_join("\n", fn {label, i} -> "  #{i}. #{label}" end)
  end
end
