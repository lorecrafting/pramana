defmodule PramanaFoundry.Projections.BenchmarkTest do
  use ExUnit.Case, async: false

  alias PramanaFoundry.Projections.Benchmark

  @tag :benchmark_artifact
  test "saved benchmark artifact retains its recorded acceptance values (not a fresh measurement)" do
    assert_benchmark_result(saved_result())
  end

  @tag :python_tiktoken_recompute
  test "optional tiktoken recomputation matches the recorded benchmark" do
    cases = fixture_cases()
    first = Benchmark.run(cases)

    assert first == Benchmark.run(cases)
    assert first == saved_result()
    assert_benchmark_result(first)
  end

  defp assert_benchmark_result(result) do
    assert result["production_selection"] == "json"

    assert result["production_reductions_percent"] !=
             result["independent_rederived_reductions_percent"]

    assert result["eligible"]

    assert Enum.all?(result["production_reductions_percent"], fn {_provider, reduction} ->
             reduction >= result["target"]["regression_floor_percent"]
           end)

    for benchmark_case <- result["cases"], {_arm, arm} <- benchmark_case["arms"] do
      assert arm["decode_ok"]
      assert arm["exact_round_trip"]
      assert arm["repeated_variance"] == %{"codex" => 0, "claude" => 0}
      assert arm["null_run_variance"] == 0
    end

    assert Enum.all?(result["cases"], &(&1["required_field_coverage_percent"] == 100.0))
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
