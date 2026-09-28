defmodule Pramana.Segment.DergeTest do
  @moduledoc """
  The Derge segmenter: one segment per printed line, addressed the way the edition is
  cited — volume, folio and side, line.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.IR
  alias Pramana.Segment.Derge

  defp ir(lines) do
    %IR{
      work_id: "toh1",
      canon: "D",
      volume: 1,
      lines: Enum.map(lines, fn {anchor, text} -> %IR.Line{anchor: anchor, text: text} end)
    }
  end

  defp segments(lines) do
    {:ok, segments} = Derge.segments(ir(lines), source: "derge", witness: "D")
    segments
  end

  describe "the citation" do
    test "the locator is the edition's own anchor, unchanged" do
      [segment] = segments([{"2.5b.3", "ཆོས"}])

      assert segment.urn == "pramana:derge.D:toh1@2.5b.3"
    end

    test "the folio keeps its side, because 5a and 5b are two leaves" do
      [a, b] = segments([{"2.5a.1", "recto"}, {"2.5b.1", "verso"}])

      assert a.page == "5a"
      assert b.page == "5b"
    end

    test "an inserted leaf keeps its printed label" do
      # Four leaves in the edition are inserted rather than numbered, and are labelled
      # 33xa, 93xb, 354xa, 355xb. They are ordinary text on an unusual folio.
      [segment] = segments([{"100.355xa.1", "ཆོས"}])

      assert segment.page == "355xa"
      assert segment.line == 1
    end

    test "the line is the line printed on the folio" do
      [segment] = segments([{"2.5b.3", "ཆོས"}])

      assert segment.line == 3
    end

    test "juan is null: a Derge volume is not a fascicle of the work" do
      # One volume holds dozens of works and one work runs across thirteen. Recording the
      # volume as a juan would make the same column mean two different things in two
      # canons.
      [segment] = segments([{"2.5b.3", "ཆོས"}])

      assert segment.juan == nil
      assert segment.register == nil
      assert segment.meta["volume"] == 2
    end
  end

  describe "spans" do
    test "character and byte offsets slice the segment out of the body" do
      # Tibetan is multi-byte throughout, so a corpus that only tracks characters cannot
      # verify a quote and one that only tracks bytes cannot count them.
      ir = ir([{"1.1b.1", "ཆོས"}, {"1.1b.2", "གསལ"}])
      {:ok, segments} = Derge.segments(ir, source: "derge", witness: "D")
      body = IR.body(ir)

      for segment <- segments do
        assert String.slice(body, segment.char_start, segment.char_end - segment.char_start) ==
                 segment.content

        assert binary_part(body, segment.byte_start, segment.byte_end - segment.byte_start) ==
                 segment.content
      end
    end

    test "the sha256 is over the segment's own text" do
      [segment] = segments([{"1.1b.1", "ཆོས"}])

      assert segment.content_sha256 ==
               :crypto.hash(:sha256, "ཆོས") |> Base.encode16(case: :lower)
    end
  end

  describe "anchors the edition prints twice" do
    test "the repeated line keeps a distinct URN" do
      [first, second] = segments([{"7.39b.6", "first"}, {"7.39b.6+2", "second"}])

      assert first.urn != second.urn
      assert second.urn == "pramana:derge.D:toh1@7.39b.6+2"
    end

    test "but the columns record what was printed, which is the same folio and line" do
      [_first, second] = segments([{"7.39b.6", "first"}, {"7.39b.6+2", "second"}])

      assert second.page == "39b"
      assert second.line == 6
      assert second.meta["repeated_anchor"] == true
    end
  end

  test "an anchor that does not parse gets null columns rather than a guessed folio" do
    [segment] = segments([{"catalogue", "ཆོས"}])

    assert segment.urn == "pramana:derge.D:toh1@catalogue"
    assert segment.page == nil
    assert segment.line == nil
    assert segment.meta == %{}
  end

  test "a blank line consumes its position but is not citable" do
    [first, second] = segments([{"1.1b.1", "ཆོས"}, {"1.1b.2", ""}, {"1.1b.3", "གསལ"}])

    assert first.ordinal == 0
    assert second.ordinal == 1
    # The blank line is still in the body, so the third line starts past it.
    assert second.urn == "pramana:derge.D:toh1@1.1b.3"

    # ཆོས is two GRAPHEMES over three codepoints — the vowel sign ◌ོ stacks onto ཆ — and
    # `char_start` counts what `String.slice/3` counts, or verification would not slice
    # the span back out. Two, a newline, and the blank line's newline.
    assert String.length("ཆོས") == 2
    assert second.char_start == 4
  end
end
