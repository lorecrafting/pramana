defmodule Pramana.Normalize.Tei84000 do
  @moduledoc """
  Reads an 84000 translation TEI: what it translates, who translated it, and the English
  itself cut at the folio boundaries of the Degé Kangyur.

  This is not a normalizer in the `Pramana.Pipeline.Normalizer` sense — it produces no
  `IR` and no citable text of its own. An 84000 file is a **rendering** of a text this
  corpus already holds in Tibetan (`docs/LAYERS.md`), so what comes out is a set of
  English spans, each keyed to the Degé folio it renders, plus the metadata that lets
  them be attributed.

  ## The join is a folio, and the folio has three witnesses in the file

  Each `<bibl>` in `<sourceDesc>` names one place in the Degé where this text is printed,
  and the body carries `<ref cRef="F.123.a" type="folio"/>` where each folio begins. Three
  fields describe that location and **each is right about a different thing**, which is
  only visible by checking all three against the Tibetan we already have:

      <biblScope>      "vol. 100 … folios 123.a–129.a"   folios right, volume WRONG
      <location>       vol 101, pages 243-255            volume right, folios off by one
      <ref cRef=…>     F.123.a … F.129.a                 the folio, as printed

  So the volume comes from `<location>` and the folio from the reference itself. Toh 883
  is in volume 101 at folio 123a in our Derge etext, and that is what those two fields
  say between them; the prose says volume 100 and the page arithmetic says folio 122a.
  Neither is a typo to be fixed — they are two different numbering conventions, and the
  only way to know which to believe was to ask the text.

  ## One file can render two places in the canon at once

  A dhāraṇī often appears twice in the Kangyur, once in its own section and once in the
  gzungs 'dus, and 84000 translates it once and anchors it in both. `toh507,883` is one
  translation with two `<bibl>`s, and its folio references **interleave** — `F.1.b`,
  `F.123.a`, `F.2.a`, `F.123.b` — because the same English is being cut at two different
  editions' page boundaries. Each `<bibl>` therefore gets its own partition of the same
  text, and a reference is assigned to the `<bibl>` whose volume and folio span contain
  it. 45 of the 396 files are like this.

  ## Notes are not the translation

  `<note>` holds the translators' endnotes — philology about the passage, not the
  passage. They are skipped, so what is stored as a rendering of a folio is what a reader
  would read as the text of that folio.
  """

  @behaviour Saxy.Handler

  @typedoc """
  One place in the Degé where the translated text is printed.

  `start_page`/`end_page` are image pages of the scanned edition, which is what
  `<location>` counts in; they bound the folio span but do not name it reliably.
  """
  @type location :: %{
          toh: String.t(),
          volume: pos_integer(),
          start_page: pos_integer(),
          end_page: pos_integer()
        }

  @type event :: {:folio, String.t()} | {:volume, pos_integer()} | {:text, String.t()}

  @type t :: %{
          locations: [location()],
          titles: %{String.t() => String.t()},
          translators: [String.t()],
          edition: String.t() | nil,
          events: [event()]
        }

  @doc """
  Parses one translation file.

  Returns the locations it renders, its titles by language, its English translators, the
  edition string (`v 1.0.7 2025`), and the body of the translation as a flat list of text
  and folio-reference events in document order. Cutting that list into spans is
  `Pramana.Normalize.Tei84000.Folios`' job, because how it is cut depends on which `<bibl>` is
  being anchored.
  """
  @spec parse(binary() | Enumerable.t()) :: {:ok, t()} | {:error, term()}
  def parse(xml) do
    state = %{
      depth: 0,
      header_depth: nil,
      translation_depth: nil,
      note_depth: nil,
      title: nil,
      titles: %{},
      bibl: nil,
      locations: [],
      translator_role: nil,
      translator: nil,
      translators: [],
      edition_depth: nil,
      edition: nil,
      events: []
    }

    with {:ok, final} <- run(xml, state) do
      {:ok,
       %{
         locations: Enum.reverse(final.locations),
         titles: final.titles,
         translators: final.translators |> Enum.reverse() |> Enum.uniq(),
         edition: final.edition && squeeze(final.edition),
         events: compact(final.events)
       }}
    end
  end

  defp run(xml, state) when is_binary(xml), do: Saxy.parse_string(xml, __MODULE__, state)
  defp run(stream, state), do: Saxy.parse_stream(stream, __MODULE__, state)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    state = %{state | depth: state.depth + 1}
    {:ok, start(local(name), Map.new(attrs), state)}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state) do
    {:ok, %{finish(local(name), state) | depth: state.depth - 1}}
  end

  @impl Saxy.Handler
  def handle_event(:characters, text, state), do: {:ok, characters(text, state)}

  defp local(name), do: name |> String.split(":") |> List.last()

  defp start("teiHeader", _attrs, state), do: %{state | header_depth: state.depth}

  # Only the header's titles. `<title>` inside a note is a journal in a citation.
  defp start("title", attrs, %{header_depth: d} = state) when not is_nil(d) do
    if attrs["type"] == "mainTitle",
      do: %{state | title: {attrs["xml:lang"], ""}},
      else: state
  end

  defp start("edition", _attrs, %{header_depth: d} = state) when not is_nil(d),
    do: %{state | edition_depth: state.depth, edition: ""}

  defp start("bibl", attrs, %{header_depth: d} = state) when not is_nil(d),
    do: %{state | bibl: attrs["key"]}

  defp start("volume", attrs, %{bibl: toh} = state) when not is_nil(toh) do
    location = %{
      toh: toh,
      volume: to_int(attrs["number"]),
      start_page: to_int(attrs["start-page"]),
      end_page: to_int(attrs["end-page"])
    }

    if location.volume && location.start_page && location.end_page,
      do: %{state | locations: [location | state.locations]},
      else: state
  end

  # The people, as the file names them. `translatorEng` is the person whose English this
  # is — the attribution the licence requires — and `translatorMain` is a sentence about
  # them ("Translated by X under the patronage of…"), which is not a name.
  defp start("author", attrs, %{header_depth: d} = state) when not is_nil(d) do
    if attrs["role"] == "translatorEng",
      do: %{state | translator_role: true, translator: ""},
      else: state
  end

  defp start("div", %{"type" => "translation"}, state),
    do: %{state | translation_depth: state.depth}

  defp start("note", _attrs, %{translation_depth: d} = state) when not is_nil(d),
    do: %{state | note_depth: state.note_depth || state.depth}

  defp start("ref", %{"type" => "folio"} = attrs, %{translation_depth: d} = state)
       when not is_nil(d) do
    case attrs["cRef"] do
      nil -> state
      cref -> %{state | events: [{:folio, cref} | state.events]}
    end
  end

  # `<ref cRef="V32" type="volume"/>` — where the text crosses into the next volume of the
  # Degé. There are only 36 in the published Kangyur and three of those name other
  # witnesses entirely (`RAS.60.a2`), so this is a hint, not a spine: most volume changes
  # are marked by nothing at all.
  defp start("ref", %{"type" => "volume"} = attrs, %{translation_depth: d} = state)
       when not is_nil(d) do
    case Regex.run(~r/^V(\d+)$/, attrs["cRef"] || "") do
      [_, number] -> %{state | events: [{:volume, String.to_integer(number)} | state.events]}
      nil -> state
    end
  end

  defp start(_name, _attrs, state), do: state

  defp finish("teiHeader", state), do: %{state | header_depth: nil}

  defp finish("title", %{title: {lang, text}} = state),
    do: %{state | title: nil, titles: Map.put(state.titles, lang || "und", squeeze(text))}

  defp finish("edition", %{edition_depth: d} = state) when d == state.depth,
    do: %{state | edition_depth: nil}

  defp finish("bibl", state), do: %{state | bibl: nil}

  defp finish("author", %{translator_role: true} = state) do
    %{state | translator_role: nil, translators: [squeeze(state.translator) | state.translators]}
  end

  defp finish("note", %{note_depth: d} = state) when d == state.depth,
    do: %{state | note_depth: nil}

  defp finish("div", %{translation_depth: d} = state) when d == state.depth,
    do: %{state | translation_depth: nil}

  defp finish(_name, state), do: state

  defp characters(text, %{title: {lang, so_far}} = state),
    do: %{state | title: {lang, so_far <> text}}

  defp characters(text, %{edition_depth: d} = state) when not is_nil(d),
    do: %{state | edition: (state.edition || "") <> text}

  defp characters(text, %{translator_role: true} = state),
    do: %{state | translator: (state.translator || "") <> text}

  defp characters(_text, %{note_depth: d} = state) when not is_nil(d), do: state

  defp characters(text, %{translation_depth: d} = state) when not is_nil(d),
    do: %{state | events: [{:text, text} | state.events]}

  defp characters(_text, state), do: state

  # Saxy reports character data in pieces; joining them here means the folio spans are
  # built from whole words rather than from parser chunks.
  defp compact(events) do
    events
    |> Enum.reverse()
    |> Enum.chunk_by(&elem(&1, 0))
    |> Enum.flat_map(fn
      [{:text, _} | _] = run -> [{:text, Enum.map_join(run, &elem(&1, 1))}]
      refs -> refs
    end)
  end

  defp squeeze(nil), do: nil
  defp squeeze(text), do: text |> String.replace(~r/\s+/u, " ") |> String.trim()

  defp to_int(nil), do: nil

  defp to_int(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end
end
