defmodule Pramana.Reviewer.RightsJudgment do
  @moduledoc "An attributed rights assessment for one exact resource and operation group."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "reviewer_rights_judgments" do
    field :account_id, Ecto.UUID
    field :grant_id, Ecto.UUID
    field :scope_sha256, :string
    field :release_id, :string
    field :item_id, :string
    field :item_fingerprint, :string
    field :policy_snapshot, :map
    field :decision, :string
    field :rationale, :string
    field :evidence_references, :string
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(judgment, attrs) do
    judgment
    |> cast(attrs, [:decision, :rationale, :evidence_references])
    |> validate_required([:decision, :rationale, :evidence_references])
    |> validate_inclusion(:decision, ~w(permitted prohibited permission_required unresolved))
    |> validate_length(:rationale, min: 1, max: 2000)
    |> validate_length(:evidence_references, min: 1, max: 2000)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:grant_id)
  end
end
