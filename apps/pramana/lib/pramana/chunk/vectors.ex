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
  alias Pramana.URN

  # The language of the text itself, by source. Not a guess: `sc` is the Mahāsaṅgīti Pāli
  # edition, `derge` is the Tibetan Kangyur, CBETA and locally-added commentary are
  # Literary Chinese. A missing entry here does not fail — it silently labels a vector
  # with the wrong language, and `Pramana.Retrieval.Semantic` reports `matched_via` from
  # exactly this field.
  @lang_by_source %{"sc" => "pli", "derge" => "bo", "derge-tengyur" => "bo"}
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
    by_translator =
      (point_renderings(text_id, lang) ++ range_renderings(text_id, lang))
      |> Enum.sort_by(& &1.first)
      |> Enum.group_by(& &1.translator_id)

    rows =
      for chunk <- chunks,
          {translator_id, translations} <- by_translator,
          row = translation_row(chunk, translator_id, translations, lang, now),
          row != nil,
          do: row

    insert(rows)
  end

  # A rendering anchored to a single segment. One query for the whole text rather than one
  # per chunk: a per-chunk query over 8,442 works is tens of thousands of round trips for
  # data that arrives in one.
  defp point_renderings(text_id, lang) do
    Repo.all(
      from s in Segment,
        join: tr in Translation,
        on: tr.anchor_urn == s.urn,
        where: s.text_id == ^text_id and tr.lang == ^lang,
        select: %{
          first: s.ordinal,
          last: s.ordinal,
          translator_id: tr.translator_id,
          text: tr.text
        }
    )
  end

  # A rendering anchored to a RANGE of segments, which is how a translator who works at a
  # coarser grain than the edition's citation unit is stored. 84000 marks the Degé
  # Kangyur's folios while this corpus addresses its lines, so every one of its 30,653
  # renderings covers about seven segments and matches no segment URN at all — joining on
  # equality found nothing, and Tibetan would have had no English route into it.
  #
  # The span comes from the ordinals recorded on the rendering rather than from parsing
  # its anchor, for the same reason `Pramana.Translations.covering/2` uses them: a locator
  # grammar belongs to its edition.
  defp range_renderings(text_id, lang) do
    # By `work_id`, which is indexed with `lang`, and not by a prefix match on the anchor:
    # the anchor form is only known after a scan, and one scan of 241,409 renderings per
    # text is 8,442 of them for the Pāli alone — ten minutes of doing nothing, since none
    # of those renderings is range-anchored at all.
    case Repo.one(from t in Text, where: t.id == ^text_id, select: {t.work_id, t.urn_prefix}) do
      nil ->
        []

      {work_id, prefix} ->
        Repo.all(
          from tr in Translation,
            where:
              tr.work_id == ^work_id and tr.lang == ^lang and
                fragment("? \\? 'ordinal_start'", tr.meta),
            select: %{
              anchor_urn: tr.anchor_urn,
              first: fragment("(? -> 'ordinal_start')::int", tr.meta),
              last: fragment("(? -> 'ordinal_end')::int", tr.meta),
              translator_id: tr.translator_id,
              text: tr.text
            }
        )
        # Ordinals belong to a text, not to a work, so a work held in two witnesses must
        # not borrow the other one's positions. `Pramana.URN.addresses?/2` and not a
        # `starts_with?` on `prefix <> "@"`, which reads CBETA's juan as someone else's
        # text — see its doc.
        |> Enum.filter(&URN.addresses?(&1.anchor_urn, prefix))
    end
  end

  defp translation_row(chunk, translator_id, translations, lang, now) do
    covered =
      translations
      |> Enum.filter(&(&1.last >= chunk.first and &1.first <= chunk.last))
      |> Enum.sort_by(& &1.first)

    span = chunk.last - chunk.first + 1
    coverage = if span > 0, do: covered_ordinals(covered, chunk) / span, else: 0.0

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

  # How much of the chunk any rendering speaks for, counted over the chunk's own segments
  # so that two overlapping folio renderings cannot claim more than the chunk has.
  defp covered_ordinals(covered, chunk) do
    covered
    |> Enum.flat_map(&Enum.to_list(max(&1.first, chunk.first)..min(&1.last, chunk.last)//1))
    |> Enum.uniq()
    |> length()
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

  @doc """
  Attaches the English of a chunk's **parallel** text as a retrieval vector.

  The eval harness measured that an English question retrieves nothing from the Chinese
  canon — 0 of 12, against 100% for the same questions asked in Chinese — because there
  is no English layer to match against. Generating one costs real money, so the
  deterministic data goes first (`CLAUDE.md` invariant #5): 24,717 curated Chinese↔Pāli
  parallels, and 210,756 human English renderings of the Pāli side, already licensed and
  already here.

  **This is not a translation of the passage, and is never stored as one.** It is a
  translation of a different text that scholarship judges to transmit the same discourse.
  A search that lands on a Chinese line through its Pāli parallel's English says exactly
  that in `matched_via`, so a reader can weigh it accordingly — the two texts differ, and
  where they differ is itself the interesting part.

  Only `full` and `resembling` parallels are used. A `mentions` is a passing reference,
  and glossing a passage with the English of something that merely mentions it would
  attach words that are about a different subject.
  """
  @spec build_parallel_glosses(String.t(), keyword()) :: {:ok, non_neg_integer()}
  def build_parallel_glosses(division, opts \\ []) do
    lang = Keyword.get(opts, :lang, "en")
    relations = Keyword.get(opts, :relations, ["full", "resembling"])
    now = DateTime.utc_now()

    division
    |> gloss_candidates(lang, relations)
    |> Enum.group_by(& &1.chunk_id)
    |> Enum.flat_map(fn {chunk_id, rows} -> gloss_rows(chunk_id, rows, lang, now) end)
    |> insert()
  end

  # One query: for every chunk in the division, the English renderings of whatever the
  # curated parallels point at. Per-chunk queries over 10,138 chunks would be tens of
  # thousands of round trips for data that arrives at once.
  defp gloss_candidates(division, lang, relations) do
    Repo.all(
      from c in Chunk,
        join: t in Text,
        on: t.id == c.text_id,
        join: w in Pramana.Corpus.Work,
        on: w.id == t.work_id,
        join: s in Segment,
        on:
          s.text_id == c.text_id and s.ordinal >= c.first_ordinal and s.ordinal <= c.last_ordinal,
        join: p in Pramana.Corpus.TextParallel,
        on: p.source_urn == s.urn,
        join: tr in Translation,
        on: tr.anchor_urn == p.target_urn,
        where: w.division == ^division and tr.lang == ^lang and p.relation in ^relations,
        select: %{
          chunk_id: c.id,
          text: tr.text,
          translator_id: tr.translator_id,
          source_uid: p.source_uid,
          target_uid: p.target_uid,
          target_urn: p.target_urn,
          relation: p.relation
        }
    )
  end

  # One row per translator per chunk, mirroring how the translation pool keeps
  # renderings separate rather than merging them into a consensus that nobody wrote.
  defp gloss_rows(chunk_id, rows, lang, now) do
    rows
    |> Enum.group_by(& &1.translator_id)
    |> Enum.map(fn {translator_id, group} ->
      content = group |> Enum.map(& &1.text) |> Enum.uniq() |> Enum.join(" ") |> String.trim()

      %{
        chunk_id: chunk_id,
        kind: "parallel_gloss",
        lang: lang,
        translator_id: translator_id,
        content: content,
        content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        meta: %{
          "from_parallels" =>
            group
            |> Enum.map(
              &%{"uid" => &1.target_uid, "urn" => &1.target_urn, "relation" => &1.relation}
            )
            |> Enum.uniq(),
          "note" =>
            "English of a PARALLEL text, not a translation of this passage. Retrieval " <>
              "aid only; never citable as a rendering of the Chinese."
        },
        inserted_at: now,
        updated_at: now
      }
    end)
    |> Enum.reject(&(&1.content == ""))
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
