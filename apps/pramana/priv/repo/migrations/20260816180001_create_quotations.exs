defmodule Pramana.Repo.Migrations.CreateQuotations do
  @moduledoc """
  Verbatim text reuse between works — the quotation graph.

  Commentaries quote their root texts constantly, and the Chinese canon recycles stock
  passages across works compiled centuries apart. Finding those reuses is **entirely
  deterministic**: identical characters, or not. No model, no embedding, no threshold to
  argue about, which is why `CLAUDE.md` invariant #5 puts it ahead of any similarity
  method that could approximate it.

  ## Shaped like `text_parallels`, and for the same reason

  A match is stored as a **pair** with two ends, each resolved to a URN range, exactly as
  a curated parallel is. The two tables answer different questions — one is "scholars say
  these transmit the same discourse", the other is "these characters are identical" — and
  keeping the shapes alike means a caller reads both the same way while never confusing
  the claims.

  ## Why the text is stored, not just the offsets

  A quotation whose text lives only as a pair of offsets becomes unreadable the moment a
  re-bake shifts them, and unverifiable in the meantime. Storing the matched string plus
  its hash means a stale row is **detectable** rather than silently wrong — the same
  reasoning that puts `content_sha256` on every segment and every vector.
  """

  use Ecto.Migration

  def change do
    create table(:quotations) do
      add :text, :text, null: false
      add :text_sha256, :string, null: false
      add :length, :integer, null: false

      # Two ends, deliberately not named source and target: verbatim identity says
      # nothing about who quoted whom. Direction is a scholarly judgement about dates and
      # transmission, and the scan cannot make it.
      add :a_text_id, references(:texts, on_delete: :delete_all), null: false
      add :a_work_id, :string, null: false
      add :a_urn, :string, null: false
      add :a_char_start, :integer, null: false
      add :a_char_end, :integer, null: false

      add :b_text_id, references(:texts, on_delete: :delete_all), null: false
      add :b_work_id, :string, null: false
      add :b_urn, :string, null: false
      add :b_char_start, :integer, null: false
      add :b_char_end, :integer, null: false

      add :bake_id, :string
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # The same passage found twice is one fact. Offsets rather than text in the key
    # because two different reuses can share the same string.
    create unique_index(:quotations, [:a_text_id, :a_char_start, :b_text_id, :b_char_start])

    create index(:quotations, [:a_work_id])
    create index(:quotations, [:b_work_id])
    create index(:quotations, [:length])
    create index(:quotations, [:text_sha256])

    # A one-character "match" is not evidence of anything. The floor lives in the
    # database as well as in the scanner, so a future loader cannot quietly relax it.
    create constraint(:quotations, :quotation_is_long_enough, check: "length >= 10")

    # A work reusing its own words is a refrain, not a citation, and the two must not be
    # mixed in one graph.
    create constraint(:quotations, :quotation_spans_two_texts, check: "a_text_id <> b_text_id")
  end
end
