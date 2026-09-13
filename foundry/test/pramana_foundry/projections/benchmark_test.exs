defmodule PramanaFoundry.Projections.BenchmarkTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Projections.Benchmark

  test "all benchmark arms decode exactly and production reduction keeps registered margin" do
    cases = fixture_cases()
    first = Benchmark.run(cases)
    second = Benchmark.run(cases)

    assert first == second
    assert first == saved_result()
    assert first["production_selection"] == "json"

    assert first["production_reductions_percent"] !=
             first["independent_rederived_reductions_percent"]

    assert first["eligible"]

    assert Enum.all?(first["production_reductions_percent"], fn {_provider, reduction} ->
             reduction >= first["target"]["regression_floor_percent"]
           end)

    for benchmark_case <- first["cases"], {_arm, result} <- benchmark_case["arms"] do
      assert result["decode_ok"]
      assert result["exact_round_trip"]
      assert result["repeated_variance"] == %{"codex" => 0, "claude" => 0}
      assert result["null_run_variance"] == 0
    end

    assert Enum.all?(first["cases"], &(&1["required_field_coverage_percent"] == 100.0))
  end

  defp fixture_cases do
    Path.expand("../../fixtures/projections/representative-v1.json", __DIR__)
    |> File.read!()
    |> :json.decode()
  end

  defp saved_result do
    Path.expand("../../fixtures/projections/benchmark-v1.json", __DIR__)
    |> File.read!()
    |> :json.decode()
  end
end
