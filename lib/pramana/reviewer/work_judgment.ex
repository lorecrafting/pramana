defmodule Pramana.Reviewer.WorkJudgment do
  @moduledoc "An attributed, append-only source-work recommendation for one exact pilot scope."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "reviewer_work_judgments" do
    field :account_id, Ecto.UUID
    field :grant_id, Ecto.UUID
    field :work_id, :string
    field :scope_sha256, :string
    field :release_id, :string
    field :work_fingerprint, :string
    field :work_snapshot, :map
    field :judgment, :string
    field :rationale, :string
    field :source_references, :string
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(judgment, attrs) do
    judgment
    |> cast(attrs, [:judgment, :rationale, :source_references])
    |> validate_required([:judgment, :rationale, :source_references])
    |> validate_inclusion(:judgment, ~w(accept needs_review exclude))
    |> validate_length(:rationale, min: 1, max: 2000)
    |> validate_length(:source_references, min: 1, max: 2000)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:grant_id)
    |> foreign_key_constraint(:work_id)
  end
end
