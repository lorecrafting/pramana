defmodule Pramana.ReleaseSelectionMigrationTest do
  @moduledoc "Upgrade DML uses the actual migration SQL; normal CI migrations exercise its DDL."
  use Pramana.DataCase, async: true

  alias Pramana.Corpus.Release, as: ReleaseSchema
  alias Pramana.Release
  alias Pramana.Release.Selection
  alias Pramana.Repo.Migrations.SelectCurrentRelease

  unless Code.ensure_loaded?(SelectCurrentRelease) do
    migration =
      Path.wildcard(
        Path.expand("../../priv/repo/migrations/*_select_current_release.exs", __DIR__)
      )
      |> List.first()

    Code.require_file(migration)
  end

  test "the upgrade selects the latest legacy row once and preserves both records" do
    a = old_release!("a", ~U[2026-01-01 00:00:00.000000Z])
    b = old_release!("b", ~U[2026-01-02 00:00:00.000000Z])
    assert Release.current() == nil
    assert %{num_rows: 1} = Repo.query!(SelectCurrentRelease.backfill_sql())
    assert Release.current() == b
    assert Repo.get!(ReleaseSchema, a.id) == a
    assert Repo.get!(ReleaseSchema, b.id) == b
    assert Repo.get!(Selection, 1).selected_at == b.stamped_at
  end

  test "a legacy timestamp tie has a deterministic identity tie-breaker" do
    timestamp = ~U[2026-01-01 00:00:00.000000Z]
    a = old_release!("a", timestamp)
    b = old_release!("b", timestamp)
    assert a.id < b.id
    Repo.query!(SelectCurrentRelease.backfill_sql())
    assert Release.current() == b
  end

  test "a database with no legacy releases stays explicitly unstamped" do
    assert %{num_rows: 0} = Repo.query!(SelectCurrentRelease.backfill_sql())
    assert Release.current_id() == nil
    assert Repo.aggregate(Selection, :count) == 0
  end

  defp old_release!(digit, timestamp) do
    Repo.insert!(%ReleaseSchema{
      release_id: String.duplicate(digit, 64),
      translation_set_id: "translations",
      vector_set_id: "vectors",
      translations_count: 0,
      vectors_count: 0,
      translators: [],
      embedding_models: [],
      stamped_at: timestamp
    })
  end
end
