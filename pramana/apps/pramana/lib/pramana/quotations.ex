defmodule Pramana.Quotations do
  @moduledoc """
  The quotation graph: where one work reproduces another's words verbatim.

  Buddhist commentaries quote their root texts constantly, and the Chinese canon recycles
  stock passages across works compiled centuries apart. This finds those reuses by
  **character identity** — no model, no embedding, no similarity threshold to defend.
  `CLAUDE.md` invariant #5 puts a deterministic method ahead of a probabilistic one
  wherever both could answer, and here only one of them can answer *exactly*.

  ## Neither end is the source

  A match has an `a` end and a `b` end, not a source and a target. Identical characters
  say nothing about who quoted whom: that is a judgement about dates, transmission and
  attribution, and the scan cannot make it. Anything that presents one end as the origin
  is adding a claim the evidence does not carry.

  ## Offsets come home to URNs

  The scanner works on `texts.body`, which is exactly what segment `char_start` and
  `char_end` index into, so a match's character range maps back onto real citation
  anchors with no second concatenation to keep in step. A quotation therefore arrives as
  a **range URN**, verifiable by the same guard as anything else.
  """

  import Ecto.Query

  alias Pramana.Corpus.Quotation
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.URN

  @doc """
  Every reuse involving a work, both ends.

  A match is stored once, arbitrarily oriented, so querying one column would return half
  the graph — the same reason `Pramana.Parallels.for_work/2` reads both directions.
  """
  @spec for_work(String.t(), keyword()) :: [map()]
  def for_work(work_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    min_length = Keyword.get(opts, :min_length, 0)

    a =
      from q in Quotation,
        where: q.a_work_id == ^work_id and q.length >= ^min_length,
        select: %{
          text: q.text,
          length: q.length,
          here: q.a_urn,
          there: q.b_urn,
          other_work_id: q.b_work_id
        }

    b =
      from q in Quotation,
        where: q.b_work_id == ^work_id and q.length >= ^min_length,
        select: %{
          text: q.text,
          length: q.length,
          here: q.b_urn,
          there: q.a_urn,
          other_work_id: q.a_work_id
        }

    (Repo.all(from(x in subquery(a), order_by: [desc: x.length], limit: ^limit)) ++
       Repo.all(from(x in subquery(b), order_by: [desc: x.length], limit: ^limit)))
    |> Enum.sort_by(& &1.length, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Every work that reproduces the passage at `urn`.

  This is the question the graph exists to answer: *show me every text that quotes this
  passage*. Overlap rather than containment — a quotation that covers part of the passage
  is still a quotation of it, and requiring full containment would hide the commonest
  case, where a commentary lifts a clause rather than a whole line.
  """
  @spec quoting(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def quoting(urn, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    with {:ok, %URN{}} <- URN.parse(urn),
         {:ok, span} <- span_bounds(urn) do
      matches =
        Repo.all(
          from q in Quotation,
            where:
              (q.a_text_id == ^span.text_id and q.a_char_start < ^span.char_end and
                 q.a_char_end > ^span.char_start) or
                (q.b_text_id == ^span.text_id and q.b_char_start < ^span.char_end and
                   q.b_char_end > ^span.char_start),
            order_by: [desc: q.length],
            limit: ^limit
        )
        |> Enum.map(&present(&1, span.text_id))

      {:ok,
       %{
         urn: urn,
         total: length(matches),
         quotations: matches,
         note:
           "Verbatim character identity, found by scanning — not a scholarly attribution. " <>
             "Neither end is marked as the origin: which text quoted which is a judgement " <>
             "about dates and transmission that this evidence does not carry."
       }}
    end
  end

  # Orient the match so `here` is the passage that was asked about.
  defp present(%Quotation{} = q, text_id) do
    {here_urn, there_urn, other_work} =
      if q.a_text_id == text_id,
        do: {q.a_urn, q.b_urn, q.b_work_id},
        else: {q.b_urn, q.a_urn, q.a_work_id}

    %{
      text: q.text,
      length: q.length,
      here: here_urn,
      there: there_urn,
      other_work_id: other_work
    }
  end

  # Accepts a single line OR a range.
  #
  # A range matters because this tool HANDS OUT range URNs: a quotation long enough to be
  # interesting crosses printed lines, so its anchor is a range, and a reader copying that
  # back in would otherwise be told the passage does not exist. Anything the system emits
  # as a citation must be accepted as one.
  defp span_bounds(urn) do
    case Repo.one(
           from s in Segment,
             where: s.urn == ^urn,
             select: %{text_id: s.text_id, char_start: s.char_start, char_end: s.char_end}
         ) do
      nil -> range_bounds(urn)
      span -> {:ok, span}
    end
  end

  defp range_bounds(urn) do
    with {:ok, %URN{locator_end: locator_end} = parsed} when not is_nil(locator_end) <-
           URN.parse(urn),
         first when not is_nil(first) <- segment_at(%{parsed | locator_end: nil}),
         last when not is_nil(last) <-
           segment_at(%{parsed | locator: locator_end, locator_end: nil}) do
      {:ok,
       %{
         text_id: first.text_id,
         char_start: min(first.char_start, last.char_start),
         char_end: max(first.char_end, last.char_end)
       }}
    else
      _ -> {:error, :not_found}
    end
  end

  defp segment_at(%URN{} = urn) do
    string = URN.to_string(urn)

    Repo.one(
      from s in Segment,
        where: s.urn == ^string,
        select: %{text_id: s.text_id, char_start: s.char_start, char_end: s.char_end}
    )
  end

  @doc """
  Stores matches, resolving each end's character range to a URN.

  A match whose range cannot be resolved to segments is **dropped and counted**, never
  stored with a null anchor: a quotation that cannot be cited is not a quotation this
  project can serve.
  """
  @spec store([map()], keyword()) :: {:ok, map()}
  def store(matches, opts \\ []) do
    bake_id = Keyword.get(opts, :bake_id)
    now = DateTime.utc_now()
    works = work_ids()

    matches
    |> Enum.chunk_every(5_000)
    |> Enum.reduce({0, 0, 0}, &store_batch(&1, &2, works, bake_id, now))
    |> then(fn {written, unresolved, total} ->
      {:ok, %{written: written, unresolved: unresolved, total: total}}
    end)
  end

  defp store_batch(batch, {written, unresolved, total}, works, bake_id, now) do
    index = segment_index(text_ids(batch), works)

    {rows, missed} =
      Enum.reduce(batch, {[], 0}, fn match, {rows, missed} ->
        case row(match, index, bake_id, now) do
          nil -> {rows, missed + 1}
          row -> {[row | rows], missed}
        end
      end)

    # Batched by ROW WIDTH, not by a constant: 5,000 quotation rows is 85,000 bound
    # parameters and Postgres accepts 65,535. See `Pramana.Batch`.
    {n, _} =
      Pramana.Batch.insert_all(Quotation, rows,
        on_conflict: :nothing,
        conflict_target: [:a_text_id, :a_char_start, :b_text_id, :b_char_start]
      )

    {written + n, unresolved + missed, total + length(batch)}
  end

  defp text_ids(batch) do
    batch
    |> Enum.flat_map(&occurrence_text_ids/1)
    |> Enum.uniq()
  end

  defp occurrence_text_ids(%{"occurrences" => occurrences}),
    do: Enum.flat_map(occurrences, &parse_text_id(&1["work"]))

  defp occurrence_text_ids(_), do: []

  defp parse_text_id(value) do
    case Integer.parse(to_string(value)) do
      {id, ""} -> [id]
      _ -> []
    end
  end

  defp work_ids do
    Repo.all(from t in Text, select: {t.id, t.work_id}) |> Map.new()
  end

  defp row(%{"text" => text, "length" => length, "occurrences" => [a, b]}, index, bake_id, now) do
    with {:ok, a_end} <- resolve_end(a, index),
         {:ok, b_end} <- resolve_end(b, index),
         true <- a_end.text_id != b_end.text_id do
      %{
        text: text,
        text_sha256: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower),
        length: length,
        a_text_id: a_end.text_id,
        a_work_id: a_end.work_id,
        a_urn: a_end.urn,
        a_char_start: a["start"],
        a_char_end: a["end"],
        b_text_id: b_end.text_id,
        b_work_id: b_end.work_id,
        b_urn: b_end.urn,
        b_char_start: b["start"],
        b_char_end: b["end"],
        bake_id: bake_id,
        meta: %{},
        inserted_at: now,
        updated_at: now
      }
    else
      _ -> nil
    end
  end

  defp row(_, _, _, _), do: nil

  # The scanner keys works by text id, so the range maps straight onto that text's
  # segments.
  defp resolve_end(%{"work" => text_id_string, "start" => start, "end" => finish}, index) do
    with {text_id, ""} <- Integer.parse(to_string(text_id_string)),
         %{work_id: work_id, segments: segments} <- Map.get(index, text_id),
         urn when not is_nil(urn) <- range_urn(segments, start, finish) do
      {:ok, %{text_id: text_id, work_id: work_id, urn: urn}}
    else
      _ -> :error
    end
  end

  defp resolve_end(_, _), do: :error

  # The URN spanning every segment the match touches. A match crossing printed lines —
  # which most do, since the line break is typographic — becomes a range, exactly as a
  # chunk does.
  defp range_urn(segments, start, finish) do
    touched =
      segments
      |> Enum.filter(fn s -> s.char_start < finish and s.char_end > start end)
      |> Enum.sort_by(& &1.char_start)

    case touched do
      [] -> nil
      [one] -> one.urn
      many -> join_range(List.first(many).urn, List.last(many).urn)
    end
  end

  defp join_range(first, last), do: URN.range(first, last)

  # Segments for ONLY the texts a batch touches.
  #
  # The first version loaded every segment in the corpus into one map. That is 4.74M
  # rows: it worked on a 155-work division and was killed on the full canon — after the
  # scanner had already done its part correctly, which made it look as though the scan
  # had failed. A resolver whose memory grows with the corpus rather than with the batch
  # cannot run on the corpus.
  defp segment_index(text_ids, works) do
    from(s in Segment,
      where: s.text_id in ^text_ids,
      select: %{text_id: s.text_id, urn: s.urn, char_start: s.char_start, char_end: s.char_end}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.text_id)
    |> Map.new(fn {text_id, segments} ->
      {text_id, %{work_id: Map.get(works, text_id), segments: segments}}
    end)
  end

  @doc "Counts, for the gate and the inventory."
  @spec stats() :: map()
  def stats do
    %{
      quotations: Repo.aggregate(Quotation, :count),
      works_involved:
        Repo.one(
          from q in Quotation,
            select: count(fragment("DISTINCT ?", q.a_work_id))
        ),
      longest: Repo.one(from q in Quotation, select: max(q.length)),
      median_length:
        Repo.one(
          from q in Quotation,
            select: fragment("percentile_cont(0.5) WITHIN GROUP (ORDER BY ?)", q.length)
        )
    }
  end
end
