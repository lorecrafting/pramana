defmodule Pramana.Segment.SegmentId do
  @moduledoc """
  Segments a text whose edition already provides segment ids.

  Used for SuttaCentral material, where the citable unit is given rather than derived:
  `mn1:1.1` is how the field cites the passage, so the locator is that id unchanged.

  Contrast `Pramana.Segment.Taisho`, which reconstructs page/register/line from `<lb/>`
  markers, and `Pramana.Segment.Page`, which uses a printed page number. All three obey
  the same rule — the anchor belongs to the edition, never to us.
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

        span = %{
          char_start: char_off,
          char_end: char_off + char_len,
          byte_start: byte_off,
          byte_end: byte_off + byte_len
        }

        case build(line, ir, source, witness, span, ordinal) do
          # +1 for the "\n" IR.body/1 joins lines with.
          nil ->
            {acc, char_off + char_len + 1, byte_off + byte_len + 1, ordinal}

          segment ->
            {[segment | acc], char_off + char_len + 1, byte_off + byte_len + 1, ordinal + 1}
        end
      end)

    {:ok, Enum.reverse(segments)}
  end

  # An empty segment id carries nothing citable. Bilara does emit a few, usually
  # structural placeholders. The blank test is `Line.blank?/1` everywhere, so no
  # segmenter can hold a narrower idea of "nothing was printed" than the check that
  # audits it — bilara never populates notes, apparatus or gaiji, so this is the same
  # predicate it already had.
  defp build(line, ir, source, witness, span, ordinal) do
    if Line.blank?(line),
      do: nil,
      else: build_segment(line, ir, source, witness, span, ordinal)
  end

  defp build_segment(line, ir, source, witness, span, ordinal) do
    Map.merge(span, %{
      urn:
        URN.to_string(%URN{
          source: source,
          witness: witness,
          work: ir.work_id,
          locator: line.anchor
        }),
      juan: nil,
      # Pāli has no page/register/line; leaving these null is the honest shape rather
      # than manufacturing coordinates the edition does not print.
      page: nil,
      register: nil,
      line: nil,
      ordinal: ordinal,
      kind: Atom.to_string(line.kind),
      content: line.text,
      content_sha256: :crypto.hash(:sha256, line.text) |> Base.encode16(case: :lower),
      meta: %{}
    })
  end
end
