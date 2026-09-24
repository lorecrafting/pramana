defmodule Pramana.Retrieval.Variants do
  @moduledoc """
  Variant Han characters (異體字), expanded at **query time only**.

  ## The hole this closes

  Not the one originally assumed. CBETA is internally consistent — it writes 說 412,524
  times and 説 never, 眾生 132,626 times and 众生 never. The recall hole is not *inside*
  the corpus; it is between the **reader's keyboard and the corpus**:

  | someone types | hits |
  |---|---|
  | 众生 (simplified) | **0** |
  | 眾生 (as CBETA writes it) | 132,626 |
  | 説法 (Japanese form) | **0** |
  | 說法 (as CBETA writes it) | 29,328 |

  A reader in Beijing or Tokyo searching this corpus gets **nothing**, silently, and
  nothing signals the miss. That is what this fixes.

  ## Query-side only, never at index time

  The stored text must stay byte-identical to the witness. Which Han form an edition
  prints is scholarly data — a critical edition's orthography is evidence about its
  transmission, not noise to be smoothed away. Normalising at ingest would destroy that
  and make `mix pramana.verify` a check on our own rewriting rather than on the source.

  So expansion happens on the *query*, the index is untouched, and the response reports
  what was expanded so a hit on a different form is visible rather than surprising.

  ## Precision over recall, deliberately

  Built from Unihan's `kSimplifiedVariant`, `kTraditionalVariant` and `kZVariant` —
  6,447 classes over 13,066 characters. `kSemanticVariant` is excluded: it means
  "characters sharing a meaning" and includes genuinely different words, so expanding
  across it would return passages using another word. A precision failure is worse than
  a recall miss here, because a reader cannot see it.

  Known cost of that choice: 眞/真 is filed under `kSemanticVariant` upstream, so it is
  not expanded. See `priv/variants/PROVENANCE.md`.
  """

  @external_resource Path.join([
                       __DIR__,
                       "..",
                       "..",
                       "..",
                       "priv",
                       "variants",
                       "unihan_variants.tsv"
                     ])

  # Loaded at COMPILE time into a literal map. 6,447 classes is small enough that runtime
  # file IO or an ETS table would be complexity without benefit, and every query needs it.
  @classes @external_resource
           |> File.read!()
           |> String.split("\n", trim: true)
           |> Enum.flat_map(fn class ->
             members = String.graphemes(class)
             Enum.map(members, &{&1, members})
           end)
           |> Map.new()

  @doc """
  The variant set for one character, including the character itself.

      iex> Pramana.Retrieval.Variants.variants_of("說")
      ["說", "説", "说"]

  A character with no known variants returns just itself, so callers need no special
  case:

      iex> Pramana.Retrieval.Variants.variants_of("佛")
      ["佛"]
  """
  @spec variants_of(String.t()) :: [String.t()]
  def variants_of(char), do: Map.get(@classes, char, [char])

  @doc "Whether a character has any known variants."
  @spec variants?(String.t()) :: boolean()
  def variants?(char), do: Map.has_key?(@classes, char)

  @doc """
  Rewrites a passage so that every character stands for its whole variant class.

  For **comparing two passages to each other**, never for storing or for querying. The
  representative it picks is arbitrary and its identity carries no meaning — all that is
  guaranteed is that two passages differing only in which form of a character they print
  fold to the same string:

      iex> Pramana.Retrieval.Variants.fold("說法") == Pramana.Retrieval.Variants.fold("説法")
      true

  This is `expand/2`'s job done the other way round, and it exists because
  `Pramana.Sc.Lzh` has to align a SAT-derived edition against a CBETA-derived one where
  the two print 説 and 說 for the same word. Expansion asks "which forms could this be
  written in"; folding asks "are these two the same word". A comparison of six characters
  where each has three forms is 729 expansions and one fold.

  Index-time normalisation is still forbidden, for the reason in the moduledoc: which
  Han form an edition prints is evidence about its transmission. Folding a *copy* to
  compare it changes nothing that is stored.
  """
  @spec fold(String.t()) :: String.t()
  def fold(text) when is_binary(text) do
    text
    |> String.graphemes()
    |> Enum.map_join(fn char ->
      case @classes do
        %{^char => [representative | _]} -> representative
        _ -> char
      end
    end)
  end

  @doc """
  Expands a query into every orthographic form it could be written in.

  Returns `{forms, expansions}` — the full list of query strings to OR-match, and a
  per-character record of what was expanded, so the caller can report it.

      iex> {forms, _} = Pramana.Retrieval.Variants.expand("眾生")
      iex> "众生" in forms and "眾生" in forms
      true

  ## The combinatorial guard

  Each variant character multiplies the number of forms: a 6-character query where every
  character has three variants is 729 strings, and OR-matching that many `LIKE` patterns
  would be slower than the search it is meant to help. Expansion stops at `max_forms`
  (default 64) and says so, rather than quietly truncating or quietly hanging.
  """
  @spec expand(String.t(), keyword()) :: {[String.t()], map()}
  def expand(query, opts \\ []) do
    max_forms = Keyword.get(opts, :max_forms, 64)
    chars = String.graphemes(query)

    expansions =
      chars
      |> Enum.filter(&variants?/1)
      |> Map.new(&{&1, variants_of(&1)})

    forms = build_forms(chars, max_forms)

    {forms,
     %{
       expanded: expansions,
       forms: length(forms),
       truncated: truncated?(chars, max_forms)
     }}
  end

  defp build_forms(chars, max_forms) do
    chars
    |> Enum.reduce([""], &extend(&2, &1, max_forms))
    |> Enum.uniq()
  end

  defp extend(prefixes, char, max_forms) do
    forms = variants_of(char)

    if length(prefixes) * length(forms) > max_forms do
      # Past the budget, stop varying and keep the character as written. The original
      # query always survives, so expansion can only ever ADD recall.
      Enum.map(prefixes, &(&1 <> char))
    else
      for prefix <- prefixes, form <- forms, do: prefix <> form
    end
  end

  defp truncated?(chars, max_forms) do
    chars
    |> Enum.reduce(1, fn char, acc -> acc * length(variants_of(char)) end)
    |> Kernel.>(max_forms)
  end
end
