defmodule Pramana.Readings do
  @moduledoc """
  The reading layer: how a form is *pronounced*, when the ordinary answer is wrong.

  `docs/LAYERS.md` §2 settles the storage question first, because it is the one that
  decides whether this is tractable: **readings are computed at render time, never
  materialized per character.** A pinyin for every character of a 250M-character corpus
  is billions of rows of derivable data. What is *not* derivable is the exceptions, and
  those are what this table holds.

  ## Why exceptions are a required asset rather than a nicety

  A general library (pypinyin and friends) mis-reads Buddhist vocabulary confidently,
  because transliterated Sanskrit follows conventional readings that ignore the
  characters' ordinary values:

      般若   bōrě, not bānruò
      南無   námó, not nánwú
      迦葉   jiāshè, not jiāyè

  They cluster in exactly the passages a reader most wants help with. The same problem
  recurs in Japanese, where Buddhist texts use 呉音 *go-on* rather than 漢音 *kan-on*
  (経 is *kyō*, not *kei*) — which bears directly on the Taishō 56–84 material.

  ## A row may decline to give a reading

  `status: "unverified"` with a null `reading` is a legitimate and useful record: it says
  the ordinary reading is wrong *without* inventing a replacement. The seed data contains
  exactly such a case — 日溪, Japanese, probably *Nikkei*, not confirmed — and keeping it
  is the same discipline as `Pramana.Taisho.Divisions.provenance_for_volume/1` returning
  nil rather than guessing.

  Building out the dictionary from DDB and Buddhist reference works is task #24.
  """

  import Ecto.Query

  alias Pramana.Corpus.GlossaryTerm
  alias Pramana.Corpus.ReadingException
  alias Pramana.Repo

  @schemes ~w(pinyin wade-giles zhuyin middle-chinese on-yomi kun-yomi
              mccune-reischauer wylie thl iast)
  @statuses ~w(verified unverified disputed)

  @doc "Reading schemes this layer knows how to record."
  @spec schemes() :: [String.t()]
  def schemes, do: @schemes

  @doc "Recognised verification statuses."
  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc """
  The exception for a form, or `nil` when the ordinary reading applies.

  `nil` means "nothing special here", which is the answer for the overwhelming majority
  of forms — this table is consulted, not enumerated.
  """
  @spec exception(String.t(), keyword()) :: ReadingException.t() | nil
  def exception(form, opts \\ []) do
    lang = Keyword.get(opts, :lang, "lzh")
    scheme = Keyword.get(opts, :scheme, "pinyin")

    Repo.one(
      from r in ReadingException,
        where: r.form == ^form and r.lang == ^lang and r.scheme == ^scheme
    )
  end

  @doc """
  Every exception occurring in a string, longest form first.

  Longest-first because 般若波羅蜜 must win over 般若 when both are recorded: applying the
  shorter one first would split a compound that has its own conventional reading.
  """
  @spec exceptions_in(String.t(), keyword()) :: [ReadingException.t()]
  def exceptions_in(text, opts \\ []) do
    lang = Keyword.get(opts, :lang, "lzh")
    scheme = Keyword.get(opts, :scheme, "pinyin")

    Repo.all(from r in ReadingException, where: r.lang == ^lang and r.scheme == ^scheme)
    |> Enum.filter(&String.contains?(text, &1.form))
    |> Enum.sort_by(&(-String.length(&1.form)))
  end

  @doc "Stores exceptions, replacing an existing row for the same form/lang/scheme."
  @spec store([map()]) :: {:ok, non_neg_integer()}
  def store(rows) when is_list(rows) do
    now = DateTime.utc_now()

    entries =
      Enum.map(rows, fn row ->
        row
        |> Map.put_new(:status, "unverified")
        |> Map.merge(%{inserted_at: now, updated_at: now})
      end)

    {count, _} =
      Repo.insert_all(ReadingException, entries,
        on_conflict: {:replace, [:reading, :note, :status, :authority, :source_id, :updated_at]},
        conflict_target: [:form, :lang, :scheme]
      )

    {:ok, count}
  end

  @doc """
  Seeds the layer from the glossary, which already records readings with provenance.

  The Huang Nianzu glossary (#34) carries `pinyin`, `reading_status` and
  `language_origin` for 376 pinned terms, including the cases that matter most: names
  that are **not Chinese** and must not be read as if they were — 元曉 is Korean
  (*Wŏnhyo*), 道隱 Japanese (*Dōin*). Projecting those into this table copies nothing and
  invents nothing; the authority stays the glossary's own source id, so a wrong reading
  can be traced to whoever asserted it.

  Chinese-origin terms are skipped: their pinyin is the ordinary reading, and an
  "exception" that agrees with the default is noise the lookup would have to filter.
  """
  @spec seed_from_glossary() :: {:ok, map()}
  def seed_from_glossary do
    terms =
      Repo.all(
        from g in GlossaryTerm,
          where: not is_nil(g.language_origin) and g.language_origin != "chinese"
      )

    rows = Enum.map(terms, &row_for/1)
    {:ok, count} = store(rows)

    {:ok,
     %{
       seeded: count,
       by_status: Enum.frequencies_by(rows, & &1.status),
       by_lang: Enum.frequencies_by(rows, & &1.lang)
     }}
  end

  defp row_for(term) do
    {reading, status} = reading_and_status(term)

    %{
      form: term.term,
      # The language whose reading conventions apply — which is the WHOLE point for these
      # entries. A Japanese name written in Chinese characters is read as Japanese; that
      # it appears in a Chinese text does not make it Chinese.
      lang: lang_code(term.language_origin),
      scheme: scheme_for(term.language_origin),
      reading: reading,
      note: note_for(term),
      status: status,
      authority: term.source_id,
      source_id: term.source_id
    }
  end

  defp lang_code("japanese"), do: "ja"
  defp lang_code("korean"), do: "ko"
  defp lang_code("sanskrit"), do: "sa"
  defp lang_code("pali"), do: "pi"
  defp lang_code("tibetan"), do: "bo"
  defp lang_code(_), do: "lzh"

  defp scheme_for("japanese"), do: "on-yomi"
  defp scheme_for("korean"), do: "mccune-reischauer"
  defp scheme_for("tibetan"), do: "wylie"
  defp scheme_for("sanskrit"), do: "iast"
  defp scheme_for("pali"), do: "iast"
  defp scheme_for(_), do: "pinyin"

  # The glossary's convention is the opposite of what it looks like, and getting it
  # backwards is not a cosmetic error. `pinyin` is populated exactly when the reading in
  # the target language could NOT be established — it is a placeholder retained per that
  # project's refuse-to-guess rule — and left EMPTY when the reading was established, in
  # which case it is stated in `canonical_english`: "Master Wŏnhyo (元曉)".
  #
  # Taking the pinyin as the reading therefore records 元曉 as *Yuánxiǎo* under
  # McCune-Reischauer and marks it verified, which is precisely the mistake this whole
  # table exists to prevent, dressed up as data.
  defp reading_and_status(%{reading_status: "unverified"}), do: {nil, "unverified"}

  defp reading_and_status(%{pinyin: pinyin}) when is_binary(pinyin) and pinyin != "",
    do: {nil, "unverified"}

  defp reading_and_status(term), do: extract_reading(term)

  # Only the unambiguous shape — a name followed by exactly this form in parentheses —
  # is extracted. "Master Kōgyō" (no form given) and "Master Bōsai (望西) / Ryōe of
  # Bōsai-rō (望西樓了惠)" (two names, two forms) are left unverified rather than parsed
  # out of English prose, which is guessing with extra steps.
  defp extract_reading(%{canonical_english: nil}), do: {nil, "unverified"}

  defp extract_reading(term) do
    pattern = ~r/^(?:Master\s+)?([^()\/]+?)\s*\(#{Regex.escape(term.term)}\)$/u

    case Regex.run(pattern, String.trim(term.canonical_english)) do
      [_, name] -> {String.trim(name), "verified"}
      _ -> {nil, "unverified"}
    end
  end

  # A retained pinyin is worth carrying, clearly labelled as what it is: the Mandarin
  # reading of characters that are not being read as Mandarin.
  defp note_for(%{pinyin: pinyin} = term) when is_binary(pinyin) and pinyin != "" do
    [term.notes, "Mandarin pinyin is #{pinyin}; this is NOT the reading in this scheme."]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" ")
  end

  defp note_for(term), do: term.notes

  @doc "Counts, for the inventory and the gate."
  @spec stats() :: map()
  def stats do
    %{
      exceptions: Repo.aggregate(ReadingException, :count),
      by_scheme: group_count(:scheme),
      by_status: group_count(:status),
      # Rows that record "the ordinary reading is wrong" without saying what is right.
      # A number worth watching: it is the backlog for #24.
      without_reading:
        Repo.aggregate(from(r in ReadingException, where: is_nil(r.reading)), :count)
    }
  end

  defp group_count(field) do
    Repo.all(
      from r in ReadingException,
        group_by: field(r, ^field),
        select: {field(r, ^field), count(r.id)},
        order_by: [desc: count(r.id)]
    )
    |> Map.new()
  end
end
