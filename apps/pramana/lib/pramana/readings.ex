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

  alias Pramana.Corpus.CharacterReading
  alias Pramana.Corpus.GlossaryTerm
  alias Pramana.Corpus.ReadingException
  alias Pramana.Readings.Build
  alias Pramana.Readings.Wylie
  alias Pramana.Repo

  # The longest form the exception table is allowed to hold, and so the longest window
  # `render/2` has to try at each position. 般若波羅蜜 is five; 摩訶般若波羅蜜多 is eight.
  @max_form_length 8

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
      Pramana.Batch.insert_all(ReadingException, entries,
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

  @doc """
  Renders a string as a list of `%{form, reading, source}` tokens.

  **Longest match wins.** 般若波羅蜜 is one token read *bō rě bō luó mì*, not 般若 followed
  by 波羅蜜 and certainly not five characters read separately; applying the shortest match
  first would split compounds that have their own conventional reading, which is the
  whole failure this layer exists to prevent.

  `source` says where each reading came from, and callers are expected to show it:

    * `:exception` — the reading dictionary overrode the ordinary one
    * `:base` — Unihan's commonest reading for the character, applied unchanged
    * `:unknown` — no reading recorded; the character is rendered with `nil` rather than
      a guess

  Two queries, no cache. Every substring of the input up to #{@max_form_length}
  characters is offered to the exception table at once, and the characters to the base
  table — for a printed line of twenty characters that is about 150 candidate forms in
  one `IN` clause. A process-level cache would be faster and would go stale silently the
  first time the dictionary is rebuilt, which is a bad trade for a layer whose only job
  is to be right.
  """
  @spec render(String.t(), keyword()) :: [map()]
  def render(text, opts \\ []) do
    lang = Keyword.get(opts, :lang, "lzh")
    scheme = Keyword.get(opts, :scheme, "pinyin")

    if scheme == "wylie", do: render_wylie(text), else: render_lookup(text, lang, scheme)
  end

  # Tibetan is the one script here whose romanisation is COMPUTED. There is no dictionary
  # to consult and nothing to look up, so these tokens are marked `:computed` rather than
  # `:base` — `:base` means "the ordinary reading, which an exception could override",
  # and for Wylie there is no such thing to override.
  defp render_wylie(text) do
    text
    |> String.split(~r/[\x{0F0B}\x{0F0C}]/u, trim: true)
    |> Enum.map(fn syllable ->
      %{
        form: syllable,
        reading: Wylie.transliterate(syllable) |> String.trim(),
        source: :computed
      }
    end)
  end

  defp render_lookup(text, lang, scheme) do
    chars = String.graphemes(text)

    exceptions = lookup_exceptions(chars, lang, scheme)
    base = lookup_base(chars)

    walk(chars, exceptions, base, [])
  end

  defp walk([], _exceptions, _base, acc), do: Enum.reverse(acc)

  defp walk([char | rest] = chars, exceptions, base, acc) do
    case longest_match(chars, exceptions) do
      {form, reading, length} ->
        token = %{form: form, reading: reading, source: :exception}
        walk(Enum.drop(chars, length), exceptions, base, [token | acc])

      nil ->
        token =
          case Map.fetch(base, char) do
            {:ok, reading} -> %{form: char, reading: reading, source: :base}
            :error -> %{form: char, reading: nil, source: :unknown}
          end

        walk(rest, exceptions, base, [token | acc])
    end
  end

  defp longest_match(chars, exceptions) do
    max = min(@max_form_length, length(chars))

    Enum.find_value(max..1//-1, fn length ->
      form = chars |> Enum.take(length) |> Enum.join()

      case Map.fetch(exceptions, form) do
        # A row that records "the ordinary reading is wrong" without saying what is right
        # must not be treated as a match — falling through to the base reading would
        # apply exactly the reading the row rejects. It is a gap, and gaps stay visible.
        {:ok, nil} -> nil
        {:ok, reading} -> {form, reading, length}
        :error -> nil
      end
    end)
  end

  defp lookup_exceptions(chars, lang, scheme) do
    candidates = windows(chars)

    Repo.all(
      from r in ReadingException,
        where: r.lang == ^lang and r.scheme == ^scheme and r.form in ^candidates,
        select: {r.form, r.reading}
    )
    |> Map.new()
  end

  defp lookup_base(chars) do
    Repo.all(
      from c in CharacterReading,
        where: c.character in ^Enum.uniq(chars),
        select: {c.character, c.reading}
    )
    |> Map.new()
  end

  # Every substring up to the cap — the set of forms that could possibly match, asked for
  # in one round trip instead of one per position.
  defp windows(chars) do
    total = length(chars)

    for start <- 0..max(total - 1, 0),
        len <- 1..@max_form_length,
        start + len <= total,
        uniq: true,
        do: chars |> Enum.slice(start, len) |> Enum.join()
  end

  @doc """
  Loads `priv/readings/*.tsv` into the database.

  Character readings first, then exceptions, because the exception check needs the
  attested sets to be present. Both are replace-on-conflict: a rebuilt dictionary must
  actually reach the database, which `on_conflict: :nothing` would quietly prevent.
  """
  @spec import_dictionary(keyword()) :: {:ok, map()}
  def import_dictionary(opts \\ []) do
    dir = Keyword.get(opts, :dir, Path.join(:code.priv_dir(:pramana), "readings"))
    now = DateTime.utc_now()

    characters =
      dir
      |> tsv("character_readings.tsv")
      |> Enum.map(fn [character, reading, attested] ->
        %{
          character: character,
          reading: reading,
          attested: String.split(attested, "|"),
          authority: "unihan",
          inserted_at: now,
          updated_at: now
        }
      end)

    exceptions =
      dir
      |> tsv("exceptions.tsv")
      |> Enum.map(fn [form, reading, _naive, authority, note] ->
        %{
          form: form,
          lang: "lzh",
          scheme: "pinyin",
          reading: reading,
          note: note,
          # Derived rows are `unverified`: CC-CEDICT is a real authority and the
          # cross-check against Unihan is real evidence, but nobody has read this entry.
          # The curated rows were checked by hand against the attested set, one at a time.
          status: if(authority == "curated", do: "verified", else: "unverified"),
          authority: authority,
          source_id: nil,
          inserted_at: now,
          updated_at: now
        }
      end)

    {characters_written, _} =
      Pramana.Batch.insert_all(CharacterReading, characters,
        on_conflict: {:replace, [:reading, :attested, :authority, :updated_at]},
        conflict_target: [:character]
      )

    # Postgres refuses an ON CONFLICT statement that proposes the same key twice, so the
    # last-wins rule cannot be left to the database. Curated rows are written last in the
    # file precisely so they win here: a form checked by hand beats the derivation.
    deduped =
      exceptions
      |> Enum.reduce(%{}, &Map.put(&2, {&1.form, &1.lang, &1.scheme}, &1))
      |> Map.values()

    {:ok, exceptions_written} = store(deduped)

    {:ok, %{characters: characters_written, exceptions: exceptions_written}}
  end

  defp tsv(dir, name) do
    Path.join(dir, name)
    |> File.stream!()
    |> Stream.map(&String.trim_trailing(&1, "\n"))
    |> Stream.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.map(&String.split(&1, "\t"))
  end

  @doc """
  Every reading Unihan attests for a character.

  The check that keeps invented readings out: a form's reading must be assembled from
  readings somebody has recorded for its characters. See `Pramana.Readings.Build`.
  """
  @spec attested(String.t()) :: [String.t()]
  def attested(character) do
    case Repo.get(CharacterReading, character) do
      %CharacterReading{attested: attested} -> attested
      nil -> []
    end
  end

  @doc """
  Checks a proposed reading against the attested sets, character by character.

  Returns `:ok`, or the offending `{character, syllable}` pairs. This is the same rule
  `mix pramana.readings.build` enforces on the curated file, exposed so a caller adding
  an entry at runtime meets the standard the build does.
  """
  @spec check(String.t(), String.t()) :: :ok | {:error, [{String.t(), String.t()}]}
  def check(form, reading) do
    chars = String.graphemes(form)
    sylls = String.split(reading)

    if length(chars) != length(sylls) do
      {:error, Enum.map(chars, &{&1, nil})}
    else
      unihan =
        Repo.all(from c in CharacterReading, where: c.character in ^chars)
        |> Map.new(&{&1.character, %{preferred: &1.reading, attested: MapSet.new(&1.attested)}})

      chars
      |> Enum.zip(sylls)
      |> Enum.reject(fn {char, syl} -> Build.attested?(unihan, char, syl) end)
      |> unattested()
    end
  end

  @doc """
  Scores the reading layer and the per-character baseline on the Buddhist test set.

  Both methods are run here rather than one being run and the other asserted, because
  the claim "a generic library fails on this vocabulary" is a measurement and has to
  keep being one. `broken` is the number the baseline got right and the dictionary got
  wrong — the regression that matters most, since a dictionary that damages the easy
  cases to fix the hard ones is not an improvement.
  """
  @spec score_test_set(keyword()) :: map()
  def score_test_set(opts \\ []) do
    dir = Keyword.get(opts, :dir, Path.join(:code.priv_dir(:pramana), "readings"))

    rows =
      dir
      |> tsv("buddhist_test_set.tsv")
      |> Enum.map(fn [form, expected, naive, occurrences] ->
        actual = form |> render() |> Enum.map_join(" ", & &1.reading)

        %{
          form: form,
          expected: expected,
          naive: naive,
          actual: actual,
          correct?: actual == expected,
          naive_correct?: naive == expected,
          occurrences: String.to_integer(occurrences)
        }
      end)

    %{
      rows: rows,
      correct: Enum.count(rows, & &1.correct?),
      naive_correct: Enum.count(rows, & &1.naive_correct?),
      fixed: Enum.count(rows, &(&1.correct? and not &1.naive_correct?)),
      broken: Enum.count(rows, &(not &1.correct? and &1.naive_correct?)),
      occurrences: rows |> Enum.map(& &1.occurrences) |> Enum.sum()
    }
  end

  defp unattested([]), do: :ok
  defp unattested(bad), do: {:error, bad}

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
