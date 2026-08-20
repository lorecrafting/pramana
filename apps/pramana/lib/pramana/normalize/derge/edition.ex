defmodule Pramana.Normalize.Derge.Edition do
  @moduledoc """
  Walks the 103 volumes of the Derge Kangyur in order and emits **whole works**.

  `Pramana.Normalize.Derge` normalizes one volume. That is not the unit anyone cites,
  because a work runs across volumes — the Vinaya over thirteen, the Śatasāhasrikā over
  twelve — and only the volume where it begins carries its `toh` marker. This module is
  the fold that turns per-volume output into per-work output, and it exists as its own
  module rather than as private functions in the ingest task because the two mistakes it
  prevents are both silent.

  ## Why the merge is not optional

  `Pramana.Corpus.Loader.load/2` is idempotent by design: loading a text replaces its
  segments. So loading a spanning work once per volume does not accumulate it — **each
  volume deletes the last one's segments**, and Toh 1 ends up holding volume 13 and
  nothing else. Twelve volumes of Vinaya would vanish into a text that looks complete,
  reports a plausible length, and resolves every URN it contains. The work is therefore
  assembled here and loaded once, when the edition moves past it.

  ## A volume that emits nothing is an error, not a quiet zero

  The first version of the normalizer treated "no `toh` marker seen yet" as front matter
  and dropped it, which discarded 146,962 lines — 31% of the edition — while every
  number it reported stayed healthy (`docs/STATUS.md`). 26 of the 103 files contain no
  marker at all, and the symptom in all 26 was the same: a volume that produced nothing.
  So that is checked here, per volume, as `{:error, {:empty_volume, n}}`. A three-line
  guard against a bug that took a count taken from the source to find.

  ## The catalogue volume is walked, not threaded

  Volume 103 is the *dkar chag* and is normalized whole (`mode: :catalogue`). It is not
  a continuation of volume 102 and does not open a work for volume 104 — there is no
  volume 104 — so the work in progress passes over it untouched and is emitted at the
  end of the edition.
  """

  alias Pramana.Normalize.Derge
  alias Pramana.Normalize.Derge.Audit
  alias Pramana.Normalize.IR

  @typedoc "A volume of the edition: its printed number and its TEI, as a binary or stream."
  @type volume :: {pos_integer(), binary() | Enumerable.t()}

  @typedoc "What the walk found, for the ingest report and for anyone checking the totals."
  @type stats :: %{
          volumes: non_neg_integer(),
          works: non_neg_integer(),
          lines: non_neg_integer(),
          spanning: non_neg_integer(),
          empty: non_neg_integer()
        }

  @doc """
  Reduces over the edition, calling `fun` once per **complete** work.

  `fun` receives the work and the accumulator and returns the new accumulator, the same
  shape as `Enum.reduce/3` — a work is a database write here and a list entry in the
  tests, and neither needs a process to hold the result.

  Volumes **must** be given in printed order; the whole mechanism is that the work open
  at the end of one is the work open at the start of the next. Pass a stream to keep one
  volume in memory at a time.

  Options:

    * `:catalogue_volumes` — volume numbers to normalize as a single work rather than
      splitting on `toh` markers. Defaults to `[103]`, the *dkar chag*. Which volume that
      is, is a fact about the edition, so it lives with the caller and not in the markup.
    * `:normalizer` — the module that reads one volume. Defaults to
      `Pramana.Normalize.Derge`, the Kangyur's TEI; the Tengyur is published as annotated
      plain text and reads through `Pramana.Normalize.DergeTengyur`. Everything else here
      — the continuation threading, the spanning works, the empty-volume guard — is about
      how an EDITION is put together and is the same for both halves of the canon.
  """
  @spec reduce(Enumerable.t(), acc, (IR.t(), acc -> acc), keyword()) ::
          {:ok, acc, stats()} | {:error, term()}
        when acc: term()
  def reduce(volumes, acc, fun, opts \\ []) when is_function(fun, 2) do
    catalogue = Keyword.get(opts, :catalogue_volumes, [103])
    normalizer = Keyword.get(opts, :normalizer, Derge)
    state = {nil, nil, %{volumes: 0, works: 0, lines: 0, spanning: MapSet.new(), empty: 0}, acc}

    volumes
    |> Enum.reduce_while(state, fn volume, state ->
      step(volume, state, fun, {catalogue, normalizer})
    end)
    |> finish(fun)
  end

  @doc "The same walk, collecting the works into a list. For tests and small editions."
  @spec works([volume()], keyword()) :: {:ok, [IR.t()], stats()} | {:error, term()}
  def works(volumes, opts \\ []) do
    case reduce(volumes, [], fn ir, acc -> [ir | acc] end, opts) do
      {:ok, collected, stats} -> {:ok, Enum.reverse(collected), stats}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  The printed volumes a work was drawn from, in order.

  Read off the anchors rather than tracked alongside them, because the anchor is where
  the volume is load-bearing: `2.5b.3` says volume 2 in the citation itself, so a work's
  volume list cannot drift out of agreement with its own addresses. `mix pramana.verify`
  uses this to find the files a text must be re-derived from.
  """
  @spec volumes(IR.t()) :: [pos_integer()]
  def volumes(%IR{lines: lines}) do
    lines
    |> Enum.map(&volume_of(&1.anchor))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp volume_of(anchor) do
    case anchor |> String.split(".") |> hd() |> Integer.parse() do
      {volume, ""} -> volume
      _ -> nil
    end
  end

  @doc """
  Finds the volumes of an unpacked edition, in printed order.

  The order comes from the number each volume prints on its own title page, never from
  the directory listing: the directory names are BDRC image-group ids. Gaps and
  duplicates are refused rather than reported, because neither raises on its own — a
  missing volume silently truncates every work that spans it, and a duplicate doubles one.
  """
  @spec volumes_at(Path.t()) :: {:ok, [{pos_integer(), Path.t()}]} | {:error, term()}
  def volumes_at(root) do
    root
    |> Path.join("**/*.xml")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, []}, fn path, {:ok, acc} ->
      case path |> header() |> Derge.volume_number() do
        {:ok, volume} -> {:cont, {:ok, [{volume, path} | acc]}}
        :error -> {:halt, {:error, {:volume_unnamed, path}}}
      end
    end)
    |> case do
      {:ok, []} -> {:error, {:no_volumes_at, root}}
      {:ok, found} -> contiguous(Enum.sort_by(found, &elem(&1, 0)))
      error -> error
    end
  end

  # The title is in the header, within the first kilobyte of every volume in the edition;
  # reading a fixed prefix keeps discovery cheap over 336 MB.
  defp header(path), do: File.open!(path, [:read, :binary], &IO.binread(&1, 8192))

  defp contiguous(volumes) do
    numbers = Enum.map(volumes, &elem(&1, 0))
    expected = Enum.to_list(1..length(numbers)//1)

    if numbers == expected,
      do: {:ok, volumes},
      else:
        {:error, {:volumes_not_contiguous, expected -- numbers, numbers -- Enum.uniq(numbers)}}
  end

  @doc """
  Re-derives one work from the volumes it was drawn from, for `mix pramana.verify`.

  The threading matters and is not symmetrical. The **first** volume is normalized with
  no continuation, because the lines before this work's marker belong to the work before
  it — passing the work id there would swallow the tail of the previous text. Every
  volume after it is normalized *as* a continuation, because that is the only reason its
  lines belong to this work at all.
  """
  @spec reproduce([volume()], String.t(), keyword()) :: {:ok, IR.t()} | {:error, term()}
  def reproduce(volumes, work_id, opts \\ []) do
    normalizer = Keyword.get(opts, :normalizer, Derge)
    mode = if String.starts_with?(work_id, "dkar-chag-"), do: :catalogue, else: :texts

    volumes
    |> Enum.reduce_while({:ok, nil}, fn {volume, source}, {:ok, acc} ->
      opts = [volume: volume, mode: mode, continuing: acc && work_id]

      case normalizer.normalize_file(source, opts) do
        {:ok, irs, _returned} -> select(irs, acc, work_id, volume)
        {:error, reason} -> {:halt, {:error, {volume, reason}}}
      end
    end)
    |> case do
      {:ok, nil} -> {:error, {:no_volumes, work_id}}
      result -> result
    end
  end

  defp select(irs, acc, work_id, volume) do
    case Enum.find(irs, &(&1.work_id == work_id)) do
      nil -> {:halt, {:error, {:work_absent_from_volume, work_id, volume}}}
      ir -> {:cont, {:ok, if(acc, do: merge(acc, ir), else: ir)}}
    end
  end

  @typedoc "One volume's side of the fidelity check, in non-whitespace bytes."
  @type reconciliation :: %{
          volume: pos_integer(),
          source_bytes: non_neg_integer(),
          walked_bytes: non_neg_integer(),
          dropped: integer(),
          allowed: non_neg_integer()
        }

  @doc """
  Checks the walk against the edition, byte for byte, volume by volume.

  Counts every non-whitespace byte inside `<text>` with `Pramana.Normalize.Derge.Audit` —
  which knows nothing about folios, markers or works — and compares it with what the walk
  attributed to each volume. This is the check the walk cannot do for itself: its own
  totals are all downstream of its own assumptions, and when those were wrong they agreed
  with each other perfectly while a third of the edition was missing.

  **Only the first volume may drop anything, and only its preamble.** Text before a
  volume's first `toh` marker belongs to no work — but every volume after the first opens
  with a work already running into it from the volume before, so there is nothing there to
  be homeless. A later volume dropping its preamble is precisely the shape of the bug that
  discarded 146,962 lines: the 26 volumes with no marker at all were read as one long
  preamble and thrown away.

  Reads each file twice, once per count. That is the point — one pass, two independent
  answers.
  """
  @spec reconcile([{pos_integer(), Path.t()}]) ::
          {:ok, [reconciliation()]} | {:error, term()}
  def reconcile(files, opts \\ []) do
    with {:ok, source} <- census(files),
         {:ok, walked, _stats} <- reduce(read(files), %{}, &tally/2, opts) do
      first = files |> Enum.map(&elem(&1, 0)) |> Enum.min()

      {:ok,
       Enum.map(files, fn {volume, _path} ->
         %{text_bytes: text_bytes, preamble_bytes: preamble} = source[volume]
         walked_bytes = Map.get(walked, volume, 0)

         %{
           volume: volume,
           source_bytes: text_bytes,
           walked_bytes: walked_bytes,
           dropped: text_bytes - walked_bytes,
           allowed: if(volume == first, do: preamble, else: 0)
         }
       end)}
    end
  end

  defp census(files) do
    Enum.reduce_while(files, {:ok, %{}}, fn {volume, path}, {:ok, acc} ->
      case path |> File.stream!(2048) |> Audit.census() do
        {:ok, census} -> {:cont, {:ok, Map.put(acc, volume, census)}}
        {:error, reason} -> {:halt, {:error, {volume, reason}}}
      end
    end)
  end

  defp read(files), do: Stream.map(files, fn {volume, path} -> {volume, File.read!(path)} end)

  # Which volume a line came from is in its own anchor, so a work spanning thirteen of
  # them lands its lines in thirteen buckets without anyone tracking that separately.
  defp tally(ir, acc) do
    Enum.reduce(ir.lines, acc, fn line, acc ->
      case volume_of(line.anchor) do
        nil -> acc
        volume -> Map.update(acc, volume, bytes(line.text), &(&1 + bytes(line.text)))
      end
    end)
  end

  defp bytes(text), do: byte_size(String.replace(text, ~r/\s/u, ""))

  defp step({volume, source}, state, fun, {catalogue, normalizer}) do
    {continuing, open, stats, acc} = state
    mode = if volume in catalogue, do: :catalogue, else: :texts

    opts = [volume: volume, mode: mode, continuing: threaded(mode, continuing)]

    # A volume whose FILE is empty is a fact about the release, not a parse that lost
    # something: Esukhia ships the Tengyur's catalogue volume as a name with no
    # transcription. Counted and skipped, while a volume that HAS bytes and yields nothing
    # still halts — that was the signature of the bug this guard was built for, and an
    # empty input cannot have that failure.
    if empty_source?(source) do
      {:cont, {continuing, open, %{stats | empty: stats.empty + 1}, acc}}
    else
      normalize(normalizer, source, opts, {volume, mode}, state, fun)
    end
  end

  defp empty_source?(source) when is_binary(source), do: String.trim(source) == ""
  defp empty_source?(_source), do: false

  defp normalize(normalizer, source, opts, {volume, mode}, state, fun) do
    case normalizer.normalize_file(source, opts) do
      {:ok, irs, returned} -> advance(irs, {volume, mode, returned}, state, fun)
      {:error, reason} -> {:halt, {:error, {volume, reason}}}
    end
  end

  # No works at all, or works with no lines: both are the signature of the bug that hid a
  # third of the edition, and `Enum.all?/2` over `[]` catches the first.
  defp advance(irs, {volume, mode, returned}, {continuing, open, stats, acc}, fun) do
    if Enum.all?(irs, &(&1.lines == [])) do
      {:halt, {:error, {:empty_volume, volume}}}
    else
      # The catalogue neither continues the previous volume nor opens the next one.
      continuing = if mode == :catalogue, do: continuing, else: returned
      {open, stats, acc} = drain(irs, open, continuing, fun, stats, acc)
      {:cont, {continuing, open, %{stats | volumes: stats.volumes + 1}, acc}}
    end
  end

  defp threaded(:catalogue, _continuing), do: nil
  defp threaded(:texts, continuing), do: continuing

  # The work carried in from earlier volumes is merged with this volume's continuation of
  # it, then whatever is complete is emitted and at most one work stays open.
  defp drain(irs, open, still_open, fun, stats, acc) do
    {irs, open, stats} = absorb(irs, open, stats)

    # Carried, but this volume did not continue it: the work ended exactly on the volume
    # boundary. It is complete.
    {stats, acc, open} =
      if open && Enum.all?(irs, &(&1.work_id != open.work_id)) do
        {stats, acc} = emit(open, fun, stats, acc)
        {stats, acc, nil}
      else
        {stats, acc, open}
      end

    Enum.reduce(irs, {open, stats, acc}, fn ir, {open, stats, acc} ->
      if ir.work_id == still_open do
        {ir, stats, acc}
      else
        {stats, acc} = emit(ir, fun, stats, acc)
        {open, stats, acc}
      end
    end)
  end

  defp absorb(irs, nil, stats), do: {irs, nil, stats}

  defp absorb(irs, open, stats) do
    case Enum.split_with(irs, &(&1.work_id == open.work_id)) do
      {[], _} ->
        {irs, open, stats}

      {[continuation], rest} ->
        {[merge(open, continuation) | rest], nil,
         %{stats | spanning: MapSet.put(stats.spanning, open.work_id)}}
    end
  end

  # The volume where a work BEGINS is the volume recorded on it, and its title comes from
  # there too. Every line already carries its own volume in its anchor, so nothing is
  # lost by the later volumes not being named here.
  defp merge(%IR{} = open, %IR{} = continuation) do
    %{open | lines: open.lines ++ continuation.lines}
  end

  defp emit(%IR{} = ir, fun, stats, acc) do
    {%{stats | works: stats.works + 1, lines: stats.lines + length(ir.lines)}, fun.(ir, acc)}
  end

  defp finish({:error, reason}, _fun), do: {:error, reason}

  defp finish({_continuing, nil, stats, acc}, _fun), do: {:ok, acc, done(stats)}

  # The last work of the edition is still open when the volumes run out.
  defp finish({_continuing, open, stats, acc}, fun) do
    {stats, acc} = emit(open, fun, stats, acc)
    {:ok, acc, done(stats)}
  end

  defp done(stats), do: %{stats | spanning: MapSet.size(stats.spanning)}
end
