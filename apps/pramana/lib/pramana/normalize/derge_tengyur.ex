defmodule Pramana.Normalize.DergeTengyur do
  @moduledoc """
  Normalizes the Digital Derge Tengyur into `Pramana.Normalize.IR`.

  The Tengyur is the other half of the Tibetan canon — 213 volumes of Indian commentary and
  treatise, Tōhoku 1109–4464, continuing without a gap from the Kangyur's 1108. Esukhia
  publishes it in two formats and **only one of them can be cited**:

      UT23703 (TEI, 2020-01)     213 volumes, folio and line markup, and NOT ONE work
                                 marker in any of them — checked all 212 files in the
                                 release; zero `unit="text"` milestones, no `toh`
                                 attribute anywhere
      plain text (2019-05)       the same text with `{D1109}` where each work begins

  So the TEI, which would have reused the Kangyur's normalizer unchanged, produces a corpus
  in which no Tengyur text can be addressed by the number the field cites it by. The plain
  text is messier and is the only one that answers "where does Toh 4346 start", so it is
  what this reads.

  ## The format, and what is kept

      [1b]                 a folio header, carrying no text
      [1b.1]               folio and line, the anchor — same shape the Kangyur prints
      {D1109}              this work begins here, mid-line if that is where it begins
      {archaic,modern}     the spelling printed, and Esukhia's normalisation of it
      (printed,suggested)  a suspected error, and the correction proposed
      [bracketed]          printed but doubtful, or untranscribable
      #                    where a note of the Pedurma comparative edition attaches

  **What the woodblock prints is what enters the text.** The archaic spelling, the
  suspected error and the doubtful reading all stay; the editors' corrections go to the
  apparatus beside them, exactly as `<lem>` and `<rdg>` do for the Taishō. A normalizer
  that silently accepted every proposed correction would produce a text no printed edition
  contains, and the citations would resolve anyway.

  The `#` marks are not text and are removed — but one apparatus entry is recorded for
  each, so the count is checkable against the source rather than being a silent deletion.
  """

  alias Pramana.Normalize.IR
  alias Pramana.Normalize.IR.Line

  # `[1b.1]` or `[355xb.7]` — the same folio grammar the Kangyur uses, including the `x`
  # of an inserted leaf.
  @anchor ~r/^\[(?<folio>\d+x?[ab]?)(?:\.(?<line>\d+))?\]/

  # `{D1109}` and `{D7a}`: the rKTs convention for a text absent from the Tōhoku catalogue
  # is the preceding number with a letter, and it is a real work either way.
  @work ~r/\{D(?<toh>\d+[a-z]?)\}/

  @doc """
  The volumes of an unpacked Tengyur, in printed order.

  The number is in the filename — `001_བསྟོད་ཚོགས།_ཀ.txt` — because this format has no
  header to carry it. Checked for gaps and duplicates for the same reason the Kangyur's
  discovery is: the walk threads a work from one volume into the next, and a missing
  volume truncates every work that spans it without erroring.
  """
  @spec volumes_at(Path.t()) :: {:ok, [{pos_integer(), Path.t()}]} | {:error, term()}
  def volumes_at(root) do
    found =
      root
      |> Path.join("*.txt")
      |> Path.wildcard()
      |> Enum.flat_map(fn path ->
        case Regex.run(~r/^(\d+)_/, Path.basename(path)) do
          [_, number] -> [{String.to_integer(number), path}]
          nil -> []
        end
      end)
      |> Enum.sort_by(&elem(&1, 0))

    numbers = Enum.map(found, &elem(&1, 0))
    expected = Enum.to_list(1..max(length(numbers), 1)//1)

    cond do
      found == [] -> {:error, {:no_volumes_at, root}}
      numbers != expected -> {:error, {:volumes_not_contiguous, expected -- numbers, []}}
      true -> {:ok, found}
    end
  end

  @doc """
  Normalizes one volume into **one IR per Tōhoku work**.

  Same contract as `Pramana.Normalize.Derge.normalize_file/2`, so
  `Pramana.Normalize.Derge.Edition` walks either canon: takes the work in progress, returns
  the work still open at the end of the volume.

  Options:

    * `:volume` — the printed volume number, required
    * `:continuing` — the work open when this volume begins
  """
  @spec normalize_file(binary() | Enumerable.t(), keyword()) ::
          {:ok, [IR.t()], String.t() | nil} | {:error, term()}
  def normalize_file(text, opts) do
    volume = Keyword.fetch!(opts, :volume)
    continuing = opts |> Keyword.get(:continuing) |> to_toh()

    {lines, toh} =
      text
      |> lines()
      |> Enum.reduce({[], continuing}, &read_line/2)

    {:ok, build(Enum.reverse(lines), volume), work_id(toh)}
  end

  defp lines(text) when is_binary(text), do: String.split(text, ~r/\r?\n/)
  defp lines(stream), do: stream |> Enum.to_list() |> Enum.join() |> lines()

  defp to_toh(nil), do: nil
  defp to_toh("toh" <> toh), do: toh
  defp to_toh(toh), do: toh

  defp work_id(nil), do: nil
  defp work_id(toh), do: "toh" <> toh

  # A line the file begins with may carry a byte-order mark; it is not part of the folio.
  defp read_line(raw, acc), do: do_read(String.replace_prefix(raw, "﻿", ""), acc)

  defp do_read("", acc), do: acc

  defp do_read(raw, {lines, toh}) do
    case Regex.named_captures(@anchor, raw) do
      # A folio header — `[1b]` with no line number — announces the leaf and carries no
      # text of its own.
      %{"line" => ""} ->
        {lines, toh}

      %{"folio" => folio, "line" => line} ->
        rest = Regex.replace(@anchor, raw, "", global: false)
        split(rest, folio, line, {lines, toh})

      nil ->
        {lines, toh}
    end
  end

  # A work can begin part-way through a printed line, and the text before the marker
  # belongs to the work before it. Both halves keep the anchor of the line they are on,
  # which is what the page prints; they are distinguished by their work, as in the Kangyur.
  defp split(rest, folio, line, {lines, toh}) do
    case String.split(rest, @work, include_captures: true) do
      [_single] ->
        {emit(lines, rest, folio, line, toh), toh}

      parts ->
        Enum.reduce(parts, {lines, toh}, &absorb(&1, &2, folio, line))
    end
  end

  # A part is either the marker that changes which work we are in, or text belonging to
  # the work we are already in.
  defp absorb(part, {lines, toh}, folio, line) do
    case Regex.named_captures(@work, part) do
      %{"toh" => new_toh} -> {lines, new_toh}
      nil -> {emit(lines, part, folio, line, toh), toh}
    end
  end

  # A line with no printed text is not a line of this work, even when the editors left a
  # mark on it. Where one work ends and the next begins mid-line the page reads
  # `[222b.1]#{D4101}#༄༅༅།…`, so splitting on the marker hands the ENDING work a fragment
  # containing only the `#`. Emitting that produced a line with `text: ""` carrying one
  # apparatus entry: the loader refused it (a segment with no content is not citable), the
  # normalizer counted it, and `mix pramana.integrity` reported toh4100 and toh4150 each
  # missing a line the bake never should have promised. The mark annotates the printed
  # line, which belongs to the work that starts on it and records it there.
  defp emit(lines, text, folio, line, toh) do
    {clean, apparatus} = extract(text)

    if clean == "" do
      lines
    else
      [%{toh: toh, folio: folio, line: line, text: clean, apparatus: apparatus} | lines]
    end
  end

  @doc """
  Separates what the woodblock prints from what the editors say about it.

  Returns `{text, apparatus}`. The lemma is always the printed form.
  """
  @spec extract(String.t()) :: {String.t(), [map()]}
  def extract(text) do
    {text, spellings} = pairs(text, ~r/\{([^,{}]+),([^,{}]*)\}/, "modern_spelling")
    {text, corrections} = pairs(text, ~r/\(([^,()]+),([^,()]*)\)/, "correction")
    {text, notes} = pedurma(text)

    {String.trim(text), spellings ++ corrections ++ notes}
  end

  # `{archaic,modern}` and `(printed,suggested)` have the same shape and the same rule:
  # the first is on the page, the second is a proposal about it.
  defp pairs(text, regex, kind) do
    entries =
      Regex.scan(regex, text)
      |> Enum.map(fn [_, printed, proposed] ->
        %{
          "lem" => printed,
          "kind" => kind,
          "rdgs" => [%{"text" => proposed, "resp" => "esukhia"}]
        }
      end)

    {Regex.replace(regex, text, "\\1"), entries}
  end

  # The Pedurma note marks are not Tibetan and would end up inside a quoted passage. They
  # are removed and counted: a deletion nobody can check is how a normalizer loses things.
  defp pedurma(text) do
    count = text |> String.graphemes() |> Enum.count(&(&1 == "#"))
    entries = List.duplicate(%{"kind" => "pedurma_note", "lem" => nil, "rdgs" => []}, count)

    {String.replace(text, "#", ""), entries}
  end

  defp build(lines, volume) do
    lines
    |> Enum.reject(&is_nil(&1.toh))
    |> Enum.group_by(& &1.toh)
    |> Enum.map(fn {toh, group} -> ir(work_id(toh), group, volume) end)
    |> Enum.sort_by(& &1.work_id)
  end

  defp ir(work_id, lines, volume) do
    %IR{
      work_id: work_id,
      canon: "D",
      volume: volume,
      number: work_id,
      lines: lines |> Enum.map(&line(&1, volume)) |> disambiguate(),
      outline: []
    }
  end

  defp line(line, volume) do
    %Line{
      anchor: "#{volume}.#{line.folio}.#{line.line}",
      text: line.text,
      kind: :prose,
      apparatus: line.apparatus
    }
  end

  # The same repeated-anchor rule the Kangyur needed: a line printed twice under one
  # address keeps the address with `+2` appended, which is visibly not a folio reference.
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
end
