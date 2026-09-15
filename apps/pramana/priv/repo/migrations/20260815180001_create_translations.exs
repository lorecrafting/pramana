defmodule Pramana.Repo.Migrations.CreateTranslations do
  @moduledoc """
  The translation pool and the reading-exception table (`docs/LAYERS.md`,
  `docs/TRANSLATION.md`).

  Two shapes that must exist before content does, because retrofitting either means a
  migration across the whole corpus.

  ## The pool

  There is no "the English translation" here. The Chinese canon holds 2–6 translations
  of the same Sanskrit work; SuttaCentral carries Sujato, Brahmali, Patton and others on
  the same suttas. Multiplicity is the normal condition of the field, not a defect
  introduced by machines — so a human translator and a model are **the same kind of row**,
  differing only in metadata. That is what lets the Phase 7 translation engine reuse this
  table rather than growing a parallel one.

  ## `anchor_urn` is a plain FK-by-value to a segment URN

  A translation is a **layer over a source anchor**, never a document. It has no
  top-level URN of its own; it is addressed as `<segment urn>#tr:<lang>/<translator>`.
  Making the anchor a column rather than the primary key is what keeps a rendering
  structurally incapable of being cited as a source (`CLAUDE.md` invariant #7).

  ## Tier is not the same question as method

  `method` says who produced it (human / llm / hybrid). `tier` says what it costs to
  trust: T0 human, T1 baked with a pinned model+prompt+glossary, T2 ephemeral. They
  correlate but are not the same axis — a hybrid post-edited by a person is `method:
  hybrid, tier: t0`. Collapsing them would lose exactly the distinction a reader needs.

  The T2 candidate cache (`translation_candidates`) deliberately does **not** land here:
  it has a different lifecycle — append-only, outside the bake — and belongs with the
  generation engine in Phase 7. See `docs/TRANSLATION.md`.
  """

  use Ecto.Migration

  def change do
    create table(:translations) do
      # The source anchor this renders. Not a FK constraint: a translation pool can be
      # loaded for anchors from any source, and a rendering must not be able to delete
      # or lock a source segment. Indexed, and checked at ingest instead.
      add :anchor_urn, :string, null: false
      add :work_id, :string, null: false
      add :lang, :string, null: false

      # "sujato", or "model:claude-opus-5@prompt-v3+glossary-ddb2". One namespace on
      # purpose: selection policy asks the same question of both.
      add :translator_id, :string, null: false
      add :translator_name, :string
      add :tier, :string, null: false
      add :method, :string, null: false

      add :text, :text, null: false
      add :text_sha256, :string, null: false

      # Reproducibility for a generated rendering. Null for a human one, and that
      # asymmetry is the point: a model rendering that cannot name its model, prompt and
      # glossary cannot be reproduced and should not be promoted.
      add :model_id, :string
      add :prompt_version, :string
      add :glossary_id, :string
      add :bake_id, :string

      add :review_state, :string, null: false, default: "raw"
      add :glossary_compliance, :float
      add :consensus_score, :float
      add :confidence, :float

      # Licence lives on the publication, not the repository: bilara-data is CC0
      # throughout except one CC BY-SA 3.0 translation. A pool row therefore carries its
      # own licence rather than inheriting the source's.
      add :license_spdx, :string
      add :license_class, :string
      add :redistributable, :boolean, null: false, default: false
      add :attribution, :text

      add :source_file, :string
      add :meta, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    # One rendering per anchor per translator per language. A second run of the same
    # translator updates in place rather than silently doubling the pool.
    create unique_index(:translations, [:anchor_urn, :lang, :translator_id])
    create index(:translations, [:anchor_urn])
    create index(:translations, [:work_id, :lang])
    create index(:translations, [:translator_id])
    create index(:translations, [:lang, :tier])

    create constraint(:translations, :translation_tier_known, check: "tier IN ('t0','t1','t2')")

    create constraint(:translations, :translation_method_known,
             check: "method IN ('human','llm','hybrid')"
           )

    create constraint(:translations, :translation_review_state_known,
             check: "review_state IN ('raw','machine_verified','human_reviewed','approved')"
           )

    # A generated rendering must be reproducible. Enforced in the database because the
    # alternative — remembering to check at every write site — is how an unattributable
    # translation ends up in a pool that something later promotes.
    create constraint(:translations, :generated_translation_names_its_model,
             check: "method = 'human' OR model_id IS NOT NULL"
           )

    # Readings (pinyin, Wylie, on'yomi) are COMPUTED at render time from a dictionary,
    # never materialized per character — that would be billions of rows for derivable
    # data. Only the exceptions are stored, because a general library gets Buddhist
    # vocabulary confidently wrong: 般若 is bōrě, not bānruò.
    create table(:reading_exceptions) do
      add :form, :string, null: false
      add :lang, :string, null: false
      add :scheme, :string, null: false
      add :reading, :string
      add :note, :text

      # Whether anyone has actually confirmed this reading. `unverified` with a null
      # reading is a legitimate, useful row: it records that the ordinary reading is
      # wrong without inventing the right one — the same refuse-to-guess discipline as
      # `provenance_for_volume/1` returning nil.
      add :status, :string, null: false, default: "unverified"
      add :authority, :string
      add :source_id, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:reading_exceptions, [:form, :lang, :scheme])
    create index(:reading_exceptions, [:scheme, :status])

    create constraint(:reading_exceptions, :reading_status_known,
             check: "status IN ('verified','unverified','disputed')"
           )

    create constraint(:reading_exceptions, :verified_reading_has_a_reading,
             check: "status <> 'verified' OR reading IS NOT NULL"
           )
  end
end
