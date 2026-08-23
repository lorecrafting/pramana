defmodule Pramana.Retrieval.HybridTest do
  @moduledoc """
  RRF fusion, and the option-validation rule that came out of a real bug: `division:`
  was silently ignored by the lexical retriever while the semantic one honoured it, so
  hybrid results were contaminated with works from outside the requested division —
  and still *looked* filtered, because half the pipeline had applied it.
  """
  use Pramana.DataCase, async: false

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Retrieval.Hybrid
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Semantic

  import Ecto.Query

  defp load!(work_id, lines, provenance) do
    body =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">#{provenance[:title]}</title>
    <author>x</author></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")
    {:ok, _} = Loader.load(ir, source: "cbeta", witness: "T", provenance: provenance)

    text_id = Repo.one!(from t in Text, where: t.work_id == ^work_id, select: t.id)
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)
    text_id
  end

  setup do
    load!("T0001", ["如是我聞一時佛住", "王舍城耆闍崛山中"],
      title: "阿含經",
      division: "阿含部",
      division_en: "Āgama",
      composition_origin: "indic",
      text_role: "root"
    )

    load!("T1992", ["如是我聞一時佛住", "禪門公案語錄"],
      title: "禪錄",
      division: "諸宗部",
      division_en: "Sectarian works",
      composition_origin: "chinese",
      text_role: "treatise"
    )

    :ok
  end

  describe "option validation — the bug that motivated it" do
    test "an unknown option raises rather than being silently dropped" do
      # `divison` (typo) previously disabled filtering with no signal at all.
      assert_raise ArgumentError, ~r/unknown search option/, fn ->
        Lexical.search("如是我聞", divison: "阿含部")
      end

      assert_raise ArgumentError, ~r/unknown search option/, fn ->
        Semantic.search("如是我聞", divison: "阿含部")
      end
    end

    test "the error names the offending key" do
      error = assert_raise ArgumentError, fn -> Lexical.search("x", nonsense: 1) end
      assert Exception.message(error) =~ ":nonsense"
    end

    test "known options are accepted" do
      assert {:ok, _} = Lexical.search("如是我聞", division: "阿含部", origin: "indic", limit: 2)
    end
  end

  describe "division filter reaches the lexical retriever" do
    test "restricts to the requested division" do
      {:ok, all} = Lexical.search("如是我聞")
      {:ok, agama} = Lexical.search("如是我聞", division: "阿含部")

      assert all.total == 2
      assert agama.total == 1
      assert hd(agama.results).span.provenance.division == "阿含部"
    end

    test "provenance carries the division so a caller can check it" do
      {:ok, %{results: [hit]}} = Lexical.search("如是我聞", division: "阿含部")

      assert hit.span.provenance.division == "阿含部"
      assert hit.span.provenance.division_en == "Āgama"
    end
  end

  describe "vector-stage options do not reach the lexical retriever" do
    # Each of these means something only to `Semantic`, and `Lexical` raises on an option
    # it does not know. `:per_tradition` was added to `Semantic` and not to Hybrid's drop
    # list, which made it unusable through the only path anything ships on: every caller
    # — the MCP tools, the eval harness — goes through `Hybrid`.
    for opt <- [
          [vector_kinds: ["source"]],
          [vector_lang: "en"],
          [balance: :tradition],
          [per_tradition: true],
          [coverage: false]
        ] do
      test "#{inspect(opt)} survives a hybrid search" do
        assert {:ok, %{retrievers: ["lexical"]}} =
                 Hybrid.search("如是我聞", unquote(opt) ++ [division: "阿含部"])
      end
    end
  end

  describe "a limit above the maximum is refused, not silently shrunk" do
    # This cost a published claim. A probe asked `Semantic` for `limit: 500`, was given
    # 200, and the finding was written up as "30 of 41 misses absent from the top 500"
    # when it meant the top 200 — see docs/STATUS.md #19. Same category as a
    # silently-ignored filter, same answer.
    test "Semantic raises and names the maximum" do
      error =
        assert_raise ArgumentError, fn -> Semantic.search("如是我聞", limit: 500) end

      assert Exception.message(error) =~ "500"
      assert Exception.message(error) =~ "200"
    end

    test "Lexical raises too, so the rule does not depend on which retriever you reach" do
      assert_raise ArgumentError, ~r/exceeds the maximum/, fn ->
        Lexical.search("如是我聞", limit: 500)
      end
    end

    test "a limit at the maximum is accepted" do
      assert {:ok, _} = Lexical.search("如是我聞", limit: 200)
    end

    # The regression this guards: Hybrid over-fetches at `limit * 3`, so before `depth`
    # was clamped, any limit above 66 asked the retrievers for more than they allow and
    # the new check turned a correct caller's search into an ArgumentError.
    test "Hybrid at the maximum limit still searches, because depth is its own heuristic" do
      assert {:ok, %{total: total}} = Hybrid.search("如是我聞", limit: 200)
      assert total > 0
    end

    test "Hybrid at a limit whose triple exceeds the maximum still searches" do
      assert {:ok, _} = Hybrid.search("如是我聞", limit: 100)
    end
  end

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
  end

  describe "search/2 degrades honestly" do
    test "without a serving it runs lexical only and SAYS so" do
      {:ok, result} = Hybrid.search("如是我聞", division: "阿含部")

      assert result.retrievers == ["lexical"]
      assert result.total > 0
    end

    test "reports embedding coverage so partial data is never mistaken for a small canon" do
      {:ok, result} = Hybrid.search("如是我聞")

      assert result.coverage.total > 0
      assert result.coverage.embedded == 0
      assert result.coverage.percent == 0.0
    end

    test "coverage is computed by DEFAULT — skipping it must be asked for" do
      {:ok, result} = Hybrid.search("如是我聞")

      refute result.coverage == :not_computed
    end

    test "coverage: false says :not_computed rather than reporting an empty corpus" do
      {:ok, result} = Hybrid.search("如是我聞", coverage: false)

      # NOT nil, and NOT a zeroed map. This field exists so an empty result cannot be
      # read as a small canon; `%{embedded: 0}` here would tell the reader the precise
      # falsehood the field was added to prevent.
      assert result.coverage == :not_computed
      assert result.total > 0
    end

    test "names the bake the results came from" do
      {:ok, _} = Pramana.Bake.record(%{"test" => true})
      {:ok, result} = Hybrid.search("如是我聞")

      assert is_binary(result.bake_id)
    end

    test "lexical hits are mapped to their containing chunk" do
      {:ok, result} = Hybrid.search("如是我聞", division: "阿含部")

      # Chunk URNs are ranges of real anchors, and must still resolve.
      for hit <- result.results do
        assert {:ok, _} = Pramana.Corpus.resolve(hit.urn)
        assert hit.span
      end
    end

    test "rejects an empty query" do
      assert {:error, :empty_query} = Hybrid.search("   ")
    end
  end
end
