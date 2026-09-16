defmodule Pramana.Retrieval.HybridPolicyTest do
  use ExUnit.Case, async: true
  alias Pramana.Retrieval.Hybrid

  describe "fuse/2 — pure RRF" do
    test "a document ranked first by both retrievers wins" do
      lexical = ["a", "b", "c"]
      semantic = ["a", "c", "b"]

      assert [{"a", _} | _] = Hybrid.fuse([lexical, semantic])
    end

    test "consensus beats a single retriever's top hit" do
      # "b" is never first, but both agree on it; "a" and "z" are each first once.
      lexical = ["a", "b"]
      semantic = ["z", "b"]

      assert [{"b", _} | _] = Hybrid.fuse([lexical, semantic])
    end

    test "scores follow 1/(k + rank)" do
      assert [{"a", score}] = Hybrid.fuse([["a"]], 60)
      assert_in_delta score, 1 / 61, 1.0e-9
    end

    test "a single ranking passes through in order" do
      assert Hybrid.fuse([["a", "b", "c"]]) |> Enum.map(&elem(&1, 0)) == ["a", "b", "c"]
    end

    test "no rankings yields nothing" do
      assert Hybrid.fuse([]) == []
    end

    # 60 is convention, not a measurement — every other retrieval constant here earned its
    # value from `evals/` and this one never has. It is an option so a sweep can move it.
    test "k is what decides how much a top rank is worth" do
      # "solo" is one retriever's top hit and the other has never heard of it. "agreed"
      # is fourth on both lists. Small k makes rank 1 dominate and the solo hit wins;
      # large k flattens rank differences until fusion is close to a vote, and agreement
      # wins. That trade is the whole content of the constant, and 60 was inherited from
      # convention rather than measured here.
      rankings = [
        ["solo", "p", "q", "agreed"],
        ["r", "s", "t", "agreed"]
      ]

      # Comparing the two against EACH OTHER rather than against the head of the list:
      # the second retriever's own rank-1 ties with "solo" at small k, and which of them
      # sorts first is not what this test is about.
      rank_of = fn fused, urn -> Enum.find_index(fused, &(elem(&1, 0) == urn)) end

      sharp = Hybrid.fuse(rankings, 1)
      flat = Hybrid.fuse(rankings, 1000)

      assert rank_of.(sharp, "solo") < rank_of.(sharp, "agreed")
      assert rank_of.(flat, "agreed") < rank_of.(flat, "solo")
    end
  end

  describe "confidence/1 — what the bands mean" do
    test "a match as close as answerable queries usually are is strong" do
      assert %{band: "strong", top_similarity: 0.81} = Hybrid.confidence([{"a", 0.81}])
    end

    test "the overlap band, where answerable and unanswerable queries both live, is weak" do
      assert %{band: "weak"} = Hybrid.confidence([{"a", 0.72}])
      assert %{band: "weak", note: note} = Hybrid.confidence([{"a", 0.7068}])
      assert note =~ "suggestions, not answers"
    end

    test "below every answerable query measured, it says so plainly" do
      assert %{band: "no_close_match", note: note} = Hybrid.confidence([{"a", 0.61}])
      assert note =~ "nearest neighbours of a question with no answer here"
    end

    test "the best match decides, not the order the retriever returned" do
      assert %{top_similarity: 0.9} = Hybrid.confidence([{"a", 0.4}, {"b", 0.9}])
    end

    # nil, not "no_close_match": the semantic arm not RUNNING is a different fact from it
    # running and finding nothing close, and conflating them would report a corpus gap
    # where the truth is that no model was loaded.
    test "no semantic arm reports nothing rather than no confidence" do
      assert Hybrid.confidence([]) == nil
    end

    # The combination fired for 6 of 10 unanswerable queries and 0 of 46 answerable ones,
    # measured through the shipped path. It is a one-way signal and the note says so.
    test "no lexical support plus a non-strong band reads as probably absent" do
      assert %{note: note, lexical_support: 0} = Hybrid.confidence([{"a", 0.71}], 0)

      assert note =~ "Nothing matches the characters typed"
      assert note =~ "one-way"
    end

    # A paraphrase has no literal match and IS answerable — 眾生皆能成佛 appears nowhere in
    # the corpus as a string. It collects n-gram support in the hybrid arm and lands
    # `strong`, so it must not be read as absent even at zero phrase matches.
    test "a strong band is never read as absent, whatever the lexical support" do
      assert %{note: note} = Hybrid.confidence([{"a", 0.82}], 0)

      refute note =~ "Nothing matches the characters typed"
      assert note =~ "as close as answerable queries usually are"
    end

    test "lexical support suppresses the combined reading" do
      assert %{note: note} = Hybrid.confidence([{"a", 0.71}], 4)

      refute note =~ "Nothing matches the characters typed"
    end
  end

  test "candidate budgets honor per-arm overrides, shared depth, limits and caps" do
    for {opts, expected} <- [
          {[limit: 2], %{limit: 2, lexical: 6, semantic: 12, rerank: 10}},
          {[limit: 2, semantic_depth: 120], %{limit: 2, lexical: 6, semantic: 120, rerank: 10}},
          {[limit: 2, lexical_depth: 120], %{limit: 2, lexical: 120, semantic: 12, rerank: 10}},
          {[limit: 2, depth: 30], %{limit: 2, lexical: 30, semantic: 30, rerank: 10}},
          {[limit: 2, depth: 30, semantic_depth: 120],
           %{limit: 2, lexical: 30, semantic: 120, rerank: 10}},
          {[limit: 2, depth: 1], %{limit: 2, lexical: 2, semantic: 2, rerank: 10}},
          {[limit: 100], %{limit: 100, lexical: 200, semantic: 200, rerank: 200}},
          {[limit: 2, depth: 10_000, rerank: false],
           %{limit: 2, lexical: 200, semantic: 200, rerank: 2}},
          {[limit: 2, rerank_multiplier: 8], %{limit: 2, lexical: 6, semantic: 12, rerank: 16}}
        ] do
      assert Hybrid.candidate_depths(opts) == expected, inspect(opts)
    end
  end
end
