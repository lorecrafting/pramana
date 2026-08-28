defmodule Mix.Tasks.Pramana.Evals.CompareTest do
  @moduledoc """
  The noise rule, which is the only part of this task with judgement in it.

  A scorecard diff is arithmetic; deciding which differences mean nothing is not. The
  first version used an absolute case count alone and reported `absence 1/4 -> 3/4` — a
  fifty-point move — as within noise, which is how a tool talks someone out of a real
  finding.
  """
  use ExUnit.Case, async: true

  alias Mix.Tasks.Pramana.Evals.Compare

  defp card(rows) do
    hits = rows |> Enum.map(fn {_k, h, _s} -> h end) |> Enum.sum()
    scored = rows |> Enum.map(fn {_k, _h, s} -> s end) |> Enum.sum()

    %{
      "overall" => stat(hits, scored),
      "by_type" => %{},
      "by_type_tradition" => Map.new(rows, fn {k, h, s} -> {k, stat(h, s)} end),
      "answered_any_tradition" => %{"rate" => 81.8, "answered" => 9, "topics" => 11}
    }
  end

  defp stat(hits, scored),
    do: %{"hits" => hits, "scored" => scored, "rate" => Float.round(100 * hits / scored, 1)}

  defp write!(name, card) do
    path = Path.join(System.tmp_dir!(), "#{name}-#{System.unique_integer([:positive])}.json")
    File.write!(path, Jason.encode!(card))
    path
  end

  defp compare(before, later, argv \\ []) do
    a = write!("before", before)
    b = write!("after", later)

    ExUnit.CaptureIO.capture_io(fn -> Compare.run([a, b] ++ argv) end)
  end

  describe "the noise rule" do
    test "one case on a large row is noise" do
      out =
        compare(
          card([{"retrieval/pali", 123, 150}]),
          card([{"retrieval/pali", 122, 150}])
        )

      assert out =~ "within noise"
    end

    # The bug this test exists for. Two cases on a four-case row is fifty percentage
    # points, and calling that noise is a tool arguing a reader out of a real result.
    test "the same case count on a tiny row is NOT noise" do
      out =
        compare(
          card([{"absence", 1, 4}]),
          card([{"absence", 3, 4}])
        )

      refute out =~ "within noise"
      assert out =~ "+2 cases"
    end

    test "a movement beyond the count is reported whatever the row size" do
      out =
        compare(
          card([{"retrieval/chinese", 223, 232}]),
          card([{"retrieval/chinese", 213, 232}])
        )

      assert out =~ "REGRESSION"
    end

    # An index rebuild is not deterministic and reorders near-ties, and Tibetan is
    # near-ties by construction at 0.9727 mean pairwise cosine.
    test "--rebuilt widens the floor and says why" do
      before = card([{"retrieval/tibetan", 30, 64}])
      later = card([{"retrieval/tibetan", 32, 64}])

      assert compare(before, later) =~ "+2 cases"

      rebuilt = compare(before, later, ["--rebuilt"])
      assert rebuilt =~ "within noise"
      assert rebuilt =~ "0.9727"
    end

    # Measured by rebuilding over unchanged data: retrieval/tibetan moved four cases with
    # the corpus, the vectors and the code all byte-identical.
    test "four cases of Tibetan movement across a rebuild is still noise" do
      out =
        compare(
          card([{"retrieval/tibetan", 32, 64}]),
          card([{"retrieval/tibetan", 28, 64}]),
          ["--rebuilt"]
        )

      assert out =~ "within noise"
      refute out =~ "REGRESSION"
    end
  end

  describe "the verdict" do
    test "a gain everywhere says so" do
      out =
        compare(
          card([{"retrieval/chinese", 200, 232}, {"retrieval/pali", 120, 150}]),
          card([{"retrieval/chinese", 210, 232}, {"retrieval/pali", 130, 150}])
        )

      assert out =~ "no per-tradition regression"
    end

    # The reranker gained overall and lost Tibetan, and only the per-tradition rows caught
    # it. A summary that reported the total alone would have called that a win.
    test "a gain that costs a tradition is not reported as a win" do
      out =
        compare(
          card([{"retrieval/chinese", 200, 232}, {"retrieval/tibetan", 40, 64}]),
          card([{"retrieval/chinese", 220, 232}, {"retrieval/tibetan", 30, 64}])
        )

      assert out =~ "DOWN on: retrieval/tibetan"
      assert out =~ "not a win"
    end

    test "a row present in only one scorecard is marked rather than dropped" do
      out =
        compare(
          card([{"retrieval/chinese", 200, 232}]),
          card([{"retrieval/chinese", 200, 232}, {"retrieval/sanskrit", 5, 10}])
        )

      assert out =~ "NEW"
    end
  end
end
