defmodule Pramana.Repo.Migrations.CreateReviewerRightsJudgments do
  use Ecto.Migration

  def up do
    drop constraint(:reviewer_grants, :reviewer_grants_capability)

    create constraint(:reviewer_grants, :reviewer_grants_capability,
             check: "capability IN ('relation_review', 'rights_signoff')"
           )

    create table(:reviewer_rights_judgments, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:users, type: :binary_id, on_delete: :restrict), null: false

      add :grant_id, references(:reviewer_grants, type: :binary_id, on_delete: :restrict),
        null: false

      add :scope_sha256, :text, null: false
      add :release_id, :text, null: false
      add :item_id, :text, null: false
      add :item_fingerprint, :text, null: false
      add :policy_snapshot, :map, null: false
      add :decision, :text, null: false
      add :rationale, :text, null: false
      add :evidence_references, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reviewer_rights_judgments, [:account_id, :scope_sha256, :item_id])

    create constraint(:reviewer_rights_judgments, :reviewer_rights_judgments_scope_sha256,
             check: "scope_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_rights_judgments, :reviewer_rights_judgments_item_fingerprint,
             check: "item_fingerprint ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_rights_judgments, :reviewer_rights_judgments_decision,
             check: "decision IN ('permitted', 'prohibited', 'permission_required', 'unresolved')"
           )

    create constraint(:reviewer_rights_judgments, :reviewer_rights_judgments_rationale,
             check: "length(trim(rationale)) BETWEEN 1 AND 2000"
           )

    create constraint(:reviewer_rights_judgments, :reviewer_rights_judgments_evidence_references,
             check: "length(trim(evidence_references)) BETWEEN 1 AND 2000"
           )
  end

  def down do
    drop table(:reviewer_rights_judgments)
    drop constraint(:reviewer_grants, :reviewer_grants_capability)

    create constraint(:reviewer_grants, :reviewer_grants_capability,
             check: "capability = 'relation_review'"
           )
  end
end
