defmodule Pramana.Glossary.Anchors do
  @moduledoc """
  Turns a glossary's printed citations into URNs this corpus can open.

  Karashima cites the passages a gloss rests on — `T.262` at `59b7` — and those are Taishō
  addresses already in the bake. Resolved, a dictionary entry stops being a claim you take
  on trust and becomes one you can open, read and byte-verify like any other citation here.

  ## The grammar, and the things in it that are not the address

  The stored form is `<work>:<locator>`, and the locator carries editorial furniture the
  glossary uses to say *whose* translation it is quoting:

      T.262:6a23                     bare
      T.224:Lk. 464b18               Lk. = Lokakṣema
      T.263:Z. 105b4.                Z. = 竺法護 Dharmarakṣa, and a trailing full stop
      T.263:Z. not found at 68c1     an address, and a claim that nothing is there
      T.262:27b-1                    the LAST line of page 27 register b

  The siglum and the punctuation are stripped; **the "not found" is not.** It is the
  reason `status` exists.

  ## Lines counted from the foot of the register

  `27b-1` is not line 1. Karashima numbers from the **bottom** when a term sits near it,
  so `-1` is the last line, `-6` the sixth from last. 285 citations use it, and reading
  them as ordinary line numbers put them all in the wrong place or nowhere.

  It was verified before it was implemented rather than inferred from the shape. The entry
  citing `T.262 27b-1` quotes 能於四衆示教利喜, which sits at page 27 register b **line
  29**, and 29 is the last line of that register. The entry citing `19a-6` is headed 方便
  and marks the headword inside 以智、方便而演説之, which is **line 24** of a register whose
  last line is 29 — `29 - 6 + 1`. Two independent confirmations, one of them landing on
  the headword itself.

  ## Absence is evidence, and it is the expensive kind

  4,347 of the 29,890 citations are Karashima having looked at a specific line in another
  translation and recorded that the term is **not** there. That is attested absence by a
  scholar who checked — which `docs/PLAN.md` calls the highest-value signal a corpus
  project has, and which is ordinarily the hardest thing to obtain. It is stored as
  `absent` with the URN of the place examined, never dropped and never confused with a
  resolution.

  ## Resolution ignores the juan, because the citation does

  A Taishō citation is work, page, register, line — `T.262` `6a23`. The juan is in our URN
  (`T0262_001`) and not in the citation, so resolution goes through `segments.page`,
  `register` and `line` rather than through URN string-building, and the juan comes back
  from the row. Constructing `pramana:cbeta.T:T0262_001@p0006a23` by assuming juan 1 would
  be right for page 6 and wrong for page 60 — rule 68, avoided by not parsing.
  """

  import Ecto.Query

  alias Pramana.Corpus.GlossaryAnchor
  alias Pramana.Corpus.GlossaryEntry
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Text
  alias Pramana.Repo

  @typedoc "A citation broken into the parts that address a line."
  @type parsed :: %{
          work_id: String.t(),
          page: String.t(),
          register: String.t(),
          line: pos_integer(),
          from_foot: boolean(),
          absent: boolean()
        }

  @doc """
  Parses one stored citation.

  Returns `{:ok, parsed}` or `{:error, reason}`; the error is kept and counted rather than
  skipped, because a citation nobody could read is a gloss whose evidence nobody checked.

      iex> Pramana.Glossary.Anchors.parse("T.262:6a23")
      {:ok, %{work_id: "T0262", page: "0006", register: "a", line: 23,
              from_foot: false, absent: false}}

      iex> Pramana.Glossary.Anchors.parse("T.262:27b-1")
      {:ok, %{work_id: "T0262", page: "0027", register: "b", line: 1,
              from_foot: true, absent: false}}
  """
  @spec parse(String.t()) :: {:ok, parsed()} | {:error, term()}
  def parse(citation) when is_binary(citation) do
    with [work, locator] <- String.split(citation, ":", parts: 2),
         {:ok, work_id} <- work_id(work),
         [_, page, register, sign, line] <-
           Regex.run(~r/(\d+)([abc])(-?)(\d+)/, locator) do
      {:ok,
       %{
         work_id: work_id,
         # CBETA pads the Taishō page to four digits — `p0006a23`, never `p6a23`.
         page: String.pad_leading(page, 4, "0"),
         register: register,
         line: String.to_integer(line),
         from_foot: sign == "-",
         absent: String.contains?(locator, "not found")
       }}
    else
      nil -> {:error, {:unparseable_locator, citation}}
      {:error, reason} -> {:error, reason}
      _ -> {:error, {:unparseable_citation, citation}}
    end
  end

  # `T.262` -> `T0262`. Taishō work ids are the canon letter and four digits, which is the
  # same padding the URN uses and the same constant this project has got wrong three times
  # — see rule 41.
  defp work_id("T." <> number) do
    case Integer.parse(number) do
      {n, ""} -> {:ok, "T" <> String.pad_leading(Integer.to_string(n), 4, "0")}
      _ -> {:error, {:unknown_work, number}}
    end
  end

  defp work_id(other), do: {:error, {:unknown_work, other}}

  @doc """
  Resolves every citation on every entry of a source, replacing what is there.

  Returns a tally by status. Nothing is inserted for an entry with no citations, which is
  all of Soothill-Hodous and all of the Mahāvyutpatti.
  """
  @spec resolve_source(String.t(), keyword()) :: map()
  def resolve_source(source_id, opts \\ []) do
    dry_run? = Keyword.get(opts, :dry_run, false)
    index = line_index(cited_works(source_id))

    source_id
    |> entries_with_citations()
    |> Enum.flat_map(&rows_for(&1, index))
    |> tally_and_store(dry_run?)
  end

  defp entries_with_citations(source_id) do
    from(e in GlossaryEntry,
      where: e.source_id == ^source_id,
      where: fragment("jsonb_array_length(coalesce(?->'citations','[]'::jsonb)) > 0", e.meta),
      select: %{id: e.id, meta: e.meta}
    )
    |> Repo.all()
  end

  defp cited_works(source_id) do
    from(e in GlossaryEntry,
      where: e.source_id == ^source_id,
      select:
        fragment(
          "distinct split_part(jsonb_array_elements_text(?->'citations'), ':', 1)",
          e.meta
        )
    )
    |> Repo.all()
    |> Enum.flat_map(fn work ->
      case work_id(work) do
        {:ok, id} -> [id]
        {:error, _} -> []
      end
    end)
  end

  # ONE QUERY PER RUN, NOT ONE PER CITATION. 29,890 citations against 12.5M segments is
  # 29,890 round trips if each is looked up on its own; the four works they cite hold
  # about 40,000 lines between them, which is one query and a map.
  defp line_index(work_ids) do
    lines =
      from(s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where: t.work_id in ^work_ids and t.source_id == "cbeta",
        select: {t.work_id, s.page, s.register, s.line, s.urn}
      )
      |> Repo.all()

    %{
      urns: Map.new(lines, fn {w, p, r, l, urn} -> {{w, p, r, l}, urn} end),
      # The last line of each register, for the from-the-foot citations. Taken from the
      # corpus rather than assumed to be 29: a register is usually 29 lines and the last
      # page of a work is not, and a constant would be wrong exactly where a term sits at
      # the end of a text.
      last:
        Enum.reduce(lines, %{}, fn {w, p, r, l, _urn}, acc ->
          Map.update(acc, {w, p, r}, l, &max(&1, l))
        end)
    }
  end

  defp rows_for(entry, index) do
    now = DateTime.utc_now()

    entry.meta
    |> Map.get("citations", [])
    |> Enum.uniq()
    |> Enum.map(fn citation ->
      {status, work_id, urn} = resolve(citation, index)

      %{
        entry_id: entry.id,
        work_id: work_id,
        urn: urn,
        citation: citation,
        status: status,
        meta: %{},
        inserted_at: now,
        updated_at: now
      }
    end)
  end

  defp resolve(citation, index) do
    case parse(citation) do
      {:ok, parsed} -> locate(parsed, index)
      {:error, _reason} -> {"unresolved", nil, nil}
    end
  end

  defp locate(parsed, index) do
    key = {parsed.work_id, parsed.page, parsed.register, line_of(parsed, index)}

    case Map.get(index.urns, key) do
      nil -> {"unresolved", parsed.work_id, nil}
      urn -> {if(parsed.absent, do: "absent", else: "resolved"), parsed.work_id, urn}
    end
  end

  # `-1` is the last line of the register, `-6` the sixth from last.
  defp line_of(%{from_foot: false} = p, _index), do: p.line

  defp line_of(%{from_foot: true} = p, index) do
    case Map.get(index.last, {p.work_id, p.page, p.register}) do
      nil -> p.line
      last -> last - p.line + 1
    end
  end

  defp tally_and_store(rows, dry_run?) do
    unless dry_run?, do: store(rows)

    rows
    |> Enum.frequencies_by(& &1.status)
    |> Map.put(:total, length(rows))
  end

  defp store(rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(
      &Repo.insert_all(GlossaryAnchor, &1,
        on_conflict: {:replace, [:work_id, :urn, :status, :meta, :updated_at]},
        conflict_target: [:entry_id, :citation]
      )
    )
  end

  @doc """
  Every gloss that cites a line — the question the table exists to answer.

  `status` travels with each, so a caller can tell "this word is glossed here" from
  "a scholar checked here and the word is absent".
  """
  @spec glossing(String.t()) :: [map()]
  def glossing(urn) when is_binary(urn) do
    from(a in GlossaryAnchor,
      join: e in GlossaryEntry,
      on: e.id == a.entry_id,
      where: a.urn == ^urn,
      select: %{
        status: a.status,
        citation: a.citation,
        chinese: e.chinese,
        sanskrit: e.sanskrit,
        definition: e.definition,
        glossary: fragment("?->>'glossary'", e.meta),
        scope: e.work_id
      },
      order_by: [a.status, e.chinese]
    )
    |> Repo.all()
  end
end
