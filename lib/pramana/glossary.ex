defmodule Pramana.Glossary do
  @moduledoc """
  Pinned term renderings, and the parser that reads them out of a markdown glossary.

  Seed data for glossary-pinned translation (#26) and the reading-exception dictionary
  (#24). Imported from `~/dev/huangnianzu-translation`, a hand-built translation project
  for the same text Pramāṇa uses as its local-source case, which reached several of this
  project's disciplines independently.

  ## What is worth importing is the reasoning, not the mapping

  A bare 道隱 → "Master Dōin" is a lookup table. The note — *"Japanese. **Not**
  'Daoyin' — swept 2026-08-06"* — records that the name is Japanese, that a specific
  wrong rendering was rejected, and that the correction was actually applied on a date.
  So `notes` is stored verbatim and `rejected_forms` is extracted, because **a decision
  recorded is not a decision applied**: knowing which form is wrong is what lets a
  checker find the places still using it.

  That principle is not theoretical. In the source project a stale rule sat inside the
  glossary for months asserting 道隱 → "Daoyin", months after the prose had been
  corrected — invisible because the checker only looked at the translations, never at the
  file every batch is told to treat as canonical.

  ## An unverified reading is data, not a gap

  日溪 is Japanese, but the reading could not be confirmed, so the project kept pinyin
  and marked the row *"reading unverified"* rather than inventing "Nikkei".
  `reading_status` models that directly. Same discipline as
  `Pramana.URN.Taisho.provenance_for_volume/1` returning nil rather than guessing: a
  refusal to guess is information, and dropping the row would destroy it.
  """

  import Ecto.Query

  alias Pramana.Corpus.GlossaryTerm
  alias Pramana.Repo

  @doc """
  Parses a markdown glossary into term maps. Pure — no database, no file IO.

  Reads every pipe table in the document, taking the section heading above it as the
  category. Rows whose first cell is not CJK are skipped, which drops the
  `Chinese | Pinyin | ...` header rows and the Open-questions tables (keyed by topic,
  not by term).
  """
  @spec parse(String.t()) :: [map()]
  def parse(markdown) do
    markdown
    |> String.split("\n")
    |> Enum.reduce({nil, []}, fn line, {category, rows} ->
      cond do
        String.starts_with?(line, "## ") ->
          {line |> String.replace_prefix("## ", "") |> String.trim(), rows}

        skip_section?(category) ->
          {category, rows}

        table_row?(line) ->
          {category, prepend(parse_row(line, category), rows)}

        true ->
          {category, rows}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq_by(& &1.term)
  end

  defp prepend(nil, rows), do: rows
  defp prepend(row, rows), do: [row | rows]

  defp table_row?(line), do: String.starts_with?(String.trim(line), "|")

  # "Open questions" is keyed by TOPIC, not by term — rows like
  # "際 family (實際 / 本際 / 真實之際)" are discussion threads, not renderings. Importing
  # them would put entries in the glossary that no lookup could ever match, and that a
  # compliance check would then treat as canonical.
  @skip_sections ["Open questions"]
  defp skip_section?(category), do: category in @skip_sections

  defp parse_row(line, category) do
    cells =
      line
      |> String.trim()
      |> String.trim("|")
      |> String.split("|")
      |> Enum.map(&String.trim/1)

    with [term, pinyin, english | rest] <- cells,
         true <- cjk?(term),
         true <- english != "" do
      notes = rest |> Enum.join(" ") |> String.trim()

      %{
        term: term,
        pinyin: blank_to_nil(pinyin),
        canonical_english: english,
        notes: blank_to_nil(notes),
        category: category,
        rejected_forms: extract_rejected(notes <> " " <> english),
        reading_status: reading_status(notes),
        language_origin: language_origin(notes)
      }
    else
      _ -> nil
    end
  end

  # `**Not** "Daoyin"` — the glossary's own marker for a rendering it rejects.
  defp extract_rejected(text) do
    ~r/\*\*[Nn]ot\*\*\s*"([^"]{2,60})"/u
    |> Regex.scan(text)
    |> Enum.map(fn [_, form] -> form end)
    |> Enum.uniq()
  end

  # Only ever claims `unverified` when the source says so. Absence of the phrase means
  # "no reading question here", not "verified" — asserting verification nobody performed
  # would be exactly the invented confidence this models against.
  defp reading_status(notes) do
    if String.match?(notes, ~r/reading unverified/i), do: "unverified", else: "not_applicable"
  end

  # Derived only from an explicit statement in the notes. A name with no stated origin
  # gets nil rather than a guess — which reading tradition a name belongs to is precisely
  # what cannot be inferred from the characters.
  defp language_origin(notes) do
    # NEGATIONS ARE STRIPPED FIRST. 元曉's note reads "Korean (Silla), not Japanese" —
    # matching on the bare word classified it as Japanese, which is the exact error the
    # source project itself made with this name before correcting it. A note that says
    # what a name is NOT is evidence about what it is not.
    positive = String.replace(notes, ~r/\bnot\s+(Japanese|Korean|Chinese|Sanskrit)\b/i, "")

    cond do
      String.match?(positive, ~r/\bKorean\b|\bSilla\b/) -> "korean"
      String.match?(positive, ~r/\bJapanese\b/) -> "japanese"
      String.match?(positive, ~r/\bSanskrit\b/) -> "sanskrit"
      true -> nil
    end
  end

  defp cjk?(text), do: String.match?(text, ~r/\p{Han}/u)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil("—"), do: nil
  defp blank_to_nil(value), do: value

  @doc """
  Stores parsed terms against a source. Idempotent per `(source_id, term)`.
  """
  @spec import(String.t(), [map()]) :: {:ok, map()}
  def import(source_id, terms) do
    now = DateTime.utc_now()

    rows =
      Enum.map(terms, fn term ->
        term
        |> Map.put(:source_id, source_id)
        |> Map.put(:inserted_at, now)
        |> Map.put(:updated_at, now)
      end)

    {count, _} =
      Pramana.Batch.insert_all(GlossaryTerm, rows,
        on_conflict:
          {:replace,
           [
             :pinyin,
             :canonical_english,
             :notes,
             :category,
             :rejected_forms,
             :reading_status,
             :language_origin,
             :updated_at
           ]},
        conflict_target: [:source_id, :term]
      )

    {:ok, %{imported: count, total: length(terms)}}
  end

  @doc "Terms for a source, ordered by category then term."
  @spec for_source(String.t()) :: [GlossaryTerm.t()]
  def for_source(source_id) do
    Repo.all(
      from t in GlossaryTerm,
        where: t.source_id == ^source_id,
        order_by: [asc: t.category, asc: t.term]
    )
  end

  @doc """
  Look up a term's pinned rendering.

  This is what makes a translation *glossary-pinned*: the renderer consults it rather
  than deciding afresh each time.
  """
  @spec lookup(String.t(), String.t()) :: GlossaryTerm.t() | nil
  def lookup(source_id, term) do
    Repo.one(from t in GlossaryTerm, where: t.source_id == ^source_id and t.term == ^term)
  end

  @doc """
  Names whose reading could not be verified.

  Surfaced deliberately: these are the rows where a renderer must not silently pick a
  reading, and a reader should be told the reading is provisional.
  """
  @spec unverified_readings(String.t()) :: [GlossaryTerm.t()]
  def unverified_readings(source_id) do
    Repo.all(
      from t in GlossaryTerm,
        where: t.source_id == ^source_id and t.reading_status == "unverified",
        order_by: t.term
    )
  end

  @doc """
  Every rendering the glossary rejects, as `{term, rejected_form}` pairs.

  The input to a "decision recorded is not a decision applied" check: a rejected form
  appearing anywhere in generated output is a rule that was written down and never
  enforced.
  """
  @spec rejected_forms(String.t()) :: [{String.t(), String.t()}]
  def rejected_forms(source_id) do
    Repo.all(
      from t in GlossaryTerm,
        where: t.source_id == ^source_id and fragment("array_length(?, 1) > 0", t.rejected_forms),
        select: {t.term, t.rejected_forms}
    )
    |> Enum.flat_map(fn {term, forms} -> Enum.map(forms, &{term, &1}) end)
  end

  @doc "Counts by category, reading status and language origin. For the inventory."
  @spec stats(String.t()) :: map()
  def stats(source_id) do
    terms = for_source(source_id)

    %{
      total: length(terms),
      by_category: terms |> Enum.frequencies_by(& &1.category),
      unverified_readings: Enum.count(terms, &(&1.reading_status == "unverified")),
      with_rejected_forms: Enum.count(terms, &(&1.rejected_forms != [])),
      by_language_origin:
        terms
        |> Enum.reject(&is_nil(&1.language_origin))
        |> Enum.frequencies_by(& &1.language_origin)
    }
  end
end
