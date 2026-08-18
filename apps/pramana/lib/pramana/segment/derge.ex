defmodule Pramana.Segment.Derge do
  @moduledoc """
  Segments the Derge Kangyur: one segment per line printed on the woodblock.

  The anchor is already in the markup — `data-orig-n="1b"` is the folio and
  `<milestone unit="line" n="3"/>` the line — so this segmenter never derives a locator,
  it only takes the one `Pramana.Normalize.Derge` read off the page apart into columns a
  query can filter on. `2.5b.3` is volume 2, folio 5 verso, line 3, and a scholar checks
  us by opening that leaf (`CLAUDE.md` invariant #2).

  ## What goes in which column

      page      the folio, side included — `5b`, not `5`
      line      the line printed on it
      juan      null
      register  null

  `page` is a string for exactly this reason: `5a` and `5b` are two different leaves and
  rounding them to the integer 5 would make two passages share an address.

  **`juan` stays null even though a Derge volume is an integer sitting right there.** A
  juan (卷) is a fascicle *of a work*; a Derge volume is a shelf position *of the
  edition*, and one volume holds dozens of works while one work runs across thirteen.
  Putting the volume there would make `juan: 2` mean "the second fascicle" in the Chinese
  canon and "whatever happens to be printed in volume 2" here — the kind of quiet
  cross-canon conflation this schema exists to prevent. The volume is in the locator,
  where it is unambiguous, and in `meta["volume"]` for filtering. The edition's real
  analogue of the juan is the *bam po*, which this etext does not mark up at all: it
  appears in the text as the words བམ་པོ, and inferring divisions from prose is exactly
  the guesswork rule 5 forbids.

  ## Anchors the edition prints twice

  Three lines in 461,414 carry an anchor another line already used. The normalizer keeps
  both and appends `+2` to the second, which is visibly not a folio reference. Here that
  suffix is stripped for the `page`/`line` columns — those record what was *printed*,
  and both lines really were printed at 39b.6 — while the locator keeps it, so the two
  passages still have distinct URNs. `meta["repeated_anchor"]` says so out loud.
  """

  @behaviour Pramana.Pipeline.Segmenter

  alias Pramana.Normalize.IR
  alias Pramana.URN

  # `33xa` and `355xb` are real: four leaves in the edition are inserted rather than
  # numbered, and the etext labels them with an `x` before the side. Counted, not guessed
  # — 65,975 folios are `NNNa`/`NNNb` and exactly 8 are `NNNxa`/`NNNxb`. A pattern that
  # only knew the regular form would have left 43 lines with a null folio for no reason
  # anyone could see from the data.
  @anchor ~r/^(?<volume>\d+)\.(?<folio>\d+x?[ab])\.(?<line>\d+)(?<repeat>\+\d+)?$/

  @impl Pramana.Pipeline.Segmenter
  def segments(%IR{} = ir, opts) do
    source = Keyword.fetch!(opts, :source)
    witness = Keyword.fetch!(opts, :witness)

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

  # Nothing was printed here. The normalizer already drops whitespace-only buffers; this
  # is the same guarantee stated where the segment is built, so an empty URN cannot be
  # created by a future change upstream.
  defp build(%{text: ""}, _ir, _source, _witness, _span, _ordinal), do: nil

  defp build(line, ir, source, witness, span, ordinal) do
    printed = printed(line.anchor)

    Map.merge(span, %{
      urn:
        URN.to_string(%URN{
          source: source,
          witness: witness,
          work: ir.work_id,
          locator: line.anchor
        }),
      juan: nil,
      page: printed[:folio],
      register: nil,
      line: printed[:line],
      ordinal: ordinal,
      kind: Atom.to_string(line.kind),
      content: line.text,
      content_sha256: :crypto.hash(:sha256, line.text) |> Base.encode16(case: :lower),
      meta: meta(printed)
    })
  end

  # An anchor that does not parse keeps its locator and gets null columns rather than a
  # guessed folio. The locator is what resolves; the columns are for filtering, and a
  # wrong folio would be worse than no folio.
  defp printed(anchor) do
    case Regex.named_captures(@anchor, anchor) do
      nil ->
        %{folio: nil, line: nil, volume: nil, repeated?: false}

      caps ->
        %{
          folio: caps["folio"],
          line: String.to_integer(caps["line"]),
          volume: String.to_integer(caps["volume"]),
          repeated?: caps["repeat"] != ""
        }
    end
  end

  defp meta(%{volume: nil}), do: %{}
  defp meta(%{volume: volume, repeated?: false}), do: %{"volume" => volume}

  defp meta(%{volume: volume, repeated?: true}),
    do: %{"volume" => volume, "repeated_anchor" => true}
end
