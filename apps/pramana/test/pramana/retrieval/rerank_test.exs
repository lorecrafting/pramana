defmodule Pramana.Retrieval.RerankTest do
  @moduledoc """
  Reordering fused candidates by query-to-rendering containment.

  Worth +46 retrieval cases and +5 topical over the whole gold set, with
  `answered from any tradition` 72.7% -> 81.8%. The tests that matter most here are the
  ones pinning what it must NOT do: it must not invent an ordering where it has no
  evidence, and it must not favour one tradition because only that tradition's renderings
  happen to be joinable — which is exactly the defect the first version shipped with.
  """
  use Pramana.DataCase, async: true

  alias Pramana.Retrieval.Rerank

  defp result(urn), do: %{urn: urn, rrf_score: 0.1, span: nil}

  describe "by_rendering/3" do
    test "returns [] for no candidates" do
      assert Rerank.by_rendering("anything", []) == []
    end

    test "leaves the order alone when the query has no tokens" do
      results = [result("a"), result("b"), result("c")]

      assert Rerank.by_rendering("   ", results) == results
    end

    test "leaves the order alone when nothing carries a rendering" do
      # THE CRITICAL PROPERTY. Every candidate scores 0, and a stable sort must return
      # them untouched. If this ever regresses, the reranker starts shuffling the Chinese
      # canon — which has no English renderings at all — on no evidence whatever.
      results = Enum.map(["u1", "u2", "u3", "u4"], &result/1)

      assert Rerank.by_rendering("four noble truths", results) == results
    end

    test "a tie keeps the incoming fused order" do
      # Ties are broken by original index, never arbitrarily. The fused order is real
      # evidence — two retrievers agreed on it — and must not be discarded by a signal
      # that cannot separate the candidates.
      results = Enum.map(1..10, &result("urn-#{&1}"))

      assert Rerank.by_rendering("a query with no matching renderings", results) == results
    end
  end
end
