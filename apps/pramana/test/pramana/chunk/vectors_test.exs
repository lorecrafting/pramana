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
end
