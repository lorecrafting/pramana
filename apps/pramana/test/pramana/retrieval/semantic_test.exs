defmodule Pramana.Retrieval.SemanticTest do
  @moduledoc """
  Vector search, tested through `search_vector/2` so no test ever loads a 2.2 GB model.

  The filtered path is the one that matters here. Postgres plans a filtered vector query
  as an HNSW index scan **followed by** the join and the provenance filter, and HNSW
  yields only `ef_search` candidates — so filtering them down to a division holding a few
  percent of the corpus discards nearly all of them. On the real 299,317-chunk corpus a
  request for 10 results in 阿含部 came back with 5, and narrower filters came back empty,
  while the matching text sat in the table embedded and correct.

  That is the worst shape of bug this project can have: an empty result reads as *"the
  canon does not say this"* when the truth is *"the index never looked there"*, and it
  strikes the provenance filters that are the whole point.

  A test database is too small for HNSW to be chosen at all, so these tests cannot
  reproduce the truncation. What they CAN pin is that the filtered path executes, applies
  the filter, and returns everything that matches — so if the iterative-scan setting is
  removed the query still has to be correct here, and the corpus-scale check in
  `docs/GPU_RUNBOOK.md` covers the rest.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Text
  alias Pramana.Embed
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Retrieval.Semantic

  @dims 1024

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

  # A deterministic unit vector that leans on one axis, so "nearest" is predictable
  # without a model.
  defp unit_vector(axis) do
    for i <- 0..(@dims - 1), do: if(i == axis, do: 1.0, else: 0.0)
  end

  # Vectors live on `chunk_vectors`, not on the chunk, so a chunk can carry its own text
  # AND a translation of it.
  defp embed_chunks!(text_id, axis, opts \\ []) do
    kind = Keyword.get(opts, :kind, "source")
    lang = Keyword.get(opts, :lang, "lzh")
    translator = Keyword.get(opts, :translator)
    now = DateTime.utc_now()

    rows =
      Repo.all(
        from c in Chunk, where: c.text_id == ^text_id, select: %{id: c.id, content: c.content}
      )
      |> Enum.map(fn chunk ->
        content = Keyword.get(opts, :content, chunk.content)

        %{
          chunk_id: chunk.id,
          kind: kind,
          lang: lang,
          translator_id: translator,
          content: content,
          content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
          embedding: Pgvector.new(unit_vector(axis)),
          embedding_model: Embed.model(),
          embedded_at: now,
          inserted_at: now,
          updated_at: now
        }
      end)

    Repo.insert_all(ChunkVector, rows)
  end

  setup do
    agama =
      load!(
        "T0001",
        ["如是我聞一時佛住", "王舍城耆闍崛山中", "與大比丘眾俱行", "爾時世尊告諸比丘"],
        title: "阿含經",
        division: "阿含部",
        division_en: "Āgama",
        composition_origin: "indic",
        text_role: "root"
      )

    chan =
      load!(
        "T1992",
        ["禪門公案語錄一", "禪門公案語錄二", "禪門公案語錄三", "禪門公案語錄四"],
        title: "禪錄",
        division: "諸宗部",
        division_en: "Sectarian works",
        composition_origin: "chinese",
        text_role: "treatise"
      )

    # The Chan text sits closer to the probe vector, so an unfiltered search prefers it.
    # That is what makes the filtered assertions meaningful: the filter has to overcome
    # a ranking that would otherwise exclude 阿含部 entirely.
    embed_chunks!(chan, 0)
    embed_chunks!(agama, 1)

    {:ok, probe: unit_vector(0)}
  end

  describe "unfiltered search" do
    test "returns the nearest chunks, ranked", %{probe: probe} do
      %{results: results} = Semantic.search_vector(probe, limit: 10)

      # 阿含部 chunks to 2 windows and 諸宗部 to 1 under max_chars: 30.
      assert length(results) == 3
      assert hd(results).span.provenance.division == "諸宗部"
    end

    test "similarity is monotonically decreasing", %{probe: probe} do
      %{results: results} = Semantic.search_vector(probe, limit: 10)
      sims = Enum.map(results, & &1.similarity)

      assert sims == Enum.sort(sims, :desc)
    end

    test "reports the model that produced the vectors", %{probe: probe} do
      assert %{model: model} = Semantic.search_vector(probe, limit: 1)
      assert model == Embed.model()
    end
  end

  describe "filtered search — the iterative-scan path" do
    test "returns every match in the division, not the globally-nearest few", %{probe: probe} do
      # 阿含部 is the FAR text from this probe. Under a plain post-filtered index scan
      # this is exactly the case that comes back short or empty.
      %{results: results} = Semantic.search_vector(probe, limit: 10, division: "阿含部")

      assert length(results) == 2
      assert Enum.all?(results, &(&1.span.provenance.division == "阿含部"))
    end

    test "each provenance filter actually restricts the result set", %{probe: probe} do
      for {opts, division} <- [
            {[division: "阿含部"], "阿含部"},
            {[origin: "indic"], "阿含部"},
            {[role: "root"], "阿含部"},
            {[exclude_origin: "chinese"], "阿含部"},
            {[division: "諸宗部"], "諸宗部"},
            {[role: "treatise"], "諸宗部"}
          ] do
        %{results: results} = Semantic.search_vector(probe, [limit: 10] ++ opts)

        assert results != [], "#{inspect(opts)} returned nothing"

        assert Enum.all?(results, &(&1.span.provenance.division == division)),
               "#{inspect(opts)} leaked results from another division"
      end
    end

    test "work_id restricts to one work", %{probe: probe} do
      %{results: results} = Semantic.search_vector(probe, limit: 10, work_id: "T0001")

      assert length(results) == 2
      assert Enum.all?(results, &(&1.span.provenance.work_id == "T0001"))
    end

    test "ranking survives relaxed_order", %{probe: probe} do
      # `relaxed_order` may hand back rows slightly out of distance order, so the module
      # re-sorts. If that sort is dropped, this catches it.
      %{results: results} = Semantic.search_vector(probe, limit: 10, origin: "indic")
      sims = Enum.map(results, & &1.similarity)

      assert sims == Enum.sort(sims, :desc)
    end

    test "a filter matching nothing returns empty rather than erroring", %{probe: probe} do
      assert %{results: []} = Semantic.search_vector(probe, limit: 10, division: "律部")
    end
  end

  describe "chunks without a vector" do
    test "are never returned", %{probe: probe} do
      Repo.update_all(ChunkVector, set: [embedding: nil, embedding_model: nil])

      assert %{results: []} = Semantic.search_vector(probe, limit: 10)
    end

    test "vectors from another model are excluded, since mixing them corrupts ranking",
         %{probe: probe} do
      Repo.update_all(ChunkVector, set: [embedding_model: "some/other-model"])

      assert %{results: []} = Semantic.search_vector(probe, limit: 10)
    end
  end

  describe "coverage/1" do
    test "reports what fraction of the corpus is vector-searchable" do
      assert %{total: 3, embedded: 3, percent: 100.0} = Semantic.coverage()
    end

    test "counts partial coverage honestly" do
      text_id = Repo.one!(from t in Text, where: t.work_id == "T0001", select: t.id)

      Repo.update_all(
        from(v in ChunkVector,
          join: c in Chunk,
          on: c.id == v.chunk_id,
          where: c.text_id == ^text_id
        ),
        set: [embedding: nil]
      )

      # T0001 owns 2 of the 3 chunks, so clearing it leaves 1 of 3.
      assert %{total: 3, embedded: 1, percent: 33.3} = Semantic.coverage()
    end

    # The chunk-level ratio CANNOT see a text that was never chunked: it is absent from
    # the numerator and the denominator alike, so it cancels out and the index reports
    # itself complete. That is not hypothetical — the real corpus reported `percent:
    # 100.0` while 1,230 baked CBETA X texts and 4,068,303 segments had no chunks at all.
    test "a text that was never chunked is reported, not cancelled out" do
      before = Semantic.coverage()
      assert before.percent == 100.0
      assert before.unchunked_texts == 0
      assert before.reachable_percent == 100.0
      assert is_nil(before.note)

      unchunked = load!("T9999", ["未分段之經文"], title: "未分段", composition_origin: "chinese")
      Repo.delete_all(from c in Chunk, where: c.text_id == ^unchunked)

      after_load = Semantic.coverage()

      # Unchanged, and that is exactly the problem this field exists to expose.
      assert after_load.percent == 100.0
      assert after_load.total == before.total

      assert after_load.unchunked_texts == 1
      assert after_load.corpus_texts == before.corpus_texts + 1
      assert after_load.reachable_percent < 100.0
      assert after_load.note =~ "cannot be reached by vector search"
    end

    test "reachability honours the same filters as the chunk counts" do
      unchunked = load!("T9999", ["未分段之經文"], title: "未分段", composition_origin: "chinese")
      Repo.delete_all(from c in Chunk, where: c.text_id == ^unchunked)

      assert %{unchunked_texts: 1} = Semantic.coverage()

      # The unchunked text is Chinese-composed, so an Indic-only view must not inherit
      # its gap — a caller filtering to Indic sources is told the truth about Indic
      # sources.
      assert %{unchunked_texts: 0, reachable_percent: 100.0, note: nil} =
               Semantic.coverage(origin: "indic")
    end
  end

  describe "multi-vector retrieval" do
    setup %{} do
      # An English rendering of the Āgama text, embedded on a THIRD axis. An English
      # query lands nowhere near the Chinese source vector; it lands on this.
      agama = Repo.one!(from t in Text, where: t.work_id == "T0001", select: t.id)

      embed_chunks!(agama, 2,
        kind: "translation",
        lang: "en",
        translator: "model:test",
        content: "Thus have I heard, at one time the Buddha was staying near Rajagaha."
      )

      {:ok, english_probe: unit_vector(2), agama: agama}
    end

    test "an English query reaches a Chinese passage through its rendering", %{
      english_probe: probe
    } do
      %{results: [result | _]} = Semantic.search_vector(probe, limit: 5)

      # Found via English — and what comes back is the CHINESE passage, addressed by the
      # Chinese anchor. The rendering changed what could be found, not what is cited.
      assert result.urn =~ "T0001"
      assert result.content =~ "如是我聞"
      assert Enum.any?(result.matched_via, &(&1.kind == "translation" and &1.lang == "en"))
    end

    test "the result says which vector matched, so a caller can tell them apart", %{
      english_probe: probe
    } do
      %{results: [result | _]} = Semantic.search_vector(probe, limit: 5)
      [via | _] = result.matched_via

      assert via.kind == "translation"
      assert via.translator_id == "model:test"
    end

    test "restricting to source vectors excludes the translation route", %{
      english_probe: probe
    } do
      %{results: results} = Semantic.search_vector(probe, limit: 5, vector_kinds: ["source"])

      refute Enum.any?(results, fn r ->
               Enum.any?(r.matched_via, &(&1.kind == "translation"))
             end)
    end

    test "a chunk matched by two of its vectors is returned once", %{agama: agama} do
      # Both the source and translation vectors of these chunks are in the index; a
      # search that reaches both must not report the passage twice.
      probe = unit_vector(1)
      %{results: results} = Semantic.search_vector(probe, limit: 20)

      urns = Enum.map(results, & &1.urn)
      assert length(urns) == length(Enum.uniq(urns))
      assert agama
    end

    test "coverage reports vectors by kind, not just a single total" do
      coverage = Semantic.coverage([])

      kinds = Enum.map(coverage.by_kind, & &1.kind) |> Enum.uniq() |> Enum.sort()
      assert kinds == ["source", "translation"]
    end
  end
end
