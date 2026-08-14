defmodule Pramana.Chunk.Builder do
  @moduledoc """
  Groups segments into retrieval chunks — the unit that gets embedded.

  A Taishō segment is one printed line (18.2 characters on average) and the break is
  typographic, not syntactic: in T0262 the name 阿若憍陳如 splits across lines as
  `…阿若憍` / `陳如…`. Embedding a segment embeds half a name.

  Chunks are windows of consecutive segments up to `:max_chars`, never crossing a juan
  boundary, and each carries the **range URN** covering its members. Because that URN
  is built from real citation anchors rather than invented, a semantic hit stays
  verifiable by exactly the same guard as a direct lookup.

  ## Boundaries

  Chunks stop at juan (fascicle) boundaries because a juan is a real division of the
  work; a window spanning two of them would produce a passage no edition contains.
  They do not overlap — see the migration for why.
  """

  import Ecto.Query

  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Segment
  alias Pramana.Repo
  alias Pramana.URN

  @default_max_chars 300

  @doc """
  Builds and stores chunks for one text, replacing any it already has.

  Idempotent, like the segment loader: re-running converges rather than duplicating.
  """
  @spec build_for_text(integer(), keyword()) :: {:ok, non_neg_integer()}
  def build_for_text(text_id, opts \\ []) do
    max_chars = Keyword.get(opts, :max_chars, @default_max_chars)

    segments =
      Repo.all(from s in Segment, where: s.text_id == ^text_id, order_by: s.ordinal)

    Repo.delete_all(from c in Chunk, where: c.text_id == ^text_id)

    rows =
      segments
      |> group(max_chars)
      |> Enum.map(&to_row(&1, text_id))

    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(&Repo.insert_all(Chunk, &1))

    {:ok, length(rows)}
  end

  @doc """
  Groups segments into windows.

  Exposed for testing without a database: the grouping rule is the part worth pinning.
  """
  @spec group([Segment.t()], pos_integer()) :: [[Segment.t()]]
  def group(segments, max_chars \\ @default_max_chars) do
    segments
    |> Enum.reduce({[], [], 0}, fn segment, {done, current, size} ->
      seg_chars = String.length(segment.content)

      cond do
        current == [] ->
          {done, [segment], seg_chars}

        # A juan is a real division of the work; a window spanning two would describe
        # a passage no printed edition contains.
        hd(current).juan != segment.juan ->
          {[Enum.reverse(current) | done], [segment], seg_chars}

        size + seg_chars > max_chars ->
          {[Enum.reverse(current) | done], [segment], seg_chars}

        true ->
          {done, [segment | current], size + seg_chars}
      end
    end)
    |> then(fn
      {done, [], _} -> Enum.reverse(done)
      {done, current, _} -> Enum.reverse([Enum.reverse(current) | done])
    end)
  end

  defp to_row(segments, text_id) do
    first = List.first(segments)
    last = List.last(segments)
    content = Enum.map_join(segments, "", & &1.content)
    now = DateTime.utc_now()

    %{
      text_id: text_id,
      urn: range_urn(first, last),
      first_ordinal: first.ordinal,
      last_ordinal: last.ordinal,
      segment_count: length(segments),
      juan: first.juan,
      content: content,
      content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
      char_start: first.char_start,
      char_end: last.char_end,
      byte_start: first.byte_start,
      byte_end: last.byte_end,
      inserted_at: now,
      updated_at: now
    }
  end

  # A single-segment chunk keeps the point URN; only a real span becomes a range.
  defp range_urn(first, first), do: first.urn

  defp range_urn(first, last) do
    with {:ok, a} <- URN.parse(first.urn),
         {:ok, b} <- URN.parse(last.urn) do
      URN.to_string(%{a | locator_end: b.locator})
    else
      _ -> first.urn
    end
  end
end
