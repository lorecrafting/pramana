defmodule Pramana.Reviewer.Judgment do
  @moduledoc "An attributed, append-only source-review observation; never a corpus decision."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @judgments ~w(supported disputed cannot_determine)

  schema "reviewer_judgments" do
    field :account_id, Ecto.UUID
    field :grant_id, Ecto.UUID
    field :assertion_id, :integer
    field :scope_sha256, :string
    field :release_id, :string
    field :assertion_fingerprint, :string
    field :judgment, :string
    field :rationale, :string
    field :source_references, :string

    field :inserted_at, :utc_datetime_usec
  end

  def changeset(judgment, attrs) do
    judgment
    |> cast(attrs, [:judgment, :rationale, :source_references])
    |> validate_required([:judgment, :rationale, :source_references])
    |> validate_inclusion(:judgment, @judgments)
    |> validate_length(:rationale, min: 1, max: 2000)
    |> validate_length(:source_references, min: 1, max: 2000)
    |> foreign_key_constraint(:account_id)
    |> foreign_key_constraint(:grant_id)
    |> foreign_key_constraint(:assertion_id)
  end
end
