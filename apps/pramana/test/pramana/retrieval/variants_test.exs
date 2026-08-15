defmodule Pramana.Retrieval.VariantsTest do
  @moduledoc """
  Variant Han characters, expanded at query time.

  The hole this closes is not the one the task originally assumed. CBETA is internally
  consistent — 說 appears 412,524 times and 説 never. The gap is between the reader's
  keyboard and the corpus: someone typing simplified 众生 or Japanese 説法 gets **zero**
  results where the traditional form gets 132,626, and nothing signals the miss.

  The invariant these tests protect is that this stays a QUERY-side expansion. Stored
  text must remain byte-identical to the witness, because which Han form an edition
  prints is evidence about its transmission, not noise.
  """
  use ExUnit.Case, async: true

  doctest Pramana.Retrieval.Variants

  alias Pramana.Retrieval.Variants

  describe "variants_of/1" do
    test "groups the orthographic traditions of one character" do
      assert Variants.variants_of("說") == ["說", "説", "说"]
      assert Variants.variants_of("眾") == ["众", "眾", "衆"]
      assert Variants.variants_of("戶") == ["戶", "户", "戸"]
    end

    test "a character with no variants returns itself, so callers need no special case" do
      assert Variants.variants_of("佛") == ["佛"]
    end

    test "membership is symmetric — any form finds the whole class" do
      # A reader may type any of them; all must reach the same set.
      for form <- ~w(說 説 说) do
        assert Enum.sort(Variants.variants_of(form)) == Enum.sort(~w(說 説 说))
      end
    end

    test "does NOT expand across kSemanticVariant" do
      # 眞/真 is filed under kSemanticVariant upstream, which mixes true orthographic
      # variants with genuinely different words. Excluding that field costs this pair
      # and buys precision — a known, documented trade (priv/variants/PROVENANCE.md).
      refute "眞" in Variants.variants_of("真")
    end
  end

  describe "expand/2" do
    test "produces every orthographic form of a query" do
      {forms, _} = Variants.expand("眾生")

      assert "眾生" in forms
      assert "众生" in forms
      assert "衆生" in forms
    end

    test "always includes the query as written" do
      # Expansion can only ADD recall; it must never lose the form actually typed.
      for query <- ["眾生", "佛說", "無有變易", "abc"] do
        {forms, _} = Variants.expand(query)
        assert query in forms, "lost the original form of #{query}"
      end
    end

    test "reports which characters were expanded" do
      # A hit on a different form should be explicable, not surprising.
      {_forms, meta} = Variants.expand("眾生")

      assert meta.expanded == %{"眾" => ["众", "眾", "衆"]}
      # `applied` is added by the retriever wrapper, not here — this reports the count.
      assert meta.forms == 3
    end

    test "a query with no variant characters expands to itself alone" do
      {forms, meta} = Variants.expand("佛")

      assert forms == ["佛"]
      assert meta.expanded == %{}
    end

    test "caps the combinatorial explosion and says that it did" do
      # Every variant character multiplies the form count. Six characters with three
      # forms each is 729 LIKE patterns — slower than the search it is meant to help.
      long = "說說說說說說"
      {forms, meta} = Variants.expand(long, max_forms: 8)

      assert length(forms) <= 8
      assert meta.truncated
      assert long in forms
    end

    test "does not claim truncation when it did not truncate" do
      {_forms, meta} = Variants.expand("眾生")
      refute meta.truncated
    end

    test "handles an empty query without raising" do
      assert {[""], _} = Variants.expand("")
    end
  end
end
