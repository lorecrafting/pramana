defmodule Pramana.Recall do
  @moduledoc """
  Measures retrieval against ground truth the corpus already contains.

  `evals/` is 1,472 hand-curated questions and a ratchet. It is the right instrument and it
  is expensive to grow, so it grows slowly. Meanwhile **the corpus is full of free relevance
  judgements**: 141,073 verbatim quotations, each one a statement that this exact passage
  occurs in two named works. If retrieval is asked for that passage and returns only one of
  them, that is a recall failure — and nobody had to label anything.

  This needs no users, no query log and no privacy posture, which is why `docs/PLAN.md` § A6
  argues for building it before instrumenting anyone.

  ## Work-level, and deliberately so

  A quotation records a **range** — `@p0488b10-p0488b12` — while retrieval returns individual
  lines, so URN equality is the wrong comparison and would report a failure for every case.
  The claim tested is therefore *does a search for this passage surface both works that
  contain it*, which is weaker than line-level recall and is exactly the failure worth
  catching: one side never appearing at all.

  ## Truncation is `:undecided`, not a miss

  A phrase occurring in three hundred places cannot have both its ends inside twenty results,
  and counting that as a miss would measure the limit rather than the retriever. When a
  result set fills the cap, absence stops being evidence and the case is reported separately
  — the same discipline as `Pramana.Coherence`'s minimum population, and the reason a number
  here is worth reading.
  """

  import Ecto.Query

  alias Pramana.Corpus
  alias Pramana.Repo
  alias Pramana.Retrieval
  alias Pramana.Retrieval.Lexical

  @default_sample 200
  @default_limit 100

  @type outcome :: :both | :one | :neither | :undecided

  @doc """
  Samples the quotation graph and reports what retrieval does with it.

  ## Options

    * `:sample` — how many pairs to draw (default #{@default_sample})
    * `:limit` — result cap per search (default #{@default_limit}); a result set that fills
      it makes the case `:undecided`
    * `:seed` — makes the sample reproducible, which a measurement has to be
  """
  @spec run(keyword()) :: map()
  def run(opts \\ []) do
    sample = Keyword.get(opts, :sample, @default_sample)
    limit = Keyword.get(opts, :limit, @default_limit)

    pairs = sample_pairs(sample, Keyword.get(opts, :seed))
    results = Enum.map(pairs, &probe(&1, limit))
    counts = Enum.frequencies_by(results, & &1.outcome)

    decided = Enum.count(results, &(&1.outcome != :undecided))
    both = Map.get(counts, :both, 0)

    %{
      sampled: length(pairs),
      decided: decided,
      undecided: Map.get(counts, :undecided, 0),
      both: both,
      one: Map.get(counts, :one, 0),
      neither: Map.get(counts, :neither, 0),
      recall: if(decided > 0, do: both / decided),
      misses: results |> Enum.filter(&(&1.outcome in [:one, :neither])) |> Enum.take(10),
      limit: limit
    }
  end

  @doc """
  The same trick, pointed at the axis that has never moved.

  `run/1` measures lexical retrieval against verbatim quotations and reports 100%. That is
  worth knowing and it is the **strong** axis. `topical/chinese` has been **0% of 12** since
  it was first measured, and `docs/PLAN.md` § F says the quiet part: *that row is 12 cases,
  cannot grow, and one case is 8.3 points.* You cannot steer on twelve cases.

  SuttaCentral's curated parallels are **scholars' cross-lingual relevance judgements** —
  10,493 Pāli↔Chinese pairs with both ends resolvable in this bake. Query with one side and
  ask whether the other comes back.

  ## The control group is the point

  Same-language pairs are measured alongside, and they are a **positive control**: if the
  Pāli→Pāli case also fails, the probe is broken and the cross-lingual figure means nothing.
  This module reported 0.0% twice while working perfectly on data it could not match, so a
  measurement here without a control is a number to distrust on principle.

  A `control` that collapses makes the whole run `:void` rather than zero — the distinction
  between *retrieval cannot do this* and *we cannot measure it*.
  """
  @spec parallels(keyword()) :: map()
  def parallels(opts \\ []) do
    sample = Keyword.get(opts, :sample, @default_sample)
    limit = Keyword.get(opts, :limit, @default_limit)
    mode = Keyword.get(opts, :mode, :hybrid)

    cross = sample_parallels(sample, :cross, Keyword.get(opts, :seed))
    control = sample_parallels(max(div(sample, 4), 10), :same, Keyword.get(opts, :seed))

    cross_results = Enum.map(cross, &probe_parallel(&1, limit, mode, opts))
    control_results = Enum.map(control, &probe_parallel(&1, limit, mode, opts))

    control_score = score(control_results)
    cross_score = score(cross_results)

    %{
      mode: mode,
      limit: limit,
      control: control_score,
      cross_lingual: cross_score,
      # VOID, NOT ZERO. If the same-language control cannot find its own pair, nothing about
      # the cross-lingual number is interpretable — and reporting 0% would blame the axis for
      # a broken probe, which this module has already done twice.
      verdict: verdict(control_score, cross_score),
      # THE NUMBER TO READ. Cross-lingual recall means little alone — the corpus, the cap and
      # the difficulty of paraphrase retrieval all move it. Against the same passage-matching
      # task in ONE language it becomes a statement about the language barrier specifically.
      relative:
        case {control_score.rate, cross_score.rate} do
          {nil, _} -> nil
          {control, cross} when control > 0 -> cross / control
          _ -> nil
        end,
      misses: cross_results |> Enum.filter(&(&1.outcome == :miss)) |> Enum.take(8)
    }
  end

  # THE CONTROL DETECTS A BROKEN PROBE. It is not a pass mark, and the first version made it
  # one — a floor of 0.5 picked from nothing, which is the mistake `docs/PROXIES.md` exists
  # to record: **a threshold has to come from a measured distribution.**
  #
  # Measured, same-language parallel recall is around 30%, and that is very likely the real
  # number rather than a fault. A parallel is a PARAPHRASE — SuttaCentral records that two
  # discourses correspond, not that they share words — so finding one inside the top hundred
  # of 12.5 million segments is genuinely hard. Calling 30% a failure would have thrown away
  # a working measurement.
  #
  # So `:void` means the probe found NOTHING, which no working retriever does. Anything above
  # that is measured, and the figure to read is cross-lingual **relative to** same-language:
  # the control is the reference point, not the bar.
  defp verdict(%{decided: 0}, _cross), do: :void
  defp verdict(%{found: 0}, _cross), do: :void
  defp verdict(_control, _cross), do: :measured

  defp score(results) do
    decided = Enum.reject(results, &(&1.outcome == :undecided))
    found = Enum.count(decided, &(&1.outcome == :found))

    %{
      sampled: length(results),
      decided: length(decided),
      found: found,
      rate: if(decided != [], do: found / length(decided))
    }
  end

  # `:cross` is a pair whose two ends come from different SOURCES — SuttaCentral and CBETA,
  # which here means Pāli and Classical Chinese. `:same` is the control.
  defp sample_parallels(n, kind, seed) do
    if seed, do: Repo.query!("SELECT setseed($1)", [seed])

    comparison = if kind == :cross, do: "<>", else: "="

    %{rows: rows} =
      Repo.query!(
        """
        SELECT p.source_urn, p.target_urn, p.target_work_id, st.source_id, tt.source_id
        FROM text_parallels p
          JOIN texts st ON st.work_id = p.source_work_id
          JOIN texts tt ON tt.work_id = p.target_work_id
        WHERE p.source_urn IS NOT NULL AND p.target_urn IS NOT NULL
          AND st.source_id #{comparison} tt.source_id
        ORDER BY random() LIMIT $1
        """,
        [n]
      )

    Enum.map(rows, fn [source_urn, target_urn, target_work, src, tgt] ->
      %{
        source_urn: source_urn,
        target_urn: target_urn,
        target_work: target_work,
        from: src,
        to: tgt
      }
    end)
  end

  # Query with the SOURCE passage's own words and ask whether the target work comes back.
  # A passage that will not resolve is `:undecided`: the parallel names a witness this bake
  # holds a work id for and not the line, which is a coverage fact rather than a retrieval one.
  defp probe_parallel(pair, limit, mode, opts) do
    with {:ok, span} <- Corpus.resolve(pair.source_urn),
         text when is_binary(text) and byte_size(text) > 0 <- span.content,
         {:ok, %{results: results}} <-
           Retrieval.search(text, Keyword.merge([mode: mode, limit: limit], search_opts(opts))) do
      works = results |> Enum.map(& &1.span.provenance.work_id) |> MapSet.new()

      Map.put(
        pair,
        :outcome,
        if(MapSet.member?(works, pair.target_work), do: :found, else: :miss)
      )
    else
      _ -> Map.put(pair, :outcome, :undecided)
    end
  end

  defp search_opts(opts), do: Keyword.take(opts, [:serving])

  # A REPRODUCIBLE SAMPLE. `order by random()` gives a different answer every run, so a
  # figure could never be compared with the one before it — the failure `docs/PROXIES.md`
  # exists to record. The seed goes to Postgres, so the same seed draws the same pairs.
  defp sample_pairs(n, seed) do
    if seed, do: Repo.query!("SELECT setseed($1)", [seed])

    Repo.all(
      from q in "quotations",
        select: %{
          text: q.text,
          a_work: q.a_work_id,
          b_work: q.b_work_id,
          length: q.length
        },
        order_by: fragment("random()"),
        limit: ^n
    )
  end

  # THE LONGEST SINGLE LINE, WITH ITS PUNCTUATION. Two mistakes were made getting here and
  # both reported 0.0% recall, which is exactly what a broken probe looks like from outside.
  #
  # A quotation spans lines — the `\n` in its text are real segment boundaries — and a
  # segment is the unit the index matches within, so the concatenated passage can never be
  # found inside one. That is the same fact `Guard`'s `:spans_line_boundary` exists for.
  #
  # And punctuation must NOT be stripped here, which is the reverse of everywhere else. The
  # stored segments carry CBETA's editorial punctuation; a stripped query matches none of
  # them. Stripping is right when comparing two passages to each other and wrong when
  # querying the index, because the index holds what the editor printed.
  defp probe(pair, limit) do
    phrase = pair.text |> String.split("\n", trim: true) |> Enum.max_by(&String.length/1)

    case Lexical.search(phrase, mode: :phrase, limit: limit) do
      {:ok, %{results: results}} ->
        works = results |> Enum.map(& &1.span.provenance.work_id) |> MapSet.new()

        Map.merge(pair, %{
          outcome: outcome(works, pair, length(results), limit),
          found: MapSet.size(works)
        })

      {:error, reason} ->
        Map.merge(pair, %{outcome: :neither, found: 0, error: reason})
    end
  end

  # A FULL RESULT SET IS NOT EVIDENCE OF ABSENCE. Where the cap was reached, the two works
  # may well both be present further down; reporting that as a miss measures `limit`.
  defp outcome(works, pair, returned, limit) when returned >= limit do
    if MapSet.member?(works, pair.a_work) and MapSet.member?(works, pair.b_work),
      do: :both,
      else: :undecided
  end

  defp outcome(works, pair, _returned, _limit) do
    case {MapSet.member?(works, pair.a_work), MapSet.member?(works, pair.b_work)} do
      {true, true} -> :both
      {false, false} -> :neither
      _ -> :one
    end
  end
end
