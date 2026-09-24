defmodule Pramana.Repo.Migrations.CreateReleases do
  @moduledoc """
  What actually answered a query, which `bake_id` stopped identifying.

  `Pramana.Bake` hashes acquired bytes, normalisation and bake config. It is the right
  identity for a **passage**: resolve a URN against the same `bake_id` and you get the same
  text, which is what makes a citation checkable years later.

  It is the wrong identity for a **retrieval**, and on 2026-09-03 that stopped being
  theoretical: **27,751 renderings and 27,751 vectors landed under an unchanged
  `bake_id`**. Two holders of one id can answer the same query differently.

  That mattered because the id was being asserted everywhere. `PramanaWeb.MCP.Reply`
  stamps it on every response of all nineteen tools and promised `{tool, arguments,
  bake_id}` was enough to reproduce an answer; the MCP guide told models to cite it for
  reproducibility; `verify_report` keys its replays on it, so a replay recorded before a
  translation import runs against the same id and a different index — and can fail, and
  blame the report.

  ## Three ids, because three things move independently

    * `source_bake_id` — the existing `bake_id`. Acquired bytes, normalisation, config.
    * `translation_set_id` — the English layer: how many renderings, by whom, at what tier.
    * `vector_set_id` — the index: how many vectors, of what kinds, from which model.
    * `release_id` — a digest of the three, and the only one that answers *what produced
      this answer*.

  ## A row rather than a computation

  These are stamped on every tool response, so they have to be readable in one indexed
  lookup. Counting 1,066,026 vectors per request is not that. A release is therefore
  **recorded** when something changes it, exactly as a bake is — and because a recorded
  fact can go stale where a computed one cannot, `Pramana.Release.drift/0` compares what
  was stamped against what is live, and `mix pramana.doctor` reports it. Drift is visible
  rather than silent, which is the whole point of the exercise.
  """
  use Ecto.Migration

  def change do
    create table(:releases) do
      add :release_id, :string, null: false
      add :source_bake_id, :string
      add :translation_set_id, :string, null: false
      add :vector_set_id, :string, null: false

      # The inputs the digests were taken over, kept so `drift/0` can say WHAT changed
      # rather than only that something did. A stamp that cannot explain itself sends the
      # next person to run the same queries by hand.
      add :translations_count, :integer, null: false
      add :vectors_count, :integer, null: false
      add :embedding_models, {:array, :string}, null: false, default: []
      add :translators, {:array, :string}, null: false, default: []

      add :stamped_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec)
    end

    create index(:releases, [:stamped_at])
    create unique_index(:releases, [:release_id])
  end
end
