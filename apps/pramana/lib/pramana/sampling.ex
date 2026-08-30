defmodule Pramana.Sampling do
  @moduledoc """
  Drawing a reproducible random sample from Postgres.

  One function, and it exists because the obvious way to write it is wrong.

  `setseed` sets the random sequence for one Postgres **session**. `Repo.query!` takes
  whichever connection the pool offers, so seeding in one call and sampling in the next puts
  the two in different sessions and the seed does nothing — silently, and only sometimes,
  because a quiet pool often hands back the same connection twice.

  `Pramana.Recall` had that bug for the whole life of its `--seed` option. Measured on
  2026-08-29: **eight calls with the same seed drew eight different samples; the same eight
  inside a transaction drew one.** Every figure published under a seed was an unseeded draw.
  See `docs/RULES.md` 67.

  A transaction pins the checkout, which is the entire fix. This module exists so the next
  measurement task does not have to rediscover that — rule 41 is about the fix that was made
  in one place and not the other.

  ## It cannot be tested from the test suite

  `Pramana.DataCase` uses Ecto's SQL sandbox, which checks out one connection and pins it, so
  `setseed` and its query always share a session there no matter how this is written.
  Deleting the transaction leaves every test green. The instrument that sees this class of
  defect is a script against a real pool, or a check in `mix pramana.gate`.
  """

  alias Pramana.Repo

  @doc """
  Runs `fun` with the connection's random sequence seeded, both on one connection.

  A `nil` seed runs `fun` as-is: an unseeded sample is a legitimate request, and wrapping it
  in a transaction it does not need would be noise.
  """
  @spec seeded(float() | nil, (-> result)) :: result when result: term()
  def seeded(nil, fun), do: fun.()

  def seeded(seed, fun) when is_float(seed) do
    {:ok, result} =
      Repo.transaction(fn ->
        Repo.query!("SELECT setseed($1)", [seed])
        fun.()
      end)

    result
  end
end
