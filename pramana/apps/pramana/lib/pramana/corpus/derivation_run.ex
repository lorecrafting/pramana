defmodule Pramana.Corpus.DerivationRun do
  @moduledoc """
  Immutable evidence that one deterministic derived-data command ran over a named scope.

  `status: "complete"` means the command finished without reported failures, its input
  digest matched its start checkpoint again, and its observed output cardinality matched
  the producer's declared expectation. It does not mean the resulting scholarly relation is correct.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "derivation_runs" do
    field :derivation, :string
    field :status, :string
    field :source_bake_id, :string
    field :implementation_version, :string
    field :scope, :map, default: %{}
    field :parameters, :map, default: %{}
    field :input_digest, :string
    field :output_digest, :string
    field :stats, :map, default: %{}
    field :started_at, :utc_datetime_usec
    field :completed_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields ~w(
    derivation
    status
    source_bake_id
    implementation_version
    scope
    parameters
    input_digest
    output_digest
    stats
    started_at
    completed_at
  )a

  @doc false
  def changeset(run, attrs) do
    run
    |> cast(attrs, @fields)
    |> validate_required(@fields -- [:source_bake_id])
    |> check_constraint(:derivation, name: :derivation_runs_kind_known)
    |> check_constraint(:status, name: :derivation_runs_status_known)
    |> check_constraint(:input_digest, name: :derivation_runs_input_digest_shape)
    |> check_constraint(:output_digest, name: :derivation_runs_output_digest_shape)
  end
end
