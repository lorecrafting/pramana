defmodule Pramana.Evals.ScoreMapTest do
  @moduledoc """
  The baseline records what each case did, not only how many hit.

  On 2026-08-29 a run scored retrieval 368/446 against a baseline's 370/446 and **there
  was no way to learn which two cases moved** — the only route to an answer was re-running
  all 446 for twenty minutes. `summarize/2` has carried per-case outcomes since then;
  `to_map/1` did not, so the baseline on disk still held rates and the ratchet could still
  say *something regressed* and never *what*.
  """
  use ExUnit.Case, async: true

  alias Pramana.Evals.Score

  defp result(id, type, outcome) do
    %{
      case: %{
        id: id,
        type: type,
        tradition: nil,
        topic: nil,
        adversarial: false
      },
      outcome: outcome
    }
  end

  test "the serialised map carries every case's outcome" do
    map =
      [
        result("a-1", :retrieval, {:hit, %{}}),
        result("a-2", :retrieval, {:miss, %{}}),
        result("a-3", :topical, {:stale, %{}})
      ]
      |> Score.summarize(1000)
      |> Score.to_map()

    assert map["cases"] == %{"a-1" => "hit", "a-2" => "miss", "a-3" => "stale"}
  end

  # A map rather than a list, because the only question ever asked of it is "what did this
  # case do last time" and a list makes that a scan of 1,472 entries per lookup.
  test "it is keyed by case id" do
    map =
      [result("only", :retrieval, {:hit, %{}})]
      |> Score.summarize(1)
      |> Score.to_map()

    assert Map.keys(map["cases"]) == ["only"]
  end

  # THE SUBSTITUTION A RATE CANNOT SEE. One case flipping to a hit and another to a miss
  # leaves every rate identical, which `docs/PLAN.md` audit item 7 names and had no way to
  # check. With per-case detail it is a diff.
  test "two cases can swap outcomes without moving any rate" do
    before_map =
      [result("x", :retrieval, {:hit, %{}}), result("y", :retrieval, {:miss, %{}})]
      |> Score.summarize(1)
      |> Score.to_map()

    after_map =
      [result("x", :retrieval, {:miss, %{}}), result("y", :retrieval, {:hit, %{}})]
      |> Score.summarize(1)
      |> Score.to_map()

    assert before_map["by_type"] == after_map["by_type"]
    refute before_map["cases"] == after_map["cases"]
  end
end
