defmodule Pramana.Readings.Pinyin do
  @moduledoc """
  Pinyin syllables, in one alphabet.

  The two sources this project derives readings from disagree about notation, not about
  sound: Unihan writes `bō`, CC-CEDICT writes `bo1`. Comparing them means converting one
  to the other first, and doing it wrong makes every entry look like a disagreement.

  ## Where the tone mark goes

  The rule is positional, not phonetic: mark **a** or **e** wherever it appears; in `ou`
  mark the **o**; otherwise mark the **last** vowel. `iu` and `ui` are the cases that
  catch people out — *liù* and *duì* both take the mark on the second vowel, which the
  general "first vowel" folk rule gets backwards.

  Output is NFC-normalised, because a combining macron appended to `a` is not the same
  binary as `ā` and a string comparison between them silently fails.
  """

  @marks %{1 => "̄", 2 => "́", 3 => "̌", 4 => "̀"}

  @doc """
  Converts a numbered syllable to its diacritic form.

  Tone 5 is neutral and carries no mark. Anything unparseable is returned unchanged
  and downcased rather than raising: the caller is reading a third-party dictionary,
  and one malformed line should not stop the build.

      iex> Pramana.Readings.Pinyin.toned("bo1")
      "bō"

      iex> Pramana.Readings.Pinyin.toned("re3")
      "rě"

      iex> Pramana.Readings.Pinyin.toned("liu4")
      "liù"

      iex> Pramana.Readings.Pinyin.toned("dui4")
      "duì"

      iex> Pramana.Readings.Pinyin.toned("lu:4")
      "lǜ"

      iex> Pramana.Readings.Pinyin.toned("de5")
      "de"
  """
  @spec toned(String.t()) :: String.t()
  def toned(syllable) do
    case Regex.run(~r/^([a-zA-Zü:]+)([1-5])$/u, syllable) do
      [_, body, tone] -> place(String.downcase(String.replace(body, "u:", "ü")), tone)
      _ -> String.downcase(syllable)
    end
  end

  defp place(body, "5"), do: body

  defp place(body, tone) do
    mark = @marks[String.to_integer(tone)]

    case vowel_index(body) do
      nil ->
        body

      i ->
        :unicode.characters_to_nfc_binary([
          String.slice(body, 0, i + 1),
          mark,
          String.slice(body, (i + 1)..-1//1)
        ])
    end
  end

  # Priority order, and the pair rules are why this is a list rather than a scan: "iu"
  # and "ui" must be found as pairs and marked on their SECOND vowel, before the bare
  # "i"/"u" rules can claim the first.
  defp vowel_index(body) do
    Enum.find_value(["a", "o", "e", "iu", "ui", "i", "u", "ü"], fn v ->
      case :binary.match(body, v) do
        {at, len} -> byte_to_char_index(body, at + len - 1)
        :nomatch -> nil
      end
    end)
  end

  defp byte_to_char_index(body, byte_offset) do
    body |> binary_part(0, byte_offset + 1) |> String.length() |> Kernel.-(1)
  end

  @doc """
  Strips tone marks, leaving the bare syllable.

  Used to recognise **neutral-tone erosion** (輕聲): CC-CEDICT records modern *spoken*
  Mandarin, where 知識 is `zhī shi` rather than `zhī shí`. That is a fact about
  twentieth-century speech, not about how a seventh-century text is read, so a
  divergence that consists only of a lost tone is not evidence of anything and must not
  enter a dictionary for Literary Chinese.

      iex> Pramana.Readings.Pinyin.toneless("bō")
      "bo"

      iex> Pramana.Readings.Pinyin.toneless("lǜ")
      "lü"
  """
  @spec toneless(String.t()) :: String.t()
  def toneless(syllable) do
    syllable
    |> :unicode.characters_to_nfd_binary()
    # The four tone marks BY NAME, not the combining-diacritics block: ü decomposes to
    # u + combining diaeresis, which is in that block and is not a tone. Stripping it
    # turns lǜ into lu and makes two different syllables compare equal.
    |> String.replace(~r/[\x{0304}\x{0301}\x{030C}\x{0300}]/u, "")
    |> :unicode.characters_to_nfc_binary()
  end

  @doc """
  True when two readings differ **only** by neutral-tone erosion.

      iex> Pramana.Readings.Pinyin.neutral_tone_only?("zhī shi", "zhī shí")
      true

      iex> Pramana.Readings.Pinyin.neutral_tone_only?("bō rě", "bān ruò")
      false
  """
  @spec neutral_tone_only?(String.t(), String.t()) :: boolean()
  def neutral_tone_only?(a, b) do
    a = String.split(a)
    b = String.split(b)

    length(a) == length(b) and
      Enum.zip(a, b)
      |> Enum.all?(fn {x, y} -> x == y or (x == toneless(x) and x == toneless(y)) end)
  end
end
