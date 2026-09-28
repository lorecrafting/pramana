defmodule Pramana.Sampling do
  @moduledoc """
  Drawing a reproducible random sample from Postgres.

  Two mechanisms were tried here, and the second one is the one to use.

  ## `setseed` — correct, and only for a fixed database configuration

  `setseed` seeds the random sequence for one Postgres **session**, and `Repo.query!` takes
  whichever connection the pool offers, so seeding in one call and sampling in the next puts
  the two in different sessions and the seed does nothing. `Pramana.Recall` had that bug for
  the whole life of its `--seed` option: **eight calls with the same seed drew eight different
  samples; the same eight inside a transaction drew one.** Rule 67.

  Wrapping both in a transaction fixes it and was shipped on 2026-08-29. But it leaves a
  subtler dependence: `random()` is **volatile and evaluated per row**, so which value a row
  draws depends on the order rows reach it. Change the plan — more parallel workers, a
  different `work_mem`, a new index — and the same seed can draw a different sample. The
  seed is then reproducible only for a fixed server configuration, which is a weaker promise
  than a project built on `bake_id` should be making.

  ## Ordering by a hash of the row — reproducible, full stop

  `md5(salt || key)` is a deterministic function **of the row itself**. It cannot depend on
  scan order, parallelism, or the plan, because nothing about the row changes when those do.
  It needs no transaction and no session state.

  **The key must be unique per row, and this is the trap.** A hash order is only as
  reproducible as its key: the first attempt keyed `text_parallels` on `source_urn ||
  target_urn`, which has 24,099 distinct values over 407,176 rows, so 94% of the table tied
  and the tie-break went straight back to the planner. Use the primary key unless something
  else is provably unique.

  **Measured on 2026-08-29**, the same 500-row sample drawn under five planner
  configurations:

      setting                              setseed + random()   md5(salt || id)
      max_parallel_workers_per_gather=0    e0cf2397             a79d3a1a
      max_parallel_workers_per_gather=4    e0cf2397             a79d3a1a
      enable_hashjoin=off                  e0cf2397             a79d3a1a
      enable_indexscan=off                 3ba7b010  <- differs a79d3a1a

  The fragility is **real, not theoretical** — it simply needs a large enough plan change to
  surface. Applying and reverting a `shared_buffers`/`work_mem` tuning that same day did *not*
  move the sample, which was briefly taken as evidence that the problem was imaginary; forcing
  a sequential scan moves it immediately.

  The cost is one md5 per candidate row and a sort, which is what `ORDER BY random()` already
  paid.

  **Passing `nil` means genuinely unseeded**, and that stays `random()`: an unseeded sample is
  a legitimate request, and a figure quoted from one is an anecdote either way.
  """

  @doc """
  The SQL ordering expression for a seeded sample, for raw queries.

  `key` is a **code-controlled** column expression, never user input; `seed` is a float
  parsed by `OptionParser`. Both are interpolated, and neither can carry a quote.
  """
  @spec order_sql(float() | nil, String.t()) :: String.t()
  def order_sql(nil, _key), do: "random()"

  def order_sql(seed, key) when is_float(seed),
    do: "md5('#{Float.to_string(seed)}' || #{key})"

  @doc """
  The salt as Postgres sees it, for building the same expression in an Ecto fragment.

  Kept here rather than inlined at each call site so the two spellings of one idea cannot
  drift — a seeded Ecto sample and a seeded raw-SQL sample must agree on what the salt is.
  """
  @spec salt(float()) :: String.t()
  def salt(seed) when is_float(seed), do: Float.to_string(seed)
end
