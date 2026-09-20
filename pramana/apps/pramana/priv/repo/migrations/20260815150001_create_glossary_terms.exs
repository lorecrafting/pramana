defmodule Pramana.Repo.Migrations.CreateGlossaryTerms do
  use Ecto.Migration

  @moduledoc """
  Pinned term renderings — the seed for glossary-pinned translation (#26) and the
  reading-exception dictionary (#24).

  Imported from a mature hand-built translation project, which independently arrived at
  several disciplines this project designed separately. The Notes column is kept
  verbatim because the *reasoning* is the valuable part: "Japanese. **Not** 'Daoyin' —
  swept 2026-08-06" records a decision, its scope, and when it was applied.
  """

  def change do
    create table(:glossary_terms) do
      # Which corpus source this glossary belongs to. Licence gating follows the source,
      # so a glossary derived from a restricted text inherits that restriction.
      add :source_id, references(:sources, type: :string, on_delete: :delete_all), null: false

      add :term, :string, null: false
      add :pinyin, :string
      add :canonical_english, :text, null: false

      # Verbatim. Carries the reasoning, the date a decision was swept, and the
      # cross-references — losing it would leave a bare mapping with no way to tell a
      # considered choice from an arbitrary one.
      add :notes, :text

      # The section heading it appeared under ("People", "Core doctrinal terms").
      add :category, :string

      # Renderings the glossary explicitly REJECTS, marked `**Not** "X"`. Kept because a
      # decision recorded is not a decision applied: knowing which form is wrong is what
      # lets a checker find the places still using it.
      add :rejected_forms, {:array, :string}, null: false, default: []

      # THE POINT OF MODELLING THIS EXPLICITLY: a reading that could not be verified must
      # be representable, not silently absent. 日溪 is Japanese, but the source project
      # could not confirm the reading, so it kept pinyin and said so rather than
      # inventing "Nikkei". Same discipline as returning nil from
      # `URN.Taisho.provenance_for_volume/1` — refuse to guess, and record the refusal.
      add :reading_status, :string, null: false, default: "not_applicable"

      # Which reading tradition the name belongs to. A Japanese monk takes a Japanese
      # reading, a Silla monk a Korean one; getting this wrong is how 元曉 becomes
      # "Yuanxiao" instead of "Wŏnhyo".
      add :language_origin, :string

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:glossary_terms, [:source_id, :term])
    create index(:glossary_terms, [:reading_status])
    create index(:glossary_terms, [:language_origin])

    create constraint(:glossary_terms, :glossary_reading_status_known,
             check: "reading_status IN ('verified','unverified','not_applicable')"
           )

    create constraint(:glossary_terms, :glossary_language_origin_known,
             check: """
             language_origin IS NULL OR
             language_origin IN ('chinese','japanese','korean','sanskrit','pali','tibetan')
             """
           )
  end
end
