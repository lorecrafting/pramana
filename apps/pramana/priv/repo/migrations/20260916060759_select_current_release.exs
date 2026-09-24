defmodule Pramana.Repo.Migrations.SelectCurrentRelease do
  use Ecto.Migration

  def up do
    create table(:release_selection, primary_key: false) do
      add(:id, :integer, primary_key: true)
      add(:release_id, references(:releases, on_delete: :delete_all), null: false)
      add(:selected_at, :utc_datetime_usec, null: false)
    end

    create(constraint(:release_selection, :release_selection_singleton, check: "id = 1"))

    # Preserve the selection the old reader would have made when upgrading an
    # existing database. From here onward selection never depends on stamp order.
    execute(backfill_sql())
  end

  @doc false
  def backfill_sql do
    """
    INSERT INTO release_selection (id, release_id, selected_at)
    SELECT 1, id, stamped_at FROM releases
    ORDER BY stamped_at DESC, id DESC LIMIT 1
    """
  end

  def down do
    drop(table(:release_selection))
  end
end
