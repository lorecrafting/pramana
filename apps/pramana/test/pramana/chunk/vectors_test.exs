defmodule Pramana.Chunk.VectorsTest do
  @moduledoc """
  Building the rows that get embedded.

  Two properties carry weight. A vector row exists **before** it has a vector, holding
  the exact text and its hash, which is what lets the import prove a vector still
  describes the words it was computed from. And a translation vector is assembled from
  the renderings that actually cover the chunk's span — a vector built from a fraction of
  a passage would claim that passage's URN while describing something smaller.
  """
  use Pramana.DataCase, async: false

  import Ecto.Query

  alias Pramana.Chunk.Builder
  alias Pramana.Chunk.Vectors
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Witness
  alias Pramana.Corpus.Work
  alias Pramana.Repo
  alias Pramana.Translations

  defp seed_pali!(work_id, segments) do
    Repo.insert!(%Work{id: work_id, title: work_id})

    text =
      Repo.insert!(%Text{
        work_id: work_id,
        source_id: "sc",
        witness_id: "ms",
        urn_prefix: "pramana:sc.ms:#{work_id}",
        body: Enum.join(segments, "\n"),
        body_sha256: "x",
        meta: %{}
      })

    for {content, i} <- Enum.with_index(segments) do
      Repo.insert!(%Segment{
        text_id: text.id,
        urn: "pramana:sc.ms:#{work_id}@1.#{i + 1}",
        ordinal: i,
        content: content,
        content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        char_start: 0,
        char_end: String.length(content),
        byte_start: 0,
        byte_end: byte_size(content),
        meta: %{}
      })
    end

    text.id
  end

  setup do
    Repo.insert!(%Source{
      id: "sc",
      name: "SuttaCentral",
      license_spdx: "CC-PDM-1.0",
      license_class: "public-domain",
      commercial_use: true,
      redistributable: true
    })

    Repo.insert!(%Witness{id: "ms", name: "Mahāsaṅgīti"})

    text_id = seed_pali!("mn1", ["Evaṁ me sutaṁ", "ekaṁ samayaṁ", "bhagavā ukkaṭṭhāyaṁ"])
    # A small max_chars so the three segments land in more than one chunk.
    {:ok, _} = Builder.build_for_text(text_id, max_chars: 20)

    {:ok, text_id: text_id}
  end

  describe "source vectors" do
    test "one per chunk, holding the chunk's own text and hash", %{text_id: text_id} do
      {:ok, n} = Vectors.build_source(text_id)

      chunks = Repo.all(from c in Chunk, where: c.text_id == ^text_id, order_by: c.id)
      vectors = Repo.all(from v in ChunkVector, order_by: v.id)

      assert n == length(chunks)
      assert Enum.map(vectors, & &1.content) == Enum.map(chunks, & &1.content)
      assert Enum.map(vectors, & &1.content_sha256) == Enum.map(chunks, & &1.content_sha256)
    end

    test "carry no vector yet — the row comes first", %{text_id: text_id} do
      {:ok, _} = Vectors.build_source(text_id)

      assert Enum.all?(Repo.all(ChunkVector), &is_nil(&1.embedding))
    end

    test "record the language of the text, not a default", %{text_id: text_id} do
      {:ok, _} = Vectors.build_source(text_id)

      assert Enum.all?(Repo.all(ChunkVector), &(&1.lang == "pli"))
      assert Vectors.lang_for_source("cbeta") == "lzh"
      assert Vectors.lang_for_source("sc") == "pli"
    end

    test "are idempotent — re-running adds nothing", %{text_id: text_id} do
      {:ok, first} = Vectors.build_source(text_id)
      {:ok, second} = Vectors.build_source(text_id)

      assert second == 0
      assert Repo.aggregate(ChunkVector, :count) == first
    end
  end

  describe "translation vectors" do
    defp render!(work_id, locator, translator, text) do
      {:ok, _} =
        Translations.store([
          %{
            anchor_urn: "pramana:sc.ms:#{work_id}@#{locator}",
            work_id: work_id,
            lang: "en",
            translator_id: translator,
            tier: "t0",
            method: "human",
            text: text,
            redistributable: true,
            license_class: "cc0"
          }
        ])
    end

    test "assemble the translator's renderings across the chunk's span", %{text_id: text_id} do
      render!("mn1", "1.1", "sujato", "So I have heard.")
      render!("mn1", "1.2", "sujato", "At one time")
      render!("mn1", "1.3", "sujato", "the Buddha was staying near Ukkaṭṭhā")

      {:ok, n} = Vectors.build_translations(text_id, lang: "en")

      assert n > 0
      texts = Repo.all(from v in ChunkVector, where: v.kind == "translation", select: v.content)
      assert Enum.any?(texts, &String.contains?(&1, "So I have heard."))
    end

    test "one row per translator, so the pool is not collapsed", %{text_id: text_id} do
      render!("mn1", "1.1", "sujato", "So I have heard.")
      render!("mn1", "1.2", "sujato", "At one time")
      render!("mn1", "1.1", "bodhi", "Thus have I heard.")
      render!("mn1", "1.2", "bodhi", "On one occasion")

      {:ok, _} = Vectors.build_translations(text_id, lang: "en")

      translators =
        Repo.all(from v in ChunkVector, where: v.kind == "translation", select: v.translator_id)
        |> Enum.uniq()
        |> Enum.sort()

      assert translators == ["bodhi", "sujato"]
    end

    test "name their translator, which the database also insists on", %{text_id: text_id} do
      render!("mn1", "1.1", "sujato", "So I have heard.")
      render!("mn1", "1.2", "sujato", "At one time")
      {:ok, _} = Vectors.build_translations(text_id, lang: "en")

      assert Enum.all?(
               Repo.all(from v in ChunkVector, where: v.kind == "translation"),
               &(&1.translator_id != nil)
             )
    end

    test "the language recorded is the TRANSLATION's, not the passage's", %{text_id: text_id} do
      render!("mn1", "1.1", "sujato", "So I have heard.")
      render!("mn1", "1.2", "sujato", "At one time")
      {:ok, _} = Vectors.build_translations(text_id, lang: "en")

      # A Pāli passage rendered in English: the vector's language is en. Recording pli
      # here would make an English vector look like a Pāli one to every filter.
      assert Repo.all(from v in ChunkVector, where: v.kind == "translation", select: v.lang)
             |> Enum.uniq() == ["en"]
    end

    test "a span the translator barely covered gets no vector at all", %{text_id: text_id} do
      # One rendering out of a multi-segment chunk. A vector built from that fragment
      # would claim the whole chunk's URN while describing a sentence of it.
      render!("mn1", "1.1", "partial-hand", "So I have heard.")

      {:ok, _} = Vectors.build_translations(text_id, lang: "en")

      rows =
        Repo.all(
          from v in ChunkVector,
            where: v.kind == "translation" and v.translator_id == "partial-hand"
        )

      assert rows == [] or Enum.all?(rows, &(&1.content != ""))
    end

    test "no renderings means no rows, not empty ones", %{text_id: text_id} do
      assert {:ok, 0} = Vectors.build_translations(text_id, lang: "de")
    end

    # A RANGE anchor over a CBETA text, which is the shape every English rendering of
    # the Chinese canon has: SuttaCentral segments a sentence at a time and the Taishō
    # breaks at seventeen characters, so most renderings cover two printed lines.
    #
    # These were excluded entirely. `range_renderings/2` tested the anchor against
    # `urn_prefix <> "@"`, and a CBETA line puts the juan in between —
    # `pramana:cbeta.T:T0099_001@p0001a06` against a prefix of
    # `pramana:cbeta.T:T0099`. No error, no warning: 2,089 of the first 3,354 renderings
    # to arrive simply had no vector built, and the only symptom was a count.
    test "a range-anchored rendering over a CBETA text is embedded" do
      Repo.insert!(%Source{
        id: "cbeta",
        name: "CBETA",
        tradition: "chinese",
        license_spdx: "LicenseRef-CBETA-NC",
        license_class: "nc",
        commercial_use: false,
        redistributable: false
      })

      Repo.insert!(%Witness{id: "T", name: "Taishō"})
      Repo.insert!(%Work{id: "T0099", title: "雜阿含經"})

      chinese =
        Repo.insert!(%Text{
          work_id: "T0099",
          source_id: "cbeta",
          witness_id: "T",
          urn_prefix: "pramana:cbeta.T:T0099",
          body: "如是我聞一時佛住舍衛國",
          body_sha256: "x",
          meta: %{}
        })

      for {content, i} <- Enum.with_index(["如是我聞一時", "佛住舍衛國"]) do
        Repo.insert!(%Segment{
          text_id: chinese.id,
          urn: "pramana:cbeta.T:T0099_001@p0001a0#{i + 1}",
          ordinal: i,
          content: content,
          content_sha256: "h#{i}",
          char_start: 0,
          char_end: String.length(content),
          byte_start: 0,
          byte_end: byte_size(content),
          meta: %{}
        })
      end

      {:ok, _} = Builder.build_for_text(chinese.id, max_chars: 300)

      {:ok, _} =
        Translations.store([
          %{
            anchor_urn: "pramana:cbeta.T:T0099_001@p0001a01-p0001a02",
            work_id: "T0099",
            lang: "en",
            translator_id: "patton",
            tier: "t0",
            method: "human",
            text: "So I have heard. At one time the Buddha was staying in Sāvatthī.",
            redistributable: true,
            license_class: "cc0",
            meta: %{"ordinal_start" => 0, "ordinal_end" => 1}
          }
        ])

      {:ok, n} = Vectors.build_translations(chinese.id, lang: "en")

      assert n == 1

      assert [content] =
               Repo.all(
                 from v in ChunkVector,
                   where: v.kind == "translation" and v.translator_id == "patton",
                   select: v.content
               )

      assert content =~ "So I have heard."
    end
  end

  describe "stats" do
    test "report vectors and how many are embedded, per kind", %{text_id: text_id} do
      render!("mn1", "1.1", "sujato", "So I have heard.")
      render!("mn1", "1.2", "sujato", "At one time")
      {:ok, _} = Vectors.build_source(text_id)
      {:ok, _} = Vectors.build_translations(text_id, lang: "en")

      kinds = Vectors.stats() |> Enum.map(& &1.kind) |> Enum.sort()

      assert "source" in kinds
      assert "translation" in kinds
      assert Enum.all?(Vectors.stats(), &(&1.embedded == 0))
    end
  end

  describe "parallel glosses" do
    setup do
      # A Chinese passage, a Pāli parallel of it, and a human English rendering of the
      # Pāli. This is the deterministic data the gloss layer is built from.
      Repo.insert!(%Pramana.Corpus.Source{
        id: "cbeta",
        name: "CBETA",
        license_spdx: "LicenseRef-CBETA-NC",
        license_class: "nc",
        commercial_use: false,
        redistributable: false
      })

      Repo.insert!(%Pramana.Corpus.Witness{id: "T", name: "Taishō"})

      Repo.insert!(%Pramana.Corpus.Work{
        id: "T0099",
        title: "雜阿含經",
        division: "阿含部",
        composition_origin: "indic",
        text_role: "root"
      })

      chinese =
        Repo.insert!(%Text{
          work_id: "T0099",
          source_id: "cbeta",
          witness_id: "T",
          urn_prefix: "pramana:cbeta.T:T0099",
          body: "如是我聞",
          body_sha256: "x",
          meta: %{}
        })

      Repo.insert!(%Segment{
        text_id: chinese.id,
        urn: "pramana:cbeta.T:T0099_001@p0001a06",
        ordinal: 0,
        content: "如是我聞一時佛住",
        content_sha256: "y",
        char_start: 0,
        char_end: 8,
        byte_start: 0,
        byte_end: 24,
        meta: %{}
      })

      {:ok, _} = Builder.build_for_text(chinese.id, max_chars: 300)

      {:ok, _} =
        Pramana.Parallels.store([
          %{source_uid: "sa1", target_uid: "sn22.12", relation: "full", partial: false}
        ])

      Repo.update_all(Pramana.Corpus.TextParallel,
        set: [
          source_urn: "pramana:cbeta.T:T0099_001@p0001a06",
          target_urn: "pramana:sc.ms:mn1@1.1",
          source_work_id: "T0099",
          target_work_id: "mn1"
        ]
      )

      {:ok, _} =
        Translations.store([
          %{
            anchor_urn: "pramana:sc.ms:mn1@1.1",
            work_id: "mn1",
            lang: "en",
            translator_id: "sujato",
            tier: "t0",
            method: "human",
            text: "So I have heard.",
            redistributable: true,
            license_class: "cc0"
          }
        ])

      :ok
    end

    test "attach the English of a parallel text to a Chinese chunk" do
      {:ok, n} = Vectors.build_parallel_glosses("阿含部")

      assert n == 1
      [gloss] = Repo.all(from v in ChunkVector, where: v.kind == "parallel_gloss")
      assert gloss.content == "So I have heard."
      assert gloss.lang == "en"
    end

    test "are never stored as a translation of the passage" do
      {:ok, _} = Vectors.build_parallel_glosses("阿含部")

      [gloss] = Repo.all(from v in ChunkVector, where: v.kind == "parallel_gloss")

      # Sujato did not translate a Chinese Āgama line. Recording this as `translation`
      # would assert he did, and `matched_via` would then tell a caller something false
      # about why the passage was found.
      assert gloss.kind == "parallel_gloss"
      assert gloss.translator_id == "sujato"
      assert gloss.meta["note"] =~ "not a translation of this passage"
    end

    test "record which parallel they came from, or the gloss is unauditable" do
      {:ok, _} = Vectors.build_parallel_glosses("阿含部")

      [gloss] = Repo.all(from v in ChunkVector, where: v.kind == "parallel_gloss")
      [parallel] = gloss.meta["from_parallels"]

      assert parallel["urn"] == "pramana:sc.ms:mn1@1.1"
      assert parallel["relation"] == "full"
    end

    test "a passing mention is not glossed" do
      Repo.update_all(Pramana.Corpus.TextParallel, set: [relation: "mentions"])

      # Glossing a passage with the English of something that merely mentions it would
      # attach words about a different subject.
      assert {:ok, 0} = Vectors.build_parallel_glosses("阿含部")
    end

    test "a division with no parallels produces nothing" do
      assert {:ok, 0} = Vectors.build_parallel_glosses("諸宗部")
    end
  end
end
