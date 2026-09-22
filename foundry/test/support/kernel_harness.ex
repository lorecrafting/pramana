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
  `Kernel.apply/2`, with every accepted post-state judged by both validators.

  A refusal passes through untouched: this makes no claim about states the kernel rejected.
  """
  def apply(state, event) do
    case WorkflowKernel.apply(state, event) do
      {:ok, next} = accepted ->
        measured = State.measure(next)
        record(measured)
        violations = Enum.flat_map(measured, fn {_family, {_held?, vs}} -> vs end)

        assert State.well_formed?(next),
               "#{event["type"]} produced a state well_formed?/1 rejects"

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

  Two callers, for two different reasons. The harness's own wiring control needs the kernel's
  verdict on an event before demonstrating that the *harness* rejects it — asking here rather
  than calling the kernel directly, because a direct call was a spelling
  `r4_no_direct_apply_test.exs` could not see, which independent review caught.

  The other is the B1 totality probe, which drives deliberately malformed payloads. It exists
  because the harness found a real defect on its first full run, and that defect is not this
  change's to fix. `apply/2` is not **closed** over its own validator: starting from a valid
  payload and corrupting exactly one key, **at least 20 `(type, key)` pairs in 14 event types**
  produce
  a state `State.well_formed?/1` rejects — `ticket_admitted.{objective_id,reason,spec_revision_id,spec}`,
  `artifact_frozen.{candidate_id,sealed_generation}`, `pm_proposal_recorded.{proposal_id,operation}`,
  `ticket_amended.{spec_revision_id,spec}`, `objective_created.planning_owner_id`,
  `attempt_settled.reason_code`, `stream_sealed.last_accepted_sequence`,
  `launch_planned.attempt_id`, `check_recorded.reason_code`, `check_planned.check_id`, and
  `reason` on `ticket_blocked`,
  `ticket_parked`, `artifact_blocked` and `freeze_failed`. Each bricks the log: the next event
  sees a state its own validator refuses and returns `:invalid_state` forever.

  That count took four tries — 2, 16, 19, then >=20 — each wrong because the probe's own blind
  spot went unenumerated: all payload values hostile at once, then a single hostile value class
  (a map, which cannot break a field validated by `plain_map?`), then a single search depth,
  then a depth-7 pass scoped to the one type the previous pass had missed, which could only
  confirm what was already suspected. No bound is established; `bin/closure_probe.exs` ships so
  the next count can be checked rather than trusted.

  `kernel.ex:17`'s property 2 is unaffected — `apply/2` still returns rather than raises.
  Closure is the half nothing asserted, which is why this was invisible until the harness
  asserted it. Fixing 20-odd sites adds refusals to a gate-validated kernel, each owing a contract
  citation, an error atom, a reachability entry and a sweep — that is a candidate with its own
  review, not a rider on this one.

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
