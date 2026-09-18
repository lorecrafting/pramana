defmodule Pramana.Repo.Migrations.CreateDerivationRuns do
  use Ecto.Migration

  @moduledoc """
  Immutable receipts for deterministic derived-data runs.

  A row says a named derivation completed over an explicit scope and records the input and
  output digests it observed. It is evidence about one run, not a claim that the derived
  relation itself is scholarly truth.

  Receipts are append-only because changing "what completed" after the fact would destroy
  the evidence the table exists to preserve.
  """

  def up do
    create table(:derivation_runs) do
      add :derivation, :string, null: false
      add :status, :string, null: false
      add :source_bake_id, :string
      add :implementation_version, :string, null: false
      add :scope, :map, null: false, default: %{}
      add :parameters, :map, null: false, default: %{}
      add :input_digest, :string, null: false
      add :output_digest, :string, null: false
      add :stats, :map, null: false, default: %{}
      add :started_at, :utc_datetime_usec, null: false
      add :completed_at, :utc_datetime_usec, null: false
      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create constraint(:derivation_runs, :derivation_runs_kind_known,
             check:
               "derivation IN ('quotations_scan','relations_title','relations_shared_text','commentary_align')"
           )

    create constraint(:derivation_runs, :derivation_runs_status_known,
             check: "status IN ('complete','partial')"
           )

    create constraint(:derivation_runs, :derivation_runs_input_digest_shape,
             check: "input_digest ~ '^[0-9a-f]{64}$'"
           )

    create constraint(:derivation_runs, :derivation_runs_output_digest_shape,
             check: "output_digest ~ '^[0-9a-f]{64}$'"
           )

    create index(:derivation_runs, [:derivation, :source_bake_id, :completed_at])

    execute("""
    CREATE FUNCTION pramana_forbid_derivation_run_mutation()
    RETURNS trigger
    LANGUAGE plpgsql
    AS $$
    BEGIN
      RAISE EXCEPTION 'derivation_runs are append-only';
    END;
    $$;
    """)

    execute("""
    CREATE TRIGGER derivation_runs_append_only
    BEFORE UPDATE OR DELETE ON derivation_runs
    FOR EACH ROW
    EXECUTE FUNCTION pramana_forbid_derivation_run_mutation();
    """)
  end

  def down do
    execute("DROP TRIGGER IF EXISTS derivation_runs_append_only ON derivation_runs")
    execute("DROP FUNCTION IF EXISTS pramana_forbid_derivation_run_mutation()")
    drop table(:derivation_runs)
  end
end
