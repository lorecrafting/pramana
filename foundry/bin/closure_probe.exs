# Closure probe: which (type, key) corruptions does apply/2 ACCEPT while producing a state
# State.well_formed?/1 rejects? Each one bricks the log — the state is written, and every later
# event then fails check_state with :invalid_state.
#
# In the tree because four successive counts of this defect were wrong in the same direction
# (2, then 16, then 19, then >=20) and none could be rechecked: the script lived in a scratch
# directory and only its output was quoted. A number nobody can reproduce is a number nobody
# can challenge.
#
#   cd foundry
#   TMPDIR=/private/tmp mix run bin/closure_probe.exs                      # depth 5
#   DEPTH=7 TMPDIR=/private/tmp mix run bin/closure_probe.exs              # slow, ~2.5h
#   DEPTH=7 ONLY_TYPES=check_recorded,check_planned mix run bin/...        # scoped
#
# WARNING on ONLY_TYPES: scoping to the type a previous pass missed is how the fourth count
# went wrong. It can only confirm what you already suspect; it cannot find the next one.
#
# What this probe still cannot see, so the next person does not rediscover it the hard way:
#   - Corruptions of more than one key at once.
#   - Values nested inside a payload map, rather than a whole top-level value.
#   - Any event type the proposer never proposes at the chosen depth. At depth 7, five types
#     were never accepted uncorrupted from any seed -- integration_planned,
#     integration_settled, integration_recorded, review_recorded, reviewer_closed -- hiding
#     21 payload keys.
#   - Deep-walk seeds (KernelWalk.deep/3) are not used; only KernelSearch seeds.
#
# The float class is a control for the probe's WIRING only: Event.value?/2 refuses floats, so
# "0 floats accepted" proves the corrupted payload really reaches Event.validate/2. It does not
# witness the malformed-post-state detection, which has no control.

# KernelSearch routes through Test.Harness, so the harness has to be loaded and its counters
# allocated even though this probe never asserts through it — seeds are built by the search.
# Omitting these is how this script crashed on its first run from the tree: it was written when
# kernel_search.ex still called the kernel directly, and worked right up until it shipped.
Code.require_file("test/support/kernel_harness.ex")
Code.require_file("test/support/kernel_walk.ex")
Code.require_file("test/support/kernel_search.ex")

PramanaFoundry.Test.Harness.start()

alias PramanaFoundry.Test.{KernelSearch, KernelWalk}
alias PramanaFoundry.Workflow.Kernel, as: WorkflowKernel
alias PramanaFoundry.Workflow.Kernel.{Event, State}

# Every value class `Event.value?/2` admits, plus one it refuses (the float) as this probe's
# own control: if the float ever shows up as accepted, the probe is not testing what it says.
classes = [%{"unexpected" => [1, nil, %{}]}, %{}, "", "x", 0, -1, [], nil, true, 1.5]

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
    "event_id" => "closure3-#{type}-#{sequence}",
    "type" => type,
    "entity_kind" => kind,
    "entity_id" => entity_id,
    "entity_revision" => revision,
    "sequence" => sequence,
    "payload" => payload
  }
end

proposals = fn state ->
  KernelWalk.candidates(%{
    state: state,
    tickets: ["T1", "T2"],
    counter: 0,
    sequential: false,
    terminating_period: 1,
    background_period: 1
  })
end

depth = String.to_integer(System.get_env("DEPTH") || "5")
seeds = [State.new() | (KernelSearch.search(depth) |> Enum.map(&elem(&1, 0)))]
IO.puts("depth #{depth}, seeds: #{length(seeds)}")

only = System.get_env("ONLY_TYPES")
only = if only, do: MapSet.new(String.split(only, ",")), else: nil

{tried, accepted, broken, proposed, float_accepted} =
  Enum.reduce(seeds, {0, 0, %{}, MapSet.new(), 0}, fn state, acc ->
    sequence = (state["last_sequence"] || 0) + 1

    Enum.reduce(proposals.(state), acc, fn {type, entity_id, payload}, acc ->
      if only && not MapSet.member?(only, type) do
        acc
      else
        {t, a, b, p, f} = acc
        acc = {t, a, b, MapSet.put(p, type), f}

        Enum.reduce(Map.keys(payload), acc, fn key, acc ->
          Enum.reduce(classes, acc, fn value, {tried, accepted, broken, proposed, float_accepted} ->
            corrupted = Map.put(payload, key, value)
            event = build.(state, type, entity_id, corrupted, sequence)

            case WorkflowKernel.apply(state, event) do
              {:ok, next} ->
                float_accepted = if is_float(value), do: float_accepted + 1, else: float_accepted

                if State.well_formed?(next),
                  do: {tried + 1, accepted + 1, broken, proposed, float_accepted},
                  else:
                    {tried + 1, accepted + 1, Map.update(broken, {type, key}, 1, &(&1 + 1)),
                     proposed, float_accepted}

              {:error, _} ->
                {tried + 1, accepted, broken, proposed, float_accepted}
            end
          end)
        end)
      end
    end)
  end)

IO.puts("corruptions tried:   #{tried}")
IO.puts("accepted by apply/2: #{accepted}")
IO.puts("accepted-but-malformed: #{Enum.sum(Map.values(broken))}")
IO.puts("distinct (type, key): #{map_size(broken)}")
IO.puts("distinct event types: #{broken |> Map.keys() |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> length()}")
IO.puts("PROBE CONTROL - float payloads accepted (must be 0): #{float_accepted}")

never = MapSet.difference(MapSet.new(Event.types()), proposed)
IO.puts("\ntypes the proposer never proposed at this depth: #{Enum.join(MapSet.to_list(never), ",")}")

IO.puts("\n(type, key) pairs:")

broken
|> Enum.sort_by(fn {{t, k}, _} -> {t, k} end)
|> Enum.each(fn {{type, key}, n} -> IO.puts("  #{String.pad_leading(to_string(n), 7)}  #{type}.#{key}") end)
