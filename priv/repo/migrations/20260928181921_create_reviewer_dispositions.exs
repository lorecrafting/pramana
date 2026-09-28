defmodule Pramana.Repo.Migrations.CreateReviewerDispositions do
  use Ecto.Migration

  def change do
    create table(:reviewer_dispositions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :assertion_id, references(:work_relations, on_delete: :restrict), null: false
      add :scope_sha256, :text, null: false
      add :release_id, :text, null: false
      add :assertion_fingerprint, :text, null: false
      add :assertion_snapshot, :map, null: false
      add :disposition, :text, null: false
      add :rationale, :text, null: false
      add :source_references, :text, null: false
      add :operator_id, :text, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:reviewer_dispositions, [:assertion_id, :inserted_at])
    create index(:reviewer_dispositions, [:scope_sha256, :disposition])

    create constraint(:reviewer_dispositions, :reviewer_dispositions_scope_sha256,
             check: "scope_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_dispositions, :reviewer_dispositions_assertion_fingerprint,
             check: "assertion_fingerprint ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_dispositions, :reviewer_dispositions_disposition,
             check: "disposition IN ('supported', 'disputed', 'unresolved')"
           )

    create constraint(:reviewer_dispositions, :reviewer_dispositions_rationale,
             check: "length(trim(rationale)) BETWEEN 1 AND 2000"
           )

    create constraint(:reviewer_dispositions, :reviewer_dispositions_source_references,
             check: "length(trim(source_references)) BETWEEN 1 AND 2000"
           )

    create constraint(:reviewer_dispositions, :reviewer_dispositions_operator_id,
             check: "length(trim(operator_id)) BETWEEN 1 AND 100"
           )
  end
end
