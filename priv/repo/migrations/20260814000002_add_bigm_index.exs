defmodule Pramana.Repo.Migrations.AddBigmIndex do
  use Ecto.Migration

  @moduledoc """
  Bigram index for Chinese substring search.

  ## Why pg_bigm and not pg_trgm or tsvector

  Classical Chinese has no whitespace, so nothing based on word boundaries works out
  of the box:

  - **`to_tsvector`** needs a tokenizer. Postgres has none for Chinese.
  - **`pg_trgm`** indexes *tri*-grams. Most Chinese words are two characters, so a
    two-character query cannot use a trigram index at all — the single most common
    query shape is exactly the one it fails on.
  - **jieba tokens in a tsvector** would give word-level precision, but Buddhist texts
    are dense with transliterated Sanskrit (阿闍梨, 耆闍崛山, 阿㝹樓馱) that a
    general-purpose Chinese dictionary segments wrongly. Segmentation errors become
    silent recall failures, and they cluster in exactly the vocabulary users search
    for.

  `pg_bigm` indexes *bi*-grams and accelerates `LIKE '%…%'`, which is
  vocabulary-independent: it works on terms no dictionary has ever seen. That property
  matters more here than word-boundary precision, so bigrams are the primary index and
  jieba is used at query time to split multi-term queries.

  pg_bigm is not in Homebrew and must be built from source; see `docs/DEV_ENV.md`.
  """

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS pg_bigm"

    # gin_bigm_ops accelerates LIKE '%...%' on segment text.
    execute """
    CREATE INDEX segments_content_bigm_index
    ON segments USING gin (content gin_bigm_ops)
    """
  end

  def down do
    execute "DROP INDEX IF EXISTS segments_content_bigm_index"
    execute "DROP EXTENSION IF EXISTS pg_bigm"
  end
end
