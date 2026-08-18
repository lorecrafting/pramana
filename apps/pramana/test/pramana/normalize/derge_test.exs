defmodule Pramana.Normalize.DergeTest do
  @moduledoc """
  The Derge Kangyur normalizer.

  Two structural facts drive every test here, and both were found by measuring the
  edition rather than reading its schema: **one file holds many works**, and **one work
  spans many files with only the first saying so**. The second cost 146,962 lines — 31%
  of the edition — silently, while every other number looked healthy.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Derge

  defp tei(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <tei:TEI xmlns:tei="http://www.tei-c.org/ns/1.0">
      <tei:teiHeader><tei:fileDesc><tei:titleStmt>
        <tei:title>༄༅། །འདུལ་བ་ཀ་བཞུགས་སོ། ། [1]</tei:title>
      </tei:titleStmt></tei:fileDesc></tei:teiHeader>
      <tei:text><tei:body><tei:div>#{body}</tei:div></tei:body></tei:text>
    </tei:TEI>
    """
  end

  defp folio(n, content), do: ~s(<tei:p n="1" data-orig-n="#{n}">#{content}</tei:p>)
  defp line(n), do: ~s(<tei:milestone unit="line" n="#{n}"/>)
  defp toh(n), do: ~s(<tei:milestone unit="text" toh="#{n}"/>)

  describe "works within a volume" do
    test "one file yields one work per toh marker" do
      xml =
        tei(
          folio("1b", "#{line(1)}#{toh(1)}ཆོས#{line(2)}གསལ") <>
            folio("2a", "#{line(1)}#{toh(2)}སངས#{line(2)}རྒྱས")
        )

      {:ok, irs, _} = Derge.normalize_file(xml, volume: 1)

      assert Enum.map(irs, & &1.work_id) == ["toh1", "toh2"]
    end

    test "the anchor is volume, folio and line, as Tibetanists cite" do
      xml = tei(folio("1b", "#{line(1)}#{toh(1)}ཆོས#{line(3)}གསལ"))

      {:ok, [ir], _} = Derge.normalize_file(xml, volume: 7)

      # Folio numbering restarts at 1a in EVERY volume, so an anchor without the volume
      # addresses two different lines in a work that spans one.
      assert Enum.map(ir.lines, & &1.anchor) == ["7.1b.1", "7.1b.3"]
    end

    test "text before the first marker is front matter and is dropped" do
      # Folio 1a of volume 1 is the title page. It belongs to no Toh number, and giving
      # it to the first work would start that work a folio early.
      xml = tei(folio("1a", "title page") <> folio("1b", "#{line(1)}#{toh(1)}ཆོས"))

      {:ok, [ir], _} = Derge.normalize_file(xml, volume: 1)

      assert Enum.map(ir.lines, & &1.anchor) == ["1.1b.1"]
    end

    test "indentation does not become a citable line" do
      # The TEI is pretty-printed. A whitespace-only buffer would become a segment with
      # a real URN addressing nothing.
      xml = tei(folio("1b", "\n  #{line(1)}#{toh(1)}ཆོས\n  #{line(2)}\n  "))

      {:ok, [ir], _} = Derge.normalize_file(xml, volume: 1)

      assert length(ir.lines) == 1
    end
  end

  describe "works across volumes" do
    test "a volume with no marker continues the work in progress" do
      # 26 of the 103 volumes contain no toh marker at all — they are the middle of the
      # Vinaya and the Prajñāpāramitā. Treating "no marker yet" as front matter dropped
      # every line in them.
      xml = tei(folio("1b", "#{line(1)}མུ་སྟེགས"))

      {:ok, [ir], continuing} = Derge.normalize_file(xml, volume: 2, continuing: "toh1")

      assert ir.work_id == "toh1"
      assert ir.lines != []
      assert continuing == "toh1"
    end

    test "the work still open at the end is returned, to feed the next volume" do
      xml = tei(folio("1b", "#{line(1)}#{toh(1)}ཆོས#{line(2)}#{toh(2)}སངས"))

      {:ok, _irs, continuing} = Derge.normalize_file(xml, volume: 1)

      assert continuing == "toh2"
    end

    test "a volume that starts a new text overrides what was continuing" do
      xml = tei(folio("1b", "#{line(1)}continues#{line(2)}#{toh(5)}new"))

      {:ok, irs, continuing} = Derge.normalize_file(xml, volume: 3, continuing: "toh4")

      assert Enum.map(irs, & &1.work_id) |> Enum.sort() == ["toh4", "toh5"]
      assert continuing == "toh5"
    end

    test "without a continuation the same volume yields nothing" do
      # The failure that hid 146,962 lines: plausible output, healthy-looking totals,
      # and a third of the edition gone.
      xml = tei(folio("1b", "#{line(1)}མུ་སྟེགས"))

      assert {:ok, [], nil} = Derge.normalize_file(xml, volume: 2)
    end
  end

  describe "anchors that repeat in the source" do
    test "a repeated line number keeps both lines, visibly marked" do
      # Three anchors in the whole edition are printed twice. Dropping the second loses
      # text; merging makes two passages one. `+2` is visibly not a folio reference.
      xml = tei(folio("39b", "#{line(6)}#{toh(3)}first#{line(6)}second"))

      {:ok, [ir], _} = Derge.normalize_file(xml, volume: 7)

      assert Enum.map(ir.lines, & &1.anchor) == ["7.39b.6", "7.39b.6+2"]
      assert Enum.map(ir.lines, & &1.text) == ["first", "second"]
    end
  end

  describe "the catalogue volume" do
    test "is one work, and its toh markers are references not divisions" do
      # Volume 103 is the dkar chag. Its markers sit on titles in a running list — Toh
      # 539 there is "homage, and" — and splitting on them yields works a few words long
      # that collide with the real text.
      xml =
        tei(folio("1b", "#{line(1)}#{toh(538)}མཆོད་པའི་སྤྲིན#{toh(539)}ཕྱག་དང་།"))

      {:ok, irs, _} = Derge.normalize_file(xml, volume: 103, mode: :catalogue)

      assert [%{work_id: "dkar-chag-103"}] = irs
      assert hd(irs).lines != []
    end

    test "the same file split as texts would produce the collision" do
      xml =
        tei(folio("1b", "#{line(1)}#{toh(538)}མཆོད་པའི་སྤྲིན#{toh(539)}ཕྱག་དང་།"))

      {:ok, irs, _} = Derge.normalize_file(xml, volume: 103)

      assert Enum.map(irs, & &1.work_id) == ["toh538", "toh539"]
    end
  end

  describe "normalize/2" do
    test "selects one work out of a volume" do
      xml = tei(folio("1b", "#{line(1)}#{toh(1)}ཆོས#{line(2)}#{toh(2)}སངས"))

      {:ok, ir} = Derge.normalize(xml, volume: 1, work_id: "toh2")

      assert ir.work_id == "toh2"
    end

    test "says so when the volume does not contain the work" do
      xml = tei(folio("1b", "#{line(1)}#{toh(1)}ཆོས"))

      assert {:error, {:work_not_in_volume, "toh9"}} =
               Derge.normalize(xml, volume: 1, work_id: "toh9")
    end
  end
end
