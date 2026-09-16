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
  alias Pramana.Normalize.IR.Line
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

    {:ok, Enum.reverse(segments)}
  end

  @doc """
  The URN prefix for a text, e.g. `pramana:cbeta.T:T0262`.
  """
  @spec urn_prefix(String.t(), String.t(), String.t()) :: String.t()
  def urn_prefix(source, witness, work_id), do: "pramana:#{source}.#{witness}:#{work_id}"

  # Genuinely blank: nothing was printed on this line but the line number. Everything
  # else — a line that is nothing but an inline note, and a line that is nothing but a
  # rare character — is real printed content and must stay addressable.
  #
  # `Line.blank?/1` rather than a pattern match written out here, because this list has
  # been written by hand three times and been wrong every time: text only (v2 dropped
  # 5,213 note-only lines), text and notes (v3 dropped 10,590), text/notes/apparatus —
  # which dropped X0575 0966b12, a line whose entire printed content is the rare
  # character 䦚. Gaiji have empty `text`, since they are a mapping rather than a
  # substitution, so a gaiji-only line matched "blank" exactly.
  defp build(line, ir, source, witness, span, ordinal) do
    if Line.blank?(line),
      do: nil,
      else: build_segment(line, ir, source, witness, span, ordinal)
  end

  defp build_segment(line, ir, source, witness, span, ordinal) do
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
    # Present only on a work assembled from several printed volumes, where the anchor
    # alone stops naming one line: X1571's two volumes repeat 22,616 page/register/line
    # anchors between them. The URN stays unique because it carries the juan, but a
    # reader checking `p0402c01` against the print needs to be told which volume.
    |> then(fn m -> if line.volume, do: Map.put(m, "volume", line.volume), else: m end)
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
