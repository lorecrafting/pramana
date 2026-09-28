defmodule Pramana.Repo.Migrations.CreateReviewerAccountsAndGrants do
  use Ecto.Migration

  def change do
    create table(:reviewer_accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :login_id, :text, null: false
      add :display_name, :text, null: false
      add :credential_digest, :text, null: false
      add :active, :boolean, null: false, default: true
      add :session_epoch, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reviewer_accounts, [:login_id])

    create constraint(:reviewer_accounts, :reviewer_accounts_credential_digest,
             check: "credential_digest ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_accounts, :reviewer_accounts_session_epoch,
             check: "session_epoch >= 0"
           )

    create table(:reviewer_grants, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :account_id, references(:reviewer_accounts, type: :binary_id, on_delete: :restrict),
        null: false

      add :scope_sha256, :text, null: false
      add :capability, :text, null: false
      add :granted_by, :text, null: false
      add :revoked_at, :utc_datetime_usec
      add :revoked_by, :text

      timestamps(type: :utc_datetime_usec)
    end

    create index(:reviewer_grants, [:account_id])

    create unique_index(:reviewer_grants, [:account_id, :scope_sha256, :capability],
             where: "revoked_at IS NULL",
             name: :reviewer_grants_active_unique
           )

    create constraint(:reviewer_grants, :reviewer_grants_scope_sha256,
             check: "scope_sha256 ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:reviewer_grants, :reviewer_grants_capability,
             check: "capability = 'relation_review'"
           )
  end
end
