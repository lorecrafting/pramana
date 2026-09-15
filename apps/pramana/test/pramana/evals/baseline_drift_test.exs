defmodule Pramana.Evals.BaselineDriftTest do
  @moduledoc """
  A green gate is not evidence that the baseline is current.

  **This is `docs/PLAN.md` item 9, and it is the half of an invariant-#6 failure that a
  gate run cannot fix by itself.** `mix pramana.evals --gate` writes `evals/baseline.json`
  only when none exists; with one present it compares and never updates. On 2026-09-03 a
  run scoring **1,364 of 1,472 passed against a baseline recording 1,359** — so the
  five-case gain was never adopted, and a later regression back down to 1,359 would have
  been measured against the old number and passed in silence.

  The fix is not to fail the gate when the system improves: a benchmark that goes red on
  good news gets ignored, and an ignored gate is worse than none. The fix is that a pass
  **says** the ratchet has drifted, names the movements, and gives the one command that
  advances it. These tests pin that a pass cannot be quiet about it.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pramana.Evals

  defp scorecard(by_type) do
    %{
      "total" => by_type |> Map.values() |> Enum.map(& &1["hits"]) |> Enum.sum(),
      "by_type" => by_type
    }
  end

  defp type(hits, rate), do: %{"hits" => hits, "rate" => rate}

  describe "drift/2" do
    test "an identical run leaves the baseline current" do
      card = scorecard(%{"retrieval" => type(380, 85.2), "topical" => type(30, 61.2)})

      assert %{stale?: false, net: 0, types: [], gained: [], lost: []} = Evals.drift(card, card)
    end

    # THE CASE THAT ACTUALLY HAPPENED, with its real numbers.
    test "a run that scored better than the baseline reports the baseline as obsolete" do
      baseline =
        scorecard(%{"topical/chinese" => type(0, 0.0), "retrieval/pali" => type(119, 79.3)})

      current =
        scorecard(%{"topical/chinese" => type(6, 50.0), "retrieval/pali" => type(118, 78.7)})

      drift = Evals.drift(current, baseline)

      assert drift.stale?
      assert drift.net == 5
      assert drift.gained == ["topical/chinese"]

      # THE LOSS IS REPORTED BESIDE THE GAIN, always. A net figure alone is the failure
      # this project is most prone to — `docs/RULES.md` 22, 44 and 54 — and here it would
      # hide a real displacement inside an improvement.
      assert drift.lost == ["retrieval/pali"]
      assert {"topical/chinese", 0, 6} in drift.types
      assert {"retrieval/pali", 119, 118} in drift.types
    end

    test "a run that scored worse is drift too, not only a regression" do
      # Below the gate's one-case tolerance this passes, and passing quietly is exactly
      # how the ratchet loses ground it had already won.
      baseline = scorecard(%{"retrieval/tibetan" => type(30, 46.9)})
      current = scorecard(%{"retrieval/tibetan" => type(29, 45.3)})

      drift = Evals.drift(current, baseline)

      assert drift.stale?
      assert drift.net == -1
      assert drift.lost == ["retrieval/tibetan"]
    end

    test "a case type the baseline predates is not reported as movement" do
      # A new case type has nothing to have drifted FROM, and reporting it as a gain would
      # make every added gold case look like an improvement.
      baseline = scorecard(%{"retrieval" => type(380, 85.2)})
      current = scorecard(%{"retrieval" => type(380, 85.2), "provenance" => type(40, 100.0)})

      assert %{stale?: false} = Evals.drift(current, baseline)
    end
  end
end
