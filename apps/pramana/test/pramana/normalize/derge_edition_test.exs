defmodule Pramana.Normalize.Derge.EditionTest do
  @moduledoc """
  The fold from volumes to works.

  Every test here is about the same fact: **the volume is not the unit**. A work runs
  across volumes, only the first one says so, and the loader replaces a text's segments
  rather than appending to them — so a spanning work that is loaded per volume keeps its
  last volume and silently loses the rest.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Derge.Edition
  alias Pramana.Normalize.IR

  defp tei(body) do
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <tei:TEI xmlns:tei="http://www.tei-c.org/ns/1.0">
      <tei:text><tei:body><tei:div>#{body}</tei:div></tei:body></tei:text>
    </tei:TEI>
    """
  end

  defp folio(n, content), do: ~s(<tei:p n="1" data-orig-n="#{n}">#{content}</tei:p>)
  defp line(n), do: ~s(<tei:milestone unit="line" n="#{n}"/>)
  defp toh(n), do: ~s(<tei:milestone unit="text" toh="#{n}"/>)

  describe "a work that spans volumes" do
    setup do
      # Toh 1 opens in volume 1, runs through the whole of volume 2 — which carries no
      # marker of its own — and ends partway into volume 3, where Toh 2 begins.
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}first"))},
        {2, tei(folio("1a", "#{line(1)}second"))},
        {3, tei(folio("1a", "#{line(1)}third#{line(2)}#{toh(2)}next work"))}
      ]

      {:ok, volumes: volumes}
    end

    test "is emitted once, with every volume's lines", %{volumes: volumes} do
      {:ok, works, _stats} = Edition.works(volumes)

      toh1 = Enum.find(works, &(&1.work_id == "toh1"))

      assert Enum.map(toh1.lines, & &1.text) == ["first", "second", "third"]
    end

    test "keeps the volume in every anchor, so the three lines are three addresses", %{
      volumes: volumes
    } do
      {:ok, works, _stats} = Edition.works(volumes)

      toh1 = Enum.find(works, &(&1.work_id == "toh1"))

      # Folio numbering restarts at 1a in every volume. Without the volume, the second
      # and third lines would both be "1a.1" — one work, one anchor, two passages.
      assert Enum.map(toh1.lines, & &1.anchor) == ["1.1b.1", "2.1a.1", "3.1a.1"]
    end

    test "is recorded as the volume it begins in", %{volumes: volumes} do
      {:ok, works, _stats} = Edition.works(volumes)

      assert Enum.find(works, &(&1.work_id == "toh1")).volume == 1
    end

    test "counts as spanning exactly once, however many volumes it crosses", %{
      volumes: volumes
    } do
      {:ok, _works, stats} = Edition.works(volumes)

      assert stats == %{volumes: 3, works: 2, lines: 4, spanning: 1, empty: 0}
    end

    test "each work is emitted exactly once", %{volumes: volumes} do
      {:ok, works, _stats} = Edition.works(volumes)

      ids = Enum.map(works, & &1.work_id)
      assert Enum.sort(ids) == ["toh1", "toh2"]
      assert length(ids) == length(Enum.uniq(ids))
    end
  end

  describe "boundaries" do
    test "a work ending exactly on a volume boundary is still emitted" do
      # Volume 2 opens with a marker, so nothing in it belongs to Toh 1. Toh 1 is
      # complete and must not be dropped for never being 'continued'.
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}alone"))},
        {2, tei(folio("1a", "#{line(1)}#{toh(2)}next"))}
      ]

      {:ok, works, stats} = Edition.works(volumes)

      assert Enum.map(works, & &1.work_id) |> Enum.sort() == ["toh1", "toh2"]
      assert stats.spanning == 0
    end

    test "the work still open when the volumes run out is emitted" do
      volumes = [{1, tei(folio("1b", "#{line(1)}#{toh(1)}last words"))}]

      assert {:ok, [%{work_id: "toh1"}], %{works: 1}} = Edition.works(volumes)
    end
  end

  describe "a volume that yields nothing" do
    test "is an error, not a quiet zero" do
      # This is the 146,962-line bug reduced to three volumes: volume 2 continues a work
      # it does not name, and without the continuation every line in it is dropped. The
      # only symptom was a volume that produced nothing.
      volumes = [{2, tei(folio("1a", "#{line(1)}orphaned"))}]

      assert {:error, {:empty_volume, 2}} = Edition.works(volumes)
    end

    test "reports the volume number, not just that something went wrong" do
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}fine"))},
        {2, tei(folio("1a", "#{line(1)}#{toh(2)}fine"))},
        {3, tei("")}
      ]

      assert {:error, {:empty_volume, 3}} = Edition.works(volumes)
    end
  end

  describe "re-deriving one work, as verify does" do
    setup do
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}first"))},
        {2, tei(folio("1a", "#{line(1)}second"))},
        {3, tei(folio("1a", "#{line(1)}third#{line(2)}#{toh(2)}next work"))}
      ]

      {:ok, volumes: volumes}
    end

    test "reproduces a spanning work byte for byte", %{volumes: volumes} do
      {:ok, works, _stats} = Edition.works(volumes)
      toh1 = Enum.find(works, &(&1.work_id == "toh1"))

      {:ok, rebuilt} = Edition.reproduce(volumes, "toh1")

      assert IR.body(rebuilt) == IR.body(toh1)
    end

    test "the volumes to re-read are recoverable from the work's own anchors", %{
      volumes: volumes
    } do
      {:ok, works, _stats} = Edition.works(volumes)
      toh1 = Enum.find(works, &(&1.work_id == "toh1"))

      assert Edition.volumes(toh1) == [1, 2, 3]
    end

    test "a work starting mid-volume does not swallow the text before its marker", %{
      volumes: volumes
    } do
      # Volume 3 holds the end of Toh 1 and the start of Toh 2. Re-deriving Toh 2 as a
      # continuation of itself would hand it Toh 1's last line.
      {:ok, rebuilt} = Edition.reproduce([List.last(volumes)], "toh2")

      assert Enum.map(rebuilt.lines, & &1.text) == ["next work"]
    end

    test "says which volume is missing the work rather than returning a short text" do
      volumes = [{9, tei(folio("1a", "#{line(1)}#{toh(4)}unrelated"))}]

      assert {:error, {:work_absent_from_volume, "toh1", 9}} = Edition.reproduce(volumes, "toh1")
    end
  end

  describe "a volume that is empty in the source" do
    test "is counted and skipped, not treated as a loss" do
      # Esukhia ships the Tengyur's catalogue volume as a filename with no transcription.
      # A file with no bytes cannot have lost anything in parsing, which is what the
      # empty-volume guard is for.
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}text"))},
        {2, ""}
      ]

      assert {:ok, works, stats} = Edition.works(volumes)
      assert stats.empty == 1
      assert stats.volumes == 1
      assert [%{work_id: "toh1"}] = works
    end
  end

  describe "the catalogue volume" do
    setup do
      volumes = [
        {1, tei(folio("1b", "#{line(1)}#{toh(1)}opening"))},
        {2, tei(folio("1a", "#{line(1)}still toh 1"))},
        {3, tei(folio("1a", "#{line(1)}#{toh(538)}a title#{toh(539)}another title"))}
      ]

      {:ok, volumes: volumes}
    end

    test "is one work, not one per marker in its list", %{volumes: volumes} do
      {:ok, works, _stats} = Edition.works(volumes, catalogue_volumes: [3])

      assert Enum.map(works, & &1.work_id) |> Enum.sort() == ["dkar-chag-3", "toh1"]
    end

    test "does not swallow the work that was open when it began", %{volumes: volumes} do
      # The dkar chag is not a continuation of the volume before it. Threading the open
      # work through it would append the catalogue's text to the last sūtra.
      {:ok, works, _stats} = Edition.works(volumes, catalogue_volumes: [3])

      toh1 = Enum.find(works, &(&1.work_id == "toh1"))

      assert Enum.map(toh1.lines, & &1.text) == ["opening", "still toh 1"]
    end

    test "without catalogue mode references are interpreted as separate works", %{
      volumes: volumes
    } do
      # Toh 538 and 539 exist as real texts elsewhere in the Kangyur. Split on, the
      # catalogue's mentions of them become works a few words long that share an address
      # with the text itself.
      {:ok, works, _stats} = Edition.works(volumes)

      assert "toh538" in Enum.map(works, & &1.work_id)
    end
  end
end
