defmodule Pramana.Normalize.Tei84000.Folios do
  @moduledoc """
  Cuts an 84000 translation into folio-sized spans, one partition per Degé location.

  `Pramana.Normalize.Tei84000` returns the English as a flat run of text, folio references
  and volume references in document order. This turns that into spans — the text of folio
  123a, the text of folio 123b — which is the grain at which the translation can be
  attached to the Tibetan, because it is the grain 84000 marks. **Our Derge anchors are
  lines and 84000's are folios**, so a span covers several lines and is anchored to the
  range of them, never to one line as though it rendered only that.

  ## The folio is taken as printed, and never computed

  `<location>` carries image-page numbers that look like they could produce the folio
  arithmetically — page 2 is folio 1b — and for most texts they agree with the reference
  in the body. Where they disagree the body is right: Toh 883's pages say folio 122a and
  its references say 123a, and 123a is where our Derge etext has it.

  So the number in the reference is used and nothing is derived from the page range except
  which `<bibl>` a reference belongs to when a file renders two places at once. A span
  whose folio the Tibetan text does not contain is **dropped by the caller**, not
  massaged into one that resolves. Toh 11 is the case that makes this a rule: 84000
  numbers its folios from the work's own beginning in the second volume, `F.92.b` where
  the Degé prints `1a`, and any offset that made those anchor would be an assertion about
  which line renders which — invented, plausible, and unfalsifiable after the fact.

  ## Which location a reference belongs to

  A file that renders two places in the canon interleaves their references, so each has to
  be attributed before the text can be cut. Three things do it:

    * an explicit `<ref type="volume" cRef="V32"/>`, where the file bothers to mark the
      crossing — only 33 do;
    * a folio number that goes **backwards**, which within one Tōhoku number means the
      next volume has begun. The Śatasāhasrikā restarts at 1b twelve times and marks
      eight of them;
    * the location's page span, which is only needed to tell one `<bibl>` from another —
      `F.1.b` in volume 88 from `F.123.a` in volume 101 — and is given a folio of
      tolerance because that is how far off it can be.
  """

  alias Pramana.Normalize.Tei84000

  @typedoc "One folio's worth of English, and the Degé folio it renders."
  @type span :: %{
          toh: String.t(),
          volume: pos_integer(),
          folio: String.t(),
          text: String.t()
        }

  # `F.33.a(b)` is 84000's notation for an inserted leaf; the Derge etext writes the same
  # leaf `33xa`. Four leaves in the edition are numbered that way.
  @folio ~r/^F\.(?<number>\d+)\.(?<side>[ab])(?<inserted>\(b\))?$/

  @doc """
  Splits a parsed file into spans.

  Returns `{:ok, %{spans:, unplaced:}}`, where `unplaced` counts folio references that
  could not be attributed to any location. Every one is a folio of English that is not
  stored, rather than one stored against the wrong Tibetan.
  """
  @spec split(Tei84000.t()) :: {:ok, %{spans: [span()], unplaced: non_neg_integer()}}
  def split(%{locations: locations, events: events}) do
    by_toh = Enum.group_by(locations, & &1.toh)

    cursors =
      Map.new(by_toh, fn {toh, locs} -> {toh, %{index: 0, last: nil, locations: locs}} end)

    {marked, _cursors} = Enum.map_reduce(events, cursors, &attribute/2)

    spans =
      by_toh
      |> Map.keys()
      |> Enum.flat_map(&cut(marked, &1))
      |> Enum.reject(&(&1.text == ""))

    {:ok, %{spans: spans, unplaced: Enum.count(marked, &match?({:folio, _, nil}, &1))}}
  end

  defp attribute({:text, _} = event, cursors), do: {event, cursors}

  # An explicit crossing. It names the volume, so the cursor moves to it rather than one
  # step along — a file can mark the crossing into volume 21 without having marked 18.
  defp attribute({:volume, number}, cursors) do
    case Enum.find(cursors, fn {_toh, c} -> Enum.any?(c.locations, &(&1.volume == number)) end) do
      nil ->
        {{:text, ""}, cursors}

      {toh, cursor} ->
        index = Enum.find_index(cursor.locations, &(&1.volume == number))
        {{:text, ""}, Map.put(cursors, toh, %{cursor | index: index, last: nil})}
    end
  end

  defp attribute({:folio, cref}, cursors) do
    case Regex.named_captures(@folio, cref) do
      nil ->
        {{:folio, cref, nil}, cursors}

      caps ->
        number = String.to_integer(caps["number"])
        folio = "#{number}#{if caps["inserted"] != "", do: "x", else: ""}#{caps["side"]}"
        place(number, folio, cursors)
    end
  end

  defp place(number, folio, cursors) do
    case candidate(number, cursors) do
      nil ->
        {{:folio, folio, nil}, cursors}

      {toh, cursor} ->
        cursor = advance(number, cursor)
        location = Enum.at(cursor.locations, cursor.index)

        {{:folio, folio, {toh, location.volume}}, Map.put(cursors, toh, %{cursor | last: number})}
    end
  end

  # Continuing a location is stronger evidence than merely falling inside its span, and
  # the two only disagree where spans overlap — which is exactly where a wrong choice
  # would produce an anchor that resolves to the wrong passage.
  defp candidate(number, cursors) do
    fitting = Enum.filter(cursors, fn {_toh, cursor} -> fits?(number, cursor) end)

    Enum.find(fitting, fn {_toh, cursor} -> continues?(number, cursor) end) ||
      List.first(fitting) ||
      sole(cursors)
  end

  # A file rendering one Tōhoku number has nothing to choose between, so a reference that
  # matches no page span still belongs to it — and will be dropped later if the folio it
  # names is not in the Tibetan.
  defp sole(cursors) when map_size(cursors) == 1, do: cursors |> Enum.to_list() |> hd()
  defp sole(_cursors), do: nil

  defp continues?(number, %{last: last}) when is_integer(last), do: number in [last, last + 1]
  defp continues?(_number, _cursor), do: false

  defp fits?(number, cursor) do
    location = Enum.at(cursor.locations, cursor.index)

    cond do
      location == nil -> false
      restarting?(number, cursor) -> true
      number >= folio_of(location.start_page) - 1 -> number <= folio_of(location.end_page) + 1
      true -> false
    end
  end

  # A folio number that goes backwards is the next volume of the same work. Only true
  # when there IS a next volume: in a single-volume location it means the file references
  # a folio out of order, which is not something to paper over.
  defp restarting?(number, %{last: last, index: index, locations: locations})
       when is_integer(last),
       do: number < last and index + 1 < length(locations)

  defp restarting?(_number, _cursor), do: false

  defp advance(number, cursor) do
    if restarting?(number, cursor), do: %{cursor | index: cursor.index + 1}, else: cursor
  end

  # Image page 2 is folio 1b, page 3 is folio 2a: the recto and verso of one leaf are two
  # pages of the scan.
  defp folio_of(page) when rem(page, 2) == 0, do: div(page, 2)
  defp folio_of(page), do: div(page + 1, 2)

  # One pass per Tōhoku number, keeping only its own folio boundaries. The other
  # location's references fall inside these spans and are text boundaries that close
  # nothing — the same English, cut differently for each place it is printed.
  defp cut(marked, toh) do
    {spans, open} =
      Enum.reduce(marked, {[], nil}, fn
        {:folio, folio, {^toh, volume}}, {spans, open} ->
          {close(spans, open), %{toh: toh, volume: volume, folio: folio, parts: []}}

        {:folio, _folio, _other}, acc ->
          acc

        {:text, _text}, {spans, nil} ->
          # Text before this location's first folio reference: the heading of the
          # translation, which renders no folio.
          {spans, nil}

        {:text, text}, {spans, open} ->
          {spans, %{open | parts: [text | open.parts]}}
      end)

    spans |> close(open) |> Enum.reverse()
  end

  defp close(spans, nil), do: spans

  defp close(spans, open) do
    text = open.parts |> Enum.reverse() |> Enum.join() |> squeeze()

    [%{toh: open.toh, volume: open.volume, folio: open.folio, text: text} | spans]
  end

  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()
end
