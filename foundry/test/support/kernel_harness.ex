defmodule PramanaFoundry.Test.Harness do
  @moduledoc """
  The single route from a test to `Kernel.apply/2`, so that the relational oracle judges
  every accepted transition the suite drives rather than only the ones the bounded search
  reaches (EV-3).

  Why a wrapper and not a hook in the four `drive/2` helpers: there are 93 `apply/2` call
  sites under `test/`, and four of them route through a `drive`. Asserting inside `drive`
  would cover a small fraction of the suite while reporting a denominator that sounds like
  all of it — rule 2's failure mode rather than its remedy.

  Why not `apply/2` itself: having the reducer refuse a post-state that violates an
  invariant is a behaviour change on a gate-validated kernel and needs its own review. This
  asserts; it does not refuse. The deferred form is recorded in `State`'s module doc.

  `r4_no_direct_apply_test.exs` is what keeps this true as subcommits 2–5 add tests: a
  wrapper nothing is obliged to use decays into a wrapper nothing uses.
  """

  import ExUnit.Assertions

  alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
  alias PramanaFoundry.Workflow.Kernel.State

  @counters {__MODULE__, :counters}

  @doc """
  `Kernel.apply/2`, with every accepted post-state judged by the relational oracle.

  A refusal passes through untouched: this makes no claim about states the kernel rejected.

  Shape is not asserted here any more. It was, and that assertion found the closure defect —
  but once the kernel refuses a malformed post-state itself (property 6, `:malformed_post_state`)
  an accepted state is well-formed by construction, and `assert State.well_formed?(next)` had
  no red control anyone could build: the fixture that used to turn it red is now refused
  before it gets here. Rule 1 says a mechanism with no red control is deleted, not kept.
  The kernel's guard has its own, in `r4_exhaustive_test.exs`.
  """
  def apply(state, event) do
    case WorkflowKernel.apply(state, event) do
      {:ok, next} = accepted ->
        measured = State.measure(next)
        record(measured)
        violations = Enum.flat_map(measured, fn {_family, {_held?, vs}} -> vs end)

        assert violations == [],
               "#{event["type"]} produced a state that violates a contract relation:\n  " <>
                 Enum.join(violations, "\n  ")

        accepted

      refused ->
        refused
    end
  end

  @doc """
  `Kernel.apply/2` with **no assertion and no counting**, and the only sanctioned way for a
  test to reach the kernel unjudged. `r4_no_direct_apply_test.exs` pins its exact call sites,
  so widening the set is a deliberate edit to that test rather than a convenience.

  Two callers. The harness's relational wiring control needs the kernel's verdict on an event
  before demonstrating that the *harness* rejects it — asking here rather than calling the
  kernel directly, because a direct call was a spelling `r4_no_direct_apply_test.exs` could
  not see, which independent review caught. The other is the B1 totality probe, which drives
  deliberately hostile payloads and wants only ok-or-error; a hostile payload the kernel
  accepts may still break a contract relation the harness would assert on, and totality is
  not a claim about relations.

  This hatch used to quarantine the closure defect: `apply/2` was not **closed** over its own
  validator, and a handler copying a payload value into state produced, for at least 20
  `(type, key)` pairs, a state `State.well_formed?/1` rejected and `:invalid_state` then refused
  forever. Closed by property 6, `require_well_formed/1` in `kernel.ex` — the post-state is validated and refused with
  `:malformed_post_state`. `bin/closure_probe.exs` is the regression: it must report
  `accepted-but-malformed: 0` with its bound line unchanged, and the four counts that preceded
  it (2, 16, 19, >=20 — each wrong in the same direction) are recorded in
  `docs/fr-08/fr08b-closure-candidate-design.md`.
  """
  def apply_unchecked(state, event), do: WorkflowKernel.apply(state, event)

  # ── Denominators (rule 2) ──────────────────────────────────────────────────────────

  @doc "Allocates the shared counters. Called once, from `test_helper.exs`."
  def start do
    :persistent_term.put(
      @counters,
      :counters.new(1 + 2 * length(State.invariant_families()), [:write_concurrency])
    )
  end

  defp record(measured) do
    counters = :persistent_term.get(@counters)
    :counters.add(counters, 1, 1)

    Enum.each(measured, fn {family, {held?, violations}} ->
      if held? do
        {held_index, violated_index} = indices(family)
        :counters.add(counters, held_index, 1)
        if violations != [], do: :counters.add(counters, violated_index, 1)
      end
    end)
  end

  defp indices(family) do
    position = Enum.find_index(State.invariant_families(), &(&1 == family))
    {2 + 2 * position, 3 + 2 * position}
  end

  @doc """
  The per-family table, as `{accepted_transitions, [{family, held, violated}]}`.

  A family with `held` at zero is reporting zero violations out of zero witnesses. That is
  not hypothetical — `receipt_custody` is 0 of 58,324 over the bounded search, which is
  EV-3's own argument for why this table has to be printed rather than assumed.
  """
  def report do
    counters = :persistent_term.get(@counters)

    families =
      for family <- State.invariant_families() do
        {held_index, violated_index} = indices(family)
        {family, :counters.get(counters, held_index), :counters.get(counters, violated_index)}
      end

    {:counters.get(counters, 1), families}
  end

  @doc "Prints `report/0`. Registered as an `ExUnit.after_suite/1` callback."
  def print_report do
    {accepted, families} = report()

    IO.puts("\nRelational oracle over #{accepted} accepted transitions:\n")

    # The violated column is expected to be nonzero on a green suite: the harness's own red
    # control drives one violating transition on purpose. A table of all zeros would mean the
    # counters never fired, which is the condition rule 1 exists to make visible.
    IO.puts("  held  violated  family")

    for {family, held, violated} <- families do
      flag = if held == 0, do: "   <- vacuous: no witness", else: ""

      IO.puts(
        "  #{String.pad_leading(to_string(held), 4)}  #{String.pad_leading(to_string(violated), 8)}  #{family}#{flag}"
      )
    end
  end
end
