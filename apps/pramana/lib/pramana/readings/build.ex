defmodule Pramana.Readings.Build do
  @moduledoc """
  Derives the reading dictionary from Unihan and CC-CEDICT.

  The asset that makes Buddhist Chinese readable is not a model output and not a
  judgement — it is a **derivation from two independent published sources**, which is
  why it lives in code that can be re-run rather than in a file somebody once wrote.

  ## The finding this is built on

  Unihan's `kMandarin` gives one reading per character: the commonest one. For 佛 —
  the single most frequent character in the canon, 533,670 occurrences — that reading
  is **fú**, because 佛 is common in 仿佛 *fǎngfú*. The Buddha is *fó*. A library that
  reads character by character therefore gets the word "Buddha" wrong half a million
  times, and no amount of tuning fixes it, because the information is not in the field
  it is reading.

  It *is* in Unihan, in the other fields. `kHanyuPinyin` lists 葉 as `yè, shè`; 若 as
  `ruò, ré, rè`; 般 as `pán, bān, bǎn, bō`. The Buddhist readings are attested. What no
  per-character table can say is **which one applies here** — and that is exactly what
  an exception dictionary is for.

  ## Four filters, each rejecting a different kind of wrong

  1. **Polyphone ambiguity.** A single character with more than one unbound reading in
     CC-CEDICT is skipped. 說 is *shuō*, *shuì* and *yuè*; choosing one without context
     is guessing, and guessing is what this table exists to replace. 1,168 characters
     are skipped this way. 佛 survives because its other reading is *bound* — CC-CEDICT
     glosses `fu2` as "used in 仿佛", which is a fact about one word, not about 佛.
  2. **Neutral-tone erosion** (輕聲). CC-CEDICT records modern spoken Mandarin, where
     知識 is `zhī shi`. Twentieth-century speech is not evidence about a seventh-century
     text, so a divergence consisting only of a lost tone is dropped: 2,956 entries.
  3. **Cross-source attestation.** Every syllable of a CC-CEDICT compound must appear in
     Unihan's attested inventory for that character. This is the one that makes the
     result trustworthy rather than merely sourced — two independent authorities have to
     agree. They agree on 96.8%; the 88 that fail are dropped.
  4. **Corpus occurrence.** A reading for a word that never appears in the canon is
     shipped weight, not an asset.

  ## What it cannot do

  Everything here is **context-free**: a form gets one reading. 藏 is *zàng* in 三藏 and
  *cáng* in 藏經 — the compound entries handle both, but a bare 藏 cannot be resolved and
  is not shipped. Recording that as an unresolved gap is the honest outcome; picking one
  would be the error this module is built to avoid.
  """

  alias Pramana.Readings.Pinyin

  @han_start 0x3400
  @han_end 0x9FFF

  # A gloss that only points at another word describes THAT word, not this character.
  # 般 `bo1` glossed "used in 般若" tells you nothing about 般 standing alone.
  @bound ~r/^\s*(used in|see |variant of|old variant|erhua variant)/i

  @cedict_line ~r/^(\S+) (\S+) \[([^\]]+)\] \/(.*)\/$/
  @buddhist ~r/buddhis|sanskrit|\bskt\b|s(u|ū)tra|bodhisattva|nirvana|dharma|monk/i

  @doc """
  Parses Unihan reading fields into `%{char => %{preferred: String.t(), attested: [String.t()]}}`.

  `kMandarin` supplies the preferred reading. Every other reading field contributes to
  the **attested set**, which is what filter 3 checks against — the union across
  `kHanyuPinyin`, `kXHC1983`, `kTGHZ2013` and `kHanyuPinlu`, because each covers a
  different slice and no one of them alone lists the Buddhist readings.
  """
  @spec unihan(Enumerable.t()) :: map()
  def unihan(lines) do
    Enum.reduce(lines, %{}, fn line, acc ->
      case String.split(String.trim_trailing(line, "\n"), "\t") do
        [<<"U+", cp::binary>>, field, value] -> merge_field(acc, codepoint(cp), field, value)
        _ -> acc
      end
    end)
  end

  defp codepoint(hex), do: <<String.to_integer(hex, 16)::utf8>>

  defp merge_field(acc, char, "kMandarin", value) do
    readings = value |> String.split() |> Enum.map(&String.downcase/1)
    acc |> put_attested(char, readings) |> put_in_preferred(char, hd(readings))
  end

  defp merge_field(acc, char, "kHanyuPinyin", value) do
    # "53243.150:yè,shè" — locations before the colon, readings after.
    put_attested(acc, char, value |> String.split() |> Enum.flat_map(&after_colon/1))
  end

  defp merge_field(acc, char, field, value) when field in ~w(kXHC1983 kTGHZ2013) do
    put_attested(acc, char, value |> String.split() |> Enum.flat_map(&after_colon/1))
  end

  defp merge_field(acc, char, "kHanyuPinlu", value) do
    # "yè(301)" — the frequency is not a reading.
    readings = value |> String.split() |> Enum.map(&Regex.replace(~r/\(\d+\)$/, &1, ""))
    put_attested(acc, char, readings)
  end

  defp merge_field(acc, _char, _field, _value), do: acc

  defp after_colon(part) do
    part
    |> String.split(":")
    |> List.last()
    |> String.split(",")
    |> Enum.map(&(&1 |> String.trim_leading("-") |> String.downcase()))
  end

  defp put_attested(acc, char, readings) do
    readings =
      readings |> Enum.map(&:unicode.characters_to_nfc_binary/1) |> Enum.reject(&(&1 == ""))

    entry = Map.get(acc, char, %{preferred: nil, attested: MapSet.new()})
    Map.put(acc, char, %{entry | attested: MapSet.union(entry.attested, MapSet.new(readings))})
  end

  defp put_in_preferred(acc, char, reading) do
    update_in(acc, [char, :preferred], fn _ -> :unicode.characters_to_nfc_binary(reading) end)
  end

  @doc """
  Parses CC-CEDICT into `{singles, compounds}`.

  Singles carry a `bound?` flag (filter 1); compounds carry their gloss so Buddhist
  vocabulary can be labelled.
  """
  @spec cedict(Enumerable.t()) :: {map(), [map()]}
  def cedict(lines) do
    Enum.reduce(lines, {%{}, []}, fn line, {singles, compounds} = acc ->
      with false <- String.starts_with?(line, "#"),
           # Five elements: the whole match, then traditional, SIMPLIFIED, pinyin, gloss.
           # The simplified form is not used, but it has to be destructured or the shape
           # does not match and every line is silently discarded.
           [_, trad, _simplified, pron, gloss] <-
             Regex.run(@cedict_line, String.trim_trailing(line, "\n")),
           true <- han?(trad),
           sylls = pron |> String.split() |> Enum.map(&Pinyin.toned/1),
           # One syllable per character, or the two cannot be zipped and the entry says
           # nothing about which character is read how.
           true <- length(sylls) == String.length(trad) do
        entry = %{form: trad, reading: Enum.join(sylls, " "), gloss: gloss}
        collect(entry, String.length(trad), singles, compounds)
      else
        _ -> acc
      end
    end)
  end

  # A single character carries the `bound?` flag filter 1 needs; a compound does not.
  defp collect(entry, 1, singles, compounds) do
    bound? = Regex.match?(@bound, entry.gloss |> String.split("/") |> hd())
    {Map.update(singles, entry.form, [{entry, bound?}], &(&1 ++ [{entry, bound?}])), compounds}
  end

  defp collect(entry, _length, singles, compounds), do: {singles, [entry | compounds]}

  defp han?(string) do
    string
    |> String.to_charlist()
    |> Enum.all?(&(&1 >= @han_start and &1 <= @han_end))
  end

  @doc """
  Applies all four filters and returns the exceptions worth shipping.

  `occurs?` decides filter 4 — pass `fn _ -> true end` to skip the corpus check.
  """
  @spec exceptions(map(), {map(), [map()]}, (String.t() -> boolean())) :: %{
          exceptions: [map()],
          rejected: map()
        }
  def exceptions(unihan, {singles, compounds}, occurs?) do
    {single_rows, single_rejects} = single_exceptions(unihan, singles)
    {compound_rows, compound_rejects} = compound_exceptions(unihan, compounds)

    rows =
      (single_rows ++ compound_rows)
      |> Enum.filter(&occurs?.(&1.form))
      |> Enum.sort_by(&{String.length(&1.form), &1.form})

    %{
      exceptions: rows,
      rejected: Map.merge(single_rejects, compound_rejects)
    }
  end

  defp single_exceptions(unihan, singles) do
    Enum.reduce(singles, {[], %{polyphonic: 0}}, fn {char, entries}, {rows, rejects} ->
      free = for {entry, false} <- entries, do: entry

      cond do
        # Filter 1. More than one context-free reading means the character alone does
        # not determine its sound, and no dictionary keyed by the character can help.
        length(free) > 1 -> {rows, Map.update!(rejects, :polyphonic, &(&1 + 1))}
        free == [] or is_nil(get_in(unihan, [char, :preferred])) -> {rows, rejects}
        true -> single_row(hd(free), unihan[char].preferred, rows, rejects)
      end
    end)
  end

  defp single_row(%{reading: reading}, preferred, rows, rejects) when reading == preferred,
    do: {rows, rejects}

  defp single_row(entry, preferred, rows, rejects),
    do: {[row(entry, preferred, "cc-cedict") | rows], rejects}

  defp compound_exceptions(unihan, compounds) do
    Enum.reduce(compounds, {[], %{neutral_tone: 0, unattested: 0}}, fn entry, {rows, rejects} ->
      chars = String.graphemes(entry.form)

      if Enum.all?(chars, &get_in(unihan, [&1, :preferred])) do
        naive = Enum.map_join(chars, " ", &unihan[&1].preferred)
        compound_row(entry, naive, unihan, rows, rejects)
      else
        {rows, rejects}
      end
    end)
  end

  defp compound_row(entry, naive, unihan, rows, rejects) do
    cond do
      entry.reading == naive ->
        {rows, rejects}

      # Filter 2.
      Pinyin.neutral_tone_only?(entry.reading, naive) ->
        {rows, Map.update!(rejects, :neutral_tone, &(&1 + 1))}

      # Filter 3.
      not attested?(unihan, entry.form, entry.reading) ->
        {rows, Map.update!(rejects, :unattested, &(&1 + 1))}

      true ->
        {[row(entry, naive, "cc-cedict") | rows], rejects}
    end
  end

  @doc """
  True when every syllable of `reading` is attested by Unihan for the matching character.

  Filter 3, and the integrity rule for hand-curated entries too: a reading nobody has
  recorded for that character is not a Buddhist convention, it is a typo or an
  invention, and this is the check that tells them apart.
  """
  @spec attested?(map(), String.t(), String.t()) :: boolean()
  def attested?(unihan, form, reading) do
    chars = String.graphemes(form)
    sylls = String.split(reading)

    length(chars) == length(sylls) and
      Enum.zip(chars, sylls)
      |> Enum.all?(fn {char, syl} ->
        case unihan[char] do
          %{attested: attested} -> MapSet.member?(attested, syl)
          _ -> false
        end
      end)
  end

  defp row(entry, naive, authority) do
    %{
      form: entry.form,
      reading: entry.reading,
      naive: naive,
      buddhist?: Regex.match?(@buddhist, entry.gloss),
      gloss: entry.gloss,
      authority: authority
    }
  end
end
