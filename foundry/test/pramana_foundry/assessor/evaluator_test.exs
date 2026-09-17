defmodule PramanaFoundry.Assessor.EvaluatorTest do
  use ExUnit.Case, async: true

  alias PramanaFoundry.Assessor.Evaluator

  test "offline evaluator compares ordering and operational measurements by arm" do
    cases = [
      %{
        "baseline_order" => ["a", "b", "c"],
        "assessor_order" => ["b", "a", "c"],
        "relevant_ids" => ["b"],
        "observed" => %{
          "baseline" => %{
            "input_tokens" => 300,
            "assessor_calls" => 0,
            "latency_ms" => 50,
            "operator_effort_ms" => 25,
            "rework_events" => 1
          },
          "assessor" => %{
            "input_tokens" => 100,
            "assessor_calls" => 1,
            "latency_ms" => 20,
            "operator_effort_ms" => 5,
            "rework_events" => 0
          }
        }
      }
    ]

    assert {:ok, result} = Evaluator.compare(cases, 1)
    assert result["schema_version"] == 2
    assert result["baseline"]["important_context_misses_at_k"] == 1
    assert result["assessor"]["important_context_misses_at_k"] == 0
    assert result["baseline"]["reads_to_cover_all_relevant"] == 2
    assert result["assessor"]["reads_to_cover_all_relevant"] == 1
    assert result["baseline"]["unnecessary_reads_before_full_relevance"] == 1
    assert result["assessor"]["unnecessary_reads_before_full_relevance"] == 0

    assert result["observed"]["baseline"]["input_tokens"] ==
             %{"known_total" => 300, "unknown_cases" => 0}

    assert result["observed"]["assessor"]["input_tokens"] ==
             %{"known_total" => 100, "unknown_cases" => 0}
  end

  test "unknown observed values remain explicit per arm instead of becoming zero" do
    cases = [
      %{
        "baseline_order" => ["a"],
        "assessor_order" => ["a"],
        "relevant_ids" => [],
        "observed" => %{
          "baseline" => %{"assessor_calls" => 0},
          "assessor" => %{"assessor_calls" => 1}
        }
      }
    ]

    assert {:ok, result} = Evaluator.compare(cases, 1)

    assert result["observed"]["baseline"]["assessor_calls"] ==
             %{"known_total" => 0, "unknown_cases" => 0}

    assert result["observed"]["assessor"]["assessor_calls"] ==
             %{"known_total" => 1, "unknown_cases" => 0}

    assert result["observed"]["assessor"]["input_tokens"] ==
             %{"known_total" => 0, "unknown_cases" => 1}
  end

  test "candidate-set changes, unknown gold ids, and ambiguous observed arms are refused" do
    base = %{
      "baseline_order" => ["a", "b"],
      "assessor_order" => ["a", "b"],
      "relevant_ids" => ["a"],
      "observed" => %{"baseline" => %{}, "assessor" => %{}}
    }

    assert {:error, :invalid_evaluation_cases} =
             Evaluator.compare([%{base | "assessor_order" => ["a", "c"]}], 1)

    assert {:error, :invalid_evaluation_cases} =
             Evaluator.compare([%{base | "relevant_ids" => ["missing"]}], 1)

    assert {:error, :invalid_evaluation_cases} =
             Evaluator.compare([%{base | "observed" => %{"assessor" => %{}}}], 1)
  end

  test "offline runner script remains valid Elixir source" do
    path = Path.expand("../../../bin/assessor_eval.exs", __DIR__)
    assert {:ok, _ast} = path |> File.read!() |> Code.string_to_quoted()
  end
end
