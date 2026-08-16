defmodule Pramana.Chunk.Vectors do
  @moduledoc """
  Builds the rows that will be embedded — one per chunk per vector kind.

  A vector row is created **before** it has a vector, holding the exact text to embed.
  That is what makes the GPU round trip checkable: export text and its hash, import
  vectors, re-check the hash. A row that appeared only at import time could not be
  verified against anything.

  ## Why a chunk gets more than one

  `Pramana.Retrieval.Semantic` says plainly that BGE-M3 is not trained on Literary
  Chinese and that cross-lingual retrieval into it is unproven. An English question
  currently has to cross that gap inside the model's own multilingual space.

  A `translation` vector gives the English question an **English target**. The hit still
  resolves to the source anchor — the passage cited is always the Pāli or the Chinese,
  never the rendering — so this improves what can be *found* without touching what can be
  *cited*.

  ## Assembling a translation's text

  A chunk covers a span of segments. A translation vector for that chunk is the same
  translator's renderings of those segments, in order, joined. Renderings are per-segment
  and a translator may not have rendered every segment in the span, so what is embedded is
  what that translator actually wrote for that span — with `coverage` recorded, because a
  vector built from 3 of 20 segments is not a vector for the passage.
  """

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.ChunkVector
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Corpus.Translation
  alias Pramana.Repo

  # The language of the text itself, by source. Not a guess: `sc` is the Mahāsaṅgīti Pāli
  # edition, CBETA and locally-added commentary are Literary Chinese.
  @lang_by_source %{"sc" => "pli"}
  @default_lang "lzh"

  # A translation vector built from a small fraction of a chunk's segments describes a
  # fragment while claiming the chunk's URN. Below this it is not built at all.
  @min_coverage 0.5

  @doc "The language of a source's text."
  @spec lang_for_source(String.t()) :: String.t()
  def lang_for_source(source_id), do: Map.get(@lang_by_source, source_id, @default_lang)

  @doc """
  Creates the `source` vector row for every chunk of a text that lacks one.

  Idempotent: existing rows are left alone, so re-running never orphans a vector that has
  already been computed.
  """
  @spec build_source(integer()) :: {:ok, non_neg_integer()}
  def build_source(text_id) do
    lang = text_id |> source_id_for() |> lang_for_source()
    now = DateTime.utc_now()

    rows =
      Repo.all(
        from c in Chunk,
          where: c.text_id == ^text_id,
          select: %{id: c.id, content: c.content, content_sha256: c.content_sha256}
      )
      |> Enum.map(fn chunk ->
        %{
          chunk_id: chunk.id,
          kind: "source",
          lang: lang,
          translator_id: nil,
          content: chunk.content,
          content_sha256: chunk.content_sha256,
          inserted_at: now,
          updated_at: now
        }
      end)

    insert(rows)
  end

  @doc """
  Creates `translation` vector rows for a text: one per chunk per translator.

  `lang` is the translation language, not the text's.
  """
  @spec build_translations(integer(), keyword()) :: {:ok, non_neg_integer()}
  def build_translations(text_id, opts \\ []) do
    lang = Keyword.get(opts, :lang, "en")
    now = DateTime.utc_now()

    chunks =
      Repo.all(
        from c in Chunk,
          where: c.text_id == ^text_id,
          select: %{id: c.id, first: c.first_ordinal, last: c.last_ordinal}
      )

    case chunks do
      [] -> {:ok, 0}
      chunks -> build_translation_rows(text_id, chunks, lang, now)
    end
  end

  defp build_translation_rows(text_id, chunks, lang, now) do
    # One query for the whole text rather than one per chunk: a per-chunk query over
    # 8,442 works is tens of thousands of round trips for data that arrives in one.
    renderings =
      Repo.all(
        from s in Segment,
          join: tr in Translation,
          on: tr.anchor_urn == s.urn,
          where: s.text_id == ^text_id and tr.lang == ^lang,
          select: %{
            ordinal: s.ordinal,
            translator_id: tr.translator_id,
            text: tr.text
          },
          order_by: s.ordinal
      )

    by_translator = Enum.group_by(renderings, & &1.translator_id)

    rows =
      for chunk <- chunks,
          {translator_id, translations} <- by_translator,
          row = translation_row(chunk, translator_id, translations, lang, now),
          row != nil,
          do: row

    insert(rows)
  end

  defp translation_row(chunk, translator_id, translations, lang, now) do
    covered =
      translations
      |> Enum.filter(&(&1.ordinal >= chunk.first and &1.ordinal <= chunk.last))
      |> Enum.sort_by(& &1.ordinal)

    span = chunk.last - chunk.first + 1
    coverage = if span > 0, do: length(covered) / span, else: 0.0

    if covered == [] or coverage < @min_coverage do
      nil
    else
      content = covered |> Enum.map_join(" ", & &1.text) |> String.trim()

      %{
        chunk_id: chunk.id,
        kind: "translation",
        lang: lang,
        translator_id: translator_id,
        content: content,
        content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        inserted_at: now,
        updated_at: now
      }
    end
  end

  # `on_conflict: :nothing` rather than replace: a row whose content changed needs its
  # VECTOR recomputed, and silently rewriting the text under an existing vector would
  # leave a vector describing words that are no longer there — the exact failure the
  # import's hash check exists to catch, introduced from the other side.
  defp insert([]), do: {:ok, 0}

  defp insert(rows) do
    written =
      rows
      |> Enum.chunk_every(2_000)
      |> Enum.reduce(0, fn batch, acc ->
        {n, _} =
          Repo.insert_all(ChunkVector, batch,
            on_conflict: :nothing,
            conflict_target:
              {:unsafe_fragment, ~s<(chunk_id, kind, lang, COALESCE(translator_id, ''))>}
          )

        acc + n
      end)

    {:ok, written}
  end

  defp source_id_for(text_id) do
    Repo.one(from t in Text, where: t.id == ^text_id, select: t.source_id)
  end

  @doc "Counts, for the gate and the runbook."
  @spec stats() :: map()
  def stats do
    Repo.all(
      from v in ChunkVector,
        group_by: [v.kind, v.lang],
        select: %{
          kind: v.kind,
          lang: v.lang,
          vectors: count(v.id),
          embedded: count(v.embedding)
        },
        order_by: [desc: count(v.id)]
    )
  end
end
