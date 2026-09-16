defmodule Pramana.Repo.Migrations.AddChunkHnswIndex do
  use Ecto.Migration

  @moduledoc """
  HNSW index for approximate nearest-neighbour search over chunk embeddings.

  `vector_ip_ops` (inner product) rather than cosine, because `Pramana.Embed`
  L2-normalises every vector — on unit vectors cosine similarity and inner product are
  the same ordering, and inner product is cheaper. If normalisation is ever dropped,
  this operator class becomes wrong, so the two decisions have to move together.

  Concurrent build: at full corpus size this index covers 299,317 vectors and takes
  long enough that locking the table would stall the bake.
  """

  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    execute """
    CREATE INDEX CONCURRENTLY IF NOT EXISTS chunks_embedding_hnsw_index
    ON chunks USING hnsw (embedding vector_ip_ops)
    """
  end

  def down do
    execute "DROP INDEX CONCURRENTLY IF EXISTS chunks_embedding_hnsw_index"
  end
end
