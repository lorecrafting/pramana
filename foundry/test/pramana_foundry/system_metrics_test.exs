defmodule PramanaFoundry.SystemMetricsTest do
  @moduledoc """
  The tests that would have caught a function raising on every call it ever made.

  `SystemMetrics.system/0` computed `ets_table_count` as
  `length(:erlang.system_info(:ets_data) |> elem(0))`. There is no `:ets_data` system info
  item, so the call raised `ArgumentError` unconditionally, from the day it was written.
  `Improver.log_metrics/1` calls it on the cycle path with no guard, so the Improver crashed
  on every cycle and never once wrote a `metrics_snapshot` — and `CLI.main(["metrics"])`
  failed the same way.

  Nothing in the suite mentioned this module. That is the whole reason a function which
  raises 100% of the time passed a gate with 900-odd tests: the gate proves the suite passes,
  not that the suite looks at anything.
  """
  use ExUnit.Case, async: true

  alias PramanaFoundry.SystemMetrics

  # Every key the moduledoc promises. Listed explicitly rather than derived from the result,
  # because `Map.keys(result) == Map.keys(result)` is the vacuous form of this test.
  @system_keys ~w(
    total_memory_bytes processes_memory_bytes ets_memory_bytes atom_memory_bytes
    code_memory_bytes binary_memory_bytes atom_count atom_limit process_count
    process_limit run_queue_length uptime_seconds ets_table_count
  )

  describe "system/0" do
    test "returns a snapshot rather than raising" do
      assert %{} = SystemMetrics.system()
    end

    test "carries every documented key" do
      keys = SystemMetrics.system() |> Map.keys() |> Enum.sort()

      assert keys == Enum.sort(@system_keys)
    end

    # The generalisation, and the half that matters. `ets_table_count` was broken twice over:
    # the system info item does not exist, AND `length(elem(_, 0))` is not a count even if it
    # had. Asserting the one key would have caught the first defect only; asserting that every
    # value is an integer catches the shape, which is what the next malformed expression over
    # this vocabulary will get wrong. Rule 4 — one assertion over the whole vocabulary.
    test "every value is an integer" do
      for {key, value} <- SystemMetrics.system() do
        assert is_integer(value), "#{key} is #{inspect(value)}, not an integer"
      end
    end

    # Independent computation, so the key is pinned to the truth rather than to "an integer".
    # `:ets.all/0` and `:erlang.system_info(:ets_count)` are different mechanisms for the same
    # fact; a count that satisfies the integer check above but reports nonsense fails here.
    test "ets_table_count agrees with an independent count of the tables" do
      assert SystemMetrics.system()["ets_table_count"] == length(:ets.all())
    end

    test "counts that the VM may report as {count, limit} are unwrapped" do
      system = SystemMetrics.system()

      assert system["atom_count"] <= system["atom_limit"]
      assert system["process_count"] <= system["process_limit"]
    end
  end

  # The other two readers on the Improver's cycle path. Neither was exercised either, and a
  # raise in either one abandons the cycle at exactly the same point.
  describe "the rest of the cycle-path snapshot" do
    test "per_process/0 returns a map rather than raising" do
      assert %{} = SystemMetrics.per_process()
    end

    test "agent_servers/0 reports a count that matches the agents it lists" do
      agents = SystemMetrics.agent_servers()

      assert is_integer(agents["count"])
      assert is_list(agents["agents"])

      assert agents["count"] == length(agents["agents"]),
             "the count and the list disagree: #{inspect(agents)}"
    end
  end
end
