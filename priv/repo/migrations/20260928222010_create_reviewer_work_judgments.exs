defmodule Pramana.Repo.Migrations.CreateReviewerWorkJudgments do
  use Ecto.Migration

  def change do
    create table(:reviewer_work_judgments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :grant_id, references(:reviewer_grants, type: :binary_id, on_delete: :restrict),
        null: false

      add :work_id, references(:works, type: :string, on_delete: :restrict), null: false
      add :scope_sha256, :text, null: false
      add :release_id, :text, null: false
      add :work_fingerprint, :text, null: false
      add :judgment, :text, null: false
      add :rationale, :text, null: false
      add :source_references, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reviewer_work_judgments, [:account_id, :scope_sha256, :work_id])

    create constraint(:reviewer_work_judgments, :reviewer_work_judgments_scope_sha256,
             check: "scope_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_work_judgments, :reviewer_work_judgments_work_fingerprint,
             check: "work_fingerprint ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_work_judgments, :reviewer_work_judgments_judgment,
             check: "judgment IN ('accept', 'needs_review', 'exclude')"
           )

    create constraint(:reviewer_work_judgments, :reviewer_work_judgments_rationale,
             check: "length(trim(rationale)) BETWEEN 1 AND 2000"
           )

    create constraint(:reviewer_work_judgments, :reviewer_work_judgments_source_references,
             check: "length(trim(source_references)) BETWEEN 1 AND 2000"
           )
  end
end
