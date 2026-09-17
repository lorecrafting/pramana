defmodule PramanaFoundry.Assessor.EvaluatorTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Assessor.Evaluator

  test "offline evaluator compares ordering without changing the candidate set" do
    cases = [
      %{
        "baseline_order" => ["a", "b", "c"],
        "assessor_order" => ["b", "a", "c"],
        "relevant_ids" => ["b"],
        "observed" => %{
          "input_tokens" => 100,
          "assessor_calls" => 1,
          "latency_ms" => 20,
          "operator_effort_ms" => 5,
          "rework_events" => 0
        }
      }
    ]

    assert {:ok, result} = Evaluator.compare(cases, 1)
    assert result["baseline"]["important_context_misses_at_k"] == 1
    assert result["assessor"]["important_context_misses_at_k"] == 0
    assert result["baseline"]["reads_to_cover_all_relevant"] == 2
    assert result["assessor"]["reads_to_cover_all_relevant"] == 1
    assert result["baseline"]["unnecessary_reads_before_full_relevance"] == 1
    assert result["assessor"]["unnecessary_reads_before_full_relevance"] == 0
    assert result["observed"]["input_tokens"] == %{"known_total" => 100, "unknown_cases" => 0}
  end

  test "unknown observed values remain explicit instead of becoming zero" do
    cases = [
      %{
        "baseline_order" => ["a"],
        "assessor_order" => ["a"],
        "relevant_ids" => [],
        "observed" => %{"assessor_calls" => 0}
      }
    ]

    assert {:ok, result} = Evaluator.compare(cases, 1)
    assert result["observed"]["assessor_calls"] == %{"known_total" => 0, "unknown_cases" => 0}
    assert result["observed"]["input_tokens"] == %{"known_total" => 0, "unknown_cases" => 1}
  end

  test "candidate-set changes and unknown gold ids are refused" do
    assert {:error, :invalid_evaluation_cases} =
             Evaluator.compare(
               [
                 %{
                   "baseline_order" => ["a", "b"],
                   "assessor_order" => ["a", "c"],
                   "relevant_ids" => ["a"]
                 }
               ],
               1
             )

    assert {:error, :invalid_evaluation_cases} =
             Evaluator.compare(
               [
                 %{
                   "baseline_order" => ["a"],
                   "assessor_order" => ["a"],
                   "relevant_ids" => ["missing"]
                 }
               ],
               1
             )
  end

  test "offline runner script remains valid Elixir source" do
    path = Path.expand("../../../bin/assessor_eval.exs", __DIR__)
    assert {:ok, _ast} = path |> File.read!() |> Code.string_to_quoted()
  end
end
