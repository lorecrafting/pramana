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
    :source_id,
    :witness_id,
    :composed_after,
    :composed_before,
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
  Overlapping windows from a query, in the unit the script actually uses.

      iex> Pramana.Retrieval.Lexical.ngrams("般若波羅蜜")
      ["般若波", "若波羅", "波羅蜜"]

      iex> Pramana.Retrieval.Lexical.ngrams("སྟོང་པ་ཉིད")
      ["སྟོང་པ", "པ་ཉིད"]

  Width 3 is the useful default for Classical Chinese: 2 is common enough to match
  almost anything, and 4 rarely survives a compound boundary. Queries shorter than the
  window are used whole.

  ## Why Tibetan windows syllables and not graphemes

  A Chinese character is a morpheme, so a 3-character window is a meaningful fragment:
  `波羅蜜` is pāramitā. A Tibetan grapheme is a *letter stack*, so the same rule cuts
  across the tsheg and yields fragments of no linguistic standing. Windowing
  `སྟོང་པ་ཉིད` (śūnyatā) by grapheme produced `["སྟོང་", "ང་པ", "་པ་", "པ་ཉི", "་ཉིད"]`,
  and `་པ་` — the particle པ between two separators — occurs in **89.6% of the corpus's
  1,352,471 Tibetan segments**, against 2.63% for the term itself. Two of five windows
  matched nine lines in ten, and `:ngram` ranks by how many distinct query terms a
  passage contains, so the junk outvoted the signal.

  That is the same failure this module already refuses for Chinese, where jieba shatters
  transliterated Sanskrit and "a single common character appears on nearly every line".
  The fix is the same in spirit: **no dictionary**. The tsheg is an explicit delimiter
  the edition itself prints, so splitting on it cannot mis-segment
  `པྲ་ཛྙཱ་ཝརྨ` (Prajñāvarman) the way a trained segmenter would — which is exactly why
  `botok` is not used here either.

  A Tibetan syllable carries roughly what a Chinese character carries, but Tibetan words
  are commonly one or two syllables, so the window is 2: at 3 a three-syllable term has
  only one window and `:ngram` degenerates into the `:phrase` search it exists to back up.
  """
  @spec ngrams(String.t(), pos_integer()) :: [String.t()]
  def ngrams(query, width \\ 3) do
    if tibetan?(query) do
      syllable_ngrams(query)
    else
      case word_ngrams(query) do
        [] -> grapheme_ngrams(query, width)
        words -> words
      end
    end
  end

  # Below this a word is a function word in any alphabetic script — `to`, `at`, `in`, `by`.
  @min_word_length 3

  # The ceiling on OR'd LIKE predicates. See the note below: past the planner's tipping
  # point pg_bigm is abandoned for a sequential scan of the whole segment table.
  @max_predicates 20

  # THE WORD IS THE UNIT FOR AN ALPHABETIC SCRIPT, AND THE GRAPHEME WINDOW IS A CJK TOOL.
  #
  # This is the third instance of one defect. The module already refuses jieba for Chinese
  # because "a single common character appears on nearly every line", and refuses grapheme
  # windows for Tibetan because `་པ་` matched 89.6% of segments. Latin script has the same
  # pathology and nothing caught it, because `tibetan?/1` was the only script test and
  # everything else fell through to trigrams: a 145-character English sentence became
  # **135** windows of `%the%`, `%er %`, `%ass%` — fragments of no linguistic standing,
  # which can only ever match the Latin-script (Pāli) part of the corpus and so enter the
  # fusion as noise on a Tibetan or Chinese question.
  #
  # It was also what made a lexical query take over two minutes. Past a point the planner
  # abandons the pg_bigm index for a sequential scan of all 6.5M segments, evaluating one
  # substring test per predicate per row. Measured with EXPLAIN on the full corpus:
  #
  #     phrase, 1 pattern of 145 chars    Bitmap Index Scan      cost 4,698
  #     ngram, 135 trigram patterns       Seq Scan on segments   cost 3,043,842
  #
  # `LIMIT depth * 5` and no ORDER BY is what made it *intermittent*: the scan stops when
  # it fills the limit, so the runtime depends on where matches fall in heap order. Depth
  # 60 filled 300 in time and depth 120 sometimes did not fill 600, which is the one-arm-
  # in-two timeout that kept depth 120 from being the default.
  #
  # THE CLIFF IS SELECTIVITY, NOT A PREDICATE COUNT — measured, having first assumed
  # otherwise. On one query the index survived 24 predicates; on another it was abandoned
  # at 10. What differs is the short common words, so the two rules below are one rule:
  #
  # - drop words under 3 characters. This is the exact analogue of the `@particles` list
  #   that already drops 之, 於, 者 from Chinese as "grammatical particles, not content" —
  #   `to`, `at`, `in`, `on`, `by` are the same thing, and length is a dictionary-free way
  #   to say so.
  # - keep the LONGEST 20. Length is a dictionary-free proxy for rarity, and rarity is
  #   what keeps the planner on the index. Longest-first held the index to 24 predicates
  #   on the query where first-20-in-order flipped to a sequential scan at 10.
  #
  # Verified over every alphabetic query in the gold set — 252 of them, 252 BitmapOr
  # plans, **zero sequential scans**.
  #
  # Returns `[]` when the rule does not apply, and the caller falls back to grapheme
  # windows. Two cases: a query containing Han, where the window IS the right unit; and a
  # query with fewer than two qualifying words, where the word search would merely repeat
  # the `:phrase` attempt that already failed. A single alphabetic word keeps trigrams
  # precisely because they are fuzzy there — `sammādiṭṭhi` should still reach
  # `sammādiṭṭhiṃ`, and 9 windows is nowhere near the cliff.
  defp word_ngrams(query) do
    if String.match?(query, ~r/\p{Han}/u) do
      []
    else
      words =
        query
        |> String.split(~r/[^\p{L}\p{N}]+/u, trim: true)
        |> Enum.filter(&(String.length(&1) >= @min_word_length))
        |> Enum.uniq()

      if length(words) < 2 do
        []
      else
        words
        |> Enum.sort_by(&String.length/1, :desc)
        |> Enum.take(@max_predicates)
      end
    end
  end

  defp grapheme_ngrams(query, width) do
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

  # The tsheg (U+0F0B) separates syllables; the shad (།) ends a clause. Both are printed,
  # so neither has to be guessed.
  @tsheg "་"
  @tibetan_syllable_window 2

  # Windows never cross a shad. The window is rejoined with a tsheg to be searched as a
  # substring, so spanning a clause break would fabricate a string the edition does not
  # print — `ཆོས་རྣམས། སྟོང་པ` would yield `རྣམས་སྟོང`, which cannot match anything and
  # still takes a vote in the ranking.
  defp syllable_ngrams(query) do
    query
    |> String.split(["།", "\n"], trim: true)
    |> Enum.flat_map(&clause_ngrams/1)
    |> Enum.uniq()
  end

  defp clause_ngrams(clause) do
    syllables =
      clause
      |> String.split([@tsheg, " "], trim: true)
      |> Enum.reject(&(&1 == "" or punctuation?(&1)))

    cond do
      syllables == [] ->
        []

      length(syllables) <= @tibetan_syllable_window ->
        [Enum.join(syllables, @tsheg)]

      true ->
        syllables
        |> Enum.chunk_every(@tibetan_syllable_window, 1, :discard)
        |> Enum.map(&Enum.join(&1, @tsheg))
    end
  end

  # Tibetan block, U+0F00-U+0FFF. Checked on the query rather than configured per source,
  # because a query is not addressed to one corpus.
  # The `u` modifier is required: without it `\x{}` is byte-limited and the pattern will
  # not even compile for a codepoint this high.
  defp tibetan?(query), do: String.match?(query, ~r/[\x{0F00}-\x{0FFF}]/u)

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
      # Preloaded through a SEPARATE query, not through the join, and without `body`.
      #
      # The join-preload shipped `texts.body` — the entire normalized work — once per
      # matched segment. Bodies average 27,218 characters and the largest is 13,279,028,
      # so a search over-fetching `limit * 5` rows pulled tens of megabytes through
      # shared buffers per query. Nothing reads it: `Corpus.span_from_segment/1` uses
      # `work`, `witness_id`, `source_id`, `source.license_class` and `volume`, and
      # `Corpus.body/1` fetches the body on its own when offsets need verifying.
      #
      # A separate preload also loads each DISTINCT text once rather than once per row,
      # which is the difference between 600 bodies and a few dozen rows of metadata.
      #
      # Measured over the full corpus, five Chinese formulae, warmed and ABBA-verified:
      # 1403 ms -> 44 ms, a 32x speedup. See docs/HISTORY.md.
      |> preload([_s, _t], text: ^Text.preload_without_body())
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
    |> filter_text(opts[:source_id], :source_id)
    |> filter_text(opts[:witness_id], :witness_id)
    |> filter_dates(opts)
    |> filter_license(opts)
  end

  # WHEN, AS A BOUND — and a bound is not a date.
  #
  # `works.date_start`/`date_end` are derived from the attributed person's lifespan, so a
  # work sits in a *range* of possible composition years. `composed_after: 600` therefore
  # keeps everything whose range reaches 600 or later (`date_end >= 600`), and
  # `composed_before: 800` keeps everything whose range starts at or before 800. An open
  # end is unknown-in-that-direction and is kept, because excluding it would assert
  # something the data does not say.
  #
  # `date_basis` is the test for "dated at all", not `date_start`: half a bound is still a
  # date, and 195 works carry only `date_end`.
  #
  # THIS FILTER DISCARDS MOST OF THE CORPUS AND MUST SAY SO. Only works with an authority
  # link that carries a lifespan have any date at all — `Pramana.Coverage.dated/0` is the
  # denominator, and the MCP tool reports it on every dated query. A silent 91% discard is
  # exactly rule 44.
  # Built as a join plus wheres against a NAMED binding rather than one clever `on`. The
  # one-expression version pushed `is_nil(^year)` into SQL to make an absent bound a no-op,
  # and Postgres rejected it outright: `$1 IS NULL` on its own gives the planner nothing to
  # infer a type from. Deciding in Elixir which predicates exist is both correct and the
  # thing that is readable a year from now.
  # A MISSING END IS NOT AN INFINITE ONE. The first version read a null `date_start` as
  # "could be any year", so 性起 — who died in 1798, with no birth recorded — came back
  # under `composed_before: 400`. Formally defensible, useless in practice, and the kind of
  # plausible-looking result this project treats as worse than an error.
  #
  # So the filter falls back to the known end: a person recorded only by death is compared
  # on that death year at both ends. Note that this is the coalesce the *storage* side
  # deliberately refuses — writing `1798 – 1798` into the row would assert a precision
  # nobody has, while using 1798 as the comparison point is a stated filtering rule. Storing
  # a claim and testing one are different acts.
  defp filter_dates(query, opts) do
    case {opts[:composed_after], opts[:composed_before]} do
      {nil, nil} ->
        query

      {after_year, before_year} ->
        query
        |> join(:inner, [s, t], w in Pramana.Corpus.Work,
          on: w.id == t.work_id and not is_nil(w.date_basis),
          as: :dated_work
        )
        |> not_before(after_year)
        |> not_after(before_year)
    end
  end

  # `coalesce` because a person recorded only by death is compared on that death year at
  # both ends — see the note on `filter_dates/2`.
  defp not_before(query, nil), do: query

  defp not_before(query, year) do
    where(
      query,
      [dated_work: w],
      fragment("coalesce(?, ?)", w.date_end, w.date_start) >= ^year
    )
  end

  defp not_after(query, nil), do: query

  defp not_after(query, year) do
    where(
      query,
      [dated_work: w],
      fragment("coalesce(?, ?)", w.date_start, w.date_end) <= ^year
    )
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

  @doc """
  The options this retriever accepts.

  Public so a dispatcher can drop what does not apply before calling — `Pramana.Retrieval`
  routes `:phrase` here from the same option list it would hand `Hybrid`, and `:coverage`
  is meaningless to a lexical search. Filtering is only safe against the real list;
  hard-coding "the hybrid-only ones" somewhere else is a list that goes stale silently.
  """
  @spec known_opts() :: [atom()]
  def known_opts, do: @known_opts

  @doc false
  def validate_opts!(opts) do
    case Keyword.keys(opts) -- @known_opts do
      [] -> :ok
      unknown -> raise ArgumentError, "unknown search option(s): #{inspect(unknown)}"
    end

    validate_limit!(opts[:limit])
  end

  @doc "The largest number of results this retriever will return."
  @spec max_limit() :: pos_integer()
  def max_limit, do: @max_limit

  # Silently clamping a limit is the same bug as silently ignoring a filter — the caller
  # is given something other than what they asked for, with nothing saying so. See the
  # note in `Pramana.Retrieval.Semantic`, where it cost a published figure.
  defp validate_limit!(nil), do: :ok

  defp validate_limit!(limit) when is_integer(limit) and limit > @max_limit do
    raise ArgumentError,
          "limit #{limit} exceeds the maximum of #{@max_limit}; ask for at most " <>
            "#{@max_limit}, and clamp at your own boundary if the value came from a user"
  end

  defp validate_limit!(_limit), do: :ok

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

  # WHICH PUBLICATION, and WHICH COLLECTION INSIDE IT. `source_id` separates CBETA from
  # SuttaCentral from the Degé; `witness_id` separates the Taishō from the 卍續藏 from the
  # 嘉興藏 inside CBETA, which became a real question the day the corpus held three of
  # them.
  #
  # `Semantic` has had `source_id` since it was written and this retriever never did — so
  # `Hybrid.search(q, source_id: "cbeta")` did not silently half-filter, it RAISED, which
  # is the correct failure and still meant no caller could restrict a search to one
  # collection at all. That asymmetry is exactly the shape of the `division:` bug this
  # module's option validation exists to prevent; it was simply latent on the other side.
  defp filter_text(query, nil, _field), do: query

  defp filter_text(query, value, field) do
    values = List.wrap(value)
    where(query, [_s, t], field(t, ^field) in ^values)
  end

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
