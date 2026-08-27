defmodule Pramana.Segment.Page do
  @moduledoc """
  Segments a page-anchored text: one segment per printed page.

  Used by locally-added sources whose edition numbers pages but not lines. The locator
  is `p<anchor>` — `p0100` for body page 100, `ptoc-0003` for a separately-numbered
  table-of-contents page — so a citation names a page a reader can turn to.

  ## Front matter keeps its own sequence

  A book that restarts numbering for its table of contents and preface has three
  distinct page-1s. Renumbering them into one run would produce references matching no
  printed page, so the prefix is preserved and the sequences stay separate.

  ## Same invariants as the Taishō segmenter

  Character AND byte offsets into `IR.body/1`; a `content_sha256` over the segment text;
  a line that is genuinely blank is skipped while still consuming its position. See
  `Pramana.Segment.Taisho` — the Phase 1 gate found that dropping *every* text-less line
  cost 10,590 uncitable printed lines, so "blank" means nothing was printed, not merely
  no body text.
  """

  @behaviour Pramana.Pipeline.Segmenter

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line
  alias Pramana.URN

  @impl Pramana.Pipeline.Segmenter
  def segments(%IR{} = ir, opts) do
    source = Keyword.fetch!(opts, :source)
    witness = Keyword.fetch!(opts, :witness)

    {segments, _char, _byte, _ordinal} =
      Enum.reduce(ir.lines, {[], 0, 0, 0}, fn line, {acc, char_off, byte_off, ordinal} ->
        char_len = String.length(line.text)
        byte_len = byte_size(line.text)
        # +1 for the "\n" that IR.body/1 joins lines with.
        next = {char_off + char_len + 1, byte_off + byte_len + 1}

        span = %{
          char_start: char_off,
          char_end: char_off + char_len,
          byte_start: byte_off,
          byte_end: byte_off + byte_len
        }

        case build(line, ir, source, witness, span, ordinal) do
          nil -> {acc, elem(next, 0), elem(next, 1), ordinal}
          segment -> {[segment | acc], elem(next, 0), elem(next, 1), ordinal + 1}
        end
      end)

    {:ok, Enum.reverse(segments)}
  end

  # Nothing was printed on this page at all. Anything else — text, a note, an
  # apparatus entry, a rare character — is content and must keep its anchor, and
  # `Line.blank?/1` is the single definition of that.
  defp build(line, ir, source, witness, span, ordinal) do
    if Line.blank?(line),
      do: nil,
      else: build_segment(line, ir, source, witness, span, ordinal)
  end

  defp build_segment(line, ir, source, witness, span, ordinal) do
    Map.merge(span, %{
      urn: build_urn(source, witness, ir.work_id, line),
      juan: line.juan,
      page: line.anchor,
      register: nil,
      line: nil,
      ordinal: ordinal,
      kind: Atom.to_string(line.kind),
      content: line.text,
      content_sha256: sha256(line.text),
      meta: meta(line)
    })
  end

  defp build_urn(source, witness, work_id, line) do
    %URN{source: source, witness: witness, work: work_id, locator: "p" <> line.anchor}
    |> URN.to_string()
  end

  defp meta(line) do
    %{}
    |> put_unless_empty("notes", line.notes)
    |> put_unless_empty("apparatus", line.apparatus)
  end

  defp put_unless_empty(map, _key, []), do: map
  defp put_unless_empty(map, key, value), do: Map.put(map, key, value)

  defp sha256(text), do: :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
end
