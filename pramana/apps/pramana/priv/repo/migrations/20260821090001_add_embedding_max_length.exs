defmodule Pramana.Repo.Migrations.AddEmbeddingMaxLength do
  @moduledoc """
  Records the token window a vector was produced with.

  `embedding_model` exists because mixing vectors from two models in one index silently
  corrupts search — every value is a valid float, so nothing fails loudly. The same is
  true of the WINDOW: a chunk longer than `max_length` is embedded as a *prefix*, and the
  same chunk at a larger window is embedded whole. Those describe different amounts of
  text, and until now the schema could not tell them apart.

  Measured 2026-08-20: 6.3% of Pāli chunks exceed the 320-token window (p95 325, max 455)
  while Chinese and Tibetan are at 0.0%/0.1%. Re-embedding `sc` alone at 512 therefore
  put two configurations in one index with no record of which was which.
  """
  use Ecto.Migration

  # Every vector in the corpus at the time of this migration was produced at 320 — the
  # value pinned in `priv/embed/modal_embed.py` and `Pramana.Embed`. Backfilled rather
  # than left null so "unknown window" means genuinely unknown, not merely old.
  @window_at_migration 320

  def up do
    alter table(:chunk_vectors) do
      add :embedding_max_length, :integer
    end

    execute """
    UPDATE chunk_vectors
       SET embedding_max_length = #{@window_at_migration}
     WHERE embedding IS NOT NULL
    """
  end

  def down do
    alter table(:chunk_vectors) do
      remove :embedding_max_length
    end
  end
end
