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
  alias Pramana.Repo

  @typedoc "A citation found in prose, and what it resolves to."
  @type found :: %{
          matched: String.t(),
          scheme: :taisho | :suttacentral,
          urn: String.t() | nil,
          reason: term() | nil
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

  @doc """
  Finds every foreign citation in a block of prose and resolves what it can.

  Returns one entry per distinct citation, each carrying the text that matched so a caller
  can point at it, and `reason` when it did not resolve. Nothing is silently dropped —
  a citation this corpus cannot place is exactly what a reader needs told.
  """
  @spec scan(String.t()) :: [found()]
  def scan(text) when is_binary(text) do
    (scan_taisho(text) ++ scan_suttacentral(text))
    |> Enum.uniq_by(& &1.matched)
  end

  defp scan_taisho(text) do
    sat =
      @sat
      |> Regex.scan(text)
      |> Enum.map(fn [matched, work, _volume, page, register, line] ->
        {matched, work, page, register, "", line}
      end)

    print =
      @print
      |> Regex.scan(text)
      |> Enum.map(fn [matched, work, page, register, sign, line] ->
        {matched, work, page, register, sign, line}
      end)

    (sat ++ print)
    |> Enum.uniq_by(fn {matched, _, _, _, _, _} -> matched end)
    |> Enum.map(&resolve_taisho/1)
  end

  defp resolve_taisho({matched, work, page, register, sign, line}) do
    work_id = "T" <> String.pad_leading(work, 4, "0")

    address = %{
      work_id: work_id,
      page: String.pad_leading(page, 4, "0"),
      register: register,
      line: String.to_integer(line),
      from_foot: sign == "-"
    }

    case taisho_urn(address) do
      {:ok, urn} -> %{matched: matched, scheme: :taisho, urn: urn, reason: nil}
      {:error, reason} -> %{matched: matched, scheme: :taisho, urn: nil, reason: reason}
    end
  end

  @doc """
  Resolves a parsed Taishō address to the URN of the line it names.

  Goes through `segments.page`, `register` and `line` rather than building a URN string,
  because **the juan is in our URN and not in the citation**. Assuming juan 1 would be
  right for page 6 and wrong for page 60 — see `Pramana.Glossary.Anchors`, where the same
  rule is applied to 29,890 of these.
  """
  @spec taisho_urn(map()) :: {:ok, String.t()} | {:error, term()}
  def taisho_urn(%{work_id: work_id} = address) do
    line = line_number(address)

    query =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where:
          t.work_id == ^work_id and t.source_id == "cbeta" and
            s.page == ^address.page and s.register == ^address.register and s.line == ^line,
        select: s.urn,
        limit: 1

    case Repo.one(query) do
      nil -> {:error, {:no_such_line, work_id, address.page, address.register, line}}
      urn -> {:ok, urn}
    end
  end

  # `27b-1` is the LAST line of the register, `-6` the sixth from last. Verified against
  # the text in `Pramana.Glossary.Anchors`; the last line is read from the corpus rather
  # than assumed to be 29, because the final page of a work is short.
  defp line_number(%{from_foot: false} = address), do: address.line

  defp line_number(%{from_foot: true} = address) do
    query =
      from s in Segment,
        join: t in Text,
        on: t.id == s.text_id,
        where:
          t.work_id == ^address.work_id and t.source_id == "cbeta" and
            s.page == ^address.page and s.register == ^address.register,
        select: max(s.line)

    case Repo.one(query) do
      nil -> address.line
      last -> last - address.line + 1
    end
  end

  defp scan_suttacentral(text) do
    @suttacentral
    |> Regex.scan(text)
    |> Enum.map(fn [matched, work, locator] ->
      urn = "pramana:sc.ms:#{work}@#{locator}"

      if segment_exists?(urn) do
        %{matched: matched, scheme: :suttacentral, urn: urn, reason: nil}
      else
        %{matched: matched, scheme: :suttacentral, urn: nil, reason: {:no_such_segment, urn}}
      end
    end)
  end

  # THE AMBIGUITY GUARD. `sn22.51:1.1` is a segment id and `Matthew 3:16` is not, and no
  # regex separates them — so the corpus does. A pattern that matched anything shaped like
  # a citation would put false findings into the checker, which is the one place this
  # project cannot afford them.
  defp segment_exists?(urn) do
    Repo.exists?(from s in Segment, where: s.urn == ^urn)
  end

  @doc """
  Rewrites foreign citations in prose as `pramana:` URNs, leaving the rest alone.

  Used by `Pramana.Guard.check_output/1` so a document citing the Taishō the way an
  article cites it is checked rather than silently passed. An unresolvable citation is
  left exactly as written — rewriting it to something that does not resolve would turn a
  citation nobody could place into a citation that looks fabricated.
  """
  @spec rewrite(String.t()) :: {String.t(), [found()]}
  def rewrite(text) when is_binary(text) do
    found = scan(text)

    rewritten =
      found
      |> Enum.filter(& &1.urn)
      # Longest first: `T0262_.09.0006a23` contains a substring that `@print` also
      # matches, and replacing the short one first would corrupt the long one.
      |> Enum.sort_by(&String.length(&1.matched), :desc)
      |> Enum.reduce(text, fn %{matched: matched, urn: urn}, acc ->
        String.replace(acc, matched, urn)
      end)

    {rewritten, found}
  end
end
