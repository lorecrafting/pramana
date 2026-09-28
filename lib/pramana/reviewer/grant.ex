defmodule Pramana.Reviewer.Grant do
  @moduledoc "Explicit authority for source review or rights signoff in one exact pilot scope."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "reviewer_grants" do
    field :account_id, Ecto.UUID
    field :scope_sha256, :string
    field :capability, :string, default: "relation_review"
    field :granted_by, :string
    field :revoked_at, :utc_datetime_usec
    field :revoked_by, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(grant, attrs) do
    grant
    |> cast(attrs, [:account_id, :scope_sha256, :granted_by])
    |> validate_required([:account_id, :scope_sha256, :granted_by])
    |> validate_inclusion(:capability, ~w(relation_review rights_signoff))
    |> validate_format(:scope_sha256, ~r/\A[0-9a-f]{64}\z/)
    |> validate_length(:granted_by, min: 1, max: 100)
    |> foreign_key_constraint(:account_id)
    |> unique_constraint([:account_id, :scope_sha256, :capability],
      name: :reviewer_grants_active_unique
    )
  end
end
