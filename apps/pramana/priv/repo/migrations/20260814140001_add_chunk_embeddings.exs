defmodule Pramana.Repo.Migrations.AddChunkEmbeddings do
  use Ecto.Migration

  @moduledoc """
  Dense embeddings on chunks, plus the HNSW index.

  1024 dimensions because BGE-M3's XLM-RoBERTa-large backbone has hidden size 1024.
  Changing model means changing this column, which is precisely why the model identity
  belongs in `bake_id` — see `embedding_model`.

  The index is created WITHOUT a vector column populated; building HNSW over an empty
  or partial table is cheap, and pgvector maintains it incrementally. For a full
  re-embed it is faster to drop and rebuild, which `mix pramana.embed --reindex` does.

  `embedding_model` records which model produced the vector. Two chunks embedded by
  different models are not comparable, and silently mixing them would corrupt search in
  a way no test would catch — the vectors are all valid floats.
  """

  def change do
    alter table(:chunks) do
      add :embedding, :vector, size: 1024
      add :embedding_model, :string
      add :embedded_at, :utc_datetime_usec
    end

    # Partial index: only chunks that HAVE an embedding, so the resumable embed task
    # can find outstanding work in one indexed scan rather than a sequential one.
    create index(:chunks, [:embedding_model],
             where: "embedding IS NULL",
             name: :chunks_pending_embedding_index
           )
  end
end
