defmodule Pramana.Definitions do
  @moduledoc """
  Finds the canon defining its own terms, so a definition can be **quoted** rather than
  composed.

  ## The formulae

  Both traditions mark a definition with a fixed interrogative formula, because these
  texts were composed to be memorised and recited. Chinese translators rendered the Indic
  formula consistently enough that it is a reliable string:

  | language | formula | reads as |
  |---|---|---|
  | Literary Chinese | 云何為X | "what is X?" |
  | | 何謂X | "what is called X?" |
  | | 何等為X | "what constitutes X?" |
  | | 何者為X | "which is X?" |
  | Pāli | Katamañca X | "and what is X?" |
  | | Katamo ca X / Katamā ca X | (gendered variants) |
  | | Kiñca X | "and what is X?" |

  The answer follows immediately. So "what does the canon mean by 正見 / sammā-diṭṭhi?"
  has a *deterministic* answer: find the formula, return the passage, and let the reader
  see the tradition's own words with a citation they can check.

  ## Why this matters more than it looks

  `CLAUDE.md` invariant #5 is *deterministic before probabilistic*. Asking a model to
  define a Buddhist technical term produces fluent prose synthesised from its training
  data, attributable to nothing. Asking this module produces 佛告比丘…云何為正見… at
  `T0099_028@p0203a25`, which a reader can check against the printed page.

  The system does not know what the term *means*. It knows where the canon says what it
  means, which is a smaller claim and a much more useful one.

  ## What this is not

  It is not a dictionary, and it does not rank definitions by quality. Several texts
  define the same term differently — that is doctrinal history, not noise — so every
  match is returned with its provenance, and a Sarvāstivāda Abhidharma definition stays
  distinguishable from a Mahāyāna sūtra's.
  """

  alias Pramana.Retrieval.Lexical

  # Formulae are ordered strongest-first: 云何為 is unambiguous, while 何謂 also occurs in
  # ordinary rhetorical questions. Order becomes the ranking when several match.
  @chinese ["云何為", "云何", "何謂", "何等為", "何者為"]
  @pali ["Katamañca", "Katamo ca", "Katamā ca", "Katame ca", "Kiñca"]

  @doc "The definitional formulae, by language."
  @spec formulae() :: %{String.t() => [String.t()]}
  def formulae, do: %{"lzh" => @chinese, "pli" => @pali}

  @doc """
  Finds passages where the canon defines `term`.

  Options are passed through to `Pramana.Retrieval.Lexical.search/2`, so the provenance
  and licence filters apply here too — a public surface can ask for definitions from
  redistributable sources only.

  Returns `%{term:, language:, results: [...], formulae_tried: [...]}`. `results` is
  empty when the canon does not define the term in a recognised formula, which is a real
  answer and is not padded with near-misses.
  """
  @spec find(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def find(term, opts \\ []) do
    term = String.trim(term)
    language = Keyword.get_lazy(opts, :language, fn -> detect_language(term) end)
    formulae = Map.get(formulae(), language, @chinese)
    limit = Keyword.get(opts, :limit, 10)

    search_opts =
      opts
      |> Keyword.drop([:language])
      |> Keyword.put(:limit, limit)
      # `:phrase`, the atom the retriever expects. Passing the string would raise, and
      # converting a caller-supplied string with `String.to_existing_atom/1` is what
      # crashed this codebase twice on module load order.
      |> Keyword.put(:mode, :phrase)

    results =
      formulae
      |> Enum.flat_map(&search_formula(&1, term, language, search_opts))
      |> Enum.uniq_by(& &1.span.urn)
      |> Enum.take(limit)

    {:ok,
     %{
       term: term,
       language: language,
       formulae_tried: formulae,
       results: results,
       total: length(results)
     }}
  end

  # The phrase is searched as a literal string — formula immediately followed by the
  # term. That adjacency is the whole signal: 正見 appears thousands of times, and
  # 云何為正見 is the handful of places the canon stops to say what it is.
  defp search_formula(formula, term, language, opts) do
    phrase = phrase_for(formula, term, language)

    case Lexical.search(phrase, opts) do
      {:ok, %{results: results}} ->
        Enum.map(results, fn result ->
          result
          |> Map.put(:formula, formula)
          |> Map.put(:matched_phrase, phrase)
        end)

      {:error, _} ->
        []
    end
  end

  # Literary Chinese runs formula and term together; Pāli separates them with a space.
  defp phrase_for(formula, term, "pli"), do: formula <> " " <> term
  defp phrase_for(formula, term, _), do: formula <> term

  @doc """
  Guesses which tradition's formulae to use, from the script the term is written in.

  Deliberately a guess about *script*, not about meaning: a term in Han characters gets
  the Chinese formulae, anything else gets the Pāli ones. Callers who know better pass
  `language:` explicitly.
  """
  @spec detect_language(String.t()) :: String.t()
  def detect_language(term) do
    if String.match?(term, ~r/\p{Han}/u), do: "lzh", else: "pli"
  end
end
