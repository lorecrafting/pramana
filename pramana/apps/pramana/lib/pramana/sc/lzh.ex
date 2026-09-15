defmodule Pramana.Sc.Lzh do
  @moduledoc """
  Anchors SuttaCentral's Chinese (`lzh`) segment ids to the CBETA lines they name.

  ## Why this exists

  This project is English-first, and one canon could not be reached that way at all:
  4,263 CBETA works had **zero** English renderings, against 5,845 for the Pāli and 472
  for the Kangyur, and that single fact was the whole of `topical/chinese` scoring 0%.
  See `docs/PLAN.md` § E1.

  bilara-data carries part of the answer and has since before this corpus existed:
  Charles Patton's translations of the Chinese Saṃyukta and Madhyama Āgamas, CC0,
  segment-aligned. They arrive keyed to SuttaCentral's own addresses — `sa379:2.2` —
  and this corpus holds those Āgamas as **CBETA**, addressed by Taishō page and line.
  Nothing joins the two, so `mix pramana.sc.translations` dropped every one of Patton's
  segments as `no_such_anchor` and nobody noticed, because that counter is also where
  the Pāli's legitimate elisions land.

  ## Anchoring to CBETA rather than loading a second Chinese text

  bilara's `root/lzh/sct` is a Chinese text, and the cheap move would be to load it as
  its own witness and hang the English off that. It is refused, because it would put a
  second copy of the Saṃyukta Āgama in the corpus and point every English reader at the
  copy that is **not** the Taishō. The whole claim of this system is that a citation can
  be checked against a print edition; an English rendering that resolves to our own
  convenience copy cannot be.

  So `root/lzh` is used as a **bridge and never stored**: it is read at ingest, matched
  against the CBETA text this corpus already holds, and what is kept is a Taishō line
  address. Invariant #5 — this is string matching, not a model.

  ## How a segment is located, and why it cannot silently land in the wrong sutta

  Both editions print the sutta number, and it is the edition's own citation grammar
  rather than anything invented here: CBETA writes `（三七九）` at the head of SĀ 379,
  digit by digit with `〇` for zero, and each of T0099's 1,350 markers and T0026's 222
  occurs exactly once. `sa379` therefore gives a **window** — from that marker to the
  next — and every segment of the sutta is matched inside it. A number that pointed at
  the wrong sutta would match nothing and the work would be dropped whole, which is the
  failure this design wants: loud.

  Within the window, segments are matched **in order and forward only**, so a stock
  phrase cannot match an earlier occurrence in a sutta already passed.

  ## Two editions of one text, and what is folded away to compare them

  `root/lzh/sct` is SAT-derived (`_publication.json`, scpub39: *"The SAT 2018 source
  texts have been corrected and re-punctuated"*), and this corpus's Āgamas are CBETA.
  The two print the same words in different Han forms — 衞/衛, 説/說, 爲/為 — and
  punctuate differently, both of which are editorial rather than textual. Comparison
  therefore folds variant classes (`Pramana.Retrieval.Variants.fold/1`) and strips
  editorial punctuation. **Nothing stored is folded**: which form an edition prints is
  evidence about its transmission, and both texts keep theirs.

  The punctuation stripped is `Pramana.Punctuation`'s, plus the four marks SuttaCentral's
  editor adds and CBETA's does not — ASCII parentheses and brackets around sutta numbers,
  `⋯` for elision, and curly quotation marks. That extra list is local to this comparison
  and deliberately not pushed into `Pramana.Punctuation`, which the citation guard uses to
  decide whether a quotation differs only in punctuation; widening it there on the
  evidence of one source would loosen a check that has nothing to do with this one.

  ## An anchor is either matched or bounded, and says which

  A segment whose text is found is anchored to the CBETA lines its characters fall in.
  A segment that is **not** found — the residue of the two editions genuinely differing,
  around 12% — is anchored to the span between its neighbours, which is not a guess: the
  segments either side matched, and order is monotonic, so the text lies between them.
  Each anchor is stamped `:exact` or `:interpolated` and the caller stores which, because
  "we found this line" and "this line is somewhere in here" are different claims and a
  reader is entitled to know which one they have.

  A segment with no matched neighbour to bound it is **dropped** and counted. Nothing is
  anchored on the strength of position alone.
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Punctuation
  alias Pramana.Repo
  alias Pramana.Retrieval.Variants
  alias Pramana.URN

  @default_root "raw/sc/bilara-data"

  # The collections whose SuttaCentral numbering has been checked against the printed
  # marker in the CBETA text this corpus holds.
  #
  # `da` (T0001) and `ea` (T0125) are deliberately absent. bilara publishes English for
  # both, but this checkout's `root/lzh` holds **no `da` file and one `ea` file**
  # (`ea19.1`, whose uid is not a bare number and which no English here covers), so
  # supporting them would be untested code serving nothing. Adding one is a line in this
  # map plus the check that its numbers are printed once — `unique_markers?/1` is that
  # check, and the window's whole guarantee rests on it.
  @collections %{"sa" => "T0099", "ma" => "T0026"}

  # SuttaCentral's editor punctuates where CBETA's does not. Derived from the residual
  # diff between the two editions over all 54 translated works, not guessed: ASCII
  # parentheses and brackets (`(三七九)` against CBETA's full-width `（三七九）`), `⋯`
  # for elision against CBETA's `…`, and curly quotation marks for speech.
  @editorial_extras ~r/[()\[\]⋯“”]/u

  @doc "The collections that can be anchored, as SuttaCentral prefix => CBETA work id."
  @spec collections() :: %{String.t() => String.t()}
  def collections, do: @collections

  @doc """
  Anchors every `root/lzh` work this corpus can place.

  Each value is `%{urn:, ordinal_start:, ordinal_end:, method: :exact | :interpolated}`.
  The ordinals are carried because `Pramana.Chunk.Vectors` builds a translation vector
  from them and cannot get them back out of a locator grammar it does not own.

  Returns `{anchors, report}`. The report carries the per-collection counts and the
  works that could not be placed at all, because a coverage figure without its
  denominator is the failure this project is most prone to.
  """
  @spec anchors(keyword()) :: {map(), map()}
  def anchors(opts \\ []) do
    root = Keyword.get(opts, :root, @default_root)
    only = Keyword.get(opts, :only)

    files =
      root
      |> Path.join("root/lzh/sct/**/*.json")
      |> Path.wildcard()
      |> Enum.sort()
      |> Enum.filter(fn file -> is_nil(only) or uid_of(file) in List.wrap(only) end)

    {anchors, report} =
      files
      |> Enum.group_by(&collection_of/1)
      |> Enum.reduce({%{}, empty_report()}, fn {collection, group}, acc ->
        anchor_collection(collection, group, acc)
      end)

    {anchors, %{report | works_seen: length(files)}}
  end

  defp anchor_collection(nil, group, {anchors, report}) do
    # bilara's lzh root also holds t765, t1536, t1537 and t1548 — abhidharma works with
    # no English in this checkout and no sutta-number grammar to window by. Counted, not
    # attempted.
    {anchors, %{report | unsupported: report.unsupported + length(group)}}
  end

  defp anchor_collection(collection, group, {anchors, report}) do
    case index(Map.fetch!(@collections, collection)) do
      {:error, reason} ->
        {anchors, add_failures(report, group, reason)}

      {:ok, index} ->
        Enum.reduce(group, {anchors, report}, &anchor_one(&1, index, &2))
    end
  end

  defp anchor_one(file, index, {anchors, report}) do
    case align_file(file, index) do
      {:ok, placed, counts} -> {Map.merge(anchors, placed), tally(report, counts)}
      {:error, reason} -> {anchors, add_failures(report, [file], reason)}
    end
  end

  @doc """
  Anchors one `root/lzh` file against the CBETA text it belongs to.

  Public because it is the unit worth testing: one file, one sutta, one window.
  """
  @spec align_file(String.t(), map()) :: {:ok, map(), map()} | {:error, term()}
  def align_file(file, index) do
    with {:ok, number} <- number_of(file),
         {:ok, window} <- window(index, number) do
      segments =
        file
        |> File.read!()
        |> Jason.decode!()
        |> Enum.reject(fn {id, _text} -> heading?(id) end)
        |> Enum.map(fn {id, text} -> {id, compare_form(text)} end)
        |> Enum.reject(fn {_id, form} -> form == "" end)
        |> Enum.sort_by(fn {id, _} -> sort_key(id) end)

      {placed, counts} = place(segments, window, index)
      {:ok, placed, counts}
    end
  end

  # Matched forward-only, then bounded. Two passes rather than one because a segment's
  # bound needs the NEXT match, which a single forward pass does not have yet.
  defp place(segments, {win_start, win_end}, index) do
    {matched, _} =
      Enum.map_reduce(segments, win_start, fn {id, form}, cursor ->
        case find(index.haystack, form, cursor, win_end) do
          {:ok, from, to} -> {{id, {from, to}}, to}
          :nomatch -> {{id, nil}, cursor}
        end
      end)

    matched
    |> bound(win_start, win_end)
    |> Enum.reduce({%{}, %{exact: 0, interpolated: 0, dropped: 0}}, fn
      {_id, nil}, {placed, counts} ->
        {placed, Map.update!(counts, :dropped, &(&1 + 1))}

      {id, {span, method}}, {placed, counts} ->
        case urn_for(index, span) do
          {:ok, anchor} ->
            {Map.put(placed, id, Map.put(anchor, :method, method)),
             Map.update!(counts, method, &(&1 + 1))}

          :error ->
            {placed, Map.update!(counts, :dropped, &(&1 + 1))}
        end
    end)
  end

  # Every unmatched segment takes the span between the last match before it and the first
  # match after it. Where that span is empty — two matches touching, with an unmatched
  # segment between them — there is nowhere to put it and it is dropped rather than
  # given its neighbour's address.
  defp bound(matched, win_start, win_end) do
    afters =
      matched
      |> Enum.reverse()
      |> Enum.scan(win_end, fn
        {_id, {from, _to}}, _acc -> from
        {_id, nil}, acc -> acc
      end)
      |> Enum.reverse()
      |> Enum.drop(1)
      |> Kernel.++([win_end])

    {bounded, _} =
      matched
      |> Enum.zip(afters)
      |> Enum.map_reduce(win_start, fn
        {{id, {from, to}}, _after}, _before ->
          {{id, {{from, to}, :exact}}, to}

        {{id, nil}, aft}, before when aft > before ->
          {{id, {{before, aft}, :interpolated}}, before}

        {{id, nil}, _aft}, before ->
          {{id, nil}, before}
      end)

    bounded
  end

  defp find(haystack, needle, from, limit) do
    length = limit - from

    cond do
      length <= 0 ->
        :nomatch

      byte_size(needle) > length ->
        :nomatch

      true ->
        case :binary.match(haystack, needle, scope: {from, length}) do
          {position, size} -> {:ok, position, position + size}
          :nomatch -> :nomatch
        end
    end
  end

  @doc """
  The CBETA text of one work, normalised for comparison and indexed by byte offset.

  Built once per work and passed to every file in that collection: T0099 is 470,724
  compared characters and rebuilding it per sutta would be 39 passes over it.
  """
  @spec index(String.t()) :: {:ok, map()} | {:error, term()}
  def index(work_id) do
    segments =
      from(s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where: t.work_id == ^work_id and t.source_id == "cbeta",
        order_by: s.ordinal,
        select: {s.urn, s.content}
      )
      |> Repo.all()

    case segments do
      [] -> {:error, {:no_such_text, work_id}}
      segments -> {:ok, build_index(work_id, segments)}
    end
  end

  defp build_index(work_id, segments) do
    {entries, parts, total} =
      Enum.reduce(segments, {[], [], 0}, fn {urn, content}, {entries, parts, offset} ->
        form = compare_form(content)
        size = byte_size(form)
        {[{offset, offset + size, urn, content} | entries], [form | parts], offset + size}
      end)

    entries = Enum.reverse(entries)

    %{
      work_id: work_id,
      haystack: IO.iodata_to_binary(Enum.reverse(parts)),
      size: total,
      starts: entries |> Enum.map(fn {from, _, _, _} -> from end) |> List.to_tuple(),
      urns: entries |> Enum.map(fn {_, _, urn, _} -> urn end) |> List.to_tuple(),
      markers: markers(entries)
    }
  end

  # `（三七九）` -> the byte offset in the compared haystack where that sutta starts.
  # Taken from the UNCOMPARED content, because the comparison form strips the very
  # parentheses that make a number a marker rather than a number in the text.
  defp markers(entries) do
    Enum.reduce(entries, %{}, fn {from, _to, _urn, content}, acc ->
      Regex.scan(~r/（([〇一二三四五六七八九]+)）/u, content, return: :index)
      |> Enum.reduce(acc, fn [{whole_start, _}, {digits_start, digits_length}], inner ->
        numeral = binary_part(content, digits_start, digits_length)
        prefix = binary_part(content, 0, whole_start)
        offset = from + byte_size(compare_form(prefix))
        Map.update(inner, numeral, [offset], &[offset | &1])
      end)
    end)
  end

  @doc """
  The span of one sutta: from its own printed number to the next number printed.

  A number that appears twice is refused rather than resolved by picking one — the
  window is what keeps a stock phrase from matching in the wrong sutta, so a window
  chosen by coin flip would remove the only guard here.
  """
  @spec window(map(), pos_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def window(index, number) do
    numeral = numeral(number)

    case Map.get(index.markers, numeral) do
      [start] ->
        next =
          index.markers
          |> Map.values()
          |> List.flatten()
          |> Enum.filter(&(&1 > start))
          |> Enum.min(fn -> index.size end)

        {:ok, {start, next}}

      nil ->
        {:error, {:no_marker, numeral}}

      several ->
        {:error, {:ambiguous_marker, numeral, length(several)}}
    end
  end

  @doc """
  Whether every sutta number printed in a work is printed exactly once.

  The check to run before adding a collection to `collections/0`: the window, and with
  it the guarantee that a match is in the right sutta, rests entirely on this.
  """
  @spec unique_markers?(String.t()) :: boolean()
  def unique_markers?(work_id) do
    case index(work_id) do
      {:ok, index} -> Enum.all?(index.markers, fn {_numeral, offsets} -> length(offsets) == 1 end)
      {:error, _} -> false
    end
  end

  # CBETA prints the number digit by digit with 〇 for zero — （八〇三）, never （八百零三）
  # and never （十）. Checked against both works this module anchors: T0099 prints 1,350
  # markers and T0026 222, and every one of them is read by this function.
  defp numeral(number) do
    number
    |> Integer.to_string()
    |> String.graphemes()
    |> Enum.map_join(fn digit -> Enum.at(~w(〇 一 二 三 四 五 六 七 八 九), String.to_integer(digit)) end)
  end

  # A byte span back to the lines it covers. One line is a point URN; several are a
  # range, which is what a citation of a passage longer than a printed line has to be —
  # `Corpus.resolve/1` and `Corpus.context/2` both take ranges.
  defp urn_for(index, {from, to}) do
    first = segment_at(index, from)
    last = segment_at(index, max(from, to - 1))

    case {first, last} do
      {nil, _} ->
        :error

      {_, nil} ->
        :error

      {i, i} ->
        {:ok, %{urn: elem(index.urns, i), ordinal_start: i, ordinal_end: i}}

      {i, j} ->
        {:ok,
         %{
           urn: URN.range(elem(index.urns, i), elem(index.urns, j)),
           ordinal_start: i,
           ordinal_end: j
         }}
    end
  end

  defp segment_at(index, offset) do
    search(index.starts, offset, 0, tuple_size(index.starts) - 1)
  end

  defp search(_starts, _offset, low, high) when low > high, do: nil

  defp search(starts, offset, low, high) do
    if low == high do
      if elem(starts, low) <= offset, do: low, else: nil
    else
      middle = div(low + high + 1, 2)

      if elem(starts, middle) <= offset,
        do: search(starts, offset, middle, high),
        else: search(starts, offset, low, middle - 1)
    end
  end

  @doc """
  The form two editions are compared in: editorial punctuation gone, variant Han
  characters folded to their class.

      iex> Pramana.Sc.Lzh.compare_form("一時，佛住舍衞國。")
      iex> |> Kernel.==(Pramana.Sc.Lzh.compare_form("一時佛住舍衛國"))
      false

  The 衞/衛 pair is NOT folded — Unihan files it under `kSemanticVariant`, which
  `Pramana.Retrieval.Variants` excludes on precision grounds. Segments that differ only
  by such a character are the residue this module anchors by interpolation instead.
  """
  @spec compare_form(String.t()) :: String.t()
  def compare_form(text) do
    text
    |> Punctuation.strip()
    |> String.replace(@editorial_extras, "")
    |> Variants.fold()
  end

  # `sa379:2.2` sorts after `sa379:1.10`, and `1.10` after `1.9`. String order gets both
  # wrong, and the forward-only match makes order load-bearing: one segment sorted early
  # drags the cursor past everything before it.
  defp sort_key(segment_id) do
    segment_id
    |> String.split(":", parts: 2)
    |> List.last()
    |> String.split(".")
    |> Enum.map(&String.to_integer/1)
  rescue
    ArgumentError -> [0]
  end

  # `0.1` and `0.2` are the collection title and the sutta number as a heading — the
  # translation's own furniture, not text of the sutta. Patton renders them "Connected
  # Discourses 379"; anchoring that to a canonical line would attach a heading to
  # scripture.
  defp heading?(segment_id) do
    case String.split(segment_id, ":", parts: 2) do
      [_uid, locator] -> String.starts_with?(locator, "0.")
      _ -> true
    end
  end

  defp number_of(file) do
    case Regex.run(~r/^[a-z]+(\d+)$/, uid_of(file)) do
      [_, digits] -> {:ok, String.to_integer(digits)}
      nil -> {:error, {:unnumbered, uid_of(file)}}
    end
  end

  @doc "`.../sa379_root-lzh-sct.json` -> `sa379`."
  @spec uid_of(String.t()) :: String.t()
  def uid_of(file) do
    file
    |> Path.basename(".json")
    |> String.split("_")
    |> hd()
  end

  defp collection_of(file) do
    uid = uid_of(file)

    Enum.find_value(@collections, fn {prefix, _work} ->
      if Regex.match?(~r/^#{prefix}\d+$/, uid), do: prefix
    end)
  end

  defp empty_report do
    %{
      works_seen: 0,
      works_placed: 0,
      unsupported: 0,
      exact: 0,
      interpolated: 0,
      dropped: 0,
      failures: %{}
    }
  end

  defp tally(report, counts) do
    %{
      report
      | works_placed: report.works_placed + 1,
        exact: report.exact + counts.exact,
        interpolated: report.interpolated + counts.interpolated,
        dropped: report.dropped + counts.dropped
    }
  end

  defp add_failures(report, files, reason) do
    Enum.reduce(files, report, fn file, acc ->
      %{acc | failures: Map.update(acc.failures, {uid_of(file), reason}, 1, &(&1 + 1))}
    end)
  end
end
