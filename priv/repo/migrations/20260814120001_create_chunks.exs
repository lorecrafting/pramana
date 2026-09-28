defmodule Pramana.Repo.Migrations.CreateChunks do
  use Ecto.Migration

  @moduledoc """
  Retrieval chunks: windows over segments, and the unit that gets embedded.

  ## Why not embed segments directly

  A Taishō segment is one printed line, averaging **18.2 characters**, and the line
  break is typographic rather than syntactic. In T0262 the name 阿若憍陳如
  (Ājñātakauṇḍinya) is split across two lines as `…阿若憍` / `陳如…`. Embedding that
  produces a vector for half a name.

  Chunks are ~300-character windows, which is both semantically coherent and 16× fewer
  rows: ~286k chunks instead of 4.7M segments. That difference decides whether
  embedding the corpus is an afternoon or a week.

  ## Two-level retrieval

  `docs/ARCHITECTURE.md` Stage 2: embed the window for recall, return the containing
  structural unit for readability. A chunk's URN is a **range** of real citation
  points (`…@p0001c18-p0001c21`), so a semantic hit is still edition-anchored and still
  verifiable by the guard — chunking never invents an identifier.

  No overlap between chunks. Overlap guards against a phrase straddling a boundary, but
  exact-phrase recall is already handled by the bigram index over segments; chunks
  exist for semantic similarity, where a boundary costs a little context rather than a
  missed match.
  """

  def change do
    create table(:chunks) do
      add :text_id, references(:texts, on_delete: :delete_all), null: false

      # A range URN spanning the chunk's first and last segment.
      add :urn, :string, null: false
      add :first_ordinal, :integer, null: false
      add :last_ordinal, :integer, null: false
      add :segment_count, :integer, null: false
      add :juan, :integer

      add :content, :text, null: false
      add :content_sha256, :string, null: false

      # Offsets into texts.body, as for segments: char for clients, byte for the server.
      add :char_start, :integer, null: false
      add :char_end, :integer, null: false
      add :byte_start, :integer, null: false
      add :byte_end, :integer, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:chunks, [:urn])
    create index(:chunks, [:text_id, :first_ordinal])
  end
end
