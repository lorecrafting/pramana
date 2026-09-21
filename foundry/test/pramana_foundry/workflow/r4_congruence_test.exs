Code.require_file("../../support/kernel_walk.ex", __DIR__)
Code.require_file("../../support/kernel_search.ex", __DIR__)

defmodule PramanaFoundry.Workflow.R4CongruenceTest do
  @moduledoc """
  The proof obligation the bounded search's quotient rests on.

  `KernelSearch` merges two states when they share `key/1` — domain content with revision
  counters, `last_event_id` and `last_sequence` stripped. Merging is what makes the search
  affordable: without it no two paths converge and the enumeration degenerates into a tree.
  It is also unproved, and if the key merges two states that behave differently the search
  silently stops exploring a branch.

  That matters beyond coverage. Every claim of the form "N states, M holding the
  precondition, 0 violating" that this subcommit recorded is computed over the quotient,
  not over the reachable set. If the quotient is unsound those denominators are overstated,
  and rule 2 in `EVIDENCE-TOOLS.md` — every claim of absence reports its denominator —
  becomes a number without a meaning. This test is what makes them load-bearing.

  The obligation, for states `s` and `t` with `key(s) == key(t)`:

    * the same proposals are offered from each,
    * each proposal is accepted by both or refused by both, with the same error atom, and
    * where accepted, the two successors share a canonical key.

  Enumeration runs under `identity_key/1`, which merges nothing. That is the only way to
  obtain two states the search itself would have merged: `search/2` under `key/1` returns
  one representative per class by construction, so grouping its output would produce
  singletons and compare nothing — rule 1's vacuous mechanism, arrived at by using the
  quotient to check the quotient.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.Test.KernelSearch

  # Depth 4 costs about two seconds and already merges 371 classes. Depth 5 was run once
  # while writing this — 13,553 comparisons, 0 violations, 22 seconds — and is not in the
  # suite: a 22-second permanent acceptance step for a check that found nothing new at
  # depth 4 is the mutation sweep's cost mistake in miniature. Raise this if the key changes.
  @depth 4

  setup_all do
    %{states: KernelSearch.search(@depth, key: &KernelSearch.identity_key/1)}
  end

  # Each member is compared against its class representative rather than against every
  # other member: equality of outcomes is transitive, so n-1 comparisons per class prove
  # what n(n-1)/2 would, and at depth 5 that is the difference between 13,553 comparisons
  # and 170,349.
  defp compare(states, key_fun) do
    states
    |> Enum.group_by(fn {state, _path} -> key_fun.(state) end)
    |> Enum.reduce({0, []}, fn {_key, [{representative, path} | rest]}, {compared, broken} ->
      base = KernelSearch.outcomes(representative)

      Enum.reduce(rest, {compared, broken}, fn {state, other_path}, {compared, broken} ->
        case KernelSearch.outcomes(state) do
          ^base -> {compared + 1, broken}
          divergent -> {compared + 1, [{path, other_path, base, divergent} | broken]}
        end
      end)
    end)
  end

  defp describe_break({path, other_path, base, divergent}) do
    """
    two states the search would have merged do not agree:
      path A: #{KernelSearch.render(path)}
      path B: #{KernelSearch.render(other_path)}
      only A: #{inspect(base -- divergent, limit: 3)}
      only B: #{inspect(divergent -- base, limit: 3)}
    """
  end

  test "states the canonical key merges behave identically", %{states: states} do
    {compared, broken} = compare(states, &KernelSearch.key/1)

    classes = states |> Enum.group_by(fn {s, _p} -> KernelSearch.key(s) end) |> map_size()

    # Rule 2: states checked, states holding the precondition, violations. The precondition
    # here is having a sibling at all — a class of one merges nothing and witnesses nothing,
    # so `compared` and not `length(states)` is the denominator this claim rests on.
    assert compared > 1_000,
           "only #{compared} merges to check across #{classes} classes at depth #{@depth}; " <>
             "the quotient collapsed or the proposer shrank, and 0 violations would mean nothing"

    assert broken == [],
           "#{length(broken)} of #{compared} merges are unsound:\n" <>
             Enum.map_join(Enum.take(broken, 2), "\n", &describe_break/1)
  end

  # Rule 1: the mechanism ships with a fixture that must fail. Five mechanisms in this
  # subcommit produced confident, clean, entirely vacuous results on their first run.
  # Dropping `phase` is the smallest loss that should matter: two tickets alike in
  # everything but phase accept different events.
  test "a key that loses a distinguishing field is caught", %{states: states} do
    lossy = fn state ->
      update_in(KernelSearch.key(state), ["tickets"], fn tickets ->
        Map.new(tickets, fn {id, ticket} -> {id, Map.drop(ticket, ["phase"])} end)
      end)
    end

    {compared, broken} = compare(states, lossy)

    assert compared > 1_000, "the control must compare as much as the real check"

    assert broken != [],
           "a key that forgets ticket phase merged #{compared} pairs without one " <>
             "disagreeing, so this test cannot detect an unsound key"
  end
end
