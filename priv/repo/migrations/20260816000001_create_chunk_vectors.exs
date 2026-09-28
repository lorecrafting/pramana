defmodule Pramana.Repo.Migrations.CreateChunkVectors do
  @moduledoc """
  Moves embeddings out of `chunks` and into `chunk_vectors`, so a chunk can carry more
  than one.

  ## Why more than one

  Cross-lingual retrieval **into** Classical Chinese is the weakest axis of this system,
  and `Pramana.Retrieval.Semantic`'s "Honest limits" says so: an English question reaches
  the Chinese canon only through BGE-M3's multilingual space, which is unproven on this
  material. A second vector per chunk — the same passage embedded in English — is the
  main available mitigation, and `docs/LAYERS.md` notes it falls out of the translation
  work rather than being a separate project.

  ## Why one table rather than extra columns

  A column per vector kind means every filter, every coverage count and every ANN query
  has to be repeated per column, and the repetition is where they drift apart. This
  codebase has already been bitten twice by a filter that applied to one retrieval path
  and not another (`division`, then `license_class`), each time producing results that
  looked filtered and were not. One row per vector, one index, one query path.

  The vector row carries **its own text and hash** rather than pointing at the chunk's.
  A translation vector's text is not in `chunks` at all, and making every row
  self-describing is what lets the export/import round trip re-check that the vector
  still matches the words it was computed from.

  ## Vector kinds

  - `source` — the passage as the edition prints it. Moved here from `chunks.embedding`.
  - `translation` — a rendering of the same span, one per translator.
  - `question` — hypothetical questions the passage answers. **Not populated.** It needs
    an LLM generation pass over 300k+ chunks, which is the Phase 7 engine's job, and
    spending it before the Phase 4 eval harness exists would be spending blind. The kind
    is enumerated now so adding it later is data, not a migration.
  """

  use Ecto.Migration

  # The move copies 299,317 vectors and rebuilds an HNSW index over them; neither fits a
  # migration lock timeout comfortably on a laptop.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def up do
    create table(:chunk_vectors) do
      add :chunk_id, references(:chunks, on_delete: :delete_all), null: false
      add :kind, :string, null: false
      # The language of the EMBEDDED TEXT, which for a translation vector is not the
      # language of the passage. Conflating the two would make an English vector look
      # like a Pāli one.
      add :lang, :string, null: false
      add :translator_id, :string

      add :content, :text, null: false
      add :content_sha256, :string, null: false

      add :embedding, :vector, size: 1024
      add :embedding_model, :string
      add :embedded_at, :utc_datetime_usec

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:chunk_vectors, :chunk_vector_kind_known,
             check: "kind IN ('source','translation','question')"
           )

    # A translation vector must name its translator; a source vector must not pretend to
    # have one. Without this the unique index below silently permits two unattributed
    # translation rows for the same chunk.
    create constraint(:chunk_vectors, :translation_vector_names_its_translator,
             check: "(kind = 'translation') = (translator_id IS NOT NULL)"
           )

    # NULLs compare as distinct in Postgres, so a plain unique index over a nullable
    # translator_id would not actually constrain source rows.
    execute """
    CREATE UNIQUE INDEX chunk_vectors_unique_index
    ON chunk_vectors (chunk_id, kind, lang, COALESCE(translator_id, ''))
    """

    create index(:chunk_vectors, [:chunk_id])
    create index(:chunk_vectors, [:kind, :lang])
    create index(:chunk_vectors, [:embedding_model], where: "embedding IS NULL")

    # Move the existing source vectors. `lang` comes from the source, because that is
    # what determines the script: CBETA and locally-added Chinese commentary are Literary
    # Chinese (lzh), SuttaCentral's root text is Pāli (pli).
    execute """
    INSERT INTO chunk_vectors
      (chunk_id, kind, lang, content, content_sha256, embedding, embedding_model,
       embedded_at, inserted_at, updated_at)
    SELECT c.id,
           'source',
           CASE WHEN t.source_id = 'sc' THEN 'pli' ELSE 'lzh' END,
           c.content,
           c.content_sha256,
           c.embedding,
           c.embedding_model,
           c.embedded_at,
           now(),
           now()
    FROM chunks c
    JOIN texts t ON t.id = c.text_id
    """

    # The HNSW index is NOT built here. Building it is an operational step, not a schema
    # one: `docs/GPU_RUNBOOK.md` already establishes drop-and-rebuild around a vector
    # import, because incremental HNSW maintenance made storing 299,317 vectors slower
    # than computing them (#37). Building it inside this migration would mean building it
    # once now and again after the next import, for no benefit.
    #
    # `mix pramana.embed.index` builds it, with the memory it actually needs — at the
    # 64 MB default the build falls back to disk and DEGRADES as the graph grows, reaching
    # 187k of 299,317 tuples in 17 minutes and still slowing.

    alter table(:chunks) do
      remove :embedding
      remove :embedding_model
      remove :embedded_at
    end
  end

  def down do
    alter table(:chunks) do
      add :embedding, :vector, size: 1024
      add :embedding_model, :string
      add :embedded_at, :utc_datetime_usec
    end

    # Only source vectors have a home to go back to. Translation vectors are dropped with
    # the table, which is the honest outcome: the old schema cannot express them.
    execute """
    UPDATE chunks c
    SET embedding = v.embedding,
        embedding_model = v.embedding_model,
        embedded_at = v.embedded_at
    FROM chunk_vectors v
    WHERE v.chunk_id = c.id AND v.kind = 'source'
    """

    execute """
    CREATE INDEX chunks_embedding_hnsw_index
    ON chunks USING hnsw (embedding vector_ip_ops)
    """

    execute "CREATE INDEX chunks_pending_embedding_index ON chunks (embedding_model) WHERE embedding IS NULL"

    drop table(:chunk_vectors)
  end
end
