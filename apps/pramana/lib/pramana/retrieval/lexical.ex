defmodule Pramana.Retrieval.Lexical do
  @moduledoc """
  Lexical retrieval over the baked corpus: bigram-accelerated substring search with
  provenance filtering.

  Results are the **same span shape** `Pramana.Corpus.resolve/1` returns — URN,
  offsets, sha256, provenance — so anything found here can be verified by the guard
  without a second code path (`CLAUDE.md` invariant #1).

  ## Search modes

  - `:phrase` — the whole query as one contiguous substring. Highest precision.
  - `:ngram` — overlapping character windows from the query, ranked by how many
    windows a passage contains. Vocabulary-independent.
  - `:terms` — the query segmented by jieba. **Unreliable on this corpus**; see below.
  - `:auto` (default) — phrase first, then `:ngram`. An exact hit beats a scattered
    one, but no result at all is worse than a scattered one.

  ## Why the fallback is n-grams and not jieba

  jieba is trained on modern Chinese and does not know Buddhist vocabulary. Measured
  against the actual corpus:

      般若波羅蜜多心經  ->  ["般若", "波", "羅", "蜜", "多心", "經"]
      耆闍崛山          ->  ["耆", "闍", "崛", "山"]
      摩訶迦旃延        ->  ["摩", "訶", "迦", "旃", "延"]
      阿耨多羅三藐三菩提 -> ["阿", "耨", "多", "羅", "三", "藐", "三", "菩提"]

  It shatters transliterated Sanskrit into single characters and invents a spurious
  word ("多心"). OR-matching those characters returns noise, because a single common
  character appears on nearly every line.

  Character n-grams need no dictionary, so they cannot fail this way: `波羅蜜` is a
  window of `般若波羅蜜多心經` whether or not any lexicon has heard of it. jieba is
  kept — word boundaries matter for the Phase 6 reading layer, where 多音字
  disambiguation is context-dependent, and for the later modern-Chinese medical
  corpus — but it is not the retrieval fallback.

  ## Ranking

  Deliberately simple and explainable, because this is lexical retrieval and its job
  is precision on terms the user actually typed:

  1. number of distinct query terms present (desc)
  2. total occurrences (desc)
  3. `ordinal` (asc) — so equal scores return in reading order rather than at random

  There is no TF-IDF here. Document-frequency weighting over a corpus this
  homogeneous mostly rewards rare characters, and semantic weighting is what the
  Phase 1 embedding stage is for. Pretending to rank semantically with a lexical
  index would make the fusion in `Retrieval.Hybrid` harder to reason about.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Corpus.Segment
  alias Pramana.Corpus.Source
  alias Pramana.Corpus.Text
  alias Pramana.Repo
  alias Pramana.Retrieval.Variants

  @default_limit 20
  @max_limit 200

  # Every option this module understands. An unknown key is a BUG, not a no-op: a
  # `division:` filter silently dropped here (while Semantic honoured it) contaminated
  # hybrid results with works from outside the requested division, and the results
  # still looked filtered because half the pipeline had applied it.
  @known_opts [
    :normalize_variants,
    :redistributable_only,
    :license_class,
    :limit,
    :mode,
    :origin,
    :role,
    :division,
    :work_id,
    :juan,
    :exclude_origin,
    :serving,
    :lexical_only,
    :semantic_only
  ]

  @type result :: %{
          span: Corpus.span(),
          score: %{terms_matched: non_neg_integer(), occurrences: non_neg_integer()},
          matched_terms: [String.t()]
        }

  @type opts :: [
          limit: pos_integer(),
          mode: :auto | :phrase | :ngram | :terms,
          origin: String.t() | [String.t()],
          role: String.t() | [String.t()],
          work_id: String.t(),
          juan: pos_integer(),
          exclude_origin: String.t() | [String.t()]
        ]

  @doc """
  Searches the corpus.

      search("如是我聞")
      search("空", origin: "indic", role: "translation", limit: 5)
      search("般若波羅蜜", mode: :terms)

  Returns `{:ok, %{results: [...], mode: used_mode, terms: [...], total: n}}`.
  """
  @spec search(String.t(), opts()) :: {:ok, map()} | {:error, atom()}
  def search(query, opts \\ [])

  def search(query, opts) when is_binary(query) do
    validate_opts!(opts)

    case String.trim(query) do
      "" -> {:error, :empty_query}
      trimmed -> do_search(trimmed, opts)
    end
  end

  def search(_, _), do: {:error, :bad_query}

  @modes [:auto, :phrase, :ngram, :terms]

  defp do_search(query, opts) do
    mode = Keyword.get(opts, :mode, :auto)

    unless mode in @modes do
      raise ArgumentError,
            "unknown lexical mode #{inspect(mode)}; expected one of #{inspect(@modes)}"
    end

    case mode do
      :phrase ->
        {:ok, run(query, [query], opts, :phrase)}

      :ngram ->
        {:ok, run(query, ngrams(query), opts, :ngram)}

      :terms ->
        {:ok, run(query, terms(query), opts, :terms)}

      :auto ->
        phrase = run(query, [query], opts, :phrase)

        if phrase.total > 0,
          do: {:ok, phrase},
          else: {:ok, run(query, ngrams(query), opts, :ngram)}
    end
  end

  @doc """
  Overlapping character windows from a query.

      iex> Pramana.Retrieval.Lexical.ngrams("般若波羅蜜")
      ["般若波", "若波羅", "波羅蜜"]

  Width 3 is the useful default for Classical Chinese: 2 is common enough to match
  almost anything, and 4 rarely survives a compound boundary. Queries shorter than the
  window are used whole.
  """
  @spec ngrams(String.t(), pos_integer()) :: [String.t()]
  def ngrams(query, width \\ 3) do
    graphemes = String.graphemes(query)

    if length(graphemes) <= width do
      [query]
    else
      graphemes
      |> Enum.chunk_every(width, 1, :discard)
      |> Enum.map(&Enum.join/1)
      |> Enum.reject(&(punctuation?(&1) or String.contains?(&1, ["\n"])))
      |> Enum.uniq()
    end
  end

  @doc """
  Segments a query into terms.

  Uses the jieba NIF, then drops terms that carry no retrieval signal: pure
  punctuation and single-character grammatical particles like 之, 於, 者, which appear
  in nearly every line and would flood the OR match. Content characters are kept even
  when single, because in Classical Chinese one character is frequently a whole word
  (空, 道, 法).

  **Not the default fallback** — see the module doc for why jieba is unreliable on
  Buddhist vocabulary. Retained for the reading layer and for modern Chinese.
  """
  @spec terms(String.t()) :: [String.t()]
  def terms(query) do
    query
    |> PramanaNative.segment()
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or punctuation?(&1) or particle?(&1)))
    |> Enum.uniq()
    |> case do
      [] -> [query]
      terms -> terms
    end
  end

  # Grammatical particles, not content. Single-character *content* words are kept.
  @particles ~w(之 於 者 而 以 其 則 乃 亦 且 夫 蓋 焉 耳 兮 與 為 也 矣 哉)
  defp particle?(term), do: term in @particles

  defp punctuation?(term), do: String.match?(term, ~r/\A[[:punct:]。、，；：？！「」『』（）　]+\z/u)

  defp run(query, terms, opts, mode) do
    limit = opts |> Keyword.get(:limit, @default_limit) |> min(@max_limit) |> max(1)
    {terms, variants} = maybe_expand_variants(terms, opts)

    rows =
      Segment
      |> join(:inner, [s], t in Text, on: t.id == s.text_id)
      |> preload([_s, t], text: {t, [:work, :witness, :source]})
      |> where(^match_filter(terms))
      |> apply_provenance_filters(opts)
      # Over-fetch, then rank in Elixir. Scoring needs occurrence counts per term,
      # which is awkward and slow in SQL; the candidate set from a bigram index is
      # small enough that ranking in memory is cheaper than a clever query.
      |> limit(^(limit * 5))
      |> Repo.all()

    rows
    |> Enum.map(&score(&1, terms))
    |> Enum.sort_by(fn r -> {-r.score.terms_matched, -r.score.occurrences, r.ordinal} end)
    |> Enum.take(limit)
    |> Enum.map(&Map.delete(&1, :ordinal))
    |> then(fn results ->
      %{
        results: results,
        mode: mode,
        query: query,
        terms: terms,
        total: length(results),
        # Reported so a hit on a DIFFERENT orthographic form is visible rather than
        # surprising: a reader who searched 众生 and got 眾生 should be told why.
        variants: variants
      }
    end)
  end

  # Query-side only. The index is never normalised — which Han form an edition prints is
  # scholarly data, not noise. See `Pramana.Retrieval.Variants`.
  defp maybe_expand_variants(terms, opts) do
    if opts[:normalize_variants] do
      {expanded, metas} =
        Enum.map_reduce(terms, %{}, fn term, acc ->
          {forms, meta} = Variants.expand(term)
          {forms, Map.merge(acc, meta.expanded)}
        end)

      {expanded |> List.flatten() |> Enum.uniq(), %{expanded: metas, applied: true}}
    else
      {terms, %{expanded: %{}, applied: false}}
    end
  end

  # Any-term match. Each LIKE '%term%' is accelerated by the gin_bigm_ops index.
  defp match_filter(terms) do
    Enum.reduce(terms, dynamic(false), fn term, acc ->
      pattern = "%" <> escape_like(term) <> "%"
      dynamic([s], ^acc or like(s.content, ^pattern))
    end)
  end

  # A query is user input: %, _ and \ must not be read as LIKE metacharacters.
  defp escape_like(term) do
    term
    |> String.replace("\\", "\\\\")
    |> String.replace("%", "\\%")
    |> String.replace("_", "\\_")
  end

  # Provenance filters compose as ordinary SQL predicates. This is the whole reason
  # the corpus lives in one Postgres — see docs/ARCHITECTURE.md, Stage 4.
  defp apply_provenance_filters(query, opts) do
    query
    |> filter_in(opts[:origin], :composition_origin)
    |> filter_in(opts[:role], :text_role)
    |> filter_in(opts[:division], :division)
    |> filter_not_in(opts[:exclude_origin], :composition_origin)
    |> filter_work(opts[:work_id])
    |> filter_juan(opts[:juan])
    |> filter_license(opts)
  end

  # THE FILTER THAT MAKES THE LICENCE POSTURE ENFORCEABLE.
  #
  # `license_class` was recorded and displayed from the start, but nothing could filter
  # on it — so "we publish the pipeline, not the corpus" was a promise kept by hand.
  # A public surface sets `redistributable_only: true` once and cannot then serve
  # CBETA (nc, not redistributable) or a restricted local text by accident.
  defp filter_license(query, opts) do
    query
    |> filter_redistributable(opts[:redistributable_only])
    |> filter_license_class(opts[:license_class])
  end

  defp filter_redistributable(query, true) do
    join(query, :inner, [s, t], src in Source, on: src.id == t.source_id and src.redistributable)
  end

  defp filter_redistributable(query, _), do: query

  defp filter_license_class(query, nil), do: query

  defp filter_license_class(query, value) do
    values = List.wrap(value)

    join(query, :inner, [s, t], src in Source,
      on: src.id == t.source_id and src.license_class in ^values
    )
  end

  @doc false
  def validate_opts!(opts) do
    case Keyword.keys(opts) -- @known_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown search option(s): #{inspect(unknown)}"
    end
  end

  defp filter_in(query, nil, _field), do: query

  defp filter_in(query, value, field) do
    values = List.wrap(value)

    join(query, :inner, [s, t], w in Pramana.Corpus.Work,
      on: w.id == t.work_id and field(w, ^field) in ^values
    )
  end

  defp filter_not_in(query, nil, _field), do: query

  defp filter_not_in(query, value, field) do
    values = List.wrap(value)

    join(query, :inner, [s, t], w in Pramana.Corpus.Work,
      on: w.id == t.work_id and (field(w, ^field) not in ^values or is_nil(field(w, ^field)))
    )
  end

  defp filter_work(query, nil), do: query
  defp filter_work(query, work_id), do: where(query, [_s, t], t.work_id == ^work_id)

  defp filter_juan(query, nil), do: query
  defp filter_juan(query, juan), do: where(query, [s], s.juan == ^juan)

  defp score(%Segment{} = segment, terms) do
    matched = Enum.filter(terms, &String.contains?(segment.content, &1))
    occurrences = Enum.sum(Enum.map(matched, &count_occurrences(segment.content, &1)))

    %{
      span: Corpus.span_from_segment(segment),
      matched_terms: matched,
      score: %{terms_matched: length(matched), occurrences: occurrences},
      ordinal: segment.ordinal
    }
  end

  defp count_occurrences(_content, ""), do: 0

  defp count_occurrences(content, term) do
    content |> String.split(term) |> length() |> Kernel.-(1)
  end
end
