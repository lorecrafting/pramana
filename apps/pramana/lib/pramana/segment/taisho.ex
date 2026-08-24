defmodule Pramana.Segment.Taisho do
  @moduledoc """
  Turns a normalized `Pramana.Normalize.IR` into URN-anchored segment rows.

  One segment per printed line. The citable unit is **edition-anchored, not
  chunker-derived** (`CLAUDE.md` invariant #2): the URN's locator is the Taishō
  page/register/line that a scholar can check against the printed volume, so we never
  invent an identifier.

  Retrieval chunks, added in Phase 1, are windows *over* these anchors — a chunk's URN
  is a range of real citation points rather than a synthetic id.

  ## Offsets

  Segments carry BOTH `char_start`/`char_end` and `byte_start`/`byte_end`, indexing
  into `IR.body/1` (which joins lines with `\\n`).

  Character offsets are for clients: Classical Chinese is multi-byte throughout, and a
  client slicing by codepoint would mis-cut on byte offsets. Byte offsets are for the
  server: `binary_part/3` is O(1) while `String.slice/3` must walk the binary counting
  codepoints, and the citation guard resolves spans on every answer.
  """

  @behaviour Pramana.Pipeline.Segmenter

  alias Pramana.Normalize.IR
  alias Pramana.URN
  alias Pramana.URN.Taisho

  @type segment :: %{
          urn: String.t(),
          juan: pos_integer() | nil,
          page: String.t() | nil,
          register: String.t() | nil,
          line: pos_integer() | nil,
          ordinal: non_neg_integer(),
          kind: String.t(),
          content: String.t(),
          content_sha256: String.t(),
          char_start: non_neg_integer(),
          char_end: non_neg_integer(),
          byte_start: non_neg_integer(),
          byte_end: non_neg_integer(),
          meta: map()
        }

  @doc """
  Builds segments for a text.

  `source` and `witness` form the URN namespace (`cbeta.T`).

  A line is skipped only when it is **genuinely blank** — no body text, no inline note,
  no apparatus. A line whose printed content is entirely an inline note still gets a
  segment, with empty `content` and the note in `meta`.

  That distinction is not pedantry. Dropping every text-less line cost the corpus 5,213
  printed lines carrying 266,547 characters of note text, concentrated in the
  catalogues (T2154, T2157) and commentaries where interlinear notes carry much of the
  substance. Those lines exist in the printed edition and had no URN, so the content
  was unreachable and the line uncitable.

  It is also invisible to `mix pramana.verify`: that re-normalizes from `raw/` and
  compares, and both sides lose the same content, so the check passes. **Reproducibility
  is not fidelity** — a deterministic pipeline can drop the same thing every time.
  """
  @impl Pramana.Pipeline.Segmenter
  @spec segments(IR.t(), keyword()) :: {:ok, [segment()]} | {:error, term()}
  def segments(%IR{} = ir, opts) do
    source = Keyword.fetch!(opts, :source)
    witness = Keyword.fetch!(opts, :witness)

    # The ordinal is CARRIED, not recomputed. Using `length(acc)` here made this
    # quadratic and it only showed up at scale: T0220a (大般若波羅蜜多經, 600 fascicles)
    # has 92,192 segments, so that was ~4.2 billion list traversals — 89 seconds of
    # segmenting against 1.4 seconds of parsing. It looked like a database timeout.
    {segments, _char, _byte, _ordinal} =
      Enum.reduce(ir.lines, {[], 0, 0, 0}, fn line, {acc, char_off, byte_off, ordinal} ->
        char_len = String.length(line.text)
        byte_len = byte_size(line.text)
        # +1 for the "\n" that IR.body/1 joins lines with.
        next_char = char_off + char_len + 1
        next_byte = byte_off + byte_len + 1

        span = %{
          char_start: char_off,
          char_end: char_off + char_len,
          byte_start: byte_off,
          byte_end: byte_off + byte_len
        }

        case build(line, ir, source, witness, span, ordinal) do
          nil -> {acc, next_char, next_byte, ordinal}
          segment -> {[segment | acc], next_char, next_byte, ordinal + 1}
        end
      end)

    {:ok, segments |> Enum.reverse() |> coalesce_repeated_anchors()}
  end

  # ONE PRINTED LINE, however many times the markup re-announces it.
  #
  # CBETA re-emits `<lb>` when an element spans the line it opened on:
  #
  #     <lb n="0831b01" ed="R003"/><cb:juan…><cb:jhead>馬鳴菩薩成就悉地念誦一卷
  #     <lb n="0831b01" ed="R003"/><note place="inline">吉備大臣持來</note></cb:jhead>
  #
  # Same number, same edition, one printed line — split only because `<cb:jhead>` closes
  # after it. Emitting two segments gives them one URN between them and the insert fails
  # on `segments_urn_index`. **284 of 1,236 X works died this way**; the Taishō survived
  # only because its repeats carry nothing on the second occurrence, so `build/6` already
  # dropped them as blank.
  #
  # Dropping the repeat is not available: it holds an inline note, which rule 3 says is
  # printed content and must stay addressable. So the line is reassembled.
  #
  # THE NEWLINE IS PART OF THE CONTENT, and that is not cosmetic. `IR.body/1` joins lines
  # with "\n", so the bytes between these two fragments in the body ARE a newline. A
  # merged span running from the first fragment's start to the second's end must therefore
  # contain it, or `binary_part(body, byte_start, byte_end - byte_start)` stops equalling
  # `content` and invariant #1 — every span byte-verifiable against the witness — breaks
  # silently for exactly these lines.
  #
  # This is rule 1 read from the other side: there, a buffered element spanning a line
  # break had to be SPLIT at the line; here an element boundary splits a line that has to
  # be rejoined. The line is the citable unit either way, never the element.
  defp coalesce_repeated_anchors(segments) do
    segments
    |> Enum.reduce([], fn segment, acc ->
      case acc do
        [%{urn: urn} = previous | rest] when urn == :erlang.map_get(:urn, segment) ->
          [merge_fragment(previous, segment) | rest]

        _ ->
          [segment | acc]
      end
    end)
    |> Enum.reverse()
    # Ordinals are position in the text and must stay contiguous; merging removed rows
    # from under them. `Corpus.between/4` selects by ordinal RANGE, so a gap here silently
    # shortens every chunk and range URN that crosses it.
    |> Enum.with_index()
    |> Enum.map(fn {segment, ordinal} -> %{segment | ordinal: ordinal} end)
  end

  defp merge_fragment(previous, fragment) do
    content = previous.content <> "\n" <> fragment.content

    %{
      previous
      | content: content,
        content_sha256: :crypto.hash(:sha256, content) |> Base.encode16(case: :lower),
        char_end: fragment.char_end,
        byte_end: fragment.byte_end,
        meta: merge_meta(previous.meta, fragment.meta)
    }
  end

  defp merge_meta(a, b) do
    Map.merge(a, b, fn
      _key, va, vb when is_list(va) and is_list(vb) -> va ++ vb
      _key, _va, vb -> vb
    end)
  end

  @doc """
  The URN prefix for a text, e.g. `pramana:cbeta.T:T0262`.
  """
  @spec urn_prefix(String.t(), String.t(), String.t()) :: String.t()
  def urn_prefix(source, witness, work_id), do: "pramana:#{source}.#{witness}:#{work_id}"

  # Genuinely blank: nothing was printed on this line but the line number. Everything
  # else — including a line that is nothing but an inline note — is real printed
  # content and must stay addressable.
  defp build(%{text: "", notes: [], apparatus: []}, _ir, _source, _witness, _span, _ordinal),
    do: nil

  defp build(line, ir, source, witness, span, ordinal) do
    anchor = parse_anchor(line.anchor)

    Map.merge(span, %{
      urn: build_urn(source, witness, ir.work_id, line),
      juan: line.juan,
      page: anchor[:page],
      register: anchor[:register],
      line: anchor[:line],
      ordinal: ordinal,
      kind: Atom.to_string(line.kind),
      content: line.text,
      content_sha256: sha256(line.text),
      meta: meta(line)
    })
  end

  # Work id carries the juan (T0262_009), locator carries page/register/line -- both
  # exactly as a Taishō citation is written in print.
  defp build_urn(source, witness, work_id, line) do
    work =
      case line.juan do
        nil -> work_id
        juan -> "#{work_id}_#{juan |> Integer.to_string() |> String.pad_leading(3, "0")}"
      end

    %URN{
      source: source,
      witness: witness,
      work: work,
      locator: "p" <> line.anchor
    }
    |> URN.to_string()
  end

  defp parse_anchor(anchor) do
    case Taisho.parse_locator("p" <> anchor) do
      {:ok, parsed} -> parsed
      {:error, _} -> %{}
    end
  end

  # Gaiji, editorial-punctuation flags, notes, and the variant apparatus travel with
  # the segment. The apparatus in particular is a shipped feature, not debris.
  defp meta(line) do
    %{}
    |> put_unless_empty("gaiji", line.gaiji)
    |> put_unless_empty("notes", line.notes)
    |> put_unless_empty("apparatus", Enum.map(line.apparatus, &normalize_app/1))
    |> then(fn m ->
      if line.editorial_punctuation, do: Map.put(m, "editorial_punctuation", true), else: m
    end)
  end

  defp normalize_app(app) do
    %{
      "from" => app.from,
      "lem" => app.lem,
      "rdgs" =>
        Enum.map(app.rdgs, fn r ->
          %{"text" => r.text, "wit" => r.wit, "resp" => r.resp, "omitted" => r.omitted}
        end)
    }
  end

  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp sha256(binary), do: :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower)
end
