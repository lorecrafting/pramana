defmodule Pramana.Repo.Migrations.CreateUsersAuthTables do
  use Ecto.Migration

  def up do
    execute "CREATE EXTENSION IF NOT EXISTS citext"

    # Existing reviewer IDs are referenced by grants and judgments. Preserve the table
    # and its foreign keys, but require an explicit data migration for deployed accounts.
    execute """
    DO $$ BEGIN
      IF EXISTS (SELECT 1 FROM reviewer_accounts) THEN
        RAISE EXCEPTION 'reviewer_accounts contains rows; migrate identities before enabling Phoenix auth';
      END IF;
    END $$
    """

    drop unique_index(:reviewer_accounts, [:login_id])
    drop constraint(:reviewer_accounts, :reviewer_accounts_credential_digest)
    drop constraint(:reviewer_accounts, :reviewer_accounts_session_epoch)
    rename table(:reviewer_accounts), to: table(:users)

    alter table(:users) do
      remove :login_id
      remove :display_name
      remove :credential_digest
      remove :active
      remove :session_epoch
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :naive_datetime
    end

    create unique_index(:users, [:email])

    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :naive_datetime

      timestamps(updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])
  end
end
