defmodule Pramana.Normalize.Tei84000.FoliosTest do
  @moduledoc """
  Cutting a translation at folio boundaries.

  The hard case is a file that renders the same text in two places in the canon at once:
  its folio references interleave, and each place needs the whole translation cut at its
  own boundaries.
  """
  use ExUnit.Case, async: true

  alias Pramana.Normalize.Tei84000.Folios

  defp location(toh, volume, start_page, end_page),
    do: %{toh: toh, volume: volume, start_page: start_page, end_page: end_page}

  defp parsed(locations, events),
    do: %{locations: locations, events: events, titles: %{}, translators: [], edition: nil}

  describe "one place in the canon" do
    test "each folio gets the text that follows its reference" do
      {:ok, split} =
        [location("toh507", 88, 2, 14)]
        |> parsed([
          {:folio, "F.1.b"},
          {:text, "Homage to all the buddhas."},
          {:folio, "F.2.a"},
          {:text, "Thus did I hear."}
        ])
        |> Folios.split()

      assert split.spans == [
               %{toh: "toh507", volume: 88, folio: "1b", text: "Homage to all the buddhas."},
               %{toh: "toh507", volume: 88, folio: "2a", text: "Thus did I hear."}
             ]
    end

    test "text before the first reference renders no folio" do
      {:ok, split} =
        [location("toh507", 88, 2, 14)]
        |> parsed([{:text, "The Translation"}, {:folio, "F.1.b"}, {:text, "Homage."}])
        |> Folios.split()

      assert [%{folio: "1b", text: "Homage."}] = split.spans
    end

    test "an inserted leaf keeps the etext's own label for it" do
      # 84000 writes `F.33.a(b)` where the Derge etext writes `33xa`. Same leaf, two
      # notations, and the anchor has to be in ours.
      {:ok, split} =
        [location("toh21", 34, 60, 70)]
        |> parsed([{:folio, "F.33.a(b)"}, {:text, "on the inserted leaf"}])
        |> Folios.split()

      assert [%{folio: "33xa"}] = split.spans
    end
  end

  describe "a work that runs across volumes" do
    test "a folio number that goes backwards means the next volume" do
      # Nothing else says so: only eight of the Śatasāhasrikā's eleven crossings are
      # marked, and the folio simply restarts at 1b in the next volume.
      {:ok, split} =
        [location("toh8", 14, 2, 787), location("toh8", 15, 2, 803)]
        |> parsed([
          {:folio, "F.394.a"},
          {:text, "the end of volume 14"},
          {:folio, "F.1.b"},
          {:text, "the start of volume 15"}
        ])
        |> Folios.split()

      assert [%{volume: 14, folio: "394a"}, %{volume: 15, folio: "1b"}] = split.spans
    end

    test "an explicit crossing names the volume it lands in" do
      # A file can mark the crossing into volume 21 without having marked 18, so the
      # marker sets the volume rather than stepping one along.
      {:ok, split} =
        [location("toh8", 14, 2, 787), location("toh8", 15, 2, 803), location("toh8", 16, 2, 787)]
        |> parsed([
          {:folio, "F.10.a"},
          {:text, "in volume 14"},
          {:volume, 16},
          {:folio, "F.10.a"},
          {:text, "in volume 16"}
        ])
        |> Folios.split()

      assert [%{volume: 14, text: "in volume 14"}, %{volume: 16, text: "in volume 16"}] =
               split.spans
    end
  end

  describe "one translation, two places in the canon" do
    setup do
      # Toh 507 in volume 88 and Toh 883 in volume 101 are the same dhāraṇī. 84000
      # translates it once and marks both editions' folio boundaries in one flow.
      events = [
        {:folio, "F.1.b"},
        {:folio, "F.123.a"},
        {:text, "Homage to all the buddhas."},
        {:folio, "F.2.a"},
        {:text, "Thus did I hear at one time."},
        {:folio, "F.123.b"},
        {:text, "The Blessed One was dwelling in Magadha."}
      ]

      {:ok,
       parsed: parsed([location("toh507", 88, 2, 14), location("toh883", 101, 243, 255)], events)}
    end

    test "each place gets the whole translation, cut at its own boundaries", %{parsed: parsed} do
      {:ok, split} = Folios.split(parsed)

      by_toh = Enum.group_by(split.spans, & &1.toh)
      # Whitespace-insensitive because the cut points differ: each span is trimmed, so a
      # boundary that falls mid-sentence for one edition falls between sentences for the
      # other. The words are the same words in the same order, which is the claim.
      words = fn spans -> spans |> Enum.map_join(& &1.text) |> String.replace(~r/\s/u, "") end

      assert words.(by_toh["toh507"]) == words.(by_toh["toh883"])
    end

    test "and cuts it differently, because the leaves fall in different places", %{
      parsed: parsed
    } do
      {:ok, split} = Folios.split(parsed)

      by_toh = Enum.group_by(split.spans, & &1.toh)

      assert Enum.map(by_toh["toh507"], & &1.folio) == ["1b", "2a"]
      assert Enum.map(by_toh["toh883"], & &1.folio) == ["123a", "123b"]
    end

    test "a reference belongs to the location whose folios it falls among", %{parsed: parsed} do
      {:ok, split} = Folios.split(parsed)

      for span <- split.spans do
        assert span.volume == if(span.toh == "toh507", do: 88, else: 101)
      end
    end

    test "a reference that fits neither is counted, not guessed at" do
      {:ok, split} =
        [location("toh507", 88, 2, 14), location("toh883", 101, 243, 255)]
        |> parsed([{:folio, "F.900.a"}, {:text, "belongs to neither"}])
        |> Folios.split()

      assert split.unplaced == 1
      assert split.spans == []
    end
  end
end
