defmodule Pramana.Repo.Migrations.AddCharCountToTexts do
  @moduledoc """
  Stores what `sum(length(body))` was costing ten seconds to recompute.

  `Pramana.Inventory.snapshot/0` reports a character total, and computing it makes Postgres
  **detoast every text in the corpus** — 548 million characters across 17,281 rows. Measured
  2026-08-29: 9.8 s for the snapshot against ~300 ms for every coverage figure it reports
  combined.

  The reader's `/inventory` page pays that on **every load**, and the whole purpose of that
  page is to state gaps quickly enough that somebody reads them before searching.

  ## Why a column rather than a cache

  A cache needs invalidation and would be one more thing that can disagree with the corpus.
  This is a property of the row, written where the row is written, in the same transaction —
  it cannot drift, because there is no moment at which the body exists and the count does
  not.

  Nullable, because a bake predating this migration has bodies and no counts, and a NOT NULL
  would have made the migration itself a rewrite of every row. `Pramana.Bake.stats/0` keeps
  the exact `sum(length(body))` as its definition of truth; this is the fast path, and
  `mix pramana.texts.count_chars` backfills.
  """

  use Ecto.Migration

  def change do
    alter table(:texts) do
      add :char_count, :integer
    end
  end
end
