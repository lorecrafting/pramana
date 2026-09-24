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

    text_id = Repo.one!(from(t in Text, where: t.work_id == ^work_id, select: t.id))
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

  # `Semantic` has had `source_id` since it was written and `Lexical` never did, so
  # `Hybrid.search(q, source_id: "cbeta")` RAISED — the correct failure, and still meant
  # no caller could restrict a search to one publication at all. `witness_id` is new to
  # both, and became a real question the day CBETA held three collections: the Taishō, the
  # 卍續藏 and the 嘉興藏 are one source and three canons.
  describe "source and collection filters reach BOTH retrievers" do
    test "a witness filter narrows the results rather than being accepted and ignored" do
      {:ok, all} = Hybrid.search("如是我聞", limit: 20)
      {:ok, filtered} = Hybrid.search("如是我聞", limit: 20, witness_id: "T")

      assert all.total > 0
      assert filtered.total > 0

      witnesses =
        filtered.results |> Enum.map(& &1.span.provenance.witness) |> Enum.uniq()

      assert witnesses == ["T"]
    end

    test "a source filter does the same" do
      {:ok, result} = Hybrid.search("如是我聞", limit: 20, source_id: "cbeta")

      sources = result.results |> Enum.map(& &1.span.provenance.source) |> Enum.uniq()
      assert sources == ["cbeta"]
    end

    test "a filter matching nothing returns nothing, not everything" do
      {:ok, result} = Hybrid.search("如是我聞", limit: 20, witness_id: "no-such-witness")

      assert result.total == 0
    end

    test "both retrievers accept them, so neither can silently drop one" do
      assert :source_id in Lexical.known_opts()
      assert :witness_id in Lexical.known_opts()

      assert {:ok, _} = Lexical.search("如是我聞", witness_id: "T", source_id: "cbeta")
      assert %{results: _} = Semantic.search_vector(List.duplicate(0.0, 1024), witness_id: "T")
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
    # when it meant the top 200 — see docs/HISTORY.md #19. Same category as a
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

    # Hybrid hands the retrievers `depth`, never the caller's `limit`, so the check added
    # to Lexical and Semantic did not cover this path: `limit: 500` clamped depth to 200,
    # returned at most 200, and said nothing.
    test "Hybrid refuses an over-limit itself, rather than relying on the retrievers" do
      assert_raise ArgumentError, ~r/exceeds the maximum/, fn ->
        Hybrid.search("如是我聞", limit: 500)
      end
    end
  end

  # Both are hybrid-level options, so both must be dropped before either retriever sees
  # them — `Lexical` and `Semantic` RAISE on an unknown option, deliberately, and that is
  # how `per_tradition` once became reachable only by calling `Semantic` directly.
  # The semantic arm returns its k nearest neighbours regardless of distance, so it cannot
  # say "I have nothing". Two fixes were measured before either was built: the gap
  # statistic does not separate (6 of 8 unanswerable queries have gaps inside the
  # answerable range) and a hard threshold at 0.75 costs ~45 retrieval cases to gain 1
  # absence case. So the number is REPORTED.
  describe "the swept knobs are hybrid-level options" do
    test "rrf_k does not reach the retrievers" do
      assert {:ok, %{total: total}} = Hybrid.search("如是我聞", rrf_k: 5)
      assert total > 0
    end

    test "rerank_multiplier does not reach the retrievers" do
      assert {:ok, %{total: total}} = Hybrid.search("如是我聞", rerank_multiplier: 8)
      assert total > 0
    end

    test "both together, as a sweep would pass them" do
      assert {:ok, %{total: total}} =
               Hybrid.search("如是我聞", rrf_k: 30, rerank_multiplier: 3, limit: 5)

      assert total > 0
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

  # THE CLASS, NOT THE INSTANCE. Hybrid fans one option list out to two retrievers that
  # each raise on an option they do not know. It used to do that with hand-maintained
  # exclusion lists, and both `:translation_coverage` and `:translators` were missing from
  # them — so a semantic-only option crashed the whole search with `unknown search
  # option(s)`, and the per-arm model comparison it was added for produced nothing.
  #
  # Asserting on the routing rather than on a list of names: whatever either retriever
  # declares, hybrid must be able to hand it every option it accepts.
  describe "option routing between the two retrievers" do
    # A value that is legal for each option, so the search is exercised rather than
    # rejected at validation. Only semantic-only options are listed — the ones the lexical
    # arm has never heard of, which are exactly the ones that used to crash it.
    @semantic_only_values %{
      vector_kinds: ["source"],
      vector_lang: "en",
      balance: true,
      per_tradition: true,
      translators: ["model:mitra"],
      translation_coverage: 0.5,
      # A chunk id that exists nowhere, because this case is about routing rather than
      # results: what must not happen is the lexical arm being handed it and raising.
      translation_chunks: [1],
      # Serving parameters. Found by this test rather than by reading the list — they
      # would have crashed the lexical arm exactly as `:translators` did.
      sequence_length: 320,
      batch_size: 8
    }

    test "no semantic-only option can crash the lexical arm" do
      declared = Semantic.known_opts() -- Lexical.known_opts()

      # If Semantic gains an option, it must be added here — the point of the test is that
      # somebody notices, which is precisely what the old exclusion lists did not force.
      untested = declared -- (Map.keys(@semantic_only_values) ++ [:serving])

      assert untested == [],
             "semantic-only options with no routing case: #{inspect(untested)}"

      for {opt, value} <- @semantic_only_values do
        assert {:ok, _} =
                 Hybrid.search("mindfulness", [{opt, value}, {:limit, 5}, {:serving, nil}]),
               "#{opt} reached the lexical arm and crashed the search"
      end
    end
  end

  test "a lexical-only search carries no confidence signal" do
    {:ok, result} = Hybrid.search("如是我聞", lexical_only: true)

    assert result.retrievers == ["lexical"]
    assert result.semantic_confidence == nil
  end

  test "a populated candidate pool is cut to limit after fusion" do
    load!("T0003", ["如是我聞一時佛住", "另一部論典之文"],
      title: "third candidate",
      division: "阿含部",
      composition_origin: "indic",
      text_role: "root"
    )

    assert {:ok, all} = Hybrid.search("如是我聞", limit: 20, lexical_only: true, rerank: false)
    assert all.total == 3

    for opts <- [[depth: 1], [depth: 30], [lexical_depth: 1], [semantic_depth: 120]] do
      assert {:ok, result} =
               Hybrid.search("如是我聞", opts ++ [limit: 2, lexical_only: true, rerank: false])

      assert result.total == 2
      assert length(Enum.uniq(Enum.map(result.results, & &1.urn))) == 2
    end
  end
end
