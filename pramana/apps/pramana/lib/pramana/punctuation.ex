defmodule Pramana.Punctuation do
  @moduledoc """
  Editorial punctuation, in one place because it is one fact about the corpus.

  **CBETA's punctuation is a modern editorial addition and is not in the witness.** The
  block-cut Taishō page has none; a modern editor supplied it. So two editions of the same
  passage differ in punctuation as a matter of course, and a comparison that counts those
  differences is measuring the editor rather than the text.

  `CLAUDE.md` says to keep it and flag it, which the normalizer does. This module is what
  every consumer downstream of that decision shares — `Pramana.Translators` used it to stop
  n-gram skew being half punctuation (`、舌` was a bigram), and `Pramana.Guard` uses it to
  tell "you quoted this from an edition that punctuates differently" apart from "these words
  are not there".

  It exists as a module rather than a constant copied twice because the second copy is the
  one that goes stale — rule 41, whose most expensive instance in this project was a
  two-digit constant fixed in the bake and left wrong in the reader.
  """

  # Whitespace, CJK full-width punctuation, and the bracket families CBETA uses. Not a
  # Unicode category: `\\p{P}` would take the tsheg out of Tibetan and the daṇḍa out of
  # transliterated Sanskrit, both of which are the witness's own marks rather than an
  # editor's.
  @editorial ~r/[\s，。、；：？！「」『』（）〔〕【】…—·]/u

  @doc "The pattern itself, for callers that need it inside a larger expression."
  @spec pattern() :: Regex.t()
  def pattern, do: @editorial

  @doc """
  Removes editorial punctuation and whitespace.

      iex> Pramana.Punctuation.strip("如是我聞，一時佛住。")
      "如是我聞一時佛住"
  """
  @spec strip(String.t()) :: String.t()
  def strip(text) when is_binary(text), do: String.replace(text, @editorial, "")

  @doc """
  Whether two passages differ only in editorial punctuation.

      iex> Pramana.Punctuation.same_but_for_punctuation?("如是我聞，", "如是我聞")
      true
      iex> Pramana.Punctuation.same_but_for_punctuation?("如是我聞", "如是我見")
      false
  """
  @spec same_but_for_punctuation?(String.t(), String.t()) :: boolean()
  def same_but_for_punctuation?(a, b) when is_binary(a) and is_binary(b),
    do: strip(a) == strip(b)
end
