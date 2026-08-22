defmodule Pramana.Retrieval.PerTraditionTest do
  @moduledoc """
  `per_tradition: true` runs one search per canon and merges, so that a canon whose
  English is a less direct statement of a doctrine is not shut out by one whose is —
  measured on "What are the four noble truths?", where Pāli held 193 of 200 slots and the
  first Tibetan result sat at rank 142.

  The failure this file exists to prevent is not bad ranking. It is a source that is
  **never queried**: the groups were once a hand-written map naming 4 of the 8 registered
  sources, so a source outside it returned nothing and reported nothing, which is
  indistinguishable from a canon that has nothing to say. `local-huang-nianzu-jie` (848
  embedded chunks) was in that position, and `sat` would have been on the day #14
  unblocks.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Loader
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Embed
  alias Pramana.Local.Manifest
  alias Pramana.Normalize.CBETA
  alias Pramana.Repo
  alias Pramana.Retrieval.Semantic
  alias Pramana.Sources

  @dims 1024

  # A local source definition as `mix pramana.local.add` builds one — through the manifest
  # and `Sources.from_manifest/1`, so the test exercises the real path that writes
  # `sources.tradition` rather than inserting the row it hopes that path produces.
  defp local_definition(id, tradition) do
    Sources.from_manifest(%Manifest{
      id: id,
      title: "測試注釋",
      provenance: %{"composition_origin" => "chinese", "text_role" => "commentary"},
      license: %{"class" => "restricted", "redistributable" => false},
      citation: %{"addressing" => "derived"},
      format: "markdown",
      tradition: tradition
    })
  end

  defp load!(work_id, source, lines, definition \\ nil) do
    body =
      lines
      |> Enum.with_index(1)
      |> Enum.map_join("\n", fn {text, i} ->
        n = "0001a" <> String.pad_leading(Integer.to_string(i), 2, "0")
        ~s(<lb n="#{n}"/>#{text})
      end)

    xml = """
    <TEI xmlns="http://www.tei-c.org/ns/1.0" xmlns:cb="http://www.cbeta.org/ns/1.0">
    <teiHeader><fileDesc><titleStmt><title level="m">測試</title></titleStmt></fileDesc></teiHeader>
    <text><body><milestone n="1" unit="juan"/>#{body}</body></text></TEI>
    """

    {:ok, ir} = CBETA.normalize(xml, work_id: work_id, canon: "T", volume: 1, number: "0001")

    {:ok, _} =
      Loader.load(ir,
        source: source,
        witness: "T",
        source_definition: definition,
        provenance: %{composition_origin: "indic", text_role: "root"}
      )

    text_id = Repo.one!(from t in Text, where: t.work_id == ^work_id, select: t.id)
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 30)
    text_id
  end

  defp unit_vector(axis) do
    for i <- 0..(@dims - 1), do: if(i == axis, do: 1.0, else: 0.0)
  end

  defp embed_chunks!(text_id, axis) do
    now = DateTime.utc_now()

    rows =
      from(c in Chunk, where: c.text_id == ^text_id, select: %{id: c.id, content: c.content})
      |> Repo.all()
      |> Enum.map(fn chunk ->
        %{
          chunk_id: chunk.id,
          kind: "source",
          lang: "lzh",
          content: chunk.content,
          content_sha256: :crypto.hash(:sha256, chunk.content) |> Base.encode16(case: :lower),
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
    # CBETA gets enough chunks to FILL the result window on its own. With only two it
    # reached slot three by ordinary ranking and the local text still appeared, which
    # would have made the assertions below pass for the wrong reason — the fixture has to
    # reproduce the monopoly it claims to be about.
    cbeta =
      load!("T0001", "cbeta", [
        "一切眾生皆有佛性",
        "如是我聞一時佛住",
        "王舍城耆闍崛山中",
        "與大比丘眾千二百",
        "爾時世尊告諸比丘",
        "諸法無我無我所故",
        "色受想行識皆無常",
        "苦空非我當如是觀",
        "若能如是觀察者則",
        "得解脫生死輪迴苦",
        "是名正見正思惟也",
        "佛說此經已歡喜奉"
      ])

    # A locally-added source: an id outside the static registry, declaring no tradition,
    # so it is its own.
    local =
      load!(
        "L0001",
        "local-test-commentary",
        ["一切眾生皆有佛性者何也"],
        local_definition("test-commentary", nil)
      )

    # The CBETA text sits ON the probe axis and the local one off it, so a single ranked
    # search prefers CBETA everywhere. That is the point: only per-canon retrieval can
    # surface the local text, which is precisely the monopoly this feature answers.
    embed_chunks!(cbeta, 0)
    embed_chunks!(local, 1)

    {:ok, probe: unit_vector(0)}
  end

  defp sources_in(results) do
    results
    |> Enum.map(fn hit ->
      hit.urn |> String.split(":") |> Enum.at(1) |> String.split(".") |> hd()
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  describe "a source outside the registry" do
    test "is invisible to a single ranked search, which is why this feature exists", %{
      probe: probe
    } do
      %{results: results} = Semantic.search_vector(probe, limit: 3)

      assert sources_in(results) == ["cbeta"]
    end

    test "is REACHED by per-tradition search rather than silently skipped", %{probe: probe} do
      %{results: results} = Semantic.search_vector(probe, limit: 10, per_tradition: true)

      assert "local-test-commentary" in sources_in(results),
             "a source in no registry group was never queried — it returns nothing and " <>
               "reports nothing, which reads as a canon with nothing to say"
    end

    test "groups come from the corpus, so a new source needs no code change", %{probe: probe} do
      second =
        load!("L0002", "local-second", ["眾生皆有佛性之義"], local_definition("second", nil))

      embed_chunks!(second, 2)

      %{results: results} = Semantic.search_vector(probe, limit: 12, per_tradition: true)

      assert "local-second" in sources_in(results)
    end
  end

  describe "a local text that declares a canon joins it" do
    test "it competes inside that canon rather than being given a quota equal to it", %{
      probe: probe
    } do
      joined =
        load!("L0003", "local-joined", ["佛性義釋"], local_definition("joined", "chinese"))

      embed_chunks!(joined, 3)

      assert Repo.get!(Source, "local-joined").tradition == "chinese"

      # Its own group is gone: it is inside `chinese` now, so it takes CBETA's slots
      # rather than a third of the results. That is the difference between belonging to a
      # canon and being one.
      groups =
        from(s in Source, select: s.tradition) |> Repo.all() |> Enum.uniq() |> Enum.sort()

      refute "local-joined" in groups

      %{results: results} = Semantic.search_vector(probe, limit: 12, per_tradition: true)
      assert results != []
    end
  end

  describe "the default path is untouched" do
    test "without per_tradition the ranking is purely by distance", %{probe: probe} do
      %{results: results} = Semantic.search_vector(probe, limit: 10)

      assert hd(results).urn =~ "cbeta"
    end
  end
end
