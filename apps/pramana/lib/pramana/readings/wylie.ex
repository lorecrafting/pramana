defmodule Pramana.Readings.Wylie do
  @moduledoc """
  Tibetan script to Wylie (EWTS) transliteration.

  Tibetan is the one script in this corpus whose romanisation is **computed rather than
  looked up**. Pinyin needs a dictionary because Chinese characters are polyphonic and
  Buddhist vocabulary breaks the ordinary readings; Wylie needs none, because it is a
  letter-for-letter transcription of an alphabetic script. `Pramana.Readings` stores
  exceptions; this module stores nothing.

  That distinction is why Wylie does **not** belong in `reading_exceptions` even though
  the table has a `scheme` column for it. A row there asserts that the ordinary answer
  is wrong for a particular form. Wylie has no ordinary answer to be wrong about — it
  has an algorithm. THL Phonetic is the opposite case: it depends on dialect and on
  conventions that genuinely vary, so *that* would need the table.

  ## The only hard part is the implicit vowel

  Unicode stores Tibetan in the same order Wylie writes it, so most of the work is a
  codepoint map. ཀུན is `ka` + vowel `u` + `na`, and emitting each in turn gives `kun`
  with no analysis at all.

  The problem is syllables with **no vowel sign**, which carry an implicit *a* — and it
  is not appended at the end. སངས is `sangs`, not `sngsa`. The *a* follows the **root
  stack**, so the root has to be identified, and that is Tibetan orthography rather than
  string handling:

    * a stack carrying subjoined letters is the root — གྲངས is `grangs`, because ག with
      subjoined ར is one stack and ང ས are suffixes
    * otherwise ག ད བ མ འ before another consonant are prefixes, so the root is second:
      གསལ is `gsal`, དཀར is `dkar`
    * and a letter that cannot be a prefix is the root: སངས is `sangs`, ཐམས is `thams`

  ## Where it is genuinely ambiguous

  གཡ is `g.ya`, not `gya` — the dot marks that ག is a prefix rather than a stack with
  subjoined ཡ, which Unicode writes differently (གྱ). The dot is emitted for exactly the
  cases EWTS defines it for. Ambiguity that Unicode itself resolves needs no dot, which
  is why this direction is tractable and Wylie-to-Unicode is not.
  """

  # U+0F40..U+0F6C. Subjoined forms live at +0x50 and reuse these values.
  @consonants %{
    0x0F40 => "k",
    0x0F41 => "kh",
    0x0F42 => "g",
    0x0F43 => "g+h",
    0x0F44 => "ng",
    0x0F45 => "c",
    0x0F46 => "ch",
    0x0F47 => "j",
    0x0F49 => "ny",
    0x0F4A => "T",
    0x0F4B => "Th",
    0x0F4C => "D",
    0x0F4D => "D+h",
    0x0F4E => "N",
    0x0F4F => "t",
    0x0F50 => "th",
    0x0F51 => "d",
    0x0F52 => "d+h",
    0x0F53 => "n",
    0x0F54 => "p",
    0x0F55 => "ph",
    0x0F56 => "b",
    0x0F57 => "b+h",
    0x0F58 => "m",
    0x0F59 => "ts",
    0x0F5A => "tsh",
    0x0F5B => "dz",
    0x0F5C => "dz+h",
    0x0F5D => "w",
    0x0F5E => "zh",
    0x0F5F => "z",
    0x0F60 => "'",
    0x0F61 => "y",
    0x0F62 => "r",
    0x0F63 => "l",
    0x0F64 => "sh",
    0x0F65 => "Sh",
    0x0F66 => "s",
    0x0F67 => "h",
    0x0F68 => "a",
    0x0F69 => "k+Sh",
    0x0F6A => "r"
  }

  @vowels %{
    0x0F71 => "A",
    0x0F72 => "i",
    0x0F74 => "u",
    0x0F7A => "e",
    0x0F7B => "ai",
    0x0F7C => "o",
    0x0F7D => "au",
    0x0F80 => "-i"
  }

  # Not vowels: they attach after one and do not satisfy the implicit-a rule.
  @marks %{0x0F7E => "M", 0x0F7F => "H", 0x0F82 => "~M`", 0x0F83 => "~M", 0x0F84 => "?"}

  @punctuation %{
    0x0F04 => "@#",
    0x0F05 => "#",
    0x0F06 => "$",
    0x0F07 => "&",
    0x0F08 => "*",
    0x0F0D => "/",
    0x0F0E => "//",
    0x0F0F => ";",
    0x0F10 => "!",
    0x0F11 => "|",
    0x0F14 => ":",
    0x0F3A => "<",
    0x0F3B => ">",
    0x0F3C => "(",
    0x0F3D => ")"
  }

  # ཙེག — the syllable break. It is a separator, not a letter, and Wylie writes it as a
  # space.
  @tsheg [0x0F0B, 0x0F0C]

  # Only these five stand before a root. A letter outside this set at the head of a
  # syllable IS the root, which is what makes སངས `sangs` rather than `sangas`.
  @prefixes ~w(g d b m ')

  # Only these ten follow a root. Used to tell བག `bag` (ག is a suffix, བ is the root)
  # from གཡ `g.ya` (ཡ is not a suffix, so ག must be a prefix).
  @suffixes ~w(g ng d n b m ' r l s)

  # Letters that sit ABOVE a root, and letters that sit BELOW it. A stack built from
  # these is native Tibetan orthography and is written plainly — རྒྱ is `rgya`. Anything
  # else stacked is a Sanskrit conjunct, which EWTS joins with `+` because `padma` would
  # otherwise read as three Tibetan syllables' worth of letters.
  @superscripts ~w(r l s)
  @subscripts ~w(y r l w)

  @doc """
  Transliterates Tibetan script into Wylie.

  Text outside the Tibetan block passes through unchanged, so a mixed line survives.

      iex> Pramana.Readings.Wylie.transliterate("བཀྲ་ཤིས་")
      "bkra shis "

      iex> Pramana.Readings.Wylie.transliterate("སངས་རྒྱས")
      "sangs rgyas"

      iex> Pramana.Readings.Wylie.transliterate("ཐམས་ཅད")
      "thams cad"

      iex> Pramana.Readings.Wylie.transliterate("ཨོཾ་མ་ཎི་པདྨེ་ཧཱུྃ")
      "oM ma Ni pad+me hU~M"
  """
  @spec transliterate(String.t()) :: String.t()
  def transliterate(text) do
    text
    |> String.to_charlist()
    |> chunk_syllables()
    |> Enum.map_join(&render_chunk/1)
  end

  # Splits on tsheg and on anything that is not a Tibetan letter, so punctuation and
  # Latin text interrupt a syllable rather than being absorbed into it.
  defp chunk_syllables(chars) do
    chars
    |> Enum.chunk_by(&letter?/1)
    |> Enum.flat_map(fn
      [c | _] = run when not is_nil(c) -> if letter?(c), do: [{:syllable, run}], else: split(run)
    end)
  end

  defp split(run), do: Enum.map(run, &{:other, &1})

  defp letter?(c),
    do:
      Map.has_key?(@consonants, c) or Map.has_key?(@vowels, c) or Map.has_key?(@marks, c) or
        subjoined?(c)

  defp subjoined?(c), do: c >= 0x0F90 and c <= 0x0FBC

  defp render_chunk({:syllable, chars}), do: syllable(chars)
  defp render_chunk({:other, c}) when c in @tsheg, do: " "

  defp render_chunk({:other, c}) do
    case Map.fetch(@punctuation, c) do
      {:ok, wylie} -> wylie
      :error -> <<c::utf8>>
    end
  end

  @doc """
  Transliterates one syllable — no tsheg, no punctuation.

      iex> Pramana.Readings.Wylie.syllable(~c"གསལ")
      "gsal"

      iex> Pramana.Readings.Wylie.syllable(~c"གྲངས")
      "grangs"
  """
  @spec syllable([integer()]) :: String.t()
  def syllable(chars) do
    stacks = stacks(chars)
    root = root_index(stacks)

    stacks
    |> Enum.with_index()
    |> Enum.map_join(fn {stack, i} ->
      dot = if i == root - 1, do: disambiguator(stack, Enum.at(stacks, root)), else: ""
      carrier(stack) <> dot <> vowel_for(stack, i == root) <> stack.marks
    end)
  end

  # The implicit vowel is decided PER STACK, not per syllable. པདྨེ is `pad+me`: the
  # explicit ེ sits on the stacked མ, and པ still needs its own *a*. A rule that skipped
  # the implicit vowel whenever the syllable contained any vowel sign would give `pd+me`.
  defp vowel_for(%{vowel: vowel}, _root?) when not is_nil(vowel), do: vowel
  # ཨ standing alone is already `a`; appending the implicit vowel would give `aa`.
  defp vowel_for(%{text: "a"}, true), do: ""
  defp vowel_for(_stack, true), do: "a"
  defp vowel_for(%{conjunct: true}, false), do: "a"
  # A non-root stack that carries a SUBJOINED letter is a syllable of its own, not a
  # suffix: a suffix is always a single letter. ཤཱཀྱ is `shAkya` — the ཱ puts the root on
  # ཤ, and the ཀྱ that follows still needs its own *a*, where a plain ས there would not.
  # Measured against 84000's published transliteration of 476 titles, this was one of the
  # differences; `gsal`, `grangs` and `brgyad` are unaffected because their subjoined
  # stack IS the root.
  defp vowel_for(%{subjoined: true}, false), do: "a"
  defp vowel_for(_stack, false), do: ""

  # ག before ཡ or ཝ needs a dot AFTER it, because `gya` and `gwa` already mean the
  # subjoined forms — which Unicode writes differently and which this never produces.
  defp disambiguator(%{text: "g"}, %{text: root}) when root in ~w(y w), do: "."
  defp disambiguator(_before, _root), do: ""

  # ཨ is a vowel carrier, not a consonant: ཨོཾ is `oM`, not `aoM`.
  defp carrier(%{text: "a", vowel: vowel}) when not is_nil(vowel), do: ""
  defp carrier(stack), do: stack.text

  # A stack is one top-level consonant plus whatever subjoins to it, plus any vowel or
  # mark that follows. Grouping this way is what makes the root test "does this stack
  # carry subjoined letters" rather than a scan over raw codepoints.
  defp stacks(chars) do
    chars
    |> Enum.reduce([], &absorb/2)
    |> Enum.reverse()
  end

  # One codepoint at a time, onto the stack being built. Written as clauses rather than
  # a `cond` because each branch is a different KIND of thing — a new stack, a letter
  # joining the current one, a vowel, a mark — and the shape should say so.
  defp absorb(c, acc) do
    cond do
      Map.has_key?(@consonants, c) -> [new_stack(@consonants[c]) | acc]
      subjoined?(c) -> add_subjoined(acc, Map.get(@consonants, c - 0x50, ""))
      Map.has_key?(@vowels, c) -> add_vowel(acc, @vowels[c])
      Map.has_key?(@marks, c) -> add_mark(acc, @marks[c])
      true -> acc
    end
  end

  defp new_stack(text),
    do: %{text: text, subjoined: false, conjunct: false, vowel: nil, marks: ""}

  defp add_vowel(acc, vowel),
    do: update_head(acc, fn s -> %{s | vowel: compose(s.vowel, vowel)} end)

  defp add_mark(acc, mark), do: update_head(acc, fn s -> %{s | marks: s.marks <> mark} end)

  defp add_subjoined([], _wylie), do: []

  defp add_subjoined([head | rest], wylie) do
    native? = native_stack?(head, wylie)
    joiner = if native?, do: "", else: "+"

    [
      %{head | text: head.text <> joiner <> wylie, subjoined: true, conjunct: not native?}
      | rest
    ]
  end

  # Native if the letter above is a superscript, or the letter below is a subscript.
  # རྒྱ is r-over-g with y beneath, both native, so it is `rgya`; ལྔ is l-over-ng, so
  # `lnga`. དྨ is neither, so it is `d+m`.
  defp native_stack?(%{text: above, conjunct: false}, below),
    do: above in @superscripts or below in @subscripts

  defp native_stack?(_head, _below), do: false

  # ཱ followed by ུ is the long U, written as one letter. Concatenating would give `Au`,
  # which EWTS reads as a different vowel.
  defp compose("A", "u"), do: "U"
  defp compose("A", "i"), do: "I"
  defp compose(nil, vowel), do: vowel
  defp compose(existing, vowel), do: existing <> vowel

  defp update_head([], _fun), do: []
  defp update_head([head | rest], fun), do: [fun.(head) | rest]

  defp root_index([]), do: 0

  defp root_index(stacks) do
    # An explicit vowel sits on the root, and that settles it outright: བདེ is `bde`
    # because ེ is on ད, where the positional rules would have read ད as a suffix and
    # given `bade`.
    #
    # Unless the vowel is on a Sanskrit conjunct, which is not a Tibetan root at all —
    # པདྨེ is `pad+me`, and trusting the vowel there gives `pd+me`.
    #
    # Failing that, a NATIVE stack is the root: གྲངས is `grangs`, so ག carries the a even
    # though two consonants follow it.
    # ...but an འ that follows another letter is a SUFFIX carrying that suffix's vowel,
    # never a root. བའི is the genitive of བ and transliterates `ba'i`: the བ keeps its
    # implicit *a* and the འ takes the ི. Reading the vowel as proof of roothood gave
    # `b'i` and did it to every genitive and agentive in the canon — པའི, བའོ, མའི,
    # ལགས་སོའི — which is most of the particles in Tibetan.
    Enum.find_index(stacks, &vowel_root?/1) ||
      Enum.find_index(stacks, &(&1.subjoined and not &1.conjunct)) ||
      root_by_position(stacks)
  end

  defp vowel_root?(stack), do: stack.vowel && not stack.conjunct && stack.text != "'"

  defp root_by_position([_only]), do: 0

  # Two letters: the second is either a suffix, making the first the root (བག `bag`),
  # or it is not, making the first a prefix (གཡ `g.ya`).
  defp root_by_position([_first, second]),
    do: if(head_letter(second) in @suffixes, do: 0, else: 1)

  # Three or more: a leading prefix letter pushes the root to second position — གསལ
  # `gsal`, དཀར `dkar` — and anything else is itself the root: སངས `sangs`.
  defp root_by_position([first | _rest]), do: if(first.text in @prefixes, do: 1, else: 0)

  # For a conjunct, the letter occupying the suffix slot is the one written first.
  defp head_letter(%{text: text}), do: text |> String.split("+") |> hd()
end
