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
  alias Pramana.Embed.Serving
  alias Pramana.Repo
  alias Pramana.Retrieval.Lexical
  alias Pramana.Retrieval.Rerank
  alias Pramana.Retrieval.Semantic
  alias Pramana.Retrieval.Terms

  # The conventional RRF constant. Larger flattens the contribution of top ranks.
  #
  # Overridable per call (`rrf_k:`) so it can be SWEPT against the gold set rather than
  # argued about. 60 is convention, not a measurement — every other retrieval constant
  # here earned its value from `evals/` and this one never has.
  @k 60
  @default_limit 20

  # Mirrors the retrievers' own ceiling. Kept here because Hybrid bounds `depth` against
  # it before either retriever sees a number.
  @max_limit 200

  # THE TWO ARMS LOOK DIFFERENT DISTANCES, AND THE MULTIPLIERS ARE MEASURED, NOT CHOSEN.
  #
  # `limit * 3` for both was the shipped default until the gold set separated them. Depth
  # was known to be worth +5 of 64 `retrieval/tibetan` cases, reproduced five times, and to
  # cost ~4x on the full 446-case set — which is why it was refused as a default twice.
  # The cost and the benefit turned out to sit in DIFFERENT retrievers. Three arms over the
  # 64 Tibetan cases, prediction registered before the run:
  #
  #     both 60 (control)            20/64   298 s
  #     semantic 120, lexical 60     25/64   465 s
  #     lexical 120, semantic 60     20/64   303 s
  #
  # - the BENEFIT is semantic. A Tibetan gold query is ENGLISH (an 84000 rendering), so the
  #   lexical arm contributes nothing to it however deep it looks; the gain comes from the
  #   right chunk sitting further down an HNSW ranking that BGE-M3 barely discriminates —
  #   Tibetan sits at 0.9727 mean pairwise cosine, so its candidates are near-ties.
  # - the COST is lexical, and it is Chinese. A definitional-formula query matches
  #   thousands of segments, so `limit * 5` over-fetch pulls `depth * 5` segments out of
  #   the bigram index and maps every one to its containing chunk — per-segment work
  #   scaling directly with depth, over the 232 Chinese cases that dominate any full run.
  #
  # On the full 446-case set this scores **334/446 (74.9%)** against 328 at the old
  # default: chinese 227/232 flat, pali 82/150, tibetan 25/64. That is the SAME total depth
  # 200 reached, at 1h50m against its 4h25m — the whole of depth 200's price was being paid
  # by an arm contributing none of its gain.
  @lexical_multiplier 3
  @semantic_multiplier 6

  @type opts :: [
          limit: pos_integer(),
          # The RRF constant and the rerank over-fetch multiplier. Both default to the
          # shipped values and exist as options so a sweep can move them without editing
          # the module — a configuration measured is worth more than a constant defended.
          rrf_k: pos_integer(),
          rerank_multiplier: pos_integer(),
          serving: Nx.Serving.t(),
          origin: String.t() | [String.t()],
          role: String.t() | [String.t()],
          division: String.t(),
          work_id: String.t(),
          exclude_origin: String.t() | [String.t()],
          balance: :tradition | nil,
          per_tradition: boolean(),
          # `false` skips the embedding-coverage count and reports `:not_computed`. For a
          # caller that never reads it — the eval harness — not for an API surface, where
          # the number is what stops partial embedding being read as a small canon.
          coverage: boolean(),
          # Candidates fetched before fusion, bounded by the retrievers' maximum. `depth`
          # sets both arms at once; the per-arm keys override one each. The defaults are
          # NOT equal — `limit * 3` lexical, `limit * 6` semantic — because the gold set
          # measured the gain as entirely semantic and the cost as almost entirely lexical.
          depth: pos_integer(),
          lexical_depth: pos_integer(),
          semantic_depth: pos_integer(),
          lexical_only: boolean(),
          semantic_only: boolean(),
          # Reorder the fused candidates by how much of the query appears in each one's
          # stored English rendering. ON by default; `false` opts out. See
          # `Pramana.Retrieval.Rerank`.
          rerank: boolean(),
          # Expand English doctrinal terms to the Chinese the canon prints, as a third
          # fused arm. OFF by default — measured at +2 of 12 and not worth the dilution.
          expand_terms: boolean()
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
    limit = validated_limit(opts)
    lexical_depth = arm_depth(opts, :lexical_depth, limit, @lexical_multiplier)
    semantic_depth = arm_depth(opts, :semantic_depth, limit, @semantic_multiplier)

    lexical = if opts[:semantic_only], do: [], else: lexical_ranking(query, opts, lexical_depth)
    scored_semantic = semantic_ranking(query, opts, semantic_depth)
    semantic = Enum.map(scored_semantic, &elem(&1, 0))
    {translated, expanded_terms} = translated_ranking(query, opts, lexical_depth)

    fused =
      [lexical, semantic, translated]
      |> Enum.reject(&(&1 == []))
      |> fuse(Keyword.get(opts, :rrf_k, @k))
      # Rerank over a WIDER slice than the caller asked for, then cut. Reordering only
      # the top `limit` cannot promote anything from below it, and the whole gain is
      # candidates sitting at ranks 11-50 (median 37).
      |> Enum.take(rerank_depth(opts, limit))
      |> Enum.map(&decorate/1)
      |> maybe_rerank(query, opts)
      |> Enum.take(limit)

    %{
      query: query,
      results: fused,
      total: length(fused),
      # Which retrievers actually contributed. Reported rather than assumed: with no
      # serving, or nothing embedded yet, this is lexical-only, and an answer built on
      # half the intended evidence should say so.
      retrievers: retrievers(lexical, semantic, translated),
      # What the English query was expanded to, so a hit on a Chinese term the
      # reader never typed is visible rather than surprising — the same reporting
      # rule `Variants` follows for 異體字.
      expanded_terms: expanded_terms,
      # How close the best semantic match was. `nil` when the semantic arm did not run,
      # which is a different statement from "nothing was close" and must stay
      # distinguishable — see `confidence/1`.
      semantic_confidence: confidence(scored_semantic, length(lexical)),
      coverage: coverage(opts),
      bake_id: Pramana.Bake.current_id()
    }
  end

  # Hybrid never handed the caller's `limit` to a retriever — it hands them `depth` — so
  # the over-limit check added to `Lexical` and `Semantic` did not cover this path at all:
  # `Hybrid.search(q, limit: 500)` clamped `depth` to 200, returned at most 200, and said
  # nothing. Exactly the silence that check exists to remove, one layer up.
  defp validated_limit(opts) do
    case Keyword.get(opts, :limit, @default_limit) do
      limit when is_integer(limit) and limit > @max_limit ->
        raise ArgumentError,
              "limit #{limit} exceeds the maximum of #{@max_limit}; ask for at most " <>
                "#{@max_limit}, and clamp at your own boundary if the value came from a user"

      limit ->
        limit
    end
  end

  # How many candidates each retriever is asked for, before fusion picks `limit` of them.
  # Fusion needs depth to work with: a document ranked 30th by one retriever can win once
  # the other agrees. The per-arm multipliers and the evidence for them are at the top.
  #
  # An explicit `depth:` still sets BOTH arms, so a caller that asks for one number gets
  # one number; `lexical_depth:`/`semantic_depth:` override a single arm. Clamped rather
  # than refused, as before: depth is not a request from the caller, it is how hard this
  # layer looks before answering. Never below `limit`, because fusing fewer candidates
  # than the caller wants returned is incoherent.
  # How wide a slice the reranker sees. `limit * 5`, because the mis-ranked gold it exists
  # to recover sits at a median rank of 37 and reordering only the top `limit` could never
  # reach it. Bounded by the retrievers' ceiling like every other depth here.
  @rerank_multiplier 5

  defp rerank_depth(opts, limit) do
    multiplier = Keyword.get(opts, :rerank_multiplier, @rerank_multiplier)
    if rerank?(opts), do: min(limit * multiplier, @max_limit), else: limit
  end

  # ON BY DEFAULT, measured over the whole gold set and every category:
  #
  #     retrieval overall   334/446 -> 380/446   +46
  #       chinese           227/232 -> 227/232   flat (no English renderings to score)
  #       pali               82/150 -> 122/150   +40, mean rank 3.09 -> 1.51
  #       tibetan            25/64  ->  31/64    +6,  mean rank 3.24 -> 1.32
  #     topical overall      21/49  ->  26/49    +5
  #       topical/tibetan     0/9   ->   2/9     first non-zero ever recorded
  #     answered from any tradition  72.7% -> 81.8%
  #
  # Nothing regressed, which is what #44 requires of a default. `rerank: false` opts out.

  defp maybe_rerank(results, query, opts) do
    if rerank?(opts), do: Rerank.by_rendering(query, results), else: results
  end

  defp rerank?(opts), do: Keyword.get(opts, :rerank, true)

  defp arm_depth(opts, key, limit, multiplier) do
    explicit = Keyword.get(opts, key) || Keyword.get(opts, :depth)

    (explicit || limit * multiplier)
    |> min(@max_limit)
    |> max(limit)
  end

  # `:not_computed`, never `nil` and never a zeroed map. The whole reason this field
  # exists is that an empty result must not be mistaken for a small canon, and a caller
  # that reads `%{embedded: 0}` or `nil` learns exactly the wrong thing. An atom the
  # reader has to look at is the only safe way to say "we did not ask".
  #
  # Opt-out because it is not free: `Semantic.coverage/1` counts 560,238 chunks and probes
  # each for a vector, and `run/2` pays it once per query. The eval harness runs ~500
  # searching cases and reads this field in none of them.
  #
  # Measured, because the cost is not one number — it depends on whether Postgres still
  # has those pages:
  #
  #     ~520 ms   warm, twelve consecutive calls
  #     ~2,700 ms cold, immediately after a 3-hour eval evicted the chunk pages
  #     ~1,650 ms per case as actually observed end-to-end (see docs/CHECKS.md)
  #
  # The older figure recorded here and in `Semantic` was ~921 ms, which is a warm-cache
  # measurement of a smaller corpus and is no longer what a caller pays.
  defp coverage(opts) do
    if Keyword.get(opts, :coverage, true) do
      Semantic.coverage(Keyword.take(opts, [:origin, :role, :division, :work_id]))
    else
      :not_computed
    end
  end

  # -- retrieval ------------------------------------------------------------------

  defp retrievers(lexical, semantic, translated) do
    Enum.reject(
      [
        if(lexical != [], do: "lexical"),
        if(semantic != [], do: "semantic"),
        if(translated != [], do: "translated_terms")
      ],
      &is_nil/1
    )
  end

  # Lexical hits are segments; map each to the chunk that contains it so both
  # retrievers speak in the same units.
  # Options that mean something only to the vector stage. Kept next to the code that
  # drops them so a new one is added in one place.
  # `:per_tradition` belongs here for the same reason `:balance` does — it selects a
  # retrieval STRATEGY inside the vector stage, and the lexical retriever has no notion of
  # it. It was added to `Semantic` without being added here, which made
  # `Hybrid.search(q, per_tradition: true)` raise from `Lexical.validate_opts!/1`: the
  # option was reachable only by calling `Semantic` directly, so nothing that ships — the
  # MCP tools, the eval harness — could use it. There is a test for exactly this now.
  @semantic_only_opts [:vector_kinds, :vector_lang, :balance, :per_tradition, :serving]

  # Options that belong to THIS layer and mean nothing to either retriever, so they are
  # dropped before both. Both retrievers reject an option they do not know — correctly —
  # so a hybrid-level option that reaches either one crashes the search.
  @hybrid_only_opts [
    :coverage,
    :depth,
    :lexical_depth,
    :semantic_depth,
    :expand_terms,
    :rerank,
    # Fusion and rerank shape, swept against the gold set rather than argued about.
    :rrf_k,
    :rerank_multiplier
  ]

  # A THIRD ARM: the English query's doctrinal terms, searched in Chinese.
  #
  # `topical/chinese` is 0% while the same twelve questions asked in Chinese are 100% —
  # the passages are indexed, and only the query is in the wrong language. Rewriting the
  # query into Chinese scored 91.7% on those twelve. See `Retrieval.Terms` for why the
  # mapping is a glossary rather than a translation model: the failure mode is term
  # choice, worth ~50 points, and a glossary can expand to EVERY attested register
  # (念住 *and* 念處) where a model must gamble on one.
  #
  # A separate arm rather than a rewritten query, for two reasons. The existing arms are
  # untouched, so nothing that works today for Pāli or Tibetan can regress. And a mixed
  # English-plus-Chinese string would be embedded as one vector by the semantic arm, which
  # is not a thing either language's vectors look like.
  #
  # Opt-in. It has not yet been scored against `answered from any tradition`, which #44
  # requires of any change before it becomes a default.
  defp translated_ranking(query, opts, depth) do
    with true <- !!opts[:expand_terms],
         [_ | _] = terms <- Terms.expand(query) do
      {rank_terms(terms, opts, depth), terms}
    else
      _ -> {[], []}
    end
  end

  defp rank_terms(terms, opts, depth) do
    lexical_opts =
      opts
      |> Keyword.drop(@semantic_only_opts ++ @hybrid_only_opts)
      |> Keyword.merge(limit: depth)
      |> Keyword.put(:mode, :phrase)

    terms
    |> Enum.map(&term_ranking(&1, lexical_opts))
    |> Enum.reject(&(&1 == []))
    # Each term is its own ranked list, fused so a passage carrying two of the query's
    # terms outranks one carrying a single term.
    |> fuse()
    |> Enum.map(&elem(&1, 0))
  end

  defp term_ranking(term, lexical_opts) do
    case Lexical.search(term, lexical_opts) do
      {:ok, %{results: results}} ->
        results |> Enum.map(& &1.span.urn) |> chunk_urns_for_segments()

      {:error, _} ->
        []
    end
  end

  defp lexical_ranking(query, opts, depth) do
    # `mode` here is HYBRID's mode (:hybrid, :semantic), which means nothing to the
    # lexical retriever. Passing it through crashed with a raw CaseClauseError. The
    # lexical stage always runs its own :auto strategy.
    # Semantic-only options are DROPPED rather than passed through. The lexical retriever
    # rejects options it does not know — correctly, since a silently-ignored filter is the
    # bug it was hardened against — so handing it `vector_kinds` crashes the whole search.
    # Hybrid is the layer that knows which stage each option belongs to.
    lexical_opts =
      opts
      |> Keyword.drop(@semantic_only_opts ++ @hybrid_only_opts)
      |> Keyword.merge(limit: depth)
      |> Keyword.put(:mode, :auto)

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
    # Default to the serving that is actually RUNNING, rather than requiring every
    # caller to remember to pass it. Previously a caller who omitted `:serving` got
    # lexical-only results with a model loaded and idle in the same VM — and the only
    # symptom was a worse answer. The eval harness (#19) found this by scoring 0/40 on
    # English-to-Pāli retrieval that works perfectly when semantic runs.
    #
    # `Keyword.get/3` rather than `opts[:serving] ||`: a caller passing `serving: nil`
    # explicitly is asking for lexical, and must keep getting it.
    serving = Keyword.get(opts, :serving, Serving.name())

    cond do
      opts[:lexical_only] ->
        []

      is_nil(serving) ->
        []

      true ->
        search_opts =
          opts
          |> Keyword.drop(@hybrid_only_opts)
          |> Keyword.merge(limit: depth, serving: serving)
          |> Keyword.delete(:mode)

        case Semantic.search(query, search_opts) do
          {:ok, %{results: results}} -> Enum.map(results, &{&1.urn, &1.similarity})
          {:error, _} -> []
        end
    end
  end

  @doc """
  How close the best semantic match actually was, reported rather than acted on.

  ## Measured, 2026-08-27, over 40 answerable and 8 unanswerable queries

  The semantic arm returns its k nearest neighbours regardless of distance, so it cannot
  say "I have nothing" — for 本門戒體, a doctrine no text in this bake discusses, the
  lexical arm correctly returns 0 hits and the hybrid returns 5 semantic near-misses.
  Two candidate fixes were measured before either was built.

      top-1 similarity     min      max
        answerable        0.7188   0.9223    (Chinese queries 0.72–0.80, English 0.76–0.92)
        unanswerable      0.6042   0.7423

      gap (top1 - top10)
        answerable        0.0077   0.0957
        unanswerable      0.0055   0.0358    6 of 8 INSIDE the answerable range

  **The gap statistic does not separate**, which refutes the hypothesis this probe was
  written to test. `photosynthesis in C4 plants` has a wider top1–top10 spread than 13 of
  20 answerable Chinese queries. Discrimination was the right lens for the Tibetan adapter
  and is the wrong one here.

  **A hard threshold would cost about 45 retrieval cases to gain 1 absence case.** At 0.75
  — the lowest cut that admits none of the unanswerable set — 4 of 40 answerable queries
  are refused, 10%, which over 446 retrieval cases is ~45 lost. That is a catastrophic
  trade and the threshold is not shipped.

  So this REPORTS. The band is a reading aid calibrated on 48 queries, not a gate, and the
  same shape as `retrievers`, `mode` and `embedding_coverage`: the system says what it
  knows about its own answer and the caller decides. Note the scale is per-language —
  English queries sit a whole band above Chinese ones — which is a second reason no single
  cut-off could be right.

  ## The two arms together — a one-way signal, measured through the shipped path

  `lexical_support` is how many passages the lexical arm contributed. Alone it is
  useless, and the first measurement of it was also **wrong**, because it was taken by
  calling `Lexical.search/2` in `:phrase` mode rather than through this function. The
  hybrid's lexical arm falls back to character n-grams, so a paraphrase that matches no
  literal string still collects support: 眾生皆能成佛 scores 0 hits in phrase mode and
  **28** here. Measuring the component gave a cleaner-looking answer than measuring the
  thing that ships. That is the third time in one day a proxy has flattered a signal in
  this project.

  Re-measured through `Retrieval.search/2`, over 56 queries:

      lexical_support == 0 AND band != strong
        answerable, Chinese literal        0 of 20
        answerable, English -> bo/pli      0 of 20
        answerable, Chinese paraphrase     0 of 6
        unanswerable                       6 of 10

  **So it is one-way.** When it fires, nothing in 46 answerable queries fired with it —
  including every paraphrase, which is the case that would have killed it. When it does
  not fire, it says nothing at all: four unanswerable queries slipped through, three
  because the n-gram fallback found incidental character overlap, and one — 如何申報所得稅,
  *how do I file income tax* — because the semantic arm confidently placed it in the
  `strong` band at all.

  That last one is worth stating plainly: **the band alone can be confidently wrong.** It
  is a reading aid, and the combination is a stronger reading aid, and neither is a proof.
  Still reported, never enforced: no result is suppressed, so a caller who disagrees with
  this reading keeps every passage.
  """
  @spec confidence([{String.t(), float()}], non_neg_integer()) :: map() | nil
  def confidence(scored, lexical_support \\ 0)

  def confidence([], _lexical_support), do: nil

  def confidence(scored, lexical_support) do
    top = scored |> Enum.map(&elem(&1, 1)) |> Enum.max()
    band = band(top)

    %{
      top_similarity: Float.round(top, 4),
      band: band,
      lexical_support: lexical_support,
      note: note_for(band, lexical_support)
    }
  end

  # The combination first, because it is the stronger reading and a caller who stops at
  # the first sentence should get the more useful one.
  defp note_for(band, 0) when band != "strong" do
    "Nothing matches the characters typed, and the nearest passage by meaning is not as " <>
      "close as answerable queries usually are. Over 56 measured queries this combination " <>
      "occurred for 6 of 10 questions the corpus could NOT answer and 0 of 46 it could, " <>
      "paraphrases included. It is one-way: when it appears the corpus probably does not " <>
      "hold an answer, and when it is absent that means nothing either way. " <>
      confidence_note(band)
  end

  defp note_for(band, _lexical_support), do: confidence_note(band)

  # Boundaries from the probe above: no unanswerable query reached 0.75, and none of the
  # answerable ones fell below 0.70.
  defp band(top) when top >= 0.75, do: "strong"
  defp band(top) when top >= 0.70, do: "weak"
  defp band(_top), do: "no_close_match"

  defp confidence_note("strong"),
    do: "The nearest passage is as close as answerable queries usually are."

  defp confidence_note("weak"),
    do:
      "The nearest passage sits in the band where answerable and unanswerable queries " <>
        "overlap. Weigh these results as suggestions, not answers."

  defp confidence_note("no_close_match"),
    do:
      "Nothing in the corpus is close to this query. Every measured query in this range " <>
        "was one the corpus could not answer — these results are the nearest neighbours " <>
        "of a question with no answer here, not answers."

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
