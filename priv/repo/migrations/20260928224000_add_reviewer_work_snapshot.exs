defmodule Pramana.Repo.Migrations.AddReviewerWorkSnapshot do
  use Ecto.Migration

  def change do
    alter table(:reviewer_work_judgments) do
      add :work_snapshot, :map, null: false, default: %{}
    end
  end
end
