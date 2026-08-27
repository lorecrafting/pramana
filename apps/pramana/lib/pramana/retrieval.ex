defmodule Pramana.Retrieval do
  @moduledoc """
  One entry point for search, so every surface asks the corpus the same question.

  `Hybrid`, `Lexical` and `Semantic` are the strategies; choosing between them by name,
  wiring the embedding serving, and mapping a mode string to a mode is **dispatch**, and
  dispatch belongs in the domain. It did not: the MCP tool held it, and the Phase 8
  reader would have held a second copy. Two surfaces that route `"semantic"` differently
  do not have a UI bug, they have a corpus that answers the same question two ways.

  ## Modes

  | mode | what it does | strength of evidence |
  |---|---|---|
  | `:hybrid` | lexical and semantic, fused by rank | strongest, and the default |
  | `:semantic` | meaning only | finds paraphrase; never proves wording |
  | `:phrase` | the exact characters | strong — the passage says what you typed |
  | `:ngram` | character windows | weak; a fallback, and reported as one |
  | `:terms` | jieba segmentation | unreliable for Buddhist vocabulary |
  | `:auto` | phrase, falling back to n-gram | reports which one answered |

  Hybrid degrades honestly rather than failing: with no serving running, or nothing
  embedded, it returns lexical results and says so in `:retrievers`.
  """

  alias Pramana.Embed
  alias Pramana.Retrieval.Hybrid
  alias Pramana.Retrieval.Lexical

  # Mapped explicitly, NEVER via `String.to_existing_atom/1`. That crashed the MCP tool
  # by load order: the guard admitted `"phrase"` and the conversion then raised, because
  # `:phrase` enters the atom table only when `Lexical` loads — which happened later, in
  # dispatch. `mode: "phrase"` as the first search in a fresh VM raised; the same call
  # after any hybrid search worked, and every test passed because something always ran
  # hybrid first. The atom table is global mutable state; this map is not.
  @modes %{
    "hybrid" => :hybrid,
    "semantic" => :semantic,
    "auto" => :auto,
    "phrase" => :phrase,
    "ngram" => :ngram,
    "terms" => :terms
  }

  @doc "The mode names a caller may supply, for building a UI or validating input."
  @spec modes() :: [String.t()]
  def modes, do: Map.keys(@modes)

  @doc """
  Parses a mode name, falling back to `:hybrid` for anything unrecognised.

  Falling back rather than raising, because a mode is a *preference* about strategy and
  an unknown one still has an obviously right answer. Contrast an unknown FILTER, which
  `Lexical` and `Semantic` raise on: a dropped filter returns results from outside the
  provenance the caller asked for and still looks filtered.
  """
  @spec mode(String.t() | atom() | nil) :: atom()
  def mode(nil), do: :hybrid
  def mode(mode) when is_atom(mode), do: if(mode in Map.values(@modes), do: mode, else: :hybrid)
  def mode(mode) when is_binary(mode), do: Map.get(@modes, mode, :hybrid)

  @doc """
  Runs a search in the given mode.

  `opts` are the retrieval options (`:limit`, `:origin`, `:role`, `:division`,
  `:work_id`, and so on) plus `:mode`. The embedding serving is supplied here rather
  than by each caller: a surface that forgets it gets lexical-only results and is told
  it got lexical-only results, which is honest but is not what anyone meant.
  """
  @spec search(String.t(), keyword()) :: {:ok, map()} | {:error, atom()}
  def search(query, opts \\ []) do
    {mode, opts} = Keyword.pop(opts, :mode)

    case mode(mode) do
      :hybrid ->
        Hybrid.search(query, Keyword.put(opts, :serving, Embed.Serving.name()))

      :semantic ->
        Hybrid.search(
          query,
          opts |> Keyword.put(:serving, Embed.Serving.name()) |> Keyword.put(:semantic_only, true)
        )

      lexical_mode ->
        # Dropped, not passed through: `Lexical` RAISES on an unknown option, deliberately
        # — a silently ignored `division:` once contaminated hybrid results with works from
        # outside the requested division while still looking filtered. So a caller may hand
        # this function one option list for any mode, and the dispatcher is what knows that
        # `:coverage` means nothing to a phrase search.
        opts = Keyword.take(opts, Lexical.known_opts())
        Lexical.search(query, Keyword.put(opts, :mode, lexical_mode))
    end
  end
end
