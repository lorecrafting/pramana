defmodule Pramana.Reviewer.Account do
  @moduledoc "Individual, operator-provisioned source reviewer identity."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "reviewer_accounts" do
    field :login_id, :string
    field :display_name, :string
    field :credential_digest, :string
    field :active, :boolean, default: true
    field :session_epoch, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:login_id, :display_name, :credential_digest])
    |> validate_required([:login_id, :display_name, :credential_digest])
    |> validate_format(:login_id, ~r/\A[a-z0-9._@-]+\z/)
    |> validate_length(:login_id, max: 254)
    |> validate_length(:display_name, min: 1, max: 100)
    |> unique_constraint(:login_id)
    |> check_constraint(:credential_digest, name: :reviewer_accounts_credential_digest)
  end
end
