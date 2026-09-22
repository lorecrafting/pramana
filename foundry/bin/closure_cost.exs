# What kernel property 6 costs: one extra State.well_formed?/1 call per ACCEPTED transition, on
# top of the one every event already pays on input. Same seeds as bin/closure_probe.exs, one
# legitimate proposal set per seed, apply/2 timed against well_formed?/1 over its accepted outputs.
#
# In the tree because the number was quoted in a design decision, and a number from a scratch
# script cannot be challenged. Run it rather than quoting it.
#
# What it measures NOW: the kernel it times already performs the post-check (property 6 landed
# at 253d9467), so this times a SECOND well_formed?/1 over outputs against an apply/2 that has
# already paid for the first. The ratio is the check's share of the post-property-6 kernel, not
# what the change added to the kernel before it; the true before/after is the pre-change run
# recorded in IMPLEMENTATION-LOG (348 / 2,053 ms, 17%), which this reproduces within noise
# because the check is a small share either way. Independent review of 253d9467 asked for this
# paragraph so the number is not quoted as the incremental cost forever.
#
#   cd foundry
#   TMPDIR=/private/tmp mix run bin/closure_cost.exs
Code.require_file("test/support/kernel_harness.ex")
Code.require_file("test/support/kernel_walk.ex")
Code.require_file("test/support/kernel_search.ex")

PramanaFoundry.Test.Harness.start()

alias PramanaFoundry.Test.{KernelSearch, KernelWalk}
alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
alias PramanaFoundry.Workflow.Kernel.{Event, State}

depth = String.to_integer(System.get_env("DEPTH") || "5")
seeds = KernelSearch.search(depth) |> Enum.map(&elem(&1, 0))
IO.puts("depth #{depth}, seeds: #{length(seeds)}")

build = fn state, type, entity_id, payload, sequence ->
  {:ok, kind} = Event.entity_kind(type)

  revision =
    case kind do
      "control" -> state["control"]["revision"]
      "objective" -> get_in(state, ["objectives", entity_id, "revision"]) || 0
      _ -> get_in(state, ["tickets", entity_id, "revision"]) || 0
    end

  %{
    "schema_version" => 1,
    "event_id" => "cost-#{type}-#{sequence}",
    "type" => type,
    "entity_kind" => kind,
    "entity_id" => entity_id,
    "entity_revision" => revision,
    "sequence" => sequence,
    "payload" => payload
  }
end

pairs =
  Enum.flat_map(seeds, fn state ->
    sequence = (state["last_sequence"] || 0) + 1

    KernelWalk.candidates(%{
      state: state,
      tickets: ["T1", "T2"],
      counter: 0,
      sequential: false,
      terminating_period: 1,
      background_period: 1
    })
    |> Enum.map(fn {type, id, payload} -> {state, build.(state, type, id, payload, sequence)} end)
  end)

IO.puts("(state, event) pairs: #{length(pairs)}")

{apply_us, results} = :timer.tc(fn -> Enum.map(pairs, fn {s, e} -> WorkflowKernel.apply(s, e) end) end)
accepted = for {:ok, next} <- results, do: next
IO.puts("apply/2: #{length(pairs)} calls, #{div(apply_us, 1000)} ms, #{length(accepted)} accepted")

{wf_us, _} = :timer.tc(fn -> Enum.each(accepted, &State.well_formed?/1) end)
IO.puts("well_formed?/1 over the #{length(accepted)} accepted outputs: #{div(wf_us, 1000)} ms")
IO.puts("post-check cost as a share of apply/2 total: #{Float.round(wf_us / apply_us * 100, 1)}%")

sizes = Enum.map(accepted, &map_size(&1["tickets"]))
IO.puts("tickets per accepted state: max #{Enum.max(sizes)}, mean #{Float.round(Enum.sum(sizes) / length(sizes), 2)}")
