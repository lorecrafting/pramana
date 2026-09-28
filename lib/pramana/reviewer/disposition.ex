defmodule Pramana.Reviewer.Disposition do
  @moduledoc "An operator's append-only disposition of one exact reviewed assertion."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @choices ~w(supported disputed unresolved)

  schema "reviewer_dispositions" do
    field :assertion_id, :integer
    field :scope_sha256, :string
    field :release_id, :string
    field :assertion_fingerprint, :string
    field :assertion_snapshot, :map
    field :disposition, :string
    field :rationale, :string
    field :source_references, :string
    field :operator_id, :string
    field :inserted_at, :utc_datetime_usec
  end

  def changeset(disposition, attrs) do
    disposition
    |> cast(attrs, [:disposition, :rationale, :source_references, :operator_id])
    |> validate_required([:disposition, :rationale, :source_references, :operator_id])
    |> validate_inclusion(:disposition, @choices)
    |> validate_length(:rationale, min: 1, max: 2000)
    |> validate_length(:source_references, min: 1, max: 2000)
    |> validate_length(:operator_id, min: 1, max: 100)
    |> foreign_key_constraint(:assertion_id)
  end
end
