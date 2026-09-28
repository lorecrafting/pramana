defmodule Pramana.Retrieval.Rerank do
  @moduledoc """
  Reorders a fused candidate list by comparing the query to each candidate's stored
  English rendering. Deterministic — no model, no GPU, no query-time inference.

  ## Why this exists, and what it is worth

  `retrieval/pali` was 82/150, the largest block of failures in the corpus. Probing all
  150 to depth 200 showed the two traditions fail in opposite ways:

      gold at rank 11-200   pali 44 (29.3%)   tibetan  9 (14.1%)
      gold absent from 200  pali 24 (16.0%)   tibetan 31 (48.4%)

  **Tibetan is a recall failure and cannot be reranked. Pāli is a ranking failure and
  can** — its gold is retrieved 84% of the time and merely sits too low, median rank 37.
  Measured over the top 50:

      before    82/150 at rank <= 10
      after    107/150 at rank <= 10      recovered 26, lost 1

  ## Why a string comparison beats an embedding here

  The vector arm compares a query to a CHUNK's embedding — a ~700-character window,
  embedded once, capped at 320 tokens. This compares the query to the rendering of the
  very segments the chunk holds, at full length. Where the query is itself a published
  translation, the match is near-exact and the separation is far sharper than cosine
  similarity over a window.

  ## THE CAVEAT, WHICH IS NOT SMALL

  The `retrieval` gold cases are DERIVED from translation anchors: the query *is* the
  rendering of the expected passage. So a query-to-rendering matcher is solving those
  cases close to the way they were constructed, and the metric flatters it. That is worth
  stating plainly, because #20 already recorded that this case type measures "pinpoint the
  anchor whose translation I quoted" while users ask topical questions.

  It is still a real capability rather than a trick — *"I have this English quote, where is
  it from?"* is ordinary scholarly work, and the citation guard's whole workflow starts
  there. But it does nothing for a topical question, where the query matches no stored
  text, and it must never be quoted as a general retrieval improvement.

  ## What it will not do

  - **Not invent an ordering.** A candidate with no rendering scores 0 and keeps its
    fused position; only candidates the signal genuinely separates move.
  - **Not invent an ordering for a candidate it cannot read.** A candidate with no
    rendering in `lang` scores 0 and keeps its fused position.

  ## ▸ A PROPERTY THIS MODULE CLAIMED AND NO LONGER HAS — 2026-09-03

  **It said "not touch Chinese: no English renderings exist over the Chinese canon, so
  every candidate scores 0 and the order is returned unchanged."** That was true when it
  was written and stopped being true the moment E1's tranche landed: **28,571 English
  renderings over the Chinese canon** now exist. This reorders Chinese candidates, and the
  behaviour changed silently, in the same commit that produced the headline figures.

  **The experiment-isolation half of this note was repaired the same day** and the note is
  corrected rather than deleted, because the figures taken before it are still in the
  documents. `renderings_for/3` now reads `Pramana.Retrieval.RenderingScope` — the one
  definition of what an arm may see — so `:translators`, `:translation_coverage` and
  `:translation_chunks` reach this stage. Before that they reached candidate generation and
  stopped: `Hybrid.maybe_rerank/3` passed no options at all, and **every arm of the 205-case
  ladder was reranked against the whole English layer**, including the renderings that arm
  was defined by excluding.

  ## What it still does not disclose

  It filters by `lang` and the arm's scope — **not by `method` and not by `tier`.** That is
  right as production behaviour: a reranker reading every rendering it has is a reranker
  working. But 27,751 CBETA chunks now have machine English and no human English, all of
  them `tier: t1` and `review_state: raw`, so **a result can be at rank 1 because an
  unreviewed model rendering matched** — and `Hybrid`'s response reports which retrievers
  generated candidates, never that this stage ran or what moved. The span carries its
  warrant; the ordering does not. `docs/HISTORY.md`, the 2026-09-03 architecture review.
  """

  alias Pramana.Repo
  alias Pramana.Retrieval.RenderingScope

  @doc """
  Reorders `results` by how much of `query` appears in each candidate's English rendering.

  `results` are the decorated maps `Hybrid` produces; the return is the same list,
  reordered. Candidates that tie — including everything with no rendering — keep their
  incoming order, so this can only move what the signal actually distinguishes.
  """
  @spec by_rendering(String.t(), [map()], keyword()) :: [map()]
  def by_rendering(query, results, opts \\ []) do
    {reordered, _report} = by_rendering_reported(query, results, opts)
    reordered
  end

  @doc """
  The same reordering, with a record of what this stage read to do it.

  **A span carries its warrant and, until 2026-09-03, the rank did not.** `Hybrid` reported
  which retrievers generated candidates and said nothing about whether this stage ran or
  what it read — and by then 27,751 CBETA chunks had machine English and no human English,
  every one `tier: t1` and `review_state: raw`. A result could be first because an
  unreviewed model rendering matched the query, with nothing in the response to say so.

  `tiers` is the answer to the question that actually matters to a reader: **was the
  ordering influenced by generated text?** It is the distinct tiers of the renderings this
  stage read, so `["t0"]` means human English alone and `["t0", "t1"]` means both.
  """
  @spec by_rendering_reported(String.t(), [map()], keyword()) :: {[map()], map()}
  def by_rendering_reported(_query, [], _opts), do: {[], report(0, [])}

  # `opts` reaches here since 2026-09-03. It did not before: `Hybrid.maybe_rerank/3` called
  # `by_rendering(query, results)` with no options at all, so an experimental arm could
  # not restrict this stage even in principle. See `Pramana.Retrieval.RenderingScope`.
  def by_rendering_reported(query, results, opts) do
    lang = Keyword.get(opts, :lang, "en")
    tokens = tokenize(query)

    if MapSet.size(tokens) == 0 do
      {results, report(0, [])}
    else
      {renderings, tiers} = renderings_for(Enum.map(results, & &1.urn), lang, opts)

      reordered =
        results
        |> Enum.with_index()
        |> Enum.sort_by(fn {result, i} ->
          {-containment(tokens, Map.get(renderings, result.urn)), i}
        end)
        |> Enum.map(&elem(&1, 0))

      # SCORED, not merely read: a candidate the stage could not read scores 0 and keeps
      # its place, so counting the rows would overstate what actually had an effect.
      scored = Enum.count(results, &Map.has_key?(renderings, &1.urn))

      {reordered, report(scored, tiers)}
    end
  end

  defp report(scored, tiers), do: %{ran: true, scored: scored, tiers: Enum.sort(tiers)}

  # How much of the QUERY is present in the rendering, not how similar the two are.
  # Containment rather than Jaccard because a rendering may legitimately be longer than
  # the span quoted from it, and being longer is not evidence against a match.
  defp containment(query_tokens, text) do
    candidate = tokenize(text)

    if MapSet.size(candidate) == 0 do
      0.0
    else
      matched = MapSet.intersection(query_tokens, candidate) |> MapSet.size()
      matched / MapSet.size(query_tokens)
    end
  end

  defp tokenize(nil), do: MapSet.new()

  defp tokenize(text) do
    text
    |> String.downcase()
    |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
    |> MapSet.new()
  end

  # A candidate is a CHUNK and a Pāli rendering is anchored to a SEGMENT, so the path runs
  # chunk -> member segments -> their renderings, concatenated.
  #
  # NOT in reading order, which this comment claimed until 2026-09-02: `string_agg` with
  # `DISTINCT` and no `ORDER BY` emits its input sorted by the aggregated value, so the
  # renderings arrive **alphabetically**. That is harmless *here* and only here — the
  # result is tokenised into a `MapSet` for overlap scoring by `score/2`, so nothing
  # downstream can observe the order. Do not copy this query anywhere the string is read
  # as prose: assembling a chunk's English in an order the source did not choose is rule
  # 71, and it scrambled 41% of the English over the Chinese canon.
  #
  # `Translations.covering/2` does not serve this: it resolves the ordinal-range anchors
  # 84000 uses for Derge, and returns nothing for a segment-anchored Pāli rendering. A
  # first version of this probe used it, scored every Pāli candidate 0.0, and reported a
  # confident "recovered 0, lost 1" while measuring nothing at all.
  #
  # One batched query per search rather than one per candidate.
  # BOTH ANCHOR FORMS, and getting this wrong is not a coverage nuisance — it is a
  # cross-tradition bias. Measured:
  #
  #     derge.D   30,653 range-anchored        0 exact-anchored
  #     sc.ms          0 range-anchored  210,756 exact-anchored
  #
  # An exact-anchor join alone therefore scores **100% of Pāli and 0% of Tibetan**. It does
  # not merely fail to help Tibetan; it promotes the Pāli candidates in a Tibetan query's
  # pool ABOVE the correct Tibetan answer, because only they are scorable. That cost 4
  # `retrieval/tibetan` cases in the first measured run — twice the documented ANN wobble,
  # and the same interference class #43 and #44 recorded, arriving through a new door.
  #
  # This is the FOURTH time this join has been written incorrectly in this codebase (see
  # "the THIRD place that join has been wrong" under #21). The shape is always the same:
  # 84000 anchors a rendering to a folio RANGE and SuttaCentral anchors one to a segment
  # ID, so any join written against whichever source the author had in mind silently
  # excludes the other.
  defp renderings_for([], _lang, _opts), do: {%{}, []}

  defp renderings_for(urns, lang, opts) do
    # $1 urns, $2 lang, and the scope's own parameters from $3 — one definition of what an
    # arm may see, shared with `Semantic` rather than restated here.
    {conditions, scope_params} = RenderingScope.sql_conditions("t", "c", opts, 3)

    sql = """
    SELECT c.urn, string_agg(DISTINCT t.text, ' '), array_agg(DISTINCT t.tier)
    FROM chunks c
    JOIN texts tx ON tx.id = c.text_id
    JOIN segments s
      ON s.text_id = c.text_id AND s.ordinal BETWEEN c.first_ordinal AND c.last_ordinal
    JOIN translations t
      ON t.lang = $2
     AND (
           t.anchor_urn = s.urn
           OR (
                t.work_id = tx.work_id
                AND (t.meta ->> 'ordinal_start')::int <= s.ordinal
                AND (t.meta ->> 'ordinal_end')::int >= s.ordinal
              )
         )
    WHERE c.urn = ANY($1)
    #{Enum.join(conditions, "\n    ")}
    GROUP BY c.urn
    """

    %{rows: rows} = Repo.query!(sql, [urns, lang | scope_params])

    {Map.new(rows, fn [urn, text, _tiers] -> {urn, text} end),
     rows |> Enum.flat_map(fn [_urn, _text, tiers] -> tiers || [] end) |> Enum.uniq()}
  end
end
