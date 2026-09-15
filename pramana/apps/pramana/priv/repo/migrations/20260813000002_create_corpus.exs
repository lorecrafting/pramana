defmodule Pramana.Repo.Migrations.CreateCorpus do
  use Ecto.Migration

  @moduledoc """
  Core corpus schema. See docs/ARCHITECTURE.md — "The provenance model".

  Provenance is deliberately several orthogonal columns on `works`, never a single
  `source` string. That is what makes the Taisho vols 56-84 rule (Japanese-composed
  commentary) and the apocrypha rule expressible as plain SQL predicates.
  """

  def change do
    # ---- Sources: the pinned upstream snapshots recorded in sources.lock.json ----
    create table(:sources, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :upstream_url, :string
      add :pin_type, :string, null: false, default: "git"
      add :pin_ref, :string
      add :retrieved_at, :utc_datetime_usec
      add :files_sha256, :string
      add :file_count, :integer

      # License gating. `license_class` drives redistribution decisions, so it is a
      # column and not free text. See docs/SOURCES.md.
      add :license_spdx, :string
      add :license_class, :string, null: false, default: "unknown"
      add :commercial_use, :boolean, null: false, default: false
      add :redistributable, :boolean, null: false, default: false

      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:sources, :license_class_known,
             check: "license_class IN ('cc0','cc-by','cc-by-sa','nc','restricted','unknown')"
           )

    # ---- Witnesses: a physical or printed edition ----
    create table(:witnesses, primary_key: false) do
      add :id, :string, primary_key: true
      add :name, :string, null: false
      add :description, :text
      timestamps(type: :utc_datetime_usec)
    end

    # ---- Works: the abstract text (FRBR work), carrying the provenance axes ----
    create table(:works, primary_key: false) do
      add :id, :string, primary_key: true
      add :title, :string
      add :title_original, :string

      # The provenance axes.
      add :composition_origin, :string
      add :text_role, :string
      add :attributed_author, :string
      add :attribution_confidence, :string
      add :date_start, :integer
      add :date_end, :integer

      add :meta, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end

    create constraint(:works, :composition_origin_known,
             check:
               "composition_origin IS NULL OR composition_origin IN " <>
                 "('indic','chinese','japanese','tibetan','korean','other')"
           )

    create constraint(:works, :text_role_known,
             check:
               "text_role IS NULL OR text_role IN " <>
                 "('root','translation','commentary','subcommentary','apocryphon','conflation')"
           )

    create index(:works, [:composition_origin])
    create index(:works, [:text_role])

    # ---- Texts: a work as it appears in one witness, from one source ----
    create table(:texts) do
      add :work_id, references(:works, type: :string, on_delete: :delete_all), null: false
      add :witness_id, references(:witnesses, type: :string, on_delete: :restrict), null: false
      add :source_id, references(:sources, type: :string, on_delete: :restrict), null: false

      add :urn_prefix, :string, null: false
      add :volume, :string
      add :body, :text
      add :body_sha256, :string
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:texts, [:work_id, :witness_id, :source_id])
    create index(:texts, [:source_id])

    # ---- Segments: the citable atom. Edition-anchored, never chunker-derived. ----
    create table(:segments) do
      add :text_id, references(:texts, on_delete: :delete_all), null: false

      # The full URN, e.g. pramana:cbeta.T:T0262_009@p0037a13
      add :urn, :string, null: false

      # Parsed anchor components, kept as columns so citation-shaped queries
      # ("everything on page 37a") are indexable.
      add :juan, :integer
      add :page, :string
      add :register, :string
      add :line, :integer

      add :ordinal, :integer, null: false
      add :kind, :string, null: false, default: "prose"

      add :content, :text, null: false
      add :content_sha256, :string, null: false

      # Offsets into texts.body — required by the decoupling contract so every
      # returned span is independently re-resolvable. See docs/ARCHITECTURE.md.
      add :char_start, :integer, null: false
      add :char_end, :integer, null: false

      # Gaiji refs, editorial-punctuation flags, <app> variant apparatus.
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:segments, [:urn])
    create index(:segments, [:text_id, :ordinal])
    create index(:segments, [:text_id, :juan])

    # ---- Bakes: bake_id = sha256(sources.lock + pipeline_version + config) ----
    create table(:bakes, primary_key: false) do
      add :id, :string, primary_key: true
      add :pipeline_version, :string, null: false
      add :sources_lock_sha256, :string, null: false
      add :config, :map, null: false, default: %{}
      add :built_at, :utc_datetime_usec
      add :stats, :map, null: false, default: %{}
      timestamps(type: :utc_datetime_usec)
    end
  end
end
