defmodule Pramana.Repo.Migrations.CreateReviewerJudgments do
  use Ecto.Migration

  def change do
    create table(:reviewer_judgments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:reviewer_accounts, type: :binary_id, on_delete: :restrict),
        null: false

      add :grant_id, references(:reviewer_grants, type: :binary_id, on_delete: :restrict),
        null: false

      add :assertion_id, references(:work_relations, on_delete: :restrict), null: false
      add :scope_sha256, :text, null: false
      add :release_id, :text, null: false
      add :assertion_fingerprint, :text, null: false
      add :judgment, :text, null: false
      add :rationale, :text, null: false
      add :source_references, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reviewer_judgments, [:assertion_id, :inserted_at])
    create index(:reviewer_judgments, [:account_id, :inserted_at])

    create constraint(:reviewer_judgments, :reviewer_judgments_scope_sha256,
             check: "scope_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_judgments, :reviewer_judgments_assertion_fingerprint,
             check: "assertion_fingerprint ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_judgments, :reviewer_judgments_judgment,
             check: "judgment IN ('supported', 'disputed', 'cannot_determine')"
           )

    create constraint(:reviewer_judgments, :reviewer_judgments_rationale,
             check: "length(trim(rationale)) BETWEEN 1 AND 2000"
           )

    create constraint(:reviewer_judgments, :reviewer_judgments_source_references,
             check: "length(trim(source_references)) BETWEEN 1 AND 2000"
           )
  end
end
