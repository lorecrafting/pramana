defmodule Pramana.Retrieval.Hybrid do
  @moduledoc """
  Fuses lexical and semantic retrieval with Reciprocal Rank Fusion.

  The two find different things, and neither subsumes the other:

  - **Lexical** (bigram index over segments) finds the characters you typed. It is the
    only thing that reliably finds 阿㝹樓馱 — a transliteration no dictionary or model
    was trained on — and it never hallucinates a match.
  - **Semantic** (BGE-M3 vectors over chunks) finds meaning. Searching 佛性 surfaces
    passages that say 如來藏; asking 苦的原因是什麼 in modern Chinese surfaces the
    Second Noble Truth in Classical Chinese. Lexical cannot do either.

  ## Why RRF rather than score blending

  Lexical scores are occurrence counts and semantic scores are cosine similarities.
  They have no common scale, and normalising them requires picking a weighting that
  is really a guess dressed as arithmetic. RRF ignores the scores entirely and uses
  only **rank**:

      score(d) = Σ  1 / (k + rank_i(d))

  with `k = 60` by convention. It is robust precisely because it throws information
  away: a document ranked 1st by either retriever scores well without either
  retriever's scale mattering.

  ## Granularity

  Lexical returns segments (printed lines); semantic returns chunks (~300-char
  windows). Fusion happens at **chunk** level, with each lexical hit mapped to its
  containing chunk — which is also `docs/ARCHITECTURE.md`'s two-level design: embed the
  window for recall, return the containing unit for readability.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Chunk
  alias Pramana.Corpus.Segment
  alias Pramana.Repo
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Semantic

  # The conventional RRF constant. Larger flattens the contribution of top ranks.
  @k 60
  @default_limit 20

  @type opts :: [
          limit: pos_integer(),
          serving: Nx.Serving.t(),
          origin: String.t() | [String.t()],
          role: String.t() | [String.t()],
          division: String.t(),
          work_id: String.t(),
          exclude_origin: String.t() | [String.t()],
          lexical_only: boolean(),
          semantic_only: boolean()
        ]

  @doc """
  Searches lexically and semantically, then fuses by rank.

  Degrades honestly: if no serving is available or nothing is embedded yet, it returns
  lexical results and says so in `:retrievers`, rather than pretending semantic ran.
  """
  @spec search(String.t(), opts()) :: {:ok, map()} | {:error, atom()}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    case String.trim(query) do
      "" -> {:error, :empty_query}
      trimmed -> {:ok, run(trimmed, opts)}
    end
  end

  def search(_, _), do: {:error, :bad_query}

  defp run(query, opts) do
    limit = Keyword.get(opts, :limit, @default_limit)
    # Over-fetch from each retriever: fusion needs depth to work with, and a document
    # ranked 30th by one retriever can win once the other agrees.
    depth = limit * 3

    lexical = if opts[:semantic_only], do: [], else: lexical_ranking(query, opts, depth)
    semantic = semantic_ranking(query, opts, depth)

    fused =
      [lexical, semantic]
      |> Enum.reject(&(&1 == []))
      |> fuse()
      |> Enum.take(limit)
      |> Enum.map(&decorate/1)

    %{
      query: query,
      results: fused,
      total: length(fused),
      # Which retrievers actually contributed. Reported rather than assumed: with no
      # serving, or nothing embedded yet, this is lexical-only, and an answer built on
      # half the intended evidence should say so.
      retrievers: retrievers(lexical, semantic),
      coverage: Semantic.coverage(Keyword.take(opts, [:origin, :role, :division, :work_id])),
      bake_id: Pramana.Bake.current_id()
    }
  end

  # -- retrieval ------------------------------------------------------------------

  defp retrievers(lexical, semantic) do
    Enum.reject(
      [if(lexical != [], do: "lexical"), if(semantic != [], do: "semantic")],
      &is_nil/1
    )
  end

  # Lexical hits are segments; map each to the chunk that contains it so both
  # retrievers speak in the same units.
  defp lexical_ranking(query, opts, depth) do
    # `mode` here is HYBRID's mode (:hybrid, :semantic), which means nothing to the
    # lexical retriever. Passing it through crashed with a raw CaseClauseError. The
    # lexical stage always runs its own :auto strategy.
    lexical_opts = opts |> Keyword.merge(limit: depth) |> Keyword.put(:mode, :auto)

    case Lexical.search(query, lexical_opts) do
      {:ok, %{results: results}} ->
        results
        |> Enum.map(& &1.span.urn)
        |> chunk_urns_for_segments()

      {:error, _} ->
        []
    end
  end

  defp semantic_ranking(query, opts, depth) do
    serving = opts[:serving]

    cond do
      opts[:lexical_only] ->
        []

      is_nil(serving) ->
        []

      true ->
        case Semantic.search(query, opts |> Keyword.merge(limit: depth) |> Keyword.delete(:mode)) do
          {:ok, %{results: results}} -> Enum.map(results, & &1.urn)
          {:error, _} -> []
        end
    end
  end

  defp chunk_urns_for_segments([]), do: []

  defp chunk_urns_for_segments(segment_urns) do
    rows =
      Repo.all(
        from s in Segment,
          join: c in Chunk,
          on:
            c.text_id == s.text_id and s.ordinal >= c.first_ordinal and
              s.ordinal <= c.last_ordinal,
          where: s.urn in ^segment_urns,
          select: {s.urn, c.urn}
      )
      |> Map.new()

    # Preserve the lexical ordering and de-duplicate, since several hits can land in
    # one chunk.
    #
    # A segment with no containing chunk falls back to its OWN urn rather than being
    # dropped. Dropping it meant that on a corpus where chunking had not been run,
    # hybrid returned nothing at all while lexical alone returned results — silently
    # worse than not fusing. Both forms are real, citable, guard-verifiable URNs.
    segment_urns
    |> Enum.map(fn urn -> Map.get(rows, urn, urn) end)
    |> Enum.uniq()
  end

  # -- fusion ---------------------------------------------------------------------

  @doc """
  Reciprocal Rank Fusion over ranked lists of URNs.

  Pure and exposed so the ranking rule can be tested without a database or a model.
  """
  @spec fuse([[String.t()]], pos_integer()) :: [{String.t(), float()}]
  def fuse(rankings, k \\ @k) do
    rankings
    |> Enum.flat_map(fn ranking ->
      ranking
      |> Enum.with_index(1)
      |> Enum.map(fn {urn, rank} -> {urn, 1 / (k + rank)} end)
    end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {urn, scores} -> {urn, Enum.sum(scores)} end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
  end

  defp decorate({urn, score}) do
    case Corpus.resolve(urn) do
      {:ok, span} -> %{urn: urn, rrf_score: Float.round(score, 6), span: span}
      {:error, _} -> %{urn: urn, rrf_score: Float.round(score, 6), span: nil}
    end
  end
end
