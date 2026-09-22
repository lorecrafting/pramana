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

  alias PramanaFoundry.Test.{Harness, KernelWalk}
  # Routed through `Test.Harness` like every other call site, after an exemption for it was
  # tried and withdrawn. The exemption's argument was that the oracle is a function of the
  # successor state alone, so asserting per accepted transition and asserting over the deduped
  # reachable set are the same judgements, which `r4_exhaustive_test.exs` already does.
  #
  # Independent review showed that argument false as stated: `explore/2` runs one more
  # expansion of the deepest frontier and DISCARDS the successors, so at depth 7 some 790,000
  # accepted transitions are driven and never reach the reachable set anything asserts over.
  #
  # And the cost it traded against was never measured — the run that justified it was the one
  # with the harness recursing into itself, so what was observed was a loop, not a price.
  #
  # Measured: unrouted workflow suite 113.7s and 116.2s; routed 139.6s and 117.4s. The first
  # routed run alone reads as "+23 seconds", and that is how it was first written down here —
  # a one-sample difference recorded as a cost, which is the same mistake as the exemption it
  # was defending. Across both samples the cost is somewhere between noise and ~20%. What is
  # NOT noisy is the coverage: 253,383 judgements to 2,351,004 — though those are judgements,
  # not distinct transitions. Two modules run this search at depth 7 from empty
  # (`r4_exhaustive_test`, `r4_guard_reachability_test`) and a third walks depth 4 under
  # `identity_key` (`r4_congruence_test`), so roughly half of that figure is the same
  # transition judged again; distinct transitions go from roughly 250,000 to 1,052,864, and
  # distinct states judged to 268,856. Still a 4.2x gain, stated as what it is.
  alias PramanaFoundry.Workflow.Kernel.{Event, State}

  @default_depth 6

  @doc """
  Every state reachable within `depth` accepted events, each with the path that reached it.

  Returns `[{state, path}]`, `path` oldest first, including the initial state with an
  empty path. Each level expands only what the previous produced.

  Options: `:tickets`, and `:from` to begin from a state other than `State.new/0`.
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
  # `:from` seeds the search with a hand-built state instead of the empty one. Depth is a
  # cost choice, and the cost is paid on the way IN: the review and integration rows sit
  # roughly a dozen events from empty, so a bound affordable enough to run reaches them
  # with almost no states to spare - 45 with an attempt in `reviewing` and none at all with
  # a recorded verdict, at depth 8 over 238,000 states. Every reachability claim about a
  # guard past that point was therefore being made on a sample of nearly nothing, which is
  # indistinguishable from a proof until someone counts. Seeding from a driven state spends
  # the whole budget where the question is.
  defp explore(depth, opts) do
    initial = Keyword.get(opts, :from) || State.new()
    key_fun = Keyword.get(opts, :key, &key/1)

    # Durable sequence is strictly increasing across the whole log, so proposals must
    # continue the seed's numbering rather than restart at 1. Without this every proposal
    # from a seeded state is refused as `out_of_order_event` and the search returns the
    # seed alone - which it did, reporting zero of every predicate asked of it and looking
    # exactly like a proof that nothing is reachable.
    offset = Keyword.get(opts, :from) |> then(&if(&1, do: &1["last_sequence"] || 0, else: 0))
    opts = Keyword.put(opts, :sequence_offset, offset)

    {frontier, states, seen, reasons} =
      Enum.reduce(
        1..depth,
        {[{initial, []}], [{initial, []}], MapSet.new([key_fun.(initial)]), MapSet.new()},
        fn _level, {frontier, states, seen, reasons} ->
          {next, seen, reasons} = expand(frontier, seen, reasons, opts, key_fun)
          {next, states ++ next, seen, reasons}
        end
      )

    # The deepest frontier is reached but never expanded, so nothing has yet proposed from
    # it. Its refusals are as real as any other's, and omitting them made two guards look
    # unreachable that are not. One more proposal pass, discarding the states.
    {_ignored, _seen, reasons} = expand(frontier, seen, reasons, opts, key_fun)

    {states, reasons}
  end

  defp expand(frontier, seen, reasons, opts, key_fun) do
    tickets = Keyword.get(opts, :tickets, ["T1"])

    Enum.reduce(frontier, {[], seen, reasons}, fn {state, path}, acc ->
      state
      |> proposals(tickets)
      |> Enum.reduce(acc, fn proposal, {acc, seen, reasons} ->
        event = build(state, proposal, length(path) + 1 + Keyword.get(opts, :sequence_offset, 0))

        case Harness.apply(state, event) do
          {:ok, next} ->
            k = key_fun.(next)

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

  @doc """
  The canonical identity two paths must share to be merged: domain content with per-path
  bookkeeping stripped.

  Public because the quotient it defines is a proof obligation, not an implementation
  detail. `r4_congruence_test.exs` enumerates under `&identity_key/1` and groups by this,
  which is the only way to obtain two states the search itself would have merged.
  """
  def key(state) do
    %{
      "control" => Map.drop(state["control"], ~w(revision last_event_id)),
      "objectives" => strip(state["objectives"]),
      "tickets" => strip(state["tickets"])
    }
  end

  defp strip(collection),
    do: Map.new(collection, fn {k, v} -> {k, Map.drop(v, ~w(revision last_event_id))} end)

  @doc """
  A key that merges nothing. Enumerating under it yields the tree `key/1` quotients, which
  is what a congruence check needs on both sides of the comparison.
  """
  def identity_key(state), do: state

  @doc """
  Every proposal's outcome from `state`: `{proposal, :accepted, successor_key}` or
  `{proposal, :refused, reason}`.

  Each event is built against `state`'s own revision and next sequence, because those are
  exactly the fields `key/1` strips — comparing two key-equal states means comparing what
  each does with its own bookkeeping, not forcing one state's bookkeeping onto the other.
  """
  def outcomes(state, tickets \\ ["T1"]) do
    sequence = (state["last_sequence"] || 0) + 1

    state
    |> proposals(tickets)
    |> Enum.map(fn proposal ->
      case Harness.apply(state, build(state, proposal, sequence)) do
        {:ok, next} -> {proposal, :accepted, key(next)}
        {:error, reason} -> {proposal, :refused, unwrap(reason)}
      end
    end)
  end

  @doc "Every error atom the kernel module can return, read from its source."
  def declared_reasons do
    __ENV__.file
    |> Path.join("../../../lib/pramana_foundry/workflow/kernel.ex")
    |> Path.expand()
    |> File.read!()
    |> reasons_in()
  end

  # Two spellings declare a refusal, and scanning for only the first is how this claimed to
  # inventory the declared set for three reviews while missing `:unknown_entity_kind` at
  # kernel.ex:80 entirely.
  @reason_spellings [
    # Returned directly.
    ~r/\{:error, :([a-z_]+)\}/,
    # Lifted from a `:error`-returning call, piped or as the second argument. The atom must
    # be the last thing before the closing paren, which is what keeps the definition
    # clauses - `ok_or({:ok, value}, _reason)` and `ok_or(:error, reason)` - out: they
    # mention no reason, they receive one.
    ~r/ok_or\(.*:([a-z_]+)\)/
  ]

  # Separate from the file read so a fixture can be fed to it; the red control lives in
  # r4_guard_reachability_test.
  @doc "Every error atom declared in `source`, in either spelling."
  def reasons_in(source) do
    @reason_spellings
    |> Enum.flat_map(&(&1 |> Regex.scan(source) |> Enum.map(fn [_, atom] -> atom end)))
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
