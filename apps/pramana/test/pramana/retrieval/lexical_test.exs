defmodule Pramana.Retrieval.LexicalTest do
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Loader
  alias Pramana.Guard
  alias Pramana.Normalize.CBETA
  alias Pramana.Retrieval.Lexical

  defp load!(body_lines, provenance) do
    lines =
      body_lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt>
      <title level="m" xml:lang="zh-Hant">#{provenance[:title] || "測試經"}</title>
      <author>#{provenance[:author] || "譯者"}</author>
    </titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{lines}</body></text></TEI>
    """

    {:ok, ir} =
      CBETA.normalize(xml,
        work_id: provenance[:work_id],
        canon: "T",
        volume: provenance[:volume] || 9,
        number: "0262"
      )

    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)
    :ok
  end

  setup do
    load!(
      [
        "如是我聞：一時，佛住王舍城耆闍崛山中",
        "與大比丘眾萬二千人俱，皆是阿羅漢",
        "除般若波羅蜜，以是功德比前功德",
        "阿㝹樓馱、劫賓那、薄拘羅"
      ],
      work_id: "T0262",
      composition_origin: "indic",
      text_role: "translation",
      title: "妙法蓮華經"
    )

    :ok
  end

  describe "phrase mode" do
    test "finds an exact contiguous substring" do
      assert {:ok, %{mode: :phrase, results: [r]}} = Lexical.search("如是我聞")
      assert r.span.content =~ "如是我聞"
      assert r.matched_terms == ["如是我聞"]
    end

    test "finds rare-glyph transliterated Sanskrit no dictionary knows" do
      # This is the case that justifies pg_bigm over dictionary tokenization.
      assert {:ok, %{mode: :phrase, results: [r]}} = Lexical.search("阿㝹樓馱")
      assert r.span.content =~ "阿㝹樓馱"
    end

    test "returns nothing rather than guessing when the phrase is absent" do
      assert {:ok, %{results: results}} = Lexical.search("此語必不存在於經中", mode: :phrase)
      assert results == []
    end
  end

  describe "ngrams/2" do
    test "produces overlapping windows" do
      assert Lexical.ngrams("般若波羅蜜") == ["般若波", "若波羅", "波羅蜜"]
    end

    test "uses a short query whole" do
      assert Lexical.ngrams("空") == ["空"]
      assert Lexical.ngrams("般若") == ["般若"]
    end

    test "is vocabulary-independent — the window is there regardless of any lexicon" do
      assert "波羅蜜" in Lexical.ngrams("般若波羅蜜多心經")
    end
  end

  describe "Tibetan windows syllables, not graphemes" do
    test "the tsheg is the unit, because the edition prints it" do
      # A Chinese character is a morpheme so a 3-character window means something. A
      # Tibetan grapheme is a letter stack, and windowing by grapheme cuts across the
      # tsheg into fragments of no linguistic standing.
      assert Lexical.ngrams("སྟོང་པ་ཉིད") == ["སྟོང་པ", "པ་ཉིད"]
    end

    test "the particle window that matched 89.6% of the corpus is gone" do
      # `་པ་` — the particle པ between two separators — occurred in 1,211,774 of the
      # 1,352,471 Tibetan segments, against 2.63% for སྟོང་པ་ཉིད itself. `:ngram` ranks by
      # how many distinct query terms a passage contains, so that one window outvoted
      # every meaningful one.
      grams = Lexical.ngrams("སྟོང་པ་ཉིད")

      refute "་པ་" in grams
      assert Enum.all?(grams, &(not String.starts_with?(&1, "་")))
      assert Enum.all?(grams, &(not String.ends_with?(&1, "་")))
    end

    test "transliterated Sanskrit survives, which is why botok is not used" do
      # The same reason jieba is not the Chinese fallback: a trained segmenter shatters
      # names it was never taught. Splitting on a printed delimiter cannot.
      assert Lexical.ngrams("པྲ་ཛྙཱ་ཝརྨ") == ["པྲ་ཛྙཱ", "ཛྙཱ་ཝརྨ"]
    end

    test "a query at or under the window is used whole" do
      assert Lexical.ngrams("སྟོང་པ") == ["སྟོང་པ"]
      assert Lexical.ngrams("ཆོས") == ["ཆོས"]
    end

    test "a window never crosses a shad" do
      # The window is rejoined with a tsheg and searched as a substring, so spanning the
      # clause break would fabricate `རྣམས་སྟོང` — a string the edition does not print,
      # which cannot match and still takes a vote in the ranking.
      grams = Lexical.ngrams("ཆོས་རྣམས། སྟོང་པ")

      assert grams == ["ཆོས་རྣམས", "སྟོང་པ"]
      refute "རྣམས་སྟོང" in grams
    end

    test "other scripts are untouched" do
      assert Lexical.ngrams("般若波羅蜜") == ["般若波", "若波羅", "波羅蜜"]
    end
  end

  describe "auto mode falls back to ngrams" do
    test "finds a passage via a window when the whole phrase is absent" do
      # 般若波羅蜜多心經 is not in this text, but 般若波羅蜜 is.
      assert {:ok, %{mode: :ngram, results: [top | _]}} = Lexical.search("般若波羅蜜多心經")
      assert top.span.content =~ "般若波羅蜜"
    end

    test "ranks by how many windows a passage contains" do
      assert {:ok, %{mode: :ngram, results: results}} =
               Lexical.search("耆闍崛山中與大比丘眾")

      scores = Enum.map(results, & &1.score.terms_matched)
      assert scores == Enum.sort(scores, :desc), "results must be ranked by coverage"
      assert hd(results).score.terms_matched > 1
    end
  end

  describe "jieba is unreliable here — regression record" do
    # Not a bug to fix, a measurement to remember. If jieba ever learns this
    # vocabulary this test will fail, and that would be good news worth noticing.
    test "shatters Buddhist transliterations into single characters" do
      assert Lexical.terms("耆闍崛山") == ["耆", "闍", "崛", "山"]
      assert "波羅蜜" not in Lexical.terms("般若波羅蜜多心經")
    end

    test "drops grammatical particles but keeps single-character content words" do
      terms = Lexical.terms("佛之教法")
      assert "佛" in terms
      refute "之" in terms
    end
  end

  describe "provenance filters compose as SQL predicates" do
    test "matching origin returns hits" do
      assert {:ok, %{total: n}} = Lexical.search("如是我聞", origin: "indic")
      assert n == 1
    end

    test "non-matching origin returns none" do
      assert {:ok, %{total: 0}} = Lexical.search("如是我聞", origin: "japanese")
    end

    test "role filters independently of origin" do
      assert {:ok, %{total: 1}} = Lexical.search("如是我聞", role: "translation")
      assert {:ok, %{total: 0}} = Lexical.search("如是我聞", role: "commentary")
    end

    test "exclude_origin removes a tradition" do
      assert {:ok, %{total: 0}} = Lexical.search("如是我聞", exclude_origin: "indic")
      assert {:ok, %{total: 1}} = Lexical.search("如是我聞", exclude_origin: "japanese")
    end

    test "juan filter narrows to a fascicle" do
      assert {:ok, %{total: 1}} = Lexical.search("如是我聞", juan: 1)
      assert {:ok, %{total: 0}} = Lexical.search("如是我聞", juan: 2)
    end
  end

  describe "results are guard-verifiable — one span shape" do
    test "a search hit can be verified without a second code path" do
      {:ok, %{results: [r]}} = Lexical.search("如是我聞")

      assert Guard.verify(r.span.urn, r.span.content)
      refute Guard.verify(r.span.urn, r.span.content <> "偽")
    end

    test "every hit carries offsets, sha256, and provenance" do
      {:ok, %{results: [r]}} = Lexical.search("如是我聞")

      assert is_integer(r.span.byte_start)
      assert r.span.sha256 == :crypto.hash(:sha256, r.span.content) |> Base.encode16(case: :lower)
      assert r.span.provenance.composition_origin == "indic"
    end
  end

  describe "input handling" do
    test "rejects an empty query" do
      assert {:error, :empty_query} = Lexical.search("")
      assert {:error, :empty_query} = Lexical.search("   ")
    end

    test "rejects a non-string query" do
      assert {:error, :bad_query} = Lexical.search(nil)
    end

    test "treats LIKE metacharacters as literal text" do
      # A query is user input. Unescaped, "%" would match every segment.
      assert {:ok, %{total: 0}} = Lexical.search("%", mode: :phrase)
      assert {:ok, %{total: 0}} = Lexical.search("_", mode: :phrase)
      assert {:ok, %{total: 0}} = Lexical.search("如是%聞", mode: :phrase)
    end

    test "respects and caps limit" do
      assert {:ok, %{results: results}} = Lexical.search("，", limit: 2)
      assert length(results) <= 2
    end
  end
end
