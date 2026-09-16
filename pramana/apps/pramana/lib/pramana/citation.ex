defmodule Pramana.Citation do
  @moduledoc """
  Citations in other people's schemes, resolved to URNs this corpus can open.

  ## The problem, stated by `docs/PLAN.md` L4

  The same line of the Lotus Sūtra is `pramana:cbeta.T:T0262_001@p0006a23` here,
  `T0262_.09.0006a23` in SAT's and CBETA's own addressing, and **`T. 262, 6a23` in every
  printed article ever written about it**. So a citation cannot be checked in the system
  that did not produce it, and the loss is not symmetrical: this project's whole claim is
  that it tells you when a citation is wrong.

  ## Where it actually bites

  `Pramana.Guard.check_output/1` scans prose for `pramana:` URNs. A report citing the
  Taishō the way scholars cite the Taishō contains none, so the guard finds nothing,
  reports **zero citations checked**, and `/check` renders that as a document with nothing
  wrong with it. An absence of findings and a clean bill of health are the same screen.

  That is the failure this module exists to close. It is not a convenience for people who
  dislike typing URNs.

  ## Only grammars this project has verified

  Two are implemented, and both were read off real data rather than a specification:

    * **Taishō print and SAT form** — `T. 262, 6a23`, `T262 6a23`, `T0262_.09.0006a23`,
      and the from-the-foot form `27b-1`. The grammar comes from the 29,890 Karashima
      citations resolved in `Pramana.Glossary.Anchors`, which is where `-1` meaning *the
      last line of the register* was verified against the text.
    * **SuttaCentral segment ids** — `mn1:1.1`, `sn22.51:2.3`. This corpus holds 244,763
      renderings anchored on them.

  **fojin's `fojin:cbeta/T0001.1` is deliberately NOT implemented.** `docs/PLAN.md` names
  it as the fourth scheme, and what the `.1` addresses — a line, a paragraph, a segment
  ordinal — is not documented anywhere this project could check. Guessing would produce a
  resolver that returns confident wrong passages, which is worse than one that returns
  nothing. See `docs/PLAN.md` L4 for what asking them would cost.

  ## Ambiguity is resolved by the corpus, never by a rule

  `T 9, 6a23` might name text 9 or volume 9; scholars write both. Rather than pick, a
  parsed work is **only accepted if this bake holds it** — the resolution fails otherwise
  and says so. A rule would be right most of the time, which is the property that makes a
  wrong citation hard to notice.
  """

  import Ecto.Query

  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.EvidenceInput
  alias Pramana.Repo

  @typedoc "A citation found in prose, and what it resolves to."
  @type found :: %{
          matched: String.t(),
          scheme: :taisho | :suttacentral,
          urn: String.t() | nil,
          reason: term() | nil,
          source_offset: non_neg_integer(),
          source_length: pos_integer()
        }

  # SAT and CBETA's own form: work, volume, page, register, line, all fixed width.
  # `T0262_.09.0006a23`, and the `_.09.` is optional because CBETA also prints
  # `T0262.0006a23`.
  @sat ~r/\bT(\d{4})(?:_?\.(\d{2}))?\.(\d{4})([abc])(\d{2})\b/

  # The way it appears in an article: `T. 262, 6a23` · `T262 6a23` · `T.262:27b-1`.
  # The separator between number and page is deliberately permissive and the page/line
  # part is not: a bare `T 262` with no address is not a citation to a passage.
  @print ~r/\bT\.?\s*(\d{1,4})[\s,.:;]+(\d{1,3})([abc])(-?)(\d{1,2})\b/

  # SuttaCentral segment ids — `mn1:1.1`, `pli-tv-bu-vb-pj1:2.3`, `sn22.51:1.1`.
  # Anchored to a word boundary at both ends so it cannot eat part of a URN.
  @suttacentral ~r/\b([a-z][a-z0-9-]*\d[a-z0-9.-]*):(\d+(?:\.\d+)+)\b/

  # Preserve literal source-evidence bytes. Foreign-looking strings inside the same
  # quotation delimiters the Guard recognizes are still returned as metadata, but they
  # are not canonicalized before the Guard compares that quotation with its witness.
  @literal_quotation ~r/[「『"“]([^」』"”]{1,400})[」』"”]/u

  @doc """
  Finds every foreign citation in a block of prose and resolves what it can.

  Returns one entry per citation occurrence, each carrying the text that matched so a caller
  can point at it, and `reason` when it did not resolve. Nothing is silently dropped —
  a citation this corpus cannot place is exactly what a reader needs told.
  """
  @spec scan(String.t()) :: [found()]
  def scan(text) when is_binary(text) do
    (scan_taisho(text) ++ scan_suttacentral(text))
    |> Enum.sort_by(&{&1.source_offset, -&1.source_length})
    |> Enum.reduce({[], 0}, fn found, {kept, finish} ->
      if found.source_offset < finish,
        do: {kept, finish},
        else: {[found | kept], found.source_offset + found.source_length}
    end)
    |> elem(0)
    |> Enum.reverse()
  end

  defp captures(pattern, text) do
    pattern
    |> Regex.scan(text, return: :index)
    |> Enum.map(fn [whole | captures] ->
      values =
        Enum.map(captures, fn
          {-1, 0} -> ""
          {pos, len} -> binary_part(text, pos, len)
        end)

      {whole, values}
    end)
  end

  defp scan_taisho(text) do
    sat =
      Enum.map(captures(@sat, text), fn {range, [work, volume, page, register, line]} ->
        {range, work, volume, page, register, "", line}
      end)

    print =
      Enum.map(captures(@print, text), fn {range, [work, page, register, sign, line]} ->
        {range, work, "", page, register, sign, line}
      end)

    Enum.map(sat ++ print, &resolve_taisho(&1, text))
  end

  defp resolve_taisho({{pos, len}, work, volume, page, register, sign, line}, text) do
    address = %{
      work_id: "T" <> String.pad_leading(work, 4, "0"),
      volume: if(volume == "", do: nil, else: String.to_integer(volume)),
      page: String.pad_leading(page, 4, "0"),
      register: register,
      line: String.to_integer(line),
      from_foot: sign == "-"
    }

    base = %{
      matched: binary_part(text, pos, len),
      scheme: :taisho,
      source_offset: pos,
      source_length: len
    }

    case taisho_urn(address) do
      {:ok, urn} -> Map.merge(base, %{urn: urn, reason: nil})
      {:error, reason} -> Map.merge(base, %{urn: nil, reason: reason})
    end
  end

  @doc """
  Resolves a parsed Taishō address to the URN of the line it names.

  Supplied volume coordinates are enforced, including per-segment volume metadata.
  Multiple matches return an ambiguity error, never the first row.

  Goes through `segments.page`, `register` and `line` rather than building a URN string,
  because **the juan is in our URN and not in the citation**. Assuming juan 1 would be
  right for page 6 and wrong for page 60 — see `Pramana.Glossary.Anchors`, where the same
  rule is applied to 29,890 of these.
  """
  @spec taisho_urn(map()) :: {:ok, String.t()} | {:error, term()}
  def taisho_urn(%{work_id: work_id} = address) do
    with {:ok, volume} <- volume_number(Map.get(address, :volume)),
         query = address_query(address, volume),
         {:ok, line} <- line_number(query, address) do
      candidates =
        Repo.all(
          from([s, _t] in query,
            where: s.line == ^line,
            select: s.urn,
            distinct: true,
            order_by: s.urn,
            limit: 2
          )
        )

      case candidates do
        [urn] ->
          {:ok, urn}

        [] when is_nil(volume) ->
          {:error, {:no_such_line, work_id, address.page, address.register, line}}

        [] ->
          {:error,
           {:no_such_line_in_volume, work_id, volume, address.page, address.register, line}}

        _ ->
          {:error, {:ambiguous_address, work_id, address.page, address.register, line}}
      end
    end
  end

  defp volume_number(nil), do: {:ok, nil}
  defp volume_number(volume) when is_integer(volume) and volume > 0, do: {:ok, volume}
  defp volume_number(_), do: {:error, :invalid_volume}

  defp address_query(address, volume) do
    query =
      from(s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where:
          t.work_id == ^address.work_id and t.source_id == "cbeta" and t.witness_id == "T" and
            s.page == ^address.page and s.register == ^address.register
      )

    if volume do
      from([s, t] in query,
        where:
          fragment("COALESCE(?->>'volume', ?)", s.meta, t.volume) == ^Integer.to_string(volume)
      )
    else
      query
    end
  end

  # The foot belongs to a particular printed register. Do not compute a maximum
  # across two volumes/texts and pretend it identified one unambiguous address.
  defp line_number(query, %{from_foot: true} = address) do
    registers =
      Repo.all(
        from([s, t] in query,
          group_by: [s.text_id, fragment("COALESCE(?->>'volume', ?)", s.meta, t.volume)],
          select: max(s.line),
          order_by: [s.text_id, fragment("COALESCE(?->>'volume', ?)", s.meta, t.volume)],
          limit: 2
        )
      )

    case registers do
      [] -> {:ok, address.line}
      [last] when is_integer(last) -> {:ok, last - address.line + 1}
      _ -> {:error, {:ambiguous_register, address.work_id, address.page, address.register}}
    end
  end

  defp line_number(_query, address), do: {:ok, address.line}

  defp scan_suttacentral(text) do
    Enum.map(captures(@suttacentral, text), fn {{pos, len}, [work, locator]} ->
      urn = "pramana:sc.ms:#{work}@#{locator}"

      found = %{
        matched: binary_part(text, pos, len),
        scheme: :suttacentral,
        source_offset: pos,
        source_length: len
      }

      if segment_exists?(urn),
        do: Map.merge(found, %{urn: urn, reason: nil}),
        else: Map.merge(found, %{urn: nil, reason: {:no_such_segment, urn}})
    end)
  end

  # THE AMBIGUITY GUARD. `sn22.51:1.1` is a segment id and `Matthew 3:16` is not, and no
  # regex separates them — so the corpus does. A pattern that matched anything shaped like
  # a citation would put false findings into the checker, which is the one place this
  # project cannot afford them.
  defp segment_exists?(urn) do
    Repo.exists?(from(s in Segment, where: s.urn == ^urn))
  end

  @doc """
  Rewrites foreign citations in prose as `pramana:` URNs, leaving the rest alone.

  Used by `Pramana.Report.verify/2` so a document citing the Taishō the way an
  article cites it is checked rather than silently passed. An unresolvable citation is
  left exactly as written — rewriting it to something that does not resolve would turn a
  citation nobody could place into a citation that looks fabricated.

  A foreign-looking address inside a literal quotation is reported in the returned
  metadata but is not rewritten. The quotation bytes are evidence and must remain what
  the author actually supplied when the Guard compares them with the cited witness.
  """
  @spec rewrite(String.t(), keyword()) :: {String.t(), [found()]}
  def rewrite(text, opts \\ []) when is_binary(text) do
    regions = EvidenceInput.regions(text, opts)

    found =
      Enum.flat_map(regions, fn {offset, region} ->
        Enum.map(scan(region), &Map.update!(&1, :source_offset, fn pos -> pos + offset end))
      end)

    edits = rewrite_edits(found, quotation_ranges(regions))
    rewritten = EvidenceInput.apply_edits(text, edits)

    {rewritten, found}
  end

  defp quotation_ranges(regions) do
    Enum.flat_map(regions, fn {offset, region} ->
      @literal_quotation
      |> Regex.scan(region, return: :index)
      |> Enum.map(fn [_, {pos, length}] ->
        %{byte_start: offset + pos, byte_end: offset + pos + length}
      end)
    end)
  end

  defp rewrite_edits(found, quote_ranges) do
    {edits, _ranges} =
      Enum.map_reduce(found, quote_ranges, fn item, ranges ->
        ranges = Enum.drop_while(ranges, &(&1.byte_end <= item.source_offset))
        edit = if item.urn != nil and not quoted?(item, ranges), do: rewrite_edit(item)
        {edit, ranges}
      end)

    Enum.reject(edits, &is_nil/1)
  end

  defp quoted?(_item, []), do: false

  defp quoted?(item, [range | _]) do
    finish = item.source_offset + item.source_length
    range.byte_start < finish and item.source_offset < range.byte_end
  end

  defp rewrite_edit(found) do
    %{
      range: %{
        byte_start: found.source_offset,
        byte_end: found.source_offset + found.source_length
      },
      before: found.matched,
      after: found.urn
    }
  end
end
