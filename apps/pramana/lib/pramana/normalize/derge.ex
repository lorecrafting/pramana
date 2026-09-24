defmodule Pramana.Normalize.Derge do
  @moduledoc """
  Normalizes the Digital Derge Kangyur TEI into `Pramana.Normalize.IR`.

  The Derge Kangyur is 103 printed volumes, and the etext ships one XML file per volume.
  **A volume is not a work.** Texts are delimited by markers *inside* the file:

      <tei:p n="2" data-orig-n="1b">
        <tei:milestone unit="line" n="1"/>
        <tei:milestone unit="text" toh="1"/>
        ༄༅༅། །རྒྱ་གར་སྐད་དུ། བི་ན་ཡ་བསྟུ།…

  So one file yields dozens of works, and the whole 103-file edition yields **1,125**.
  This is `docs/RULES.md` rule 23 seen from the other side: there, ten Pāli suttas
  shared one JSON file and taking the work id from the filename collapsed ten passages
  onto one address. Here the mismatch runs the other way and the fix is the same — take
  the work id from what the source itself **cites**, which for Tibetan is the Tōhoku
  number.

  ## The citation anchor is in the markup already

  `data-orig-n="1b"` is the folio — leaf 1, verso — and `<milestone unit="line" n="3"/>`
  the line printed on it, so a passage is addressed `1b.3`. That is how Tibetanists
  cite, and it is the same bargain the Taishō segmenter strikes with page-register-line
  (`CLAUDE.md` invariant #2): adopt the edition's own reference system, never invent one.

  Folio numbering **restarts at `1a` in every volume**, so the volume is part of the
  anchor: `2.5b.3` is volume 2, folio 5 verso, line 3. Tibetanists cite that way anyway
  ("D 1, vol. 2, f. 5b.3"), and without it a work spanning volumes addresses two
  different lines as `1b.1`.

  ## One work spans many volumes, and only the first one says so

  The `toh` marker appears **once**, where the text begins. The Vinaya runs from volume 1
  to volume 13 and the Prajñāpāramitā across a dozen more, and their continuation volumes
  carry no marker at all — **26 of the 103 files contain not one**.

  So `normalize_file/2` takes the work in progress and returns the work still in progress
  at the end, and volumes must be fed in order. The first version treated "no marker yet"
  as front matter and dropped it, which silently discarded 146,962 lines — 31% of the
  edition — while every other number looked healthy. A volume that yields zero works is
  the signal, and it is now an explicit `:continuing` argument rather than an assumption.

  ## Volume 103 is the catalogue, and it lies about what it contains

  The last volume is the *dkar chag*, the edition's own index. Eight `toh` markers
  appear there as well as in the text volumes, sitting on titles in a running list:
  Toh 539 in the catalogue is `ཕྱག་དང་།` — "homage, and". Treating those as work
  boundaries produces eight extra works that are a few words long, look plausible, and
  collide on the URN with the real text.

  The distinction is not a guess. Measured across the edition:

      volume 103        median    24 characters between markers
      every other      median 7,804

  So the catalogue is normalized as **one work in its own right** — it is a real text of
  the Kangyur — with the markers inside it recorded as references rather than divisions.
  `mode: :catalogue` selects that, and the ingest task holds the volume number, because
  which volume is the dkar chag is a fact about the edition rather than about the markup.
  """

  @behaviour Pramana.Pipeline.Normalizer
  @behaviour Saxy.Handler

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  # ༄༅། །འདུལ་བ་ཀ་བཞུགས་སོ། ། [1] — the volume names itself on its own title page.
  @volume_in_title ~r/<(?:\w+:)?title[^>]*>[^<]*\[(\d+)\]/

  @doc """
  The printed volume number, read off the volume's own title page.

  The volume is not otherwise in the markup in a form worth trusting, and it is required
  for every anchor, because folio numbering restarts at `1a` in each one. The alternative
  is to take it from the file's position in a directory listing — but the filenames are
  BDRC image-group ids (`UT4CZ5369-I1KG9127`), not volume numbers, and they sort into the
  right order by coincidence of issue date. Feeding the volumes out of order does not
  error: it silently mislabels every anchor in the edition, and the works that span
  volumes come out interleaved.

  All 103 volumes of the Digital Derge Kangyur carry it, and it agrees with their sort
  order in every case — which is worth knowing, and is not worth assuming.
  """
  @spec volume_number(binary()) :: {:ok, pos_integer()} | :error
  def volume_number(xml) when is_binary(xml) do
    case Regex.run(@volume_in_title, xml) do
      [_, number] -> {:ok, String.to_integer(number)}
      nil -> :error
    end
  end

  @doc """
  Normalizes one Derge volume into **one IR per Tōhoku work**.

  Options:

    * `:volume` — the printed volume number, required; it is not in the markup in a form
      worth trusting
    * `:continuing` — the Tōhoku number in progress when this volume opens, from the
      previous volume's return value
    * `:mode` — `:texts` (default) splits on `toh` markers; `:catalogue` emits the file
      as a single work and records the markers as references

  Returns `{:ok, irs, continuing}`, where `continuing` is the work still open at the end
  of the volume — feed it to the next one.
  """
  @spec normalize_file(binary() | Enumerable.t(), keyword()) ::
          {:ok, [IR.t()], String.t() | nil} | {:error, term()}
  def normalize_file(xml, opts) do
    volume = Keyword.fetch!(opts, :volume)
    mode = Keyword.get(opts, :mode, :texts)

    state = %{
      folio: nil,
      line: nil,
      # The work already in progress when this volume opens. nil only for the first
      # volume, and for a volume that genuinely starts a text.
      toh: opts |> Keyword.get(:continuing) |> to_toh(),
      buffer: [],
      lines: [],
      title: nil,
      in_title?: false,
      # Everything outside <text> is the library's description of the book, not the book.
      in_text?: false,
      rid: nil,
      mode: mode
    }

    with {:ok, parsed} <- parse(xml, state) do
      final = flush(parsed)
      {:ok, build(final, volume, mode), work_id(final.toh)}
    end
  end

  @impl Pramana.Pipeline.Normalizer
  @doc """
  One work out of a volume, by Tōhoku number.

  The behaviour is single-IR because most sources are one file per text. Derge is not,
  so the honest implementation selects rather than pretends: it normalizes the volume
  and returns the work asked for, or says the volume does not contain it.
  """
  @spec normalize(binary() | Enumerable.t(), keyword()) :: {:ok, IR.t()} | {:error, term()}
  def normalize(xml, opts) do
    work_id = Keyword.fetch!(opts, :work_id)

    with {:ok, irs, _continuing} <- normalize_file(xml, opts) do
      case Enum.find(irs, &(&1.work_id == work_id)) do
        nil -> {:error, {:work_not_in_volume, work_id}}
        ir -> {:ok, ir}
      end
    end
  end

  # `:continuing` is threaded from the previous volume's return value, so both ends
  # speak work ids. Accepting the bare Toh number too costs nothing and stops
  # `continuing: "toh1"` from quietly becoming work `tohtoh1` — which is not an error
  # anywhere, just a work nobody will ever look up.
  defp to_toh(nil), do: nil
  defp to_toh("toh" <> toh), do: toh
  defp to_toh(toh), do: toh

  defp work_id(nil), do: nil
  defp work_id(toh), do: "toh" <> toh

  defp parse(xml, state) when is_binary(xml), do: Saxy.parse_string(xml, __MODULE__, state)
  defp parse(stream, state), do: Saxy.parse_stream(stream, __MODULE__, state)

  @impl Saxy.Handler
  def handle_event(:start_document, _prolog, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:end_document, _data, state), do: {:ok, state}

  @impl Saxy.Handler
  def handle_event(:start_element, {name, attrs}, state) do
    {:ok, start(local(name), Map.new(attrs), state)}
  end

  @impl Saxy.Handler
  def handle_event(:end_element, name, state) do
    {:ok, finish(local(name), state)}
  end

  @impl Saxy.Handler
  def handle_event(:characters, text, %{in_title?: true} = state),
    do: {:ok, %{state | title: (state.title || "") <> text}}

  # The teiHeader describes the book; it is not the book. Every volume's
  # `<publicationStmt>` carries a 416-byte distributor note, and buffering it made that
  # note the first citable line of whatever work was open when the volume began — 102 of
  # the 103 volumes, a line of Esukhia's provenance blurb addressed as canon under a URN
  # that resolves. Nothing errored: it is text, in a text, with an anchor. The anchor was
  # the only tell, `2..`, because no folio had been read yet.
  def handle_event(:characters, _text, %{in_text?: false} = state), do: {:ok, state}

  def handle_event(:characters, text, state),
    do: {:ok, %{state | buffer: [text | state.buffer]}}

  # The TEI here is namespace-prefixed (`tei:p`), and Saxy reports names verbatim.
  defp local(name), do: name |> String.split(":") |> List.last()

  # A new folio. Emitting the buffer here rather than at the next line milestone is what
  # keeps the last line of a page attached to that page.
  defp start("p", attrs, state) do
    state = flush(state)
    %{state | folio: attrs["data-orig-n"] || attrs["n"], line: 1}
  end

  defp start("milestone", %{"unit" => "line"} = attrs, state) do
    state = flush(state)
    %{state | line: to_int(attrs["n"]) || (state.line || 0) + 1}
  end

  # A work boundary — or, in the catalogue, a reference to one. Either way the text
  # before it belongs to whatever came before.
  defp start("milestone", %{"unit" => "text"} = attrs, %{mode: :texts} = state) do
    state = flush(state)
    %{state | toh: attrs["toh"]}
  end

  defp start("milestone", %{"unit" => "text"}, state), do: state
  defp start("title", _attrs, state), do: %{state | in_title?: true}
  defp start("text", _attrs, state), do: %{state | in_text?: true}
  defp start(_name, _attrs, state), do: state

  defp finish("title", state), do: %{state | in_title?: false}
  defp finish("p", state), do: flush(state)
  defp finish(_name, state), do: state

  # Moves the accumulated characters onto the line list, tagged with the folio, line and
  # work they were read under. Whitespace-only buffers are dropped: the TEI is indented,
  # and an "empty line" would become a citable segment addressing nothing.
  defp flush(%{buffer: []} = state), do: state

  defp flush(state) do
    text = state.buffer |> Enum.reverse() |> Enum.join() |> String.trim()

    if text == "" do
      %{state | buffer: []}
    else
      line = %{toh: state.toh, folio: state.folio, line: state.line, text: text}
      %{state | buffer: [], lines: [line | state.lines]}
    end
  end

  defp to_int(nil), do: nil

  defp to_int(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp build(state, volume, :catalogue) do
    [
      ir("dkar-chag-#{volume}", state, volume,
        title: state.title,
        references: state.lines |> Enum.map(& &1.toh) |> Enum.reject(&is_nil/1) |> Enum.uniq()
      )
    ]
  end

  defp build(state, volume, :texts) do
    state.lines
    |> Enum.reverse()
    # Text before the first marker is the volume's own front matter — a title page, not
    # part of Toh 1. Dropping it loses nothing citable and keeps a work from starting a
    # folio too early.
    |> Enum.reject(&is_nil(&1.toh))
    |> Enum.chunk_by(& &1.toh)
    |> Enum.group_by(&hd(&1).toh)
    |> Enum.map(fn {toh, chunks} ->
      ir(work_id(toh), %{state | lines: Enum.concat(chunks)}, volume, title: nil)
    end)
    |> Enum.sort_by(& &1.work_id)
  end

  # Three anchors in the whole edition — 461,414 lines — are printed twice: two folios
  # carry a repeated line number, and one line is duplicated verbatim in the etext. These
  # are artefacts of the source, not of this parser.
  #
  # Neither dropping the second nor silently merging is acceptable: one loses text, the
  # other makes two different passages one. So the repeat keeps the printed anchor with a
  # `+2` appended, which is visibly not a folio reference — a reader who sees it knows
  # the edition is ambiguous there rather than being handed a citation that looks clean
  # and does not resolve.
  defp disambiguate(lines) do
    lines
    |> Enum.map_reduce(%{}, fn line, seen ->
      case Map.get(seen, line.anchor, 0) do
        0 -> {line, Map.put(seen, line.anchor, 1)}
        n -> {%{line | anchor: "#{line.anchor}+#{n + 1}"}, Map.put(seen, line.anchor, n + 1)}
      end
    end)
    |> elem(0)
  end

  defp ir(work_id, state, volume, opts) do
    lines =
      state.lines
      |> List.wrap()
      |> then(fn ls -> if Keyword.has_key?(opts, :references), do: Enum.reverse(ls), else: ls end)
      |> Enum.map(fn line ->
        %Line{anchor: "#{volume}.#{line.folio}.#{line.line}", text: line.text, kind: :prose}
      end)
      |> disambiguate()

    %IR{
      work_id: work_id,
      canon: "D",
      volume: volume,
      number: work_id,
      title_original: opts[:title] && String.trim(opts[:title]),
      lines: lines,
      outline: []
    }
  end
end
