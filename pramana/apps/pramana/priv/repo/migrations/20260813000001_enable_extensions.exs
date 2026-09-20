defmodule Pramana.Repo.Migrations.EnableExtensions do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS vector"
    execute "CREATE EXTENSION IF NOT EXISTS pg_trgm"
    # NOTE: pg_bigm (bigram index for Chinese, which has no whitespace) is NOT in
    # Homebrew and must be compiled from source. It is not needed until Phase 1
    # lexical search. See docs/DEV_ENV.md.
  end

  def down do
    execute "DROP EXTENSION IF EXISTS pg_trgm"
    execute "DROP EXTENSION IF EXISTS vector"
  end
end
