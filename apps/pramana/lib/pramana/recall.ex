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

  alias Pramana.Repo
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
