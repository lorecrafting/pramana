defmodule Pramana.Retrieval.RenderingScope do
  @moduledoc """
  Which English renderings an experimental arm is allowed to see — for **every** retrieval
  stage, not just the one that generates candidates.

  ## Why this exists

  `--translators` and `--translation_coverage` were honoured by
  `Pramana.Retrieval.Semantic` and ignored by `Pramana.Retrieval.Rerank`, which could not
  honour them even in principle: `Hybrid.maybe_rerank/3` called `by_rendering(query,
  results)` and passed no options at all. So an arm's **candidates** were isolated and its
  **ordering** was computed against the whole English layer, including the renderings that
  defined the arm by their absence. Every figure in the 205-case model ladder was produced
  that way.

  A scope that only one stage obeys is not a scope. This module is the one definition, and
  both stages read it.

  ## The two rules

  **Translators.** A vector or rendering is in scope when it is not a translation at all,
  or when its `translator_id` is one of the named arms. Source text is never excluded —
  restricting the English layer must not silently restrict the Chinese.

  **Coverage.** An ablation keeps a deterministic pseudo-random fraction, and the two
  stages MUST hide the same chunks or the ablation is incoherent — candidates drawn from
  one 25% and reranked against a different 25% is not 25% coverage of anything. So both
  hash the **chunk id**: `Semantic` over `chunk_vectors.chunk_id`, `Rerank` over
  `chunks.id`, which are the same number. `hashtext` is Postgres's own, so the partition is
  stable across processes and runs without storing anything.

  ## What it deliberately does not do

  It does not decide whether a rendering may be **shown**. That is a separate question —
  `tier: t1` renderings are findable by design and are not reviewed prose — and conflating
  search eligibility with display eligibility is how generated text ends up read as though
  it were edited. See `docs/PLAN.md`.
  """

  @doc """
  The translator ids an arm may see, or `nil` for "no restriction".

  `nil` and `[]` mean different things and the difference is load-bearing: `nil` is *every
  translator*, and `[]` is *no English at all*, which is the no-English control arm.
  """
  @spec translators(keyword()) :: [String.t()] | nil
  def translators(opts) do
    case Keyword.get(opts, :translators) do
      nil -> nil
      ids -> List.wrap(ids)
    end
  end

  @doc """
  The percentage of translation-bearing chunks an ablation keeps, or `nil` for all of them.

  Returned as an integer 0..100 because both stages compare it against
  `abs(hashtext(chunk_id)) % 100`, and doing that arithmetic in one place is the point.
  """
  @spec coverage_keep(keyword()) :: 0..100 | nil
  def coverage_keep(opts) do
    case Keyword.get(opts, :translation_coverage) do
      nil -> nil
      c when is_number(c) and c >= 1.0 -> nil
      c when is_number(c) and c >= 0.0 -> round(c * 100)
    end
  end

  @doc """
  SQL conditions restricting a `translations` row, for the stage that is not written in
  Ecto.

  Returns `{fragments, params}` where each fragment is already parameterised against the
  numbering the caller starts from — `next_param` is the first free `$n`. `Rerank` reads
  renderings with a hand-written join whose ordinal-range predicate Ecto cannot express
  comfortably, so it gets conditions rather than a query.
  """
  @spec sql_conditions(String.t(), String.t(), keyword(), pos_integer()) ::
          {[String.t()], [term()]}
  def sql_conditions(translation_alias, chunk_alias, opts, next_param) do
    {conditions, params, _n} =
      [
        {translators(opts), &"AND #{translation_alias}.translator_id = ANY($#{&1})"},
        {coverage_keep(opts), &"AND abs(hashtext(#{chunk_alias}.id::text)) % 100 < $#{&1}"}
      ]
      |> Enum.reduce({[], [], next_param}, fn
        {nil, _sql}, acc -> acc
        {value, sql}, {conds, params, n} -> {conds ++ [sql.(n)], params ++ [value], n + 1}
      end)

    {conditions, params}
  end
end
